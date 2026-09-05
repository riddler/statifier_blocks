# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*, which is the earlier
# of the two problems.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.PaletteBodyTest do
    @moduledoc """
    The palette's body: the count line, the group headers, and the shape of a
    row (parity item 1.3).

    All of it is presentation, so all of it is asserted against the component
    with assigns handed to it directly rather than through a mounted editor.
    The count line is the one part that looks stateful and is not - it is
    arithmetic over the two lists the component already has, which is exactly
    why it can be driven by passing a different `query` rather than by typing
    into a connected view.

    The total is read off the core palette rather than written down, so adding
    a core entry does not fail a test about wording. What is written down is
    how many the scan saw: a helper that silently returned zero would
    otherwise make every count assertion here vacuously true.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.Editor.PaletteBrowser
    alias StatifierBlocks.Palette
    alias StatifierBlocks.ViewModel

    defp groups, do: groups_for(EditorFixtures.palette())

    defp groups_for(%Palette{} = palette) do
      EditorFixtures.signup_wizard()
      |> ViewModel.build(palette, [])
      |> Map.fetch!(:palette_groups)
    end

    defp total, do: groups() |> Enum.map(&length(&1.entries)) |> Enum.sum()

    defp total_of(kind) do
      groups() |> Enum.map(&Enum.count(&1.entries, fn e -> e.kind == kind end)) |> Enum.sum()
    end

    defp palette_html(opts \\ []) do
      render_component(
        &PaletteBrowser.palette_browser/1,
        Keyword.merge([groups: groups(), target: "#editor"], opts)
      )
    end

    # The count line's rendered text, with the markup around it taken off, so
    # an assertion is about what an author reads rather than about how the
    # formatter chose to indent a paragraph.
    defp count_text(html) do
      [_whole, text] = Regex.run(~r{<p class="sb-palette__count"[^>]*>(.*?)</p>}s, html)
      String.trim(text)
    end

    # The text inside one span, with its markup taken off and its whitespace
    # collapsed, so an assertion is about the sentence an author reads rather
    # than about where the formatter broke the line.
    defp text_of(html, class) do
      [_whole, text] =
        Regex.run(~r{<span class="#{Regex.escape(class)}"[^>]*>(.*?)</span>}s, html)

      text
      |> String.replace(~r{<[^>]*>}, "")
      |> String.replace(~r{\s+}, " ")
      |> String.trim()
    end

    # One row, from its `<li>` to the close of it.
    defp entry(html, type_name) do
      assert [row] = Regex.run(~r|<li data-type="#{Regex.escape(type_name)}".*?</li>|s, html)
      row
    end

    describe "the count line" do
      # The two kinds are counted apart, because a recipe is not a block type
      # (ADR-0005 clause 1C) and the line said it was: the core palette's
      # sixteen types plus the "deadline" recipe read as "17 block types".
      #
      # Sabotage: deleting the `<p class="sb-palette__count">` from
      # `PaletteBrowser` - `count_text/1`'s match fails and every test in this
      # describe goes red on the missing line rather than on its wording.
      #
      # Sabotage: `count_line/3`'s last arm reading `entry_count(groups)` again
      # instead of `kind_count(groups, :type)` - the line goes back to
      # "17 block types" and this test names the conflation.
      test "unfiltered, it is the size of the palette, by kind" do
        assert total() == 17, "the scan actually saw the core palette"
        assert total_of(:type) == 16
        assert total_of(:recipe) == 1

        assert count_text(palette_html()) == "16 block types, 1 recipe"
      end

      # Sabotage: `count_line/3`'s first arm reading `"#{total} of #{shown}"` -
      # the numbers swap and this goes red naming "17 of 4", which is the
      # transposition that reads as plausible in a screenshot.
      test "a query says how much of the palette is left, and what was typed" do
        html = palette_html(query: "wait")

        # The quotes come back escaped because the query is author input and
        # HEEx escapes it; a browser reads the line as `4 of 17 match "wait"`.
        assert count_text(html) == "4 of 17 match &quot;wait&quot;"
      end

      # The acceptance set is the filter the author did not type, so it is the
      # one a count line has to explain. Both halves are asserted: an
      # implementation that reported the same line for a slot-filtered palette
      # as for an unfiltered one is the defect, and it is invisible unless the
      # unfiltered case is in the same test.
      #
      # Sabotage: `count_line/3` dropping its `shown < total` arm - the
      # filtered palette claims "17 block types" over a list of two.
      #
      # Two rows survive the set, not one: the acceptance set is a set of
      # BLOCK TYPES, and the `"deadline"` recipe is not one (ADR-0005 clause
      # 1C), so no set of type names can answer for it. Whether a deadline
      # fits where the author armed is the recipe's own question, and clause
      # 3C has `insert/2` answer it by refusing the pick.
      #
      # Which is exactly why the fit count is over types alone and the recipe
      # is named beside it rather than inside it: the recipe is on screen, so
      # the line has to account for it, and it did not fit, so the line must
      # not count it as having.
      #
      # Sabotage: `count_line/3`'s second arm comparing `shown < total` over
      # entries again - the recipe joins the numerator and this reads
      # "2 of 16 block types fit here", which is the count of a row the slot
      # never accepted.
      test "a slot's acceptance set narrows the line too, without a query" do
        filtered = palette_html(allowed: MapSet.new(["core.wait"]))

        assert count_text(filtered) == "1 of 16 block types fit here; 1 recipe also listed"
        assert count_text(palette_html(allowed: nil)) == "16 block types, 1 recipe"
      end

      # A host registers the recipes it wants, so both ends of the range are
      # cases the line has to read correctly: none at all, and more than one.
      # The core palette can only prove the middle of it.
      #
      # Sabotage: `recipe_clause/1` losing its `0` clause and returning
      # `"0 recipes"` - the no-recipe palette's line grows a trailing clause
      # about nothing and both assertions here go red.
      test "with no recipes registered, the line says nothing about them" do
        types_only = groups_for(Palette.new(Palette.core_types()))

        assert count_text(palette_html(groups: types_only)) == "16 block types"

        assert count_text(palette_html(groups: types_only, allowed: MapSet.new(["core.wait"]))) ==
                 "1 of 16 block types fit here"
      end

      # Sabotage: `recipe_clause/1`'s catch-all reading `"#{count} recipe"` -
      # the plural goes and this reads "2 recipe".
      test "more than one recipe is counted in the plural" do
        two =
          groups_for(
            Palette.new(Palette.core_types(),
              recipes:
                Map.put(Palette.core_recipes(), "cutoff", StatifierBlocks.Core.DeadlineRecipe)
            )
          )

        assert count_text(palette_html(groups: two)) == "16 block types, 2 recipes"

        assert count_text(palette_html(groups: two, allowed: MapSet.new(["core.wait"]))) ==
                 "1 of 16 block types fit here; 2 recipes also listed"
      end

      # Sabotage: `count_line/3`'s `total_types == 1` arm deleted - a
      # one-type palette reads "1 block types".
      test "one block type is singular" do
        one = groups_for(Palette.new(Map.take(Palette.core_types(), ["core.wait"])))

        assert count_text(palette_html(groups: one)) == "1 block type"
      end

      # Sabotage: hard-coding `data-filtering="false"` - the unfiltered case
      # still passes and the two filtered ones go red, which is the pair that
      # says the attribute tracks something.
      test "the attribute the stylesheet reads tracks either filter" do
        assert palette_html() =~ ~s(data-filtering="false")
        assert palette_html(query: "wait") =~ ~s(data-filtering="true")

        assert palette_html(allowed: MapSet.new(["core.wait"])) =~ ~s(data-filtering="true")
      end
    end

    describe "a group header" do
      # Sabotage: deleting the `<span class="sb-palette__group-count">` line -
      # the header goes back to a bare name and the second assertion goes red.
      test "carries its name and the number of rows under it" do
        html = palette_html()

        assert html =~ ~s(<h3 class="sb-palette__group-name">)
        assert html =~ "<span>Structure</span>"
        assert html =~ ~s(<span class="sb-palette__group-count">17</span>)
      end

      # The count is of what is under the header NOW. A header that kept
      # reporting the registry's count would say 17 over a list of four, which
      # is worse than no count at all.
      #
      # Sabotage: `length(group.entries)` reading from `@groups` instead of the
      # filtered group - the unfiltered case passes and this goes red on 17.
      test "counts the filtered rows, not the registry's" do
        assert palette_html(query: "wait") =~
                 ~s(<span class="sb-palette__group-count">4</span>)
      end
    end

    describe "a row" do
      # Sabotage: deleting the `<span class="sb-palette__name">` wrapper from
      # `PaletteBrowser` - the label goes back to bare text in the row and the
      # name assertion goes red while the description one still passes.
      test "is a tile, a name, and the description its type declared" do
        row = entry(palette_html(), "core.wait")

        assert row =~ ~s(<span class="sb-palette__icon">)
        assert row =~ ~s(<span class="sb-palette__name">Wait</span>)

        assert row =~ ~s(class="sb-palette__description")
        assert row =~ "Pauses for a fixed duration before continuing."
      end

      # The tile is a slot, not an icon. `Icons.glyph/1` renders nothing at all
      # for a nameless entry, so an implementation that gave the glyph the
      # tile's class - which is what this package shipped - left a type that
      # declared no icon with no box, and its name out of the column every
      # other name lines up in.
      #
      # Sabotage: putting `class="sb-palette__icon"` back on `<Icons.glyph>`
      # and dropping the wrapper - this goes red on the missing tile, and so
      # does the `core.wait` row above, because with no wrapper the tile only
      # exists for a type that named a glyph.
      test "renders the tile even for a type that declared no icon" do
        row = entry(palette_html(groups: [nameless_group()]), "myapp.plain")

        assert row =~ ~s(<span class="sb-palette__icon">)
        refute row =~ "data-icon", "there was no glyph to put in it"
      end
    end

    describe "the insert-mode line (sb-dfyk)" do
      # Sabotage: rendering the line unconditionally rather than under
      # `:if={@insert_target}` - the resting palette grows an instruction with
      # two blanks in it and the refutation below goes red.
      test "is absent while nothing is armed" do
        html = palette_html()

        refute html =~ "sb-palette__mode"
        refute html =~ "Pick a block to insert into"
        assert html =~ ~s(data-inserting="false")
      end

      # The sentence names the destination in the words the canvas already
      # shows: the slot's LABEL and the holder's TITLE, never `body` and never
      # a block id.
      # Sabotage: dropping `@insert_target.slot` from the template - the line
      # renders "insert into of Sequence" and the label assertion goes red.
      test "names the slot and the block the pick will land in" do
        html = palette_html(insert_target: %{slot: "Steps", parent: "Sequence"})

        assert html =~ ~s(data-inserting="true")
        assert text_of(html, "sb-palette__mode-text") =~ "Pick a block to insert into"
        assert html =~ ~s(<strong class="sb-palette__mode-slot">Steps</strong>)
        assert html =~ ~s(<strong class="sb-palette__mode-parent">Sequence</strong>)
      end

      # The way out of the mode, beside the sentence that announced it. A real
      # button, not a run of text: it is the control an author reaches for
      # while lost, and it carries the same event the toolbar's does.
      # Sabotage: rendering the Cancel as a `<span>` - the button assertion
      # goes red, and with it the promise that the mode has a visible exit.
      test "carries a Cancel control that closes the palette" do
        html = palette_html(insert_target: %{slot: "Steps", parent: "Sequence"})

        assert html =~ ~s(class="sb-button sb-palette__cancel")
        assert html =~ ~s(phx-click="palette-close")
        assert [_button] = Regex.run(~r|<button[^>]*sb-palette__cancel.*?</button>|s, html)
      end

      # The (b) ruling made visible: a pick with nothing armed stays a no-op,
      # and says so in the region the armed case uses for its instruction.
      # Sabotage: leaving the `@insert_target == nil` guard off the unarmed
      # line - both lines render together while a gap is armed, and the
      # refutation in the second block goes red.
      test "the unarmed pick says why it did nothing, and only when nothing is armed" do
        armed =
          palette_html(insert_target: %{slot: "Steps", parent: "Sequence"}, unarmed_pick: true)

        refute armed =~ "sb-palette__mode--unarmed"

        loose = palette_html(unarmed_pick: true)
        assert loose =~ "sb-palette__mode--unarmed"
        assert text_of(loose, "sb-palette__mode-text") =~ "Nothing is armed"
        assert text_of(loose, "sb-palette__mode-text") =~ ~s(Choose a "+" on the canvas first.)
      end
    end

    # A group of one entry that declared neither an icon nor a description -
    # decision 10's defaults, which `ViewModel` has already applied by the time
    # this component sees an entry.
    defp nameless_group do
      %ViewModel.PaletteGroup{
        name: "Payments",
        entries: [
          %{
            kind: :type,
            name: "myapp.plain",
            type_name: "myapp.plain",
            module: __MODULE__,
            entry: %{
              label: "Plain",
              group: "Payments",
              description: "",
              icon: nil,
              keywords: [],
              order: 0
            }
          }
        ]
      }
    end
  end
end
