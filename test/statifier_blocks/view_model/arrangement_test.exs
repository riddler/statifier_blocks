defmodule StatifierBlocks.ViewModel.ArrangementTest do
  @moduledoc """
  `ViewModel.arrangement/1` and `fan_label/1`: ADR-0005 amendment 10b's
  side-by-side arrangement, derived once for three consumers.

  The load-bearing assertion in this file is the negative one, and it is the
  same one the presentation tests make about `layout` and `slot_style`: a
  host block type reaches `:fan` or `:lanes` by declaring the shape, never by
  being named. Every fixture below is a `host.*` type for that reason - a
  derivation asserted only through `core.branch` and `core.parallel` would
  pass just as well if it were a case over those two strings.

  Not tagged `:liveview`: `ViewModel` is outside the Phoenix guard, so this
  has to pass in the headless tree.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.ViewModel
  alias StatifierBlocks.ViewModel.{Node, Slot}

  describe "arrangement/1 (10b)" do
    # Sabotage: `arrangement_of/2` answering `:fan` for a single body slot -
    # every ordinary sequence acquires columns, a pill and a fan, and the
    # whole document renders as one-armed branches.
    test "one body slot arranges nothing" do
      assert ViewModel.arrangement(container([slot("body", [leaf("blk_a")])])) == :stack
    end

    # Sabotage: dropping the `[]` clause - a container declaring no body slot
    # at all is called arranged, and `Connectors.fan_edges/3` is handed an
    # empty column list to fan into.
    test "no body slot at all arranges nothing, whatever the type declared" do
      assert ViewModel.arrangement(container([], %{layout: :columns})) == :stack
      assert ViewModel.arrangement(container([slot("rail", [], :secondary)])) == :stack
    end

    # Sabotage: counting `node.slots` instead of `body_slots/1` - a group with
    # one body and one interrupt rail is called a fan, so a rail is drawn as
    # an alternative to the body it watches rather than beside it.
    test "a rail is not a column: it is attached beside the body, not fanned into" do
      node =
        container([
          slot("body", [leaf("blk_a")]),
          slot("interrupts", [leaf("blk_rule")], :secondary),
          slot("on_error", [leaf("blk_oops")], :failure)
        ])

      assert ViewModel.arrangement(node) == :stack
      assert Enum.map(ViewModel.body_slots(node), & &1.name) == ["body"]
    end

    # Sabotage: reading `layout` only, and never the body-slot count - a
    # branch's arms stack full-width again, which is the layout that put every
    # fan edge straight down through the arm above its target (`sb-ay0`).
    test "more than one body slot is a fan, declared by shape and not by name" do
      node = container([slot("arm_a", [leaf("blk_a")]), slot("otherwise", [])])

      assert ViewModel.arrangement(node) == :fan
    end

    # Sabotage: dropping the `layout: :columns` clause - a parallel with one
    # lane stops being lanes, and a two-lane parallel becomes indistinguishable
    # from a two-armed branch.
    test "layout: :columns is lanes, at any number of lanes" do
      one = container([slot("lane_a", [leaf("blk_a")])], %{layout: :columns})
      two = container([slot("lane_a", []), slot("lane_b", [])], %{layout: :columns})

      assert ViewModel.arrangement(one) == :lanes
      assert ViewModel.arrangement(two) == :lanes
    end

    # `:columns` wins over the count, which is what makes the two arrangements
    # a partition rather than an ordering question.
    # Sabotage: testing the body-slot count before the layout - a parallel with
    # two lanes is reported as an exclusive fan and the pill above it reads
    # "one of" over lanes that all run.
    test "a declared columns layout is lanes even with several body slots" do
      node =
        container(
          [slot("lane_a", [leaf("blk_a")]), slot("lane_b", [leaf("blk_b")])],
          %{layout: :columns}
        )

      assert ViewModel.arrangement(node) == :lanes
    end
  end

  describe "fan_label/1: the only place the distinction is stated" do
    # Sabotage: returning one word for both arrangements - side-by-side
    # columns look identical either way, so the picture stops saying whether
    # one column runs or all of them do and nothing else in it does.
    test "a fan reads one of, lanes read all of, and a stack reads nothing" do
      fan = container([slot("arm_a", []), slot("otherwise", [])])
      lanes = container([slot("lane_a", [])], %{layout: :columns})
      stack = container([slot("body", [leaf("blk_a")])])

      assert ViewModel.fan_label(fan) == "one of"
      assert ViewModel.fan_label(lanes) == "all of"
      assert ViewModel.fan_label(stack) == nil
    end

    # The pill and the columns come off one derivation, which is the whole
    # reason it is a function here rather than two `case`s in two components.
    # Sabotage: deriving the label from `entry.layout` directly - a branch
    # gets columns from `arrangement/1` and no pill from the label, so the
    # arms fan out with nothing saying they are alternatives.
    test "every arranged node has words and every stacked one has none" do
      for node <- [
            container([slot("arm_a", []), slot("otherwise", [])]),
            container([slot("lane_a", [])], %{layout: :columns}),
            container([slot("body", [])]),
            container([])
          ] do
        arranged? = ViewModel.arrangement(node) != :stack

        assert arranged? == (ViewModel.fan_label(node) != nil)
      end
    end
  end

  # ------------------------------------------------------------- fixtures

  defp container(slots, entry \\ %{layout: :stack}) do
    %Node{
      block_id: "blk_host",
      type: "host.arranged",
      type_version: 1,
      status: :ok,
      entry: entry,
      slots: slots
    }
  end

  defp leaf(id) do
    %Node{
      block_id: id,
      type: "host.leaf",
      type_version: 1,
      status: :ok,
      entry: %{layout: :stack},
      slots: []
    }
  end

  defp slot(name, children, style \\ :primary) do
    %Slot{name: name, label: name, declared?: true, style: style, children: children}
  end
end
