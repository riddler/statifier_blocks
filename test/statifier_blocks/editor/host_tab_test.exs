# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.HostTabTest do
    @moduledoc """
    The drawer's host-tab seam: the editor's `drawer_tabs` assign.

    Everything here drives the seam the way a host does - descriptors built
    from the host LiveView's own assigns, moved by the host for its own
    reasons - because the load-bearing claim is that a tab whose content is
    changing under the host *redraws*. That is the one thing the first
    consumer needs and the one thing a `LiveComponent` slot cannot do: a slot
    body is not among the assigns the component was passed, so a host assign
    read only inside one never re-renders it, and the appended step never
    reaches the screen.

    The strip's ordering, which picks stand, and which declarations never
    become tabs are `StatifierBlocks.ShellTest`'s - they are decisions with
    return values and they belong in the headless tree. What is here is what
    only a rendered drawer can show: that the tab is drawn, that it activates,
    that its body is the host's, and that the two package tabs are untouched
    beside it.
    """

    use StatifierBlocks.EditorLiveCase

    @runs %{id: "runs", title: "Runs", count: 0}
    @jobs %{id: "jobs", title: "Jobs", count: 7}

    defp open(view) do
      view |> element(".sb-drawer__strip") |> render_click()
      view
    end

    defp pick(view, id) do
      view |> element(~s(.sb-drawer__tab[phx-value-tab="#{id}"])) |> render_click()
      view
    end

    defp feed(view, line) do
      send(view.pid, {:feed, line})
      render(view)
      view
    end

    describe "a drawer with no host tab" do
      # The absence half of the seam, and the reason it is a test rather than
      # an assumption: a host contributing nothing has to get the drawer
      # exactly as it was, or every existing host acquires a defect on
      # upgrade.
      #
      # Sabotage: `Shell.host_tabs/1` answering an empty list with a
      # placeholder entry - a fourth, nameless tab appears and the ordering
      # assertion goes red.
      test "carries the four package tabs and nothing else", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)
        open(view)

        html = render(view)

        assert has_element?(view, "#sb-drawer-tab-tables")
        assert has_element?(view, "#sb-drawer-tab-findings")
        assert has_element?(view, "#sb-drawer-tab-declarations")
        assert has_element?(view, "#sb-drawer-tab-fixtures")

        assert tabs(html) == [
                 "sb-drawer-tab-tables",
                 "sb-drawer-tab-findings",
                 "sb-drawer-tab-declarations",
                 "sb-drawer-tab-fixtures"
               ]
      end
    end

    describe "a host tab" do
      # Sabotage: dropping `host_tabs: assigns.drawer_tabs` from the editor's
      # `drawer_view/1` call - the strip never learns the tab exists and every
      # assertion here goes red at the first one.
      test "is drawn beside the package's, with its own title and count", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, host_tabs: [@jobs])
        open(view)

        assert tabs(render(view)) == [
                 "sb-drawer-tab-tables",
                 "sb-drawer-tab-findings",
                 "sb-drawer-tab-declarations",
                 "sb-drawer-tab-fixtures",
                 "sb-drawer-tab-jobs"
               ]

        assert view |> element("#sb-drawer-tab-jobs") |> render() =~ "Jobs"
        assert view |> element("#sb-drawer-tab-jobs") |> render() =~ "(7)"
      end

      # Sabotage: `drawer-tab`'s handler calling `Shell.drawer_tab(tab)` on the
      # one-argument form again - the pick resolves to `:tables`, the panel
      # stays the truth-table one and the first assertion goes red. This is the
      # test that says the tab is a tab and not a label.
      test "activates, and its panel is the host's markup", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, host_tabs: [@runs], feed: ["step one"])

        view |> open() |> pick("runs")

        assert has_element?(view, ~s(.sb-drawer[data-tab="runs"]))
        assert has_element?(view, ~s(#sb-drawer-tab-runs[aria-selected="true"]))
        assert has_element?(view, ~s(#sb-drawer-tab-tables[aria-selected="false"]))

        assert has_element?(
                 view,
                 ~s(#sb-drawer-panel-runs[aria-labelledby="sb-drawer-tab-runs"] .host-feed)
               )

        assert view |> element(".sb-drawer__panel") |> render() =~ "step one"
        refute has_element?(view, ".sb-drawer__panel .sb-drawer__empty")
      end

      # The claim the seam exists for. The host appends to an assign of its
      # own and nothing is pushed into the editor, so the tab's body is redrawn
      # by the host's render pass - which is what a run feed is.
      #
      # Sabotage: taking the descriptors as a slot instead of an assign (the
      # shape this seam was first drafted in) - the first line still shows,
      # because it was there at mount, and the two lines appended afterwards
      # never arrive.
      test "redraws when the host's own assigns move", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, host_tabs: [@runs])

        view |> open() |> pick("runs")

        refute view |> element(".sb-drawer__panel") |> render() =~ "step one"

        view |> feed("step one") |> feed("step two")

        panel = view |> element(".sb-drawer__panel") |> render()

        assert panel =~ "step one"
        assert panel =~ "step two"
      end

      # The count is drawn from the same assign, so it is live for the same
      # reason - and it is what the collapsed strip reports, which is 2A's
      # whole argument for the strip.
      #
      # Sabotage: reading the count once at mount into editor state rather
      # than off the descriptor each render - the chip freezes at (0) and the
      # assertions after the appends go red.
      test "reports a count that moves with it, on the tab and on the strip", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, host_tabs: [@runs])

        view |> open() |> pick("runs")
        assert view |> element("#sb-drawer-tab-runs") |> render() =~ "(0)"

        view |> feed("step one") |> feed("step two")
        assert view |> element("#sb-drawer-tab-runs") |> render() =~ "(2)"

        view |> element(".sb-drawer__close") |> render_click()

        assert has_element?(view, ~s(.sb-drawer[data-open="false"][data-count="2"]))
        assert view |> element(".sb-drawer__strip") |> render() =~ "Runs"
      end

      # Sabotage: rendering the host branch on `@host_tabs != []` rather than
      # on the active tab matching one - the findings panel is replaced by the
      # host's feed the moment a host tab exists, and the package's own tabs
      # stop working.
      test "leaves the package's tabs working beside it", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, host_tabs: [@runs], feed: ["step one"])

        view |> open() |> pick("runs")
        view |> pick("findings")

        assert has_element?(view, ".sb-drawer__panel .sb-findings")
        refute view |> element(".sb-drawer__panel") |> render() =~ "step one"

        view |> pick("tables")

        assert has_element?(view, ~s(.sb-drawer[data-tab="tables"][data-status="no_fixtures"]))
        assert has_element?(view, ".sb-drawer__panel .sb-drawer__empty")
      end

      # The host withdrew it while it was showing. The drawer has to resolve
      # to a tab that is actually there rather than label a panel that is not.
      #
      # Sabotage: `resolve_tab/2` returning a pick it does not recognise
      # unchanged instead of resolving it - `data-tab` stays `runs` with no
      # `#sb-drawer-tab-runs` to control it.
      test "that the host withdraws stops being the active one", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, host_tabs: [@runs])

        view |> open() |> pick("runs")
        assert has_element?(view, ~s(.sb-drawer[data-tab="runs"]))

        send(view.pid, {:host_tabs, []})
        render(view)

        # Resolved rather than defaulted: the wizard's one unresolvable block
        # is a finding, so the tab that actually holds something is Findings.
        assert has_element?(view, ~s(.sb-drawer[data-tab="findings"]))
        refute has_element?(view, "#sb-drawer-tab-runs")
      end
    end

    describe "a host tab the strip refuses" do
      # Sabotage: dropping `Shell.host_tabs/1` from `drawer_view/1` - two
      # buttons carry `id="sb-drawer-tab-findings"`, which no `aria-controls`
      # can resolve and no author can tell apart.
      test "named for a package tab never reaches the DOM", %{conn: conn} do
        shadow = %{id: "findings", title: "Mine", count: 3}
        {:ok, view, _html} = mount_editor(conn, host_tabs: [shadow])
        open(view)

        html = render(view)

        assert tabs(html) == [
                 "sb-drawer-tab-tables",
                 "sb-drawer-tab-findings",
                 "sb-drawer-tab-declarations",
                 "sb-drawer-tab-fixtures"
               ]

        assert view |> element("#sb-drawer-tab-findings") |> render() =~ "Findings"
        refute view |> element("#sb-drawer-tab-findings") |> render() =~ "Mine"
      end

      # Sabotage: passing `@drawer_tabs` unfiltered to the drawer - the second
      # `runs` entry renders a second button with the same id.
      test "repeating an id is drawn once", %{conn: conn} do
        twice = [@runs, %{id: "runs", title: "Runs again", count: 4}]
        {:ok, view, _html} = mount_editor(conn, host_tabs: twice)
        open(view)

        assert tabs(render(view)) == [
                 "sb-drawer-tab-tables",
                 "sb-drawer-tab-findings",
                 "sb-drawer-tab-declarations",
                 "sb-drawer-tab-fixtures",
                 "sb-drawer-tab-runs"
               ]
      end

      # A tab name arrives off a `phx-value-tab` attribute, so an id no host
      # declared is a crafted payload rather than a bug, and the answer to it
      # is the package's first tab - the same answer an unknown package tab
      # gets.
      #
      # Sabotage: `drawer_tab/2`'s `value in host_ids` clause widened to
      # `is_binary(value) -> value` - the crafted name reaches `data-tab` and
      # the drawer renders a panel with no tab controlling it.
      test "no host declared cannot be picked", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, host_tabs: [@runs])
        open(view)

        view |> with_target("#editor") |> render_click("drawer-tab", %{"tab" => "not_a_tab"})

        assert has_element?(view, ~s(.sb-drawer[data-tab="tables"]))
      end
    end

    # The tab strip's ids, in document order. Read off the rendered drawer
    # rather than through `has_element?/2`, because the claims here are about
    # how many tabs there are and in what order - neither of which a
    # per-selector assertion can make.
    defp tabs(html) do
      Regex.scan(~r/id="(sb-drawer-tab-[^"]+)"/, html, capture: :all_but_first)
      |> List.flatten()
    end
  end
end
