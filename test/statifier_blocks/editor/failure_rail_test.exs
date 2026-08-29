# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.FailureRailTest do
    @moduledoc """
    The `:failure` rail as the shipped editor renders it (ADR-0005 amendments
    10g-10j, `sb-rx1`).

    The derivations are asserted with LiveView absent, in
    `StatifierBlocks.ViewModel.AccentAndRailTest`. What is left here is the
    part that could not be: that the components ask those functions and put
    their answers in the markup, on the two core types that declare the two
    rail styles - `core.invoke`'s `on_error` and `core.resumable_group`'s
    `interrupts` - so the two vocabularies are asserted against each other
    rather than one at a time.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.{Block, Document, Palette}

    # One document carrying both rail styles and a body slot, so every
    # assertion below has its own control in the same render.
    defp document do
      Document.new(
        Block.new("core.resumable_group",
          id: "blk_checkout",
          slots: %{
            "body" => [
              Block.new("core.invoke",
                id: "blk_authorize",
                config: %{"invoke_type" => "myapp:authorize"},
                slots: %{"on_error" => [Block.new("core.raise", id: "blk_declined")]}
              )
            ],
            "interrupts" => [Block.new("core.on_event", id: "blk_cancelled")]
          }
        ),
        id: "doc_checkout"
      )
    end

    defp mount_checkout(conn), do: mount_editor(conn, document: document())

    describe "the two rail vocabularies (10g, 10h)" do
      # Sabotage: dropping the `:failure` arm from `Slot`'s class list - the
      # failure rail falls back to the placement class alone and renders in
      # the interrupt's dashed warning edge, which is the reading campaign
      # 013's screens recorded as wrong.
      test "a :failure slot carries its own class, not the interrupt's", %{conn: conn} do
        {:ok, view, _html} = mount_checkout(conn)

        assert has_element?(view, ~s([data-slot-name="on_error"].sb-slot--failure))
        assert has_element?(view, ~s([data-slot-name="on_error"].sb-slot--rail))

        refute has_element?(view, ~s([data-slot-name="on_error"].sb-slot--secondary)),
               "the two rail vocabularies share a placement and nothing else"
      end

      # Sabotage: stamping the failure class on the rail partition rather
      # than on the style - the interrupt rail acquires the error family, and
      # "fires whether or not you get there" is drawn as "this went wrong".
      test "the interrupt rail keeps its own, and a body slot has neither", %{conn: conn} do
        {:ok, view, _html} = mount_checkout(conn)

        assert has_element?(view, ~s([data-slot-name="interrupts"].sb-slot--secondary))
        refute has_element?(view, ~s([data-slot-name="interrupts"].sb-slot--failure))
        refute has_element?(view, ~s([data-slot-name="body"].sb-slot--rail))
        refute has_element?(view, ~s([data-slot-name="body"].sb-slot--failure))
      end

      # Sabotage: `ViewModel.boundary?/1` reading the `:secondary` partition -
      # an invoke whose only rail is its failure path loses the edge the
      # region needs, which is 10c's stated reason for the box.
      test "a container whose only rail is a failure path is a boundary", %{conn: conn} do
        {:ok, view, _html} = mount_checkout(conn)

        assert has_element?(view, ~s([data-block-id="blk_authorize"].sb-node--boundary))
        refute has_element?(view, ~s([data-block-id="blk_declined"].sb-node--boundary))
      end
    end

    describe "the exit edge (10h's last row, per the sb-67s ruling)" do
      # Sabotage: `Slot` stamping the rail partition rather than
      # `exit_edge/1` - the failure rail's exit is drawn as the interrupt's
      # dashed escape, so the canvas draws as out-of-band what ADR-0004's
      # amendment makes an in-band completion event.
      test "a failure rail's exit is the ordinary flow edge", %{conn: conn} do
        {:ok, view, _html} = mount_checkout(conn)

        assert has_element?(view, ~s([data-slot-name="on_error"][data-exit-edge="flow"]))
      end

      # Sabotage: `exit_edge/1` answering `:flow` for every style - the
      # escape channel disappears from the rail it belongs to, and the ruling
      # that kept it exclusively interrupt vocabulary says nothing.
      test "an interrupt rail's exit is the escape channel", %{conn: conn} do
        {:ok, view, _html} = mount_checkout(conn)

        assert has_element?(view, ~s([data-slot-name="interrupts"][data-exit-edge="interrupt"]))
      end
    end

    describe "an unrecognized style (10i)" do
      defmodule Newer do
        @moduledoc """
        A host type declaring a style this editor does not know. It is a HOST
        type on purpose: 10i exists for a host built against a newer record,
        and a core type could not be one.
        """

        @behaviour StatifierBlocks.BlockType

        @impl true
        def current_version, do: 1

        @impl true
        def slots(_config), do: [{"on_error", :zero_or_more, "If it fails"}]

        @impl true
        def config_schema(_config), do: []

        @impl true
        def validate_config(_config), do: :ok

        @impl true
        def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

        @impl true
        def palette_entry, do: %{label: "Charge the card", slot_style: %{"on_error" => :sidecar}}
      end

      # Sabotage: passing the declared style through unnormalized - the DOM
      # carries a style the stylesheet cannot read, and the slot renders with
      # no vocabulary at all rather than the ordinary one.
      test "renders as an ordinary body slot, children and all", %{conn: conn} do
        document =
          Document.new(
            Block.new("myapp.capture",
              id: "blk_capture",
              slots: %{"on_error" => [Block.new("myapp.capture", id: "blk_retry")]}
            ),
            id: "doc_capture"
          )

        {:ok, view, _html} =
          mount_editor(conn,
            document: document,
            palette: Palette.new(%{"myapp.capture" => Newer})
          )

        assert has_element?(view, ~s([data-slot-name="on_error"][data-slot-style="primary"]))
        refute has_element?(view, ~s([data-slot-name="on_error"].sb-slot--rail))
        refute has_element?(view, ~s([data-block-id="blk_capture"].sb-node--boundary))

        assert has_element?(view, ~s([data-block-id="blk_retry"])),
               "10i keeps the children; it does not drop the slot"
      end
    end
  end
end
