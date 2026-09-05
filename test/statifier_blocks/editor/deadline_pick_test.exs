# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*, which is the earlier
# of the two problems.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.DeadlinePickTest do
    @moduledoc """
    The `"deadline"` palette recipe, driven the way an author drives it:
    click a "+" and choose the entry (ADR-0005 clauses 1C-4C).

    Nothing here simulates a drag. A recipe row is a pick and only a pick -
    the drop path mints ONE block of a named type, and an arrangement is not
    one block - so the whole gesture is the keyboard-reachable path decision 8
    already guarantees.
    """

    use StatifierBlocks.EditorLiveCase

    # A group with one step in its body, and a sequence beside it that has no
    # interrupts rail at all - the two positions clause 3C tells apart.
    #
    #   blk_root (core.sequence)
    #     body: [blk_group, blk_plain]
    defp document do
      step = Block.new("core.wait", id: "blk_step", config: %{"duration" => "1s"})
      group = Block.new("core.group", id: "blk_group", slots: %{"body" => [step]})
      plain = Block.new("core.sequence", id: "blk_plain")

      Document.new(
        Block.new("core.sequence", id: "blk_root", slots: %{"body" => [group, plain]}),
        id: "bdoc_deadline"
      )
    end

    defp add_button(parent_id, slot, index) do
      ~s([data-parent-id="#{parent_id}"][data-slot="#{slot}"][data-index="#{index}"] .sb-gap__add)
    end

    defp arm(view, parent_id, slot, index) do
      view |> element(add_button(parent_id, slot, index)) |> render_click()
      view
    end

    defp pick_deadline(view) do
      view |> with_target("#editor") |> render_click("palette-pick", %{"recipe" => "deadline"})
      view
    end

    defp types_in(document, block_id, slot) do
      document
      |> Document.blocks()
      |> Enum.find(&(&1.id == block_id))
      |> Map.fetch!(:slots)
      |> Map.get(slot, [])
      |> Enum.map(& &1.type)
    end

    describe "the pick" do
      # Sabotage: `insert_from_recipe/3` committing only the head of the list
      # instead of the whole compound - the rail stays empty and the
      # `interrupts` assertion goes red while the `body` one still passes.
      test "one pick puts down both halves of the pair", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: document())

        view |> arm("blk_group", "body", 0) |> pick_deadline()

        assert %Document{} = changed = latest_document()
        assert types_in(changed, "blk_group", "body") == ["core.send", "core.wait"]
        assert types_in(changed, "blk_group", "interrupts") == ["core.on_event"]
      end

      # ADR-0010 decision 5: the two halves are coupled by an event name, and
      # the recipe is what writes it twice.
      #
      # Sabotage: the handler's config carrying the schema default `""` for
      # `event` rather than the generated name - the two names differ and this
      # goes red.
      test "the halves name the same event, and the pair compiles", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: document())

        view |> arm("blk_group", "body", 0) |> pick_deadline()

        changed = latest_document()
        blocks = Document.blocks(changed)
        timer = Enum.find(blocks, &(&1.type == "core.send"))
        handler = Enum.find(blocks, &(&1.type == "core.on_event"))

        assert timer.config["event"] == handler.config["event"]
        assert timer.config["delay"] != ""

        assert {:ok, %{warnings: []}} =
                 StatifierBlocks.Compiler.compile(changed, Palette.core())
      end

      # The palette row exists, and it is a recipe row rather than a type row:
      # it carries no `data-type` at all, because a recipe has no `type_name`
      # (clause 1C).
      #
      # Sabotage: `palette_groups/1` skipping `palette.recipes` - the row is
      # absent and every assertion here goes red.
      test "the entry draws as a row of its own kind", %{conn: conn} do
        {:ok, view, html} = mount_editor(conn, document: document())

        assert html =~ ~s(data-recipe="deadline")
        assert has_element?(view, ~s([data-recipe="deadline"] .sb-palette__pick))
        refute html =~ ~s(<li data-type="deadline")
      end
    end

    describe "the refusal (clause 3C)" do
      # Nothing is written, so there is nothing for the view model to say
      # anything about - a refused gesture is not a finding.
      #
      # Sabotage: `enclosing_group/2` answering `{:ok, block}` for any block -
      # the sequence takes the pair, a document reaches the host, and the
      # `nil` assertion goes red.
      test "a position with no interrupts rail writes nothing at all", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: document())

        view |> arm("blk_plain", "body", 0) |> pick_deadline()

        assert latest_document() == nil, "the document never moved"
      end
    end

    describe "undo and redo (clause 2n)" do
      # The property the compound constructor exists for. Two commits would
      # leave the author one undo away from a document that compiles to a
      # chart abandoning on an event no handler answers.
      #
      # Sabotage: `Edit.History.commit/4` pushing one entry per leaf - the
      # first undo leaves the send behind and the "both gone" assertion goes
      # red.
      test "one undo removes both halves, and one redo restores both", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: document())

        view |> arm("blk_group", "body", 0) |> pick_deadline()
        assert %Document{} = latest_document()

        view |> with_target("#editor") |> render_click("undo", %{})
        undone = latest_document()

        assert types_in(undone, "blk_group", "body") == ["core.wait"]
        assert types_in(undone, "blk_group", "interrupts") == []

        view |> with_target("#editor") |> render_click("redo", %{})
        redone = latest_document()

        assert types_in(redone, "blk_group", "body") == ["core.send", "core.wait"]
        assert types_in(redone, "blk_group", "interrupts") == ["core.on_event"]
      end
    end
  end
end
