defmodule StatifierBlocks.InvokeStepTest.Receipt do
  @moduledoc "A leaf step declaring nothing but the invoke type it names."

  use StatifierBlocks.InvokeStep,
    invoke_type: "myapp:receipt",
    palette: %{label: "Receipt", group: "Card processing", icon: "document-text"}
end

defmodule StatifierBlocks.InvokeStepTest.Authorize do
  @moduledoc "A leaf step with a required field, a produced type, and a param."

  use StatifierBlocks.InvokeStep,
    invoke_type: "myapp:authorize",
    produces: "myapp.authorization",
    fields: [
      %{
        key: "assign_to",
        type: :string,
        label: "Write the decision to",
        required?: true,
        default: "authorization",
        datamodel_path?: true
      }
    ],
    palette: %{label: "Authorize card", group: "Card processing", keywords: ["card"]}

  alias StatifierBlocks.InvokeStep

  @assign_to_message "must be a bare lowercase identifier, like authorization"

  @impl true
  def validate_config(config) do
    []
    |> InvokeStep.check_invoke_type(config)
    |> InvokeStep.check_identifier(config, "assign_to", @assign_to_message)
    |> InvokeStep.verdict()
  end

  @impl true
  def emit(block, context) do
    InvokeStep.emit(block, context, invoke_type(), [
      InvokeStep.literal_param("channel", "network", "invoke_type")
    ])
  end
end

