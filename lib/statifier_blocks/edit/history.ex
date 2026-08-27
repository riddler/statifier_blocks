defmodule StatifierBlocks.Edit.History do
  @moduledoc """
  Undo and redo over `StatifierBlocks.Edit.t()` commands (ADR-0005
  decision 3), and the one funnel every editor command actually goes
  through: `commit/4` runs `Edit.check_config/3` before `Edit.apply/2`, so
  "invalid config never reaches the document" is a property of this
  module, not a rule an editor shell has to remember to enforce itself.

  ## The gate runs on undo and redo too

  `Edit.apply/2` is purely structural; it never asks a block type whether
  a config is valid. `commit/4`, `undo/3` and `redo/3` all route through
  the same private funnel, and that funnel always calls
  `Edit.check_config/3` first - undo and redo included, not just the
  initial commit. This is deliberate, not an oversight: one code path
  means one thing to test, and it is the strict reading of decision 9
  ("invalid config never reaches the document" is a property of every
  path that can produce a document, not only the first one).

  It is also sound, not merely convenient. The config an inverse restores
  was already in the document at some earlier point, which means it
  already validated - under whatever palette was in effect when it got
  there. ADR-0005 decision 15 makes the editor single-session: one
  palette, built once, for the whole session. A host that swapped the
  palette out from under a live session could in principle see an undo
  refused by a rule that did not exist when the config was written, but
  that scenario is exactly what decision 15 puts out of scope. Within a
  single session the palette never changes underneath the history, so the
  config an undo or redo restores always validates the same way it did
  the first time.
  """

  alias StatifierBlocks.{Block, BlockType, Document, Edit, Palette}

  @typedoc """
  `undo` and `redo` hold commands in the order they would be *applied*
  next: `List.first(undo)` is what a call to `undo/3` runs, and
  `List.first(redo)` is what a call to `redo/3` runs. `limit` bounds how
  many entries `undo` may carry; `:infinity` (the default) never drops
  one.
  """
  @type t :: %__MODULE__{
          undo: [Edit.t()],
          redo: [Edit.t()],
          limit: pos_integer() | :infinity
        }

  defstruct undo: [], redo: [], limit: :infinity

  @doc """
  Builds an empty history. Options: `:limit`, a `pos_integer()` bounding
  the undo stack, or `:infinity` (the default - never drops an entry).
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{limit: Keyword.get(opts, :limit, :infinity)}
  end

  @doc """
  Applies `command` to `document` through the gate, pushes its inverse
  onto the undo stack, and clears the redo stack - a fresh commit
  invalidates whatever `redo/3` would have replayed.

  Funnel order (ADR-0005 decision 9): `Edit.check_config/3`, then
  `Edit.apply/2`, then push and clear. The trailing `{:error, term()}` arm
  is `Edit.apply/2`'s own error union, propagated unchanged.
  """
  @spec commit(t(), Palette.t(), Document.t(), Edit.t()) ::
          {:ok, t(), Document.t()}
          | {:error, {:invalid_config, Block.id(), [BlockType.finding()]}}
          | {:error, term()}
  def commit(%__MODULE__{} = history, %Palette{} = palette, %Document{} = document, command) do
    with {:ok, new_document, inverse} <- apply_gated(palette, document, command) do
      {:ok, %{history | undo: [inverse | history.undo] |> bounded(history.limit), redo: []},
       new_document}
    end
  end

  @doc """
  Applies the top of the undo stack's own inverse - the command already
  captured at commit time, so it is already the correct target - through
  the same gated path `commit/4` uses. Moves the *new* inverse `apply/2`
  hands back onto the redo stack, so `redo/3` can replay the original
  forward command.
  """
  @spec undo(t(), Palette.t(), Document.t()) ::
          {:ok, t(), Document.t()} | {:error, :nothing_to_undo} | {:error, term()}
  def undo(%__MODULE__{undo: []}, %Palette{}, %Document{}), do: {:error, :nothing_to_undo}

  def undo(
        %__MODULE__{undo: [command | rest]} = history,
        %Palette{} = palette,
        %Document{} = document
      ) do
    with {:ok, new_document, inverse} <- apply_gated(palette, document, command) do
      {:ok, %{history | undo: rest, redo: [inverse | history.redo]}, new_document}
    end
  end

  @doc """
  The mirror of `undo/3`: re-applies the top of the redo stack through the
  same gated path, and moves its inverse back onto the undo stack.
  """
  @spec redo(t(), Palette.t(), Document.t()) ::
          {:ok, t(), Document.t()} | {:error, :nothing_to_redo} | {:error, term()}
  def redo(%__MODULE__{redo: []}, %Palette{}, %Document{}), do: {:error, :nothing_to_redo}

  def redo(
        %__MODULE__{redo: [command | rest]} = history,
        %Palette{} = palette,
        %Document{} = document
      ) do
    with {:ok, new_document, inverse} <- apply_gated(palette, document, command) do
      {:ok, %{history | redo: rest, undo: [inverse | history.undo] |> bounded(history.limit)},
       new_document}
    end
  end

  @doc "Whether `undo/3` would have anything to do."
  @spec can_undo?(t()) :: boolean()
  def can_undo?(%__MODULE__{undo: []}), do: false
  def can_undo?(%__MODULE__{}), do: true

  @doc "Whether `redo/3` would have anything to do."
  @spec can_redo?(t()) :: boolean()
  def can_redo?(%__MODULE__{redo: []}), do: false
  def can_redo?(%__MODULE__{}), do: true

  # The one funnel: check_config/3, then apply/2. Every public function
  # above routes through this - `commit/4`, `undo/3` and `redo/3` alike -
  # so the gate never has an exception to test.
  @spec apply_gated(Palette.t(), Document.t(), Edit.t()) ::
          {:ok, Document.t(), Edit.t()}
          | {:error, {:invalid_config, Block.id(), [BlockType.finding()]}}
          | {:error, term()}
  defp apply_gated(%Palette{} = palette, %Document{} = document, command) do
    with :ok <- Edit.check_config(palette, document, command) do
      Edit.apply(document, command)
    end
  end

  @spec bounded([Edit.t()], pos_integer() | :infinity) :: [Edit.t()]
  defp bounded(undo, :infinity), do: undo
  defp bounded(undo, limit), do: Enum.take(undo, limit)
end
