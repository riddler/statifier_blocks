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

    defp track(document) do
      Enum.find(Document.blocks(document), &(&1.id == "blk_track_conversion"))
    end

    describe "rendering" do
      # Sabotage: `BlockNode.status_tag/1` answering "ok" for an unresolvable
      # node - the chrome and the read-only JSON both stop rendering.
      test "type name, unavailable chrome, and a :block finding", %{conn: conn} do
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
                 ~s([data-block-id="blk_track_conversion"] > .sb-finding),
                 ~r/unknown block type/
               )
      end

      # Sabotage: `ViewModel.build_unresolvable_node/3` leaving `raw_config_json`
      # nil - the read-only config disappears and the author cannot see what the
      # block holds.
      test "its config renders read-only as canonical JSON, not as a form", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        json =
          view
          |> element(~s([data-block-id="blk_track_conversion"] > .sb-node__raw-config))
          |> render()

        # Escaped in the markup, because it is text the editor did not author.
        assert json =~ "&quot;event&quot;:&quot;signup.completed&quot;"
        assert json =~ "&quot;variant_key&quot;:&quot;ab_variant&quot;"

        view
        |> element(
          ~s([data-block-id="blk_track_conversion"] > .sb-node__chrome > .sb-node__label)
        )
        |> render_click()

        refute has_element?(view, ~s(.sb-form[data-block-id="blk_track_conversion"])),
               "there is no config_schema/1 to drive a form and inventing one would be guessing"
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
