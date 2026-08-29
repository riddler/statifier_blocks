# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*, which is the earlier
# of the two problems.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.GraduationTest do
    @moduledoc """
    What the campaign-012/013 spike proved about the DOM, rendered by the
    shipped components (`sb-8dc`).

    The derivations behind all of it are asserted with LiveView absent, in
    `StatifierBlocks.ViewModel.AccentAndRailTest`. What is left here is the
    part that could not be: that the components ask those functions and put
    their answers in the markup. The load-bearing negative - that no component
    under `StatifierBlocks.Editor.*` names a block type in code - is already
    scanned by `StatifierBlocks.Editor.PresentationTest`, and this file's three
    additions to the metadata surface are covered by that scan for free.
    """

    use StatifierBlocks.EditorLiveCase

    defmodule Accented do
      @moduledoc """
      A host block type declaring the two things this file is about: an accent
      token, and a slot in each of the rail styles.

      It is a HOST type on purpose. The seam exists so that a host registering
      its own vocabulary can give it its own identity without the editor
      learning a name, and a core type declaring it would prove less.
      """

      @behaviour StatifierBlocks.BlockType

      @impl true
      def current_version, do: 1

      @impl true
      def slots(_config),
        do: [{"body", :zero_or_more, "Body"}, {"on_error", :zero_or_more, "If it fails"}]

      @impl true
      def config_schema(_config), do: []

      @impl true
      def validate_config(_config), do: :ok

      @impl true
      def emit(%StatifierBlocks.Block{id: id}, _context), do: {:ok, {:emitted, id}}

      @impl true
      def palette_entry do
        %{
          label: "Charge the card",
          group: "Payments",
          accent_token: "--sb-accent-myapp",
          slot_style: %{"on_error" => :failure}
        }
      end
    end

    defmodule Plain do
      @moduledoc "The same shape, declaring no accent and no rail. The control."

      @behaviour StatifierBlocks.BlockType

      @impl true
      def current_version, do: 1

      @impl true
      def slots(_config), do: [{"body", :zero_or_more, "Body"}]

      @impl true
      def config_schema(_config), do: []

      @impl true
      def validate_config(_config), do: :ok

      @impl true
      def emit(%StatifierBlocks.Block{id: id}, _context), do: {:ok, {:emitted, id}}

      @impl true
      def palette_entry, do: %{label: "Send a receipt", group: "Payments"}
    end

    defp palette do
      Palette.new(%{"myapp.capture" => Accented, "myapp.receipt" => Plain})
    end

    defp document do
      Document.new(
        Block.new("myapp.capture",
          id: "blk_capture",
          slots: %{"body" => [Block.new("myapp.receipt", id: "blk_receipt")], "on_error" => []}
        ),
        id: "doc_payments"
      )
    end

    defp mount_payments(conn), do: mount_editor(conn, document: document(), palette: palette())

    # One block's opening tag, so an assertion about a card cannot be satisfied
    # by markup somewhere else on the page.
    defp node_tag(html, block_id) do
      [tag] = Regex.run(~r|<div class="sb-node[^>]*data-block-id="#{block_id}"[^>]*>|, html)
      tag
    end

    describe "the per-block-type accent (d14's accent_token, consumption side)" do
      # Sabotage: `BlockNode.accent_style/1` returning nil unconditionally - the
      # card stops carrying its type's identity and every block in the editor
      # is the editor's own accent again.
      test "a declaring type's card rebinds --sb-block-accent from the named token",
           %{conn: conn} do
        {:ok, _view, html} = mount_payments(conn)

        # The card, not the whole page: the palette row carries the same
        # declaration, so a document-wide match would pass on the row alone.
        capture = node_tag(html, "blk_capture")

        assert capture =~ ~s(data-sb-block-accent="--sb-accent-myapp")

        assert capture =~ "--sb-block-accent: var(--sb-accent-myapp, var(--sb-accent))",
               "the fallback is what makes a token a host never declared resolve to the accent"
      end

      # Sabotage: stamping the accent on every node rather than on the ones
      # that declared it - a type without an identity acquires one, and the
      # `style` attribute lands on cards that need none.
      test "a type that declares none carries no stamp and no style", %{conn: conn} do
        {:ok, _view, html} = mount_payments(conn)

        receipt = node_tag(html, "blk_receipt")

        refute receipt =~ "data-sb-block-accent",
               "a block type that declared nothing gets the editor's own accent, from the CSS"

        refute receipt =~ "--sb-block-accent:"
      end

      # Sabotage: dropping the stamp from `PaletteBrowser` - a block type then
      # looks like itself on the canvas and like everything else in the list it
      # is picked from.
      test "the palette row carries the same accent as the card it produces", %{conn: conn} do
        {:ok, view, _html} = mount_payments(conn)

        row = view |> element(~s([data-type="myapp.capture"] > .sb-palette__pick)) |> render()

        assert row =~ ~s(data-sb-block-accent="--sb-accent-myapp")
        assert row =~ "--sb-block-accent: var(--sb-accent-myapp, var(--sb-accent))"
      end
    end

    describe "the rail partition and its boundary box (10c, 10h)" do
      # Sabotage: `Slot`'s class list reading `@slot.style == :secondary` for
      # the rail class - a failure slot goes back into the body flow, which is
      # the placement row 10h changed.
      test "a :failure slot is placed as a rail", %{conn: conn} do
        {:ok, view, _html} = mount_payments(conn)

        assert has_element?(view, ~s([data-slot-name="on_error"].sb-slot--rail))

        refute has_element?(view, ~s([data-slot-name="on_error"].sb-slot--secondary)),
               "the two rail vocabularies share a placement and nothing else; " <>
                 "the interrupt's dashed warning edge is not a failure path's"

        refute has_element?(view, ~s([data-slot-name="body"].sb-slot--rail))
      end

      # Sabotage: `ViewModel.boundary?/1` reading the `:secondary` partition -
      # a container whose only rail is a failure path loses the edge the rule
      # attached to it is about.
      test "the container of a rail slot is a boundary box, and a plain one is not",
           %{conn: conn} do
        {:ok, view, _html} = mount_payments(conn)

        assert has_element?(view, ~s([data-block-id="blk_capture"].sb-node--boundary))
        refute has_element?(view, ~s([data-block-id="blk_receipt"].sb-node--boundary))
      end

      # Sabotage: `Slot` stamping a constant - `sb-rx1`'s failure vocabulary
      # then has no hook to tell the two rail styles apart in the DOM.
      test "the declared style reaches the markup for a renderer to read",
           %{conn: conn} do
        {:ok, view, _html} = mount_payments(conn)

        assert has_element?(view, ~s([data-slot-name="on_error"][data-slot-style="failure"]))
        assert has_element?(view, ~s([data-slot-name="body"][data-slot-style="primary"]))
      end
    end

    describe "the :info severity (decision 11, amended 2026-08-29)" do
      # Sabotage: `Finding.severity_class/1` losing its `:info` clause - an
      # advisory row renders in the error family, which is a claim that
      # something is wrong about a finding that makes no claim at all.
      test "an advisory finding renders in its own chrome, not the error family",
           %{conn: conn} do
        advisory =
          Finding.new({:block, "blk_receipt"}, :lint, "Handled by the receipts worker.",
            severity: :info
          )

        {:ok, _view, html} =
          mount_editor(conn, document: document(), palette: palette(), findings: [advisory])

        assert html =~ "sb-finding--info"
        refute html =~ "sb-finding--error"
      end
    end
  end
end
