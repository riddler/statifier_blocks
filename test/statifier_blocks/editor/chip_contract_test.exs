# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*, which is the earlier
# of the two problems.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.ChipContractTest do
    @moduledoc """
    ADR-0005's Note of 2026-09-08, item 2, at the markup: an over-cap summary
    chip is drawn clipped with its full text on the `title`, and the
    presentation-cap diagnostic that says so is read in the drawer's Findings
    tab rather than on the card face.

    The clipping itself is `BlockType`'s and is asserted with LiveView absent
    (`block_type/summary_test.exs`); the finding's derivation is `ViewModel`'s
    and is asserted there too (`view_model/card_summary_test.exs`). What is
    left for this file is the half that only exists once there is markup -
    which element carries the clipped text, which carries the full one, and
    which surface the diagnostic appears on - because that is what the item
    rules and what neither of the other two files can see.

    The document is the reference card-processing composite: a container whose
    body holds one step, both declaring chips over the cap. A container is the
    shape the ruling was measured on - its node box is as wide as everything
    it holds, so a face finding placed outside its card drew as a full-width
    line between the card and the slot label under it.
    """

    use StatifierBlocks.EditorLiveCase

    # 36 and 38 graphemes against the cap of 32, and 29 under it: the lengths
    # the card-processing composite's own chips had when the face was measured
    # in the 0.26.0 cycle. The first two are what a clip has to survive; the
    # third is what has to be left alone.
    @over_a "authorize the card and settle it now"
    @over_b "review the balance and the fraud model"
    @under "capture the authorized amount"

    @clipped_a "authorize the card and settle i…"
    @clipped_b "review the balance and the frau…"

    defmodule Composite do
      @moduledoc """
      The composite card: one declared slot, and a summary whose chips name
      the steps it was expanded from.
      """

      @behaviour StatifierBlocks.BlockType

      @impl true
      def current_version, do: 1

      @impl true
      def slots(_config), do: [{"body", :zero_or_more, "Steps"}]

      @impl true
      def config_schema(_config), do: []

      @impl true
      def validate_config(_config), do: :ok

      @impl true
      def summary(config), do: Map.get(config, "summary", [])

      @impl true
      def emit(%StatifierBlocks.Block{id: id}, _context), do: {:ok, {:emitted, id}}

      @impl true
      def palette_entry, do: %{label: "Authorize with a deadline", group: "Card processing"}
    end

    defmodule Step do
      @moduledoc "A leaf inside the composite's one slot, summarising itself."

      @behaviour StatifierBlocks.BlockType

      @impl true
      def current_version, do: 1

      @impl true
      def slots(_config), do: []

      @impl true
      def config_schema(_config), do: []

      @impl true
      def validate_config(_config), do: :ok

      @impl true
      def summary(config), do: Map.get(config, "summary", [])

      @impl true
      def emit(%StatifierBlocks.Block{id: id}, _context), do: {:ok, {:emitted, id}}

      @impl true
      def palette_entry, do: %{label: "Authorize card", group: "Card processing"}
    end

    defp palette do
      Palette.new(%{"myapp.composite" => Composite, "myapp.step" => Step})
    end

    defp document do
      Document.new(
        Block.new("myapp.composite",
          id: "blk_authorize",
          config: %{"summary" => [@under, @over_a, @over_b]},
          slots: %{
            "body" => [
              Block.new("myapp.step", id: "blk_step", config: %{"summary" => [@over_a]})
            ]
          }
        ),
        id: "doc_card_processing"
      )
    end

    defp mount_composite(conn), do: mount_editor(conn, document: document(), palette: palette())

    defp open_findings(view) do
      view |> element(".sb-drawer__strip") |> render_click()
      view |> element(~s(.sb-drawer__tab[phx-value-tab="findings"])) |> render_click()
    end

    # Every chip on the canvas, in document order, as `{drawn, title}`. A
    # chip with no title is `{drawn, nil}`, which is what an untranslated,
    # unclipped chip has always rendered as.
    defp chips(html) do
      ~r|<span class="sb-node__chip"(?:\s+title="([^"]*)")?\s*>\s*([^<]*?)\s*</span>|
      |> Regex.scan(html)
      |> Enum.map(fn
        [_all, "", drawn] -> {drawn, nil}
        [_all, title, drawn] -> {drawn, title}
        [_all, drawn] -> {drawn, nil}
      end)
    end

    describe "an over-cap chip on the card face" do
      # Sabotage: put the `:too_long` arm of `drawn_chips/3` back on the
      # refusal branch - the composite draws one chip where its type declared
      # three, which is the silence this item removes.
      test "every declared chip is drawn: none is dropped", %{conn: conn} do
        {:ok, _view, html} = mount_composite(conn)

        assert Enum.map(chips(html), &elem(&1, 0)) ==
                 [@under, @clipped_a, @clipped_b, @clipped_a]
      end

      # Sabotage: drop `@chip_ellipsis` from `clip/1` - the chip ends mid-word
      # with nothing saying it was cut, which reads as the declaration rather
      # than as a prefix of one.
      test "a clipped chip ends in the ellipsis and stops at the cap", %{conn: conn} do
        {:ok, view, _html} = mount_composite(conn)

        assert String.length(@over_b) == 38
        assert String.length(@clipped_b) == 32
        assert String.ends_with?(@clipped_b, "…")

        assert has_element?(view, ".sb-node__chip", @clipped_b)
        refute has_element?(view, ".sb-node__chip", @over_b)
      end

      # Sabotage: leave a clipped chip's `title` at the `nil` an untranslated
      # chip gets - the `title` completes nothing the reader can see, which is
      # the half of the ruling that makes the clip readable at all.
      test "the full text is on the chip's title attribute", %{conn: conn} do
        {:ok, _view, html} = mount_composite(conn)

        assert chips(html) == [
                 {@under, nil},
                 {@clipped_a, @over_a},
                 {@clipped_b, @over_b},
                 {@clipped_a, @over_a}
               ]
      end
    end

    describe "where the presentation-cap diagnostic is read" do
      # The item's first clause, and the one the card-face captures were taken
      # for: four of these paragraphs filled the composite's card body, their
      # tint past its edges.
      #
      # Sabotage: drop the `presentation_finding?/1` reject from
      # `face_findings/1` - two come back onto the composite's face and one
      # onto its step's.
      test "no cap finding draws on the card face", %{conn: conn} do
        {:ok, view, _html} = mount_composite(conn)

        refute has_element?(view, ".sb-node__chrome > .sb-finding")
        refute has_element?(view, ".sb-node > .sb-finding")
      end

      # ... and it is still said, in the one place the item names.
      #
      # Sabotage: filter the cap findings out of `derived_findings/3` instead
      # of out of the face - the card is identical either way and the author
      # loses the diagnostic entirely, which is the failure the whole
      # `summary_refusals/3` reader exists to prevent.
      test "the drawer's Findings tab lists every one of them", %{conn: conn} do
        {:ok, view, _html} = mount_composite(conn)
        open_findings(view)

        for message <- [
              "summary chip 2 is 36 characters; the cap is 32, so it is drawn clipped",
              "summary chip 3 is 38 characters; the cap is 32, so it is drawn clipped",
              "summary chip 1 is 36 characters; the cap is 32, so it is drawn clipped"
            ] do
          assert has_element?(view, ".sb-findings__list .sb-findings__message", message)
        end
      end

      # The count is unchanged by where the finding is drawn: the badge on a
      # folded container still says how much is wrong inside it.
      #
      # Sabotage: reject the cap findings in `build_resolved_node/4` rather
      # than at the face - the rollup drops to zero and a folded composite
      # says nothing is wrong inside it.
      test "the rollup still counts them", %{conn: conn} do
        {:ok, _view, html} = mount_composite(conn)

        assert [_all, count] =
                 Regex.run(
                   ~r/data-block-id="blk_authorize"[^>]*data-findings-count="(\d+)"/,
                   html
                 )

        assert count == "3"
      end

      # A finding from any other rule is untouched by the item: it is about
      # the document rather than about a declaration's length, and the card is
      # still where an author reads it. ADR-0005 amendment `11b` reserves
      # `:info` to `:lint`, so excluding the whole source would have taken
      # every advisory off every card with it.
      #
      # Sabotage: reject on `source == :lint` alone - this goes red, and
      # `graduation_test.exs`'s `:info` assertion goes with it.
      test "a finding that is not a cap diagnostic still draws on the face", %{conn: conn} do
        advisory =
          Finding.new({:block, "blk_step"}, :lint, "Handled by the settlement worker.",
            severity: :info
          )

        {:ok, view, _html} =
          mount_editor(conn, document: document(), palette: palette(), findings: [advisory])

        assert has_element?(
                 view,
                 ~s([data-block-id="blk_step"] > .sb-node__chrome > .sb-finding.sb-finding--info),
                 "Handled by the settlement worker."
               )
      end
    end
  end
end
