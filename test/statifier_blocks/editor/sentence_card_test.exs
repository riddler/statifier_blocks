# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*, which is the earlier
# of the two problems.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.SentenceCardTest do
    @moduledoc """
    The negative half of ADR-0005's 2026-09-07 amendment: `sentence` is a
    field on the view model and **a card draws what it drew yesterday**.

    The assertion is a comparison rather than a `refute`, and that is the
    point. Two host types identical in every declaration except that one
    exports `sentence/1`, registered under the SAME type name so nothing in
    the markup can tell them apart by name, produce byte-identical canvases.
    A `refute html =~ "..."` would pass for an implementation that drew the
    sentence somewhere the string happened not to match; this fails for any
    change to the card at all.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.{Block, Document, Palette}

    defmodule Speaking do
      @moduledoc "A host type with a sentence, a summary chip and a badge."

      @behaviour StatifierBlocks.BlockType

      @impl true
      def current_version, do: 1

      @impl true
      def slots(_config), do: [{"body", :any, "Body"}]

      @impl true
      def config_schema(_config), do: []

      @impl true
      def validate_config(_config), do: :ok

      @impl true
      def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

      @impl true
      def palette_entry,
        do: %{label: "Charge the card", group: "Money", badge: "charges", order: 1}

      @impl true
      def summary(_config), do: ["one chip"]

      @impl true
      def sentence(_config), do: "Charge the card and wait for the settlement to clear"
    end

    defmodule Silent do
      @moduledoc "The same type to the last character, minus `sentence/1`."

      @behaviour StatifierBlocks.BlockType

      @impl true
      def current_version, do: 1

      @impl true
      def slots(_config), do: [{"body", :any, "Body"}]

      @impl true
      def config_schema(_config), do: []

      @impl true
      def validate_config(_config), do: :ok

      @impl true
      def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

      @impl true
      def palette_entry,
        do: %{label: "Charge the card", group: "Money", badge: "charges", order: 1}

      @impl true
      def summary(_config), do: ["one chip"]
    end

    # Everything from the editor component down. The wrapper above it carries
    # the mount's own id and its signed session, which differ between two
    # mounts of the same document for reasons that have nothing to do with
    # what a card draws.
    defp editor(html) do
      [_before, component] = String.split(html, ~s(<div data-phx-component=), parts: 2)
      component
    end

    defp document do
      Document.new(Block.new("host.charge", id: "blk_charge"), id: "doc")
    end

    describe "a type that declares sentence/1" do
      # Sabotage: draw `@node.sentence` anywhere in `BlockNode.block_node/1` -
      # the two renders stop matching and this goes red.
      test "draws exactly the card it drew without one", %{conn: conn} do
        {:ok, _speaking, spoken} =
          mount_editor(conn,
            document: document(),
            palette: Palette.new(%{"host.charge" => Speaking})
          )

        {:ok, _silent, silent} =
          mount_editor(conn,
            document: document(),
            palette: Palette.new(%{"host.charge" => Silent})
          )

        assert editor(spoken) == editor(silent)
      end

      # Sabotage: put the sentence on the card's title line - the chip and
      # the label are still there, so only this assertion catches it.
      test "draws its label and its chip, and nothing of the sentence", %{conn: conn} do
        {:ok, _view, html} =
          mount_editor(conn,
            document: document(),
            palette: Palette.new(%{"host.charge" => Speaking})
          )

        assert html =~ "Charge the card"
        assert html =~ "one chip"
        refute html =~ "wait for the settlement to clear"
      end
    end
  end
end
