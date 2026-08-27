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
    block's chrome, that the document-level panel lists all of them, and that a
    collapsed subtree still carries a count - because a finding that can hide
    inside something folded shut is the failure mode that makes tree editors
    feel unreliable.
    """

    use StatifierBlocks.EditorLiveCase

    defp findings do
      [
        Finding.new({:block, "blk_variant"}, :lint, "no handler registered for this invoke type",
          severity: :warning
        ),
        Finding.new({:slot, "blk_wizard", "body"}, :arity, "this slot wants at least one step"),
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

    describe "the document-level panel" do
      # Sabotage: `Findings.findings/1` rendering `@view_model.root.findings`
      # instead of `@view_model.findings` - the count collapses to the root's
      # own and the anchors below go missing.
      test "lists every finding, whatever its anchor", %{conn: conn} do
        {:ok, view, html} = mount_editor(conn, findings: findings())

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

      # Sabotage: `Findings.findings/1` rendering a reveal button for orphans
      # too - clicking it would select a block that is not there.
      test "an orphan is listed but has nothing to reveal", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, findings: findings())

        assert has_element?(view, ~s(li[data-orphan="true"] > .sb-findings__orphan))
        refute has_element?(view, ~s(li[data-orphan="true"] > .sb-findings__reveal))
        assert has_element?(view, ~s(li[data-orphan="false"] > .sb-findings__reveal))
      end

      # Sabotage: the reveal button pushing an event other than "select" - the
      # block never gains the selected class.
      test "selecting an entry selects and reveals its anchor", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, findings: findings())

        view
        |> element(~s(li[data-anchor="block:blk_variant"] > .sb-findings__reveal))
        |> render_click()

        assert has_element?(view, ~s([data-block-id="blk_variant"].sb-node--selected))
      end

      test "a document with nothing wrong with it says so", %{conn: conn} do
        # Not the wizard: its unresolvable block always derives a `:resolution`
        # finding, which is decision 12 working rather than a defect.
        document = Document.new(EditorFixtures.wait("blk_only", "PT1H"), id: "doc_one_step")
        {:ok, _view, html} = mount_editor(conn, document: document)

        assert html =~ "No findings."
        assert html =~ ~s(data-findings-count="0")
      end
    end

    describe "the count badge (d11's last sentence)" do
      # Sabotage: `ViewModel`'s `findings_count/3` counting only a node's own
      # findings rather than its whole subtree - the wizard's badge drops from
      # 3 to 1 and this goes red.
      test "a node's badge covers its whole subtree, so nothing hides folded shut", %{conn: conn} do
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
    end

    defp badge(html, block_id) do
      [_all, count] =
        Regex.run(~r/data-block-id="#{block_id}"[^>]*data-findings-count="(\d+)"/, html)

      String.to_integer(count)
    end
  end
end
