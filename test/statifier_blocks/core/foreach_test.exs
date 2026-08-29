defmodule StatifierBlocks.Core.ForeachTest do
  @moduledoc """
  What `core.foreach` means and what it compiles to: ADR-0004's
  2026-08-29 foreach amendment, F1 through F6.

  Two of the assertions here are the ones the upstream pin
  (statifier-ex `st-wlrx`) exists to keep honest, and they are asserted
  both as bytes and at runtime because either half alone would pass while
  the loop was broken:

    * the loop-back transition is `type="internal"`. An external
      transition whose target is inside its own source exits and re-enters
      that source, re-running the foreach state's `<onentry>` - so the
      list is re-snapshotted and the cursor reset on every pass, and the
      loop never ends.
    * termination is spelled `===`. Predicator's loose `==` against
      `undefined` evaluates to `:undefined` rather than to a boolean, and
      a `nil` item does not satisfy `===` - which is F5's narrowed limit,
      pinned by the null-item run below.

  The declaration mechanism the loop needs is
  `StatifierBlocks.Compiler.DeclaredRootsTest`'s; the shape assertions
  every core type shares live in `conformance_test.exs`. Nothing here
  repeats either.
  """

  use ExUnit.Case, async: true

  alias Statifier.Effect.DatamodelChange
  alias StatifierBlocks.{Block, Compiler, Document, Palette, Provenance}
  alias StatifierBlocks.Core.Foreach

  defmodule SignupStep do
    @moduledoc """
    `myapp.signup_step`: one screen of the signup wizard, waiting for the
    visitor to submit it.

    A body that finishes the instant it is entered would run the whole
    loop inside one macrostep and prove nothing about re-entry, so this
    stub waits for an external event exactly as a real screen does.
    """

    @behaviour StatifierBlocks.BlockType

    alias StatifierBlocks.Compiler.Context
    alias StatifierBlocks.Core.Emit

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config),
      do: [%{key: "event", type: :string, label: "Submitted by", required?: true, default: ""}]

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def io(_config), do: %{kinds: [:step]}

    @impl true
    def emit(%StatifierBlocks.Block{config: config}, context) do
      done = Context.done_id(context)
      {:ok, collecting} = Context.role_id(context, "collecting")

      waiting =
        Emit.state(collecting, nil, [
          Emit.transition(event: Map.get(config, "event", "step.submitted"), target: done)
        ])

      {:ok, Emit.state(context.state_id, collecting, [waiting, Emit.final(done)])}
    end
  end

  @wizard %{"items" => "steps", "item_as" => "step", "index_as" => "step_index"}

  describe "validate_config/1 (ADR-0002 decision 7)" do
    # sabotage: accepted any value for `items` -> a foreach over nothing
    # validates and this goes red (verified)
    test "items names one datamodel path" do
      assert Foreach.validate_config(@wizard) == :ok

      assert {:error, [{"items", message}]} =
               Foreach.validate_config(%{"item_as" => "step"})

      assert message =~ "datamodel path"

      assert {:error, [{"items", _m}]} =
               Foreach.validate_config(%{"items" => "signup invitees", "item_as" => "step"})
    end

    # sabotage: made `item_as` optional -> a loop with no binding at all
    # validates and this goes red on the second assertion (verified)
    test "item_as is required and index_as is optional, both bare identifiers" do
      assert Foreach.validate_config(%{"items" => "steps", "item_as" => "step"}) == :ok

      assert Foreach.validate_config(%{
               "items" => "steps",
               "item_as" => "step",
               "index_as" => ""
             }) == :ok

      assert {:error, [{"item_as", _required}]} = Foreach.validate_config(%{"items" => "steps"})

      assert {:error, [{"item_as", _shape}]} =
               Foreach.validate_config(%{"items" => "steps", "item_as" => "Step"})

      assert {:error, [{"index_as", _shape}]} =
               Foreach.validate_config(%{
                 "items" => "steps",
                 "item_as" => "step",
                 "index_as" => "Step Index"
               })
    end

    # sabotage: dropped the cross-field check -> both bindings compile to
    # two assignments to one root, the second wins, and this goes red
    # (verified)
    test "the item and its position cannot share one name" do
      assert {:error, [{"index_as", message}]} =
               Foreach.validate_config(%{
                 "items" => "steps",
                 "item_as" => "step",
                 "index_as" => "step"
               })

      assert message =~ "cannot share one name"
    end
  end

  describe "slots/1, io/1 and palette_entry/0" do
    # sabotage: declared a second slot -> a foreach with two bodies has no
    # single subgraph to iterate and this goes red (verified)
    test "one body slot, a step containing steps, and no declared type flow" do
      assert Foreach.slots(@wizard) == [{"body", :any, "For each item"}]

      assert Foreach.io(@wizard) == %{kinds: [:step], slot_accepts: %{"body" => [:step]}}

      entry = Foreach.palette_entry()
      assert entry.label == "For each"
      assert entry.slot_style == %{"body" => :primary}
    end
  end

  describe "emit/2 (F1-F5)" do
    setup do
      %{scxml: compile!(wizard()).scxml}
    end

    # sabotage: emitted the head state after the body state -> every
    # assertion below still passes and this one goes red on the first
    # differing byte, which is the whole reason it is here (verified)
    test "compiles to the plain Appendix D loop the amendment describes", %{scxml: scxml} do
      assert scxml =~
               ~s(<state id="s_blk_F" initial="s_blk_F__head">) <>
                 ~s(<onentry><assign expr="steps" location="s_blk_F__items"/>) <>
                 ~s(<assign expr="0" location="s_blk_F__i"/></onentry>) <>
                 ~s(<transition event="done.state.s_blk_F__body" target="s_blk_F__head" ) <>
                 ~s(type="internal"><assign expr="s_blk_F__i + 1" location="s_blk_F__i"/>) <>
                 ~s(</transition>) <>
                 ~s(<state id="s_blk_F__head">) <>
                 ~s(<onentry><assign expr="s_blk_F__items[s_blk_F__i]" location="step"/>) <>
                 ~s(<assign expr="s_blk_F__i" location="step_index"/></onentry>) <>
                 ~s(<transition cond="s_blk_F__items[s_blk_F__i] === undefined" ) <>
                 ~s(target="s_blk_F__o_done"/>) <>
                 ~s(<transition target="s_blk_F__body"/></state>) <>
                 ~s(<state id="s_blk_F__body" initial="s_blk_STEP">)
    end

    # THE FIRST HARD REQUIREMENT, as bytes. See the moduledoc.
    # sabotage: dropped `internal: true` from the loop-back transition ->
    # this goes red, and so does every runtime assertion below (verified)
    test "the loop-back transition is internal", %{scxml: scxml} do
      assert scxml =~
               ~s(<transition event="done.state.s_blk_F__body" target="s_blk_F__head" ) <>
                 ~s(type="internal">)
    end

    # THE SECOND HARD REQUIREMENT, as bytes.
    # sabotage: spelled the condition `==` -> the loop's termination test
    # evaluates to `:undefined` rather than to a boolean and this goes red
    # on the `refute` (verified)
    test "termination is the strict === against undefined, never the loose ==", %{scxml: scxml} do
      assert scxml =~ ~s(cond="s_blk_F__items[s_blk_F__i] === undefined")
      refute scxml =~ ~r/\[s_blk_F__i\] == undefined/
    end

    # sabotage: dropped the snapshot root from `roots/1` -> the loop
    # assigns a root nothing declared, predicator refuses to read it, and
    # this goes red on the declaration bytes (verified)
    test "declares the cursor, the snapshot and both bindings at the top", %{scxml: scxml} do
      assert scxml =~
               ~s(<datamodel><data expr="0" id="s_blk_F__i"/><data id="s_blk_F__items"/>) <>
                 ~s(<data id="step"/><data id="step_index"/></datamodel>)
    end

    # sabotage: emitted the index binding unconditionally -> a foreach
    # that names no position declares a root called "" and this goes red
    # (verified)
    test "a foreach that names no position emits no index root and no index binding" do
      scxml = compile!(wizard(index: false)).scxml

      assert scxml =~ ~s(<datamodel><data expr="0" id="s_blk_F__i"/><data id="s_blk_F__items"/>)
      assert scxml =~ ~s(<data id="step"/></datamodel>)
      refute scxml =~ "step_index"
    end
  end

  describe "the compiled loop, run over three items (F1, F4)" do
    setup do
      %{machine: machine!(wizard(), "['email', 'profile', 'plan']")}
    end

    # sabotage: dropped the cursor increment from the loop-back
    # transition -> every pass re-binds item 0 and this goes red on the
    # second pass (verified)
    test "binds the item and its position once per pass, and enters the body each time", %{
      machine: machine
    } do
      {pass1, effects} = Statifier.initialize(machine)

      assert written(effects, "s_blk_F__items") == ["email", "profile", "plan"]
      assert written(effects, "step") == "email"
      assert written(effects, "step_index") == 0
      assert leaves(pass1) == MapSet.new(["s_blk_STEP__collecting"])

      {pass2, effects2} = submit(pass1)

      assert written(effects2, "s_blk_F__i") == 1
      assert written(effects2, "step") == "profile"
      assert written(effects2, "step_index") == 1
      assert leaves(pass2) == MapSet.new(["s_blk_STEP__collecting"])

      {_pass3, effects3} = submit(pass2)

      assert written(effects3, "step") == "plan"
      assert written(effects3, "step_index") == 2

      # The snapshot is taken once: the loop state is entered exactly once,
      # so exactly one write to it lands across the whole run.
      assert written(effects2, "s_blk_F__items") == :none
      assert written(effects3, "s_blk_F__items") == :none
    end

    # THE FIRST HARD REQUIREMENT, at runtime: an external loop-back
    # re-enters `s_blk_F`, re-runs its onentry and resets the cursor to 0,
    # so the run never leaves the loop.
    # sabotage: dropped `internal: true` from the loop-back transition ->
    # the fourth submit finds the cursor back at 0 and this goes red
    # (verified)
    test "runs off the end of the list and leaves the loop", %{machine: machine} do
      {pass1, _effects} = Statifier.initialize(machine)
      {pass2, _effects} = submit(pass1)
      {pass3, _effects} = submit(pass2)
      {finished, effects} = submit(pass3)

      assert written(effects, "s_blk_F__i") == 3
      assert written(effects, "step") == :undefined
      assert leaves(finished) == MapSet.new(["s_blk_ROOT__o_done"])

      # The loop is over: another submit is inert.
      {again, _effects} = submit(finished)
      assert leaves(again) == MapSet.new(["s_blk_ROOT__o_done"])
    end

    # sabotage: bound the head from the source path rather than from the
    # snapshot -> the second pass reads the list the body just mutated,
    # runs off its end, and this goes red (verified)
    test "a body that writes the source list does not change the iteration" do
      machine = machine!(wizard(mutate: true), "['email', 'profile', 'plan']")

      {pass1, _effects} = Statifier.initialize(machine)
      {pass2, effects2} = submit(pass1)
      {pass3, effects3} = submit(pass2)

      assert written(effects2, "step") == "profile"
      assert written(effects3, "step") == "plan"
      assert pass3.datamodel["steps"] == ["mutated"]
      assert pass3.datamodel["s_blk_F__items"] == ["email", "profile", "plan"]
    end
  end

  # THE SECOND HARD REQUIREMENT, at runtime, and F5's narrowed limit: the
  # ruling's prose says a legitimate `undefined`/`null` item stops the loop
  # early, and in the resolved predicator it does not - `===` is strict, so
  # only the out-of-bounds read trips it.
  describe "the compiled loop, run over a list holding a null item (F5)" do
    # sabotage: spelled the termination condition `==` -> the cond is no
    # longer a boolean, the head takes neither arm cleanly, and this goes
    # red on the first pass (verified)
    test "a null item is iterated, not mistaken for the end of the list" do
      machine = machine!(wizard(), "['email', null, 'plan']")

      {pass1, effects} = Statifier.initialize(machine)
      assert written(effects, "step") == "email"

      {pass2, effects2} = submit(pass1)
      assert written(effects2, "step") == nil
      assert written(effects2, "step_index") == 1
      assert leaves(pass2) == MapSet.new(["s_blk_STEP__collecting"])

      {pass3, effects3} = submit(pass2)
      assert written(effects3, "step") == "plan"

      # Only the out-of-bounds read ends it.
      {finished, last} = submit(pass3)
      assert written(last, "step") == :undefined
      assert leaves(finished) == MapSet.new(["s_blk_ROOT__o_done"])
    end
  end

  describe "the :duplicate_binding refusal (F6)" do
    # sabotage: reported the finding against the root block rather than
    # the block that declared the colliding name -> the editor puts the
    # error on a loop the author did not touch and this goes red
    # (verified)
    test "a nested foreach re-using the outer loop's item name is refused" do
      assert {:error, findings} = compile(nested())
      assert [%{code: :duplicate_binding} = finding] = findings

      assert finding.stage == :emit
      assert finding.fault == :author
      assert finding.block_id == "blk_INNER"
      assert finding.config_key == "item_as"
      assert finding.reason == {:duplicate_binding, "blk_INNER", "step"}
      assert finding.message =~ "overwrite the enclosing one"
    end

    # sabotage: dropped the `config_key` from the finding -> the error
    # lands on the block as a whole rather than on the field the name was
    # typed into, and this goes red (verified)
    test "an index_as colliding with an enclosing binding is refused against index_as" do
      assert {:error, [finding]} =
               compile(nested(inner: %{"item_as" => "field", "index_as" => "step"}))

      assert finding.config_key == "index_as"
      assert finding.block_id == "blk_INNER"
    end

    # Sibling loops are NOT F6's case - neither is inside the other - and
    # they are refused all the same, one stage later and by the check
    # decision 9 delegates. The carve-out pre-empts that finding only
    # where the overwrite would otherwise be silent; see the moduledoc of
    # `StatifierBlocks.Core.Foreach`.
    # sabotage: keyed the collision scope on the whole document rather
    # than on the walk's ancestry -> the refusal arrives from the Emit
    # stage instead, and this goes red on the stage (verified)
    test "two sibling loops sharing a binding name are refused by the delegated check" do
      assert {:error, [finding]} = compile(siblings())

      assert finding.stage == :chart
      assert finding.code == :duplicate_id
      assert finding.fault == :author
      assert finding.block_id == "blk_G"
      assert finding.config_key == "item_as"
    end

    # sabotage: minted the cursor as a fixed name instead of through
    # `Context.role_id/2` -> two loops in one document collide on their
    # generated roots and this goes red (verified)
    test "the generated roots never collide, whatever the bindings do" do
      assert {:ok, compiled} = compile(siblings(distinct: true))

      # Each loop's roots are declared as a group, in the order the walk
      # meets the loops, so the two never interleave and never collide.
      assert compiled.scxml =~
               ~s(<datamodel><data expr="0" id="s_blk_F__i"/><data id="s_blk_F__items"/>) <>
                 ~s(<data id="step"/><data expr="0" id="s_blk_G__i"/>) <>
                 ~s(<data id="s_blk_G__items"/><data id="extra_step"/></datamodel>)
    end
  end

  describe "provenance (ADR-0004 decision 5)" do
    # sabotage: rebuilt the hoisted `<data>` elements at the top rather
    # than moving them -> the roots' bytes lose their owners and this goes
    # red (verified)
    test "every state and every declared root this block emits is owned" do
      compiled = compile!(wizard())

      for state_id <- [
            "s_blk_F",
            "s_blk_F__head",
            "s_blk_F__body",
            "s_blk_F__body_done",
            "s_blk_F__o_done"
          ] do
        assert {:ok, owner} = Provenance.owner_of_state(compiled.provenance, state_id)
        assert owner.block_id == "blk_F", state_id
      end

      # The author-named bindings carry the config field they were typed
      # into, which is what puts an upstream finding on the right field.
      assert {:ok, owner} = owner_at(compiled, ~s(<data id="step"/>))
      assert owner.block_id == "blk_F"
      assert owner.config_key == "item_as"
    end
  end

  # -- the documents ---------------------------------------------------------

  defp wizard(opts \\ []) do
    config =
      if Keyword.get(opts, :index, true),
        do: @wizard,
        else: Map.delete(@wizard, "index_as")

    body =
      if Keyword.get(opts, :mutate, false),
        do: [mutation(), step("blk_STEP")],
        else: [step("blk_STEP")]

    Block.new("core.sequence",
      id: "blk_ROOT",
      slots: %{
        "body" => [
          Block.new("core.foreach", id: "blk_F", config: config, slots: %{"body" => body})
        ]
      }
    )
  end

  # The inner loop collides with the outer one's `item_as` by default, and
  # with `index_as` instead when the caller says so.
  defp nested(opts \\ []) do
    inner_config =
      %{"items" => "step.fields", "item_as" => "step"}
      |> Map.merge(Keyword.get(opts, :inner, %{}))

    inner =
      Block.new("core.foreach",
        id: "blk_INNER",
        config: inner_config,
        slots: %{"body" => [step("blk_STEP")]}
      )

    Block.new("core.foreach",
      id: "blk_F",
      config: @wizard,
      slots: %{"body" => [inner]}
    )
  end

  defp siblings(opts \\ []) do
    second = if Keyword.get(opts, :distinct, false), do: "extra_step", else: "step"

    Block.new("core.sequence",
      id: "blk_ROOT",
      slots: %{
        "body" => [
          Block.new("core.foreach",
            id: "blk_F",
            config: %{"items" => "steps", "item_as" => "step"},
            slots: %{"body" => [step("blk_ONE")]}
          ),
          Block.new("core.foreach",
            id: "blk_G",
            config: %{"items" => "extra_steps", "item_as" => second},
            slots: %{"body" => [step("blk_TWO")]}
          )
        ]
      }
    )
  end

  defp step(id),
    do: Block.new("myapp.signup_step", id: id, config: %{"event" => "step.submitted"})

  defp mutation,
    do:
      Block.new("core.assign",
        id: "blk_MUT",
        config: %{"path" => "steps", "value" => "['mutated']"}
      )

  # -- the plumbing ----------------------------------------------------------

  defp palette,
    do: Palette.new(Map.merge(Palette.core_types(), %{"myapp.signup_step" => SignupStep}))

  defp compile(root), do: Compiler.compile(Document.new(root, id: "bdoc_LOOP"), palette())

  defp compile!(root) do
    {:ok, compiled} = compile(root)
    compiled
  end

  # The source list is the **host's** root, and this package has no
  # author-facing `<data>` declaration yet - so the test declares it the
  # way a host would, by merging into the `<datamodel>` the compiler now
  # emits. That the merge is one string replacement is the point: the
  # element exists, and a host has somewhere to put its own roots.
  defp machine!(root, source_list) do
    scxml =
      root
      |> compile!()
      |> Map.fetch!(:scxml)
      |> String.replace("<datamodel>", ~s(<datamodel><data expr="#{source_list}" id="steps"/>))

    {:ok, machine} = Statifier.compile(scxml)
    machine
  end

  defp submit(machine_state) do
    {:ok, next, effects} =
      Statifier.send_event(machine_state, Statifier.Event.external("step.submitted"))

    {next, effects}
  end

  defp leaves(machine_state), do: Statifier.active_leaf_states(machine_state)

  defp changes(effects) do
    for {:datamodel_change, %DatamodelChange{} = payload} <- effects, do: payload
  end

  # The value written to `location` by this batch of effects, or `:none`.
  defp written(effects, location) do
    case Enum.filter(changes(effects), &(&1.location_source == location)) do
      [] -> :none
      list -> List.last(list).new_value
    end
  end

  defp owner_at(compiled, needle) do
    {offset, _length} = :binary.match(compiled.scxml, needle)
    Provenance.owner_at(compiled.provenance, offset + 1)
  end
end
