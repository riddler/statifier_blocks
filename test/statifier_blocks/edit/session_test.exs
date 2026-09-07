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
        _refused -> {:error, %{"label" => "must be a string"}}
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
end
