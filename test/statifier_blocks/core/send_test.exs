defmodule StatifierBlocks.Core.SendTest do
  @moduledoc """
  `core.send`: the event grammar it shares with `core.raise`, the optional
  delay that is the vocabulary's first, and the compiled `<send>`.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, Document, Palette, Provenance}
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.{Raise, Send}

  describe "validate_config/1" do
    # Sabotage: inverted `check_event/2`'s condition -> a good event name
    # was rejected, taking this red (verified).
    test "accepts an event name with or without a delay" do
      assert Send.validate_config(%{"event" => "signup.abandoned"}) == :ok
      assert Send.validate_config(%{"event" => "signup.abandoned", "delay" => "PT2H"}) == :ok
      assert Send.validate_config(%{"event" => "signup.abandoned", "delay" => "1h30m"}) == :ok
    end

    # Sabotage: dropped the `check_event/2` clause from the `|>` pipeline
    # in `validate_config/1` -> every bad event below went green, taking
    # this red (verified).
    test "rejects everything an event name cannot be" do
      assert {:error, [{"event", _}]} = Send.validate_config(%{"event" => ""})
      assert {:error, [{"event", _}]} = Send.validate_config(%{"event" => "two words"})
      assert {:error, [{"event", _}]} = Send.validate_config(%{"event" => 1})
      assert {:error, [{"event", _}]} = Send.validate_config(%{})
    end

    # The three-way property `core.raise`'s own suite states two-way: a
    # name any one of them refuses is a rail that cannot catch what a step
    # sends.
    #
    # Sabotage: relaxed `check_event/2` to `Config.non_empty_string?/1` ->
    # `core.send` accepted `"has space"` and `".leading"` while
    # `core.raise` still refused them, parting the two grammars and taking
    # this red (verified).
    test "speaks core.raise's event grammar, name for name" do
      names = [
        "signup.abandoned",
        "signup.email_verified",
        "error.communication.invoke.blk_x",
        "done.state.blk_y",
        "Cancelled",
        "_internal",
        "a-b.c_d.9",
        "",
        "  ",
        ".leading",
        "9starts_with_a_digit",
        "has space",
        "has/slash"
      ]

      disagreements =
        Enum.filter(names, fn event ->
          sends = Send.validate_config(%{"event" => event}) == :ok
          raises = Raise.validate_config(%{"event" => event}) == :ok
          sends != raises
        end)

      assert disagreements == []
    end

    # An absent key and the field's own default are both "no delay", and
    # the default is what the config form writes into every block of this
    # type - so `""` cannot be a finding.
    #
    # Sabotage: dropped the `{:ok, ""}` clause from `check_delay/2` -> the
    # empty default became a finding on every freshly dropped block,
    # taking this red (verified).
    test "an absent delay and the empty default are both silent" do
      assert Send.validate_config(%{"event" => "signup.abandoned"}) == :ok
      assert Send.validate_config(%{"event" => "signup.abandoned", "delay" => ""}) == :ok
    end

    # Sabotage: dropped the `check_delay/2` clause from the pipeline ->
    # every bad delay below went green, taking this red (verified).
    test "rejects a present delay that is not a duration in either spelling" do
      for bad <- ["soon", "7200", "P", "PT", "1.5s", "500ms", 90, nil] do
        assert {:error, [{"delay", _}]} =
                 Send.validate_config(%{"event" => "signup.abandoned", "delay" => bad})
      end
    end

    # Sabotage: swapped `check_event/2` and `check_delay/2` in the
    # pipeline -> `Config.verdict/1` reversed them into `[delay, event]`
    # and the ordered pattern went red, which is this assertion earning
    # its keep: the finding order is the order the editor renders
    # (verified).
    test "reports both findings when both fields are bad, event first" do
      assert {:error, [{"event", _}, {"delay", _}]} =
               Send.validate_config(%{"event" => "has space", "delay" => "soon"})
    end
  end

  describe "leaf-ness" do
    # Sabotage: gave `slots/1` a `body` slot -> red, since a send is a
    # leaf with nothing to sequence (verified).
    test "declares no slots and one step kind" do
      assert Send.slots(%{"event" => "signup.abandoned"}) == []
      assert Send.io(%{}) == %{kinds: [:step]}
    end
  end

  # Sabotage: made the delay field `required?: true` -> red, because the
  # optionality is the whole of what separates this field from
  # `core.wait`'s (verified).
  test "config_schema/1 declares a required event then an optional duration" do
    assert Send.config_schema(%{}) == [
             %{
               key: "event",
               type: :string,
               label: "Send this event",
               required?: true,
               default: ""
             },
             %{key: "delay", type: :duration, label: "After", required?: false, default: ""}
           ]
  end

  describe "compiled SCXML" do
    # Sabotage: emitted `<raise>` instead of `<send>` -> red, and with it
    # the queue difference that is the reason `core.send` and `core.raise`
    # are two types (verified).
    test "emits <send> inside <onentry>, in a compound state with its own <final>" do
      scxml = compile!(send_block(%{"event" => "signup.abandoned"})).scxml

      assert scxml =~ ~s(<state id="s_blk_SND" initial="s_blk_SND__o_done">)
      assert scxml =~ ~s(<onentry><send event="signup.abandoned"/></onentry>)

      assert scxml =~
               ~s(<final id="s_blk_SND__o_done"><onentry>) <>
                 ~s(<raise event="done.outcome.s_blk_SND.done"/></onentry></final>)
    end

    # Sabotage: returned `{:ok, "0s"}` from both of `delay/1`'s "no delay"
    # arms -> the send grew a zero delay, which puts it on a later
    # macrostep and is exactly the "no delay is not PT0S" distinction,
    # taking this red (verified).
    test "no delay means no delay attribute at all" do
      for config <- [
            %{"event" => "signup.abandoned"},
            %{"event" => "signup.abandoned", "delay" => ""}
          ] do
        scxml = compile!(send_block(config)).scxml

        assert scxml =~ ~s(<send event="signup.abandoned"/>)
        refute scxml =~ "delay="
      end
    end

    # Sabotage: emitted the ISO value in the `delay` attribute rather than
    # `Duration.to_delay/1`'s shorthand -> `delay="PT2H"`, which
    # `Statifier.Duration` does not read, taking this red (verified).
    test "an ISO delay is emitted as the shorthand the engine reads" do
      scxml = compile!(send_block(%{"event" => "signup.abandoned", "delay" => "PT2H"})).scxml

      assert scxml =~ ~s(<send delay="2h" event="signup.abandoned"/>)
    end

    # Sabotage: had `delay/1` answer `{:ok, value}` with the stored bytes
    # instead of calling `compiled/1` -> a stored `1h30m` still happened
    # to emit `1h30m`, but `8h3d` emitted `8h3d` rather than the canonical
    # `3d8h`, taking this red on the second case (verified).
    test "a predicator delay compiles through the ISO pivot and back" do
      scxml = compile!(send_block(%{"event" => "signup.abandoned", "delay" => "1h30m"})).scxml
      assert scxml =~ ~s(<send delay="1h30m" event="signup.abandoned"/>)

      reordered = compile!(send_block(%{"event" => "signup.abandoned", "delay" => "8h3d"})).scxml
      assert reordered =~ ~s(<send delay="3d8h" event="signup.abandoned"/>)
    end
  end

  describe "end to end" do
    # Sabotage: dropped `Emit.final(done)` from the children `emit/2`
    # passes to `Emit.state/3` -> the block never reaches a `<final>`,
    # `done.state` is never raised, and the block's own state stays active
    # instead, taking this red (verified).
    test "the chart compiles, and the block completes when the send is armed" do
      compiled = compile!(send_block(%{"event" => "signup.abandoned", "delay" => "PT2H"}))

      {:ok, machine} = Statifier.compile(compiled.scxml)
      {machine_state, _effects} = Statifier.initialize(machine)

      assert MapSet.member?(Statifier.active_leaf_states(machine_state), "s_blk_SND__o_done")
    end

    # The check that makes the shorthand a contract rather than a habit:
    # `Statifier.Duration.to_ms/1` is what resolves a `delay` attribute at
    # runtime, and it reads the predicator unit grammar only - it answers
    # `{:error, {:invalid_delay, "PT2H"}}` for the ISO spelling. So a chart
    # that carries ISO in `delay` compiles and then fails to arm.
    #
    # Sabotage: had `compiled/1` answer the ISO value instead of
    # `Duration.to_delay/1`'s shorthand -> `to_ms/1` refused every emitted
    # delay, taking this red (verified).
    test "every delay this type emits is one the engine can resolve" do
      for stored <- ["PT2H", "1h30m", "8h3d", "P1Y2M3DT4H5M6S", "PT0S"] do
        scxml = compile!(send_block(%{"event" => "signup.abandoned", "delay" => stored})).scxml

        [_whole, delay] = Regex.run(~r/<send delay="([^"]+)"/, scxml)

        assert {:ok, _milliseconds} = Statifier.Duration.to_ms(delay)
      end
    end
  end

  describe "emit/2" do
    # Sabotage: made `event/1` fall through to `{:ok, event}`
    # unconditionally -> emit/2 answered {:ok, ...} for a config
    # validate_config/1 rejects, taking this red (verified).
    test "refuses an event it cannot compile rather than emitting nonsense" do
      block = send_block(%{"event" => ""})

      assert {:error, [{"event", _message}]} = Send.emit(block, Context.new("blk_SND", "bdoc_T"))
    end

    # Sabotage: made `compiled/1` raise on an unparseable delay instead of
    # returning a finding -> the test failed with the raise rather than
    # matching, which is decision 1's "an Emit finding, never a raise"
    # (verified).
    test "an unparseable delay is a finding, never a raise" do
      block = send_block(%{"event" => "signup.abandoned", "delay" => "soon"})

      assert {:error, [{"delay", _message}]} = Send.emit(block, Context.new("blk_SND", "bdoc_T"))
    end
  end

  describe "provenance" do
    # Sabotage: dropped the `Emission.attribute_from_config/3` call on the
    # send element -> the event value's span carried no config key, taking
    # this red (verified).
    test "the sent event's value is attributed to the block and the event field" do
      compiled = compile!(send_block(%{"event" => "signup.abandoned", "delay" => "PT2H"}))

      {offset, _length} = :binary.match(compiled.scxml, "signup.abandoned")

      assert {:ok, %{block_id: "blk_SND", config_key: "event"}} =
               Provenance.owner_at(compiled.provenance, offset)
    end

    # The delay's emitted bytes are not the author's - `PT2H` was stored
    # and `2h` was written - so annotating them would point a finding at a
    # span nobody typed. `core.wait` leaves its own delay unannotated too.
    #
    # Sabotage: added `attribute_from_config("delay", "delay")` to the
    # send element -> the derived span claimed the author's config key,
    # taking this red (verified).
    test "the delay attribute is not attributed, because it is derived" do
      compiled = compile!(send_block(%{"event" => "signup.abandoned", "delay" => "PT2H"}))

      {offset, _length} = :binary.match(compiled.scxml, ~s(delay="2h"))
      {offset, _length} = :binary.match(compiled.scxml, "2h", scope: {offset, 10})

      assert {:ok, owner} = Provenance.owner_at(compiled.provenance, offset)
      refute Map.get(owner, :config_key) == "delay"
    end
  end

  defp send_block(config), do: Block.new("core.send", id: "blk_SND", config: config)

  defp compile!(root) do
    {:ok, compiled} = Compiler.compile(Document.new(root, id: "bdoc_T"), Palette.core())
    compiled
  end
end
