defmodule StatifierBlocks.Core.PlacementTest do
  @moduledoc """
  The bead's third acceptance criterion: the `core.on_event` placement rule
  holds **in both directions**, and holds purely from ADR-0003 decision 3's
  kind tags.

  The property is checked exhaustively rather than sampled. The core
  vocabulary is finite - a fixed set of types, and a bounded slot set once each type
  is given a config - so every `{parent, slot, child}` triple in it can be
  enumerated, and enumerating them all is a stronger statement than any
  number of random draws: there is no unvisited corner left for a
  counterexample to hide in.

  The biconditional under test, over every core parent slot and every core
  child, as the 2026-08-31 amendments leave it:

      admitted?(parent, slot, child) <=>
        if parent slot is the drafts body, true
        else ((slot is "interrupts") == (child is core.on_event))
             and child is not core.drafts

  The first two lines are the original property. Read left to right that is
  "an interrupt handler goes in an interrupts slot"; read right to left it
  is "and nothing else does, and it goes nowhere else" - the mirror-image
  error ADR-0002 decision 10's withdrawn one-directional rule left
  unstated.

  The two new clauses are the shelf, and each is the record working rather
  than an exemption bought to keep the test green:

    * **The drafts body is enumerated on its own**, because ADR-0003's
      amendment of 2026-08-31, section A1, declares it
      `slot_accepts: %{"body" => :any}` deliberately - a shelf that refused
      the fragment an author most needed to put down would be worse than no
      shelf. It is the one core slot that admits everything, `core.on_event`
      included, and that admission is checked directly below rather than
      folded into a property that would have to be weakened to allow it.
    * **`core.drafts` is refused everywhere else**, because ADR-0002's
      amendment of the same date, section G9b, mints `:draft_shelf` for
      exactly that: every other core slot accepts `[:step]` or
      `[:interrupt_handler]`, so the ordinary intersection refuses a shelf
      with no new rule and no per-type list. The right-hand side conjoins
      it, and the direction that says so is asserted on its own below.

  What the kind cannot say - that the root's `body` admits a shelf anyway,
  and that a document carries at most one - is not a placement question and
  is not here. Both are Structure-stage findings owned by
  `StatifierBlocks.Shelf` (G12, campaign-024 ruling R-b), tested in
  `test/statifier_blocks/shelf_test.exs`.
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

  # The one core slot that accepts `:any` (A1). Enumerated by declaration
  # rather than by name, so a second `:any` slot appearing in the
  # vocabulary later is caught by this test rather than silently absorbed
  # by it.
  defp tray_slot?(module, config, slot) do
    module
    |> Assignability.io(config)
    |> Map.get(:slot_accepts, %{})
    |> Map.get(slot) == :any
  end

  # Sabotage: deleted `"interrupts" => [:interrupt_handler]` from
  # `Core.Group.io/1` - red on every group/on_event pair, in the direction
  # that says a plain step must not land in an interrupts slot.
  test "placement is exactly 'interrupt handlers in interrupts slots', in both directions" do
    for {parent, parent_config, slot} <- core_slots(),
        {child, child_config} <- core_children() do
      admitted = Assignability.admits?({parent, parent_config}, slot, {child, child_config})

      expected =
        if tray_slot?(parent, parent_config, slot) do
          true
        else
          slot == "interrupts" == (child == Core.OnEvent) and child != Core.Drafts
        end

      assert admitted == expected, """
      #{inspect(parent)} slot #{inspect(slot)} #{if admitted, do: "admitted", else: "refused"} \
      #{inspect(child)}, expected the opposite.
      """
    end
  end

  # Sabotage: gave `Core.Drafts.io/1` `kinds: [:step, :draft_shelf]` - red
  # on every step slot in the vocabulary, which is G9b's whole argument for
  # minting the kind rather than adding one.
  test "a draft shelf is refused by every core slot but the shelf's own body" do
    shelf = {Core.Drafts, CoreFixtures.valid_config(Core.Drafts)}

    {trays, others} =
      Enum.split_with(core_slots(), fn {m, c, s} -> tray_slot?(m, c, s) end)

    # Pinned by name, not only derived. `tray_slot?/3` reads the very
    # declaration under test, so without this line a narrowed
    # `Core.Drafts.io/1` would move the partition instead of failing - the
    # test would follow the mutation rather than catch it.
    assert Enum.map(trays, fn {m, _c, s} -> {m, s} end) == [{Core.Drafts, "body"}]
    assert Enum.all?(trays, fn {m, c, s} -> Assignability.admits?({m, c}, s, shelf) end)
    refute Enum.any?(others, fn {m, c, s} -> Assignability.admits?({m, c}, s, shelf) end)
  end

  # Sabotage: changed `Core.Drafts.io/1`'s `"body"` to `[:step]` - red on
  # the handler and on the shelf, which is A1's "maximally permissive" read
  # as an assertion rather than as prose.
  test "the shelf's body admits every core type, handler and shelf included" do
    for {module, config, slot} <- core_slots(),
        tray_slot?(module, config, slot),
        {child, child_config} <- core_children() do
      assert Assignability.admits?({module, config}, slot, {child, child_config}),
             "#{inspect(module)} slot #{inspect(slot)} refused #{inspect(child)}"
    end
  end

  # Sabotage: added `kinds: [:step]` alongside `:interrupt_handler` on
  # `Core.OnEvent` - red here, because a handler that is also a step is
  # admitted everywhere.
  test "core.on_event is admitted by every interrupts slot and refused by every other" do
    handler = {Core.OnEvent, CoreFixtures.valid_config(Core.OnEvent)}

    # The shelf's body is excluded from "every other", not exempted from
    # the rule: A1 declares it `:any` deliberately, so it admits a handler
    # for the same reason it admits everything else, and the test above
    # asserts that admission directly rather than letting this one carry it.
    {interrupts, others} =
      core_slots()
      |> Enum.reject(fn {m, c, s} -> tray_slot?(m, c, s) end)
      |> Enum.split_with(fn {_module, _config, slot} -> slot == "interrupts" end)

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
