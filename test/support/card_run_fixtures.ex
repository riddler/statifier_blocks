# statifier-ui is optional here, exactly as `phoenix_live_view` is, and the
# headless CI job resolves a tree without either. Everything below names
# `StatifierUI` at compile time - it builds a real wire-format stream out of a
# real session - so the whole file is wrapped, the shape every other
# statifier-ui-naming file in this suite uses.
if Code.ensure_loaded?(StatifierUI.Live.State) do
  defmodule StatifierBlocks.CardRunFixtures do
    @moduledoc """
    One card-processing run, compiled from a block document and driven through
    statifier for real.

    The Run pane's claims are all about a stream: which blocks a configuration
    is inside at one macrostep and at another, which block's state handled a
    step, and what the datamodel held when the run was there. A hand-written
    message list can imply any of those, and implying them is exactly what
    would let the pane and the engine disagree without a test noticing. So this
    fixture compiles a document, starts a session, sends it an event, and keeps
    what the subscriber recorded.

    ## The shape, and why each block is the one it is

    A transaction opens waiting for its capture, the capture writes the
    settlement amount, and the run then waits to be told the money moved:

        core.sequence  blk_card_flow
          core.await   blk_card_open      card.captured
          core.assign  blk_card_amount    settlement <- 'settled'
          core.await   blk_card_settle    card.settled

    Two awaits and one event between them is what makes the stream **two
    macrosteps**, which is the smallest run the pane's assertions can be made
    against: one where the entry block is where the run is, one where the
    settle block is, and a scrubber move from the second to the first. The
    assign in the middle is what gives the Datamodel tab a value to draw beside
    a declared type; without it the run would hold nothing and "held" would be
    a column of blanks.

    The settle block is an await rather than anything that finishes, so the run
    is still *at* it at the tip. A block that completed would leave the
    configuration on the sequence's own final state, and the marks would name
    the container rather than the step - true, and not what an author watching
    a run wants to see.
    """

    alias StatifierBlocks.{Block, Compiled, Compiler, Document, Palette}
    alias StatifierUI.Live.State
    alias StatifierUI.Trace.Subscriber

    @session "sess_sb_card_run"
    @declare [{"settlement", nil}]

    @doc "The entry block: the transaction is open and waiting for its capture."
    @spec entry_block() :: String.t()
    def entry_block, do: "blk_card_open"

    @doc "The settle block: the capture landed and the run is waiting to settle."
    @spec settle_block() :: String.t()
    def settle_block, do: "blk_card_settle"

    @doc "The block that writes the settlement, and the path it writes."
    @spec written_path() :: String.t()
    def written_path, do: "settlement"

    @doc "The event that moves the run from the first macrostep to the second."
    @spec capture_event() :: String.t()
    def capture_event, do: "card.captured"

    @doc "The document the run is over."
    @spec document() :: Document.t()
    def document do
      Document.new(
        Block.new("core.sequence",
          id: "blk_card_flow",
          slots: %{
            "body" => [
              Block.new("core.await", id: entry_block(), config: %{"event" => capture_event()}),
              Block.new("core.assign",
                id: "blk_card_amount",
                config: %{"path" => written_path(), "value" => "'settled'"}
              ),
              Block.new("core.await", id: settle_block(), config: %{"event" => "card.settled"})
            ]
          }
        ),
        id: "bdoc_card_run"
      )
    end

    @doc "The palette the document resolves through."
    @spec palette() :: Palette.t()
    def palette, do: Palette.core()

    @doc "The roots the compile declares, which is what lets the assign bind."
    @spec declare() :: keyword()
    def declare, do: @declare

    @doc "The compiled chart and its provenance map."
    @spec compiled() :: Compiled.t()
    def compiled do
      {:ok, %Compiled{} = compiled} = Compiler.compile(document(), palette(), declare: @declare)
      compiled
    end

    @doc """
    The run: the compiled machine, the provenance map, and the recorded
    stream, having been sent one capture event.

    The subscriber attaches before the session starts stepping
    (`subscribe: false`), so the stream carries the `session.start` manifest
    the marks and the handled-block resolution both read; a late attach would
    leave both with nothing to resolve names through, which is a state worth
    testing and is not this fixture's.
    """
    @spec run() :: %{
            machine: Statifier.Machine.t(),
            provenance: StatifierBlocks.Provenance.t(),
            messages: [term()],
            state: State.t()
          }
    def run do
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
      Statifier.Session.send_event(session, capture_event())
      await_macrostep(subscriber, 2)

      messages = Subscriber.messages(subscriber)
      Statifier.Session.stop(session)

      %{
        machine: machine,
        provenance: provenance,
        messages: messages,
        state: State.new(machine, messages: messages)
      }
    end

    # A bounded poll rather than a fixed sleep, the discipline
    # `StatifierBlocks.RuntimeFixtures.await_configuration/3` already sets: a
    # sleep long enough to be reliable on a loaded machine is long enough to be
    # felt in every run of the suite.
    @spec await_macrostep(pid(), non_neg_integer(), non_neg_integer()) :: :ok
    defp await_macrostep(subscriber, macrostep, attempts \\ 200) do
      stable? =
        Enum.any?(Subscriber.messages(subscriber), fn message ->
          message.type == "trace.macrostep_stable" and message.macrostep == macrostep
        end)

      cond do
        stable? ->
          :ok

        attempts == 0 ->
          raise "the card run never stabilized at macrostep #{macrostep}"

        true ->
          Process.sleep(5)
          await_macrostep(subscriber, macrostep, attempts - 1)
      end
    end
  end
end
