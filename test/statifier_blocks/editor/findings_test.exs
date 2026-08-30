# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*, which is the earlier
# of the two problems.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.FindingsTest do
    @moduledoc """
    ADR-0005 decision 11: findings are anchored, and the anchor decides where
    they render.

    The routing itself is `StatifierBlocks.ViewModel`'s and was tested with
    LiveView absent. What is asserted here is the half that only exists once
    there is markup: that a `:config` finding really does appear beneath its
    field, a `:slot` finding on that slot's header, a `:block` finding on the
    block's chrome, that the drawer's Findings tab lists all of them, and
    that every node carries its subtree rollup - because a finding that can
    hide inside something folded shut is the failure mode that makes tree
    editors feel unreliable. The rollup is the number a collapsed container's
    badge reads; the badge itself belongs to
    `StatifierBlocks.Editor.CollapseTest`, which is where a container can be
    folded shut.

    The document-level list is a drawer tab since operator ruling R4
    (2026-08-29) and no longer a block under the canvas, so every assertion
    about it opens the drawer first. That is not test ceremony: an author
    reaches the list the same way.
    """

    use StatifierBlocks.EditorLiveCase

    defp findings do
      [
        Finding.new({:block, "blk_variant"}, :lint, "no handler registered for this invoke type",
          severity: :warning
        ),
        Finding.new(
          {:slot, "blk_wizard", "body"},
          :assignability,
          "this slot wants at least one step"
        ),
        Finding.new({:config, "blk_email_step", "duration"}, :config, "far too long a wait"),
        Finding.new({:block, "blk_deleted_long_ago"}, :resolution, "no such block any more")
      ]
    end

    describe "inline anchors" do
      # Sabotage: `Slot.slot/1` dropping its `@slot.findings` loop - the slot
      # header renders without the message and this goes red.
      test "a :slot finding renders on that slot's header", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, findings: findings())

        assert has_element?(
                 view,
                 ~s([data-slot-name="body"][data-parent-id="blk_wizard"] > .sb-slot__header > .sb-finding),
                 "this slot wants at least one step"
               )
      end

      # Sabotage: `BlockNode.block_node/1` dropping its `@node.findings` loop.
      test "a :block finding renders on the block's chrome, at its severity", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, findings: findings())

        assert has_element?(
                 view,
                 ~s([data-block-id="blk_variant"] > .sb-finding.sb-finding--warning),
                 "no handler registered for this invoke type"
               )
      end

      # Sabotage: `Field.field/1` dropping its `@field.findings` loop - the
      # message vanishes from beneath the input.
      test "a :config finding renders beneath its field, once selected", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, findings: findings())

        refute has_element?(view, ".sb-field .sb-finding"),
               "nothing is selected, so there is no form to render it in"

        view
        |> element(~s([data-block-id="blk_email_step"] > .sb-node__chrome > .sb-node__label))
        |> render_click()

        assert has_element?(
                 view,
                 ~s([data-field="duration"] > .sb-finding),
                 "far too long a wait"
               )
      end
    end

    describe "the Findings drawer tab (R4)" do
      # Sabotage: `Findings.findings/1` rendering `@view.tables` instead of
      # `@view.findings` - the count collapses to zero and the anchors below go
      # missing.
      test "lists every finding, whatever its anchor", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, findings: findings())
        html = open_findings(view)

        # Four supplied, plus the derived `:resolution` finding for the block
        # whose type this palette does not have.
        assert html =~ ~s(data-findings-count="5")

        for anchor <- [
              "block:blk_variant",
              "slot:blk_wizard:body",
              "config:blk_email_step:duration",
              "block:blk_deleted_long_ago"
            ] do
          assert has_element?(view, ~s(.sb-findings__list li[data-anchor="#{anchor}"]))
        end
      end

      # Sabotage: `Editor.render/1` keeping the `<Findings.findings>` call in
      # `.sb-editor__main` - the list renders a second time with no scope on
      # it, which is the position R4 retires.
      test "and nothing lists them under the canvas", %{conn: conn} do
        {:ok, view, html} = mount_editor(conn, findings: findings())

        refute html =~ "sb-findings"
        refute has_element?(view, ".sb-editor__main .sb-findings")
      end

      # A row is severity, subject, message. The subject carries both halves on
      # purpose: the label is what an author recognises and the id is what they
      # paste into a bug report.
      #
      # Sabotage: `Findings.row/1` rendering the anchor in place of
      # `Shell.label_for/2`'s answer - the row names a tuple rather than a
      # block and the label assertion goes red.
      test "a row carries its severity, its subject and its message", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, findings: findings())
        open_findings(view)

        row = ~s(li[data-anchor="config:blk_email_step:duration"])

        assert has_element?(view, "#{row} .sb-findings__severity", "error")
        assert has_element?(view, "#{row} .sb-findings__label", "Wait")
        assert has_element?(view, "#{row} .sb-findings__id", "blk_email_step")
        assert has_element?(view, "#{row} .sb-findings__message", "far too long a wait")
      end

      # D4's anatomy, the two cells the row did not carry before: which part of
      # the block the finding is about, and who says so. The tail is the half
      # of the anchor the subject does not already say - the subject is the
      # block, so the tail is the key or the slot name and nothing else.
      #
      # Sabotage: `anchor_tail/1`'s `{:config, _, _}` clause returning the
      # whole `anchor_tag/1` string - the row reads
      # "config:blk_email_step:duration", which repeats the id the subject
      # column already carries, and the first assertion goes red (verified).
      test "a row names the part of the block it is about, and its source", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, findings: findings())
        open_findings(view)

        config = ~s(li[data-anchor="config:blk_email_step:duration"])
        assert has_element?(view, "#{config} .sb-findings__anchor", "config.duration")
        assert has_element?(view, "#{config} .sb-findings__source", "config")

        slot = ~s(li[data-anchor="slot:blk_wizard:body"])
        assert has_element?(view, "#{slot} .sb-findings__anchor", "slot:body")
        assert has_element?(view, "#{slot} .sb-findings__source", "assignability")
      end

      # A `{:block, id}` finding's anchor IS its subject, so a tail would say
      # the id twice on the widest row in the list - the same reasoning the
      # orphan's subject already follows.
      #
      # Sabotage: `anchor_tail/1`'s `{:block, _}` clause returning
      # `"block:#{id}"` instead of nil - the block-anchored row grows a tail
      # and this refute goes red (verified).
      test "a block-anchored row has no tail, because its anchor is its subject", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, findings: findings())
        open_findings(view)

        block = ~s(li[data-anchor="block:blk_variant"])
        refute has_element?(view, "#{block} .sb-findings__anchor")
        assert has_element?(view, "#{block} .sb-findings__id", "blk_variant")
        assert has_element?(view, "#{block} .sb-findings__source", "lint")
      end

      # D2/D3: how much is wrong, in the enum's own words, above a list that is
      # still ordered by the document rather than by severity. Four supplied
      # plus the derived `:resolution` finding is five, of which one is the
      # `:lint` warning.
      #
      # Sabotage: `severity_pills/1` rendering `@counts` in `Enum.reverse/1` -
      # the warning pill leads the triage row and the ordering assertion goes
      # red (verified); dropping the pill row entirely makes all of them red.
      test "a pill row above the list says how many at each severity", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, findings: findings())
        html = open_findings(view)

        assert has_element?(view, ~s(.sb-findings__pills [data-severity="error"]), "4")
        assert has_element?(view, ~s(.sb-findings__pills [data-severity="warning"]), "1")
        refute has_element?(view, ~s(.sb-findings__pills [data-severity="info"]))

        # The pills sit above the list, not inside it: they summarise the rows
        # and are not one of them. D2: the list below is still the document's
        # order, so the pills are the only thing severity arranges.
        refute has_element?(view, ".sb-findings__list .sb-findings__pills")
        {pills, _len} = :binary.match(html, "sb-findings__pills")
        {list, _len} = :binary.match(html, "sb-findings__list")
        assert pills < list

        # Most urgent first. The first match of each is its pill, because the
        # pills are above the rows that carry the same stamp.
        {error_at, _len} = :binary.match(html, ~s(data-severity="error"))
        {warning_at, _len} = :binary.match(html, ~s(data-severity="warning"))
        assert error_at < warning_at
      end

      # C7: the stamp is `Shell.findings_count/1`'s answer and not a `length/1`
      # taken here. The two agree today, which is exactly why the coupling has
      # to be pinned by a mutation of the function rather than by a number.
      #
      # Sabotage: `Shell.findings_count/1` returning `length(findings) + 1` -
      # the stamp follows it to 6 and this goes red (verified). Replacing the
      # call with `length(@findings)` and repeating the mutation leaves the
      # stamp at 5 while the drawer's own chip reads 6, which is the
      # two-numbers defect that function was extracted to close.
      test "the stamped count is Shell.findings_count/1's", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, findings: findings())
        html = open_findings(view)

        assert html =~ ~s(data-findings-count="5")
      end

      # Sabotage: `Findings.findings/1` rendering a reveal button for orphans
      # too - clicking it would select a block that is not there.
      test "an orphan is listed but has nothing to reveal", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, findings: findings())
        open_findings(view)

        assert has_element?(view, ~s(li[data-orphan="true"] > .sb-findings__orphan))
        refute has_element?(view, ~s(li[data-orphan="true"] > .sb-findings__reveal))
        assert has_element?(view, ~s(li[data-orphan="false"] > .sb-findings__reveal))
      end

      # `Shell.label_for/2` falls back to the id for a block the tree does not
      # hold, so an orphan whose subject rendered both halves would say the
      # same thing twice across the row's widest column.
      #
      # Sabotage: `Findings.row/1` rendering the label unconditionally - the
      # orphan's subject carries two id spans and the refute goes red
      # (verified).
      test "an orphan's subject is its id and not its id twice", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, findings: findings())
        open_findings(view)

        orphan = ~s(li[data-anchor="block:blk_deleted_long_ago"])

        assert has_element?(view, "#{orphan} .sb-findings__id", "blk_deleted_long_ago")
        refute has_element?(view, "#{orphan} .sb-findings__label")
      end

      # Sabotage: the reveal button pushing an event other than "select" - the
      # block never gains the selected class.
      test "selecting an entry selects and reveals its anchor", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, findings: findings())
        open_findings(view)

        view
        |> element(~s(li[data-anchor="block:blk_variant"] > .sb-findings__reveal))
        |> render_click()

        assert has_element?(view, ~s([data-block-id="blk_variant"].sb-node--selected))

        # The reveal is a selection and not a navigation: the tab an author was
        # reading is still the tab they are on.
        assert has_element?(view, ~s(.sb-drawer[data-tab="findings"]))
      end

      test "a document with nothing wrong with it says so", %{conn: conn} do
        # Not the wizard: its unresolvable block always derives a `:resolution`
        # finding, which is decision 12 working rather than a defect.
        document = Document.new(EditorFixtures.wait("blk_only", "PT1H"), id: "doc_one_step")
        {:ok, view, _html} = mount_editor(conn, document: document)
        html = open_findings(view)

        assert html =~ "No findings."
        assert html =~ ~s(data-findings-count="0")
      end
    end

    # The rollup and the badge are two different things, and sb-vamn separated
    # them. `findings_count` - the rollup - is unchanged and still covers a
    # whole subtree, and it is on every node whether or not that node is
    # folded shut. The `.sb-badge` span that painted it on every container
    # face is still gone: ADR-0005 :461 and :1457 put that badge on a
    # **collapsed** subtree, so an expanded face carries none. The counts an
    # author reads on an open tree are the drawer's Findings tab and the
    # inspector's grouping, both of which consume the rollup.
    #
    # The collapsed case is asserted in `StatifierBlocks.Editor.CollapseTest`,
    # beside the fold that produces it. Nothing in this file collapses
    # anything, which is what makes the refute below an assertion about the
    # EXPANDED face rather than about the badge's existence.
    describe "the subtree rollup and the badge (d11's last sentence)" do
      # Sabotage: `ViewModel`'s `findings_count/3` counting only a node's own
      # findings rather than its whole subtree - the wizard's rollup drops
      # from 4 to 1 and this goes red.
      test "a node's rollup covers its whole subtree, so nothing can hide folded shut",
           %{conn: conn} do
        {:ok, _view, html} = mount_editor(conn, findings: findings())

        # Three supplied - one :slot on the wizard, one :block on the branch,
        # one :config on the wait - plus the `:resolution` finding `ViewModel`
        # derives for the unresolvable block. Only the first is the wizard's
        # own, and all four are inside its subtree.
        assert badge(html, "blk_wizard") == 4
        assert badge(html, "blk_variant") == 1
        assert badge(html, "blk_email_step") == 1
        assert badge(html, "blk_control_pause") == 0
      end

      # Sabotage: dropping the `@collapsed?` half of the badge's `:if` on
      # `BlockNode`'s chrome - the wizard's expanded face carries a count
      # again and this goes red.
      test "an expanded container with findings in its subtree renders no badge on its face",
           %{conn: conn} do
        {:ok, view, html} = mount_editor(conn, findings: findings())

        # The wizard is a container, nothing here has folded it, and its
        # subtree rollup is 4. The rollup is on the node; the badge is on no
        # face that is open.
        assert badge(html, "blk_wizard") == 4
        refute html =~ "sb-badge"
        refute has_element?(view, ".sb-badge")
      end
    end

    # The two clicks an author makes to reach the list: the strip opens the
    # drawer, and the tab is picked explicitly rather than left to the strip's
    # resolution rule, so these tests assert the tab's content and not that
    # rule (`StatifierBlocks.Editor.ShellTest` asserts the rule).
    defp open_findings(view) do
      view |> element(".sb-drawer__strip") |> render_click()
      view |> element(~s(.sb-drawer__tab[phx-value-tab="findings"])) |> render_click()
    end

    defp badge(html, block_id) do
      [_all, count] =
        Regex.run(~r/data-block-id="#{block_id}"[^>]*data-findings-count="(\d+)"/, html)

      String.to_integer(count)
    end
  end
end
