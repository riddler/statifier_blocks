# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The pure half of this claim -
# that `Composite.outcomes/2` answers the host root's outcomes at all - lives
# in `StatifierBlocks.CompositeTest`, deliberately outside this guard.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.CompositeOutcomeCandidatesTest do
    @moduledoc """
    `core.on_event`'s `event` candidates over a **composite** sibling
    (`sb-9w7w`, ADR-0002's Note of 2026-09-07, item 3).

    The component holds a palette, so a composite in the enclosing body offers
    the outcomes its expansion root really declares rather than the core-only
    fallback `c:StatifierBlocks.BlockType.outcomes/1` is confined to. The
    composite here roots at a **host** type, which is the only case where the
    two answers differ - and the case a host embedding the editor over its own
    types is always in.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.Block

    defmodule Authorizes do
      @moduledoc "A host leaf that authorizes a card and declares its own outcomes."

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
      def io(_config), do: %{kinds: [:step]}
      @impl true
      def outcomes(_config), do: [{"approved", "Approved"}, {"declined", "Declined"}]
      @impl true
      def palette_entry, do: %{label: "Authorizes"}
      @impl true
      def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
    end

    defmodule AuthorizeWithDeadline do
      @moduledoc "A composite rooted at `myapp.authorizes`, so its exact outcomes need a palette."

      use StatifierBlocks.Composite,
        name: "myapp.authorize_with_deadline",
        params: [
          %{key: "deadline", type: :string, label: "Deadline", required?: true, default: ""}
        ],
        palette_entry: %{label: "Authorize with a deadline"}

      alias StatifierBlocks.Block

      @impl StatifierBlocks.Composite
      def subtree(_params), do: [Block.new("myapp.authorizes", id: "authorize")]
    end

    @approved "done.outcome.s_blk_auth.approved"
    @declined "done.outcome.s_blk_auth.declined"
    @fallback "done.outcome.s_blk_auth.done"

    defp palette do
      Palette.new(
        Map.merge(Palette.core_types(), %{
          "myapp.authorize_with_deadline" => AuthorizeWithDeadline,
          "myapp.authorizes" => Authorizes
        })
      )
    end

    defp cards_document do
      Document.new(
        Block.new("core.group",
          id: "blk_cards",
          slots: %{
            "body" => [
              Block.new("myapp.authorize_with_deadline",
                id: "blk_auth",
                config: %{"deadline" => "2h"}
              )
            ],
            "interrupts" => [
              Block.new("core.on_event",
                id: "blk_cancel",
                config: %{"event" => "", "outcome" => "abandon"}
              )
            ]
          }
        ),
        id: "doc_cards"
      )
    end

    defp cards_view(conn) do
      {:ok, view, _html} = mount_editor(conn, document: cards_document(), palette: palette())

      view
      |> element(~s([data-block-id="blk_cancel"] > .sb-node__chrome > .sb-node__label))
      |> render_click()

      view
    end

    # Sabotage: left `outcome_candidates/2` calling `BlockType.outcome_names/2`
    # on the resolved module -> 2 failures (verified), this one and the count
    # below: the two real options vanish and the fallback `done` takes their
    # place, because the core-only derivation cannot resolve a root the core
    # type map does not carry. That default is the wire that is not there.
    test "a composite sibling offers its host root's outcomes", %{conn: conn} do
      view = cards_view(conn)

      for event <- [@approved, @declined] do
        assert has_element?(view, ~s(datalist#sb-field-event-events option[value="#{event}"]))
      end

      refute has_element?(view, ~s(datalist#sb-field-event-events option[value="#{@fallback}"]))
    end

    # Sabotage: as above -> red (the second of that run's 2 failures). The
    # count is asserted separately because a routing that offered the exact
    # names *and* kept the fallback would pass the value assertions above and
    # still be wrong.
    test "the composite contributes exactly its two outcomes", %{conn: conn} do
      view = cards_view(conn)

      assert has_element?(view, ~s(datalist#sb-field-event-events[data-event-candidates="2"]))
    end

    # The callback is unchanged and stays unchanged: item 3 adds no palette
    # argument to `c:StatifierBlocks.BlockType.outcomes/1`. This is what the
    # editor would have offered, kept here so the difference the routing makes
    # is written down beside the routing.
    #
    # Sabotage: routed the callback too -> red.
    test "the callback itself still takes the core-only fallback" do
      assert AuthorizeWithDeadline.outcomes(%{"deadline" => "2h"}) == [{"done", "Done"}]
    end
  end
end
