# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*, which is the earlier
# of the two problems.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.ShellTest do
    @moduledoc """
    The shell's event translation, driven through `Phoenix.LiveViewTest`.

    ADR-0005's consequence is that the great majority of the editor's behaviour
    is tested in plain ExUnit with no browser and no LiveView, and that
    `LiveViewTest` covers what is left: turning a `phx-` event into a command.
    These are those tests.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.Document

    describe "mounting" do
      test "renders every block in the document, unresolvable ones included", %{conn: conn} do
        {:ok, view, html} = mount_editor(conn)

        for id <- ~w(blk_wizard blk_email_step blk_variant blk_track_conversion blk_settle_pause) do
          assert html =~ ~s(data-block-id="#{id}")
        end

        assert has_element?(
                 view,
                 ~s([data-block-id="blk_track_conversion"][data-status="unresolvable"])
               )
      end

      test "surfaces the revision it loaded, for a host's optimistic concurrency", %{conn: conn} do
        document = EditorFixtures.signup_wizard()
        {:ok, _view, html} = mount_editor(conn, document: document)

        assert html =~ ~s(data-revision="#{document.revision}")
      end
    end

    describe "selection" do
      test "clicking a block's label selects it and opens its form", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        refute has_element?(view, ".sb-form")

        view
        |> element(~s([data-block-id="blk_email_step"] > .sb-node__chrome > .sb-node__label))
        |> render_click()

        assert has_element?(view, ~s(.sb-form[data-block-id="blk_email_step"]))
        assert has_element?(view, ~s([data-block-id="blk_email_step"].sb-node--selected))
      end

      test "an unresolvable block may be selected but gets no form (d12)", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        view
        |> element(
          ~s([data-block-id="blk_track_conversion"] > .sb-node__chrome > .sb-node__label)
        )
        |> render_click()

        assert has_element?(view, ~s([data-block-id="blk_track_conversion"].sb-node--selected))
        refute has_element?(view, ~s(.sb-form[data-block-id="blk_track_conversion"]))
      end
    end

    describe "delete" do
      test "removes the block and notifies the host", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        view
        |> element(~s([data-block-id="blk_email_step"] > .sb-node__chrome > .sb-node__remove))
        |> render_click()

        refute has_element?(view, ~s([data-block-id="blk_email_step"]))

        ids = latest_document() |> Document.blocks() |> Enum.map(& &1.id)
        refute "blk_email_step" in ids
      end

      test "an unresolvable block may be deleted, children and all", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        view
        |> element(
          ~s([data-block-id="blk_track_conversion"] > .sb-node__chrome > .sb-node__remove)
        )
        |> render_click()

        ids = latest_document() |> Document.blocks() |> Enum.map(& &1.id)
        refute "blk_track_conversion" in ids
        refute "blk_settle_pause" in ids
      end
    end

    describe "undo and redo" do
      test "step back to the document before the edit, and forward again", %{conn: conn} do
        {:ok, view, html} = mount_editor(conn)
        before = EditorFixtures.signup_wizard()

        assert html =~
                 ~s(<button type="button" class="sb-button sb-toolbar__button" phx-click="undo")

        view
        |> element(~s([data-block-id="blk_email_step"] > .sb-node__chrome > .sb-node__remove))
        |> render_click()

        view |> element(~s(button[phx-click="undo"])) |> render_click()
        assert Document.content_hash(latest_document()) == Document.content_hash(before)

        view |> element(~s(button[phx-click="redo"])) |> render_click()
        refute "blk_email_step" in Enum.map(Document.blocks(latest_document()), & &1.id)
      end

      test "undo is disabled with nothing to undo", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        assert has_element?(view, ~s(button[phx-click="undo"][disabled]))
        assert has_element?(view, ~s(button[phx-click="redo"][disabled]))

        # sb-sl6f: disabled has to READ as disabled, and the only thing that
        # makes it read is the vocabulary class - `[disabled]` alone is a
        # native-chrome button in a pane that dresses everything else.
        # Sabotage: dropping `sb-button` from the toolbar's class attributes.
        assert has_element?(view, ~s(button.sb-button[phx-click="undo"][disabled]))
        assert has_element?(view, ~s(button.sb-button[phx-click="redo"][disabled]))
      end
    end

    describe "the canvas toolbar (8A)" do
      # Sabotage: rendering the zoom percentage from a literal rather than from
      # the assign - the control moves and the readout does not, which is the
      # defect an author reads as "zoom is broken".
      test "zoom steps along the ladder and the readout follows", %{conn: conn} do
        {:ok, view, html} = mount_editor(conn)

        assert html =~ ~s(data-zoom="100")
        assert render(view) =~ "100%"

        view |> element(~s(button[phx-click="zoom-in"])) |> render_click()
        assert render(view) =~ "110%"

        view |> element(~s(button[phx-click="zoom-out"])) |> render_click()
        view |> element(~s(button[phx-click="zoom-out"])) |> render_click()
        assert render(view) =~ "90%"
        assert has_element?(view, ~s(.sb-editor[data-zoom="90"]))
      end

      # Sabotage: dropping the `selected?` guard on Fit active - the control
      # offers itself with nothing to fit, and pressing it does nothing at all.
      test "Fit active is disabled until something is selected", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        assert has_element?(view, ~s(button[phx-value-fit="active"][disabled]))

        view
        |> element(~s([data-block-id="blk_email_step"] > .sb-node__chrome > .sb-node__label))
        |> render_click()

        refute has_element?(view, ~s(button[phx-value-fit="active"][disabled]))

        view |> element(~s(button[phx-value-fit="active"])) |> render_click()
        assert has_element?(view, ~s(.sb-editor[data-fit="active"]))
      end

      # Sabotage: computing the metrics over the selected node rather than the
      # root - they stop being document metrics and start being a subtree's.
      test "reports the document's block count and depth", %{conn: conn} do
        {:ok, _view, html} = mount_editor(conn, document: EditorFixtures.credit_card())

        assert html =~ "6 blocks"
        assert html =~ "depth 3"
      end
    end

    describe "the canvas panel's header row (parity item 1.2)" do
      # The header is what makes the middle pane a pane: the palette and the
      # inspector name themselves, and before this the canvas was the one
      # region an author had to recognise by its contents.
      # Sabotage: dropping the `<h2 class="sb-toolbar__title">` element - the
      # row goes back to being an unlabelled strip of buttons and this goes red.
      test "names the pane and says what is in it", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        row = view |> element(".sb-toolbar") |> render()

        assert row =~ ~s(<h2 class="sb-toolbar__title">)
        assert row =~ "Canvas"
        assert row =~ "nested tree"
      end

      # Sabotage: moving the readout out of `.sb-toolbar__zoom` - the two steps
      # and the number they move stop being one control, which is the whole of
      # what a segmented control claims, and the CSS that draws the seam has
      # nothing to draw it around.
      test "zoom is ONE segmented control, minus / readout / plus", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        zoom = view |> element(".sb-toolbar__zoom") |> render()

        assert zoom =~ ~s(role="group")
        assert zoom =~ ~s(phx-click="zoom-out")
        assert zoom =~ ~s(<output class="sb-toolbar__zoom-level">100%</output>)
        assert zoom =~ ~s(phx-click="zoom-in")
      end

      # The two metrics are read, never pressed, and a chip is the shape this
      # editor gives a read-only fact.
      # Sabotage: rendering the metrics as bare spans - they sit at the end of a
      # row of buttons looking exactly like two more of them.
      test "the metrics are chips, depth then count", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: EditorFixtures.credit_card())

        metrics = view |> element(".sb-toolbar__metrics") |> render()

        assert metrics =~ ~s(<span class="sb-toolbar__chip" data-metric="depth">depth 3</span>)
        assert metrics =~ ~s(<span class="sb-toolbar__chip" data-metric="blocks">6 blocks</span>)
      end

      # The zoom wrapper `sb-6ai` added sits between the two, which is the one
      # thing that may ever come between them: it carries the scaled extent so
      # the panel scrolls the size the stage is drawn at, and it is outside the
      # stage because everything inside the stage is measured in the stage's
      # own untransformed space.
      # Sabotage: rendering the stage without the panel around it - `overflow`
      # then has to go on the stage itself, where it sizes the connector overlay
      # to the padding box and the edges stop scrolling with the tree.
      test "the stage sits inside a panel that is the scroller", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        assert has_element?(view, ".sb-canvas-panel > .sb-canvas-zoom > #sb-canvas")
      end

      # The stylesheet half of the same item, held here rather than in a comment.
      # The padding is not decoration: the root block's surface covers the panel
      # edge to edge, so the band it opens is the only place a ground can show.
      # A capture of this rule without it showed dots that were present,
      # correct, and invisible.
      # Sabotage: dropping `padding` from `.sb-canvas-panel` - every assertion
      # about the token stays green and the ground disappears, which is what
      # this names.
      test "the panel is bordered, padded, and carries the dotted ground" do
        css = File.read!("assets/css/statifier_blocks.css")
        panel = Regex.run(~r/\.sb-canvas-panel\s*\{(.*?)\n\}/s, css)

        assert panel, "the scan actually found the rule"
        [_all, body] = panel

        assert body =~ ~r/overflow:\s*auto/
        assert body =~ ~r/padding:\s*var\(--sb-space-2\)/
        assert body =~ ~r/border:\s*var\(--sb-border-width\)/
        assert body =~ ~r/background:\s*var\(--sb-canvas-grid\)/
      end
    end

    describe "the tabbed inspector (3A)" do
      # Sabotage: adding a fourth tab to the strip - 3A is exactly three, and
      # the reason it is a rule rather than a list is that the list will be
      # tempting to grow.
      test "carries exactly Config, Findings and Condition", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        assert view |> element(".sb-inspector__tabs") |> render() =~ "Config"
        assert has_element?(view, ~s(.sb-inspector__tab[phx-value-tab="findings"]))
        assert has_element?(view, ~s(.sb-inspector__tab[phx-value-tab="condition"]))

        assert view
               |> render()
               |> then(&Regex.scan(~r/class="sb-inspector__tab[ "]/, &1))
               |> length() == 3
      end

      # Sabotage: rendering every panel at once - the tabs stop meaning
      # anything and the inspector goes back to being one scrolling column.
      test "shows the selected block's form on Config and its conditions on Condition",
           %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: EditorFixtures.credit_card())

        view
        |> element(~s([data-block-id="blk_cc_decision"] > .sb-node__chrome > .sb-node__label))
        |> render_click()

        assert has_element?(view, ~s(.sb-inspector[data-tab="config"] .sb-form))
        refute has_element?(view, ".sb-conditions")

        view |> element(~s(.sb-inspector__tab[phx-value-tab="condition"])) |> render_click()

        assert has_element?(view, ~s(.sb-inspector[data-tab="condition"]))
        refute has_element?(view, ".sb-inspector__panel .sb-form")
        assert render(view) =~ "amount &gt; 500"
        assert render(view) =~ "risk_band == &#39;high&#39;"
      end

      # Sabotage: feeding the tab `view_model.findings` - the inspector's tab
      # becomes a second document-level panel, which is the conflation 3A ends.
      test "the Findings tab is the block's own, not the document's", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        view
        |> element(~s([data-block-id="blk_email_step"] > .sb-node__chrome > .sb-node__label))
        |> render_click()

        view |> element(~s(.sb-inspector__tab[phx-value-tab="findings"])) |> render_click()

        assert has_element?(view, ~s(.sb-inspector[data-tab="findings"]))
        assert has_element?(view, ".sb-inspector__empty")

        # The document's own list is in the drawer since R4, and never under
        # the canvas: two lists in one column, one of them unlabelled as to
        # scope, is the conflation 3A ends.
        refute has_element?(view, ".sb-editor__main .sb-findings")
        view |> element(".sb-drawer__strip") |> render_click()
        view |> element(~s(.sb-drawer__tab[phx-value-tab="findings"])) |> render_click()
        assert has_element?(view, ".sb-drawer__panel .sb-findings")
      end

      # Sabotage: passing the raw param through instead of normalizing it - a
      # crafted value reaches the template as an unknown panel id.
      test "an unknown tab falls back to Config", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        view |> with_target("#editor") |> render_click("inspector-tab", %{"tab" => "datamodel"})

        assert has_element?(view, ~s(.sb-inspector[data-tab="config"]))
      end
    end

    describe "the drawer (1A, 2A)" do
      # Sabotage: rendering the drawer only when fixtures exist - it becomes
      # open-or-gone, which is the one thing 2A rules out by name.
      test "is present with no fixtures source at all, reading a count of 0",
           %{conn: conn} do
        # A document with nothing wrong with it, so the strip has no findings
        # to resolve to and reports the tab this test is about.
        {:ok, view, html} = mount_editor(conn, document: unremarkable_document())

        assert html =~ ~s(data-count="0")
        assert has_element?(view, ~s(.sb-drawer[data-open="false"]))
        assert view |> element(".sb-drawer__strip") |> render() =~ "Truth tables"
      end

      # R4 put a second tab in the drawer, so the strip has to say WHICH tab it
      # is counting. Resolution, and not a fixed default: a strip reading
      # "Truth tables 0" on a document with findings in it hides the only thing
      # the drawer is holding, which is the state 2A built the strip to avoid.
      #
      # Sabotage: `Shell.drawer_view/1`'s `resolve_tab/2` returning `:tables`
      # for an unchosen tab instead of the first non-empty one - the strip
      # reads "Truth tables 0" and this goes red.
      test "an unchosen strip resolves to the tab that holds something", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        assert has_element?(view, ~s(.sb-drawer[data-open="false"][data-tab="findings"]))
        assert view |> element(".sb-drawer__strip") |> render() =~ "Findings"
      end

      # The resolution is an order, not a ranking: whichever tab comes first in
      # `Shell.drawer_tabs/0` and is not empty wins, however much the other one
      # holds. A strip that reordered itself by volume would move under an
      # author as they edited.
      #
      # Sabotage: `resolve_tab/2` preferring the fullest tab rather than the
      # first non-empty one - four findings outnumber the one table and the
      # strip flips to Findings (verified).
      test "the first non-empty tab wins, however full the other is", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn,
            findings: [
              Finding.new({:block, "blk_variant"}, :lint, "one", severity: :warning),
              Finding.new({:slot, "blk_wizard", "body"}, :arity, "two"),
              Finding.new({:config, "blk_email_step", "duration"}, :config, "three")
            ],
            fixtures: EditorFixtures.credit_card_tables()
          )

        # One table against four findings - the three supplied plus the one the
        # wizard's unresolvable block derives.
        assert has_element?(view, ~s(.sb-drawer[data-tab="tables"][data-count="1"]))
      end

      # Sabotage: `handle_event("drawer-tab", ...)` left as the no-op it was
      # before R4 - the click changes nothing and the panel stays on tables.
      test "picking a tab switches the panel and the aria wiring", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: unremarkable_document())

        view |> element(".sb-drawer__strip") |> render_click()

        assert has_element?(
                 view,
                 ~s(#sb-drawer-panel-tables[aria-labelledby="sb-drawer-tab-tables"])
               )

        view |> element(~s(.sb-drawer__tab[phx-value-tab="findings"])) |> render_click()

        assert has_element?(view, ~s(.sb-drawer[data-tab="findings"]))

        assert has_element?(
                 view,
                 ~s(#sb-drawer-panel-findings[aria-labelledby="sb-drawer-tab-findings"])
               )

        assert has_element?(view, ~s(#sb-drawer-tab-findings[aria-selected="true"]))
        assert has_element?(view, ~s(#sb-drawer-tab-tables[aria-selected="false"]))
      end

      # Sabotage: passing the raw param through instead of normalizing it - a
      # crafted value reaches the template as an unknown panel id.
      test "an unknown drawer tab falls back to the first one", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        view |> with_target("#editor") |> render_click("drawer-tab", %{"tab" => "fixtures"})

        assert has_element?(view, ~s(.sb-drawer[data-tab="tables"]))
      end

      # Sabotage: `resolve_tab/2` re-resolving a chosen tab - the author's pick
      # of an empty tab is overruled by the other one and this goes red.
      test "a chosen tab stands even when it is empty", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        view |> with_target("#editor") |> render_click("drawer-tab", %{"tab" => "tables"})

        assert has_element?(view, ~s(.sb-drawer[data-tab="tables"][data-count="0"]))
      end

      # Parity item 1.11: the count is a chip, and a chip reading "(0)" is a
      # chip with punctuation baked into it. The parentheses that used to be
      # literals in the strip's markup are what the CSS cannot take back out,
      # so the markup carrying a bare number is the half of the treatment a
      # stylesheet cannot hold on its own.
      # Sabotage: putting the parentheses back around `{@view.count}` on the
      # strip - the chip renders "(0)" and this goes red.
      test "the strip's count is a bare number, not a parenthesised one",
           %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: unremarkable_document())

        count = view |> element(".sb-drawer__strip .sb-drawer__count") |> render()

        assert count =~ ~r/>\s*0\s*</
        refute count =~ "("
      end

      # Sabotage: putting the selection's count on the strip - a strip reading
      # (0) because nothing is selected says something false about the
      # document.
      test "the collapsed strip carries the document's count", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn,
            document: EditorFixtures.credit_card(),
            fixtures: EditorFixtures.credit_card_tables()
          )

        assert has_element?(view, ~s(.sb-drawer[data-open="false"][data-count="1"]))
      end

      # Sabotage: showing "nothing here" instead of the jumps - the drawer
      # teaches an author to stop opening it, which is the cold-start gap 2A
      # closes.
      test "opening with nothing selected shows the index page", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn,
            document: EditorFixtures.credit_card(),
            fixtures: EditorFixtures.credit_card_tables()
          )

        view |> element(".sb-drawer__strip") |> render_click()

        assert has_element?(view, ~s(.sb-drawer[data-status="no_selection"]))
        assert has_element?(view, ~s(.sb-drawer__jump[phx-value-block-id="blk_cc_decision"]))
      end

      # Sabotage: pinning the drawer's subject at open time - it stops
      # following the canvas and becomes a second cursor in the editor.
      test "its subject follows the selection, and a jump makes one", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn,
            document: EditorFixtures.credit_card(),
            fixtures: EditorFixtures.credit_card_tables()
          )

        view |> element(".sb-drawer__strip") |> render_click()

        view
        |> element(~s(.sb-drawer__jump[phx-value-block-id="blk_cc_decision"]))
        |> render_click()

        assert has_element?(view, ~s(.sb-drawer[data-status="ready"]))
        assert has_element?(view, ~s(.sb-table[data-table="Authorization routing"]))

        view
        |> element(~s([data-block-id="blk_cc_settle_pause"] > .sb-node__chrome > .sb-node__label))
        |> render_click()

        assert has_element?(view, ~s(.sb-drawer[data-status="none_for_block"]))
      end

      # Sabotage: making the resize a client-side style write - the height
      # never reaches the host, so nothing remembers it and decision 7's one
      # hook has quietly become two.
      test "the resize is a server-side command and the host is told", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, drawer_height: 20.0)

        view |> element(".sb-drawer__strip") |> render_click()
        assert render(view) =~ "--sb-drawer-height: 20.0rem"

        view |> form("#sb-drawer-resize", %{"height" => "9.5"}) |> render_change()

        assert render(view) =~ "--sb-drawer-height: 9.5rem"
        assert_receive {:drawer_height, 9.5}
      end

      # Sabotage: dropping the clamp on the way out of the event - a crafted
      # height reaches the host and comes back on the next mount.
      test "a height outside the band is bounded before the host sees it", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        view |> element(".sb-drawer__strip") |> render_click()
        view |> form("#sb-drawer-resize", %{"height" => "400"}) |> render_change()

        {_min, max, _default} = StatifierBlocks.Shell.height_band()
        assert_receive {:drawer_height, ^max}
      end
    end

    describe "the host's half (8A)" do
      # Sabotage: rendering a document title in the package - 8A puts the outer
      # header on the host, and a package that draws one leaves a host with two
      # headers and no way to remove ours.
      test "the header is the host's slot, and the package draws none of it",
           %{conn: conn} do
        {:ok, _view, bare} = mount_editor(conn)
        refute bare =~ "sb-editor__header"

        {:ok, view, html} = mount_editor(conn, header: "Chargeback flow")

        assert html =~ ~s(class="sb-editor__header")

        assert view |> element(".sb-editor__header > .host-header") |> render() =~
                 "Chargeback flow"
      end
    end

    describe "the palette below 780 (7A)" do
      # Sabotage: hiding the strip in markup rather than in the stylesheet -
      # the arrangement stops being a container query and starts being a state
      # the server has to know the container's width to compute.
      test "the strip is always in the markup; the breakpoint decides what shows",
           %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        assert has_element?(view, ~s(.sb-palette[data-sheet="closed"] > .sb-palette__strip))

        view |> element(".sb-palette__strip") |> render_click()
        assert has_element?(view, ~s(.sb-palette[data-sheet="open"]))

        # Choosing from the sheet puts it away: below 780 it overlays the
        # canvas, so leaving it open hides the block the author just chose.
        view
        |> element(~s([data-block-id="blk_email_step"] > .sb-node__chrome > .sb-node__label))
        |> render_click()

        assert has_element?(view, ~s(.sb-palette[data-sheet="closed"]))
      end
    end

    describe "a document switch (2A)" do
      # Sabotage: leaving the drawer open across a switch - it shows the old
      # document's subject under the new document, and the selection it follows
      # names a block that is not there.
      test "closes the drawer and drops the selection", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn,
            document: EditorFixtures.credit_card(),
            fixtures: EditorFixtures.credit_card_tables()
          )

        view
        |> element(~s([data-block-id="blk_cc_decision"] > .sb-node__chrome > .sb-node__label))
        |> render_click()

        view |> element(".sb-drawer__strip") |> render_click()
        assert has_element?(view, ~s(.sb-drawer[data-open="true"]))

        send(view.pid, {:swap_document, EditorFixtures.signup_wizard()})
        render(view)

        assert has_element?(view, ~s(.sb-drawer[data-open="false"]))
        refute has_element?(view, ".sb-node--selected")
      end
    end

    # A one-block document the palette resolves, so nothing derives a finding
    # from it. The signup wizard cannot serve here: its unresolvable block
    # always derives a `:resolution` finding, which is decision 12 working.
    defp unremarkable_document do
      Document.new(EditorFixtures.wait("blk_only", "PT1H"), id: "doc_one_step")
    end
  end
end
