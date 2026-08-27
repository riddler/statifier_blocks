defmodule StatifierBlocks.Core.Group do
  @moduledoc """
  `core.group`: a boundary around a run of steps that interrupt rules can
  fire against.

  Two named slots - `body` for the steps, `interrupts` for the handlers -
  which is ADR-0001 decision 10's "a *second, differently-meaning* slot on
  the same block", the case slots are named for. Interrupt rules are not a
  block type that wraps a group; they are handler blocks *in* the group's
  `interrupts` slot, because that is the arrangement they compile to and
  the arrangement an author reads as "these can interrupt this".

  ## Against `core.resumable_group`

  This type is `core.resumable_group` without the history mode: the same
  two slots, the same kind tags, no `config` at all. Reach for the
  resumable one when re-entering the group after an interrupt should return
  to where it left off; reach for this one when the group has nothing to
  remember. ADR-0002 decision 10 names only the resumable form, so the
  split is this bead's, and it is drawn so that the resumable row of that
  table is untouched.

  Unlike `StatifierBlocks.Core.Sequence`, a group is **not** transparent to
  type flow: it can be left early by an interrupt, so what reaches the
  block after it is not simply what its last step produced. It declares no
  `produces` and takes ADR-0003 decision 5's permissive `:unknown`.
  """

  @behaviour StatifierBlocks.BlockType

  alias StatifierBlocks.Core.Emit

  @impl true
  def current_version, do: 1

  @impl true
  def slots(_config),
    do: [
      {"body", :any, "Steps"},
      {"interrupts", :any, "Interrupt rules"}
    ]

  @impl true
  def config_schema(_config), do: []

  @impl true
  def validate_config(_config), do: :ok

  @doc """
  Half of ADR-0003 decision 3's placement rule: `interrupts` admits
  interrupt handlers and `body` admits steps, so an ordinary step dropped
  into `interrupts` is a `:kind_not_admitted` finding without this type
  knowing that `core.on_event` exists.
  """
  @impl true
  def io(_config),
    do: %{
      kinds: [:step],
      slot_accepts: %{"body" => [:step], "interrupts" => [:interrupt_handler]}
    }

  @impl true
  def palette_entry,
    do: %{
      label: "Group",
      group: "Structure",
      description: "Groups steps so interrupt rules can fire against them.",
      icon: "rectangle-group",
      keywords: ["interrupt", "boundary", "scope"],
      order: 1,
      layout: :stack,
      slot_style: %{"body" => :primary, "interrupts" => :secondary}
    }

  @doc """
  A compound state whose `body` runs in order, guarded by whatever sits in
  `interrupts` (`StatifierBlocks.Core.Emit`). With no interrupt handlers it
  is exactly a sequence; with them, the body and the handlers run as
  regions of a `<parallel>` and the two-event interrupt protocol is wired
  on the group's own state.

  A group has nothing to remember, so a `"resume"` handler re-enters the
  `<parallel>` and the body restarts from its first step. Resuming where it
  left off is `StatifierBlocks.Core.ResumableGroup`, and that difference is
  the whole of what separates the two types.
  """
  @impl true
  def emit(_block, context), do: Emit.interruptible(context, nil)
end
