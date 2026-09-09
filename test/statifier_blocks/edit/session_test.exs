defmodule StatifierBlocks.Edit.SessionTest do
  @moduledoc """
  The commit funnel as a value: `commit/2`, `change_config/3`, `step/2`,
  `update_list/4` and `apply_gesture/2` over a document, a history and the
  drafts, with no socket in the picture.

  What is asserted here is the decision each one carries - which refusal
  becomes a draft, which becomes a `last_error`, which gesture moves the
  document and which does not - because those are the decisions a host
  re-implements when the package keeps them private.

  A pure test. Nothing here names LiveView, so it compiles and runs headless.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Document, Palette}
  alias StatifierBlocks.Edit.{History, Session}
  alias StatifierBlocks.ViewModel.Field

  doctest StatifierBlocks.Edit.Session

  defmodule Listed do
    @moduledoc """
    A leaf carrying one list of strings and one required label, so a config
    the document refuses and a list the gesture edits sit on the same block.
    """

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config) do
      [
        %{key: "label", type: :string, label: "Label", required?: true, default: ""},
        %{key: "tags", type: {:list, :string}, label: "Tags", required?: false, default: []}
      ]
    end

    @impl true
    def validate_config(config) do
      case Map.get(config, "label") do
        label when is_binary(label) -> :ok
        _refused -> {:error, [{"label", "must be a string"}]}
      end
    end

    @impl true
    def io(_config), do: %{kinds: [:step]}

    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defp palette do
    Palette.new(Map.put(Palette.core_types(), "myapp.listed", Listed))
  end

  defp document do
    listed =
      Block.new("myapp.listed",
        id: "blk_LIST",
        config: %{"label" => "Tag them", "tags" => ["a"]}
      )

    Document.new(Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [listed]}),
      id: "bdoc_session"
    )
  end

  defp session do
    %Session{palette: palette(), document: document(), history: History.new()}
  end

  defp tags_field(value) do
    %Field{
      key: "tags",
      type: {:list, :string},
      label: "Tags",
      required?: false,
      default: [],
      value: value
    }
  end

  defp tags(session), do: Document.committed_config(session.document, "blk_LIST")["tags"]

  describe "commit/2" do
    # Sabotage: `commit/2` answering `{:ok, session}` on the error branch -
    # a refusal would then be reported to the host as a change.
    test "a command the gate takes moves the document, the history and nothing else" do
      assert {:ok, moved} = Session.commit(session(), {:remove, "blk_LIST"})

      assert Enum.map(Document.blocks(moved.document), & &1.id) == ["blk_ROOT"]
      assert History.can_undo?(moved.history)
      assert moved.drafts == %{}
      assert moved.last_error == nil
    end

    # Sabotage: putting the refusal in `drafts` rather than `last_error` -
    # a refusal with no config to hold would be keyed by nothing.
    test "a command the gate refuses lands in last_error and moves nothing" do
      before = session()

      assert {:error, refused} = Session.commit(before, {:remove, "blk_NOPE"})

      assert refused.document == before.document
      assert refused.history == before.history
      assert refused.last_error == {:no_such_block, "blk_NOPE"}
    end

    # Sabotage: `commit/2` clearing `drafts` on the way through - a draft
    # held on one block would vanish when another block was moved.
    test "drafts are untouched: a command is not a statement about a refused config" do
      {:error, drafted} = Session.change_config(session(), "blk_LIST", %{"label" => 42})

      assert {:ok, moved} = Session.commit(drafted, {:remove, "blk_LIST"})
      assert Map.keys(moved.drafts) == ["blk_LIST"]
    end
  end

  describe "change_config/3" do
    # Sabotage: the `{:invalid_config, id, _}` arm falling through to
    # `last_error` - the author's keystrokes are dropped, which is the
    # decision ADR-0005 decision 9 made the other way.
    test "a config the document refuses is held as that block's draft" do
      assert {:error, drafted} = Session.change_config(session(), "blk_LIST", %{"label" => 42})

      assert drafted.drafts == %{"blk_LIST" => %{"label" => 42}}
      assert drafted.last_error == nil
      assert drafted.document == document()
    end

    # Sabotage: the success arm keeping the draft - the form would go on
    # showing a refused value the author has already fixed.
    test "a config the document takes clears that block's draft" do
      {:error, drafted} = Session.change_config(session(), "blk_LIST", %{"label" => 42})

      assert {:ok, cleared} =
               Session.change_config(drafted, "blk_LIST", %{"label" => "ok", "tags" => []})

      assert cleared.drafts == %{}
      assert Document.committed_config(cleared.document, "blk_LIST")["label"] == "ok"
    end

    # Sabotage: matching `_findings` on the `{:invalid_config, id, _}` arm
    # again - the sentences the gate already stated are thrown away, and the
    # only way back to them is the `validate_config/1` call the funnel has
    # just made.
    test "the findings the refusal carried are kept beside the draft" do
      assert {:error, drafted} = Session.change_config(session(), "blk_LIST", %{"label" => 42})

      assert drafted.draft_findings == %{"blk_LIST" => [{"label", "must be a string"}]}
    end

    # Sabotage: the success arm deleting the draft and keeping the findings -
    # the form draws a sentence about a value the author has already fixed.
    test "a config the document takes clears that block's findings too" do
      {:error, drafted} = Session.change_config(session(), "blk_LIST", %{"label" => 42})

      assert {:ok, cleared} =
               Session.change_config(drafted, "blk_LIST", %{"label" => "ok", "tags" => []})

      assert cleared.draft_findings == %{}
    end

    # Sabotage: `change_config/3`'s last arm recording the refusal in
    # `drafts` rather than in `last_error` - a refusal with no config to hold
    # is keyed by nothing.
    test "a refusal that is not this block's config lands in last_error" do
      assert {:error, refused} = Session.change_config(session(), "blk_NOPE", %{"label" => "x"})

      assert refused.drafts == %{}
      assert refused.last_error == {:no_such_block, "blk_NOPE"}
    end
  end

  describe "step/2" do
    # Sabotage: `step/2` keeping the drafts - the author is shown a value
    # belonging to a document state they just stepped out of.
    test "an undo restores the document and drops every draft" do
      {:error, drafted} = Session.change_config(session(), "blk_LIST", %{"label" => 42})
      {:ok, moved} = Session.commit(drafted, {:remove, "blk_LIST"})

      assert {:ok, back} = Session.step(moved, :undo)

      assert Enum.map(Document.blocks(back.document), & &1.id) == ["blk_ROOT", "blk_LIST"]
      assert back.drafts == %{}
      assert back.draft_findings == %{}
      assert back.last_error == nil
    end

    # Sabotage: `step/2` calling `History.undo/3` for both directions.
    test "a redo puts back what the undo took" do
      {:ok, moved} = Session.commit(session(), {:remove, "blk_LIST"})
      {:ok, back} = Session.step(moved, :undo)

      assert {:ok, forward} = Session.step(back, :redo)
      assert Enum.map(Document.blocks(forward.document), & &1.id) == ["blk_ROOT"]
    end

    # Sabotage: an empty stack answering `{:ok, session}` - the host is
    # notified of a change that did not happen.
    test "an empty stack is an error carrying the history's own reason" do
      assert {:error, no_undo} = Session.step(session(), :undo)
      assert no_undo.last_error == :nothing_to_undo

      assert {:error, no_redo} = Session.step(session(), :redo)
      assert no_redo.last_error == :nothing_to_redo
    end
  end

  describe "update_list/4" do
    # Sabotage: `update_list/4` committing the rows without the surrounding
    # config - every other field on the block is blanked.
    test "an :add appends a blank member and keeps the rest of the config" do
      assert {:ok, added} = Session.update_list(session(), "blk_LIST", tags_field(["a"]), :add)

      assert tags(added) == ["a", ""]
      assert Document.committed_config(added.document, "blk_LIST")["label"] == "Tag them"
    end

    # Sabotage: `{:remove, index}` dropping the last member rather than the
    # named one.
    test "a {:remove, index} drops the member at that index" do
      {:ok, added} = Session.update_list(session(), "blk_LIST", tags_field(["a"]), :add)

      assert {:ok, removed} =
               Session.update_list(added, "blk_LIST", tags_field(["a", ""]), {:remove, 0})

      assert tags(removed) == [""]
    end

    # Sabotage: `update_list/4` reading the committed config rather than the
    # effective one - a list edit made while a draft is held is applied to
    # the document's rows and the author's other keystrokes are lost.
    test "the rows come from the effective config, so a held draft is what is edited" do
      {:error, drafted} =
        Session.change_config(session(), "blk_LIST", %{"label" => 42, "tags" => ["x"]})

      assert {:error, again} =
               Session.update_list(drafted, "blk_LIST", tags_field(["x"]), :add)

      assert again.drafts["blk_LIST"] == %{"label" => 42, "tags" => ["x", ""]}
    end

    # Sabotage: `update_list/4` writing through the field's key rather than
    # its `value_path/1` - a block type that re-homed the field writes to a
    # key nothing reads.
    test "the write goes through the field's own value_path" do
      field = %{tags_field(["a"]) | key: "tags-row", value_path: ["tags"]}

      assert {:ok, added} = Session.update_list(session(), "blk_LIST", field, :add)
      assert tags(added) == ["a", ""]
      assert Document.committed_config(added.document, "blk_LIST")["tags-row"] == nil
    end
  end

  describe "apply_gesture/2" do
    # Sabotage: `:add` appending the field's default rather than a blank.
    test "a list field appends a blank string and removes by index" do
      assert Session.apply_gesture(tags_field(["a", "b"]), :add) == ["a", "b", ""]
      assert Session.apply_gesture(tags_field(["a", "b"]), {:remove, 0}) == ["b"]
    end

    # Sabotage: `rows_of/2` wrapping a `{:type_expr, _}` string - a type
    # name becomes a nameless member.
    test "a type_expr field reads only a member list as rows" do
      inline = %{tags_field([%{"name" => "a", "type" => "string"}]) | type: {:type_expr, %{}}}
      named = %{tags_field("cards.credit_txn") | type: {:type_expr, %{}}}

      assert Session.apply_gesture(inline, :add) == [
               %{"name" => "a", "type" => "string"},
               %{"name" => "", "type" => "", "required?" => false}
             ]

      assert Session.apply_gesture(named, :add) == [
               %{"name" => "", "type" => "", "required?" => false}
             ]
    end

    # Sabotage: the descent applying the gesture at the outer list rather
    # than at the addressed member.
    test "a {path, gesture} pair descends into the member list at that path" do
      nested = %{
        tags_field([%{"name" => "outer", "type" => [%{"name" => "inner", "type" => "string"}]}])
        | type: {:type_expr, %{}}
      }

      assert Session.apply_gesture(nested, {[0], :add}) == [
               %{
                 "name" => "outer",
                 "type" => [
                   %{"name" => "inner", "type" => "string"},
                   %{"name" => "", "type" => "", "required?" => false}
                 ]
               }
             ]

      assert Session.apply_gesture(nested, {[0], {:remove, 0}}) == [
               %{"name" => "outer", "type" => []}
             ]
    end

    # Sabotage: `member_row/1` passing a non-map row through - the descent
    # then calls `Map.put/3` on a string and raises.
    test "a member that is not a map descends as a blank member" do
      nested = %{tags_field(["not a member"]) | type: {:type_expr, %{}}}

      assert Session.apply_gesture(nested, {[0], :add}) == [
               %{
                 "name" => "",
                 "required?" => false,
                 "type" => [%{"name" => "", "type" => "", "required?" => false}]
               }
             ]
    end
  end

  describe "refusal/1" do
    # Item 6 of ADR-0005's Note of 2026-09-08 rules that a refused gesture
    # renders `last_error` on the surface, and leaves the sentence to the
    # refusal's own vocabulary. The vocabulary is this module's, because
    # `last_error` is: a host driving the same funnel refuses the same
    # gestures for the same reasons, and a sentence kept in the package
    # editor would be one the host had to write again.
    #
    # Every reason a gesture can leave in `last_error` is here, one per
    # case, and each is asserted to be a sentence of its own rather than to
    # be the fallback - which is the whole claim: a refusal an author cannot
    # act on is what item 6 is about.
    #
    # Sabotage: deleted the `{:cannot_expand_root, id}` clause - red, because
    # the reason falls through to "That change was refused." and the author
    # is told that something was refused without being told what.
    for {reason, sentence} <- [
          {:nothing_to_undo, "There is nothing to undo."},
          {:nothing_to_redo, "There is nothing to redo."},
          {{:no_such_block, "blk_NOPE"}, "That block is no longer in the document."},
          {{:no_such_slot, "blk_ROOT", "rail"}, ~s(That block has no "rail" slot.)},
          {{:index_out_of_range, {"blk_ROOT", "body", 9}},
           "That position is no longer in the slot."},
          {{:would_cycle, "blk_ROOT"}, "A block cannot be moved inside itself."},
          {{:duplicate_block_id, "blk_A"}, "That change would give two blocks the same id."},
          {{:cannot_remove_root, "blk_ROOT"}, "The outermost block cannot be removed."},
          {{:invalid_config, "blk_A", []}, "Those settings were refused."},
          {{:unknown_block_type, "myapp.nope"}, ~s(The palette has no block type "myapp.nope".)},
          {{:unknown_recipe, "nope"}, ~s(The palette has no arrangement "nope".)},
          {{:recipe_out_of_reach, "authorize_with_a_deadline"},
           ~s(The arrangement "authorize_with_a_deadline" does not fit where it was placed.)},
          {{:not_a_composite, "blk_A"},
           "That block is not made of steps, so there is nothing to replace it with."},
          {{:cannot_expand_root, "blk_ROOT"},
           "The outermost block cannot be replaced with its steps."},
          {{:expansion_not_admitted, {"blk_G", "rail", 0}},
           "This slot does not accept the steps that block is made of, so nothing was replaced."},
          {{:composite_expansion_failed, "blk_GS", "duplicate local ids"},
           "That block's declaration cannot be expanded, so nothing was replaced."},
          {{:not_one_subtree, ["blk_A", "blk_B"]},
           "A step is saved from one block and everything inside it, " <>
             "and that is not what is selected."},
          {{:cannot_collapse_root, "blk_ROOT"}, "The outermost block cannot be saved as a step."},
          {{:unspellable_field, "blk_A", "deadline"},
           ~s(The setting "deadline" cannot be carried into a step.)}
        ] do
      # Sabotage: deleted the arm this case names from `refusal/1` - red,
      # because the reason falls through to the generic sentence.
      test "#{inspect(reason)} reads as its own sentence" do
        assert Session.refusal(unquote(Macro.escape(reason))) == unquote(sentence)
      end
    end

    # One refusal that is not this module's to phrase. A datamodel envelope
    # is `StatifierBlocks.Declarations.refusal/1`'s, and is handed to it
    # rather than re-phrased here, so the declarations panel and the canvas
    # say one thing about one refusal.
    #
    # Sabotage: gave the envelope its own sentence here - green until the
    # two wordings drift, which is the defect, and red the moment either
    # side is edited without the other.
    test "a datamodel envelope keeps the declarations panel's own wording" do
      reason = {:malformed_envelope, {:datamodel, {:duplicate_id, "signup"}}}

      assert Session.refusal(reason) == StatifierBlocks.Declarations.refusal(reason)
      assert Session.refusal(reason) =~ "signup"
    end

    # Sabotage: made the fallback `inspect/1` the term - red, because the
    # author is then shown a tuple, which is exactly what item 6's ruling
    # about the panel's own sentence rules out.
    test "a reason a later amendment adds falls back to the generic sentence" do
      assert Session.refusal({:something_new, "blk_A"}) == "That change was refused."
      assert Session.refusal(:nothing_recognisable) == "That change was refused."
    end
  end
end
