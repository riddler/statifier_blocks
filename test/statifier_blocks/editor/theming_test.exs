# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*, which is the earlier
# of the two problems.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.ThemingTest do
    @moduledoc """
    ADR-0005 decision 14: a class prefix, CSS custom properties, and a
    per-component class override.

    The `sb-` prefix and the `--sb-*` property namespace are a **new contract**,
    not an inherited one - statifier-ui has no theming convention, so there is
    nothing here to be consistent with. The record commits to them as a stable
    surface, which makes them worth holding mechanically rather than by review:
    the first test below scans the whole rendered document and fails on a single
    unprefixed class, wherever it came from.
    """

    use StatifierBlocks.EditorLiveCase

    # Every class token the editor emits, from the whole rendered tree.
    defp classes(html) do
      ~r/class="([^"]*)"/
      |> Regex.scan(html)
      |> Enum.flat_map(fn [_all, value] -> String.split(value, ~r/\s+/, trim: true) end)
      |> Enum.uniq()
    end

    describe "the class prefix" do
      # Sabotage: renaming one class in `Editor.Canvas` from "sb-canvas" to
      # "canvas" - it lands in `stray` and this goes red naming it.
      test "every class the package emits is prefixed sb-", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        # Select a block so the config form's classes are in the render too.
        html =
          view
          |> element(~s([data-block-id="blk_email_step"] > .sb-node__chrome > .sb-node__label))
          |> render_click()

        stray = Enum.reject(classes(html), &String.starts_with?(&1, "sb-"))

        assert stray == [],
               "ADR-0005 decision 14: no CSS framework is depended on and no framework's " <>
                 "class names are emitted. Unprefixed: #{inspect(stray)}"

        assert "sb-canvas" in classes(html), "the scan actually saw the markup"
      end

      # Sabotage: dropping the `@class` element from `Editor`'s root class list -
      # the host's class never reaches the markup.
      test "a host's class is appended to the component's own", %{conn: conn} do
        {:ok, _view, html} = mount_editor(conn)

        assert html =~ ~s(class="sb-editor )
      end
    end

    describe "custom properties" do
      # Sabotage: `Canvas.theme_style/1` returning nil unconditionally - the
      # override never renders and the host cannot restyle without a stylesheet.
      test "a theme renders as --sb-* declarations on the canvas root", %{conn: conn} do
        theme = %{"--sb-accent" => "hotpink", "--sb-radius" => "0"}
        {:ok, view, _html} = mount_editor(conn, theme: theme)

        style = view |> element("#sb-canvas") |> render()

        assert style =~ "--sb-accent:hotpink"
        assert style =~ "--sb-radius:0"
      end

      # Sabotage: `Canvas.theme_style/1` dropping its `--sb-` filter - a host
      # could then set any declaration on the canvas root, and this goes red.
      test "anything outside the --sb-* namespace is ignored, not emitted", %{conn: conn} do
        theme = %{"--sb-accent" => "hotpink", "background" => "url(javascript:alert(1))"}
        {:ok, view, _html} = mount_editor(conn, theme: theme)

        style = view |> element("#sb-canvas") |> render()

        assert style =~ "--sb-accent:hotpink"
        refute style =~ "background"
      end

      test "no theme means no declarations, so the stylesheet's defaults stand", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        assert view |> element("#sb-canvas") |> render() =~ ~s(style="")
      end
    end

    describe "the stylesheet" do
      @stylesheet "assets/css/statifier_blocks.css"

      test "declares a default for every --sb-* property it reads", %{conn: _conn} do
        css = File.read!(@stylesheet)

        declared =
          ~r/^\s*(--sb-[a-z-]+):/m
          |> Regex.scan(css)
          |> MapSet.new(fn [_all, name] -> name end)

        read =
          ~r/var\((--sb-[a-z-]+)/
          |> Regex.scan(css)
          |> MapSet.new(fn [_all, name] -> name end)

        missing = MapSet.difference(read, declared)

        assert MapSet.size(missing) == 0,
               "decision 14: each --sb-* property has a default. Missing: #{inspect(missing)}"

        assert MapSet.size(declared) > 5, "the scan actually found the declarations"
      end

      test "emits no framework class names", %{conn: _conn} do
        css = File.read!(@stylesheet)

        selectors =
          ~r/^\.([a-z][a-z0-9_-]*)/m
          |> Regex.scan(css)
          |> Enum.map(fn [_all, name] -> name end)

        assert Enum.all?(selectors, &String.starts_with?(&1, "sb-"))
        assert selectors != []
      end
    end
  end
end
