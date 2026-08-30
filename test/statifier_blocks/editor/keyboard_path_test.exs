# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*, which is the earlier
# of the two problems.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.KeyboardPathTest do
    @moduledoc """
    ADR-0005 decision 8: every drop target is reachable without dragging.

    These tests never simulate a drag. They click a "+" and choose a palette
    entry, and assert the document that results - which is the point of the
    decision twice over. It is an accessibility affordance, drag-and-drop being
    unusable by keyboard and hostile on touch; and it is what makes the whole
    insertion path exercisable in `LiveViewTest` at all, because clicking a "+"
    and choosing a type produces the identical command a successful drop would.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.Edit.Targets

    defp add_button(parent_id, slot, index) do
      ~s([data-parent-id="#{parent_id}"][data-slot="#{slot}"][data-index="#{index}"] .sb-gap__add)
    end

    describe "the + button" do
      # Sabotage: rendering the gap's "+" only when a drag session is open -
      # the button is then absent on a freshly mounted view and this goes red.
      test "every gap in every slot carries one, with no drag in progress", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        # Three children in the wizard's body means four gaps, not three.
        for index <- 0..3 do
          assert has_element?(view, add_button("blk_wizard", "body", index))
        end

        assert has_element?(view, add_button("blk_variant", "otherwise", 0))

        assert has_element?(view, add_button("blk_track_conversion", "after", 0)),
               "an unresolvable block's existing slots still render their gaps (d12)"
      end

      # Sabotage: `Editor.accepted_types/3` returning every type name rather
      # than filtering - `core.branch` then appears in a palette opened from a
      # slot that does not accept it.
      test "opening it filters the palette by the same predicate a drag uses", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        html = view |> element(add_button("blk_wizard", "body", 0)) |> render_click()

        assert html =~ ~s(data-filtered="true")

        offered =
          ~r/<li data-type="([^"]+)">/
          |> Regex.scan(html)
          |> MapSet.new(fn [_all, type] -> type end)

        document = EditorFixtures.signup_wizard()
        palette = EditorFixtures.palette()

        expected =
          palette.types
          |> Map.keys()
          |> Enum.filter(fn type ->
            probe = Block.new(type, config: default_config(palette, type))
            {"blk_wizard", "body"} in Targets.droppable_slots_for(document, palette, probe)
          end)
          |> MapSet.new()

        assert offered == expected
        refute offered == MapSet.new(Map.keys(palette.types)), "the filter did something"
      end

      # Sabotage: `Editor.insert_from_palette/3` ignoring the stored position
      # and appending instead - the new block lands last and the order assertion
      # goes red.
      test "picking an entry inserts at exactly the position the + named", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        view |> element(add_button("blk_wizard", "body", 0)) |> render_click()
        view |> element(~s(.sb-palette__pick[phx-value-type="core.wait"])) |> render_click()

        document = latest_document()
        [first | rest] = body_ids(document)

        assert rest == ["blk_email_step", "blk_variant", "blk_track_conversion"]
        assert first != "blk_email_step"

        inserted = Enum.find(Document.blocks(document), &(&1.id == first))
        assert inserted.type == "core.wait"

        assert inserted.config == %{"duration" => "1h"},
               "a new block starts from its schema's declared defaults"
      end

      # Sabotage: minting the inserted block with a fixed id - inserting twice
      # then produces a duplicate id, which `Edit.apply/2` refuses, and the
      # second insert never lands.
      test "each insertion mints its own id, so two are two blocks", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        view |> element(add_button("blk_wizard", "body", 0)) |> render_click()
        view |> element(~s(.sb-palette__pick[phx-value-type="core.wait"])) |> render_click()

        view |> element(add_button("blk_wizard", "body", 0)) |> render_click()
        view |> element(~s(.sb-palette__pick[phx-value-type="core.wait"])) |> render_click()

        ids = body_ids(latest_document())

        assert length(ids) == 5
        assert length(Enum.uniq(ids)) == 5
      end

      # Sabotage: leaving `palette_position` set after a pick - the palette
      # stays filtered and the unfiltered assertion goes red.
      test "the palette returns to unfiltered after the insert", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        view |> element(add_button("blk_wizard", "body", 0)) |> render_click()

        html =
          view |> element(~s(.sb-palette__pick[phx-value-type="core.wait"])) |> render_click()

        assert html =~ ~s(data-filtered="false")
      end

      # The selector names the PALETTE's cancel, which since sb-lti6 is the
      # only one: the toolbar's "Cancel insert" carried the same event from a
      # second pane, and one command with two buttons is a command an author
      # has to work out twice. `element/2` raises on more than one match, so
      # this selector going ambiguous again is itself a failure.
      # Sabotage: "palette-close" clearing `palette_allowed` but not
      # `palette_position` - a later pick would then still insert, and the
      # document would change where this expects it not to.
      test "cancelling an insert inserts nothing", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        view |> element(add_button("blk_wizard", "body", 0)) |> render_click()

        html =
          view
          |> element(~s(.sb-palette__cancel[phx-click="palette-close"]))
          |> render_click()

        assert html =~ ~s(data-filtered="false")

        view |> element(~s(.sb-palette__pick[phx-value-type="core.wait"])) |> render_click()

        refute latest_document(), "no position, no insert"
      end

      # sb-lti6. The insert mode used to announce its exit twice - once beside
      # the sentence that explains the mode, and once in the toolbar above the
      # canvas - and the two were the same event with two labels. Counted on
      # the rendered page rather than read off the components, because "how
      # many ways out does an author see" is a question about the page.
      # Sabotage: restoring the toolbar's Cancel button - re-declare the insert
      # attr sb-9t19 removed from the toolbar, pass it from the editor, and
      # render a second `palette-close` control behind it. The count goes to
      # two and this names both.
      test "the insert mode offers exactly one Cancel", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        html = view |> element(add_button("blk_wizard", "body", 0)) |> render_click()

        assert html =~ ~s(data-inserting="true")

        cancels = Regex.scan(~r/phx-click="palette-close"/, html)

        assert length(cancels) == 1, """
        One command, one button. The palette's Cancel is the one that survives
        (sb-lti6): it sits beside the line that says which slot the next pick
        fills, which is the sentence an author is reading when they decide to
        leave. Escape is the third way out and is not a control on the page.

        Found #{length(cancels)} controls carrying `palette-close`.
        """
      end
    end

    # sb-dfyk. Everything above was already true before this bead and none of it
    # was visible: the palette narrowed, the position was stored, and the canvas
    # said nowhere which of forty-one gaps the next pick would fill.
    describe "the armed gap" do
      # Sabotage: passing `armed={nil}` from `Editor` to `Canvas` rather than
      # `@palette_position` - the gap renders `data-armed="false"` everywhere and
      # the first assertion goes red while every insertion test above still
      # passes, which is exactly the shape of the defect.
      test "clicking a + arms that gap and no other", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        html = view |> element(add_button("blk_wizard", "body", 1)) |> render_click()

        assert [_one] = Regex.scan(~r/<div class="sb-gap sb-gap--armed"/, html)

        assert html =~
                 ~s(data-parent-id="blk_wizard" data-slot="body" data-index="1" data-armed="true")

        assert has_element?(view, ~s(#{add_button("blk_wizard", "body", 1)}[aria-pressed="true"]))

        assert has_element?(
                 view,
                 ~s(#{add_button("blk_wizard", "body", 0)}[aria-pressed="false"])
               )
      end

      # The armed state is a mode, so it outlives the round trips an author
      # spends deciding - typing in the search box is the one they always make.
      # Sabotage: clearing `palette_position` in the "palette-search" handler -
      # the gap disarms as soon as anyone types and this goes red.
      test "stays armed across a search", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        view |> element(add_button("blk_wizard", "body", 1)) |> render_click()
        html = view |> form("#sb-palette-search", %{"q" => "wait"}) |> render_change()

        assert html =~ ~s(data-index="1" data-armed="true")
      end

      # Sabotage: dropping `palette_position: nil` from the successful
      # `insert_from_palette/3` clause - the gap stays lit over a document that
      # already took the block, and this goes red.
      test "the pick inserts and clears it", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        view |> element(add_button("blk_wizard", "body", 1)) |> render_click()

        html =
          view |> element(~s(.sb-palette__pick[phx-value-type="core.wait"])) |> render_click()

        refute html =~ "sb-gap--armed"
        refute html =~ ~s(data-armed="true")
        assert length(body_ids(latest_document())) == 4
      end

      # Sabotage: leaving the toolbar's cancel as the only one - this selector
      # matches nothing and the test goes red on a missing element, which is
      # the state the bead was filed about.
      test "the palette's own Cancel disarms it", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        view |> element(add_button("blk_wizard", "body", 1)) |> render_click()
        html = view |> element(~s(.sb-palette__cancel)) |> render_click()

        refute html =~ "sb-gap--armed"
        assert html =~ ~s(data-inserting="false")
      end

      # Escape is net-new: before this bead nothing in `lib/` or `assets/js`
      # listened for a key at all. It is bound only while a gap is armed, so the
      # editor is not holding a window listener for a mode nobody opened.
      # Sabotage: binding `phx-window-keydown` unconditionally - the first
      # refutation goes red on a resting editor that is listening anyway.
      test "Escape cancels, and is bound only while something is armed", %{conn: conn} do
        {:ok, view, html} = mount_editor(conn)

        refute html =~ "phx-window-keydown"

        html = view |> element(add_button("blk_wizard", "body", 1)) |> render_click()
        assert html =~ ~s(phx-window-keydown="palette-close")
        assert html =~ ~s(phx-key="Escape")

        html = view |> element("#editor") |> render_keydown(%{"key" => "Escape"})

        refute html =~ "sb-gap--armed"
        refute html =~ "phx-window-keydown"

        view |> element(~s(.sb-palette__pick[phx-value-type="core.wait"])) |> render_click()

        refute latest_document(), "Escape left no position behind"
      end
    end

    describe "the insert-mode line" do
      # Sabotage: computing `insert_target` from `palette_allowed` rather than
      # from `palette_position` - the line renders while the palette is
      # narrowed but names nothing, and the slot assertion goes red.
      test "says where the pick will land, in the canvas's own words", %{conn: conn} do
        {:ok, view, html} = mount_editor(conn)

        refute html =~ "Pick a block to insert into"

        html = view |> element(add_button("blk_wizard", "body", 1)) |> render_click()

        assert html =~ "Pick a block to insert into"
        assert html =~ ~s(<strong class="sb-palette__mode-slot">Steps</strong>)
        assert html =~ ~s(<strong class="sb-palette__mode-parent">Sequence</strong>)
        assert html =~ ~s(data-inserting="true")
      end

      # Ruling (b), asserted end to end: with nothing armed the pick still
      # changes no document, and now says so instead of failing silently.
      # Sabotage: making `insert_from_palette(socket, _type, nil)` return the
      # socket untouched again - the pick goes back to being invisible and the
      # wording assertion goes red.
      test "a pick with nothing armed inserts nothing and gives a reason", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        html =
          view |> element(~s(.sb-palette__pick[phx-value-type="core.wait"])) |> render_click()

        refute latest_document(), "ruling (b): no armed position, no insert"
        assert html =~ "sb-palette__mode--unarmed"
        assert html =~ "Nothing is armed"
      end

      # The reason is hidden by the mode line's own guard rather than by a
      # second piece of state: an armed palette has an instruction to give, and
      # `palette-close` clears the flag on every other way out of the reason.
      # Sabotage: dropping `@insert_target == nil` from the unarmed line's
      # `:if` - both lines render at once and this goes red.
      test "the reason goes away once a gap is armed", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        view |> element(~s(.sb-palette__pick[phx-value-type="core.wait"])) |> render_click()
        html = view |> element(add_button("blk_wizard", "body", 1)) |> render_click()

        refute html =~ "sb-palette__mode--unarmed"
        assert html =~ "Pick a block to insert into"
      end
    end

    describe "search" do
      # Sabotage: `PaletteBrowser.matches?/2` ignoring `keywords`. The needle
      # has to be a word that appears in no label and no description or the
      # mutation survives - "fork" is a keyword of core.parallel and nothing
      # else, which is the whole reason it is the one used here.
      test "matches label, description, type name and keywords", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        html = view |> form("#sb-palette-search", %{"q" => "fork"}) |> render_change()

        assert html =~ ~s(<li data-type="core.parallel">)
        refute html =~ ~s(<li data-type="core.wait">)

        html =
          view |> form("#sb-palette-search", %{"q" => "one after another"}) |> render_change()

        assert html =~ ~s(<li data-type="core.sequence">), "descriptions match too"
        refute html =~ ~s(<li data-type="core.parallel">)
      end

      # Sabotage: `PaletteBrowser.filter/3` not rejecting empty groups - the
      # "No block types match" line never renders.
      test "a query matching nothing says so rather than rendering empty groups", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        html = view |> form("#sb-palette-search", %{"q" => "chargeback"}) |> render_change()

        assert html =~ "No block types match."
        refute html =~ ~s(<li data-type=)
      end
    end

    defp body_ids(document) do
      document
      |> Document.blocks()
      |> Enum.find(&(&1.id == "blk_wizard"))
      |> Map.fetch!(:slots)
      |> Map.fetch!("body")
      |> Enum.map(& &1.id)
    end

    defp default_config(palette, type) do
      {:ok, module} = Palette.fetch(palette, type)
      Map.new(module.config_schema(%{}), fn %{key: key, default: default} -> {key, default} end)
    end
  end
end
