defmodule StatifierBlocks.PublishTest do
  @moduledoc """
  `StatifierBlocks.Publish.findings/3` with LiveView out of the picture
  (ADR-0004's Amendment of 2026-09-22, G4).

  The equality against the editor's own list needs a mounted editor and is
  `StatifierBlocks.Editor.PublishEqualityTest`'s. What is asserted here is
  the part a headless host relies on: the Document-stage refusal comes back
  alone and anchored on the document, a structure refusal reaches the list
  adapted, an undeclared datamodel path is a refusal when the document
  declares its own roots and the editor's `:info` advisory when only the
  host declares, and the function is total on a document whose tree is not
  a tree.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{
    Block,
    Compiler,
    CoreFixtures,
    Datamodel,
    Document,
    DocumentFixtures,
    Finding,
    Publish
  }

  alias StatifierBlocks.Document.DatamodelEntry

  # A datamodel document declaring the patron's email and nothing else.
  @datamodel %{
    "version" => 1,
    "scopes" => [%{"scope" => "local", "entries" => [%{"path" => "patron.email"}]}]
  }

  describe "the Document stage" do
    # The envelope is refused and one block's value is blank too, so the
    # editor's composition, had it run, would add its own Config finding.
    #
    # Sabotage: dropped step 3's early return, so the editor's composition
    # runs over the refused document - the view model's derived Config
    # finding joins the list and the equality goes red (verified).
    test "a Document-stage refusal is returned alone, anchored on the document" do
      document = %{blank(patron_registration(), "blk_PVER", "event") | revision: -1}

      assert [%Compiler.Finding{} = refusal] =
               Compiler.structure_findings(document, CoreFixtures.palette())

      assert Publish.findings(document, CoreFixtures.palette(), %{}) == [
               %Finding{
                 anchor: :document,
                 source: :compile,
                 severity: :error,
                 message: refusal.message
               }
             ]
    end

    # Sabotage: removed the Compiler's `in_document_order/2` clause for a
    # Document-stage refusal - this raises in `Document.blocks/1` (verified).
    test "never raises on a root that is not a block" do
      document = %{patron_registration() | root: "not a block"}

      assert [%Finding{anchor: :document, severity: :error}] =
               Publish.findings(document, CoreFixtures.palette(), %{})
    end
  end

  describe "the editor's composition" do
    # Sabotage: made `findings/3` pass `[]` as the caller findings of step 4
    # - the Config stage's refusal drops out and only the view model's own
    # derived copy of it is left, so the second assertion goes red
    # (verified).
    test "a Config refusal appears twice, derived and from the compile, as the editor shows it" do
      document = blank(patron_registration(), "blk_PVER", "event")
      findings = Publish.findings(document, CoreFixtures.palette(), %{})

      on_event = Enum.filter(findings, &(&1.anchor == {:config, "blk_PVER", "event"}))
      assert length(on_event) == 2
      assert Enum.map(on_event, & &1.source) == [:config, :config]
      assert Enum.all?(on_event, &(&1.severity == :error))
    end

    # The advisory is the editor's (11e), and a host refuses on `:error`
    # only. The block names a datamodel path the datamodel does not declare,
    # and the document declares no root of its own, so only the host has
    # declared anything and the advisory refuses nothing.
    #
    # Sabotage: made `findings/3` drop `Datamodel.findings/4` from step 4 -
    # the advisory is gone and the first assertion goes red (verified).
    # Sabotage: made `at_publish/2` raise the advisories whatever the
    # document declares - the severity assertion goes red (verified).
    test "an undeclared datamodel path is the editor's :info advisory, not a refusal" do
      document = with_note(patron_registration(), "patron.card_number")
      findings = Publish.findings(document, CoreFixtures.palette(), %{datamodel: @datamodel})

      assert [advisory] = Enum.filter(findings, &(&1.anchor == {:config, "blk_PNOTE", "path"}))
      assert advisory.severity == :info
      assert advisory.source == :lint
      assert advisory.message =~ "patron.card_number"
      refute Enum.any?(findings, &(&1.severity == :error))
    end

    # With no datamodel the advisory is off (11f), as the editor's default is.
    #
    # Sabotage: made step 4 default `:datamodel` to `[]` rather than `nil` -
    # an empty declared set flags the path and the refute goes red (verified).
    test "no datamodel in the context turns the advisory off, as the editor's default does" do
      document = with_note(patron_registration(), "patron.card_number")

      assert Publish.findings(document, CoreFixtures.palette(), %{}) ==
               Publish.findings(document, CoreFixtures.palette(), %{datamodel: nil})

      refute Enum.any?(
               Publish.findings(document, CoreFixtures.palette(), %{}),
               &(&1.severity == :info)
             )
    end
  end

  describe "an undeclared datamodel path where the document declares its roots" do
    # The document declares the root `patron`, and the note writes under a
    # misspelt root no surface declares.
    #
    # Sabotage: made `at_publish/2`'s condition false - the finding stays
    # `:info` and the severity match goes red (verified).
    test "is an :error finding, so the host's publish step refuses" do
      document = patron_registration() |> with_roots(["patron"]) |> with_note("patorn.email")
      findings = Publish.findings(document, CoreFixtures.palette(), %{})

      assert [refusal] = Enum.filter(findings, &(&1.anchor == {:config, "blk_PNOTE", "path"}))
      assert %Finding{severity: :error, source: :lint} = refusal
      assert refusal.message =~ "patorn.email"
    end

    # The anchor, source and message are the editor's advisory's; only the
    # severity moves.
    #
    # Sabotage: made `at_publish/2` also rewrite the message - the list
    # equality goes red (verified).
    test "is the editor's advisory raised to :error, the rest of it unchanged" do
      document = patron_registration() |> with_roots(["patron"]) |> with_note("patorn.email")
      findings = Publish.findings(document, CoreFixtures.palette(), %{})

      assert [advisory] = Datamodel.findings(document, CoreFixtures.palette(), nil, [])

      assert Enum.filter(findings, &(&1.anchor == advisory.anchor)) == [
               %{advisory | severity: :error}
             ]
    end

    # The host's datamodel and the document's roots are one declared set
    # (11k), so a path the host declares is no refusal: the host's datamodel
    # only ever clears a path.
    #
    # Sabotage: made step 4 hand `Datamodel.findings/4` `nil` for the
    # datamodel - `loan.due_on` is undeclared and the first refute goes red
    # (verified).
    test "a path the host's datamodel declares is not refused" do
      datamodel = ["loan.due_on"]

      document =
        patron_registration()
        |> with_roots(["patron"])
        |> with_note("loan.due_on")

      findings = Publish.findings(document, CoreFixtures.palette(), %{datamodel: datamodel})

      refute Enum.any?(findings, &(&1.anchor == {:config, "blk_PNOTE", "path"}))
      refute Enum.any?(findings, &(&1.severity == :error))
    end

    # A path under a declared root is declared (11l), so there is nothing
    # to refuse.
    #
    # Sabotage: made `Datamodel`'s `declared?/3` ignore the declared roots -
    # the path is flagged, raised to `:error`, and the refute goes red
    # (verified).
    test "a path under the document's own root is not refused" do
      document = patron_registration() |> with_roots(["patron"]) |> with_note("patron.email")

      refute Enum.any?(
               Publish.findings(document, CoreFixtures.palette(), %{}),
               &(&1.severity == :error)
             )
    end
  end

  describe "an undeclared datamodel path where only the host declares" do
    # The compile call's `:declare` roots are the host's too, and they do
    # not make the document's advisory a refusal.
    #
    # Sabotage: made step 4 hand `at_publish/2` the document with the
    # `:declare` roots added to its own - the advisory is raised and the
    # severity match goes red (verified).
    test "the host's :declare roots alone keep the :info advisory" do
      document = with_note(patron_registration(), "patorn.email")
      findings = Publish.findings(document, CoreFixtures.palette(), %{declare: [{"patron", nil}]})

      assert [%Finding{severity: :info, source: :lint}] =
               Enum.filter(findings, &(&1.anchor == {:config, "blk_PNOTE", "path"}))

      refute Enum.any?(findings, &(&1.severity == :error))
    end
  end

  # -- helpers -------------------------------------------------------------

  # The document's own `datamodel` key, declaring each root with no initial
  # value.
  defp with_roots(%Document{} = document, ids) do
    %{document | datamodel: Enum.map(ids, &%DatamodelEntry{id: &1})}
  end

  defp patron_registration do
    {:ok, document} = Document.from_json(DocumentFixtures.patron_registration_json())
    document
  end

  defp blank(%Document{root: root} = document, block_id, key) do
    %{document | root: update_block(root, block_id, &%{&1 | config: Map.put(&1.config, key, "")})}
  end

  # One `core.assign` at the head of the root's body, writing `path`.
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
