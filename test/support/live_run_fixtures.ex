# statifier-ui is optional here, exactly as `phoenix_live_view` is, and the
# headless CI job resolves a tree without either. Everything below names
# `StatifierUI` at compile time, so the whole file is wrapped the way
# `card_run_fixtures.ex` is - this is not a LiveView test, so it carries the
# `Code.ensure_loaded?(StatifierUI.Live.State)` guard rather than the
# `Phoenix.LiveView` one.
if Code.ensure_loaded?(StatifierUI.Live.State) do
  defmodule StatifierBlocks.LiveRunFixtures do
    @moduledoc """
    A run whose session stays alive, for the Run pane's send control
    (`sb-djj5`): `CardRunFixtures.run/0`'s sibling, kept live rather than
    stopped.

    `CardRunFixtures.run/0` starts a real session, sends one event, collects
    the subscriber's messages, stops the session and returns a
    persisted-shaped `State` (`stats: nil`). That is exactly wrong for a test
    of a control that only works over a *live* stream with a session to send
    into: this module keeps the session alive and returns it alongside a
    `State` built through `State.sync/2`, which pulls messages and stats in
    one call and is therefore live-shaped by construction (`stats != nil`).

    ## The shape, and why it is two awaits

    A `core.sequence` of two `core.await` blocks:

        core.sequence  blk_order_flow
          core.await   blk_order_open   event: "order.approved"
          core.await   blk_order_done   event: "order.settled"

    Both are awaits rather than anything that finishes, so the run sits *at*
    a block at the tip before and after the send - `card_run_fixtures.ex`'s
    moduledoc gives the same reason for the same choice.

    The first block's configured event is `"order.approved"` - `core.await`'s
    own `fixtures/0` sample name
    (`lib/statifier_blocks/core/await.ex:220-226`). That is deliberate: the
    palette this bead's pane draws is fed by the selected block's *type's*
    fixture sample, taken verbatim, not by the block's configured `event`
    (see `editor.ex`'s `run_events/1`). Configuring the two to agree here is
    what keeps the LiveView test's send genuinely handled - the chart really
    is waiting for `"order.approved"` - rather than a click that lands on a
    machine indifferent to it and produces no macrostep at all.
    """

    alias StatifierBlocks.{Block, Compiled, Compiler, Document, Palette}
    alias StatifierUI.Live.State
    alias StatifierUI.Trace.Subscriber

    @session "sess_sb_live_run"
    @declare []

    @doc "The block the run opens at, waiting for `sample_event/0`."
    @spec open_block() :: String.t()
    def open_block, do: "blk_order_open"

    @doc "The block the run reaches once `sample_event/0` has been handled."
    @spec done_block() :: String.t()
    def done_block, do: "blk_order_done"

    @doc """
    The event `open_block/0` is configured for - `core.await`'s own
    `fixtures/0` sample name, so the send this bead's pane makes is genuinely
    handled.
    """
    @spec sample_event() :: String.t()
    def sample_event, do: "order.approved"

    @doc "The document the run is over."
    @spec document() :: Document.t()
    def document do
      Document.new(
        Block.new("core.sequence",
          id: "blk_order_flow",
          slots: %{
            "body" => [
              Block.new("core.await", id: open_block(), config: %{"event" => sample_event()}),
              Block.new("core.await", id: done_block(), config: %{"event" => "order.settled"})
            ]
          }
        ),
        id: "bdoc_live_run"
      )
    end

    @doc "The palette the document resolves through."
    @spec palette() :: Palette.t()
    def palette, do: Palette.core()

    @doc "The roots the compile declares - none, this document reads no path."
    @spec declare() :: keyword()
    def declare, do: @declare

    @doc "The compiled chart and its provenance map."
    @spec compiled() :: Compiled.t()
    def compiled do
      {:ok, %Compiled{} = compiled} = Compiler.compile(document(), palette(), declare: @declare)
      compiled
    end

    @doc """
    A live run: a real session and subscriber, both left running, plus a
    `State` synced from the subscriber so `state.stats` is already populated.

    Mirrors `CardRunFixtures.run/0` up to the point that fixture stops the
    session - this keeps it alive and returns the session and subscriber
    alongside the state, so a test can send into it and re-sync.
    """
    @spec live() :: %{
            session: pid(),
            subscriber: pid(),
            machine: Statifier.Machine.t(),
            provenance: StatifierBlocks.Provenance.t(),
            state: State.t()
          }
    def live do
      %Compiled{scxml: scxml, provenance: provenance} = compiled()
      {:ok, machine} = Statifier.compile(scxml)
      {:ok, subscriber} = Subscriber.start_link(machine: machine)

      {:ok, session} =
        Statifier.Session.start_link(machine,
          trace: true,
          subscribers: [subscriber],
          session_id: @session
        )

      :ok = Subscriber.attach(subscriber, session, subscribe: false)
      await_macrostep(subscriber, 1)

      %{
        session: session,
        subscriber: subscriber,
        machine: machine,
        provenance: provenance,
        state: State.new(machine) |> State.sync(subscriber)
      }
    end

    @doc "Re-reads `run.state` off `run.subscriber` - what a host does after a send."
    @spec sync(map(), pid()) :: State.t()
    def sync(%{state: state}, subscriber), do: State.sync(state, subscriber)

    @doc "Stops a live run's session - call this from `on_exit`."
    @spec stop(map()) :: :ok
    def stop(%{session: session}), do: Statifier.Session.stop(session)

    @doc """
    A bounded poll on the subscriber's messages for `"trace.macrostep_stable"`
    at `macrostep` - never a sleep long enough to be felt, the discipline
    `card_run_fixtures.ex`'s `await_macrostep/2` and
    `StatifierBlocks.RuntimeFixtures.await_configuration/3` both set.
    """
    @spec await_macrostep(pid(), non_neg_integer(), non_neg_integer()) :: :ok
    def await_macrostep(subscriber, macrostep, attempts \\ 200) do
      stable? =
        Enum.any?(Subscriber.messages(subscriber), fn message ->
          message.type == "trace.macrostep_stable" and message.macrostep == macrostep
        end)

      cond do
        stable? ->
          :ok

        attempts == 0 ->
          raise "the live run never stabilized at macrostep #{macrostep}"

        true ->
          Process.sleep(5)
          await_macrostep(subscriber, macrostep, attempts - 1)
      end
    end
  end
end
