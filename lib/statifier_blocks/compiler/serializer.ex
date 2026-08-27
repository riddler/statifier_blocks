defmodule StatifierBlocks.Compiler.Serializer do
  @moduledoc """
  Turns an `StatifierBlocks.Emission` tree into SCXML bytes, and records
  where every one of them came from (ADR-0004 decisions 5 and 6).

  > #### This module is identity-bearing code {: .warning}
  >
  > `Statifier.Machine.Identity.of_source/2` hashes the SCXML **source
  > bytes** (st-ADR-0052), so indentation, attribute order and
  > empty-element spelling are all identity-bearing: a change here that
  > moves a single byte changes the chart identity of every document this
  > package compiles, and `Statifier.Machine.Identity.matches?/2` is what
  > st-ADR-0060's resume refuses on. Treat any edit to this module as a
  > compiler-version bump (decision 6's third determinism input), and see
  > `test/statifier_blocks/compiler/serializer_test.exs`, which enforces
  > the sensitivity rather than leaving it as prose.

  The rules, all of them fixed so that `{document, palette, compiler
  version}` determines the bytes:

    * attributes in sorted order (`StatifierBlocks.Emission.element/3` sorts
      them at construction);
    * **no incidental whitespace at all** - no indentation, no newlines, no
      space between elements. Generated SCXML is not read by hand; it is
      hashed, and the provenance map is what a human reads it through;
    * one canonical empty-element form, `<name/>`, never `<name></name>`;
    * no XML declaration, since it carries no information this package uses
      and would be one more byte sequence to keep stable;
    * `&`, `<`, `>` escaped in text and attribute values, plus `"` in
      attribute values. Escaping `>` is not required by XML but is
      canonical, and canonical is what this module is for.

  ## Why the spans are recorded here and nowhere else

  Decision 5 keys error routing on a **byte span over the generated
  SCXML**, because upstream findings carry a `%Statifier.Parser.Location{}`
  and no element reference at all. Only the code that writes the bytes
  knows where each element and each attribute value landed, so recording
  the spans is this module's job and cannot be a second pass over the
  output: re-deriving offsets by re-parsing would be a second
  implementation of the serializer that must agree with the first.
  Recording them costs one accumulator.

  `serialize/1` walks the tree once and returns both. It reads the
  resolved `owner` `StatifierBlocks.Compiler` stamped onto each element;
  an element with no owner contributes bytes and no span, which is a
  compiler bug rather than a supported mode - `compiler_test.exs` states
  the totality of the map as a property over the artifact.
  """

  alias StatifierBlocks.Compiler.StateId
  alias StatifierBlocks.{Emission, Provenance}

  @doc """
  Serializes `emission` to SCXML bytes and the provenance map over them.
  """
  @spec serialize(Emission.t()) :: {binary(), Provenance.t()}
  def serialize(%Emission{} = emission) do
    {iodata, _offset, spans, by_state_id} = write(emission, {[], 0, [], %{}})

    {IO.iodata_to_binary(Enum.reverse(iodata)),
     %Provenance{by_state_id: by_state_id, spans: Enum.reverse(spans)}}
  end

  @doc """
  Serializes `emission` to SCXML bytes, discarding the provenance map.

  Every child placeholder must already have been spliced out by the
  compiler; one that survives to here is a compiler bug, and this function
  raises `ArgumentError` on it rather than writing a hole into
  identity-bearing bytes. `StatifierBlocks.Compiler` never lets one reach
  this point - it reports an unspliced placeholder as an Emit finding - so
  the raise is an assertion, not an error path a caller handles.
  """
  @spec to_binary(Emission.t()) :: binary()
  def to_binary(%Emission{} = emission), do: emission |> serialize() |> elem(0)

  @typep acc ::
           {iodata(), non_neg_integer(), [{Provenance.span(), Provenance.owner()}],
            %{optional(String.t()) => Provenance.owner()}}

  @spec write(Emission.node_t(), acc()) :: acc()
  defp write(%Emission{} = emission, {_iodata, start, _spans, _states} = acc) do
    acc =
      acc
      |> put("<" <> emission.name)
      |> write_attributes(emission)
      |> write_body(emission)

    acc
    |> record_span(start, emission)
    |> record_state(emission)
  end

  defp write({:child, block_id}, _acc) do
    raise ArgumentError, "unspliced child placeholder for block #{inspect(block_id)}"
  end

  @spec write_attributes(acc(), Emission.t()) :: acc()
  defp write_attributes(acc, %Emission{attributes: attributes} = emission) do
    Enum.reduce(attributes, acc, fn {name, value}, acc ->
      escaped = escape(value)

      acc = put(acc, " " <> name <> ~s(="))
      value_start = offset(acc)

      acc
      |> put(escaped)
      |> record_attribute_span(value_start, emission, name)
      |> put(~s("))
    end)
  end

  @spec write_body(acc(), Emission.t()) :: acc()
  defp write_body(acc, %Emission{children: []}), do: put(acc, "/>")

  defp write_body(acc, %Emission{name: name, children: children}) do
    acc
    |> put(">")
    |> then(fn acc -> Enum.reduce(children, acc, &write/2) end)
    |> put("</" <> name <> ">")
  end

  # The element's own span: the whole of it, from `<` to the closing `>`.
  @spec record_span(acc(), non_neg_integer(), Emission.t()) :: acc()
  defp record_span({iodata, stop, spans, states}, start, %Emission{owner: owner}) do
    case owner do
      nil -> {iodata, stop, spans, states}
      owner -> {iodata, stop, [{{start, stop}, owner} | spans], states}
    end
  end

  # An attribute value's span, carrying the config key that value came from
  # when the block type named one. Strictly inside the element's own span,
  # which is what makes `Provenance.owner_at/2`'s innermost-wins rule pick
  # it (ADR-0004 decision 9's content findings).
  @spec record_attribute_span(acc(), non_neg_integer(), Emission.t(), String.t()) :: acc()
  defp record_attribute_span({iodata, stop, spans, states} = acc, start, emission, attribute) do
    with %{} = owner <- emission.owner,
         {^attribute, config_key} <- List.keyfind(emission.attribute_owners, attribute, 0) do
      {iodata, stop, [{{start, stop}, %{owner | config_key: config_key}} | spans], states}
    else
      _no_key -> acc
    end
  end

  # Decision 5's other key. Every generated state carries an id
  # (`StatifierBlocks.Compiler.StateId`'s totality), and an `id` this
  # package minted is exactly one `unstate_id/1` accepts - which is what
  # keeps an author's own `<data id>` out of this half of the map.
  @spec record_state(acc(), Emission.t()) :: acc()
  defp record_state({iodata, offset, spans, states} = acc, %Emission{owner: owner} = emission) do
    with %{} <- owner,
         {"id", id} <- List.keyfind(emission.attributes, "id", 0),
         {:ok, {_block_id, _role}} <- StateId.unstate_id(id) do
      {iodata, offset, spans, Map.put(states, id, owner)}
    else
      _not_a_generated_state -> acc
    end
  end

  @spec put(acc(), binary()) :: acc()
  defp put({iodata, offset, spans, states}, chunk) do
    {[chunk | iodata], offset + byte_size(chunk), spans, states}
  end

  @spec offset(acc()) :: non_neg_integer()
  defp offset({_iodata, offset, _spans, _states}), do: offset

  @spec escape(String.t()) :: String.t()
  defp escape(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace(~s("), "&quot;")
  end
end
