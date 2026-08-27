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

  alias StatifierBlocks.{Block, Document}

  @spec encode(Document.t()) :: iodata()
  def encode(%Document{} = document) do
    pairs = [
      {"id", document.id},
      {"revision", document.revision},
      {"root", document.root},
      {"schema_version", document.schema_version}
    ]

    pairs = maybe_put(pairs, "metadata", document.metadata)

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
