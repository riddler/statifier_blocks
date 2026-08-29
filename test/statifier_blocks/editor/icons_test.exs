# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.IconsTest do
    @moduledoc """
    The shipped default icon set (`sb-jja`), and the seam it does not move.

    The bead's own acceptance criterion is a negative one - mount with no
    `icon` and there is no fallback glyph anywhere in the rendered editor - and
    that is the first test below. It is worth having as a test rather than as a
    screenshot because the defect it names was invisible to every other check
    in this suite: the editor rendered, every event worked, the theme audit was
    green, and a `U+25A1` sat in twenty tiles.

    The rest hold the contract around it: the host's component still wins, an
    entry that names no icon gets no tile rather than an empty one, a name this
    package has never heard of gets a mark rather than a box, and every name
    `Palette.core/0` actually emits has a glyph here.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.Editor.Icons

    # The glyph the editor used to render in every tile, in all three of the
    # forms it could reach a comparison: the character, the entity the
    # template wrote, and the escaped entity a rendered document carries.
    @fallback ["□", "&#9633;", "&amp;#9633;"]

    describe "the no-icon state" do
      # Sabotage: restoring `<span class="sb-node__icon" ...>&#9633;</span>` as
      # the nil-icon clause in `Editor.Icons.glyph/1` - every canvas tile
      # carries the square again and this goes red naming it.
      test "no fallback glyph anywhere when the host passes no icon", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        # Select a block and open the palette from a gap, so the inspector and
        # the filtered palette are in the render too - the whole editor, not
        # just the canvas.
        view
        |> element(~s([data-block-id="blk_email_step"] > .sb-node__chrome > .sb-node__label))
        |> render_click()

        html = render(view)

        for glyph <- @fallback do
          refute html =~ glyph,
                 "sb-jja: the editor renders no fallback glyph. Found #{inspect(glyph)}."
        end

        assert html =~ "sb-node__icon", "the scan actually saw the icon tiles"
      end

      # Sabotage: dropping the `%{name: nil}` clause from `Icons.glyph/1` so a
      # nameless entry falls through to the unnamed mark - the unresolvable
      # block grows a tile and this goes red.
      test "an entry that names no icon gets no tile at all", %{conn: conn} do
        {:ok, _view, html} = mount_editor(conn)

        refute chrome(html, EditorFixtures.unknown_type()) =~ "sb-node__icon",
               "ADR-0005 decision 12: an unresolvable block has no palette entry and so " <>
                 "names no icon; a nameless entry is not a missing one."

        assert chrome(html, "core.wait") =~ "sb-node__icon",
               "the scan actually saw a chrome that does carry a tile"
      end
    end

    describe "the shipped set" do
      # Sabotage: deleting the `"clock"` key from `Icons`'s `@glyphs` - the
      # wait step falls through to the unnamed mark and this goes red.
      test "a canvas tile carries the glyph its palette entry named", %{conn: conn} do
        {:ok, _view, html} = mount_editor(conn)

        tile = tile(html, "clock")

        assert tile =~ ~s(<svg), "the shipped set is inline SVG, not a font and not a CDN"
        assert tile =~ ~s(stroke="currentColor"), "the tile's own rule decides the colour"
        assert "clock" in Icons.known_names()
      end

      # Sabotage: changing `Map.get(@glyphs, assigns.name, @unnamed)` to
      # `Map.fetch!/2` - an unknown name raises instead of degrading, and this
      # goes red.
      test "a name this package does not ship gets a mark, never a box" do
        # The case a host block type declaring `icon: "credit-card"` lands in.
        rendered = render_component(&Icons.icon/1, name: "credit-card", class: "sb-node__icon")

        assert rendered =~ ~s(data-icon="credit-card")
        assert rendered =~ "<svg"

        for glyph <- @fallback, do: refute(rendered =~ glyph)
      end

      # Sabotage: dropping any one name from `@glyphs` - the core palette emits
      # a name with no glyph and this goes red naming it.
      test "every icon name the core palette emits has a glyph" do
        emitted =
          Palette.core()
          |> palette_icon_names()
          |> MapSet.new()

        missing = MapSet.difference(emitted, MapSet.new(Icons.known_names()))

        assert MapSet.to_list(missing) == [],
               "sb-jja: the shipped set covers the names `Palette.core/0` emits. " <>
                 "Missing: #{inspect(MapSet.to_list(missing))}"

        assert MapSet.size(emitted) == 11, "the scan actually saw the core palette"
      end

      # Sabotage: adding a name to `@glyphs` that no core type emits - the set
      # grows a glyph nothing can reach and this goes red.
      test "and ships nothing the core palette does not emit" do
        emitted = Palette.core() |> palette_icon_names() |> MapSet.new()

        stray = MapSet.difference(MapSet.new(Icons.known_names()), emitted)

        assert MapSet.to_list(stray) == [],
               "sb-jja: this is the default set for this package's own palette, not a " <>
                 "general icon library. Unreachable: #{inspect(MapSet.to_list(stray))}"
      end
    end

    describe "the palette entry's tile" do
      # Sabotage: deleting the `<Icons.glyph .../>` line from
      # `Editor.PaletteBrowser` - the palette goes back to declaring an `icon`
      # attr it never renders, which is the ground truth this bead found.
      test "a palette entry renders the icon its type named", %{conn: conn} do
        {:ok, _view, html} = mount_editor(conn)

        entry = palette_entry(html, "core.wait")

        assert entry =~ "sb-palette__icon",
               "the `icon` attr `Editor` passes this component has to reach the markup"

        assert entry =~ ~s(data-icon="clock")
      end
    end

    describe "the override" do
      # Sabotage: making `Icons.glyph/1`'s last clause render `<.icon .../>`
      # too - the host's component is accepted and ignored, and this goes red
      # on both surfaces.
      test "a host's icon component still wins on the canvas and the palette", %{conn: conn} do
        {:ok, _view, html} = mount_editor(conn, icon: :host)

        assert tile(html, "clock") =~ ~s(data-host-icon="true"),
               "ADR-0005 decision 10: the host's component resolves every name"

        assert palette_entry(html, "core.wait") =~ ~s(data-host-icon="true"),
               "and it is the same component on both surfaces"

        refute html =~ ~s(stroke-linejoin="round"),
               "the shipped set is not rendered alongside the host's"
      end

      # Sabotage: dropping the `%{name: nil}` clause - the host component is
      # called with a nil name, which is a contract change it never asked for.
      test "a host component is never called with a nameless entry", %{conn: conn} do
        {:ok, _view, html} = mount_editor(conn, icon: :host)

        refute chrome(html, EditorFixtures.unknown_type()) =~ "data-host-icon",
               "an entry that named no icon does not reach the host's component either"

        assert chrome(html, "core.wait") =~ "data-host-icon",
               "the scan actually saw a chrome the host's component did reach"
      end
    end

    # The icon names a palette's entries declare, read the way the palette
    # browser reads them: off the view model, with decision 10's defaults
    # already applied.
    defp palette_icon_names(palette) do
      Document.new(Block.new("core.sequence", id: "blk_root"))
      |> StatifierBlocks.ViewModel.build(palette, [])
      |> Map.fetch!(:palette_groups)
      |> Enum.flat_map(& &1.entries)
      |> Enum.map(& &1.entry.icon)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
    end

    # One block's chrome row: the tile, if it has one, is its first child, and
    # nothing inside a chrome is a div, so the first close is the chrome's own.
    defp chrome(html, type_name) do
      assert [row] =
               Regex.run(
                 ~r|data-type="#{Regex.escape(type_name)}".*?<div class="sb-node__chrome".*?</div>|s,
                 html
               )

      row
    end

    defp tile(html, name) do
      assert [tile] =
               Regex.run(~r|<span class="sb-node__icon" data-icon="#{name}".*?</span>|s, html)

      tile
    end

    defp palette_entry(html, type_name) do
      assert [entry] = Regex.run(~r|<li data-type="#{type_name}".*?</li>|s, html)
      entry
    end
  end
end
