defmodule StatifierBlocks.CanonicalJson do
  @moduledoc false

  # ADR-0001 decision 8's deterministic encoder: sorted object keys, no
  # insignificant whitespace, empty `slots`/`config`/`metadata` omitted
  # rather than encoded as `{}`/`[]`, and no floats. Two encodes of equal
  # documents are therefore byte-identical, which is what makes a SHA-256
  # over the result a usable document identity (`Document.content_hash/1`).
  #
  # Objects and arrays are framed here, sorted here. Only scalars go through
  # `JSON.encode!/1`, and only for its RFC-8259 string escaper:
  # `JSON.encode!/1` emits map keys in Erlang term order, which is not the
  # UTF-8 byte order decision 8 requires, so this module never hands it a
  # map or a list.
  #
  # This module assumes `document` has already passed `Validation.validate/1`
  # (`Document.to_json/1` is the boundary that enforces that) - it has no
  # float clause and no clause for a term outside decision 6's value
  # grammar, so either raises `FunctionClauseError` here rather than
  # producing bytes that only look canonical.
  #
  # `datamodel` (ADR-0001 decision 11) is in these bytes like every other
  # envelope key, and therefore in `Document.content_hash/1`: two documents
  # differing only in an entry's `description` hash differently even
  # though they compile to byte-identical SCXML (the non-reversibility
  # clause `StatifierBlocks.Compiler`'s moduledoc states, a second
  # instance of it).

  alias StatifierBlocks.{Block, Document}
  alias StatifierBlocks.Document.DatamodelEntry

  @spec encode(Document.t()) :: iodata()
  def encode(%Document{} = document) do
    pairs = [
      {"id", document.id},
      {"revision", document.revision},
      {"root", document.root},
      {"schema_version", document.schema_version}
    ]

    pairs = maybe_put(pairs, "metadata", document.metadata)
    pairs = maybe_put_list(pairs, "datamodel", document.datamodel)

    object(pairs)
  end

  # The same rules over a plain term rather than a document: sorted object
  # keys, no insignificant whitespace, no floats, nothing omitted. Used by
  # `StatifierBlocks.Provenance.to_json/1`, which ADR-0004 decision 5 binds
  # to decision 8's canonical rules without making it part of the document.
  @spec encode_term(term()) :: iodata()
  def encode_term(term), do: value(term)

  @spec value(term()) :: iodata()
  defp value(%Block{} = block) do
    pairs = [
      {"id", block.id},
      {"type", block.type},
      {"type_version", block.type_version}
    ]

    pairs = maybe_put(pairs, "config", block.config)
    pairs = maybe_put_slots(pairs, block.slots)

    object(pairs)
  end

  defp value(%DatamodelEntry{} = entry) do
    pairs = [{"id", entry.id}]
    pairs = maybe_put_scalar(pairs, "expr", entry.expr)
    pairs = maybe_put_scalar(pairs, "description", entry.description)

    object(pairs)
  end

  defp value(value) when is_map(value) and not is_struct(value) do
    object(Enum.into(value, []))
  end

  defp value(value) when is_list(value) do
    inner = value |> Enum.map(&value/1) |> Enum.intersperse(?,)
    [?[, inner, ?]]
  end

  defp value(nil), do: JSON.encode!(nil)
  defp value(value) when is_boolean(value), do: JSON.encode!(value)
  defp value(value) when is_integer(value), do: JSON.encode!(value)
  defp value(value) when is_binary(value), do: JSON.encode!(value)

  # `slots` is a map keyed by slot name; a slot whose list is empty is
  # omitted entirely (decision 8), and a `slots` object left empty by that
  # omission is itself omitted rather than encoded as `{}`.
  @spec maybe_put_slots([{String.t(), term()}], %{optional(String.t()) => [Block.t()]}) ::
          [{String.t(), term()}]
  defp maybe_put_slots(pairs, slots) do
    non_empty =
      slots
      |> Enum.reject(fn {_name, children} -> children == [] end)
      |> Map.new()

    maybe_put(pairs, "slots", non_empty)
  end

  # `config` and `metadata` (and the derived `slots` map above) are omitted
  # entirely when empty, rather than encoded as `{}`.
  @spec maybe_put([{String.t(), term()}], String.t(), map()) :: [{String.t(), term()}]
  defp maybe_put(pairs, _key, value) when value == %{}, do: pairs
  defp maybe_put(pairs, key, value), do: [{key, value} | pairs]

  # `datamodel` (ADR-0001 decision 11) is the same "empty is omitted"
  # rule, over a list rather than a map: a document declaring no roots
  # gets no `datamodel` key at all, which is what keeps every document
  # encoded before decision 11 existed byte-identical. A sibling to
  # `maybe_put/3` rather than a widening of it, so a document's ordinary
  # map fields (`config`, `metadata`, `slots`) keep their existing guard
  # untouched.
  @spec maybe_put_list([{String.t(), term()}], String.t(), list()) :: [{String.t(), term()}]
  defp maybe_put_list(pairs, _key, []), do: pairs
  defp maybe_put_list(pairs, key, value) when is_list(value), do: [{key, value} | pairs]

  # `expr`/`description` on a `DatamodelEntry` are omitted when `nil`
  # rather than encoded as `null` - the same "absent means omitted" rule
  # `maybe_put/3` and `maybe_put_list/3` apply to their own fields.
  @spec maybe_put_scalar([{String.t(), term()}], String.t(), term()) :: [{String.t(), term()}]
  defp maybe_put_scalar(pairs, _key, nil), do: pairs
  defp maybe_put_scalar(pairs, key, value), do: [{key, value} | pairs]

  @spec object([{String.t(), term()}]) :: iodata()
  defp object(pairs) do
    inner =
      pairs
      # binaries compare byte-wise
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {k, v} -> [JSON.encode!(k), ?:, value(v)] end)
      |> Enum.intersperse(?,)

    [?{, inner, ?}]
  end
end
