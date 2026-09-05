if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.TrayTest do
    @moduledoc """
    The drafts tray as ADR-0005's amendment of 2026-08-31 leaves it:
    `slot_style: :tray` outside the rail partition (10s, 10t), no connector
    in or out or between (10u), and findings on the fragment by decision 11
    unchanged (11n).

    The two questions that record deferred to `sb-uag7` are answered here as
    well as in the record's absence: the tray is drawn in the canvas, last
    in the root's `body`, and a palette-to-tray drop is permitted.

    Geometry is `Connectors`' business and is asserted in
    `connectors_test.exs`; what this file asserts is the markup the editor
    actually renders.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.{Assignability, Block, Document, Palette, ViewModel}

    defp step(id, duration \\ "1h"),
      do: Block.new("core.wait", id: id, config: %{"duration" => duration})

    defp shelf(children),
      do: Block.new("core.drafts", id: "blk_SHELF", slots: %{"body" => children})

    # Two leaf fragments, so a shelf document and a shelf-free one produce
    # exactly the same edge set under the same measurement. A container
    # fragment is the subject of its own test below.
    defp fragments, do: [step("blk_F1", "9h"), step("blk_F2", "3h")]

    defp document(body) do
      Document.new(Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => body}),
        id: "bdoc_TRAY"
      )
    end

    defp with_shelf, do: document([step("blk_A"), shelf(fragments()), step("blk_B")])

    defp mount_tray(conn, doc \\ nil),
      do: mount_editor(conn, document: doc || with_shelf(), palette: Palette.core())

    # A non-empty tray opens FOLDED (`sb-e2zy`), so a test about what is
    # drawn inside it opens it first, through the same fold control an
    # author uses. Written as one helper rather than a line per test so the
    # tests below assert the tray's contents and not the fold.
    defp unfold(view) do
      view
      |> element(~s(.sb-node__fold[phx-value-block-id="blk_SHELF"]))
      |> render_click()

      view
    end

    defp mount_unfolded(conn, doc \\ nil) do
      {:ok, view, _html} = mount_tray(conn, doc)
      unfold(view)
    end

    describe "10s and 10t: the style, and the partition it is not in" do
      # Sabotage: dropped `:tray` from `ViewModel`'s `@slot_styles` - red
      # here, because 10i then degrades it to `:primary` and the shelf
      # renders as an ordinary body flow, connectors and all. That is the
      # one bad rendering 10v says the ordinary route cannot reach.
      test "the shelf's body carries the tray style and its own class", %{conn: conn} do
        view = mount_unfolded(conn)

        assert has_element?(view, ~s([data-parent-id="blk_SHELF"][data-slot-style="tray"]))
        assert has_element?(view, ~s([data-parent-id="blk_SHELF"].sb-slot--tray))
      end

      # Sabotage: added `:tray` to `ViewModel`'s `@rail_styles` - red here,
      # and a boundary box would be drawn around the root block of every
      # document that has a shelf: a frame around the entire workflow, to
      # say something about a shelf beside it (10t).
      test "a tray is no rail, and contributes no boundary", %{conn: conn} do
        view = mount_unfolded(conn)

        refute has_element?(view, ~s([data-parent-id="blk_SHELF"].sb-slot--rail))
        refute has_element?(view, ~s([data-parent-id="blk_SHELF"][data-exit-edge]))
        refute has_element?(view, ~s(.sb-node[data-block-id="blk_ROOT"].sb-node--boundary))
      end

      # Sabotage: made `body_slots/1` keep tray slots - red here, because
      # the shelf's contents would be counted as one of the things the
      # container fans into.
      test "the tray is not one of the container's body slots" do
        vm = ViewModel.build(with_shelf(), Palette.core(), [])

        shelf_node =
          Enum.find(vm.root.slots |> hd() |> Map.fetch!(:children), &ViewModel.shelf?/1)

        assert [%{name: "body", style: :tray}] = shelf_node.slots
        assert ViewModel.body_slots(shelf_node) == []
        assert ViewModel.arrangement(shelf_node) == :stack
        refute ViewModel.boundary?(shelf_node)
      end
    end

    describe "10u: no connector, in or out or between" do
      # Sabotage: dropped the `not ViewModel.tray?(slot)` guard from
      # `Connectors.adjacency_edges/2` - red here on the edge that appears
      # between the two fragments. An edge between two parked cards asserts
      # a sequencing relationship no compiler stage reads and no runtime can
      # ever produce.
      test "no edge leaves a fragment, enters the tray, or leaves it" do
        starts = edge_starts(with_shelf())

        # The three edges a shelf-free document of this shape draws, and
        # nothing else: the root into its first step, that step into the
        # next, and no more.
        refute MapSet.member?(starts, outlet_point("blk_F1")),
               "an edge runs between the two fragments"

        refute MapSet.member?(starts, outlet_point("blk_SHELF")), "an edge leaves the tray"
        refute MapSet.member?(starts, card_point("blk_SHELF")), "an edge enters the tray"
      end

      # The same rule read from the other end, and the reason it is worth its
      # own assertion (`sb-e2zy`): every refute above names a point an edge
      # STARTS from, and an edge entering the shelf does not start there - it
      # ends there, at the anchor card's inlet. The campaign-024 wrap ruling
      # is that this card takes no inbound arrow at any zoom, because an
      # arrow into it is what makes the shelf read as a trailing step.
      #
      # Sabotage: read `slot.children` instead of `ViewModel.flow_children/1`
      # in `adjacency_edges/2` - red here, on an edge from the step before
      # the shelf into the shelf's own card.
      test "no edge ends on the shelf's anchor card" do
        ends = edge_ends(with_shelf())

        refute MapSet.member?(ends, card_inlet("blk_SHELF")),
               "an edge lands on the drafts anchor card"

        # The flow's own inbound edges are untouched, so the refute above is
        # about the shelf and not about the assertion finding nothing.
        assert MapSet.member?(ends, card_inlet("blk_B"))
      end

      # Sabotage: read `slot.children` instead of `ViewModel.flow_children/1`
      # in `adjacency_edges/2` - red here. G9a's rendering counterpart is
      # that the sibling before the shelf is adjacent to the sibling after
      # it, so the flow reads exactly the same with a shelf in the document
      # as without one.
      test "the flow is byte-identical with a shelf in the document and without" do
        with_it = edge_paths(with_shelf())
        without_it = edge_paths(document([step("blk_A"), step("blk_B")]))

        assert with_it == without_it
        assert MapSet.member?(edge_starts(with_shelf()), outlet_point("blk_A"))
      end

      # 10u's other half, stated as its own assertion because it is the one
      # a suppression rule is most likely to over-reach and break: inside a
      # parked fragment the child order IS sequencing, and drawing it as
      # anything else would hide the thing the author parked it to keep
      # working on.
      #
      # Sabotage: suppressed edges for every descendant of a shelf rather
      # than for the tray slot itself - red here.
      test "a fragment's own internal connectors are drawn normally" do
        nested =
          document([
            step("blk_A"),
            Block.new("core.drafts",
              id: "blk_SHELF",
              slots: %{
                "body" => [
                  Block.new("core.sequence",
                    id: "blk_F1",
                    slots: %{"body" => [step("blk_IN1"), step("blk_IN2")]}
                  )
                ]
              }
            ),
            step("blk_B")
          ])

        starts = edge_starts(nested)

        assert MapSet.member?(starts, card_point("blk_F1")), "the fragment draws no entry edge"
        assert MapSet.member?(starts, outlet_point("blk_IN1")), "the fragment draws no flow"
      end
    end

    describe "11n: findings render on the fragment" do
      # Sabotage: filtered parked findings out of the document panel - red
      # here, and an author could not find the problem they parked the
      # fragment because of.
      test "a config finding on a parked block reaches its card and the panel", %{conn: conn} do
        broken = document([step("blk_A"), shelf([step("blk_PARKED", "not a duration")])])
        {:ok, view, _html} = mount_tray(conn, broken)

        # A folded tray cannot hide it, which since `sb-e2zy` is the case an
        # author sees FIRST: the shelf opens folded and 11n's count badge on
        # the collapsed subtree is what says there is something in there to
        # look at.
        assert has_element?(view, ~s([data-block-id="blk_SHELF"] .sb-badge))

        # And unfolded, the anchor names a block id, the block is in the
        # document, and where its findings are drawn is where the block is
        # drawn.
        view = unfold(view)
        assert has_element?(view, ~s([data-block-id="blk_PARKED"][data-findings-count="1"]))

        # And it is in the document-level panel's source rather than filtered
        # out of it, which is what would leave an author unable to find the
        # problem they parked the fragment because of. Asserted on the list
        # the panel renders from rather than on the drawer tab, so the
        # assertion is about the routing and not about which tab is open.
        vm = ViewModel.build(broken, Palette.core(), [])

        assert Enum.any?(vm.findings, &match?({:config, "blk_PARKED", _key}, &1.anchor))
        assert vm.orphan_findings == []
      end

      # Sabotage: anchored `:draft_blocks_present` on the first fragment
      # rather than on the shelf - red here. It says something about the
      # document rather than about anybody's work, so it lands on the tray's
      # own chrome.
      test ":draft_blocks_present renders on the tray itself", %{conn: conn} do
        findings =
          with_shelf()
          |> then(&StatifierBlocks.Compiler.compile(&1, Palette.core()))
          |> then(fn {:ok, compiled} -> compiled.warnings end)
          |> Enum.flat_map(fn finding ->
            case StatifierBlocks.Finding.from_compiler(finding, []) do
              {:ok, presented} -> [presented]
              _other -> []
            end
          end)

        {:ok, view, _html} =
          mount_editor(conn, document: with_shelf(), palette: Palette.core(), findings: findings)

        # Unfolded, so the refute is about where the finding landed and not
        # about the fragment being inside something folded shut.
        view = unfold(view)

        assert has_element?(view, ~s([data-block-id="blk_SHELF"][data-findings-count="1"]))
        refute has_element?(view, ~s([data-block-id="blk_F1"][data-findings-count="1"]))
      end
    end

    describe "sb-e2zy: a non-empty tray opens folded" do
      # Sabotage: had `Editor.opening_folds/1` answer `MapSet.new()` - red
      # here. At default zoom a shelf holding a couple of fragments is taller
      # than the flow above it, and an author who opened the document to read
      # the workflow got the parked work instead.
      test "the shelf is collapsed on mount, and its tray is not drawn", %{conn: conn} do
        {:ok, view, _html} = mount_tray(conn)

        assert has_element?(view, ~s([data-block-id="blk_SHELF"][data-collapsed="true"]))
        refute has_element?(view, ~s([data-parent-id="blk_SHELF"][data-slot-style="tray"]))
        refute has_element?(view, ~s([data-block-id="blk_F1"]))
      end

      # Sabotage: dropped the `stocked?/1` filter - red here. The tray of an
      # empty shelf IS the drop target the first fragment is parked onto, so
      # folding it shut folds away the affordance.
      test "an empty shelf opens as it always did", %{conn: conn} do
        {:ok, view, _html} = mount_tray(conn, document([step("blk_A"), shelf([])]))

        assert has_element?(view, ~s([data-block-id="blk_SHELF"][data-collapsed="false"]))
        assert has_element?(view, ~s([data-parent-id="blk_SHELF"][data-slot-style="tray"]))
      end

      # The fold is the INITIAL value and nothing else: decision 2's
      # amendment of 2026-08-30 keeps owning the control, the set stays out
      # of the document and off the undo stack, and an author who opens the
      # tray keeps it open for the rest of the session.
      #
      # Sabotage: recomputed the folds in `rebuild/1` rather than only on the
      # opening - red here on the second assertion, and the tray would slam
      # shut under the author on the next edit.
      test "unfolding sticks across an edit", %{conn: conn} do
        view = mount_unfolded(conn)

        assert has_element?(view, ~s([data-block-id="blk_SHELF"][data-collapsed="false"]))

        view
        |> element(~s(.sb-node__remove[phx-value-block-id="blk_A"]))
        |> render_click()

        assert has_element?(view, ~s([data-block-id="blk_SHELF"][data-collapsed="false"]))
      end

      # The reset in `switch_document/2` resets TO the opening folds, so a
      # document the host swaps in opens the way the same document opens when
      # it is the first one - the sentence the fit note had to write for its
      # own opening, applied to this fold.
      #
      # Sabotage: left `collapsed_ids: MapSet.new()` in `switch_document/2` -
      # red here, and the same document would look different depending on
      # whether it was opened or swapped in.
      test "a document swapped in opens folded too", %{conn: conn} do
        view = mount_unfolded(conn, document([step("blk_A"), shelf([])]))

        swapped =
          Document.new(
            Block.new("core.sequence",
              id: "blk_ROOT",
              slots: %{"body" => [step("blk_A"), shelf(fragments())]}
            ),
            id: "bdoc_OTHER"
          )

        send(view.pid, {:swap_document, swapped})
        render(view)

        assert has_element?(view, ~s([data-block-id="blk_SHELF"][data-collapsed="true"]))
      end
    end

    describe "the two answers this bead owed the record" do
      # Where the tray is drawn: the canvas, at the foot. The shelf renders
      # after its slot's flow children, and G12a admits it only as a direct
      # child of the root's `body`, so "last in the root's body" is a strip
      # at the foot of the canvas.
      #
      # Sabotage: dropped the `Enum.sort_by/2` from `Slot.shelf_last/1` -
      # red here, and the shelf would sit wherever in the flow the author
      # happened to drop it, reading as a step between two steps.
      test "the shelf is drawn after its slot's flow children", %{conn: conn} do
        {:ok, _view, html} = mount_tray(conn)

        assert index(html, ~s(data-block-id="blk_A")) < index(html, ~s(data-block-id="blk_SHELF"))
        assert index(html, ~s(data-block-id="blk_B")) < index(html, ~s(data-block-id="blk_SHELF"))
      end

      # Sabotage: suppressed every gap in the slot rather than the shelf's -
      # red here on the surviving gaps, which is what keeps the flow's own
      # insertion points where they were.
      test "the shelf carries no trailing gap, and the flow keeps its own", %{conn: conn} do
        {:ok, view, _html} = mount_tray(conn)

        assert has_element?(view, ~s(.sb-gap[data-parent-id="blk_ROOT"][data-index="0"]))
        assert has_element?(view, ~s(.sb-gap[data-parent-id="blk_ROOT"][data-index="1"]))
        refute has_element?(view, ~s(.sb-gap[data-parent-id="blk_ROOT"][data-index="2"]))
      end

      # A palette-to-tray drop is permitted, by doing nothing: a drop is an
      # Insert and the tray's `slot_accepts` is `:any` (A1), so the existing
      # target computation already admits it. Forbidding it would take new
      # machinery to refuse what the declaration admits, and it would refuse
      # hardest the half-built fragment the shelf exists to hold.
      #
      # Sabotage: narrowed `Core.Drafts.io/1`'s `"body"` to `[:step]` - red
      # on the handler, which is the case that says the answer is A1's `:any`
      # and not an accident of which types were tried.
      test "the tray is a valid drop target for anything" do
        doc = with_shelf()

        for candidate <- [
              step("blk_NEW"),
              Block.new("core.on_event", id: "blk_H", config: %{"event" => "x.y"}),
              Block.new("core.group", id: "blk_G")
            ] do
          targets = Assignability.valid_targets(Palette.core(), doc, candidate, %{})

          assert Enum.any?(targets, &match?({"blk_SHELF", "body", _index}, &1)),
                 "the tray refused #{candidate.type}"
        end
      end
    end

    # One box per block, laid out so every anchor point is distinct: a card
    # at y = 100*n and an outlet at y = 100*n + 40, each 200 wide from x = 0,
    # so the point an edge leaves from is (100, y). Nothing here is asserted
    # for its arithmetic - the coordinates exist so that "which edge" can be
    # named by "from where".
    @boxes ~w(blk_ROOT blk_A blk_SHELF blk_F1 blk_F2 blk_B blk_IN1 blk_IN2)

    defp measurement do
      base = %{"stage" => rect(0, 0, 200, 1000)}

      @boxes
      |> Enum.with_index(1)
      |> Enum.reduce(base, fn {id, n}, acc ->
        acc
        |> Map.put("card:#{id}", rect(0, 100 * n, 200, 30))
        |> Map.put("outlet:#{id}", rect(0, 100 * n + 40, 200, 0))
      end)
    end

    defp rect(x, y, w, h),
      do: %StatifierBlocks.Connectors.Rect{x: x / 1, y: y / 1, width: w / 1, height: h / 1}

    defp position(id), do: 100 * (Enum.find_index(@boxes, &(&1 == id)) + 1)
    # A card is the SOURCE of an entry edge from its bottom edge; the
    # outlet is a zero-height box and is its own point.
    defp card_point(id), do: "M 100 #{position(id) + 30}"
    defp outlet_point(id), do: "M 100 #{position(id) + 40}"
    # And the TARGET of one is the card's top edge, which is where the
    # arrowhead is drawn.
    defp card_inlet(id), do: "L 100 #{position(id)}"

    defp edges(doc) do
      doc
      |> ViewModel.build(Palette.core(), [])
      |> Map.fetch!(:root)
      |> StatifierBlocks.Connectors.edges(measurement())
    end

    defp edge_paths(doc), do: doc |> edges() |> Enum.map(& &1.d) |> MapSet.new()

    defp edge_starts(doc) do
      doc
      |> edges()
      |> Enum.map(fn edge -> edge.d |> String.split(" ") |> Enum.take(3) |> Enum.join(" ") end)
      |> MapSet.new()
    end

    defp edge_ends(doc) do
      doc
      |> edges()
      |> Enum.map(fn edge -> edge.d |> String.split(" ") |> Enum.take(-3) |> Enum.join(" ") end)
      |> MapSet.new()
    end

    defp index(html, needle) do
      {start, _length} = :binary.match(html, needle)
      start
    end
  end
end
