# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The rule these assert the
# *rendering* of is pure and lives in `StatifierBlocks.DatamodelTest`, which
# is deliberately outside this guard.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.DatamodelTest do
    @moduledoc """
    ADR-0005 amendment 11g: the undeclared-path advisory arrives through the
    findings pane, and there is no second channel.

    What the pure test cannot assert is the half that only exists once there
    is markup - that an `:info` finding really does reach the document-level
    panel and the field beneath its control, at its own severity, through the
    routing every other finding already used. That is the claim 11g makes and
    it is the only reason these tests need a mounted editor.
    """

    use StatifierBlocks.EditorLiveCase

    @declared ["signup.step", "signup.variant_id"]

    defp document do
      Document.new(
        Block.new("core.sequence",
          id: "blk_wizard",
          slots: %{
            "body" => [
              Block.new("core.assign",
                id: "blk_variant_write",
                config: %{"path" => "signup.variant", "value" => "\"b\""}
              )
            ]
          }
        ),
        id: "doc_signup_wizard"
      )
    end

    defp mount_wizard(conn, opts) do
      mount_editor(conn, Keyword.put(opts, :document, document()))
    end

    # The document-level list is the drawer's Findings tab since operator
    # ruling R4 (2026-08-29), so reaching it is two clicks rather than a look
    # at the mounted markup.
    defp open_findings(view) do
      view |> element(".sb-drawer__strip") |> render_click()
      view |> element(~s(.sb-drawer__tab[phx-value-tab="findings"])) |> render_click()
    end

    describe "with a datamodel supplied" do
      # sabotage: `Editor.rebuild/1` passing `findings` instead of
      # `findings ++ advisories` to `ViewModel.build/3` - the advisory never
      # reaches the view model, the count stays 0 and this goes red
      # (verified).
      test "an undeclared path is listed in the findings tab", %{conn: conn} do
        {:ok, view, _html} = mount_wizard(conn, datamodel: @declared)
        html = open_findings(view)

        assert html =~ ~s(data-findings-count="1")

        assert has_element?(
                 view,
                 ~s(.sb-findings__list li[data-anchor="config:blk_variant_write:path"]),
                 "signup.variant is not declared in the datamodel"
               )
      end

      # sabotage: `Finding.severity_class/1`'s `:info` clause removed - the
      # entry renders as `sb-finding--error`, which would tell the author a
      # compilable document is broken, and both assertions here go red
      # (verified).
      test "it renders at :info severity, from the :lint source", %{conn: conn} do
        {:ok, view, _html} = mount_wizard(conn, datamodel: @declared)
        open_findings(view)

        assert has_element?(
                 view,
                 ~s(.sb-findings__list li.sb-finding--info[data-severity="info"][data-source="lint"])
               )
      end

      # sabotage: `Editor.update/3`'s normalization clause removed -
      # `declared_paths` stays `nil` however the host assigns `datamodel`,
      # so nothing is produced and this goes red (verified).
      test "it also renders beneath the annotated field once selected", %{conn: conn} do
        {:ok, view, _html} = mount_wizard(conn, datamodel: @declared)

        view
        |> element(~s([data-block-id="blk_variant_write"] > .sb-node__chrome > .sb-node__label))
        |> render_click()

        assert has_element?(
                 view,
                 ~s([data-field="path"] > .sb-finding.sb-finding--info),
                 "signup.variant is not declared in the datamodel"
               )
      end

      # sabotage: the advisory anchored `{:block, id}` rather than
      # `{:config, id, "path"}` - it still lists in the panel, so only this
      # test catches the misrouting, which is why the declared case is
      # asserted from the rendered side too (verified).
      test "a declared path renders nothing", %{conn: conn} do
        {:ok, view, _html} = mount_wizard(conn, datamodel: ["signup.variant"])
        html = open_findings(view)

        assert html =~ ~s(data-findings-count="0")
        refute html =~ "not declared in the datamodel"
      end
    end

    describe "with no datamodel supplied (11f)" do
      # sabotage: `Datamodel.findings/3`'s `nil` arm falling through to
      # `undeclared_findings/3` with an empty set - the document the host
      # said nothing about fills with advisories, the count goes to 1 and
      # this goes red (verified).
      test "the tab says there are no findings at all", %{conn: conn} do
        {:ok, view, _html} = mount_wizard(conn, [])
        html = open_findings(view)

        assert html =~ ~s(data-findings-count="0")
        assert has_element?(view, ".sb-findings__empty", "No findings.")
        refute html =~ "not declared in the datamodel"
      end

      # The mount default is reachable only from a host that never passes
      # the assign at all, which no mounted-editor test can express: the
      # case template always passes one. So it is asserted where it lives.
      #
      # sabotage: `Editor.mount/1` defaulting `declared_paths` to
      # `MapSet.new([])` rather than `nil` - a host that never opts in gets
      # an advisory on every annotated field, and this goes red (verified).
      test "a host that never passes the assign gets no datamodel, not an empty one" do
        {:ok, socket} = StatifierBlocks.Editor.mount(%Phoenix.LiveView.Socket{})

        assert socket.assigns.datamodel == nil
        assert socket.assigns.declared_paths == nil
      end
    end
  end
end
