defmodule StatifierBlocks.Core.PlacementTest do
  @moduledoc """
  The bead's third acceptance criterion: the `core.on_event` placement rule
  holds **in both directions**, and holds purely from ADR-0003 decision 3's
  kind tags.

  The property is checked exhaustively rather than sampled. The core
  vocabulary is finite - seven types, and a bounded slot set once each type
  is given a config - so every `{parent, slot, child}` triple in it can be
  enumerated, and enumerating them all is a stronger statement than any
  number of random draws: there is no unvisited corner left for a
  counterexample to hide in.

  The biconditional under test, over every core parent slot and every core
  child:

      admitted?(parent, slot, child) <=> (slot is "interrupts") == (child is core.on_event)

  Read left to right that is "an interrupt handler goes in an interrupts
  slot"; read right to left it is "and nothing else does, and it goes
  nowhere else" - the mirror-image error ADR-0002 decision 10's withdrawn
  one-directional rule left unstated.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.Assignability
  alias StatifierBlocks.Core
  alias StatifierBlocks.CoreFixtures

  # Every {parent module, config, slot name} in the core vocabulary.
  defp core_slots do
    for {_name, module} <- CoreFixtures.core_modules(),
        config = CoreFixtures.valid_config(module),
        {slot, _arity, _label} <- module.slots(config),
        do: {module, config, slot}
  end

  defp core_children do
    for {_name, module} <- CoreFixtures.core_modules(),
        do: {module, CoreFixtures.valid_config(module)}
  end

  # Sabotage: deleted `"interrupts" => [:interrupt_handler]` from
  # `Core.Group.io/1` - red on every group/on_event pair, in the direction
  # that says a plain step must not land in an interrupts slot.
  test "placement is exactly 'interrupt handlers in interrupts slots', in both directions" do
    for {parent, parent_config, slot} <- core_slots(),
        {child, child_config} <- core_children() do
      admitted = Assignability.admits?({parent, parent_config}, slot, {child, child_config})
      expected = slot == "interrupts" == (child == Core.OnEvent)

      assert admitted == expected, """
      #{inspect(parent)} slot #{inspect(slot)} #{if admitted, do: "admitted", else: "refused"} \
      #{inspect(child)}, expected the opposite.
      """
    end
  end

  # Sabotage: added `kinds: [:step]` alongside `:interrupt_handler` on
  # `Core.OnEvent` - red here, because a handler that is also a step is
  # admitted everywhere.
  test "core.on_event is admitted by every interrupts slot and refused by every other" do
    handler = {Core.OnEvent, CoreFixtures.valid_config(Core.OnEvent)}

    {interrupts, others} =
      Enum.split_with(core_slots(), fn {_module, _config, slot} -> slot == "interrupts" end)

    assert interrupts != []
    assert Enum.all?(interrupts, fn {m, c, s} -> Assignability.admits?({m, c}, s, handler) end)
    refute Enum.any?(others, fn {m, c, s} -> Assignability.admits?({m, c}, s, handler) end)
  end

  # Sabotage: changed `Core.Group.io/1`'s "body" to `:any` - red here, on
  # the arm of the property that keeps a handler out of a body slot.
  test "no interrupts slot admits anything that is not an interrupt handler" do
    for {parent, parent_config, "interrupts"} <-
          Enum.filter(core_slots(), fn {_m, _c, slot} -> slot == "interrupts" end),
        {child, child_config} <- core_children(),
        child != Core.OnEvent do
      refute Assignability.admits?({parent, parent_config}, "interrupts", {child, child_config}),
             "#{inspect(parent)} admitted #{inspect(child)} into interrupts"
    end
  end

  # Sabotage: made `Assignability.kinds/2` default to `[]` instead of
  # `[:step]` - red here, which is the ADR-0003 decision 5 default the whole
  # property rests on.
  test "a host handler is admitted without either side naming the other" do
    group = {Core.Group, %{}}
    host_handler = {CoreFixtures.OnEvent, %{}}
    host_step = {CoreFixtures.Notify, %{}}

    assert Assignability.admits?(group, "interrupts", host_handler)
    refute Assignability.admits?(group, "interrupts", host_step)
    refute Assignability.admits?(group, "body", host_handler)
    assert Assignability.admits?(group, "body", host_step)
  end
end
