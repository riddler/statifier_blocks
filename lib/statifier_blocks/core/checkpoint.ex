defmodule StatifierBlocks.Core.Checkpoint do
  @moduledoc """
  `core.checkpoint`: a point of no return an author places (ADR-0002's
  Amendment of 2026-11-20, `C12d`).

  Passing it clears Back's trail, so no returnable step before it can be
  returned to from a step after it. It is not itself a returnable step: a
  checkpoint is where returning stops, not a place to return to, so it
  defines no `returnable?/1`.

  ## Declarations

  Every callback but four is the default `use StatifierBlocks.BlockType`
  injects. It has no slots, no config fields and refuses nothing, so a block
  of it carries what every block carries - its id, its type, its
  `type_version` and its note - and nothing else. `outcomes/1` is not
  defined, so it has the one outcome `done`. `io/1` is the injected `%{}`:
  it reads and writes nothing an author declares, so every slot that admits
  an unconstrained block admits it. Its version is 1.

  It is kind-neutral like every core type: it says nothing about what the
  steps around it are or who takes them, and it is placed and judged the
  same way in any document.

  ## What it compiles to

  `emit/2` is the step that does nothing, the shape `core.placeholder`
  emits (ADR-0004's `D5`): one compound state carrying a single `<final>`
  reached on entry, so the parent's ordinary `done.state` sequencing
  carries on to the next sibling.

  The clear is not this module's. When the trail scope the checkpoint sits
  in has a trail root - when at least one returnable step belongs to that
  scope - `StatifierBlocks.Compiler.Trail` puts
  `<assign expr="[]" location="T"/>` first in the checkpoint state's
  `<onentry>`, where `T` is that scope's trail root (ADR-0004's
  Amendment of 2026-11-20, `L6`). In a scope with no returnable step the
  checkpoint compiles to this module's shape alone, and no trail root, push
  or Back transition appears because of it (`L8`): placing a checkpoint
  does not create a returnable step.
  """

  use StatifierBlocks.BlockType

  alias StatifierBlocks.Core.Emit

  @impl true
  def palette_entry,
    do: %{
      label: "Checkpoint",
      group: "Structure",
      description: "A point of no return: no step before it can be returned to after it.",
      icon: "flag",
      keywords: ["checkpoint", "back", "return", "point of no return", "commit"],
      order: 18
    }

  @impl true
  def explain,
    do:
      "A checkpoint is a point of no return. Passing it clears the record of steps that can be returned to, so once the flow has gone past it, no step before it can be gone back to from a step after it. It does nothing else: the flow walks straight through it to the next step, and it is never a step to return to itself."

  @doc """
  The line the outline and the Map draw under the block's title.

      iex> StatifierBlocks.Core.Checkpoint.sentence(%{})
      "No going back past this point"
  """
  @impl true
  def sentence(_config), do: "No going back past this point"

  @doc """
  The step that does nothing (`D5`): one compound state carrying a single
  `<final>` reached on entry.

      <state id="s_blk_CHK" initial="s_blk_CHK__o_done">
        <final id="s_blk_CHK__o_done">
          <onentry><raise event="done.outcome.s_blk_CHK.done"/></onentry>
        </final>
      </state>

  The trail's clear, where the checkpoint's scope has a trail, is added by
  `StatifierBlocks.Compiler.Trail`, not here.
  """
  @impl true
  def emit(_block, context), do: Emit.ordered(context, [])
end
