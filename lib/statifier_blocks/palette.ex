defmodule StatifierBlocks.Palette do
  @moduledoc """
  A palette names the block types a host makes available: a map from a
  block's `type_name` to the module implementing `StatifierBlocks.BlockType`
  for it (ADR-0002 decision 2).

  It is a **caller-supplied value**, nothing more. A palette is built once
  for an editing or compiling operation and passed explicitly into whatever
  needs it - document validation, the editor's session state, the compiler -
  the same way any other value is threaded through a pipeline. Nothing in
  this package holds a palette across operations, and no cadence beyond "one
  value per operation" is implied: a caller that wants the same set of types
  for its next operation builds (or reuses) the value again, deliberately.

  It is explicitly **not**:

    * an application-configuration lookup keyed by block type
    * a table of shared entries reachable by name from anywhere in the
      process tree
    * a lookup registered under a well-known process name
    * anything wired up automatically when this package (or a host
      application) starts

  Any of those would make two hosts sharing one runtime step on each
  other's block types - the multi-tenant property this design exists to
  keep. Two `StatifierBlocks.Palette` values built with different modules
  under the same `type_name` in the same running system resolve
  independently; neither can see or clobber the other.

  Every consumer that walks a document and resolves blocks against a
  palette carries the case where a block's `type_name` has no entry as an
  ordinary pattern-matched arm, not as an exception - `fetch/2` never
  raises, so there is nothing to rescue.
  """

  alias StatifierBlocks.Block

  @type t :: %__MODULE__{types: %{optional(Block.type_name()) => module()}}

  defstruct types: %{}

  @doc """
  Builds a palette from a `type_name => module` map. Defaults to an empty
  palette.
  """
  @spec new(%{optional(Block.type_name()) => module()}) :: t()
  def new(types \\ %{}) when is_map(types), do: %__MODULE__{types: types}

  @doc """
  Resolves a `type_name` to its module. Total; never raises (ADR-0002
  decision 3). `Map.fetch/2` rather than a sentinel default, so a palette
  that genuinely maps a name to `nil` stays distinguishable from a name no
  entry carries.
  """
  @spec fetch(t(), Block.type_name()) ::
          {:ok, module()}
          | {:error, {:unknown_block_type, Block.type_name()}}
  def fetch(%__MODULE__{types: types}, type_name) do
    case Map.fetch(types, type_name) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, {:unknown_block_type, type_name}}
    end
  end
end