defmodule StatifierBlocks.InvokeStepTest do
  @moduledoc """
  ADR-0007 decision 2: `use StatifierBlocks.InvokeStep` is the leaf step
  that names one host invoke type, declared rather than spelled.

  The emission it produces is `core.invoke`'s with the `on_error` slot
  taken out, so the shape assertions here mirror
  `core/invoke_test.exs`'s - deliberately, because the two must not drift.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, BlockType, Compiler, Document, InvokeStep, Palette, Provenance}
  alias StatifierBlocks.InvokeStepTest.{Authorize, Receipt}

  describe "what use declares (ADR-0007 decision 2)" do
    # Sabotage: renamed the injected `invoke_type/0` - the declaration is
    # no longer readable back off the module, the file stops compiling, and
    # this goes red (verified).
    test "the declared invoke type is the module's own answer" do
      assert Receipt.invoke_type() == "myapp:receipt"
      assert Authorize.invoke_type() == "myapp:authorize"
      assert BlockType in (Receipt.module_info(:attributes)[:behaviour] || [])
    end

    # Sabotage: put the `invoke_type` field ahead of `label` in
    # `config_schema/2` - the inspector renders declaration order, so the
    # card's own name stops leading the form and this goes red (verified).
    test "the schema is label, then invoke_type prefilled, then the declared fields" do
      assert [label, invoke_type] = Receipt.config_schema(%{})
      assert %{key: "label", type: :string, required?: false, default: ""} = label
      assert %{key: "invoke_type", required?: true, default: "myapp:receipt"} = invoke_type

      assert [%{key: "label"}, %{key: "invoke_type"}, %{key: "assign_to", required?: true}] =
               Authorize.config_schema(%{})
    end

    # Sabotage: made `io/1` ignore the `:produces` option - the step stops
    # declaring what its answer produces to the next sibling and this goes
    # red (verified).
    test "io is a step, and carries produces only when the step declared one" do
      assert Receipt.io(%{}) == %{kinds: [:step]}
      assert Authorize.io(%{}) == %{kinds: [:step], produces: "myapp.authorization"}
    end

    # Sabotage: reversed `outcomes/0` - ADR-0004 decision 6's byte
    # determinism reads the order, so the two outcomes swap in the compiled
    # bytes and this goes red (verified).
    test "two outcomes, done before error, never sorted" do
      assert Receipt.outcomes(%{}) == [{"done", "Done"}, {"error", "Error"}]
      assert BlockType.outcomes(Receipt, %{}) == [{"done", "Done"}, {"error", "Error"}]
    end

    # Sabotage: reversed the merge in `palette_entry/1` so the defaults win
    # over the declaration - `Authorize`'s own keywords are overwritten by
    # the empty default and this goes red (verified).
    test "the declared palette keys win over the base's defaults" do
      assert Receipt.palette_entry() == %{
               layout: :stack,
               keywords: [],
               label: "Receipt",
               group: "Card processing",
               icon: "document-text"
             }

      assert Authorize.palette_entry().keywords == ["card"]
    end

    # Sabotage: dropped the `checked_declaration/1` guard - a typo'd
    # invoke type compiles and is met later as a finding by every author of
    # every document carrying the step, and this goes red (verified).
    test "a declared invoke type outside the grammar is a compile error" do
      assert_raise ArgumentError, ~r/namespace:name/, fn ->
        defmodule Broken do
          @moduledoc false
          use StatifierBlocks.InvokeStep, invoke_type: "receipt"
        end
      end
    end
  end

  describe "validate_config/1" do
    # Sabotage: made `check_invoke_type/2` refuse an absent key - a step
    # running on its declared default becomes invalid, and this goes red
    # (verified).
    test "an absent invoke_type is the declared default, not a gap" do
      assert Receipt.validate_config(%{}) == :ok
      assert Receipt.validate_config(%{"invoke_type" => "myapp:receipt"}) == :ok
    end

    # Sabotage: accepted any non-empty string as an invoke type - a bare
    # "receipt" validates and this goes red (verified).
    test "a stored invoke_type is checked against the namespace:name grammar" do
      assert {:error, [{"invoke_type", message}]} =
               Receipt.validate_config(%{"invoke_type" => "receipt"})

      assert message =~ "namespace:name"
    end

    # Sabotage: narrowed `check_assign_to/2`'s blank arm to `nil` - a
    # stored empty string stops counting as blank, so a step that keeps
    # nothing is refused and this goes red (verified).
    test "assign_to is optional by default, and an identifier when it is there" do
      assert Receipt.validate_config(%{"assign_to" => ""}) == :ok

      assert {:error, [{"assign_to", _message}]} =
               Receipt.validate_config(%{"assign_to" => "Auth.x"})
    end

    # Sabotage: made `check_identifier/4` accept anything - the required
    # key a step overrode `validate_config/1` to demand stops being
    # demanded and this goes red (verified).
    test "a step that requires the key refuses the blank" do
      assert Authorize.validate_config(%{"assign_to" => "authorization"}) == :ok
      assert {:error, [{"assign_to", _message}]} = Authorize.validate_config(%{})
    end
  end

  describe "the compiled emission" do
    setup do
      %{receipt: compile!(step("myapp.receipt", "blk_RCP", %{}))}
    end

    # Sabotage: emitted the `<invoke>` without its `type` attribute - the
    # chart names no invoke type and this goes red (verified).
    test "names the declared invoke type, and never runs one", %{receipt: compiled} do
      assert compiled.scxml =~ ~s(<invoke type="myapp:receipt"/>)
      assert compiled.invoke_types == ["myapp:receipt"]
    end

    # Sabotage: emitted the failure transition on ADR-0068's full event
    # with a literal invoke id - the descriptor stops matching the id the
    # engine mints and this goes red (verified).
    test "both outcomes are reachable transitions on the inner state", %{receipt: compiled} do
      assert compiled.scxml =~
               ~s(<transition event="done.invoke" target="s_blk_RCP__o_done"/>)

      assert compiled.scxml =~
               ~s(<transition event="error.communication.invoke" target="s_blk_RCP__o_error"/>)
    end

    # Sabotage: emitted only the done final - a parent wiring the error
    # outcome has nothing to hear and this goes red (verified).
    test "one <final> per outcome, each raising its own event", %{receipt: compiled} do
      assert compiled.scxml =~
               ~s(<final id="s_blk_RCP__o_done"><onentry>) <>
                 ~s(<raise event="done.outcome.s_blk_RCP.done"/></onentry></final>)

      assert compiled.scxml =~
               ~s(<final id="s_blk_RCP__o_error"><onentry>) <>
                 ~s(<raise event="done.outcome.s_blk_RCP.error"/></onentry></final>)
    end

    # Sabotage: dropped the `<assign>` from the success transition - the
    # handler's answer is never written anywhere and this goes red
    # (verified).
    test "assign_to writes the answer on the success path only" do
      compiled =
        compile!(step("myapp.receipt", "blk_RCP", %{"assign_to" => "receipt"}))

      assert compiled.scxml =~
               ~s(<transition event="done.invoke" target="s_blk_RCP__o_done">) <>
                 ~s(<assign expr="_event.data" location="receipt"/></transition>)

      # The failure transition carries nothing: an error is not an answer.
      refute compiled.scxml =~
               ~s(<transition event="error.communication.invoke" target="s_blk_RCP__o_error"><assign)
    end

    # Sabotage: swapped `literal_param/3`'s name and value - the `<param>`
    # carries the channel name as its literal and this goes red
    # (verified).
    test "a step's own <param> children ride on the <invoke>" do
      compiled = compile!(step("myapp.authorize", "blk_AUT", %{"assign_to" => "authorization"}))

      assert compiled.scxml =~ ~s(<param expr="'network'" name="channel"/>)
    end

    # Sabotage: minted the outcome finals with `Context.role_id/2` in the
    # `o_` namespace - the reservation refuses them, the compile fails
    # with an Emit finding, and this goes red (verified).
    test "every state the step emits is owned by its block", %{receipt: compiled} do
      for state_id <- [
            "s_blk_RCP",
            "s_blk_RCP__running",
            "s_blk_RCP__o_done",
            "s_blk_RCP__o_error"
          ] do
        assert {:ok, owner} = Provenance.owner_of_state(compiled.provenance, state_id)
        assert owner.block_id == "blk_RCP", state_id
      end
    end
  end

  describe "the compiled chart, run" do
    # Sabotage: pointed the success transition back at the running state -
    # the run never reaches a final and this goes red (verified).
    test "a done.invoke lands the run in the done outcome" do
      {:ok, machine_state, _effects} =
        send_to(step("myapp.receipt", "blk_RCP", %{}), "done.invoke.inv_1")

      assert active?(machine_state, "s_blk_RCP__o_done")
    end

    # Sabotage: pointed the failure transition at the done outcome - a
    # failed call finishes as a success and this goes red (verified).
    test "ADR-0068's error lands the run in the error outcome" do
      {:ok, machine_state, _effects} =
        send_to(step("myapp.receipt", "blk_RCP", %{}), "error.communication.invoke.inv_1")

      assert active?(machine_state, "s_blk_RCP__o_error")
    end
  end

  describe "invoke_type/2" do
    # Sabotage: made `invoke_type/2` prefer the declared default over a
    # stored one - a document that overrode the handler is ignored and
    # this goes red (verified).
    test "a stored invoke type wins over the declared default" do
      assert InvokeStep.invoke_type(%{"invoke_type" => "myapp:other"}, "myapp:receipt") ==
               "myapp:other"

      assert InvokeStep.invoke_type(%{}, "myapp:receipt") == "myapp:receipt"
    end
  end

  defp step(type_name, id, config), do: Block.new(type_name, id: id, config: config)

  defp palette do
    Palette.from_modules(
      [{"myapp.receipt", Receipt}, {"myapp.authorize", Authorize}],
      core: true
    )
  end

  defp compile!(root) do
    {:ok, compiled} = Compiler.compile(Document.new(root, id: "bdoc_T"), palette())
    compiled
  end

  defp send_to(root, event) do
    {:ok, machine} = Statifier.compile(compile!(root).scxml)
    {machine_state, _effects} = Statifier.initialize(machine)

    Statifier.send_event(machine_state, event)
  end

  defp active?(machine_state, state_id) do
    MapSet.member?(Statifier.active_leaf_states(machine_state), state_id)
  end
end
