defmodule StatifierBlocks.ViewModel.DocumentAnchorTest do
  @moduledoc """
  The `:document` anchor in the view model and the shell (ADR-0005's
  Amendment of 2026-09-22, `11v` and `11w`).

  A `:document` finding names the document the list is about. It routes to no
  node, it is not an orphan, and it stays in `findings`, the document-level
  panel's source, so it is inside the number a host reads. The inspector's
  grouping puts it first, in a group of its own that says so.

  Also pinned: the one thing the amendment leaves undecided stays undecided.
  A host's `StatifierBlocks.DocumentValidator` returning a `:document` anchor
  is dropped, as any shape the validator seam does not recognise is.

  Pure: no LiveView module is named. The markup is
  `StatifierBlocks.Editor.PublishEqualityTest`'s.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Document, Finding, Palette, Shell, ViewModel}

  defmodule AnchorsOnTheDocument do
    @moduledoc "A host rule that tries the `:document` anchor."

    @behaviour StatifierBlocks.DocumentValidator

    @impl true
    def validate_document(%Document{}), do: [{:document, "the whole loan document is wrong"}]
  end

  defp document do
    Document.new(
      Block.new("core.sequence",
        id: "blk_LOAN",
        slots: %{
          "body" => [
            Block.new("core.await", id: "blk_RETURN", config: %{"event" => "copy.returned"})
          ]
        }
      ),
      id: "bdoc_LOAN"
    )
  end

  defp palette, do: Palette.new(Palette.core_types())

  defp document_finding,
    do: Finding.new(:document, :compile, "the document is not structurally valid")

  defp findings do
    [
      Finding.new({:block, "blk_RETURN"}, :lint, "no copy is ever returned", severity: :warning),
      document_finding(),
      Finding.new({:block, "blk_GONE"}, :resolution, "no such block any more")
    ]
  end

  describe "the view model (11w)" do
    # Sabotage: removed the `Enum.reject/2` of `:document` findings from
    # `ViewModel.build/3` - `finding_block_id/1` answers `nil`, no block holds
    # that id, and the finding lands in `orphan_findings` (verified).
    test "routes to no node and is not an orphan, and stays in findings" do
      vm = ViewModel.build(document(), palette(), findings())

      assert document_finding() in vm.findings
      refute document_finding() in vm.orphan_findings
      assert vm.orphan_findings == [Enum.at(findings(), 2)]
      refute document_finding() in all_node_findings(vm.root)
    end

    # The badge on a collapsed subtree does not count it: it belongs to no
    # subtree. The document's number does.
    #
    # Sabotage: replaced `ViewModel.build/3`'s reject of `:document` findings
    # with a rewrite of each one to `{:block, root_id}` - the finding is routed
    # onto the root, and its `findings_count` goes to 2 (verified).
    test "no node's count includes it, and the document's count does" do
      vm = ViewModel.build(document(), palette(), findings())

      assert vm.root.findings_count == 1
      assert Shell.findings_count(vm.findings) == 3
    end

    # Sabotage: added a `:document` clause to the validator seam's `anchor?/1`
    # - the host's finding is admitted and this goes red (verified).
    test "a host rule's :document anchor is dropped: that producer is not decided" do
      palette = Palette.new(Palette.core_types(), validators: [AnchorsOnTheDocument])
      vm = ViewModel.build(document(), palette, [])

      refute Enum.any?(vm.findings, &(&1.anchor == :document))
    end
  end

  describe "the inspector's grouping (11w)" do
    # Sabotage: made `prepend_document/2` append instead of prepend - the
    # document's group is no longer first and the first assertion goes red
    # (verified).
    test "the document's findings are one group, first, with document? true" do
      vm = ViewModel.build(document(), palette(), findings())
      groups = Shell.findings_groups(vm.root, vm.findings, vm.orphan_findings)

      assert Enum.map(groups, &{&1.block_id, &1.label, &1.document?}) == [
               {nil, "Document", true},
               {"blk_RETURN", "Wait for event", false},
               {nil, "Unanchored", false}
             ]

      assert hd(groups).findings == [document_finding()]

      total = groups |> Enum.flat_map(& &1.findings) |> length()
      assert total == Shell.findings_count(vm.findings)
    end
  end

  defp all_node_findings(%ViewModel.Node{} = node) do
    fields = if node.form, do: Enum.flat_map(node.form.fields, & &1.findings), else: []
    unrouted = if node.form, do: node.form.unrouted, else: []

    node.findings ++
      fields ++
      unrouted ++
      Enum.flat_map(node.slots, fn slot ->
        slot.findings ++ Enum.flat_map(slot.children, &all_node_findings/1)
      end)
  end
end
