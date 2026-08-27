defmodule StatifierBlocks.EditTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Document, Edit}

  # A signup wizard with an A/B-tested confirmation step and two parallel
  # conversion-event lanes, built entirely from `Palette.core()` types
  # (`core.sequence`, `core.wait`, `core.branch`, `core.parallel`). `Edit`
  # takes no palette, so nothing here resolves these types against one -
  # the vocabulary is chosen only so the tree reads as a real document.
  #
  #   blk_ROOT (core.sequence)
  #     body: [blk_LANDING, blk_SIGNUP, blk_VARIANT, blk_EVENTS, blk_WELCOME]
  #
  #   blk_VARIANT (core.branch, arm "variant_a")
  #     variant_a: [blk_CTA_A]
  #     otherwise:  [blk_CTA_B]
  #
  #   blk_EVENTS (core.parallel, lanes "started"/"completed")
  #     lane_started:   [blk_EVT_START]
  #     lane_completed: [blk_EVT_DONE]
  #
  # `body` carries exactly five children, which is what the d4 edge cases
  # ("1 -> 3 of five", "3 -> 1") are stated against.
  defp signup_wizard do
    cta_a = Block.new("core.wait", id: "blk_CTA_A", config: %{"duration" => "PT1S"})
    cta_b = Block.new("core.wait", id: "blk_CTA_B", config: %{"duration" => "PT1S"})

    variant =
      Block.new("core.branch",
        id: "blk_VARIANT",
        config: %{"arms" => [%{"slot" => "variant_a", "cond" => ~s(bucket == "a")}]},
        slots: %{"variant_a" => [cta_a], "otherwise" => [cta_b]}
      )

    evt_start = Block.new("core.wait", id: "blk_EVT_START", config: %{"duration" => "PT1S"})
    evt_done = Block.new("core.wait", id: "blk_EVT_DONE", config: %{"duration" => "PT1S"})

    events =
      Block.new("core.parallel",
        id: "blk_EVENTS",
        config: %{"lanes" => ["started", "completed"]},
        slots: %{"lane_started" => [evt_start], "lane_completed" => [evt_done]}
      )

    landing = Block.new("core.wait", id: "blk_LANDING", config: %{"duration" => "PT1S"})
    signup = Block.new("core.wait", id: "blk_SIGNUP", config: %{"duration" => "PT1S"})
    welcome = Block.new("core.wait", id: "blk_WELCOME", config: %{"duration" => "PT1S"})

    root =
      Block.new("core.sequence",
        id: "blk_ROOT",
        slots: %{"body" => [landing, signup, variant, events, welcome]}
      )

    Document.new(root, id: "bdoc_SIGNUP")
  end

  defp body_ids(document) do
    document.root.slots
    |> Map.fetch!("body")
    |> Enum.map(& &1.id)
  end

  describe "apply/2 :insert" do
    # Sabotage: in `insert_child/4`, appended the new child instead of
    # splicing it at `index` (`children ++ [child]`) -> red, the new
    # `blk_NEW` landed last instead of at index 2.
    test "inserts into an existing slot at the given index" do
      document = signup_wizard()
      new_step = Block.new("core.wait", id: "blk_NEW", config: %{"duration" => "PT1S"})

      assert {:ok, updated, inverse} =
               Edit.apply(document, {:insert, {"blk_ROOT", "body", 2}, new_step})

      assert body_ids(updated) == [
               "blk_LANDING",
               "blk_SIGNUP",
               "blk_NEW",
               "blk_VARIANT",
               "blk_EVENTS",
               "blk_WELCOME"
             ]

      assert inverse == {:remove, "blk_NEW"}
      assert {:ok, ^document, _} = Edit.apply(updated, inverse)
    end

    # Sabotage: in rule 2's implementation (`insert_child/4`'s
    # `Map.get(parent.slots, slot_name, [])`), changed the default to
    # `[nil]` -> red, `Enum.split/2` blows up on the fabricated `nil`.
    test "creates a slot key the parent doesn't carry yet (rule 2)" do
      document = signup_wizard()
      confirmation = Block.new("core.wait", id: "blk_CONFIRM", config: %{"duration" => "PT1S"})

      assert {:ok, updated, {:remove, "blk_CONFIRM"}} =
               Edit.apply(document, {:insert, {"blk_WELCOME", "confirmation", 0}, confirmation})

      welcome = Enum.find(updated.root.slots["body"], &(&1.id == "blk_WELCOME"))
      assert welcome.slots == %{"confirmation" => [confirmation]}
    end

    # Sabotage: in `apply/2`'s `:insert` clause, dropped the
    # `check_no_duplicates/2` step from the `with` chain -> red, the
    # duplicate insert silently succeeded instead of erroring.
    test "refuses an id already present in the document" do
      document = signup_wizard()
      dup = Block.new("core.wait", id: "blk_LANDING", config: %{"duration" => "PT2S"})

      assert Edit.apply(document, {:insert, {"blk_ROOT", "body", 0}, dup}) ==
               {:error, {:duplicate_block_id, "blk_LANDING"}}
    end

    # Sabotage: in `check_no_duplicates/2`, walked only the inserted
    # block's own id (dropped `subtree_ids/1`'s slot recursion) -> red, a
    # duplicate two levels down in the inserted subtree went undetected.
    test "refuses a duplicate id nested inside the inserted subtree" do
      document = signup_wizard()

      nested = Block.new("core.wait", id: "blk_EVT_START", config: %{"duration" => "PT1S"})
      wrapper = Block.new("core.group", id: "blk_WRAP", slots: %{"body" => [nested]})

      assert Edit.apply(document, {:insert, {"blk_ROOT", "body", 0}, wrapper}) ==
               {:error, {:duplicate_block_id, "blk_EVT_START"}}
    end

    # Sabotage: in `check_index/4`, changed `index <= length(children)` to
    # `index < length(children)` -> red, inserting at the end index (the
    # commonest drop, appending) was refused.
    test "accepts an index equal to the slot's current length (append)" do
      document = signup_wizard()
      last = Block.new("core.wait", id: "blk_LAST", config: %{"duration" => "PT1S"})

      assert {:ok, updated, _inverse} =
               Edit.apply(document, {:insert, {"blk_ROOT", "body", 5}, last})

      assert List.last(body_ids(updated)) == "blk_LAST"
    end

    # Sabotage: in `check_index/4`, dropped the upper-bound clause entirely
    # (`is_integer(index) and index >= 0`) -> red, an index far past the
    # slot's length no longer errored.
    test "refuses an index past the slot's length" do
      document = signup_wizard()
      extra = Block.new("core.wait", id: "blk_EXTRA")

      assert Edit.apply(document, {:insert, {"blk_ROOT", "body", 99}, extra}) ==
               {:error, {:index_out_of_range, {"blk_ROOT", "body", 99}}}
    end

    # Sabotage: in `check_slot_name/2`, dropped the `slot_name != ""` half
    # of the guard -> red, an empty slot name was accepted as valid instead
    # of refused.
    test "refuses a malformed (empty) slot name" do
      document = signup_wizard()
      extra = Block.new("core.wait", id: "blk_EXTRA")

      assert Edit.apply(document, {:insert, {"blk_ROOT", "", 0}, extra}) ==
               {:error, {:no_such_slot, "blk_ROOT", ""}}
    end

    # Sabotage: in `apply/2`'s `:insert` clause, swapped `find_block/2`'s
    # argument order to `find_block(parent_id, document)` -> red, compiles
    # but the guard clause on `Document.t()` fails to match and every
    # insert raises `FunctionClauseError` instead of erroring.
    test "refuses a parent id that is not in the document" do
      document = signup_wizard()
      extra = Block.new("core.wait", id: "blk_EXTRA")

      assert Edit.apply(document, {:insert, {"blk_GHOST", "body", 0}, extra}) ==
               {:error, {:no_such_block, "blk_GHOST"}}
    end
  end

  describe "apply/2 :remove" do
    # Sabotage: in `remove_at_path/2`'s single-segment clause, used
    # `before ++ after_children ++ [detached]` when rebuilding
    # `new_children` -> red, the remaining four steps in `body` came back
    # in the wrong order.
    test "removes a block and prunes nothing when the slot still has children" do
      document = signup_wizard()

      assert {:ok, updated, inverse} = Edit.apply(document, {:remove, "blk_SIGNUP"})
      assert body_ids(updated) == ["blk_LANDING", "blk_VARIANT", "blk_EVENTS", "blk_WELCOME"]

      assert inverse ==
               {:insert, {"blk_ROOT", "body", 1}, Enum.at(document.root.slots["body"], 1)}

      assert {:ok, ^document, _} = Edit.apply(updated, inverse)
    end

    # Sabotage: in `remove_at_path/2`'s single-segment clause, changed the
    # pruning guard from `new_children == []` to `new_children == nil` ->
    # red, `otherwise` stayed in the map as `[]` instead of being deleted,
    # so canonical JSON's "empty slots are omitted" rule (ADR-0001 decision
    # 8) would be violated by this document.
    test "prunes a slot key that removal empties (rule 3)" do
      document = signup_wizard()

      assert {:ok, updated, inverse} = Edit.apply(document, {:remove, "blk_CTA_B"})

      variant = Enum.find(updated.root.slots["body"], &(&1.id == "blk_VARIANT"))
      refute Map.has_key?(variant.slots, "otherwise")
      assert {:ok, ^document, _} = Edit.apply(updated, inverse)
    end

    # Sabotage: in `apply/2`'s `:remove` clause, dropped `check_not_root/2`
    # from the `with` chain -> red, removing the root silently "succeeded"
    # and raised inside `detach/2` instead of refusing cleanly.
    test "refuses to remove the root" do
      document = signup_wizard()

      assert Edit.apply(document, {:remove, "blk_ROOT"}) ==
               {:error, {:cannot_remove_root, "blk_ROOT"}}
    end

    # Sabotage: in `find_block/2`, changed the `nil` branch to
    # `{:ok, document.root}` -> red, removing an id that isn't in the
    # document silently detached the root instead of refusing.
    test "refuses a block id that is not in the document" do
      document = signup_wizard()

      assert Edit.apply(document, {:remove, "blk_GHOST"}) ==
               {:error, {:no_such_block, "blk_GHOST"}}
    end
  end

  describe "apply/2 :move (same slot)" do
    # Sabotage: in `apply/2`'s `:move` clause, applied `check_index/4`
    # against the pre-detach `parent` instead of the post-detach one ->
    # red, moving forward within `body` landed one position too early
    # because the moved block's own old slot was still occupying an index.
    test "moves forward within the same slot: index 1 to 3 of five" do
      document = signup_wizard()

      assert {:ok, updated, inverse} =
               Edit.apply(document, {:move, "blk_SIGNUP", {"blk_ROOT", "body", 3}})

      assert body_ids(updated) == [
               "blk_LANDING",
               "blk_VARIANT",
               "blk_EVENTS",
               "blk_SIGNUP",
               "blk_WELCOME"
             ]

      assert inverse == {:move, "blk_SIGNUP", {"blk_ROOT", "body", 1}}
      assert {:ok, ^document, _} = Edit.apply(updated, inverse)
    end

    # Sabotage: in `apply/2`'s `:move` clause, reused `detach/2`'s
    # `original_target` in place of `to_target` when calling
    # `insert_child/4` -> red, a backward move inserted at the source
    # index instead of the requested destination.
    test "moves backward within the same slot: index 3 to 1" do
      document = signup_wizard()

      assert {:ok, updated, inverse} =
               Edit.apply(document, {:move, "blk_EVENTS", {"blk_ROOT", "body", 1}})

      assert body_ids(updated) == [
               "blk_LANDING",
               "blk_EVENTS",
               "blk_SIGNUP",
               "blk_VARIANT",
               "blk_WELCOME"
             ]

      assert inverse == {:move, "blk_EVENTS", {"blk_ROOT", "body", 3}}
      assert {:ok, ^document, _} = Edit.apply(updated, inverse)
    end

    # Sabotage: in `check_index/4`, changed `index <= length(children)` to
    # `index < length(children)` -> red, moving to the post-removal slot's
    # end index (the "drop at the very end" gesture) was refused.
    test "moves to the slot's end index" do
      document = signup_wizard()

      assert {:ok, updated, inverse} =
               Edit.apply(document, {:move, "blk_LANDING", {"blk_ROOT", "body", 4}})

      assert body_ids(updated) == [
               "blk_SIGNUP",
               "blk_VARIANT",
               "blk_EVENTS",
               "blk_WELCOME",
               "blk_LANDING"
             ]

      assert inverse == {:move, "blk_LANDING", {"blk_ROOT", "body", 0}}
      assert {:ok, ^document, _} = Edit.apply(updated, inverse)
    end
  end

  describe "apply/2 :move (cross slot)" do
    # Sabotage: in `apply/2`'s `:move` clause, called `find_block(document,
    # to_parent)` (the pre-detach document) instead of `find_block(without,
    # to_parent)` -> red, moving a block into its former sibling slot
    # double-counted it against the pre-removal children.
    test "moves between slots on different parents" do
      document = signup_wizard()

      assert {:ok, updated, inverse} =
               Edit.apply(document, {:move, "blk_CTA_A", {"blk_EVENTS", "lane_started", 0}})

      variant = Enum.find(updated.root.slots["body"], &(&1.id == "blk_VARIANT"))
      events = Enum.find(updated.root.slots["body"], &(&1.id == "blk_EVENTS"))

      refute Map.has_key?(variant.slots, "variant_a")
      assert Enum.map(events.slots["lane_started"], & &1.id) == ["blk_CTA_A", "blk_EVT_START"]

      assert inverse == {:move, "blk_CTA_A", {"blk_VARIANT", "variant_a", 0}}
      assert {:ok, ^document, _} = Edit.apply(updated, inverse)
    end

    # Sabotage: in `insert_child/4`, changed
    # `Map.get(parent.slots, slot_name, [])` to `Map.fetch!(parent.slots,
    # slot_name)` -> red, moving into a slot key the destination parent
    # doesn't carry yet raised `KeyError` instead of creating the key.
    test "moves into a slot the destination parent doesn't carry yet" do
      document = signup_wizard()

      assert {:ok, updated, inverse} =
               Edit.apply(document, {:move, "blk_WELCOME", {"blk_VARIANT", "confirmation", 0}})

      variant = Enum.find(updated.root.slots["body"], &(&1.id == "blk_VARIANT"))
      assert Enum.map(variant.slots["confirmation"], & &1.id) == ["blk_WELCOME"]
      assert {:ok, ^document, _} = Edit.apply(updated, inverse)
    end

    # Sabotage: in `remove_at_path/2`'s single-segment clause, changed the
    # pruning guard from `new_children == []` to `false` -> red, moving the
    # slot's only child away left `variant_a` present as `[]` instead of
    # being pruned.
    test "a move that empties its source slot prunes that slot key" do
      document = signup_wizard()

      assert {:ok, updated, inverse} =
               Edit.apply(document, {:move, "blk_CTA_A", {"blk_ROOT", "body", 0}})

      variant = Enum.find(updated.root.slots["body"], &(&1.id == "blk_VARIANT"))
      refute Map.has_key?(variant.slots, "variant_a")
      assert {:ok, ^document, _} = Edit.apply(updated, inverse)
    end
  end

  describe "apply/2 :move error arms" do
    # Sabotage: in `apply/2`'s `:move` clause, dropped `check_not_root/2`
    # from the `with` chain -> red, moving the root raised inside `detach/2`
    # instead of refusing cleanly.
    test "refuses to move the root" do
      document = signup_wizard()

      assert Edit.apply(document, {:move, "blk_ROOT", {"blk_VARIANT", "otherwise", 0}}) ==
               {:error, {:cannot_remove_root, "blk_ROOT"}}
    end

    # Sabotage: in `find_block/2`, changed the `nil` branch to
    # `{:ok, document.root}` -> red, moving an id that isn't in the
    # document treated the root as the block being moved instead of
    # refusing.
    test "refuses a moved block id that is not in the document" do
      document = signup_wizard()

      assert Edit.apply(document, {:move, "blk_GHOST", {"blk_ROOT", "body", 0}}) ==
               {:error, {:no_such_block, "blk_GHOST"}}
    end

    # Sabotage: in `check_not_cycle/2`, narrowed the check from
    # `MapSet.member?(subtree_ids(moved), to_parent)` to
    # `to_parent == moved.id` -> red, dropping a block into a *descendant*
    # of itself (not onto itself) was no longer detected.
    test "refuses a move into the dragged block's own subtree" do
      document = signup_wizard()

      assert Edit.apply(document, {:move, "blk_VARIANT", {"blk_CTA_A", "extra", 0}}) ==
               {:error, {:would_cycle, "blk_VARIANT"}}
    end

    # Sabotage: in `subtree_ids/1`, seeded the accumulator with
    # `MapSet.new([])` instead of `MapSet.new([id])` -> red, dropping a
    # block onto itself (no children needed) was no longer detected because
    # the block's own id was never a member of its own subtree set.
    test "refuses a move onto the dragged block itself" do
      document = signup_wizard()

      assert Edit.apply(document, {:move, "blk_VARIANT", {"blk_VARIANT", "extra", 0}}) ==
               {:error, {:would_cycle, "blk_VARIANT"}}
    end

    # Sabotage: in `check_slot_name/2`, dropped the `slot_name != ""` half
    # of the guard -> red, a move naming an empty destination slot was
    # accepted instead of refused.
    test "refuses a malformed destination slot name" do
      document = signup_wizard()

      assert Edit.apply(document, {:move, "blk_LANDING", {"blk_VARIANT", "", 0}}) ==
               {:error, {:no_such_slot, "blk_VARIANT", ""}}
    end

    # Sabotage: in `find_block/2`, changed the `nil` branch to
    # `{:ok, document.root}` -> red, a destination parent that isn't in
    # the (post-detach) document resolved to the root instead of refusing.
    test "refuses a destination parent id that is not in the document" do
      document = signup_wizard()

      assert Edit.apply(document, {:move, "blk_LANDING", {"blk_GHOST", "body", 0}}) ==
               {:error, {:no_such_block, "blk_GHOST"}}
    end

    # Sabotage: in `apply/2`'s `:move` clause, passed the pre-detach target
    # tuple (still naming the dragged block's own old index) to
    # `check_index/4` instead of `to_target` -> red, an out-of-range
    # destination index went unrefused.
    test "refuses an out-of-range destination index" do
      document = signup_wizard()

      assert Edit.apply(document, {:move, "blk_LANDING", {"blk_ROOT", "body", 99}}) ==
               {:error, {:index_out_of_range, {"blk_ROOT", "body", 99}}}
    end
  end

  describe "apply/2 :update_config" do
    # Sabotage: in `apply/2`'s `:update_config` clause, built the inverse
    # as `{:update_config, id, config}` (the new config) instead of
    # `block.config` -> red, undoing a config change reapplied the new
    # config instead of restoring the old one.
    test "replaces a nested block's config and inverts to the previous one" do
      document = signup_wizard()
      new_config = %{"duration" => "PT99S"}

      assert {:ok, updated, inverse} =
               Edit.apply(document, {:update_config, "blk_LANDING", new_config})

      landing = Enum.find(updated.root.slots["body"], &(&1.id == "blk_LANDING"))
      assert landing.config == new_config
      assert inverse == {:update_config, "blk_LANDING", %{"duration" => "PT1S"}}
      assert {:ok, ^document, _} = Edit.apply(updated, inverse)
    end

    # Sabotage: in `update_at_path/3`'s `path == []` clause - the one
    # place any target's config actually gets written, root or nested,
    # since recursion always bottoms out there - changed `fun.(block)` to
    # `block` (ignore the update) -> red on every `:update_config` test,
    # this one included: the root's own config came back unchanged.
    test "updates the root block's own config directly (an empty path)" do
      document = signup_wizard()

      assert {:ok, updated, inverse} =
               Edit.apply(document, {:update_config, "blk_ROOT", %{"note" => "wizard root"}})

      assert updated.root.config == %{"note" => "wizard root"}
      assert inverse == {:update_config, "blk_ROOT", %{}}
      assert {:ok, ^document, _} = Edit.apply(updated, inverse)
    end

    # Sabotage: in `find_block/2`, changed the `nil` branch to
    # `{:ok, document.root}` -> red, updating the config of an id that
    # isn't in the document silently rewrote the root's config instead of
    # refusing.
    test "refuses a block id that is not in the document" do
      document = signup_wizard()

      assert Edit.apply(document, {:update_config, "blk_GHOST", %{}}) ==
               {:error, {:no_such_block, "blk_GHOST"}}
    end
  end
end
