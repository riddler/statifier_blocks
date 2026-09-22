# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that mounts it. `Publish.findings/3` itself is
# pure and is asserted headless in `StatifierBlocks.PublishTest`; the claim
# here is about the editor, and only a mounted editor renders its list.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.PublishEqualityTest do
    @moduledoc """
    `Publish.findings/3` is the editor's list (ADR-0004's Amendment of
    2026-09-22, G4, and ADR-0005's companion Amendment, `11v` to `11x`).

    The equality G4 names: for a document the Document stage accepts, the
    publish entry's findings equal the findings the editor shows for the same
    document, palette and context when the editor is handed the adapted
    `Compiler.structure_findings/3` list as its caller findings - finding for
    finding, order included - and `Editor.findings_count/3` over the same
    inputs is its length.

    The editor's list is read off the page, not recomputed: every row of the
    drawer's Findings tab carries the whole anchor (`data-anchor`), the
    source, the severity and the message, which is every field of a
    `StatifierBlocks.Finding`. Each row is read back into a struct and the
    two lists are compared as terms. A test that rebuilt the editor's
    composition here would be comparing `Publish` with a copy of itself.

    The documents are the two stored fixtures, read and never extended, and
    each with one value blanked so the compile refuses; the several-sources
    case, the undeclared-path case and the Document-stage case use the patron
    registration fixture.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.{Compiler, CoreFixtures, DocumentFixtures, Editor, Publish}

    @datamodel %{
      "version" => 1,
      "scopes" => [%{"scope" => "local", "entries" => [%{"path" => "patron.email"}]}]
    }

    describe "the editor's list, finding for finding" do
      # Sabotage: made step 4 of `Publish.findings/3` hand `ViewModel.build/3`
      # the advisories before the adapted list - red at the several-sources
      # case, where the editor draws the compile's findings first (verified).
      test "over both stored fixtures, as stored and with one value blanked", %{conn: conn} do
        for {document, context} <- equality_cases() do
          published = Publish.findings(document, CoreFixtures.palette(), context)

          assert editor_list(conn, document, context) == published
          assert findings_count(document, context) == length(published)
        end
      end

      # The blanked cases are the ones where the caller findings are not empty,
      # so they are the cases the equality is about. Pinned on its own so a
      # fixture that stopped refusing could not turn the loop above into a
      # comparison of two lists with nothing from the compile in them.
      #
      # Sabotage: made `Compiler.structure_findings/3` return `[]` always - red
      # at the first blanked case (verified).
      test "the blanked fixtures do hand the editor structure findings" do
        for {document, context} <- equality_cases(), document.id in blanked_ids() do
          refute adapted_structure(document, context) == []
        end
      end

      # Sabotage: made `Publish.findings/3` drop `Datamodel.findings/4` from
      # step 4 - the editor still draws the advisory and the equality goes red
      # (verified).
      test "an undeclared datamodel path is the same :info advisory on both", %{conn: conn} do
        document = with_note(patron_registration(), "patron.card_number")
        context = %{datamodel: @datamodel}
        published = Publish.findings(document, CoreFixtures.palette(), context)

        assert editor_list(conn, document, context) == published
        assert [%Finding{severity: :info, source: :lint}] = published
      end
    end

    describe "a Document-stage finding in the editor (11w)" do
      setup do
        document = %{patron_registration() | revision: -1}
        [finding] = Publish.findings(document, CoreFixtures.palette(), %{})
        %{document: document, finding: finding}
      end

      # Sabotage: made `ViewModel.build/3` split `:document` findings with the
      # rest - `finding_block_id/1` answers `nil`, the finding lands in
      # `orphan_findings`, and the row is stamped `data-orphan="true"`
      # (verified).
      test "the drawer lists it as a span with nothing to select, and counts it",
           %{conn: conn, document: document, finding: finding} do
        {:ok, view, _html} = mount_editor(conn, document: document, findings: [finding])
        open_findings(view)

        row = ~s(li.sb-findings__row[data-anchor="document"])
        assert has_element?(view, ~s(#{row}[data-orphan="false"] > .sb-findings__document))
        refute has_element?(view, "#{row} button")
        assert has_element?(view, "#{row} .sb-findings__label", "Document")
        refute has_element?(view, "#{row} .sb-findings__id")

        assert Editor.findings_count(document, CoreFixtures.palette(), findings: [finding]) ==
                 length(editor_rows(view))
      end

      # Sabotage: dropped `prepend_document/2` from `Shell.findings_groups/3` -
      # the finding has no group and the heading assertion goes red (verified).
      test "the inspector lists it first, as the document's group, with nothing to select",
           %{conn: conn, document: document, finding: finding} do
        {:ok, view, _html} = mount_editor(conn, document: document, findings: [finding])

        view |> element(~s(.sb-inspector__tab[phx-value-tab="findings"])) |> render_click()

        group = ~s(.sb-inspector__group[data-document="true"])
        assert has_element?(view, ~s(#{group}[data-unanchored="false"]))
        assert has_element?(view, "#{group} .sb-inspector__group-title", "Document")
        assert has_element?(view, ~s(#{group} li[data-anchor="document"] span.sb-findings__cells))
        refute has_element?(view, "#{group} button")
      end
    end

    # -- helpers -----------------------------------------------------------

    defp equality_cases do
      [
        {worked_example(), %{}},
        {signup_wizard(), %{}},
        {blank(worked_example(), "blk_WAI", "duration", "bdoc_BLANKED_WORKED"), %{}},
        {blank(signup_wizard(), "blk_WINT", "event", "bdoc_BLANKED_WIZARD"), %{}},
        {several_sources(), %{datamodel: @datamodel}}
      ]
    end

    defp blanked_ids, do: ["bdoc_BLANKED_WORKED", "bdoc_BLANKED_WIZARD", "bdoc_PATRON_SEVERAL"]

    # Findings from four places at once, so the order between them is
    # observable: the view model's derived Config finding, the compile's
    # Config and Structure findings handed in as caller findings, and the
    # undeclared-path advisory after them. The patron's event is blanked, a
    # deadline block carries a slot its type does not declare, and a note
    # writes a path the datamodel does not declare.
    defp several_sources do
      extra =
        Block.new("core.assign",
          id: "blk_PEXTRA",
          config: %{"path" => "patron.email", "value" => "1"}
        )

      document =
        patron_registration()
        |> blank("blk_PVER", "event", "bdoc_PATRON_SEVERAL")
        |> with_note("patron.card_number")

      %{
        document
        | root:
            update_block(
              document.root,
              "blk_PDLN",
              &%{&1 | slots: Map.put(&1.slots, "later", [extra])}
            )
      }
    end

    # The caller findings G4 hands the editor.
    defp adapted_structure(document, context) do
      opts = context |> Map.take([:datamodel, :declare]) |> Enum.to_list()
      structure = Compiler.structure_findings(document, CoreFixtures.palette(), opts)
      {adapted, []} = Finding.from_compiler_all(structure)
      adapted
    end

    defp findings_count(document, context) do
      Editor.findings_count(
        document,
        CoreFixtures.palette(),
        [findings: adapted_structure(document, context)] ++ Enum.to_list(context)
      )
    end

    # Mounts the editor on the adapted structure findings and reads its
    # drawer back into findings.
    defp editor_list(conn, document, context) do
      {:ok, view, _html} =
        mount_editor(
          conn,
          [
            document: document,
            palette: CoreFixtures.palette(),
            findings: adapted_structure(document, context)
          ] ++ Enum.to_list(context)
        )

      open_findings(view)
      editor_rows(view)
    end

    defp open_findings(view) do
      view |> element(".sb-drawer__strip") |> render_click()
      view |> element(~s(.sb-drawer__tab[phx-value-tab="findings"])) |> render_click()
    end

    defp editor_rows(view) do
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("li.sb-findings__row")
      |> Enum.map(&row_finding/1)
    end

    defp row_finding(row) do
      [anchor] = LazyHTML.attribute(row, "data-anchor")
      [source] = LazyHTML.attribute(row, "data-source")
      [severity] = LazyHTML.attribute(row, "data-severity")
      message = row |> LazyHTML.query(".sb-findings__message") |> LazyHTML.text()

      %Finding{
        anchor: anchor(anchor),
        source: String.to_existing_atom(source),
        severity: String.to_existing_atom(severity),
        message: message
      }
    end

    defp anchor("document"), do: :document

    defp anchor(tag) do
      case String.split(tag, ":", parts: 3) do
        ["config", id, key] -> {:config, id, key}
        ["slot", id, name] -> {:slot, id, name}
        ["block", id] -> {:block, id}
      end
    end

    defp worked_example, do: decode(DocumentFixtures.worked_example_json())
    defp signup_wizard, do: decode(DocumentFixtures.signup_wizard_json())
    defp patron_registration, do: decode(DocumentFixtures.patron_registration_json())

    defp decode(json) do
      {:ok, document} = Document.from_json(json)
      document
    end

    defp blank(%Document{root: root} = document, block_id, key, id) do
      %{
        document
        | id: id,
          root: update_block(root, block_id, &%{&1 | config: Map.put(&1.config, key, "")})
      }
    end

    defp with_note(%Document{root: root} = document, path) do
      note = Block.new("core.assign", id: "blk_PNOTE", config: %{"path" => path, "value" => "1"})
      %{document | root: %{root | slots: Map.update!(root.slots, "body", &[note | &1])}}
    end

    defp update_block(%Block{id: id} = block, id, fun), do: fun.(block)

    defp update_block(%Block{slots: slots} = block, id, fun) do
      %{
        block
        | slots:
            Map.new(slots, fn {name, children} ->
              {name, Enum.map(children, &update_block(&1, id, fun))}
            end)
      }
    end
  end
end
