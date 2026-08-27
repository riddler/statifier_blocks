defmodule StatifierBlocks.Document do
  @moduledoc """
  A block document: one tree, one envelope (ADR-0001).

  This module is the package's single public entry point over the tree:
  construction, the shared pre-order walk, and path lookup live here.
  Canonical encoding, content identity, and structural decoding land in
  later phases of the same bead.
  """

  alias StatifierBlocks.{Block, Validation}

  @typedoc ~S(`"bdoc_" <> uxid`.)
  @type id :: String.t()

  @type t :: %__MODULE__{
          schema_version: pos_integer(),
          id: id(),
          revision: non_neg_integer(),
          root: Block.t(),
          metadata: %{optional(String.t()) => Block.json()}
        }

  defstruct [:id, :root, schema_version: 1, revision: 0, metadata: %{}]

  @typedoc "Derived, never stored. Identifies a position, not a block."
  @type path :: [{Block.id(), Block.slot_name(), non_neg_integer()}]

  @doc """
  Wraps `root` in a document envelope.

  Options: `:id` (default a freshly minted `StatifierBlocks.Id.document/0`),
  `:revision` (default `0`), `:metadata` (default `%{}`). `:schema_version`
  is not an option - decision 7 fixes it at `1` for this ADR's envelope.
  """
  @spec new(Block.t(), keyword()) :: t()
  def new(%Block{} = root, opts \\ []) do
    %__MODULE__{
      id: Keyword.get_lazy(opts, :id, &StatifierBlocks.Id.document/0),
      root: root,
      revision: Keyword.get(opts, :revision, 0),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Every block in `document`, pre-order, root first.

  Within a block, slots are visited in UTF-8-sorted slot-name order so
  every consumer of this walk sees one deterministic order regardless of
  how the `slots` map happened to be built. Later phases (encoding,
  validation) build on this walk rather than re-deriving their own.
  """
  @spec blocks(t()) :: [Block.t()]
  def blocks(%__MODULE__{root: root}), do: walk(root)

  @spec walk(Block.t()) :: [Block.t()]
  defp walk(%Block{slots: slots} = block) do
    children =
      slots
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.flat_map(fn {_slot_name, children} -> children end)
      |> Enum.flat_map(&walk/1)

    [block | children]
  end

  @doc """
  The path from the root to the block carrying `id`.

  A path names the `{parent block id, slot name, index}` steps taken from
  the root, so the root's own path is `{:ok, []}` - it has taken none.
  Returns `:error` when no block in `document` carries `id`.
  """
  @spec fetch_path(t(), Block.id()) :: {:ok, path()} | :error
  def fetch_path(%__MODULE__{root: %Block{id: id}}, id), do: {:ok, []}

  def fetch_path(%__MODULE__{root: root}, id) do
    find_path(root, id)
  end

  @spec find_path(Block.t(), Block.id()) :: {:ok, path()} | :error
  defp find_path(%Block{slots: slots} = block, id) do
    slots
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.find_value(:error, fn {slot_name, children} ->
      find_in_slot(block.id, slot_name, children, id, 0)
    end)
  end

  @spec find_in_slot(Block.id(), Block.slot_name(), [Block.t()], Block.id(), non_neg_integer()) ::
          {:ok, path()} | false
  defp find_in_slot(_parent_id, _slot_name, [], _id, _index), do: false

  defp find_in_slot(parent_id, slot_name, [%Block{id: id} | _rest], id, index) do
    {:ok, [{parent_id, slot_name, index}]}
  end

  defp find_in_slot(parent_id, slot_name, [child | rest], id, index) do
    case find_path(child, id) do
      {:ok, path} -> {:ok, [{parent_id, slot_name, index} | path]}
      :error -> find_in_slot(parent_id, slot_name, rest, id, index + 1)
    end
  end

  @doc """
  Checks `document` against ADR-0001's structural rules: schema version,
  envelope shape, per-block shape (id, type, type_version, config, slots),
  and document-wide id uniqueness. Never consults a block-type registry -
  `config` is opaque here and `type` is never resolved against anything.
  """
  @spec validate(t()) :: :ok | {:error, Validation.error()}
  def validate(%__MODULE__{} = document), do: Validation.validate(document)
end
