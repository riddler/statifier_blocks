# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.DrawerTabFocusTest do
    @moduledoc """
    The drawer strip as a keyboard widget: one Tab stop, and the arrow keys
    that reach the other tabs from it.

    A `role="tablist"` is a single widget on the Tab sequence, and the six
    drawer tabs were six consecutive stops ahead of the height slider and the
    collapse control - so reaching the slider from the canvas cost six Tab
    presses, and the strip announced itself six times. The roving attribute
    fixed that and left the other half owing: with one stop, the five tabs
    that are not it are reachable by arrow key or not at all, and once the
    strip began scrolling at the narrow breakpoint with its scrollbar hidden
    (`sb-mtak`), "not at all" also meant not visible.

    So this file asserts both halves. The stop is one and it moves with the
    active tab; Left and Right walk the strip and wrap, Home and End go to the
    ends, a key the strip does not answer changes nothing, and the tab a key
    lands on is the one the strip asks the browser to focus - which is what
    scrolls it into view, because `focus()` scrolls.

    Focus itself is asserted through the strip's **instruction** to move it
    rather than through a focused element, because `Phoenix.LiveViewTest`
    renders markup and has no focus: the `sb-drawer-tab-focus-*` span and the
    `phx-mounted` on it are the whole of what the server contributes, and a
    browser capture on the bead carries the other end.
    """

    use StatifierBlocks.EditorLiveCase

    # A sixth tab, so the strip is the width the narrow breakpoint clips and
    # the far end of it is five presses from the near end.
    @runs %{id: "runs", title: "Runs", count: 0}

    # The strip's order: the package's five, then the host's, which is how
    # `Shell.drawer_view/1` assembles it.
    @order ~w(tables findings declarations fixtures datamodel runs)

    defp mount_six(conn) do
      {:ok, view, _html} = mount_editor(conn, host_tabs: [@runs])
      view |> element(".sb-drawer__strip") |> render_click()
      view
    end

    defp key(view, key) do
      view |> element(".sb-drawer__tabs") |> render_keydown(%{"key" => key})
    end

    # Each tab id paired with the tabindex on the same button, in document
    # order. Read off the rendered drawer rather than through per-selector
    # assertions, because the claim is about how many stops the strip has -
    # which no single selector can make. The pattern spans one tag: `id`
    # and `tabindex` are attributes of the same button in the template, so
    # `[^>]*` cannot cross into the next one.
    defp tab_stops(html) do
      ~r/id="(sb-drawer-tab-[^"]+)"[^>]*tabindex="(-?\d)"/
      |> Regex.scan(html, capture: :all_but_first)
      |> Enum.map(fn [id, tabindex] -> {id, tabindex} end)
    end

    defp active(html) do
      html
      |> tab_stops()
      |> Enum.find_value(fn
        {"sb-drawer-tab-" <> id, "0"} -> id
        _inactive -> nil
      end)
    end

    # The tab the strip is asking the browser to focus, or `nil` when it is
    # asking for nothing. The span's `id` carries the tab and the `phx-mounted`
    # carries the selector; both are read, so a span that stopped naming the
    # tab it focuses cannot pass.
    defp focus_request(html) do
      with [_, tab, command] <-
             Regex.run(~r/id="sb-drawer-tab-focus-([^"]+)"[^>]*phx-mounted="([^"]*)"/, html),
           true <- String.contains?(command, "#sb-drawer-tab-#{tab}") do
        tab
      else
        _none -> nil
      end
    end

    describe "the drawer tab strip" do
      # Sabotage: dropping the `tabindex` attribute from `drawer.ex`'s tab
      # button - no button matches the pairing pattern, the list comes back
      # empty and the emptiness assertion goes red.
      test "makes only the active tab a Tab stop", %{conn: conn} do
        stops = conn |> mount_six() |> render() |> tab_stops()

        assert stops != []
        {active, inactive} = Enum.split_with(stops, fn {_id, tabindex} -> tabindex == "0" end)

        assert length(active) == 1
        assert inactive != []
        assert Enum.all?(inactive, fn {_id, tabindex} -> tabindex == "-1" end)
      end

      # Sabotage: hard-coding `tabindex="0"` on the first entry instead of the
      # active one - the strip still has exactly one stop, so the test above
      # stays green, and this one goes red the moment the author picks a
      # second tab.
      test "moves the Tab stop to whichever tab is active", %{conn: conn} do
        view = mount_six(conn)

        view |> element(~s(.sb-drawer__tab[phx-value-tab="declarations"])) |> render_click()

        stops = view |> render() |> tab_stops()

        assert {"sb-drawer-tab-declarations", "0"} in stops

        assert Enum.count(stops, fn {_id, tabindex} -> tabindex == "0" end) == 1
      end
    end

    describe "the arrow keys" do
      # The one stop is only worth having if the other five tabs are reachable
      # from it, so this walks the whole strip a press at a time and checks
      # every landing rather than one of them.
      #
      # Sabotage: `drawer_tab_step/3` answering `"ArrowRight"` with
      # `List.first(ids)` - the first step still lands on `findings` from
      # `tables` only if `tables` is where the walk starts, and the second
      # landing is wrong whatever it started on.
      test "Right walks the strip one tab at a time and wraps", %{conn: conn} do
        view = mount_six(conn)
        start = view |> render() |> active()
        from = Enum.find_index(@order, &(&1 == start))

        walked =
          Enum.map(1..length(@order), fn step ->
            {key(view, "ArrowRight") |> active(),
             Enum.at(@order, rem(from + step, length(@order)))}
          end)

        assert Enum.all?(walked, fn {landed, expected} -> landed == expected end),
               "walked #{inspect(walked)}"
      end

      # Sabotage: `"ArrowLeft"` answering `rem(at + 1, count)` - Left becomes a
      # second Right, which the walk above cannot see because it never presses
      # Left, and this goes red on its first assertion. (Writing the step as
      # `Enum.at(ids, at - 1)` is *not* a sabotage: `Enum.at/2` reads a
      # negative index from the end, so it wraps correctly too. `rem/2` is
      # written out because it says the wrap is intended rather than inherited
      # from an indexing convention.)
      test "Left wraps from the first tab to the last", %{conn: conn} do
        view = mount_six(conn)

        view |> element(~s(.sb-drawer__tab[phx-value-tab="tables"])) |> render_click()

        assert view |> key("ArrowLeft") |> active() == "runs"
        assert view |> key("ArrowRight") |> active() == "tables"
      end

      # Sabotage: `"Home"` answering `List.last(ids)` and `"End"`
      # `List.first(ids)` - both go red, and neither is caught by the walk
      # above, which never presses either.
      test "Home and End go to the ends", %{conn: conn} do
        view = mount_six(conn)

        assert view |> key("End") |> active() == "runs"
        assert view |> key("Home") |> active() == "tables"
      end

      # Every keystroke inside the strip reaches the handler, including the
      # Enter and Space that press the focused button, so the keys it does not
      # answer have to be inert rather than merely harmless.
      #
      # Sabotage: `drawer_tab_step/3`'s catch-all answering `List.first(ids)`
      # rather than `nil` - Enter on a tab past the first silently jumps the
      # strip back to `tables`.
      test "a key the strip does not answer changes nothing", %{conn: conn} do
        view = mount_six(conn)

        view |> element(~s(.sb-drawer__tab[phx-value-tab="fixtures"])) |> render_click()

        for pressed <- ["Enter", " ", "a", "ArrowUp", "Escape"] do
          html = key(view, pressed)
          assert active(html) == "fixtures", "#{inspect(pressed)} moved the strip"
          assert focus_request(html) == nil, "#{inspect(pressed)} asked for focus"
        end
      end
    end

    describe "the focus the arrow keys move" do
      # The half a rendered strip can prove: the tab a key landed on is the
      # tab the strip asks the browser to focus. `focus()` is also what
      # scrolls it into view at the narrow breakpoint, so this is the whole
      # server-side contribution to both.
      #
      # Sabotage: `handle_event("drawer-tab-key", ...)` assigning
      # `drawer_tab_focus: nil` - the tab still moves, so every test above
      # stays green, and the strip stops asking for focus at all.
      test "names the tab the key landed on", %{conn: conn} do
        view = mount_six(conn)

        assert view |> key("End") |> focus_request() == "runs"
        assert view |> key("Home") |> focus_request() == "tables"
        assert view |> key("ArrowRight") |> focus_request() == "findings"
      end

      # Sabotage: dropping `drawer_tab_focus: nil` from the `"drawer-tab"`
      # click handler - a pointer pick leaves the previous key's request
      # standing, and reopening the drawer later moves focus for a keystroke
      # nobody pressed.
      test "is asked for by a key press and by nothing else", %{conn: conn} do
        view = mount_six(conn)

        assert view |> render() |> focus_request() == nil
        assert view |> key("ArrowRight") |> focus_request() != nil

        view |> element(~s(.sb-drawer__tab[phx-value-tab="datamodel"])) |> render_click()
        assert view |> render() |> focus_request() == nil

        assert view |> key("ArrowRight") |> focus_request() == "runs"

        view |> element(".sb-drawer__close") |> render_click()
        view |> element(".sb-drawer__strip") |> render_click()
        assert view |> render() |> focus_request() == nil
      end

      # The bead's own criterion, driven the way a keyboard drives it: from
      # the strip's one Tab stop, arrow keys alone reach the tab furthest from
      # it - the one the narrow breakpoint clips - and the strip both selects
      # it and asks for focus on it.
      #
      # Sabotage: capping `drawer_tab_step/3` at the package's five tabs
      # (`Shell.drawer_tabs()` without `host_tab_ids/1`) - the walk stops at
      # `datamodel` and the host's tab stays unreachable, which is the defect
      # this bead was filed for.
      test "reaches the far end of a six-tab strip from the near end", %{conn: conn} do
        view = mount_six(conn)

        view |> element(~s(.sb-drawer__tab[phx-value-tab="tables"])) |> render_click()

        html = Enum.reduce(1..5, nil, fn _step, _last -> key(view, "ArrowRight") end)

        assert active(html) == "runs"
        assert focus_request(html) == "runs"
        assert {"sb-drawer-tab-runs", "0"} in tab_stops(html)
      end
    end
  end
end
