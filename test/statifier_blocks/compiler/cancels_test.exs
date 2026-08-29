defmodule StatifierBlocks.Compiler.CancelsTest do
  @moduledoc """
  The scope-shaped cancel (ADR-0004's 2026-08-29 amendment): a delayed
  `core.send` gets its `<cancel>` in the `<onexit>` of the nearest
  enclosing scope state, and nowhere else.
  """

  use ExUnit.Case, async: true

  alias Statifier.Effect.Cancel
  alias StatifierBlocks.{Block, Compiler, Document, Palette, Provenance}
  alias StatifierBlocks.Compiler.Cancels

  describe "armed_role/0" do
    # Sabotage: returned "timer" instead of "send" -> every arming block's
    # id became `s_blk___timer` and the whole suite below went red at once
    # (verified).
    test "names the one role both halves of the convention turn on" do
      assert Cancels.armed_role() == "send"
    end
  end

  describe "the enclosing scope" do
    # Sabotage: had `Cancels.arm/2` return its emission unchanged -> the
    # sequence emitted no `<onexit>` at all, which is the whole of what
    # the amendment adds (verified).
    test "a sequence carries the cancel for a delayed send in its body" do
      scxml = compile!(sequence_with_send("2h")).scxml

      assert scxml =~
               ~s(<state id="s_blk_SEQ" initial="s_blk_SND">) <>
                 ~s(<onexit><cancel sendid="s_blk_SND__send"/></onexit>)
    end

    # An undelayed send is on the external queue before the scope can be
    # exited, so a cancel for it could never match a pending timer.
    #
    # Sabotage: dropped the `List.keymember?(attributes, "delay", 0)`
    # guard from `armed?/2` -> an instantaneous send grew a cancel that
    # can never fire, taking this red (verified).
    test "an undelayed send arms nothing, so its scope cancels nothing" do
      scxml = compile!(sequence_with_send("")).scxml

      assert scxml =~ ~s(<send event="signup.abandoned" id="s_blk_SND__send"/>)
      refute scxml =~ "<cancel"
      refute scxml =~ "<onexit>"
    end

    # "The state that armed the send" is the NEAREST enclosing scope, not
    # every scope above it - the operator's 2026-08-29 ruling on the shape.
    #
    # Sabotage: made `armed_sends/2` ignore the block id in the send id and
    # match any `<send>` under the child -> the outer group cancelled the
    # inner sequence's send as well, giving two cancels for one send and
    # taking the second assertion red (verified).
    test "a nested send is cancelled by the nearest scope only" do
      scxml = compile!(group_around(sequence_with_send("2h"))).scxml

      assert scxml =~
               ~s(<state id="s_blk_SEQ" initial="s_blk_SND">) <>
                 ~s(<onexit><cancel sendid="s_blk_SND__send"/></onexit>)

      assert [_one] = Regex.scan(~r/<cancel /, scxml)
    end

    # Sabotage: sorted the collected ids instead of keeping the order the
    # compiler hands children over in -> `blk_SND2` came first and the
    # document-order pin went red, which is decision 6's determinism
    # (verified).
    test "two sends in one scope cancel in document order" do
      root =
        Block.new("core.sequence",
          id: "blk_SEQ",
          slots: %{"body" => [send_block("blk_SND1", "2h"), send_block("blk_SND2", "3h")]}
        )

      scxml = compile!(root).scxml

      assert scxml =~
               ~s(<onexit><cancel sendid="s_blk_SND1__send"/>) <>
                 ~s(<cancel sendid="s_blk_SND2__send"/></onexit>)
    end

    # Sabotage: made `arm/2` inject into any element rather than only a
    # `<state>`/`<parallel>`, and had the root document's own wrapper pass
    # through it -> a `<cancel>` appeared outside every state, the engine
    # refused the compile, and this went red (verified).
    test "a send that is the whole document has no enclosing scope" do
      scxml = compile!(send_block("blk_SND", "2h")).scxml

      refute scxml =~ "<cancel"
    end

    # `core.wait` mints a delayed `<send>` of its own, and a wait left
    # before its delay elapses would otherwise leave that send armed in a
    # durable host - the interpreter's exit of the wait's state cancels
    # nothing an external scheduler already holds. So the wait mints under
    # the same reserved role and the scope reaches it.
    #
    # Sabotage: put `core.wait`'s send back under a role of its own -> the
    # id read `s_blk_WAI__timer`, no cancel was emitted, and both
    # assertions went red (verified).
    test "a core.wait timer is a cancellable armed send" do
      root =
        Block.new("core.sequence",
          id: "blk_SEQ",
          slots: %{
            "body" => [Block.new("core.wait", id: "blk_WAI", config: %{"duration" => "2h"})]
          }
        )

      scxml = compile!(root).scxml

      assert scxml =~ ~s(id="s_blk_WAI__send")
      assert scxml =~ ~s(<onexit><cancel sendid="s_blk_WAI__send"/></onexit>)
    end
  end

  describe "provenance" do
    # The cancel is a consequence of where the send sits in this scope, so
    # a finding against it is the scope's, not the send block's.
    #
    # Sabotage: attributed the injected `<onexit>` to the send block with
    # `Emission.attributed_to/2` - the other reading of whose cancel this
    # is - and `owner_at/2` answered `blk_SND`, taking this red (verified).
    # Running the pass after `Attribution.stamp/3` rather than before it
    # does NOT show up here: an unstamped element inherits the enclosing
    # range, which happens to be this same scope.
    test "the cancel belongs to the scope that emitted it" do
      compiled = compile!(group_around(sequence_with_send("2h")))

      {offset, _length} = :binary.match(compiled.scxml, ~s(<cancel sendid=))

      assert {:ok, %{block_id: "blk_SEQ"}} = Provenance.owner_at(compiled.provenance, offset)
    end
  end

  describe "the compiled chart, run" do
    setup do
      compiled = compile!(group_around(parked_sequence()))
      {:ok, machine} = Statifier.compile(compiled.scxml)
      {machine_state, effects} = Statifier.initialize(machine)

      %{machine_state: machine_state, initial_effects: effects}
    end

    # The send is armed and the sequence is parked in the wait behind it,
    # so the scope is still live and nothing may have cancelled yet.
    #
    # Sabotage: moved the `<onexit>` onto the send block's own state
    # rather than its scope's -> the send's state goes final the instant
    # it is entered, the cancel fired in the same macrostep that armed it,
    # and this went red (verified).
    test "the armed send is still pending while its scope is live", ctx do
      assert cancels(ctx.initial_effects) == []

      assert MapSet.member?(
               Statifier.active_leaf_states(ctx.machine_state),
               "s_blk_WAI__waiting"
             )
    end

    # The runtime half, through the resolved statifier: leaving the scope
    # has to produce a `{:cancel, %Cancel{}}` effect naming the derived
    # send id, which is the pair `{session scope, send id}` statifier-ex
    # ADR-0054 decision 3 keys a pending delayed send on.
    #
    # Sabotage: emitted `<cancel sendid="s_blk_SND">` (the block's state
    # id rather than the send id) -> the effect still surfaced, naming a
    # send nothing had armed, and the `send_id` assertion went red
    # (verified).
    test "exiting the scope yields the cancel effect naming the derived send id", ctx do
      {:ok, _machine_state, effects} =
        Statifier.send_event(ctx.machine_state, "signup.abandoned")

      assert [%Cancel{send_id: "s_blk_SND__send"} | _rest] = cancels(effects)
    end

    # `core.wait`'s own delayed send sits in the same scope and is armed in
    # the same macrostep, and the run is parked behind it when the scope is
    # left - which is exactly the abandoned wait a durable host would
    # otherwise be left holding a timer for.
    #
    # Sabotage: put `core.wait`'s send back under a role of its own -> only
    # the `core.send`'s cancel came back and this went red (verified).
    test "the wait's timer in the same scope is cancelled too", ctx do
      {:ok, _machine_state, effects} =
        Statifier.send_event(ctx.machine_state, "signup.abandoned")

      assert Enum.map(cancels(effects), & &1.send_id) == [
               "s_blk_SND__send",
               "s_blk_WAI__send"
             ]
    end
  end

  defp cancels(effects), do: for({:cancel, cancel} <- effects, do: cancel)

  defp send_block(id, delay) do
    Block.new("core.send",
      id: id,
      config: %{"event" => "signup.abandoned", "delay" => delay}
    )
  end

  defp sequence_with_send(delay) do
    Block.new("core.sequence", id: "blk_SEQ", slots: %{"body" => [send_block("blk_SND", delay)]})
  end

  # The same scope with a `core.wait` behind the send, so the sequence is
  # still active after the first macrostep and the run can be observed
  # both before and after the scope is left.
  defp parked_sequence do
    Block.new("core.sequence",
      id: "blk_SEQ",
      slots: %{
        "body" => [
          send_block("blk_SND", "2h"),
          Block.new("core.wait", id: "blk_WAI", config: %{"duration" => "48h"})
        ]
      }
    )
  end

  # A group whose interrupt rail abandons on an external event, so the
  # body region - and the sequence in it - is genuinely exited at runtime.
  defp group_around(body) do
    Block.new("core.group",
      id: "blk_GRP",
      slots: %{
        "body" => [body],
        "interrupts" => [
          Block.new("core.on_event",
            id: "blk_INT",
            config: %{"event" => "signup.abandoned", "outcome" => "abandon"}
          )
        ]
      }
    )
  end

  defp compile!(root) do
    {:ok, compiled} = Compiler.compile(Document.new(root, id: "bdoc_T"), Palette.core())
    compiled
  end
end
