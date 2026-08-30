# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*, which is the earlier
# of the two problems.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.UnresolvableTest do
    @moduledoc """
    ADR-0005 decision 12: unresolvable blocks render, and never lose data.

    ADR-0001 decision 9 made decoding registry-free and ADR-0002 decision 3 made
    resolution total, both of them explicitly to create this case rather than
    avoid it. The acceptance property the record names is preservation: open a
    document containing a block type the host does not have, edit an unrelated
    part of the tree, save, and the unresolvable block's bytes are unchanged. An
    editor that quietly dropped it would turn a missing palette entry into
    silent data loss.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.Editor.BlockNode
    alias StatifierBlocks.{Finding, ViewModel}

    defp track(document) do
      Enum.find(Document.blocks(document), &(&1.id == "blk_track_conversion"))
    end

    # Two more findings on the unresolvable block, so "every finding" is a
    # claim a one-finding fixture cannot make: the block's own resolution
    # finding plus these. They are `:block` anchored because that is the only
    # anchor a block with no schema has - there is no field for a `:config`
    # finding to hang off.
    defp extra_findings do
      [
        Finding.new(
          {:block, "blk_track_conversion"},
          :lint,
          "no handler is registered for its invoke type",
          severity: :warning
        ),
        Finding.new(
          {:block, "blk_track_conversion"},
          :lint,
          "its stored variant key names a datamodel path that is gone",
          severity: :warning
        )
      ]
    end

    # The second of `Palette.resolve/2`'s three failures: a type the palette
    # HAS, at a version it does not know how to read. The fixtures have no
    # such block, and the whole point of the reason line is that this case and
    # a missing type do not read the same.
    defp too_new_document do
      Document.new(
        Block.new("core.sequence",
          id: "blk_root",
          slots: %{
            "body" => [Block.new("core.wait", id: "blk_from_the_future", type_version: 9)]
          }
        ),
        id: "doc_too_new"
      )
    end

    defp track_node do
      EditorFixtures.signup_wizard()
      |> ViewModel.build(EditorFixtures.palette(), [])
      |> Map.fetch!(:root)
      |> find_node("blk_track_conversion")
    end

    defp find_node(%ViewModel.Node{block_id: id} = node, id), do: node

    defp find_node(%ViewModel.Node{} = node, id) do
      node.slots |> Enum.flat_map(& &1.children) |> Enum.find_value(&find_node(&1, id))
    end

    describe "rendering" do
      # Sabotage: `BlockNode.status_tag/1` answering "ok" for an unresolvable
      # node - the dashed chrome and the reason line both stop rendering.
      test "type name, unavailable chrome, and one reason line", %{conn: conn} do
        {:ok, view, html} = mount_editor(conn)

        assert has_element?(
                 view,
                 ~s([data-block-id="blk_track_conversion"][data-status="unresolvable"].sb-node--unresolvable)
               )

        refute has_element?(
                 view,
                 ~s([data-block-id="blk_email_step"][data-status="unresolvable"])
               )

        assert html =~ EditorFixtures.unknown_type()

        assert has_element?(
                 view,
                 ~s([data-block-id="blk_track_conversion"] > .sb-node__reason),
                 "type is not registered here"
               )
      end

      # D4's compaction, and the half of it a screenshot cannot assert: the
      # face carries the reason and NOTHING else, however many findings the
      # block has. Two findings are supplied rather than one, because a face
      # that rendered only the first would pass an assertion written against
      # a block with one.
      #
      # Sabotage: `BlockNode.face_findings/1` returning `findings` for the
      # unresolvable clause too - both sentences come back onto the card and
      # the lane is as wide as the longer of them again.
      test "no finding and no config render on the face", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, findings: extra_findings())

        # One line, counted over the whole canvas: the wizard has exactly one
        # unresolvable block, so a second match would be a card saying its
        # reason twice.
        assert view |> render() |> then(&Regex.scan(~r{class="sb-node__reason"}, &1)) |> length() ==
                 1

        refute has_element?(view, ~s([data-block-id="blk_track_conversion"] > .sb-finding)),
               "D4: an unresolvable card's findings are the inspector's, all of them"

        refute has_element?(view, ~s([data-block-id="blk_track_conversion"] > pre)),
               "D4: the raw config left the face - it is the widest thing the card can hold"
      end

      # The reason is `Palette.resolve/2`'s error term phrased here, so a
      # block stored by a NEWER version of a type the host does have reads
      # differently from one whose type is missing altogether. Same chrome,
      # different sentence, and the author can tell which problem they have
      # without opening the pane.
      #
      # Sabotage: collapsing `BlockNode.reason_words/1` to a single clause -
      # the migration case and the missing-type case say the same thing, and
      # the line stops being worth reading.
      test "the reason names which of the three failures this is", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn, document: too_new_document(), palette: EditorFixtures.palette())

        assert has_element?(
                 view,
                 ~s([data-block-id="blk_from_the_future"] > .sb-node__reason),
                 "stored by a newer version"
               )

        refute has_element?(
                 view,
                 ~s([data-block-id="blk_from_the_future"] > .sb-node__reason),
                 "type is not registered here"
               )
      end

      # `status` is typed `{:unresolvable, term()}`, so the phrase table has a
      # fourth clause and this is what holds it: a card is not the thing that
      # raises when `Palette.resolve/2`'s error set grows. A real node with
      # its status rewritten, so what is asserted is the phrase table rather
      # than a struct assembled by hand.
      #
      # Sabotage: deleting `BlockNode.reason_words/1`'s last clause - this
      # goes red with a FunctionClauseError, which is what an author would
      # get in place of a canvas.
      test "a reason shape this package does not name still renders a card" do
        node = %{track_node() | status: {:unresolvable, :something_not_yet_written}}

        html = render_component(&BlockNode.block_node/1, node: node, target: "#editor")

        assert html =~ "type did not resolve"
      end

      # D4's other half: what left the face is one click away, in full. Driven
      # through the real selection path rather than handed to the component,
      # because "selecting the card shows it" is the acceptance sentence and
      # the seam between the canvas and the pane is the part that can break.
      #
      # Sabotage: dropping the `<pre>` from `Inspector.block_section/1` - the
      # bytes are then on no surface at all, which is worse than where they
      # were before D4 moved them.
      test "selecting it shows the config and every finding in the inspector", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, findings: extra_findings())

        view
        |> element(
          ~s([data-block-id="blk_track_conversion"] > .sb-node__chrome > .sb-node__label)
        )
        |> render_click()

        json = view |> element(".sb-inspector__raw-config") |> render()

        # Escaped in the markup, because it is text the editor did not author.
        assert json =~ "&quot;event&quot;:&quot;signup.completed&quot;"
        assert json =~ "&quot;variant_key&quot;:&quot;ab_variant&quot;"

        refute has_element?(view, ~s(.sb-form[data-block-id="blk_track_conversion"])),
               "there is no config_schema/1 to drive a form and inventing one would be guessing"

        findings =
          view
          |> element(~s(.sb-inspector__tab[phx-value-tab="findings"]))
          |> render_click()

        assert findings =~ "unknown block type"
        assert findings =~ "no handler is registered for its invoke type"
        assert findings =~ "its stored variant key names a datamodel path that is gone"
      end

      # Sabotage: `ViewModel.build_unresolvable_node/3` returning `slots: []` -
      # the child vanishes from the render, which is the data-loss failure this
      # whole decision exists to prevent.
      test "its existing children render normally, recursively, with raw slot names", %{
        conn: conn
      } do
        {:ok, view, _html} = mount_editor(conn)

        assert has_element?(
                 view,
                 ~s([data-block-id="blk_track_conversion"] [data-slot-name="after"][data-declared="false"])
               )

        assert has_element?(view, ~s([data-block-id="blk_settle_pause"])),
               "the child is a resolvable core.wait and renders as one"
      end

      # Sabotage: `Edit.Targets.droppable_slots_for/3` not consulting `slots/1`
      # - the unresolvable block's slot would light up as a target.
      test "it is never a drop target for a foreign block", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        html =
          view
          |> element("#sb-canvas")
          |> render_hook("dragstart", %{"block-id" => "blk_email_step"})

        assert html =~ ~s(data-slot-name="after" data-parent-id="blk_track_conversion")

        refute Regex.match?(
                 ~r/data-slot-name="after" data-parent-id="blk_track_conversion"[^>]*data-drop="ok"/,
                 html
               )
      end
    end

    describe "preservation" do
      # Sabotage: `Editor.commit/2` rebuilding the document from the view model
      # rather than threading `Edit.apply/2`'s own result - the unresolvable
      # block's config would be re-derived from a schema it does not have, and
      # its bytes would change.
      test "an edit elsewhere leaves its bytes untouched", %{conn: conn} do
        before = track(EditorFixtures.signup_wizard())
        {:ok, view, _html} = mount_editor(conn)

        view
        |> element(~s([data-block-id="blk_email_step"] > .sb-node__chrome > .sb-node__remove))
        |> render_click()

        after_edit = track(latest_document())

        assert after_edit == before

        assert after_edit.config == %{
                 "event" => "signup.completed",
                 "variant_key" => "ab_variant"
               }

        assert after_edit.type_version == before.type_version
      end

      # Sabotage: the "drop" handler applying an `:insert` of a rebuilt block -
      # the moved unresolvable block would come back with a fresh id and an
      # empty config.
      test "it may be moved, and arrives with its subtree and config intact", %{conn: conn} do
        before = track(EditorFixtures.signup_wizard())
        {:ok, view, _html} = mount_editor(conn)

        canvas = element(view, "#sb-canvas")
        render_hook(canvas, "dragstart", %{"block-id" => "blk_track_conversion"})

        render_hook(canvas, "drop", %{
          "block-id" => "blk_track_conversion",
          "parent-id" => "blk_variant",
          "slot" => "otherwise",
          "index" => "0"
        })

        document = latest_document()
        assert track(document) == before

        assert Enum.any?(Document.blocks(document), &(&1.id == "blk_settle_pause")),
               "the subtree came with it"
      end
    end
  end
end
