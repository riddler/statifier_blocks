defmodule StatifierBlocks.Core.OnEventTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, Document, Palette}
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.OnEvent

  describe "validate_config/1 and the capture map" do
    # sabotage: dropped `check_capture/2` from `validate_config/1`'s pipeline
    # -> every rejected map below went green, taking this red (verified)
    test "accepts a map of datamodel path to _event.data path" do
      assert OnEvent.validate_config(capture(%{"order.cancel_reason" => "reason"})) == :ok

      assert OnEvent.validate_config(
               capture(%{"order.cancel_reason" => "reason", "order.at" => "at"})
             ) == :ok
    end

    # An absent key and an empty map are the same thing, and both are what a
    # document that never carried pairs - or carried them and no longer does -
    # looks like.
    #
    # sabotage: made `check_capture/2`'s `nil` clause report a finding -> the
    # absent case went red (verified); a second mutation dropping the
    # `is_map` clause's `Enum.all?` short-circuit took the empty case red
    # too, since `Enum.all?` over `%{}` is the arm that lets an empty map
    # through
    test "treats an absent capture and an empty one alike" do
      assert OnEvent.validate_config(Map.delete(capture(%{}), "capture")) == :ok
      assert OnEvent.validate_config(capture(%{})) == :ok
    end

    # sabotage: had `pair?/1` check only the destination -> the bad-source
    # cases went green, taking this red (verified). A second, narrower
    # mutation replacing `@whitespace` with a `[" ", "\t", "\n"]` membership
    # test left the carriage-return case green, taking it red on its own
    test "rejects a pair whose either half is not a path" do
      for bad <- [
            %{"" => "reason"},
            %{"order.cancel_reason" => ""},
            %{"order cancel_reason" => "reason"},
            %{"order.cancel_reason" => "the reason"},
            %{"order.cancel_reason" => "reason\r"},
            %{"order.cancel_reason" => "reason\t"},
            %{"order.cancel_reason" => 1},
            %{1 => "reason"}
          ] do
        assert {:error, [{"capture", _message}]} = OnEvent.validate_config(capture(bad)),
               inspect(bad)
      end
    end

    # sabotage: let the `_other` clause fall through to `findings` -> a
    # capture that is not a map at all went green, taking this red (verified)
    test "rejects a capture that is not a map" do
      for bad <- ["order.cancel_reason", ["order.cancel_reason"], 1] do
        assert {:error, [{"capture", _message}]} = OnEvent.validate_config(capture(bad)),
               inspect(bad)
      end
    end

    # The finding order is the order the editor renders, and `capture` is
    # checked last, so it reports last.
    #
    # sabotage: moved `check_capture/2` ahead of `check_event/2` in the
    # pipeline -> `Config.verdict/1` reversed them into a different order and
    # the ordered pattern went red (verified)
    test "reports capture after the fields declared before it" do
      assert {:error, [{"event", _}, {"outcome", _}, {"capture", _}]} =
               OnEvent.validate_config(%{"capture" => "not a map"})
    end
  end

  describe "emit/2 and the compiled assigns" do
    # sabotage: emitted the assigns after the raise rather than before ->
    # the index comparison went red (verified)
    test "writes one assign per pair, ahead of the outcome raise" do
      scxml =
        compile!(handler(%{"order.cancel_reason" => "reason", "order.cancelled_at" => "at"}))

      assert scxml =~ ~s(<assign expr="_event.data.reason" location="order.cancel_reason"/>)
      assert scxml =~ ~s(<assign expr="_event.data.at" location="order.cancelled_at"/>)

      assert index(scxml, ~s(location="order.cancel_reason")) <
               index(scxml, "<raise ")

      assert index(scxml, ~s(location="order.cancelled_at")) <
               index(scxml, "<raise ")
    end

    # A map has no order of its own, and above 32 pairs its iteration order
    # is a hash order rather than the sorted one a small map happens to
    # give - which is exactly why the record fixes an order rather than
    # leaving the bytes to iteration. Forty pairs is what makes this
    # assertion able to fail.
    #
    # sabotage: dropped the `Enum.sort_by/2` from `captures/1` -> the emitted
    # order followed the map's iteration and this went red (verified; it
    # stays green with the sort under either map representation)
    test "orders the pairs by their datamodel paths, not by the map's iteration" do
      pairs = for n <- 0..39, into: %{}, do: {"d.k#{String.pad_leading("#{n}", 2, "0")}", "s#{n}"}

      emitted =
        pairs
        |> handler()
        |> compile!()
        |> then(&Regex.scan(~r/<assign expr="[^"]*" location="([^"]*)"\/>/, &1))
        |> Enum.map(fn [_whole, location] -> location end)

      assert emitted == Enum.sort(Map.keys(pairs))
      assert length(emitted) == 40
    end

    # The additivity claim, asserted as bytes rather than as prose: a handler
    # that carries no capture compiles to exactly what it compiled to before
    # the key existed, and an emptied one is the same handler.
    #
    # sabotage: made `captures/1`'s `nil` clause emit a single assign from a
    # hard-coded pair -> both comparisons went red (verified)
    test "compiles byte-identically to today for a handler with no capture" do
      without = compile!(Map.delete(handler(%{}).config, "capture") |> block())
      absent = compile!(handler(nil))
      empty = compile!(handler(%{}))

      assert absent == without
      assert empty == without
      refute without =~ "<assign"
    end

    # `emit/2` is checked directly rather than through a compile, for the
    # reason `emit_test.exs` gives about the guard: the Config stage rejects
    # this config first, so a compile would go red whether or not `emit/2`
    # answered for it, and the answer is the thing under test. A capture
    # silently dropped is the failure the key exists to prevent.
    #
    # sabotage: had `captures/1`'s malformed arm return `{:ok, []}` ->
    # `emit/2` answered `{:ok, ...}` with the pair dropped and no assign
    # emitted, taking this red (verified)
    test "refuses a malformed capture rather than dropping the pair" do
      assert {:error, [{"capture", _message}]} =
               OnEvent.emit(
                 block(%{
                   "event" => "order.cancelled",
                   "outcome" => "abandon",
                   "capture" => %{"order.cancel_reason" => ""}
                 }),
                 Context.new("blk_OE", "bdoc_T")
               )
    end
  end

  describe "what the interpreter does with a captured path" do
    # The record's run-time claim, pinned against the engine rather than
    # against the record: a source path the payload does not carry is
    # written as the engine's explicit unbound marker, and that marker is
    # not `nil`. A consumer of a captured path tests for it; the
    # `error.execution` the record's bullet describes is upstream work and
    # is deliberately NOT asserted here, because it does not happen today.
    #
    # sabotage: none available in this package - the behaviour under test is
    # the engine's, and this test is here to go red if a version bump
    # changes it. Its own construction was verified instead by asserting
    # `nil` in place of the marker, which went red on the real engine.
    test "writes the unbound marker, not nil, for a payload key that is not there" do
      {machine_state, _effects} =
        run(%{"order.cancel_reason" => "reason"}, %{"order" => %{}})

      captured = machine_state.datamodel |> Map.fetch!("order") |> Map.fetch!("cancel_reason")

      assert captured == :undefined
      refute captured == nil
    end

    # The other half of the pair, so the test above is read as "the payload
    # was missing" rather than "capture never writes anything".
    #
    # sabotage: dropped the assigns from the transition's children -> the
    # path was never written and this went red (verified)
    test "writes the payload value when the source path is there" do
      {machine_state, _effects} =
        run(%{"order.cancel_reason" => "reason"}, %{"order" => %{}},
          data: %{"reason" => "customer_request"}
        )

      assert machine_state.datamodel["order"]["cancel_reason"] == "customer_request"
    end
  end

  # -- helpers ---------------------------------------------------------------

  defp capture(value), do: %{"event" => "order.cancelled", "outcome" => "abandon"} |> put(value)

  defp put(config, value), do: Map.put(config, "capture", value)

  defp handler(pairs) do
    block(%{"event" => "order.cancelled", "outcome" => "abandon", "capture" => pairs})
  end

  defp block(config), do: Block.new("core.on_event", id: "blk_OE", config: config)

  defp compile!(%Block{} = root) do
    {:ok, compiled} = Compiler.compile(Document.new(root, id: "bdoc_T"), Palette.core())
    compiled.scxml
  end

  defp index(haystack, needle) do
    [{start, _length}] = Regex.run(~r/#{Regex.escape(needle)}/, haystack, return: :index)
    start
  end

  # A capturing handler in a group whose body waits, so the interrupt has
  # something live to interrupt, run to the point just after the event has
  # fired the handler.
  defp run(pairs, datamodel, opts \\ []) do
    root =
      Block.new("core.group",
        id: "blk_GRP",
        slots: %{
          "body" => [Block.new("core.wait", id: "blk_STEP", config: %{"duration" => "48h"})],
          "interrupts" => [
            Block.new("core.on_event",
              id: "blk_INT",
              config: %{
                "event" => "order.cancelled",
                "outcome" => "abandon",
                "capture" => pairs
              }
            )
          ]
        }
      )

    {:ok, machine} = Statifier.compile(compile!(root))
    {machine_state, _effects} = Statifier.initialize(machine, datamodel: datamodel)

    {:ok, machine_state, effects} =
      Statifier.send_event(
        machine_state,
        Statifier.Event.external("order.cancelled", Keyword.take(opts, [:data]))
      )

    {machine_state, effects}
  end
end
