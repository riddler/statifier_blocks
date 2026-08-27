defmodule StatifierBlocks.Decode do
  @moduledoc false

  # ADR-0001 decision 9's registry-free structural decode. This module never
  # consults a block-type registry and never resolves `type` against
  # anything - an unknown type decodes successfully.
  #
  # Two kinds of check happen here, deliberately kept apart:
  #
  # - Checks only decode can make, because they concern *bytes that were
  #   never asked for* rather than the shape of a value that made it into a
  #   struct: whether the top-level term is JSON at all, whether it is an
  #   object carrying a "schema_version" key, and whether a block object
  #   carries a key the encoder would never have written. The last one is
  #   decision 2's "the document is the minimum that must round-trip" - a
  #   key silently dropped here would break `encode(decode(bytes)) == bytes`
  #   with no error to say so.
  # - Everything else - schema version, envelope field shapes, per-block
  #   field shapes, id uniqueness, the no-floats rule - is built as a
  #   `%Document{}`/`%Block{}` from the raw decoded values (defaulting only
  #   where ADR-0001 says a key is optional) and handed to
  #   `Validation.validate/1`, which already implements those checks in the
  #   right order. Duplicating them here would be a second place for the
  #   error vocabulary to drift from `Validation`'s.
  #
  # Never `struct/2` over decoded input, never `String.to_atom/1` or
  # `String.to_existing_atom/1` (decision 6). Every `%Block{}`/`%Document{}`
  # below is built by literal struct syntax on explicitly extracted keys, and
  # every map key read from decoded JSON is a literal string in this module's
  # source, never one derived from the input.

  alias StatifierBlocks.{Block, Document, Validation}

  @block_keys ~w(id type type_version config slots)

  @spec decode(binary()) :: {:ok, Document.t()} | {:error, Validation.error()}
  def decode(binary) when is_binary(binary) do
    with {:ok, term} <- decode_bytes(binary),
         {:ok, envelope} <- ensure_block_document(term),
         {:ok, root} <- decode_block(Map.get(envelope, "root")) do
      document = %Document{
        id: Map.get(envelope, "id"),
        revision: Map.get(envelope, "revision"),
        root: root,
        schema_version: Map.get(envelope, "schema_version"),
        metadata: Map.get(envelope, "metadata", %{})
      }

      case Validation.validate(document) do
        :ok -> {:ok, document}
        {:error, _reason} = error -> error
      end
    end
  end

  # --- Bytes -> a decodable term -------------------------------------------

  @spec decode_bytes(binary()) :: {:ok, term()} | {:error, :not_a_block_document}
  defp decode_bytes(binary) do
    case JSON.decode(binary) do
      {:ok, term} -> {:ok, term}
      {:error, _reason} -> {:error, :not_a_block_document}
    end
  end

  # The decoded top level must be a JSON object carrying "schema_version" -
  # anything else is not recognizable as a block document at all, distinct
  # from being a recognizable one that is wrong in a specific way.
  @spec ensure_block_document(term()) :: {:ok, map()} | {:error, :not_a_block_document}
  defp ensure_block_document(%{} = term) when not is_struct(term) do
    if Map.has_key?(term, "schema_version") do
      {:ok, term}
    else
      {:error, :not_a_block_document}
    end
  end

  defp ensure_block_document(_term), do: {:error, :not_a_block_document}

  # --- Blocks, recursively --------------------------------------------------

  # A term found where a block is expected. When it is not a JSON object at
  # all, it is passed through unchanged rather than raising: `Validation`
  # already has an arm for "not a `%Block{}`" (the envelope's `root`) and for
  # "not a block list" (a slot's children), so an unresolvable shape here
  # still produces a typed refusal instead of a crash.
  @spec decode_block(term()) :: {:ok, Block.t() | term()} | {:error, Validation.error()}
  defp decode_block(%{} = map) when not is_struct(map) do
    case Enum.find(Map.keys(map), &(&1 not in @block_keys)) do
      nil -> build_block(map)
      key -> {:error, {:malformed_block, reported_id(map), {:unexpected_key, key}}}
    end
  end

  defp decode_block(other), do: {:ok, other}

  @spec build_block(map()) :: {:ok, Block.t()} | {:error, Validation.error()}
  defp build_block(map) do
    with {:ok, slots} <- decode_slots(Map.get(map, "slots", %{})) do
      {:ok,
       %Block{
         id: Map.get(map, "id"),
         type: Map.get(map, "type"),
         type_version: Map.get(map, "type_version"),
         config: Map.get(map, "config", %{}),
         slots: slots
       }}
    end
  end

  # Not a non-empty UTF-8 string yet (that is `Validation`'s job) - just
  # enough to name the block an `{:unexpected_key, _}` error is about,
  # matching `Validation`'s own "`nil` when the id itself is untrustworthy"
  # convention.
  @spec reported_id(map()) :: Block.id() | nil
  defp reported_id(map) do
    case Map.get(map, "id") do
      id when is_binary(id) and id != "" -> if String.valid?(id), do: id, else: nil
      _other -> nil
    end
  end

  # --- Slots -----------------------------------------------------------------

  # `slots` is passed through unchanged when it is not a map at all -
  # `Validation`'s `check_slots_shape/2` already has the `:not_a_map` arm.
  @spec decode_slots(term()) ::
          {:ok, %{optional(String.t()) => term()} | term()} | {:error, Validation.error()}
  defp decode_slots(slots) when is_map(slots) and not is_struct(slots) do
    Enum.reduce_while(slots, {:ok, %{}}, fn {name, value}, {:ok, acc} ->
      case decode_slot_value(value) do
        {:ok, decoded} -> {:cont, {:ok, Map.put(acc, name, decoded)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp decode_slots(other), do: {:ok, other}

  # A slot's value must be a list to be decoded block-by-block. A non-list
  # value is passed through unchanged - `Validation`'s per-slot check already
  # has the `:not_a_block_list` arm for it.
  @spec decode_slot_value(term()) :: {:ok, [Block.t()] | term()} | {:error, Validation.error()}
  defp decode_slot_value(value) when is_list(value) do
    case Enum.reduce_while(value, {:ok, []}, &decode_slot_item/2) do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      {:error, _reason} = error -> error
    end
  end

  defp decode_slot_value(other), do: {:ok, other}

  @spec decode_slot_item(term(), {:ok, [Block.t()]}) ::
          {:cont, {:ok, [Block.t()]}} | {:halt, {:error, Validation.error()}}
  defp decode_slot_item(item, {:ok, acc}) do
    case decode_block(item) do
      {:ok, block} -> {:cont, {:ok, [block | acc]}}
      {:error, _reason} = error -> {:halt, error}
    end
  end
end
