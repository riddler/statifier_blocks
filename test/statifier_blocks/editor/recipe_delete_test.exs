# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.RecipeDeleteTest.Overreach do
    @moduledoc """
    A recipe that claims a block in a DIFFERENT enclosing group - the answer
    clause 2D says the caller refuses before a compound is built. Registered
    as `"clock_overreach"`, which sorts before `"deadline"` by name
    deliberately, so a test that sees the deadline's own claim survive has
    seen the refusal AND the fall-through in one gesture.
    """

    @behaviour StatifierBlocks.Recipe

    @impl true
    def insert(_target, _document), do: {:error, :never}

    @impl true
    def palette_entry, do: %{label: "Overreach", order: 91}

    @impl true
    def members("blk_send", _document), do: ["blk_send", "blk_far"]
    def members(_block_id, _document), do: []
  end

  defmodule StatifierBlocks.Editor.RecipeDeleteTest.Pairwise do
    @moduledoc """
    A well-behaved recipe that recognises a different arrangement in the same
    group and, registered as `"clock_pairwise"`, sorts before `"deadline"`. It
    is how the first-by-name tiebreak (`3D`, ruling `RQ-SF037-11`) is observed
    from outside.
    """

    @behaviour StatifierBlocks.Recipe

    @impl true
    def insert(_target, _document), do: {:error, :never}

    @impl true
    def palette_entry, do: %{label: "Pairwise", order: 92}

    @impl true
    def members("blk_send", _document), do: ["blk_send", "blk_capture"]
    def members(_block_id, _document), do: []
  end

  defmodule StatifierBlocks.Editor.RecipeDeleteTest do
    @moduledoc """
    The delete path after ADR-0005's amendment of 2026-09-07, clause 3D: the
    editor asks the palette's recipes, and one claim becomes one offered
    compound with one undo entry.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.Editor.RecipeDeleteTest.{Overreach, Pairwise}

    # The amendment's worked example, plus a second group holding the block
    # `Overreach` reaches for.
    #
    #   blk_root (core.sequence)
    #     body: [blk_settle, blk_other]
    #
    #   blk_settle (core.group)
    #     body:       [blk_send, blk_capture]
    #     interrupts: [blk_handler]
    #
    #   blk_other (core.group)
    #     body: [blk_far]
    defp document do
      timer =
        Block.new("core.send",
          id: "blk_send",
          config: %{"event" => "deadline.a1b2c3d4", "delay" => "1h"}
        )

      capture =
        Block.new("core.invoke",
          id: "blk_capture",
          config: %{"invoke_type" => "myapp:capture"}
        )

      handler =
        Block.new("core.on_event", id: "blk_handler", config: %{"event" => "deadline.a1b2c3d4"})

      far = Block.new("core.wait", id: "blk_far", config: %{"duration" => "1s"})

      settle =
        Block.new("core.group",
          id: "blk_settle",
          slots: %{"body" => [timer, capture], "interrupts" => [handler]}
        )

      other = Block.new("core.group", id: "blk_other", slots: %{"body" => [far]})

      Document.new(
        Block.new("core.sequence", id: "blk_root", slots: %{"body" => [settle, other]}),
        id: "bdoc_settlement"
      )
    end

    defp palette(recipes \\ []),
      do: StatifierBlocks.Palette.from_modules([], core: true, recipes: recipes)

    defp click_delete(view, id) do
      view
      |> element(~s(button[phx-click="remove"][phx-value-block-id="#{id}"]))
      |> render_click()
    end

    defp confirm(view, id) do
      view
      |> element(~s(button[phx-click="remove-confirm"][phx-value-block-id="#{id}"]))
      |> render_click()
    end

    defp ids(document), do: document |> Document.blocks() |> Enum.map(& &1.id)

    describe "a block no recipe claims" do
      # The amendment's second table row, and the reason the clause is safe to
      # land: the overwhelming case is the one that does not change.
      #
      # Sabotage: `recipe_claim/2` answering the asked-about id alone rather
      # than `[]` for an unclaimed block - the plain remove becomes an offer
      # and this goes red.
      test "removes immediately, as it did before the clause", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: document(), palette: palette())

        click_delete(view, "blk_capture")

        assert %Document{} = changed = latest_document()
        refute "blk_capture" in ids(changed)
        assert "blk_send" in ids(changed)
      end
    end

    describe "a claimed block is OFFERED, not removed" do
      # "The compound is offered, not imposed." The first click commits
      # nothing at all - the document the host holds has not moved.
      #
      # Sabotage: the `remove` handler committing the compound directly
      # instead of assigning `pending_remove` - `latest_document/0` returns a
      # document and this goes red.
      test "the first click commits nothing and draws the count", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: document(), palette: palette())

        html = click_delete(view, "blk_send")

        assert latest_document() == nil
        assert html =~ ~s(phx-click="remove-confirm")
        assert html =~ ~s(phx-value-block-id="blk_send")
        assert html =~ "x2"
        assert html =~ "and the 1 block it goes with"
      end

      # One `{:compound, ...}`, which by clause 2n is ONE undo entry: the
      # arrangement comes out the way it went in, and one undo puts it back
      # whole.
      #
      # Sabotage: `remove_compound/2` committing a `{:remove, id}` per claimed
      # id instead of one compound - the deletion assertions still pass, and
      # the single undo leaves the send missing, so the last assertion goes
      # red. That is the whole point of the test.
      test "the second click removes both halves as one undo entry", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: document(), palette: palette())

        click_delete(view, "blk_send")
        confirm(view, "blk_send")

        assert %Document{} = removed = latest_document()
        refute "blk_send" in ids(removed)
        refute "blk_handler" in ids(removed)
        assert "blk_capture" in ids(removed)

        view |> element(~s(button[phx-click="undo"])) |> render_click()

        assert %Document{} = restored = latest_document()
        assert "blk_send" in ids(restored)
        assert "blk_handler" in ids(restored)
      end

      # The rail half is the same arrangement reached from the other side.
      test "the handler on the rail offers the same compound", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: document(), palette: palette())

        html = click_delete(view, "blk_handler")

        assert latest_document() == nil
        assert html =~ ~s(phx-click="remove-confirm")

        confirm(view, "blk_handler")

        assert %Document{} = removed = latest_document()
        refute "blk_send" in ids(removed)
        refute "blk_handler" in ids(removed)
      end

      # `2n`'s undo is what makes a mistaken yes cheap; Keep is what makes it
      # unnecessary. Declining leaves the document untouched and puts the
      # ordinary control back.
      test "keep withdraws the offer and writes nothing", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: document(), palette: palette())

        click_delete(view, "blk_send")
        html = view |> element(~s(button[phx-click="remove-cancel"])) |> render_click()

        assert latest_document() == nil
        refute html =~ ~s(phx-click="remove-confirm")
        assert html =~ ~s(phx-click="remove")
      end
    end

    describe "an offer is one unanswered question" do
      # Two offers on the canvas at once would be two questions the author
      # did not ask; the second gesture is the answer to the first.
      #
      # Sabotage: leaving the first offer in place when the next delete finds
      # no claim - the confirm control is still on the send and this goes red.
      test "a second delete withdraws the first offer", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: document(), palette: palette())

        click_delete(view, "blk_send")
        html = click_delete(view, "blk_far")

        refute html =~ ~s(phx-click="remove-confirm")
        assert %Document{} = changed = latest_document()
        assert "blk_send" in ids(changed)
        refute "blk_far" in ids(changed)
      end

      # A run's marks and a run itself are cleared when the host swaps a
      # document in, and an offer is cleared for the same reason and one more:
      # it is a question nobody has answered, and the new document never asked
      # it.
      #
      # Sabotage: leaving `pending_remove` off `switch_document/2`'s list -
      # the swapped-in document renders a confirm control on a block id it
      # inherited from the old one, and this goes red.
      test "a document swap withdraws the offer", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: document(), palette: palette())

        click_delete(view, "blk_send")
        send(view.pid, {:swap_document, StatifierBlocks.EditorFixtures.credit_card()})

        refute render(view) =~ ~s(phx-click="remove-confirm")
      end
    end

    describe "a read-only mount" do
      # `read_only?` clause 6: no edit reaches the document. The offer is two
      # more gestures that would, so they go on `@read_only_refused` with the
      # rest rather than being guarded one at a time.
      #
      # Sabotage: leaving `remove-confirm` off the list - a crafted event
      # deletes the arrangement out of a read-only mount and this goes red.
      test "refuses the offer gestures a crafted event could send", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn,
            document: document(),
            palette: palette(),
            profile: %{read_only?: true}
          )

        view |> with_target("#editor") |> render_click("remove", %{"block-id" => "blk_send"})

        view
        |> with_target("#editor")
        |> render_click("remove-confirm", %{"block-id" => "blk_send"})

        view |> with_target("#editor") |> render_click("remove-cancel", %{})

        assert latest_document() == nil
      end
    end

    describe "the caller bounds the answer" do
      # Clause 2D's refusal, read at the editor: a claim naming a block in
      # another enclosing group is dropped before a compound is built, and the
      # next recipe by name is still asked - so the deadline's own claim is
      # what the author is offered.
      #
      # Sabotage: dropping `same_enclosing_block?/3` from `claim/3` - the
      # offer counts 2 either way, so the assertion that matters is the one on
      # what the confirm REMOVES: `blk_far` would go with it and this goes red.
      test "an out-of-group claim is refused, and the next recipe is asked", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn,
            document: document(),
            palette: palette([{"clock_overreach", Overreach}])
          )

        click_delete(view, "blk_send")
        confirm(view, "blk_send")

        assert %Document{} = removed = latest_document()
        assert "blk_far" in ids(removed)
        refute "blk_send" in ids(removed)
        refute "blk_handler" in ids(removed)
      end

      # `3D`'s tiebreak, ruling `RQ-SF037-11`: more than one claim is a
      # deterministic pick by recipe name, not a refusal. `"clock_pairwise"` sorts
      # before `"deadline"`, so its claim is the one offered.
      #
      # Sabotage: iterating the recipes map without sorting - the map's own
      # order decides, and this test goes red intermittently rather than
      # never, which is the failure mode the sort exists to remove.
      test "two claims are settled first by name", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn,
            document: document(),
            palette: palette([{"clock_pairwise", Pairwise}])
          )

        click_delete(view, "blk_send")
        confirm(view, "blk_send")

        assert %Document{} = removed = latest_document()
        refute "blk_send" in ids(removed)
        refute "blk_capture" in ids(removed)
        assert "blk_handler" in ids(removed)
      end
    end
  end
end
