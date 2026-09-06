# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.SourceConfigFocusTest do
    @moduledoc """
    `sb-rd29`'s click-through, from a Source tab span to a Config tab field.

    `StatifierBlocks.Editor.SourceTabTest` already covers the span selecting
    its owning block; what it does not cover is the config-emitted span's
    second half - that the click also lands the author on the field they
    would otherwise have to hunt the Config tab for. That is what this file
    asserts, through the one thing a rendered LiveView can prove: the
    `phx-mounted` instruction naming the field's own input id, the same way
    `StatifierBlocks.Editor.DrawerTabFocusTest` proves the tab strip's own
    one-shot focus rather than a browser's notion of what has focus.
    """

    use StatifierBlocks.EditorLiveCase

    defp open_source(view) do
      view |> element(".sb-drawer__strip") |> render_click()
      view |> element(~s(.sb-drawer__tab[phx-value-tab="source"])) |> render_click()
      view
    end

    # The field the strip is asking the browser to focus, or `nil` when it is
    # asking for nothing - read the same way
    # `StatifierBlocks.Editor.DrawerTabFocusTest`'s `focus_request/1` reads
    # the drawer's own one-shot span, because the mechanism is the same one.
    defp focused_field(html) do
      with [_, target, command] <-
             Regex.run(~r/id="sb-config-focus-([^"]+)"[^>]*phx-mounted="([^"]*)"/, html),
           true <- String.contains?(command, "#" <> target) do
        target
      else
        _none -> nil
      end
    end

    describe "a config-emitted span" do
      # The bead's own criterion: the click selects the block AND names the
      # field, and the id it names is the real one the config form gave that
      # field - `sb-field-invoke_type` - not a restatement of the config key.
      #
      # Sabotage: `handle_event("select", %{"block-id" => id, "config-key" =>
      # _key}, socket)` dropping `inspector_tab: :config` - the field is still
      # named, but on a tab the author is not looking at, which fails the
      # acceptance criterion's "opens the Config tab" half even though the
      # regex above would still pass.
      test "selects the block and focuses its field", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: EditorFixtures.invoke_step())

        open_source(view)
        _ = selections()

        html =
          view
          |> element(~s(.sb-source__span[data-config-key="invoke_type"]))
          |> render_click()
          |> then(fn _ -> render(view) end)

        assert [%{id: "blk_authorize"}] = selections()
        assert has_element?(view, ~s(#sb-inspector-tab-config[aria-selected="true"]))
        assert focused_field(html) == "sb-field-invoke_type"
      end

      # Sabotage: `focus_input_id/2` returning the raw key instead of
      # `Field.input_id/1`'s result - this catches the drift the assertion
      # above already would, spelled out on its own so a reviewer sees the
      # field id is derived rather than restated.
      test "names the field's real input id, not the bare config key", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: EditorFixtures.invoke_step())

        open_source(view)

        html =
          view
          |> element(~s(.sb-source__span[data-config-key="invoke_type"]))
          |> render_click()

        refute focused_field(html) == "invoke_type"
        assert focused_field(html) == "sb-field-invoke_type"
      end
    end

    describe "a plain span" do
      # "Selects only" is two claims, and the absent focus instruction is the
      # weaker one: a key that names no field of the selected block focuses
      # nothing either way. The claim with teeth is that the click did not
      # route through the config-emitted clause at all, and the tab the
      # author is left on is what says so - which is why this starts on
      # Findings rather than on the default Config.
      #
      # Sabotage: `phx-value-config-key` posting `""` instead of omitting
      # itself for a span with no `config_key` - the config clause would
      # match every plain click and pull the author off the tab they were
      # reading.
      test "selects only - no focus instruction, and no tab switch", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: EditorFixtures.invoke_step())

        open_source(view)
        view |> element("#sb-inspector-tab-findings") |> render_click()
        _ = selections()

        html =
          view
          |> element(~s(.sb-source__span[data-block="blk_flow"][data-offset="0"]))
          |> render_click()

        assert [%{id: "blk_flow"}] = selections()
        assert focused_field(html) == nil
        assert has_element?(view, ~s(#sb-inspector-tab-findings[aria-selected="true"]))
      end
    end

    describe "the one-shot instruction" do
      # Modeled on `StatifierBlocks.Editor.DrawerTabFocusTest`'s "is asked for
      # by a key press and by nothing else": a manual pick of another
      # inspector tab is not a new focus request, and it must not leave the
      # old one standing for the next visit to Config.
      #
      # Sabotage: dropping `config_field_focus: nil` from the
      # `"inspector-tab"` handler - clicking Findings then back to Config
      # would refocus `invoke_type` for a click that never asked for it.
      test "is cleared by a manual tab pick", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: EditorFixtures.invoke_step())

        open_source(view)

        html =
          view
          |> element(~s(.sb-source__span[data-config-key="invoke_type"]))
          |> render_click()

        assert focused_field(html) == "sb-field-invoke_type"

        view |> element("#sb-inspector-tab-findings") |> render_click()
        view |> element("#sb-inspector-tab-config") |> render_click()

        refute render(view) =~ "sb-config-focus-"
      end

      # A plain selection right after a config-emitted one must not leave the
      # earlier field's focus instruction standing. The second click is a
      # role span of the SAME block on purpose: a stale key resolves against
      # whatever block is selected when it renders, so clicking away to a
      # different block would hide the stale key behind a form that has no
      # field by that name, and the assertion would hold whether the clause
      # cleared it or not.
      #
      # Sabotage: dropping `config_field_focus: nil` from the plain `"select"`
      # clause - the key from the earlier click survives, and the block's own
      # Config tab refocuses a field this click never pointed at.
      test "is cleared by the very next plain selection", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: EditorFixtures.invoke_step())

        open_source(view)

        view
        |> element(~s(.sb-source__span[data-config-key="invoke_type"]))
        |> render_click()

        # The run of bytes the value sits inside, which the same block owns
        # and no config field wrote. Named by its text rather than its byte
        # offset: an offset is a property of the serializer's output, and a
        # test that pins one fails the day an unrelated attribute moves.
        html =
          view
          |> element(
            ~s(.sb-source__span[data-block="blk_authorize"][data-role="running"]),
            ~s(<invoke type=")
          )
          |> render_click()

        assert [%{id: "blk_authorize"}] = selections()
        assert focused_field(html) == nil
      end
    end
  end
end
