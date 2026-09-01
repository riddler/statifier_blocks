defmodule StatifierBlocks.Core.Placeholder do
  @moduledoc """
  `core.placeholder`: an in-flow leaf marking a gap the author has left on
  purpose (ADR-0002's amendment of 2026-08-31, section G10).

  It compiles to a step that does nothing and it warns. Both halves matter.
  The step is real, so the chart runs and a preview walks straight through
  the gap - an author previewing a half-built workflow sees the half they
  built, which is what makes a marker cheaper to place than a hole. The
  warning is where the reminder belongs: in the compile, addressed to the
  author, rather than in the running machine addressed to nobody
  (ADR-0004's amendment of the same date, D4 and D5).

  ## Declarations

  Every callback but three is the default `use StatifierBlocks.BlockType`
  injects (ADR-0007 decision 1), and that is the point rather than an
  economy. `io/1` in particular takes ADR-0003 decision 5's permissive
  default in full - `kinds: [:step]`, `consumes: :unknown`,
  `produces: :unknown` - which section A3 of that record's amendment states
  is the honest answer: a gap goes wherever a step goes, and declaring
  anything narrower would be this package deciding what an author's
  unwritten step was going to do.

  The one config field, `note`, is prose and this package never reads it.
  It exists so a gap can carry the author's own words into the editor's
  card and into the compile warning. Nothing parses it, nothing routes on
  it, and an empty one is not a finding: an unexplained gap is still a gap,
  and refusing one would make the marker more expensive to place than
  leaving the hole unmarked, which inverts the whole point (G10b).

  No `icon` is declared. The icon seam treats an entry that names no icon
  as a nameless entry rather than a missing one and draws no tile at all,
  and a marker for something not yet written is exactly that case.

  ## Against `core.drafts`

  The two types are opposites and shipped together on purpose (G10a).
  `StatifierBlocks.Core.Drafts` holds work that is **not** in the flow and
  says nothing about it; a placeholder block **is** in the flow and says
  something is missing from it. An author moving a fragment off the shelf
  into the flow is filling a gap; an author who has not built the fragment
  yet marks the gap instead.

  ## The word "placeholder"

  The compiler already uses it: an `StatifierBlocks.Emission` carries
  `{:child, block_id}` markers that ADR-0004 decision 10's Emit stage
  splices each child's emission into, and both the code and that record
  call those **child placeholders**. They are an internal step of one
  compile, never stored, never rendered and never seen by an author. A
  placeholder block is the opposite in every one of those respects
  (G10a-i).
  """

  use StatifierBlocks.BlockType

  alias StatifierBlocks.Core.Emit

  @impl true
  def config_schema(_config),
    do: [
      %{
        key: "note",
        type: :string,
        label: "What goes here",
        required?: false,
        default: ""
      }
    ]

  @doc """
  Refuses a `note` that is not a string, and refuses nothing else. An
  absent `note` and an empty one are both accepted (G10b).
  """
  @impl true
  def validate_config(config) do
    case Map.get(config, "note", "") do
      note when is_binary(note) -> :ok
      _other -> {:error, [{"note", "must be text"}]}
    end
  end

  @impl true
  def palette_entry,
    do: %{
      label: "Placeholder",
      group: "Structure",
      description: "Marks a step the author has deliberately left unwritten.",
      keywords: ["gap", "todo", "missing", "stub", "marker"],
      order: 13
    }

  @doc """
  The smallest thing a step can be: one compound state carrying a single
  `<final>` reached on entry, so the block completes immediately and the
  parent's ordinary `done.state` sequencing carries on to the next sibling
  (D5).

      <state id="s_blk_PLA" initial="s_blk_PLA__done">
        <final id="s_blk_PLA__done"/>
      </state>

  There is no `<log>`, no raised event and no data written. A marker that
  announced itself into the chart would be a marker the author had to
  remember to remove before the chart was real.
  """
  @impl true
  def emit(_block, context), do: Emit.ordered(context, [])
end
