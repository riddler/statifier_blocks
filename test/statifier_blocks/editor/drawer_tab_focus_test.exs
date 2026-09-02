# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.DrawerTabFocusTest do
    @moduledoc """
    The drawer strip's tab stop: one, not one per tab.

    A `role="tablist"` is a single widget on the Tab sequence, and the six
    drawer tabs were six consecutive stops ahead of the height slider and the
    collapse control - so reaching the slider from the canvas cost six Tab
    presses, and the strip announced itself six times. The inspector's strip
    already carried the roving attribute; this asserts the drawer's does too,
    and that it *moves* when the active tab does rather than being stamped on
    a fixed tab.

    What is deliberately not asserted: arrow-key movement between the tabs.
    Nothing in this package's shipped JavaScript listens for keys, and the
    change that introduced this test was constrained to add none, so the
    inactive tabs are reachable by pointer and by the panel beside them and
    not from the strip itself by keyboard.
    """

    use StatifierBlocks.EditorLiveCase

    defp open(view) do
      view |> element(".sb-drawer__strip") |> render_click()
      view
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

    describe "the drawer tab strip" do
      # Sabotage: dropping the `tabindex` attribute from `drawer.ex`'s tab
      # button - no button matches the pairing pattern, the list comes back
      # empty and the emptiness assertion goes red.
      test "makes only the active tab a Tab stop", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        stops = view |> open() |> render() |> tab_stops()

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
        {:ok, view, _html} = mount_editor(conn)

        open(view)
        view |> element(~s(.sb-drawer__tab[phx-value-tab="declarations"])) |> render_click()

        stops = view |> render() |> tab_stops()

        assert {"sb-drawer-tab-declarations", "0"} in stops

        assert Enum.count(stops, fn {_id, tabindex} -> tabindex == "0" end) == 1
      end
    end
  end
end
