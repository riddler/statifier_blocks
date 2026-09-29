defmodule StatifierBlocks.Edit.NoteTest do
  # The note command (ADR-0005's Amendment of 2026-09-29, 2s): decision 2's
  # closed set gains `{:update_note, id, note}`, whose inverse is the note
  # that was there before. It goes through `Edit.apply/2` and `Edit.History`
  # like every other edit, `check_config/3` asks no block type about it, and
  # a recipe may write it only on a block its own compound inserted.
  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Document, DocumentFixtures, Edit, Palette, Recipe}
  alias StatifierBlocks.Edit.History

  @note "Sent once the patron submits the form; the desk resends by hand."

  defp find(%Document{} = document, id),
    do: Enum.find(Document.blocks(document), &(&1.id == id))

  defp noted(note) do
    {:ok, document, _inverse} =
      Edit.apply(DocumentFixtures.patron_registration(), {:update_note, "blk_PDLN", note})

    document
  end

  describe "Edit.apply/2" do
    # Sabotage: the clause's inverse built from `note` instead of
    # `block.note` - the inverse carries the new note, so undo re-applies it.
    test "answers the new document and the inverse carrying the previous note" do
      document = DocumentFixtures.patron_registration()

      assert {:ok, updated, inverse} = Edit.apply(document, {:update_note, "blk_PDLN", @note})

      assert find(updated, "blk_PDLN").note == @note
      assert inverse == {:update_note, "blk_PDLN", ""}
      assert {:ok, ^document, {:update_note, "blk_PDLN", @note}} = Edit.apply(updated, inverse)
    end

    # Sabotage: the clause writing the note onto the document root rather
    # than onto the block `id` names - the named block keeps its old note.
    test "writes the note on the named block and on no other" do
      updated = noted(@note)

      assert find(updated, "blk_PDLN").note == @note

      assert updated
             |> Document.blocks()
             |> Enum.reject(&(&1.id == "blk_PDLN"))
             |> Enum.all?(&(&1.note == ""))
    end

    # Sabotage: `CanonicalJson.maybe_put_note/2`'s `""` clause removed, so an
    # emptied note is written as `"note":""` - the bytes differ from the
    # never-noted document's and the first assertion goes red.
    test "an empty note is the absent note, omitted from canonical form" do
      original = DocumentFixtures.patron_registration()

      assert {:ok, cleared, {:update_note, "blk_PDLN", @note}} =
               Edit.apply(noted(@note), {:update_note, "blk_PDLN", ""})

      assert Document.to_json(cleared) == Document.to_json(original)
      refute Document.to_json(cleared) =~ ~s("note")
      assert cleared == original
    end

    # Sabotage: the clause writing `String.trim(note)` - the surrounding
    # whitespace is dropped and the stored note is not what the author wrote.
    test "stores the note as written, whitespace included" do
      assert find(noted("  two spaces\nand a line  "), "blk_PDLN").note ==
               "  two spaces\nand a line  "
    end

    # Sabotage: the clause answering a lookup miss with a term of its own
    # (`{:error, :gone}`) rather than `find_block/2`'s `{:no_such_block, id}`.
    test "refuses a block the document does not hold" do
      assert Edit.apply(DocumentFixtures.patron_registration(), {:update_note, "blk_NOPE", @note}) ==
               {:error, {:no_such_block, "blk_NOPE"}}
    end

    # Sabotage: the clause skipping `Validation.note/2` - the non-string is
    # written onto the block and `{:ok, _, _}` is answered.
    test "refuses a note that is not a string, in the term validate/1 answers" do
      document = DocumentFixtures.patron_registration()

      assert Edit.apply(document, {:update_note, "blk_PDLN", nil}) ==
               {:error, {:malformed_block, "blk_PDLN", {:note, :not_a_string}}}

      assert Edit.apply(document, {:update_note, "blk_PDLN", <<0xFF>>}) ==
               {:error, {:malformed_block, "blk_PDLN", {:note, :not_a_string}}}

      bad = %{document | root: %{document.root | note: nil}}

      assert {:error, {:malformed_block, _id, {:note, :not_a_string}}} = Document.validate(bad)
    end

    # Sabotage: `check_compound/1` refusing a list holding an `:update_note`
    # - the compound is refused and the two notes are never written.
    test "is one leaf of a compound like any other command, one inverse per leaf" do
      document = DocumentFixtures.patron_registration()

      assert {:ok, updated, inverse} =
               Edit.apply(
                 document,
                 {:compound,
                  [{:update_note, "blk_PDLN", "first"}, {:update_note, "blk_PDLN", "second"}]}
               )

      assert find(updated, "blk_PDLN").note == "second"

      assert inverse ==
               {:compound, [{:update_note, "blk_PDLN", "first"}, {:update_note, "blk_PDLN", ""}]}

      assert {:ok, ^document, _forward} = Edit.apply(updated, inverse)
    end
  end

  describe "Edit.History" do
    # Sabotage: `apply/2`'s inverse built from `note` instead of
    # `block.note` - undo leaves the note in place and the second assertion
    # goes red.
    test "undo and redo round-trip a note" do
      palette = Palette.core()
      document = DocumentFixtures.patron_registration()

      assert {:ok, history, noted} =
               History.commit(History.new(), palette, document, {:update_note, "blk_PDLN", @note})

      assert find(noted, "blk_PDLN").note == @note

      assert {:ok, history, undone} = History.undo(history, palette, noted)
      assert undone == document

      assert {:ok, _history, redone} = History.redo(history, palette, undone)
      assert redone == noted
    end

    # Sabotage: as above - with the inverse carrying the new note, undoing
    # the second edit lands on the second note instead of the first.
    test "undo steps back through two notes one at a time" do
      palette = Palette.core()
      document = DocumentFixtures.patron_registration()

      {:ok, history, first} =
        History.commit(History.new(), palette, document, {:update_note, "blk_PDLN", "first"})

      {:ok, history, second} =
        History.commit(history, palette, first, {:update_note, "blk_PDLN", "second"})

      assert find(second, "blk_PDLN").note == "second"

      {:ok, history, back_one} = History.undo(history, palette, second)
      assert find(back_one, "blk_PDLN").note == "first"

      {:ok, _history, back_two} = History.undo(history, palette, back_one)
      assert find(back_two, "blk_PDLN").note == ""
    end
  end

  describe "Edit.check_config/3" do
    # The deliberate clause: a note is not config, so no block type is asked
    # - not even on a block whose stored config its type refuses, where a
    # gate that asked would refuse the note for a reason the note is not.
    #
    # Sabotage: the clause routed through the `:update_config` gate with the
    # block's stored config (`check_config(palette, document, {:update_config,
    # id, block.config})`) - the stored config is refused and the note with it.
    test "answers :ok without asking the block type, even over a refused config" do
      palette = Palette.core()
      bad_config = %{"event" => "registration.deadline", "delay" => 42}

      document =
        update_block(
          DocumentFixtures.patron_registration(),
          "blk_PDLN",
          &%{&1 | config: bad_config}
        )

      assert {:error, {:invalid_config, "blk_PDLN", [_ | _]}} =
               Edit.check_config(palette, document, {:update_config, "blk_PDLN", bad_config})

      assert Edit.check_config(palette, document, {:update_note, "blk_PDLN", @note}) == :ok
      assert Edit.check_config(palette, document, {:update_note, "blk_NOPE", @note}) == :ok

      assert {:ok, _history, noted} =
               History.commit(History.new(), palette, document, {:update_note, "blk_PDLN", @note})

      assert find(noted, "blk_PDLN").note == @note
    end
  end

  describe "Recipe.within_reach?/2" do
    @target {"blk_g", "body", 0}

    # The deliberate clause: a note is bounded like a config - a recipe may
    # write the note of a block its own compound inserted, and nothing else.
    #
    # Sabotage: the `{:update_note, id, _note}` clause of the private
    # `reach/3` answering `{:cont, minted}` for every id (admitted anywhere,
    # as a declaration is) - the note on the block already there is then in
    # reach and the refutation goes red.
    test "admits a note on a block the compound inserted, and refuses any other" do
      inserted = Block.new("core.send", id: "blk_A")

      assert Recipe.within_reach?(@target, [
               {:insert, @target, inserted},
               {:update_note, "blk_A", @note}
             ])

      refute Recipe.within_reach?(@target, [{:update_note, "blk_elsewhere", @note}])

      refute Recipe.within_reach?(@target, [
               {:update_note, "blk_A", @note},
               {:insert, @target, inserted}
             ])
    end
  end

  defp update_block(%Document{root: root} = document, id, fun),
    do: %{document | root: update_tree(root, id, fun)}

  defp update_tree(%Block{id: id} = block, id, fun), do: fun.(block)

  defp update_tree(%Block{slots: slots} = block, id, fun) do
    %{
      block
      | slots:
          Map.new(slots, fn {name, children} ->
            {name, Enum.map(children, &update_tree(&1, id, fun))}
          end)
    }
  end
end
