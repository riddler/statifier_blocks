defmodule StatifierBlocks.Compiler.Serializer do
  @moduledoc """
  Turns an `StatifierBlocks.Emission` tree into SCXML bytes (ADR-0004
  decision 6).

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
      hashed, and the provenance map (sb-qz0) is what a human reads it
      through;
    * one canonical empty-element form, `<name/>`, never `<name></name>`;
    * no XML declaration, since it carries no information this package uses
      and would be one more byte sequence to keep stable;
    * `&`, `<`, `>` escaped in text and attribute values, plus `"` in
      attribute values. Escaping `>` is not required by XML but is
      canonical, and canonical is what this module is for.
  """

  alias StatifierBlocks.Emission

  @doc """
  Serializes `emission` to SCXML bytes.

  Every child placeholder must already have been spliced out by the
  compiler; one that survives to here is a compiler bug, and this function
  raises `ArgumentError` on it rather than writing a hole into
  identity-bearing bytes. `StatifierBlocks.Compiler` never lets one reach
  this point - it reports an unspliced placeholder as an Emit finding - so
  the raise is an assertion, not an error path a caller handles.
  """
  @spec to_binary(Emission.t()) :: binary()
  def to_binary(%Emission{} = emission) do
    emission |> iodata() |> IO.iodata_to_binary()
  end

  @spec iodata(Emission.node_t()) :: iodata()
  defp iodata(%Emission{name: name, attributes: attributes, children: []}) do
    ["<", name, attrs(attributes), "/>"]
  end

  defp iodata(%Emission{name: name, attributes: attributes, children: children}) do
    ["<", name, attrs(attributes), ">", Enum.map(children, &iodata/1), "</", name, ">"]
  end

  defp iodata({:child, block_id}) do
    raise ArgumentError, "unspliced child placeholder for block #{inspect(block_id)}"
  end

  @spec attrs([{String.t(), String.t()}]) :: iodata()
  defp attrs(attributes) do
    Enum.map(attributes, fn {name, value} -> [" ", name, ~s(="), escape(value), ~s(")] end)
  end

  @spec escape(String.t()) :: String.t()
  defp escape(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace(~s("), "&quot;")
  end
end
