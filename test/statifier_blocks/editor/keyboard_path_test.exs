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

      # Sabotage: "palette-close" clearing `palette_allowed` but not
      # `palette_position` - a later pick would then still insert, and the
      # document would change where this expects it not to.
      test "cancelling an insert inserts nothing", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        view |> element(add_button("blk_wizard", "body", 0)) |> render_click()
        html = view |> element(~s(button[phx-click="palette-close"])) |> render_click()

        assert html =~ ~s(data-filtered="false")

        view |> element(~s(.sb-palette__pick[phx-value-type="core.wait"])) |> render_click()

        refute latest_document(), "no position, no insert"
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
