# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. What this file asserts is
# markup, so there is no pure half to place outside the guard.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.PublishStatusTest do
    @moduledoc """
    The `publish_status` assign: the one line a host fills with the count of
    live executions on the previous revision and the class of the change.

    The host computes both; the editor only draws what it is handed. So the
    claims here are about markup: `nil` draws nothing and moves nothing else,
    each of the four classes draws its own line, the count is spelled for
    zero, one and many, the line sits beside the header slot whether or not
    the slot is filled, and a value outside the documented shape is refused
    into no line.

    The documents are the suite's incumbent fixtures, reused; the host's
    header text is a library document's name.
    """

    use StatifierBlocks.EditorLiveCase

    @header "Loan renewal"
    @line ~r{<p[^>]*class="sb-editor__publish-status"[^>]*>.*?</p>\s*}s

    defp editor(view), do: view |> element("#editor") |> render()

    defp fixtures do
      [
        {"signup_wizard", EditorFixtures.signup_wizard()},
        {"credit_card", EditorFixtures.credit_card()},
        {"invoke_step", EditorFixtures.invoke_step()}
      ]
    end

    describe "nil" do
      # Sabotage: `publish_line/1`'s fallback clause answering a map with an
      # empty text rather than `nil`, so `nil` drew an empty status paragraph.
      # Ran red.
      test "renders byte for byte what a host passing nothing gets, for every fixture",
           %{conn: conn} do
        for {name, document} <- fixtures(), header <- [nil, @header] do
          {:ok, plain, _html} = mount_editor(conn, document: document, header: header)

          {:ok, with_nil, _html} =
            mount_editor(conn, document: document, header: header, publish_status: nil)

          assert editor(with_nil) == editor(plain), "#{name} moved under publish_status: nil"
          refute editor(with_nil) =~ "sb-editor__publish-status"
        end
      end

      # Sabotage: a `data-publish` attribute on the root element whenever a
      # line is drawn - markup outside the line that the filled mount adds.
      # Ran red here only.
      test "a filled line is the only thing it adds", %{conn: conn} do
        {:ok, plain, _html} = mount_editor(conn, header: @header)

        {:ok, view, _html} =
          mount_editor(conn, header: @header, publish_status: %{live: 3, class: :compatible})

        filled = editor(view)

        assert filled =~ "sb-editor__publish-status"
        assert Regex.replace(@line, filled, "") == editor(plain)
      end
    end

    describe "each class" do
      # Sabotage: dropping `:mapped` from `@publish_classes`. Ran red on the
      # `:mapped` iteration, which is the point of looping over all four.
      test "draws one line naming the class the host passed", %{conn: conn} do
        for class <- [:identical, :compatible, :mapped, :breaking] do
          {:ok, view, _html} =
            mount_editor(conn, header: @header, publish_status: %{live: 3, class: class})

          line = view |> element(".sb-editor__publish-status") |> render()

          assert line =~ ~s(data-publish-class="#{class}")
          assert line =~ ~s(role="status")

          assert line =~
                   "3 live executions on the previous revision; this change is #{class}"
        end
      end
    end

    describe "the count" do
      # Sabotage: deleting the `live_executions(0)` clause, so zero fell to
      # the plural clause and read "0 live executions". Ran red here only.
      test "zero live executions says so in words", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn, publish_status: %{live: 0, class: :breaking})

        line = view |> element(".sb-editor__publish-status") |> render()

        assert line =~ "No live executions on the previous revision; this change is breaking"
        assert line =~ ~s(data-live="0")
      end

      # Sabotage: deleting the `live_executions(1)` clause. Ran red on
      # "1 live executions".
      test "one live execution is singular", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn, publish_status: %{live: 1, class: :identical})

        assert view |> element(".sb-editor__publish-status") |> render() =~
                 "1 live execution on the previous revision; this change is identical"
      end
    end

    describe "where the line is drawn" do
      # Sabotage: drawing the line inside `<header>` after the slot rather
      # than beside it. Ran red: the line is then the header's child.
      test "with the header slot filled, directly after the host's header", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn, header: @header, publish_status: %{live: 2, class: :mapped})

        assert has_element?(view, "#editor > .sb-editor__header + .sb-editor__publish-status")
        refute has_element?(view, ".sb-editor__header .sb-editor__publish-status")
      end

      # Sabotage: guarding the line with `:if={@publish_line && @header != []}`,
      # so an empty slot hid it. Ran red here, and on the two count tests,
      # which mount without a header.
      test "with the header slot empty, as the root's first child", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn, publish_status: %{live: 2, class: :mapped})

        refute has_element?(view, ".sb-editor__header")
        assert has_element?(view, "#editor > .sb-editor__publish-status:first-child")
      end
    end

    describe "a value outside the documented shape" do
      # Sabotage: dropping the `class in @publish_classes` guard. Ran red on
      # the unknown class, which then drew a line naming it.
      test "is refused into no line", %{conn: conn} do
        {:ok, plain, _html} = mount_editor(conn)

        for status <- [
              %{live: 3, class: :renamed},
              %{live: -1, class: :compatible},
              %{live: "3", class: :compatible},
              %{class: :compatible},
              :compatible
            ] do
          {:ok, view, _html} = mount_editor(conn, publish_status: status)

          assert editor(view) == editor(plain), "#{inspect(status)} drew something"
        end
      end
    end

    describe "a host re-filling the line" do
      # Sabotage: `update/2` treating a `nil` it is handed as "unchanged" and
      # keeping the line it had. Ran red here only.
      test "redraws it on each update, and nil takes it away", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn, header: @header, publish_status: %{live: 3, class: :compatible})

        send(view.pid, {:publish_status, %{live: 4, class: :breaking}})

        assert view |> element(".sb-editor__publish-status") |> render() =~
                 "4 live executions on the previous revision; this change is breaking"

        send(view.pid, {:publish_status, nil})

        refute has_element?(view, ".sb-editor__publish-status")
      end
    end
  end
end
