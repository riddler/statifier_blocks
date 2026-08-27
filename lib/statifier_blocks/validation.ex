defmodule StatifierBlocks.Validation do
  @moduledoc false

  # ADR-0001's structural rules as one ordered, total, event-shaped check
  # over an in-memory document. This is the error vocabulary phase 4's
  # decoder reuses, which is why it lands before the encoder.
  #
  # Nothing here consults a block-type registry: `config` is opaque and
  # `type` is never resolved against anything (decision 9's registry-free
  # rule applies to validation as much as it does to decoding).
  #
  # This module does its own pre-order walk rather than calling
  # `Document.blocks/1`: that walk assumes a well-typed tree (it sorts and
  # flattens `slots` directly), so it is not safe to run ahead of the very
  # check that confirms `slots` is shaped as a map of block lists. Walking
  # and validating together means a block with a malformed `slots` is
  # reported instead of crashing the walk that would otherwise try to
  # recurse into it.

  alias StatifierBlocks.{Block, Document}

  @typedoc "ADR-0001's typespec block, defined once and reused by from_json/1."
  @type error ::
          :not_a_block_document
          | {:unsupported_schema_version, pos_integer()}
          | {:duplicate_block_id, Block.id()}
          | {:malformed_block, Block.id() | nil, term()}
          | {:malformed_envelope, term()}

  @typedoc "Decision 6's value-grammar rejection: a float, or an unrecognized term."
  @type json_problem :: {:float, [term()]} | {:not_json, term()}

  @doc """
  Checks `document` against ADR-0001's structural rules, in order:

  1. The envelope (`schema_version`, `id`, `revision`, `metadata`, `root`).
  2. Every block, pre-order (`id`, `type`, `type_version`, `config`,
     `slots`), slots visited in UTF-8-sorted name order - the same order
     `Document.blocks/1` uses for a well-formed tree.
  3. Id uniqueness across the whole tree.

  Never consults a block-type registry and never looks at what a `config`
  key means - only that the value grammar is canonical JSON.
  """
  @spec validate(Document.t()) :: :ok | {:error, error()}
  def validate(%Document{} = document) do
    with :ok <- validate_envelope(document),
         {:ok, blocks} <- validate_tree(document.root) do
      validate_unique_ids(blocks)
    end
  end

  # --- Envelope ----------------------------------------------------------

  @spec validate_envelope(Document.t()) :: :ok | {:error, error()}
  defp validate_envelope(%Document{} = document) do
    with :ok <- check_schema_version(document.schema_version),
         :ok <- check_document_id(document.id),
         :ok <- check_revision(document.revision),
         :ok <- check_metadata(document.metadata) do
      check_root(document.root)
    end
  end

  @spec check_schema_version(term()) :: :ok | {:error, error()}
  defp check_schema_version(1), do: :ok

  defp check_schema_version(version) when is_integer(version) and version > 0,
    do: {:error, {:unsupported_schema_version, version}}

  defp check_schema_version(version),
    do: {:error, {:malformed_envelope, {:schema_version, :not_a_pos_integer, version}}}

  @spec check_document_id(term()) :: :ok | {:error, error()}
  defp check_document_id(id) do
    if non_empty_utf8?(id) do
      :ok
    else
      {:error, {:malformed_envelope, {:id, :not_a_non_empty_string}}}
    end
  end

  @spec check_revision(term()) :: :ok | {:error, error()}
  defp check_revision(revision) do
    if is_integer(revision) and revision >= 0 do
      :ok
    else
      {:error, {:malformed_envelope, {:revision, :not_a_non_neg_integer}}}
    end
  end

  @spec check_metadata(term()) :: :ok | {:error, error()}
  defp check_metadata(metadata) do
    case canonical_json_object(metadata) do
      :ok -> :ok
      {:error, reason} -> {:error, {:malformed_envelope, {:metadata, reason}}}
    end
  end

  @spec check_root(term()) :: :ok | {:error, error()}
  defp check_root(%Block{}), do: :ok
  defp check_root(other), do: {:error, {:malformed_envelope, {:root, :not_a_block, other}}}

  # --- The pre-order walk, validating as it goes --------------------------

  # Returns the pre-order block list on success, so the caller can run the
  # id-uniqueness pass over it without a second walk.
  @spec validate_tree(Block.t()) :: {:ok, [Block.t()]} | {:error, error()}
  defp validate_tree(%Block{} = block) do
    # The id reported alongside a failure is `nil` when the block's own id
    # is the thing that is malformed - there is nothing trustworthy to name.
    reported_id = if non_empty_utf8?(block.id), do: block.id, else: nil

    with :ok <- check_block_id(reported_id, block.id),
         :ok <- check_type(reported_id, block.type),
         :ok <- check_type_version(reported_id, block.type_version),
         :ok <- check_config(reported_id, block.config),
         :ok <- check_slots_shape(reported_id, block.slots) do
      validate_slots(reported_id, block.slots, [block])
    end
  end

  @spec check_block_id(Block.id() | nil, term()) :: :ok | {:error, error()}
  defp check_block_id(reported_id, id) do
    if non_empty_utf8?(id) do
      :ok
    else
      {:error, {:malformed_block, reported_id, {:id, :not_a_non_empty_string}}}
    end
  end

  @spec check_type(Block.id() | nil, term()) :: :ok | {:error, error()}
  defp check_type(reported_id, type) do
    if non_empty_utf8?(type) do
      :ok
    else
      {:error, {:malformed_block, reported_id, {:type, :not_a_non_empty_string}}}
    end
  end

  @spec check_type_version(Block.id() | nil, term()) :: :ok | {:error, error()}
  defp check_type_version(reported_id, type_version) do
    if is_integer(type_version) and type_version > 0 do
      :ok
    else
      {:error, {:malformed_block, reported_id, {:type_version, :not_a_pos_integer}}}
    end
  end

  @spec check_config(Block.id() | nil, term()) :: :ok | {:error, error()}
  defp check_config(reported_id, config) do
    case canonical_json_object(config) do
      :ok -> :ok
      {:error, reason} -> {:error, {:malformed_block, reported_id, {:config, reason}}}
    end
  end

  # Confirms `slots` is at least a map before `validate_slots/3` iterates
  # it - iterating a non-map would raise rather than report.
  @spec check_slots_shape(Block.id() | nil, term()) :: :ok | {:error, error()}
  defp check_slots_shape(_reported_id, slots) when is_map(slots), do: :ok

  defp check_slots_shape(reported_id, slots),
    do: {:error, {:malformed_block, reported_id, {:slots, :not_a_map, slots}}}

  # `slots` is confirmed to be a map by the time this runs. Visits slot
  # names in UTF-8-sorted order, matching `Document.blocks/1`'s order for a
  # well-formed tree, and recurses into each child immediately (pre-order,
  # depth before breadth) rather than collecting siblings first.
  @spec validate_slots(Block.id() | nil, %{optional(term()) => term()}, [Block.t()]) ::
          {:ok, [Block.t()]} | {:error, error()}
  defp validate_slots(reported_id, slots, acc) do
    slots
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce_while({:ok, acc}, fn {slot_name, children}, {:ok, acc} ->
      case validate_slot(reported_id, slot_name, children, acc) do
        {:ok, _acc} = ok -> {:cont, ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  @spec validate_slot(Block.id() | nil, term(), term(), [Block.t()]) ::
          {:ok, [Block.t()]} | {:error, error()}
  defp validate_slot(reported_id, slot_name, children, acc) do
    cond do
      not non_empty_utf8?(slot_name) ->
        {:error, {:malformed_block, reported_id, {:slots, {:slot_name, slot_name}}}}

      not (is_list(children) and Enum.all?(children, &match?(%Block{}, &1))) ->
        {:error, {:malformed_block, reported_id, {:slots, {slot_name, :not_a_block_list}}}}

      true ->
        validate_children(children, acc)
    end
  end

  @spec validate_children([Block.t()], [Block.t()]) :: {:ok, [Block.t()]} | {:error, error()}
  defp validate_children(children, acc) do
    Enum.reduce_while(children, {:ok, acc}, fn child, {:ok, acc} ->
      case validate_tree(child) do
        {:ok, child_blocks} -> {:cont, {:ok, acc ++ child_blocks}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  # --- Id uniqueness -------------------------------------------------------

  @spec validate_unique_ids([Block.t()]) :: :ok | {:error, error()}
  defp validate_unique_ids(blocks) do
    blocks
    |> Enum.reduce_while(MapSet.new(), fn %Block{id: id}, seen ->
      if MapSet.member?(seen, id) do
        {:halt, {:error, {:duplicate_block_id, id}}}
      else
        {:cont, MapSet.put(seen, id)}
      end
    end)
    |> case do
      {:error, _reason} = error -> error
      %MapSet{} -> :ok
    end
  end

  # --- Canonical JSON value grammar (decision 6) ---------------------------

  # A top-level object check for `config`/`metadata`: must itself be a
  # (non-struct) map before its keys and values are walked.
  @spec canonical_json_object(term()) ::
          :ok | {:error, :not_a_canonical_json_object | json_problem()}
  defp canonical_json_object(value) when is_map(value) and not is_struct(value),
    do: canonical_json_check(value, [])

  defp canonical_json_object(_value), do: {:error, :not_a_canonical_json_object}

  # Recursive predicate deciding decision 6's value grammar: `nil`,
  # booleans, integers, UTF-8 binaries, lists of the same, and maps with
  # UTF-8-binary keys. Floats are rejected explicitly and by name
  # (`{:float, path}`) rather than falling into the generic `{:not_json, _}`
  # arm, so an author who trips the no-floats rule is told which rule they
  # hit. `path` accumulates the keys/indices walked so far, outermost first.
  @spec canonical_json_check(term(), [term()]) :: :ok | {:error, json_problem()}
  defp canonical_json_check(nil, _path), do: :ok
  defp canonical_json_check(value, _path) when is_boolean(value), do: :ok
  defp canonical_json_check(value, _path) when is_integer(value), do: :ok
  defp canonical_json_check(value, path) when is_float(value), do: {:error, {:float, path}}

  defp canonical_json_check(value, _path) when is_binary(value) do
    if String.valid?(value) do
      :ok
    else
      {:error, {:not_json, value}}
    end
  end

  defp canonical_json_check(value, path) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {item, index}, :ok ->
      case canonical_json_check(item, path ++ [index]) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp canonical_json_check(value, path) when is_map(value) and not is_struct(value) do
    Enum.reduce_while(value, :ok, fn {key, item}, :ok ->
      check_object_entry(key, item, path)
    end)
  end

  defp canonical_json_check(value, _path), do: {:error, {:not_json, value}}

  @spec check_object_entry(term(), term(), [term()]) ::
          {:cont, :ok} | {:halt, {:error, json_problem()}}
  defp check_object_entry(key, item, path) do
    if is_binary(key) and String.valid?(key) do
      case canonical_json_check(item, path ++ [key]) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    else
      {:halt, {:error, {:not_json, key}}}
    end
  end

  @spec non_empty_utf8?(term()) :: boolean()
  defp non_empty_utf8?(value) when is_binary(value) and value != "", do: String.valid?(value)
  defp non_empty_utf8?(_value), do: false
end
