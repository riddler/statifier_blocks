defmodule StatifierBlocks.Core.Sequence do
  @moduledoc """
  `core.sequence`: an ordered run of steps, and the conventional document
  root (ADR-0002 decision 10).

  One `body` slot, no config at all. Adjacency inside `body` *is*
  sequencing (ADR-0001 decision 5), so a sequence adds no meaning of its
  own beyond "these, in this order" - which is exactly why it is the one
  core type that is transparent to type flow: it declares
  `produces: {:passthrough, "body"}`, so whatever the last step in its body
  produces is what the sequence produces, computed by ADR-0003 decision 4
  rather than by anything here.

  A sequence has no `interrupts` slot. A container that can be interrupted
  is `StatifierBlocks.Core.Group` or
  `StatifierBlocks.Core.ResumableGroup`; keeping the plain ordered case free
  of that machinery is what makes the two readable side by side in a
  palette.
  """

  @behaviour StatifierBlocks.BlockType

  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.Emit

  @impl true
  def current_version, do: 1

  @impl true
  def slots(_config), do: [{"body", :any, "Steps"}]

  @impl true
  def config_schema(_config), do: []

  @doc """
  Always `:ok`. A sequence declares no config fields, so there is nothing
  for an author to get wrong; a config carrying keys this type does not
  know is left alone rather than rejected, the same way ADR-0001 decision 9
  leaves an unresolvable type alone at decode time.
  """
  @impl true
  def validate_config(_config), do: :ok

  @impl true
  def io(_config),
    do: %{
      kinds: [:step],
      produces: {:passthrough, "body"},
      slot_accepts: %{"body" => [:step]}
    }

  @impl true
  def palette_entry,
    do: %{
      label: "Sequence",
      group: "Structure",
      description: "Runs its steps one after another.",
      icon: "bars-3",
      keywords: ["steps", "order", "then"],
      order: 0,
      layout: :stack
    }

  @doc """
  A compound state running `body` in order and finishing at its own
  `<final>` - `StatifierBlocks.Core.Emit`'s plain ordered shape, with
  nothing added. A sequence with an empty `body` enters its `<final>`
  directly and is done, which is the honest compilation of "these, in this
  order" over no steps.
  """
  @impl true
  def emit(_block, context), do: Emit.ordered(context, Context.children(context, "body"))
end
