defmodule StatifierBlocks.Core.CoreTypesTest do
  @moduledoc """
  What each `core.*` type *means*, one describe per type: the slot sets it
  derives from config, the findings its `validate_config/1` is the
  authority for (ADR-0002 decision 7), and the registry function that hands
  a host the whole vocabulary.

  The shape assertions every type shares live in `conformance_test.exs`;
  nothing here repeats them.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.Core
  alias StatifierBlocks.Palette

  describe "Palette.core/0 and core_types/0" do
    # Sabotage: dropped `"core.group"` from `core_types/0` - red on the
    # seven-entry assert and on the fetch below.
    test "hand a host every core type, by the name a document stores" do
      assert %Palette{} = palette = Palette.core()
      assert map_size(Palette.core_types()) == 7
      assert palette.types == Palette.core_types()

      assert {:ok, Core.Sequence} = Palette.fetch(palette, "core.sequence")
      assert {:ok, Core.Group} = Palette.fetch(palette, "core.group")
      assert {:ok, Core.Branch} = Palette.fetch(palette, "core.branch")
      assert {:ok, Core.Parallel} = Palette.fetch(palette, "core.parallel")
      assert {:ok, Core.Wait} = Palette.fetch(palette, "core.wait")
      assert {:ok, Core.ResumableGroup} = Palette.fetch(palette, "core.resumable_group")
      assert {:ok, Core.OnEvent} = Palette.fetch(palette, "core.on_event")
    end

    # Sabotage: made `core_types/0` return a `%Palette{}` - red, because a
    # host could no longer merge its own entries into it.
    test "a host entry sharing a core name wins the merge" do
      merged = Palette.new(Map.merge(Palette.core_types(), %{"core.wait" => Core.Sequence}))

      assert {:ok, Core.Sequence} = Palette.fetch(merged, "core.wait")
      assert {:ok, Core.Branch} = Palette.fetch(merged, "core.branch")
    end
  end

  describe "core.sequence" do
    # Sabotage: changed `produces` to `:unknown` - red, and with it the
    # transparency ADR-0003 decision 4 gives this one type.
    test "is a transparent single-slot container" do
      assert Core.Sequence.slots(%{}) == [{"body", :any, "Steps"}]
      assert Core.Sequence.config_schema(%{}) == []
      assert Core.Sequence.validate_config(%{"anything" => 1}) == :ok

      assert %{produces: {:passthrough, "body"}, slot_accepts: %{"body" => [:step]}} =
               Core.Sequence.io(%{})
    end
  end

  describe "core.group" do
    # Sabotage: gave `Core.Group` a `history` field - red, because the
    # split from `core.resumable_group` is exactly that it has none.
    test "is two named slots and no config" do
      assert Core.Group.slots(%{}) == [
               {"body", :any, "Steps"},
               {"interrupts", :any, "Interrupt rules"}
             ]

      assert Core.Group.config_schema(%{}) == []
      assert Core.Group.validate_config(%{}) == :ok

      assert Core.Group.palette_entry().slot_style == %{
               "body" => :primary,
               "interrupts" => :secondary
             }
    end
  end

  describe "core.resumable_group" do
    # Sabotage: accepted any string for `history` - red on the third assert.
    test "requires a history mode of shallow or deep" do
      assert Core.ResumableGroup.validate_config(%{"history" => "shallow"}) == :ok
      assert Core.ResumableGroup.validate_config(%{"history" => "deep"}) == :ok

      assert {:error, [{"history", _}]} =
               Core.ResumableGroup.validate_config(%{"history" => "sideways"})

      assert {:error, [{"history", _}]} = Core.ResumableGroup.validate_config(%{})
      assert {:error, [{"history", _}]} = Core.ResumableGroup.validate_config(%{"history" => 1})
    end

    # Sabotage: dropped the `:select` options - red on the option pair.
    test "renders the history mode as an ordinary select, with a default" do
      assert [%{key: "history", type: {:select, options}, required?: true, default: "shallow"}] =
               Core.ResumableGroup.config_schema(%{})

      assert Enum.map(options, &elem(&1, 0)) == ["shallow", "deep"]
    end
  end

  describe "core.wait" do
    # Sabotage: dropped the trailing `\\z` anchor from the duration regex -
    # red on `"PT48H later"`.
    test "accepts ISO-8601 durations and rejects everything else" do
      for good <- ["PT30S", "PT48H", "P1D", "P1Y2M3DT4H5M6S", "P2W"] do
        assert Core.Wait.validate_config(%{"duration" => good}) == :ok
      end

      for bad <- ["", "P", "PT", "48h", "PT1.5S", "PT48H later", 30, nil] do
        assert {:error, [{"duration", _}]} = Core.Wait.validate_config(%{"duration" => bad})
      end

      assert {:error, [{"duration", "required"}]} = Core.Wait.validate_config(%{})
    end

    # Sabotage: gave `core.wait` a `body` slot - red, since a wait is a leaf.
    test "is a leaf that constrains nothing but its own kind" do
      assert Core.Wait.slots(%{"duration" => "PT1H"}) == []
      assert Core.Wait.io(%{}) == %{kinds: [:step]}
    end
  end

  describe "core.on_event" do
    # Sabotage: accepted an empty `event` - red on the second assert.
    test "requires an event name and a known outcome" do
      assert Core.OnEvent.validate_config(%{"event" => "order.cancelled", "outcome" => "resume"}) ==
               :ok

      assert {:error, [{"event", _}]} =
               Core.OnEvent.validate_config(%{"event" => "", "outcome" => "abandon"})

      assert {:error, [{"event", _}]} =
               Core.OnEvent.validate_config(%{"event" => "two words", "outcome" => "abandon"})

      assert {:error, [{"outcome", _}]} =
               Core.OnEvent.validate_config(%{"event" => "ok", "outcome" => "explode"})

      assert {:error, [{"event", _}, {"outcome", _}]} = Core.OnEvent.validate_config(%{})
    end

    # Sabotage: added `:step` to its kinds - red, and the placement property
    # goes red with it.
    test "tags itself an interrupt handler and nothing else" do
      assert Core.OnEvent.io(%{}) == %{kinds: [:interrupt_handler]}
      assert Core.OnEvent.slots(%{}) == []
    end

    # Sabotage: returned a `datasets` bundle here instead of `events` - red.
    # PROVISIONAL: the bundle shape is ADR-0002 decision 9's amendment
    # (PR #13), which is not accepted.
    test "ships one example event payload (PROVISIONAL)" do
      assert %{events: events} = Core.OnEvent.fixtures()
      assert Map.has_key?(events, "order.cancelled")
    end
  end

  describe "core.branch" do
    @arms %{
      "arms" => [
        %{"slot" => "arm_approved", "cond" => "budget_remaining > amount"},
        %{"slot" => "arm_review", "cond" => "amount > 200"}
      ]
    }

    # Sabotage: appended `otherwise` before the arms - red on slot order,
    # which is the order the editor renders arms in.
    test "derives one at-least-one slot per arm, in config order, then otherwise" do
      assert Core.Branch.slots(@arms) == [
               {"arm_approved", :at_least_one, ~s(When "approved")},
               {"arm_review", :at_least_one, ~s(When "review")},
               {"otherwise", :any, "Otherwise"}
             ]

      assert Core.Branch.slots(%{}) == [{"otherwise", :any, "Otherwise"}]
    end

    # Sabotage: keyed the per-arm field on `"arms"` - red, and a finding
    # would no longer route to the field it is about.
    test "derives one expression field per arm, keyed on the arm's slot" do
      assert [
               %{key: "arm_approved", type: :expression, required?: true},
               %{key: "arm_review", type: :expression, required?: true}
             ] = Core.Branch.config_schema(@arms)
    end

    # sabotage: drop the `value_path` from `config_schema/1` - the key is read
    # as the address again, so a condition renders empty and edits nowhere.
    test "each arm's field declares where its condition actually lives" do
      assert [
               %{key: "arm_approved", value_path: ["arms", 0, "cond"]},
               %{key: "arm_review", value_path: ["arms", 1, "cond"]}
             ] = Core.Branch.config_schema(@arms)
    end

    # sabotage: build the path from `Enum.with_index` over the *filtered* arms
    # - the good arm below a malformed one addresses the malformed one's
    # condition, which is a live case since that config is mid-edit.
    test "the path indexes the stored arms, not the well-formed ones" do
      config = %{
        "arms" => [
          %{"slot" => "not_an_arm", "cond" => "junk"},
          %{"slot" => "arm_second", "cond" => "x == 1"},
          %{"slot" => "arm_second", "cond" => "shadowed"},
          %{"slot" => "arm_third", "cond" => "x == 2"}
        ]
      }

      assert [
               %{key: "arm_second", value_path: ["arms", 1, "cond"]},
               %{key: "arm_third", value_path: ["arms", 3, "cond"]}
             ] = Core.Branch.config_schema(config)
    end

    # Sabotage: accepted a bare suffix as an arm slot - red on `"approved"`.
    test "reports malformed, duplicated and conditionless arms" do
      assert Core.Branch.validate_config(@arms) == :ok
      assert Core.Branch.validate_config(%{}) == :ok

      assert {:error, [{"arms", _}]} = Core.Branch.validate_config(%{"arms" => "nope"})

      assert {:error, [{"arms", _}]} =
               Core.Branch.validate_config(%{"arms" => [%{"slot" => "approved", "cond" => "x"}]})

      assert {:error, [{"arms", _}]} =
               Core.Branch.validate_config(%{"arms" => [%{"slot" => "arm_a"}]})

      assert {:error, [{"arm_a", _}]} =
               Core.Branch.validate_config(%{"arms" => [%{"slot" => "arm_a", "cond" => ""}]})

      assert {:error, [{"arm_a", "two arms cannot share one slot"}]} =
               Core.Branch.validate_config(%{
                 "arms" => [
                   %{"slot" => "arm_a", "cond" => "x"},
                   %{"slot" => "arm_a", "cond" => "y"}
                 ]
               })
    end

    # Sabotage: dropped `produces: :unknown` and joined the arms instead -
    # red, and ADR-0003 decision 4 is violated in the same edit.
    test "admits steps in every arm and produces nothing knowable" do
      assert %{kinds: [:step], produces: :unknown, slot_accepts: accepts} = Core.Branch.io(@arms)

      assert accepts == %{
               "arm_approved" => [:step],
               "arm_review" => [:step],
               "otherwise" => [:step]
             }
    end

    # Sabotage: swapped the two datasets' budgets - red on the expectation.
    # PROVISIONAL: bundle shape is ADR-0002 decision 9's amendment (PR #13).
    test "ships a condition evaluated against two datasets (PROVISIONAL)" do
      assert %{datasets: datasets, expressions: expressions} = Core.Branch.fixtures()
      assert Map.keys(datasets) |> Enum.sort() == ["approved", "declined"]

      assert %{"approves" => %{"source" => "budget_remaining > amount", "expect" => expect}} =
               expressions

      assert expect == %{"approved" => true, "declined" => false}
    end
  end

  describe "core.parallel" do
    @lanes %{"lanes" => ["capture", "receipt"]}

    # Sabotage: labelled a lane with its slot name rather than its bare name
    # - red on the label, which is what an author reads.
    test "derives one any-arity slot per lane, prefixed lane_" do
      assert Core.Parallel.slots(@lanes) == [
               {"lane_capture", :any, "capture"},
               {"lane_receipt", :any, "receipt"}
             ]

      assert Core.Parallel.slots(%{}) == []
    end

    # Sabotage: accepted `"Bad Name"` as a lane - red, and it would have
    # made a slot name no document could round-trip cleanly.
    test "reports lane names that are not bare identifiers, and duplicates" do
      assert Core.Parallel.validate_config(@lanes) == :ok
      assert Core.Parallel.validate_config(%{}) == :ok

      assert {:error, [{"lanes", _}]} = Core.Parallel.validate_config(%{"lanes" => 5})
      assert {:error, [{"lanes", _}]} = Core.Parallel.validate_config(%{"lanes" => ["Bad Name"]})
      assert {:error, [{"lanes", _}]} = Core.Parallel.validate_config(%{"lanes" => [1]})

      assert {:error, [{"lanes", message}]} =
               Core.Parallel.validate_config(%{"lanes" => ["capture", "capture"]})

      assert message =~ "capture"
    end

    # Sabotage: changed `layout` to `:stack` - red, and the lanes would
    # render as if they were ordered (ADR-0005 decision 10).
    test "renders as columns and produces nothing knowable" do
      assert Core.Parallel.palette_entry().layout == :columns
      assert %{produces: :unknown, slot_accepts: accepts} = Core.Parallel.io(@lanes)
      assert accepts == %{"lane_capture" => [:step], "lane_receipt" => [:step]}
    end
  end
end
