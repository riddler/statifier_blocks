# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*, which is the earlier
# of the two problems.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.CollapseTest do
    @moduledoc """
    A container folds shut: ADR-0005's amendment to decision 2 (2026-08-30).

    The load-bearing claim is the one about *where the state lives*. Collapse
    is not a fifth `Edit` command - decision 2's four are the document's
    algebra and they are unchanged - so what these tests drive is the shell:
    one server event, one `MapSet` beside `selected_id`, nothing serialized,
    nothing on the undo stack, and a reset on a document switch exactly like
    the selection's.

    Every selector here is scoped to `.sb-node`. `.sb-palette` has carried a
    `data-collapsed` of its own since the pane fold shipped, so a bare
    `[data-collapsed]` assertion would pass or fail for the wrong element.
    """

    use StatifierBlocks.EditorLiveCase

    # The wizard's own body findings, one per depth, so a rollup on a folded
    # container has something to be a rollup *of*.
    defp findings do
      [
        Finding.new({:block, "blk_variant"}, :lint, "no handler registered for this invoke type",
          severity: :warning
        ),
        Finding.new({:config, "blk_email_step", "duration"}, :config, "far too long a wait")
      ]
    end

    defp fold(view, block_id) do
      view
      |> element(~s(.sb-node[data-block-id="#{block_id}"] > .sb-node__chrome > .sb-node__fold))
      |> render_click()
    end

    defp collapsed?(view, block_id) do
      has_element?(view, ~s(.sb-node[data-block-id="#{block_id}"][data-collapsed="true"]))
    end

    # Two lanes side by side: `:lanes` arrangement, so the card draws a fan
    # label above its slots and a join marker under them.
    defp lanes_document do
      Document.new(
        Block.new("core.parallel",
          id: "blk_lanes",
          config: %{"lanes" => ["signup", "email"]},
          slots: %{
            "lane_signup" => [EditorFixtures.wait("blk_l1", "1h")],
            "lane_email" => [EditorFixtures.wait("blk_l2", "2h")]
          }
        ),
        id: "doc_lanes"
      )
    end

    describe "the fold is editor state, toggled by one server event" do
      # Sabotage: making `handle_event("collapse-toggle", ...)` `MapSet.put/2`
      # unconditionally - the fold never opens again and the second click in
      # this test goes red.
      test "one click folds a container shut and the next opens it", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        refute collapsed?(view, "blk_wizard")

        fold(view, "blk_wizard")
        assert collapsed?(view, "blk_wizard")

        fold(view, "blk_wizard")
        refute collapsed?(view, "blk_wizard")
      end

      # Sabotage: storing one `collapsed_id` rather than a `MapSet` - folding
      # the branch unfolds the wizard and this goes red on the second
      # assertion, which is the whole reason the assign is a set.
      test "a second container folds independently of the first", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        # Two SIBLING containers, both children of the wizard's body: folding
        # an ancestor would take the other one out of the markup, and the
        # assertion would then be about rendering rather than about the set.
        fold(view, "blk_variant")
        fold(view, "blk_track_conversion")

        assert collapsed?(view, "blk_variant")
        assert collapsed?(view, "blk_track_conversion")

        fold(view, "blk_track_conversion")

        assert collapsed?(view, "blk_variant")
        refute collapsed?(view, "blk_track_conversion")
      end

      # Nothing about the fold reaches the document. The editor tells its host
      # about a document only when a command changed one, and folding is not a
      # command - which is the amendment's first sentence, asserted.
      # Sabotage: routing the fold through `commit/2` with an `:update_config`
      # - the host is notified of a document it did not ask for and this goes
      # red.
      test "folding notifies the host of nothing", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        fold(view, "blk_wizard")

        assert latest_document() == nil
      end
    end

    describe "the collapsed face (the amendment's second clause)" do
      # Sabotage: dropping the `:if` guard from the fan label - a folded card
      # still announces the arrangement of a body it is not drawing, and this
      # goes red on the fan.
      test "a collapsed container renders no slots, no fan and no join marker",
           %{conn: conn} do
        # A `core.parallel` is the one shape that draws all three: lanes side
        # by side, so a fan label above them and a join marker under.
        {:ok, view, _html} = mount_editor(conn, document: lanes_document())

        node = ~s(.sb-node[data-block-id="blk_lanes"])

        assert has_element?(view, node <> " .sb-node__slots")
        assert has_element?(view, node <> " > .sb-node__fan")
        assert has_element?(view, node <> " > .sb-node__join")

        fold(view, "blk_lanes")

        refute has_element?(view, node <> " .sb-node__slots")
        refute has_element?(view, node <> " > .sb-node__fan")
        refute has_element?(view, node <> " > .sb-node__join")
      end

      # The region is UNRENDERED, not hidden: no child card exists in the
      # markup at all, which is why the measure hook needs no change and why
      # `Connectors.edges` has no anchor to draw an edge into.
      # Sabotage: dropping the `:if` from `.sb-node__slots` - the body renders
      # under a card that says it is shut, the child cards are back in the
      # markup with their anchors, and this goes red.
      test "a collapsed container's children are not in the markup at all",
           %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        assert has_element?(view, ~s(.sb-node[data-block-id="blk_control_pause"]))

        fold(view, "blk_variant")

        refute has_element?(view, ~s(.sb-node[data-block-id="blk_control_pause"]))
      end

      # Decision 8: every drop target is reachable without dragging, by the
      # "+" on its gap. A folded region's targets are not reachable by pointer
      # or by keyboard until it is opened - which is what "unrendered" means
      # and what the amendment states against decision 8 rather than leaving
      # to the markup.
      # Sabotage: dropping the `:if` from `.sb-node__slots` - the gaps come
      # back with the body, the "+" of a slot nobody can see is clickable
      # again, and this goes red.
      test "a collapsed container's insertion points are not reachable", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        armed = ~s([data-parent-id="blk_variant"][data-slot="otherwise"] > .sb-gap__add)
        assert has_element?(view, armed)

        fold(view, "blk_variant")

        refute has_element?(view, armed)
      end

      # A container with nothing in it is still a container, and folding one
      # is legal: what folds is the region, not the children that happen to be
      # in it.
      # Sabotage: guarding the fold button on a non-empty subtree - an empty
      # container loses its control and this goes red.
      test "a container with an empty subtree still folds", %{conn: conn} do
        document =
          Document.new(
            Block.new("core.sequence", id: "blk_empty", slots: %{"body" => []}),
            id: "doc_empty"
          )

        {:ok, view, _html} = mount_editor(conn, document: document)

        fold(view, "blk_empty")

        assert collapsed?(view, "blk_empty")
      end

      # Sabotage: rendering the fold on every non-root card the way the `x` is
      # rendered - a leaf gains a control for a body it does not have, and
      # this goes red.
      test "a leaf carries no fold button and never reads as collapsed", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        leaf = ~s(.sb-node[data-block-id="blk_email_step"])

        assert has_element?(view, leaf <> ~s([data-container="false"]))
        refute has_element?(view, leaf <> " > .sb-node__chrome > .sb-node__fold")
        assert has_element?(view, leaf <> ~s([data-collapsed="false"]))
      end
    end

    describe "the badge, on the one face that carries it (d11's last sentence)" do
      # Sabotage: rendering `.sb-badge` whenever the rollup is non-zero rather
      # than only on a collapsed face - the badge is back on every container
      # as the counts multiply up the tree, and the first refute goes red.
      test "the badge renders on a collapsed container and on no expanded one",
           %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, findings: findings())

        refute has_element?(view, ".sb-node .sb-badge")

        fold(view, "blk_variant")

        assert has_element?(
                 view,
                 ~s(.sb-node[data-block-id="blk_variant"] > .sb-node__chrome > .sb-badge)
               )
      end

      # The number is the SUBTREE rollup, not the node's own findings, which
      # is the whole reason `findings_count` covers a subtree.
      # Sabotage: rendering `@node.findings |> length()` instead of
      # `@node.findings_count` - the wizard's badge reads 0 where four
      # findings are folded inside it, and this goes red.
      test "the badge reads the subtree rollup", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, findings: findings())

        fold(view, "blk_wizard")

        # Two supplied - one on the branch, one on the wait - plus the
        # `:resolution` finding `ViewModel` derives for the unresolvable
        # block. None is the wizard's own; all three are inside its subtree.
        assert has_element?(
                 view,
                 ~s(.sb-node[data-block-id="blk_wizard"] > .sb-node__chrome > .sb-badge),
                 "3"
               )
      end

      # Sabotage: dropping the `> 0` guard - an empty badge ring appears on
      # every folded container in a clean document and this goes red.
      test "a collapsed container with nothing wrong carries no badge", %{conn: conn} do
        document =
          Document.new(
            Block.new("core.sequence",
              id: "blk_clean",
              slots: %{"body" => [EditorFixtures.wait("blk_clean_step", "PT1H")]}
            ),
            id: "doc_clean"
          )

        {:ok, view, _html} = mount_editor(conn, document: document)

        fold(view, "blk_clean")

        assert collapsed?(view, "blk_clean")
        refute has_element?(view, ".sb-node .sb-badge")
      end
    end

    describe "the control itself (the amendment's keyboard clause)" do
      # A native button, so Enter and Space are the browser's and the tab
      # order is the document's. No window key binding exists and no shortcut
      # key is claimed.
      # Sabotage: dropping `aria-expanded` from the button - the control stops
      # saying whether the region it names is open, which is the whole of what
      # a screen reader has to go on, and this goes red.
      test "the fold is a native button carrying aria-expanded", %{conn: conn} do
        {:ok, view, html} = mount_editor(conn)

        assert html =~
                 ~r/<button[^>]*class="sb-node__fold"[^>]*aria-expanded="true"/s

        fold(view, "blk_wizard")

        assert has_element?(
                 view,
                 ~s(.sb-node[data-block-id="blk_wizard"] > .sb-node__chrome > button.sb-node__fold[aria-expanded="false"])
               )
      end

      # `data-reveal` names the CONTRACT the stylesheet selects on, so the
      # rest state is one string a test can read rather than a computed style
      # nothing can check. Shut is "always" because a control that hides a
      # region has to be the way back to it.
      # Sabotage: leaving `data-reveal="hover-or-selected"` on a folded
      # container - the only way back is a hover, which a keyboard does not
      # have, and this goes red.
      test "the fold is revealed on hover or selection while open, and always while shut",
           %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        open = ~s(.sb-node[data-block-id="blk_wizard"] > .sb-node__chrome > .sb-node__fold)

        assert has_element?(view, open <> ~s([data-reveal="hover-or-selected"]))

        fold(view, "blk_wizard")

        assert has_element?(view, open <> ~s([data-reveal="always"]))
      end

      # Sabotage: adding `phx-window-keydown="collapse-toggle"` to the editor
      # root - the fold acquires a shortcut key the amendment refuses, and
      # this goes red.
      test "no window key binding carries the fold", %{conn: conn} do
        {:ok, _view, html} = mount_editor(conn)

        refute html =~ ~r/phx-window-keydown="collapse-toggle"/
      end
    end

    describe "a document switch (2A)" do
      # A block id from the old document names nothing in the new one, so the
      # set goes the way the selection goes. The palette's own fold is the
      # deliberate exception - it addresses no block.
      # Sabotage: leaving `collapsed_ids` out of `switch_document/2`'s assign
      # list - the stale id survives the round trip, the wizard comes back
      # folded shut, and this goes red.
      #
      # The document leaves and comes back, because the reset fires on an
      # identity CHANGE: swapping the same document in is the host re-render
      # `switch_document/2`'s first clause exists to ignore, and a test that
      # only swapped away would be asserting that a block id is absent from a
      # document that never had it.
      test "clears the folds and leaves the palette's own alone", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        view |> element(".sb-palette__toggle") |> render_click()
        fold(view, "blk_wizard")

        assert collapsed?(view, "blk_wizard")
        assert has_element?(view, ~s(.sb-palette[data-collapsed="true"]))

        send(view.pid, {:swap_document, EditorFixtures.credit_card()})
        _away = render(view)
        send(view.pid, {:swap_document, EditorFixtures.signup_wizard()})
        _back = render(view)

        assert has_element?(view, ~s(.sb-node[data-block-id="blk_wizard"]))
        refute collapsed?(view, "blk_wizard")
        assert has_element?(view, ~s(.sb-palette[data-collapsed="true"]))
      end
    end
  end
end
