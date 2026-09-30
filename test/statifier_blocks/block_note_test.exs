defmodule StatifierBlocks.BlockNoteTest do
  # A block's optional author-written note (ADR-0001's Amendment of
  # 2026-09-28, 2a to 2f): decode admits it, canonical form keeps a non-empty one and
  # omits an empty one, the shipped schema describes it, it moves with its
  # block, and the compiler and the provenance map never read it.
  use ExUnit.Case, async: true

  alias StatifierBlocks.{
    Block,
    Compiler,
    Describe,
    Document,
    DocumentFixtures,
    Edit,
    Palette,
    Schema,
    ViewModel
  }

  alias StatifierBlocks.Edit.History
  alias StatifierBlocks.Map, as: BlockMap
  alias StatifierBlocks.Map.Info

  @note "Sent once the patron submits the form; the desk resends by hand."

  defp palette, do: Palette.new(Palette.core_types())

  # The patron registration document with `note` on the deadline send.
  defp with_note(note) do
    DocumentFixtures.patron_registration()
    |> update_block("blk_PDLN", &%{&1 | note: note})
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

  defp find(%Document{} = document, id),
    do: Enum.find(Document.blocks(document), &(&1.id == id))

  defp schema, do: ExJsonSchema.Schema.resolve(JSON.decode!(Schema.json()))

  # The patron registration bytes with one member spliced into the
  # deadline send's object, ahead of its first key.
  defp json_with_pdln_member(member) do
    String.replace(
      DocumentFixtures.patron_registration_json(),
      ~s({"config":{"delay":"24h"),
      ~s({#{member},"config":{"delay":"24h")
    )
  end

  describe "a document with a note on a block" do
    # Sabotage: dropped "note" from `Decode`'s @block_keys -> the decode is
    # refused as an unexpected key -> red.
    test "decodes, and the note is on the block" do
      json = Document.to_json(with_note(@note))

      assert {:ok, document} = Document.from_json(json)
      assert find(document, "blk_PDLN").note == @note
      assert document == with_note(@note)
    end

    # Sabotage: `CanonicalJson.maybe_put_note/2`'s last clause returning
    # `pairs` (the note never written) -> the note is missing from the
    # bytes -> red.
    test "round-trips through canonical form byte-stable, the note in key order" do
      json = Document.to_json(with_note(@note))

      assert json =~ ~s("id":"blk_PDLN","note":"#{@note}","type":"core.send")
      assert {:ok, decoded} = Document.from_json(json)
      assert Document.to_json(decoded) == json
    end

    # Sabotage: the schema's block "note" property deleted (block keeps
    # "additionalProperties": false) -> the canonical bytes are refused -> red.
    test "validates against the shipped schema" do
      json = Document.to_json(with_note(@note))

      assert ExJsonSchema.Validator.validate(schema(), JSON.decode!(json)) == :ok
    end

    # Sabotage: in `Compiler.compile/3`, appended every block's `note` to
    # the compiled SCXML -> the SCXML differs -> red.
    test "compiles to the same SCXML and provenance map as without the note" do
      {:ok, plain} = Compiler.compile(DocumentFixtures.patron_registration(), palette())
      {:ok, noted} = Compiler.compile(with_note(@note), palette())

      assert noted.scxml == plain.scxml
      assert noted.provenance == plain.provenance
      assert noted.record.chart_identity == plain.record.chart_identity
    end

    # Sabotage: `CanonicalJson.maybe_put_note/2` omitting every note -> the
    # two hashes are equal -> red.
    test "changes the document hash, and the compile record's document hash with it" do
      plain = DocumentFixtures.patron_registration()
      noted = with_note(@note)

      refute Document.content_hash(noted) == Document.content_hash(plain)

      {:ok, compiled} = Compiler.compile(noted, palette())
      assert compiled.record.document_hash == Document.content_hash(noted)
    end
  end

  describe "an empty note" do
    # Sabotage: removed `maybe_put_note/2`'s `""` clause -> `"note":""` is
    # written -> red.
    test "is omitted from canonical form" do
      plain_json = DocumentFixtures.patron_registration_json()

      assert Document.to_json(with_note("")) == plain_json
      refute plain_json =~ ~s("note")
    end

    # Sabotage: in `Decode.build_block/1`, `Map.get(map, "note")` with no
    # default -> an absent note decodes to nil and is refused -> red.
    test "is what an absent note decodes to, so the two round-trip as one" do
      assert {:ok, document} = Document.from_json(DocumentFixtures.patron_registration_json())
      assert find(document, "blk_PDLN").note == ""
      assert document == DocumentFixtures.patron_registration()
    end

    # Sabotage: `Validation.check_note/2` refusing `""` -> the decode is
    # refused -> red.
    test "decodes, and re-encodes without the key" do
      json = json_with_pdln_member(~s("note":""))

      assert {:ok, document} = Document.from_json(json)
      assert document == DocumentFixtures.patron_registration()
      assert Document.to_json(document) == DocumentFixtures.patron_registration_json()
    end
  end

  describe "a non-string note is refused" do
    # Sabotage: `Validation.check_note/2` returning `:ok` for every value
    # -> the integer decodes -> red.
    test "an integer, a list, an object and a boolean, by decode" do
      for value <- [~s(5), ~s(["a"]), ~s({"a":1}), ~s(true)] do
        json = json_with_pdln_member(~s("note":#{value}))

        assert Document.from_json(json) ==
                 {:error, {:malformed_block, "blk_PDLN", {:note, :not_a_string}}},
               value
      end
    end

    # Sabotage: `Validation.check_note/2` given a `nil` clause returning
    # `:ok` -> an explicit null decodes -> red.
    test "an explicit null, distinctly from an absent note" do
      json = json_with_pdln_member(~s("note":null))

      assert Document.from_json(json) ==
               {:error, {:malformed_block, "blk_PDLN", {:note, :not_a_string}}}
    end

    # Sabotage: `Validation.check_note/2` accepting any binary (dropped the
    # `String.valid?/1`) -> the invalid bytes validate -> red.
    test "an integer or invalid UTF-8 on a block built in code, by validate" do
      for value <- [5, nil, <<0xFF>>] do
        assert Document.validate(with_note(value)) ==
                 {:error, {:malformed_block, "blk_PDLN", {:note, :not_a_string}}}
      end
    end
  end

  describe "a block term stored before the note field existed" do
    # The patron registration document as a host could have kept it outside
    # JSON before blocks had a note: every `%Block{}` in it lacks the
    # `:note` key, and it comes back through `:erlang.binary_to_term/1`.
    defp old_shape(%Document{root: root} = document) do
      %{document | root: strip_note(root)}
      |> :erlang.term_to_binary()
      |> :erlang.binary_to_term()
    end

    defp strip_note(%Block{slots: slots} = block) do
      block
      |> Map.delete(:note)
      |> Map.put(
        :slots,
        Map.new(slots, fn {name, children} -> {name, Enum.map(children, &strip_note/1)} end)
      )
    end

    # Sabotage: `CanonicalJson`'s `%Block{}` clause defaulting a missing
    # note to "x" rather than "" -> the old term gains a note -> red.
    test "encodes to the same bytes as the note-free document" do
      document = DocumentFixtures.patron_registration()
      old = old_shape(document)

      refute Map.has_key?(old.root, :note)
      assert Document.to_json(old) == Document.to_json(document)
    end

    # Sabotage: `Validation`'s `stored_note/1` defaulting a missing note to
    # `nil` rather than "" -> the old term is refused -> red.
    test "validates as the note-free document" do
      old = old_shape(DocumentFixtures.patron_registration())

      refute Map.has_key?(find(old, "blk_PDLN"), :note)
      assert Document.validate(old) == :ok
    end

    # Sabotage: `Edit.apply/2`'s `:update_note` clause defaulting a missing
    # note to "x" rather than "" -> the inverse carries "x" -> red.
    test "takes a note, and the inverse carries the empty note back" do
      document = DocumentFixtures.patron_registration()
      old = old_shape(document)

      assert {:ok, noted, inverse} = Edit.apply(old, {:update_note, "blk_PDLN", @note})
      assert find(noted, "blk_PDLN").note == @note
      assert inverse == {:update_note, "blk_PDLN", ""}

      assert {:ok, undone, {:update_note, "blk_PDLN", @note}} = Edit.apply(noted, inverse)
      assert find(undone, "blk_PDLN").note == ""
      assert Document.to_json(undone) == Document.to_json(document)
    end

    # Sabotage: the clause writing `Map.put(block, :note, "")` whatever the
    # note -> the committed block has no note -> red.
    test "undo and redo round-trip a note through Edit.History" do
      palette = Palette.core()
      old = old_shape(DocumentFixtures.patron_registration())

      assert {:ok, history, noted} =
               History.commit(History.new(), palette, old, {:update_note, "blk_PDLN", @note})

      assert find(noted, "blk_PDLN").note == @note

      assert {:ok, history, undone} = History.undo(history, palette, noted)
      assert find(undone, "blk_PDLN").note == ""
      assert Document.to_json(undone) == Document.to_json(old)

      assert {:ok, _history, redone} = History.redo(history, palette, undone)
      assert redone == noted
    end

    # Sabotage: `Map.Info`'s private `notes/1` defaulting a missing note to
    # "x" rather than "" -> every old block describes a note -> red.
    test "describes on the Map as the note-free document" do
      document = DocumentFixtures.patron_registration()
      old = old_shape(document)

      refute Map.has_key?(find(old, "blk_PDLN"), :note)
      assert described(old) == described(document)
      assert Enum.all?(described(old), &(&1.note == nil))
    end
  end

  # The Map's description of every element, as `StatifierBlocks.Map.Info`
  # answers it for a document.
  defp described(%Document{} = document) do
    palette = Palette.core()
    view_model = ViewModel.build(document, palette, [])
    graph = BlockMap.graph(view_model, [])
    outline = Describe.outline(document, palette, [])
    Info.elements(document, graph, view_model, outline, palette, [])
  end

  describe "copy and move" do
    # Sabotage: `Block.new/2` building the struct with `note: ""` whatever
    # the options -> the note is lost -> red.
    test "Block.new/2 takes a note, and a copy of the struct keeps it" do
      block = Block.new("core.await", id: "blk_PVER", note: @note)
      copy = %{block | id: "blk_PVER2"}

      assert block.note == @note
      assert copy.note == @note
      assert Block.new("core.await").note == ""
    end

    # Sabotage: in `Edit.apply/2`'s `:move` clause, inserted
    # `%{detached | note: ""}` -> the moved block loses its note -> red.
    test "a moved block keeps its note, and the undo keeps it too" do
      document = with_note(@note)

      assert {:ok, moved, inverse} =
               Edit.apply(document, {:move, "blk_PDLN", {"blk_PGRP", "body", 1}})

      assert find(moved, "blk_PDLN").note == @note
      assert {:ok, ^document, _inverse} = Edit.apply(moved, inverse)
    end
  end
end
