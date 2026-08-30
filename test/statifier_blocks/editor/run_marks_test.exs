# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.RunMarksTest do
    @moduledoc """
    The host marking seam: `active_marks` and `invoke_mark`.

    Everything here drives the seam the way a host does - `send_update/3` into
    the mounted component - rather than by reaching into assigns, because the
    load-bearing claim is about a delivery mechanism. `send_update/3` carries
    only the keys it names, so a mark that lived in the assigns the host last
    passed would be dropped by the host's very next re-render, and that is the
    defect these tests exist to keep out.

    The other claim is where a mark stops being true: a mark addresses one
    block, so a different document clears it, unlike the pane folds ADR-0005's
    2026-08-30 amendment to decision 2 exempts from that reset.

    Every selector is scoped to `.sb-node`. `.sb-palette` carries data
    attributes of its own, and a bare `[data-run-active]` assertion would be
    asserting about whatever matched first.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.Editor

    defp mark(view, assigns) do
      Phoenix.LiveView.send_update(view.pid, Editor, [{:id, "editor"} | assigns])
      render(view)
      view
    end

    defp active?(view, block_id) do
      has_element?(view, ~s(.sb-node[data-block-id="#{block_id}"][data-run-active="true"]))
    end

    defp invoking?(view, block_id) do
      has_element?(view, ~s(.sb-node[data-block-id="#{block_id}"][data-run-invoking="true"]))
    end

    # Read through the same selector engine every other assertion here uses,
    # rather than by parsing the document: `LiveViewTest` is the reader a host
    # would have, and the markup contract is what these tests are about.
    defp outcome?(view, block_id, outcome) do
      has_element?(
        view,
        ~s(.sb-node[data-block-id="#{block_id}"][data-invoke-outcome="#{outcome}"])
      )
    end

    defp answered?(view, block_id) do
      has_element?(view, ~s(.sb-node[data-block-id="#{block_id}"][data-invoke-outcome]))
    end

    # A host re-render that says nothing about the marks: the same document,
    # at the revision a host would hold after saving it. Same `id`, so
    # `switch_document/2` is a no-op, and what this exercises is the update a
    # host makes for its own reasons - the one carrying `document`, `palette`
    # and `findings` and no mark at all.
    #
    # The revision is what makes it a re-render at all, and it is worth
    # spelling out: `assign/3` skips an identical value, and two calls to the
    # same fixture build structurally identical documents, so re-sending the
    # fixture unchanged updates nothing and this helper would prove nothing.
    defp host_rerender(view) do
      document = %{EditorFixtures.signup_wizard() | revision: 1}

      send(view.pid, {:swap_document, document})
      render(view)
      view
    end

    describe "the marks a host paints" do
      # Sabotage: stamping `data-run-active` from `@collapsed?` instead of
      # from `@run_active?` - the marked block reports false and this goes
      # red on the first assertion.
      test "an active mark lands on the block it names and on no other", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        refute active?(view, "blk_email_step")

        mark(view, active_marks: ["blk_email_step"])

        assert active?(view, "blk_email_step")
        refute active?(view, "blk_variant")
        refute active?(view, "blk_wizard")
      end

      # Sabotage: making `active_ids/1` keep the last id rather than the set
      # (`|> List.last() |> List.wrap() |> MapSet.new()`) - one of the two
      # goes dark and this goes red, which is why the assign is a set.
      test "several blocks can be active at once", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        mark(view, active_marks: ["blk_email_step", "blk_variant"])

        assert active?(view, "blk_email_step")
        assert active?(view, "blk_variant")
      end

      # Sabotage: dropping the `data-invoke-outcome` stamp from
      # `block_node.ex` - the mark still shows and the answer disappears, so
      # the last assertion goes red while the first two stay green.
      test "an invoke mark carries the block and the outcome", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        mark(view, invoke_mark: {"blk_variant", "done"})

        assert invoking?(view, "blk_variant")
        refute invoking?(view, "blk_email_step")
        assert outcome?(view, "blk_variant", "done")
      end

      # Sabotage: making `invoke_mark/1`'s bare-id clause return
      # `{id, "pending"}` - an outcome appears where the record says there is
      # none yet, and this goes red on the `nil`.
      test "a call with no answer yet is marked with no outcome", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        mark(view, invoke_mark: "blk_variant")

        assert invoking?(view, "blk_variant")
        refute answered?(view, "blk_variant")
      end

      # The two marks answer different questions, so one block can carry both
      # and neither reading may swallow the other.
      # Sabotage: making `marks/1` return `nil` unless BOTH are set (`or` for
      # `and`) - one mark without the other renders nothing at all, and the
      # active block goes dark the moment the invoke mark is cleared.
      test "the two marks are independent of each other", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        mark(view, active_marks: ["blk_email_step"], invoke_mark: {"blk_email_step", "error"})

        assert active?(view, "blk_email_step")
        assert invoking?(view, "blk_email_step")

        mark(view, invoke_mark: nil)

        assert active?(view, "blk_email_step")
        refute invoking?(view, "blk_email_step")
      end

      # Sabotage: rendering the marks straight out of `assigns` in `render/1`
      # rather than out of the state `update/3` wrote - the host's next
      # re-render arrives with no `:active_marks` key, the mark vanishes, and
      # this goes red. It is the whole reason the mark is editor state.
      test "a mark survives a host re-render that does not mention it", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        mark(view, active_marks: ["blk_email_step"], invoke_mark: {"blk_variant", "done"})
        host_rerender(view)

        assert active?(view, "blk_email_step")
        assert invoking?(view, "blk_variant")
        assert outcome?(view, "blk_variant", "done")
      end

      # Sabotage: removing `active_ids` and `invoking` from
      # `switch_document/2`'s reset - the marks follow the author into a
      # document whose blocks they do not name, and this goes red.
      test "a different document clears both marks", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        mark(view, active_marks: ["blk_email_step"], invoke_mark: {"blk_variant", "done"})
        assert active?(view, "blk_email_step")

        send(view.pid, {:swap_document, EditorFixtures.invoke_step()})
        render(view)

        send(view.pid, {:swap_document, EditorFixtures.signup_wizard()})
        render(view)

        refute active?(view, "blk_email_step")
        refute invoking?(view, "blk_variant")
      end

      # Sabotage: stamping `data-run-active` only while the container is open
      # (`not @collapsed? and @run_active?`) - the mark disappears exactly
      # when the fold is what makes it worth having, and this goes red while
      # the unfolded cases above stay green.
      test "a mark on a folded container still shows", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        view
        |> element(~s(.sb-node[data-block-id="blk_wizard"] > .sb-node__chrome > .sb-node__fold))
        |> render_click()

        mark(view, active_marks: ["blk_wizard"], invoke_mark: {"blk_wizard", "error"})

        assert has_element?(
                 view,
                 ~s(.sb-node[data-block-id="blk_wizard"][data-collapsed="true"][data-run-active="true"])
               )

        assert invoking?(view, "blk_wizard")
        assert outcome?(view, "blk_wizard", "error")
      end

      # Sabotage: guarding `update/3` on the VALUE rather than on the key's
      # presence - a clear then looks exactly like an absence, the marks stay
      # lit, and both refutes go red. It is the reason the guard is
      # `Map.has_key?/2`.
      test "an empty set and a nil clear the marks", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        mark(view, active_marks: ["blk_email_step"], invoke_mark: {"blk_variant", "done"})
        mark(view, active_marks: [], invoke_mark: nil)

        refute active?(view, "blk_email_step")
        refute invoking?(view, "blk_variant")
      end
    end

    describe "the normalizers are total" do
      # A host holds a run's state in whatever shape its own runtime produced.
      # Sabotage: removing `active_ids/1`'s catch-all clause - the bare string
      # raises a `FunctionClauseError` inside the host's render instead of
      # marking nothing, and this goes red as an exit.
      #
      # The blanks and non-strings in the list are here rather than in a test
      # of their own: dropping them changes what the set holds and nothing a
      # reader can see, because no node has an empty `data-block-id` to light.
      # A claim nothing can falsify is not a test, so what is asserted is the
      # part that IS observable - the junk reaches the editor and the real
      # block beside it still lights.
      test "a shape the editor does not recognise marks nothing", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        mark(view, active_marks: "blk_email_step", invoke_mark: 42)

        refute active?(view, "blk_email_step")
        refute invoking?(view, "blk_email_step")
        refute has_element?(view, ~s(.sb-node[data-run-invoking="true"]))

        mark(view, active_marks: ["blk_email_step", "", nil, 7])

        assert active?(view, "blk_email_step")
      end

      # An Elixir host holds an outcome as an atom as readily as a string.
      # Sabotage: removing `outcome_text/1`'s atom clause - the atom falls to
      # the catch-all, the outcome becomes "no answer yet", and this goes red.
      test "an atom outcome reaches the markup as its word", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        mark(view, invoke_mark: {"blk_variant", :error})

        assert outcome?(view, "blk_variant", "error")
      end
    end
  end
end
