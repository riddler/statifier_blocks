# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.SaveAsStepTest do
    @moduledoc """
    The "Save as a step" gesture and the `on_collapse` seam: ADR-0005 part
    (iii) as amended 2026-09-07, clauses `15E` to `20E` (filed with
    `sb-uzly`).

    Deliberately **not** `StatifierBlocks.Editor.CollapseTest`, which already
    exists and covers decision 2's container **fold** - a different gesture
    with an unfortunately similar name. Nothing here uses the words
    `collapse` or `collapsed` for a CSS class or an event either, for the
    same reason: the drawer and palette folds own those in this shell.

    The load-bearing claim is a negative one. The gesture edits no document
    and this package persists nothing (`16E`, epic ruling `R5`), so what
    every test here watches is the pair of seams together: `on_collapse`
    fired, and `on_change` silent.
    """

    use StatifierBlocks.EditorLiveCase

    defp select(view, id) do
      view
      |> element(~s([data-block-id="#{id}"] > .sb-node__chrome > .sb-node__label))
      |> render_click()

      view
    end

    defp open_tray(view, id) do
      view
      |> element(
        ~s([data-block-id="#{id}"] > .sb-node__chrome > .sb-node__strip > .sb-node__save-step)
      )
      |> render_click()

      view
    end

    defp mark(view, id, key) do
      view
      |> element(
        ~s(.sb-save-step__field input[phx-value-block-id="#{id}"][phx-value-field-key="#{key}"])
      )
      |> render_click()

      view
    end

    defp save(view) do
      view |> element(".sb-save-step__confirm") |> render_click()
      view
    end

    describe "the control" do
      # Sabotage: drew the button on every card rather than the selected one
      # - red here. The gesture's subject is a selection, and a control on a
      # card nobody selected has no subject.
      test "is drawn on the selected card and nowhere else", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        refute has_element?(view, ".sb-node__save-step")

        select(view, "blk_email_step")

        assert has_element?(
                 view,
                 ~s([data-block-id="blk_email_step"] .sb-node__save-step)
               )

        refute has_element?(view, ~s([data-block-id="blk_variant"] .sb-node__save-step))
      end

      # Sabotage: dropped the `not @root?` guard - red. The root has no target
      # a composite could take, which is why `propose/3` refuses it, and
      # offering a gesture that can only be refused is worse than not offering
      # it.
      test "is not drawn on the document root", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        select(view, "blk_wizard")

        refute has_element?(view, ~s([data-block-id="blk_wizard"] .sb-node__save-step))
      end
    end

    describe "the marking tray" do
      # Sabotage: built the rows from the document root rather than from the
      # selected subtree - red on the second assertion. 18E is about the
      # values in the selection, so the tray has to be too.
      test "names every block in the selected subtree and every field on it", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        view |> select("blk_variant") |> open_tray("blk_variant")

        assert has_element?(
                 view,
                 ~s(.sb-save-step__field input[phx-value-block-id="blk_variant"])
               )

        assert has_element?(
                 view,
                 ~s(.sb-save-step__field input[phx-value-block-id="blk_variant"][phx-value-field-key="arm_variant_b"])
               )

        refute has_element?(
                 view,
                 ~s(.sb-save-step__field input[phx-value-block-id="blk_email_step"])
               )
      end

      # Sabotage: had Cancel commit the proposal anyway - red. A tray the
      # author closed said nothing, and a seam that fired on it would be
      # reporting a gesture nobody took.
      test "Cancel closes it and says nothing", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        view |> select("blk_email_step") |> open_tray("blk_email_step")
        assert has_element?(view, ".sb-save-step")

        view |> element(".sb-save-step__cancel") |> render_click()

        refute has_element?(view, ".sb-save-step")
        assert collapses() == []
      end
    end

    describe "the gesture" do
      # Sabotage: fired `on_change` beside `on_collapse` - red on the last
      # assertion, which is the consent breach the record names in as many
      # words: the gesture edits no document and the package persists nothing.
      test "hands the host a declaration and edits nothing", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        _document = latest_document()

        view |> select("blk_email_step") |> open_tray("blk_email_step") |> save()

        assert [declaration] = collapses()
        assert declaration["version"] == 1
        assert [%{"type" => "core.wait", "id_suffix" => "wait"}] = declaration["subtree"]
        refute Map.has_key?(declaration, "type_name")

        assert is_nil(latest_document())
        refute has_element?(view, ".sb-save-step")
      end

      # Sabotage: passed the tray's marks straight through when empty rather
      # than as 18E's unmarked reading - red, because a tray with nothing
      # ticked would then propose a step with no params at all.
      test "a tray with nothing ticked is the unmarked reading", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: EditorFixtures.invoke_step())

        view |> select("blk_authorize") |> open_tray("blk_authorize") |> save()

        assert [%{"params" => params}] = collapses()

        assert [%{"key" => "invoke_type", "default" => "myapp:authorize"}] = params
      end

      # Sabotage: made the checkbox a document edit - red on `latest_document`.
      # Marking is tray state and nothing else; only Save reads the document,
      # and it only reads it.
      test "a marked value is the one proposed", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        view
        |> select("blk_variant")
        |> open_tray("blk_variant")
        |> mark("blk_variant", "arm_variant_b")
        |> save()

        assert [%{"params" => [%{"key" => "arm_variant_b"}]}] = collapses()
        assert is_nil(latest_document())
      end

      # Sabotage: fired `on_collapse` with the `{:error, _}` - red. A refused
      # gesture is reported in the editor's own chrome; a host callback never
      # has to match a failure it did not ask for (16E).
      test "a refusal reaches the host as nothing at all", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        # `blk_track_conversion` is the fixture's unresolvable block, so the
        # palette answers no schema for it and `propose/3` refuses.
        view |> select("blk_track_conversion") |> open_tray("blk_track_conversion") |> save()

        assert collapses() == []
        assert is_nil(latest_document())
      end
    end

    # ADR-0005's Note of 2026-09-08, item 1. The gesture's only outcome is a
    # callback, so a mount that registered none is offered no gesture: the
    # control is not drawn, the tray is unreachable, and the four events it
    # is made of are answered with the socket unchanged. `data-collapse-save`
    # is the one selector both halves carry, so "nothing of it is drawn" is
    # one assertion rather than two that could drift apart.
    describe "a host that does not pass on_collapse" do
      # Sabotage: dropped the `@collapsible` guard from the control - red on
      # the second assertion, which is the whole of the item's ruling.
      test "is drawn no Save control, on any card", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, on_collapse: false)

        refute has_element?(view, "[data-collapse-save]")

        select(view, "blk_email_step")

        refute has_element?(view, "[data-collapse-save]")

        refute has_element?(
                 view,
                 ~s([data-block-id="blk_email_step"] .sb-node__save-step)
               )
      end

      # The control is not there to send them, so these arrive only from a
      # crafted payload. Sabotage: inverting the guard on the refusing clause
      # so it never matches - "save-as-step" reaches its own handler, the tray
      # opens on a mount that draws no control, and this goes red on it.
      test "refuses the four events the gesture is made of", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, on_collapse: false)

        select(view, "blk_email_step")

        for {event, params} <- [
              {"save-as-step", %{"block-id" => "blk_email_step"}},
              {"save-as-step-mark",
               %{"block-id" => "blk_email_step", "field-key" => "to_address"}},
              {"save-as-step-confirm", %{}},
              {"save-as-step-cancel", %{}}
            ] do
          view |> with_target("#editor") |> render_click(event, params)

          refute has_element?(view, "[data-collapse-save]"),
                 "#{event} drew something the mount withholds"
        end

        assert collapses() == []
        assert is_nil(latest_document())
      end
    end

    describe "a host that does pass on_collapse" do
      # The other side of the same contract, so neither half can be read as
      # "nothing is ever drawn". Sabotage: dropped `data-collapse-save` from
      # the tray section - red on the second assertion.
      test "is drawn the control, and the tray it opens", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        select(view, "blk_email_step")

        assert has_element?(
                 view,
                 ~s([data-block-id="blk_email_step"] .sb-node__save-step[data-collapse-save])
               )

        open_tray(view, "blk_email_step")

        assert has_element?(view, ~s(.sb-save-step[data-collapse-save]))
      end
    end
  end
end
