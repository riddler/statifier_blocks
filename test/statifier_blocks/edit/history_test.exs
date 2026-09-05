defmodule StatifierBlocks.Edit.HistoryTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Document, Palette}
  alias StatifierBlocks.Edit.History

  # A small signup wizard with an A/B-tested variant step, built from
  # `Palette.core()` types (`core.sequence`, `core.wait`, `core.branch`).
  # `blk_VARIANT`'s config is well-formed under `Core.Branch.validate_config/1`
  # (a real `"arm_..."` slot name, a real `"cond"`), which is what makes the
  # happy-path commits below actually pass the gate rather than passing it
  # vacuously.
  #
  #   blk_ROOT (core.sequence)
  #     body: [blk_LANDING, blk_VARIANT, blk_WELCOME]
  #
  #   blk_VARIANT (core.branch, arm "arm_variant_a")
  #     arm_variant_a: [blk_CTA_A]
  #     otherwise:      [blk_CTA_B]
  defp signup_wizard do
    cta_a = Block.new("core.wait", id: "blk_CTA_A", config: %{"duration" => "1s"})
    cta_b = Block.new("core.wait", id: "blk_CTA_B", config: %{"duration" => "1s"})

    variant =
      Block.new("core.branch",
        id: "blk_VARIANT",
        config: %{"arms" => [%{"slot" => "arm_variant_a", "cond" => ~s(bucket == "a")}]},
        slots: %{"arm_variant_a" => [cta_a], "otherwise" => [cta_b]}
      )

    landing = Block.new("core.wait", id: "blk_LANDING", config: %{"duration" => "1s"})
    welcome = Block.new("core.wait", id: "blk_WELCOME", config: %{"duration" => "1s"})

    root =
      Block.new("core.sequence",
        id: "blk_ROOT",
        slots: %{"body" => [landing, variant, welcome]}
      )

    Document.new(root, id: "bdoc_SIGNUP")
  end

  defp palette, do: Palette.core()

  defp body_ids(document) do
    document.root.slots |> Map.fetch!("body") |> Enum.map(& &1.id)
  end

  describe "new/1" do
    # Sabotage: in `new/1`, hardcoded `limit: 5` instead of reading the
    # `:limit` option -> red, a history built with `limit: 2` still
    # reported `limit: 5`.
    test "defaults to :infinity, honours a given :limit" do
      assert %History{undo: [], redo: [], limit: :infinity} = History.new()
      assert %History{limit: 2} = History.new(limit: 2)
    end
  end

  describe "commit/4" do
    # Sabotage: in `commit/4`, pushed `command` instead of `inverse` onto
    # the undo stack -> red, undoing the committed insert reapplied the
    # same insert instead of removing it.
    test "applies the command, pushes its inverse, clears redo" do
      document = signup_wizard()
      history = History.new()
      new_step = Block.new("core.wait", id: "blk_NEW", config: %{"duration" => "1s"})
      command = {:insert, {"blk_ROOT", "body", 0}, new_step}

      assert {:ok, history, updated} = History.commit(history, palette(), document, command)
      assert List.first(body_ids(updated)) == "blk_NEW"
      assert history.undo == [{:remove, "blk_NEW"}]
      assert history.redo == []

      assert {:ok, _history, ^document} = History.undo(history, palette(), updated)
    end

    # Sabotage: in `commit/4`, dropped the `redo: []` reset from the
    # returned struct (kept the caller's existing redo stack instead) ->
    # red, a commit made after an undo left the stale redo entry in place
    # instead of clearing it.
    test "a fresh commit clears whatever redo/3 would have replayed" do
      document = signup_wizard()
      history = History.new()
      command1 = {:update_config, "blk_LANDING", %{"duration" => "9s"}}
      command2 = {:update_config, "blk_WELCOME", %{"duration" => "8s"}}

      assert {:ok, history, doc1} = History.commit(history, palette(), document, command1)
      assert {:ok, history, _doc1_undone} = History.undo(history, palette(), doc1)
      assert history.redo != []

      assert {:ok, history, _doc2} = History.commit(history, palette(), document, command2)
      assert history.redo == []
    end

    # Sabotage: in `apply_gated/3` (the private funnel `commit/4` calls),
    # dropped the `Edit.check_config/3` step from the `with` chain and
    # called `Edit.apply/2` directly -> red, an `:update_config` carrying
    # config `Core.Branch.validate_config/1` rejects was applied to the
    # document anyway before the gate ever ran.
    test "refuses an :update_config whose config Core.Branch rejects: missing cond" do
      document = signup_wizard()
      history = History.new()

      # Well-formed slot name, but the arm carries no "cond" at all.
      bad_config = %{"arms" => [%{"slot" => "arm_variant_a"}]}
      command = {:update_config, "blk_VARIANT", bad_config}

      assert History.commit(history, palette(), document, command) ==
               {:error,
                {:invalid_config, "blk_VARIANT",
                 [{"arms", ~s(every arm needs a "slot" and a "cond")}]}}

      assert document == signup_wizard()
      assert history == History.new()
    end

    # Sabotage: same funnel bypass as above, exercised against the other
    # named acceptance case (a malformed slot name rather than a missing
    # "cond") so both of the plan's two named triggers are covered
    # independently -> red, the malformed-slot-name config also got
    # written to the document before the gate ran.
    test "refuses an :update_config whose config Core.Branch rejects: malformed slot name" do
      document = signup_wizard()
      history = History.new()

      # A "cond" is present, but the slot name doesn't look like "arm_approved".
      bad_config = %{"arms" => [%{"slot" => "not-an-arm-name", "cond" => "true"}]}
      command = {:update_config, "blk_VARIANT", bad_config}

      assert History.commit(history, palette(), document, command) ==
               {:error,
                {:invalid_config, "blk_VARIANT",
                 [{"arms", ~s(an arm's slot must look like "arm_approved")}]}}

      assert document == signup_wizard()
      assert history == History.new()
    end

    # Sabotage: in `check_config/3`'s `:update_config` clause, dropped the
    # `else` fallback (`_error -> :ok`) -> red, committing a config change
    # to a block whose type isn't in the palette let `Palette.resolve/2`'s
    # own `{:error, {:unknown_block_type, _}}` fall straight out of the
    # `with` as `check_config/3`'s return, which the funnel then rejected
    # instead of the intended `:ok` fallthrough that lets `Edit.apply/2`
    # structurally accept it.
    test "does not gate an :update_config on a block whose type does not resolve" do
      ghost = Block.new("myapp.unregistered", id: "blk_GHOST", config: %{"whatever" => true})

      root =
        Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [ghost]})

      document = Document.new(root, id: "bdoc_GHOST")
      history = History.new()

      command = {:update_config, "blk_GHOST", %{"anything" => "goes"}}

      assert {:ok, _history, updated} = History.commit(history, palette(), document, command)
      ghost_updated = Enum.find(updated.root.slots["body"], &(&1.id == "blk_GHOST"))
      assert ghost_updated.config == %{"anything" => "goes"}
    end

    # Sabotage: in `apply_gated/3`, changed the `with` to ignore
    # `Edit.apply/2`'s own error and always return the last successful
    # match -> red, inserting a duplicate id through `commit/4` silently
    # "succeeded" instead of propagating `{:error, {:duplicate_block_id,
    # _}}` unchanged.
    test "propagates Edit.apply/2's own error union unchanged" do
      document = signup_wizard()
      history = History.new()
      dup = Block.new("core.wait", id: "blk_LANDING")

      assert History.commit(history, palette(), document, {:insert, {"blk_ROOT", "body", 0}, dup}) ==
               {:error, {:duplicate_block_id, "blk_LANDING"}}
    end
  end

  describe "undo/3 and redo/3" do
    # Sabotage: in `undo/3`, pushed `command` (the popped undo entry) onto
    # redo instead of `inverse` (`Edit.apply/2`'s fresh return) -> red,
    # `redo/3` reapplied the same undo instead of restoring the original
    # forward command.
    test "round-trips a multi-command session through undo and redo" do
      original = signup_wizard()
      history = History.new()

      commands = [
        {:update_config, "blk_LANDING", %{"duration" => "2s"}},
        {:move, "blk_WELCOME", {"blk_ROOT", "body", 0}},
        {:remove, "blk_CTA_B"}
      ]

      {history, final} =
        Enum.reduce(commands, {history, original}, fn command, {history, document} ->
          {:ok, history, document} = History.commit(history, palette(), document, command)
          {history, document}
        end)

      assert length(history.undo) == 3
      assert history.redo == []

      # Undo all three, back to the original document, one step at a time.
      {history, back_to_start} =
        Enum.reduce(1..3, {history, final}, fn _step, {history, document} ->
          {:ok, history, document} = History.undo(history, palette(), document)
          {history, document}
        end)

      assert back_to_start == original
      assert history.undo == []
      assert length(history.redo) == 3

      # Redo all three, forward to the same final document.
      {history, forward_again} =
        Enum.reduce(1..3, {history, back_to_start}, fn _step, {history, document} ->
          {:ok, history, document} = History.redo(history, palette(), document)
          {history, document}
        end)

      assert forward_again == final
      assert history.redo == []
      assert length(history.undo) == 3
    end

    # Sabotage: in `undo/3`'s empty clause, changed `{:error,
    # :nothing_to_undo}` to `{:ok, history, document}` -> red, undoing an
    # empty history silently "succeeded" and handed back the document
    # unchanged instead of refusing.
    test "undo/3 on an empty stack refuses" do
      document = signup_wizard()
      assert History.undo(History.new(), palette(), document) == {:error, :nothing_to_undo}
    end

    # Sabotage: in `redo/3`'s empty clause, changed `{:error,
    # :nothing_to_redo}` to `{:ok, history, document}` -> red, redoing an
    # empty stack no longer refused.
    test "redo/3 on an empty stack refuses" do
      document = signup_wizard()
      assert History.redo(History.new(), palette(), document) == {:error, :nothing_to_redo}
    end

    # Sabotage: in `apply_gated/3` (the private funnel `undo/3` and
    # `redo/3` both call), removed the `Edit.check_config/3` step entirely
    # -> red, this test's directly-constructed history - whose undo stack
    # names an `:update_config` command that the current palette's
    # `validate_config/1` rejects - went on to apply that command instead
    # of refusing, and the document that came back carried the invalid
    # config. This is the moduledoc's "the gate runs on undo too" sentence
    # made executable: a history's undo/redo stacks are plain data, so
    # nothing stops one from naming a command that would fail the gate if
    # committed fresh, and this function must still catch it.
    test "undo/3 runs the config gate too, not only commit/4" do
      document = signup_wizard()

      bad_config = %{"arms" => [%{"slot" => "arm_variant_a"}]}
      history = %History{undo: [{:update_config, "blk_VARIANT", bad_config}], redo: []}

      assert undo_result = History.undo(history, palette(), document)

      assert {:error, {:invalid_config, "blk_VARIANT", _findings}} = undo_result
      assert history.undo == [{:update_config, "blk_VARIANT", bad_config}]
      assert history.redo == []
    end

    # Same as above, for `redo/3`'s own funnel call.
    test "redo/3 runs the config gate too, not only commit/4" do
      document = signup_wizard()

      bad_config = %{"arms" => [%{"slot" => "not-an-arm-name", "cond" => "true"}]}
      history = %History{undo: [], redo: [{:update_config, "blk_VARIANT", bad_config}]}

      assert {:error, {:invalid_config, "blk_VARIANT", _findings}} =
               History.redo(history, palette(), document)

      assert history.redo == [{:update_config, "blk_VARIANT", bad_config}]
      assert history.undo == []
    end
  end

  describe "the limit" do
    # Sabotage: in `bounded/2`, changed `Enum.take(undo, limit)` to
    # `Enum.take(undo, limit + 1)` -> red, a `limit: 2` history kept three
    # undo entries instead of two after a third commit.
    test "a bounded limit drops the oldest undo entry" do
      document = signup_wizard()
      history = History.new(limit: 2)

      commands = [
        {:update_config, "blk_LANDING", %{"duration" => "2s"}},
        {:update_config, "blk_WELCOME", %{"duration" => "3s"}},
        {:update_config, "blk_CTA_A", %{"duration" => "4s"}}
      ]

      {history, _final} =
        Enum.reduce(commands, {history, document}, fn command, {history, document} ->
          {:ok, history, document} = History.commit(history, palette(), document, command)
          {history, document}
        end)

      assert length(history.undo) == 2

      assert history.undo == [
               {:update_config, "blk_CTA_A", %{"duration" => "1s"}},
               {:update_config, "blk_WELCOME", %{"duration" => "1s"}}
             ]
    end
  end

  describe "can_undo?/1 and can_redo?/1" do
    # Sabotage: in `can_undo?/1`, swapped the two clauses (`[]` returning
    # `true`, the fallback returning `false`) -> red, a fresh empty
    # history reported `can_undo?/1 == true`.
    test "reflect whether their respective stacks are empty" do
      document = signup_wizard()
      history = History.new()

      refute History.can_undo?(history)
      refute History.can_redo?(history)

      command = {:update_config, "blk_LANDING", %{"duration" => "2s"}}
      assert {:ok, history, updated} = History.commit(history, palette(), document, command)
      assert History.can_undo?(history)
      refute History.can_redo?(history)

      assert {:ok, history, _reverted} = History.undo(history, palette(), updated)
      refute History.can_undo?(history)
      assert History.can_redo?(history)
    end
  end
end
