defmodule StatifierBlocks.Compiler.TrailTest do
  @moduledoc """
  The trail of returnable steps in the chart's own datamodel (ADR-0004's
  Amendment of 2026-11-20): the trail root per scope, declared only where a
  returnable step is (`L1`), the push on entering a returnable step (`L2`),
  the rule that the trail holds state ids and never responses (`L7`), and
  no changed byte for a document with no returnable step (`L8`).

  The fixtures are test-only types for a library's patron registration.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, Document, Palette, Provenance}
  alias StatifierBlocks.Compiler.{Context, Trail}
  alias StatifierBlocks.Core.Emit
  alias StatifierBlocks.Emission

  doctest StatifierBlocks.Compiler.Trail

  defmodule Collect do
    @moduledoc """
    Collects one answer from a patron: waits for `step.submitted`, writes the
    event's data into the `responses` root, and completes. `step.again`
    re-enters the step's own state. Returnable unless its config says the
    patron may not come back to it.
    """
    use StatifierBlocks.BlockType

    @impl true
    def config_schema(_config) do
      [
        %{
          key: "revisable",
          type: :boolean,
          label: "The patron may come back to this",
          required?: false,
          default: true
        }
      ]
    end

    @impl true
    def returnable?(config), do: Map.get(config, "revisable", true) == true

    @impl true
    def emit(_block, context), do: {:ok, Collect.state(context)}

    @doc false
    def state(context, event \\ "step.submitted") do
      done = Context.done_id(context)
      {:ok, waiting} = Context.role_id(context, "waiting")

      submit =
        Emit.transition([event: event, target: done], [
          Emission.element("assign", [{"expr", "_event.data"}, {"location", "responses"}])
        ])

      again = Emit.transition(event: "step.again", target: context.state_id)

      Emit.state(context.state_id, waiting, [
        again,
        Emit.state(waiting, nil, [submit]),
        Emit.final(done)
      ])
    end
  end

  defmodule IssueCard do
    @moduledoc "Emits what `Collect` emits and declares nothing about returning."
    use StatifierBlocks.BlockType

    @impl true
    def config_schema(config), do: Collect.config_schema(config)

    @impl true
    def emit(_block, context), do: {:ok, Collect.state(context)}
  end

  defmodule Counted do
    @moduledoc """
    `Collect`, completed by the event its config names, and counting every
    entry into its state in the `visits` root, so a test can tell a step
    that was re-entered from one that was left alone.
    """
    use StatifierBlocks.BlockType

    @impl true
    def config_schema(config) do
      Collect.config_schema(config) ++
        [
          %{
            key: "event",
            type: :string,
            label: "The event that completes it",
            required?: false,
            default: "step.submitted"
          }
        ]
    end

    @impl true
    def returnable?(config), do: Collect.returnable?(config)

    @impl true
    def emit(%Block{config: config}, context) do
      %Emission{children: children} =
        state = Collect.state(context, Map.get(config, "event", "step.submitted"))

      visit =
        Emission.element("onentry", [], [
          Emission.element("assign", [{"expr", "visits + 1"}, {"location", "visits"}])
        ])

      {:ok, %{state | children: children ++ [visit]}}
    end
  end

  @sentinel "SENTINEL-library-card-7f3a"

  describe "the trail root (L1)" do
    # sabotage: made every block returnable in `collect/3` (`if true`) ->
    # the root block's trail appeared and this went red (verified)
    test "a document with no returnable step declares no trail root" do
      scxml = compile!(registration(revisable: false)).scxml

      refute scxml =~ "__trail"
      assert scxml =~ ~s(<datamodel><data id="responses"/></datamodel>)
    end

    # sabotage: changed `@suffix` to "__trails" -> red (verified)
    test "the document scope's root is declared once, empty, after the host roots" do
      scxml = compile!(registration()).scxml

      assert scxml =~
               ~s(<datamodel><data id="responses"/><data expr="[]" id="s_blk_ROOT__trail"/></datamodel>)

      assert length(String.split(scxml, ~s(id="s_blk_ROOT__trail"))) == 2
    end

    # sabotage: made the `core.foreach` arm of `child_scope/3` match no
    # slot -> the body's step pushed onto the document's trail and this
    # went red (verified)
    test "a foreach body is its own scope, and its enclosing scope declares nothing" do
      root =
        Block.new("core.sequence",
          id: "blk_ROOT",
          slots: %{
            "body" => [
              Block.new("core.foreach",
                id: "blk_F",
                config: %{"items" => "patrons", "item_as" => "patron"},
                slots: %{"body" => [Block.new("library.collect", id: "blk_NAME")]}
              )
            ]
          }
        )

      scxml = compile!(root, declare: [{"patrons", "[]"}, {"responses", nil}]).scxml

      refute scxml =~ "s_blk_ROOT__trail"
      assert scxml =~ ~s(<data expr="[]" id="s_blk_F__body__trail"/>)
      assert scxml =~ "s_blk_F__body__trail[0] !== 's_blk_NAME'"

      # host roots lead, the loop's own roots follow, then the body's trail
      [datamodel] = Regex.run(~r{<datamodel>.*</datamodel>}, scxml)
      ids = Regex.scan(~r{<data[^>]* id="([^"]+)"}, datamodel, capture: :all_but_first)

      assert List.flatten(ids) ==
               ["patrons", "responses", "s_blk_F__i", "s_blk_F__items", "patron"] ++
                 ["s_blk_F__body__trail"]
    end

    # sabotage: made the `core.parallel` arm of `child_scope/3` match no
    # slot -> both lanes pushed onto the document's trail and this went red
    # (verified)
    test "each parallel lane is its own scope" do
      root =
        Block.new("core.parallel",
          id: "blk_P",
          config: %{"lanes" => ["sender", "recipient"]},
          slots: %{
            "lane_sender" => [Block.new("library.collect", id: "blk_SEND")],
            "lane_recipient" => [Block.new("library.collect", id: "blk_RECV")]
          }
        )

      scxml = compile!(root).scxml

      refute scxml =~ "s_blk_P__trail"
      assert scxml =~ ~s(<data expr="[]" id="s_blk_P__lane_sender__trail"/>)
      assert scxml =~ ~s(<data expr="[]" id="s_blk_P__lane_recipient__trail"/>)
      assert scxml =~ "s_blk_P__lane_sender__trail[0] !== 's_blk_SEND'"
      assert scxml =~ "s_blk_P__lane_recipient__trail[0] !== 's_blk_RECV'"
    end
  end

  describe "the push on entry (L2)" do
    # sabotage: moved the push after the state's other children in
    # `place/2` -> it was no longer the state's first child and this went
    # red (verified)
    test "a returnable step's state opens with the push, first among its children" do
      scxml = compile!(registration()).scxml

      assert scxml =~
               ~s(<state id="s_blk_CARD" initial="s_blk_CARD__waiting"><onentry>) <>
                 ~s(<if cond="s_blk_ROOT__trail[0] !== 's_blk_CARD'">) <>
                 ~s(<assign expr="['s_blk_CARD', s_blk_ROOT__trail]" location="s_blk_ROOT__trail"/>) <>
                 ~s(</if></onentry>)
    end

    # sabotage: read `BlockType.returnable?/2` with an empty config in
    # `collect/3` -> blk_RULES, whose config says no, pushed too and this
    # went red (verified)
    test "a step whose type answers false for its config pushes nothing" do
      scxml = compile!(registration()).scxml

      refute scxml =~ "'s_blk_RULES'"
      assert scxml =~ ~s(<state id="s_blk_RULES" initial="s_blk_RULES__waiting"><transition)
    end

    # sabotage: put the `<assign>` straight in the `<onentry>`, dropping the
    # `<if>` guard -> `step.again`'s re-entry pushed blk_CARD a second time
    # and this went red (verified)
    test "the trail records each step once per visit, and a re-entry is not a visit" do
      state = start(registration())
      assert trail(state) == ["s_blk_NAME", []]

      state = deliver(state, "step.submitted", %{"name" => "Ada"})
      assert trail(state) == ["s_blk_CARD", ["s_blk_NAME", []]]

      state = deliver(state, "step.again")
      assert trail(state) == ["s_blk_CARD", ["s_blk_NAME", []]]

      state = deliver(state, "step.submitted", %{"card" => "new"})
      state = deliver(state, "step.submitted", %{"rules" => "agreed"})

      assert trail(state) == ["s_blk_PICKUP", ["s_blk_CARD", ["s_blk_NAME", []]]]
    end
  end

  describe "state ids only (L7)" do
    # sabotage: in `push/3`, pushed the step's responses in place of its
    # state id literal, `[responses, T]` -> the sentinel the patron
    # submitted entered the trail and the refute went red (verified)
    test "a sentinel response never enters the trail" do
      state = start(registration())
      state = deliver(state, "step.submitted", %{"name" => @sentinel})

      # the step did write the sentinel, so its absence below means something
      assert inspect(state.datamodel["responses"]) =~ @sentinel

      state = deliver(state, "step.submitted", %{"card" => @sentinel})
      state = deliver(state, "step.submitted", %{"rules" => @sentinel})

      trail = trail(state)

      refute inspect(trail) =~ @sentinel
      assert flatten(trail) == ["s_blk_PICKUP", "s_blk_CARD", "s_blk_NAME"]
    end
  end

  describe "no returnable step, no changed byte (L8)" do
    # sabotage: read `BlockType.returnable?/2` with an empty config in
    # `collect/3` -> the declared-false steps pushed, the two compiles
    # differed and this went red (verified)
    test "a type that answers false compiles as a type that never declared the callback" do
      declared_false = compile!(registration(revisable: false), palette())
      undeclared = compile!(registration(type: "library.issue"), palette())

      assert declared_false.scxml == undeclared.scxml
      assert declared_false.provenance == undeclared.provenance
    end

    # sabotage: made every block returnable in `collect/3` (`if true`) ->
    # `lay/2` rewrote the emission and this went red (verified)
    test "lay/2 hands back the emission it was given when no step is returnable" do
      emission = Emission.element("state", [{"id", "s_blk_ROOT"}])
      node = %{block: Block.new("core.sequence", id: "blk_ROOT"), module: IssueCard, slots: []}

      assert Trail.lay(emission, node) === emission
      assert Trail.scopes(node) == []
    end
  end

  describe "provenance (L9) and determinism" do
    # sabotage: owned the push by the step's state id instead of its block
    # id -> red (verified)
    test "a push belongs to its step and a trail root to the scope's block, both role :trail" do
      compiled = compile!(registration())

      {push, _length} = :binary.match(compiled.scxml, "['s_blk_CARD'")

      assert {:ok, %{block_id: "blk_CARD", role: ":trail", config_key: nil}} =
               Provenance.owner_at(compiled.provenance, push)

      {root, _length} = :binary.match(compiled.scxml, ~s(<data expr="[]"))

      assert {:ok, %{block_id: "blk_ROOT", role: ":trail", config_key: nil}} =
               Provenance.owner_at(compiled.provenance, root)
    end

    # sabotage: made every block returnable in `collect/3` (`if true`) ->
    # the root block joined the steps and this went red (verified)
    test "the scopes list their steps in document order" do
      root = registration()

      node_steps =
        Trail.scopes(%{
          block: root,
          module: StatifierBlocks.Core.Sequence,
          slots: [{"body", Enum.map(root.slots["body"], &resolved/1)}]
        })

      assert [%{state_id: "s_blk_ROOT", owner: "blk_ROOT", steps: steps}] = node_steps

      assert steps == [
               {"blk_NAME", "s_blk_NAME"},
               {"blk_CARD", "s_blk_CARD"},
               {"blk_PICKUP", "s_blk_PICKUP"}
             ]
    end
  end

  describe "the Back transitions (L3, L4)" do
    # sabotage: dropped `internal: true` from `scope_back/2` -> the scope
    # state's Back lost `type="internal"` and this went red (verified)
    test "the scope state carries one Back per step, after its own transitions" do
      scxml = compile!(registration()).scxml

      assert scxml =~
               ~s(<transition event="done.state.s_blk_PICKUP" target="s_blk_ROOT__o_done" type="internal"/>) <>
                 ~s(<transition cond="s_blk_ROOT__trail[0] === 's_blk_NAME'" event="statifier_blocks.back" ) <>
                 ~s(target="s_blk_NAME" type="internal">) <>
                 ~s(<assign expr="s_blk_ROOT__trail[1]" location="s_blk_ROOT__trail"/></transition>) <>
                 ~s(<transition cond="s_blk_ROOT__trail[0] === 's_blk_CARD'") <>
                 ~s( event="statifier_blocks.back" target="s_blk_CARD" type="internal">)
    end

    # sabotage: kept the step's own state in `others` in
    # `steps_additions/2` -> a self-targeting Back appeared on s_blk_CARD
    # and this went red (verified)
    test "a step's state carries Back to each other step, then the catch-all, after the push" do
      scxml = compile!(registration()).scxml

      back_to = fn step ->
        ~s(<transition cond="s_blk_ROOT__trail[1][0] === '#{step}'" event="statifier_blocks.back" ) <>
          ~s(target="#{step}"><assign expr="s_blk_ROOT__trail[1][1]" location="s_blk_ROOT__trail"/>) <>
          ~s(</transition>)
      end

      assert scxml =~
               ~s(</if></onentry>) <>
                 back_to.("s_blk_NAME") <>
                 back_to.("s_blk_PICKUP") <>
                 ~s(<transition event="statifier_blocks.back"/><transition event="step.again")

      refute scxml =~ "s_blk_ROOT__trail[1][0] === 's_blk_RULES'"
    end

    # sabotage: read the top, `T[0]`, in place of `T[1][0]` in
    # `step_back/3` -> Back at s_blk_CARD took the catch-all and this went
    # red (verified)
    test "Back at the second step re-enters the first and pops" do
      state = start(registration()) |> deliver("step.submitted")
      assert leaves(state) == ["s_blk_CARD__waiting"]

      state = deliver(state, "statifier_blocks.back")

      assert leaves(state) == ["s_blk_NAME__waiting"]
      assert trail(state) == ["s_blk_NAME", []]
    end

    # sabotage: removed the catch-all from `step_back/3` -> the event
    # reached the scope state, re-entered s_blk_NAME and the visit count
    # moved (verified)
    test "Back at the first step does nothing" do
      state = start(registration(type: "library.counted"), counted())
      assert visits(state) == 1

      state = deliver(state, "statifier_blocks.back")

      assert leaves(state) == ["s_blk_NAME__waiting"]
      assert trail(state) == ["s_blk_NAME", []]
      assert visits(state) == 1
    end

    # sabotage: emitted no scope-state Back (`put/4` of `:scope_back`
    # dropped) -> Back from the step that is not returnable took no
    # transition and this went red (verified)
    test "Back from a step that is not returnable re-enters the trail's top step" do
      state = start(registration())
      state = state |> deliver("step.submitted") |> deliver("step.submitted")
      assert leaves(state) == ["s_blk_RULES__waiting"]

      state = deliver(state, "statifier_blocks.back")

      assert leaves(state) == ["s_blk_CARD__waiting"]
      assert trail(state) == ["s_blk_CARD", ["s_blk_NAME", []]]
    end
  end

  describe "no transition on an empty trail (L5)" do
    # sabotage: dropped the `:finals` clear in `scope_additions/2` -> Back
    # re-entered s_blk_PICKUP in the finished document and this went red
    # (verified)
    test "Back sent to a finished document takes no transition" do
      state = start(registration())
      state = Enum.reduce(1..4, state, fn _step, state -> deliver(state, "step.submitted") end)

      assert leaves(state) == ["s_blk_ROOT__o_done"]
      assert trail(state) == []

      state = deliver(state, "statifier_blocks.back")

      assert leaves(state) == ["s_blk_ROOT__o_done"]
      assert trail(state) == []
    end

    # sabotage: made every block returnable in `collect/3` (`if true`) ->
    # the declared-false registration carried Back and this went red
    # (verified)
    test "a document with no returnable step has no Back transition" do
      refute compile!(registration(revisable: false)).scxml =~ "statifier_blocks.back"
    end

    # sabotage: dropped the one-step clause in `scope_additions/2` -> the
    # scope-state Back appeared on the root and this went red (verified)
    test "a root block that is the one returnable step offers no Back" do
      root = Block.new("library.counted", id: "blk_ROOT")
      scxml = compile!(root, counted()).scxml

      refute scxml =~ "s_blk_ROOT__trail[0] === "
      assert scxml =~ ~s(<transition event="statifier_blocks.back"/>)

      state = start(root, counted()) |> deliver("statifier_blocks.back")

      assert leaves(state) == ["s_blk_ROOT__waiting"]
      assert visits(state) == 1
    end
  end

  describe "the boundaries that clear the trail (L6)" do
    # sabotage: made the `core.foreach` arm of `child_scope/3` match no
    # slot -> the body's steps joined the document's trail and this went
    # red (verified)
    test "inside a loop body Back stays within the body and the iteration" do
      state = start(looping(), patrons("['ada', 'grace']"))
      state = deliver(state, "step.submitted")

      assert leaves(state) == ["s_blk_B1__waiting"]
      assert trail(state) == []
      assert body_trail(state) == ["s_blk_B1", []]

      # the body's first step: the step before the loop is not behind it
      state = deliver(state, "statifier_blocks.back")
      assert leaves(state) == ["s_blk_B1__waiting"]

      state = state |> deliver("step.submitted") |> deliver("statifier_blocks.back")
      assert leaves(state) == ["s_blk_B1__waiting"]
      assert body_trail(state) == ["s_blk_B1", []]

      # the second pass starts with nothing from the first behind it
      state = state |> deliver("step.submitted") |> deliver("step.submitted")
      assert leaves(state) == ["s_blk_B1__waiting"]
      assert body_trail(state) == ["s_blk_B1", []]

      state = state |> deliver("step.submitted") |> deliver("step.submitted")
      assert leaves(state) == ["s_blk_AFTER__waiting"]
    end

    # sabotage: dropped the boundary clears in `boundary_additions/2` ->
    # the step after the loop could go back to the step before it and
    # this went red (verified)
    test "a loop is a boundary for the scope it sits in" do
      state = start(looping(), patrons("[]"))
      state = deliver(state, "step.submitted")

      assert leaves(state) == ["s_blk_AFTER__waiting"]
      assert trail(state) == ["s_blk_AFTER", []]

      state = deliver(state, "statifier_blocks.back")
      assert leaves(state) == ["s_blk_AFTER__waiting"]
    end

    # sabotage: made the `core.parallel` arm of `child_scope/3` match no
    # slot -> both lanes shared the document's trail and this went red
    # (verified)
    test "inside a parallel lane Back stays within the lane" do
      state = start(lanes(), counted())
      refute Map.has_key?(state.datamodel, "s_blk_P__trail")
      assert state.datamodel["s_blk_P__lane_sender__trail"] == ["s_blk_SEND", []]
      assert visits(state) == 2

      state = deliver(state, "statifier_blocks.back")

      assert leaves(state) == ["s_blk_RECV__waiting", "s_blk_SEND__waiting"]
      assert visits(state) == 2
    end

    # sabotage: dropped the `:finals` clear in `scope_additions/2` -> the
    # finished lane's Back re-entered s_blk_SEND and this went red
    # (verified)
    test "a finished lane offers no Back while another lane runs" do
      state = start(lanes(), counted())
      state = deliver(state, "send.submitted")

      assert leaves(state) == ["s_blk_P__done_lane_sender", "s_blk_RECV__waiting"]
      assert state.datamodel["s_blk_P__lane_sender__trail"] == []

      state = deliver(state, "statifier_blocks.back")

      assert leaves(state) == ["s_blk_P__done_lane_sender", "s_blk_RECV__waiting"]
      assert visits(state) == 2
    end

    # sabotage: dropped the `:entry` clear of a body or lane in
    # `scope_additions/2` -> both clears were missing and this went red
    # (verified)
    test "a loop iteration and a parallel lane each clear their own trail on entry" do
      loop = compile!(looping(), patrons("[]")).scxml
      lanes = compile!(lanes(), counted()).scxml

      assert loop =~
               ~s(<state id="s_blk_F__body" initial="s_blk_B1"><onentry>) <>
                 ~s(<assign expr="[]" location="s_blk_F__body__trail"/></onentry>)

      assert lanes =~
               ~s(<state id="s_blk_P__lane_sender" initial="s_blk_SEND"><onentry>) <>
                 ~s(<assign expr="[]" location="s_blk_P__lane_sender__trail"/></onentry>)
    end

    # sabotage: left `core.subchart` out of `@boundaries` -> its clears
    # were missing and this went red (verified)
    test "a sub-path clears its scope's trail on entry and on exit" do
      scxml = compile!(sub_paths(), patrons("[]")).scxml
      clear = ~s(<assign expr="[]" location="s_blk_ROOT__trail"/>)

      assert scxml =~
               ~s(<state id="s_blk_SUB" initial="s_blk_SUB__running">) <>
                 ~s(<onentry>#{clear}</onentry><onexit>#{clear}</onexit>)

      assert scxml =~ ~r{<state id="s_blk_MAP" [^>]*><onentry>#{Regex.escape(clear)}}
      assert scxml =~ ~r{<state id="s_blk_MAP" .*?<onexit>#{Regex.escape(clear)}}s
    end

    # sabotage: attached every boundary of the document to each scope in
    # `finish/2` -> the loop, whose scope has no step, carried a clear and
    # this went red (verified)
    test "a boundary in a scope with no returnable step adds nothing" do
      scxml = compile!(looping(edges: false), patrons("[]")).scxml

      refute scxml =~ "s_blk_ROOT__trail"

      assert scxml =~
               ~s(<state id="s_blk_F" initial="s_blk_F__head"><onentry><assign expr="patrons")

      refute scxml =~ "<onexit>"
      assert scxml =~ ~s(<data expr="[]" id="s_blk_F__body__trail"/>)
    end
  end

  describe "provenance of Back and the clears (L9)" do
    # sabotage: owned the scope-state Back by the scope's block in
    # `scope_back/2` -> red (verified)
    test "Back belongs to its step, a clear to its boundary or its scope's block" do
      compiled = compile!(looping(), patrons("[]"))

      owner = fn needle ->
        {at, _length} = :binary.match(compiled.scxml, needle)
        {:ok, owner} = Provenance.owner_at(compiled.provenance, at)
        {owner.block_id, owner.role, owner.config_key}
      end

      assert owner.(~s(<transition cond="s_blk_F__body__trail[0] === 's_blk_B2')) ==
               {"blk_B2", ":trail", nil}

      assert owner.(~s(<transition cond="s_blk_F__body__trail[1][0] === 's_blk_B1')) ==
               {"blk_B2", ":trail", nil}

      assert owner.(~s(<transition event="statifier_blocks.back"/>)) ==
               {"blk_BEFORE", ":trail", nil}

      assert owner.(~s(<assign expr="[]" location="s_blk_ROOT__trail"/>)) ==
               {"blk_F", ":trail", nil}

      assert owner.(~s(<assign expr="[]" location="s_blk_F__body__trail"/>)) ==
               {"blk_F", ":trail", nil}
    end
  end

  # -- Fixtures ------------------------------------------------------------------

  # The registration: name, card and pickup are returnable; the rules step
  # is a collect whose config says the patron may not come back to it.
  defp registration(opts \\ []) do
    type = Keyword.get(opts, :type, "library.collect")
    revisable = Keyword.get(opts, :revisable, true)

    step = fn id, revisable? ->
      Block.new(type, id: id, config: %{"revisable" => revisable?})
    end

    Block.new("core.sequence",
      id: "blk_ROOT",
      slots: %{
        "body" => [
          step.("blk_NAME", revisable),
          step.("blk_CARD", revisable),
          step.("blk_RULES", false),
          step.("blk_PICKUP", revisable)
        ]
      }
    )
  end

  # A step before a loop over the patrons, two returnable steps in its
  # body, and a step after it; `edges: false` leaves the loop alone.
  defp looping(opts \\ []) do
    step = &Block.new("library.collect", id: &1)

    loop =
      Block.new("core.foreach",
        id: "blk_F",
        config: %{"items" => "patrons", "item_as" => "patron"},
        slots: %{"body" => [step.("blk_B1"), step.("blk_B2")]}
      )

    body =
      if Keyword.get(opts, :edges, true),
        do: [step.("blk_BEFORE"), loop, step.("blk_AFTER")],
        else: [loop]

    Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => body})
  end

  # Two lanes, each one counted returnable step completed by its own event.
  defp lanes do
    step = fn id, event ->
      Block.new("library.counted", id: id, config: %{"event" => event})
    end

    Block.new("core.parallel",
      id: "blk_P",
      config: %{"lanes" => ["sender", "recipient"]},
      slots: %{
        "lane_sender" => [step.("blk_SEND", "send.submitted")],
        "lane_recipient" => [step.("blk_RECV", "recv.submitted")]
      }
    )
  end

  # A returnable step, then a library card issued by a sub-path, then one
  # issued per patron by a map.
  defp sub_paths do
    Block.new("core.sequence",
      id: "blk_ROOT",
      slots: %{
        "body" => [
          Block.new("library.collect", id: "blk_NAME"),
          Block.new("core.subchart",
            id: "blk_SUB",
            config: %{"chart" => "library_card", "outcomes" => "done"}
          ),
          Block.new("core.map",
            id: "blk_MAP",
            config: %{
              "items" => "patrons",
              "chart" => "library_card",
              "item_as" => "patron",
              "index_as" => "position",
              "collect" => "cards",
              "on" => "all"
            }
          )
        ]
      }
    )
  end

  defp counted, do: [declare: [{"responses", nil}, {"visits", "0"}]]

  defp patrons(expr),
    do: [declare: [{"patrons", expr}, {"cards", nil}, {"responses", nil}]]

  defp resolved(%Block{type: type} = block) do
    module = Map.fetch!(palette().types, type)
    %{block: block, module: module, slots: []}
  end

  defp palette do
    Palette.new(
      Map.merge(Palette.core_types(), %{
        "library.collect" => Collect,
        "library.issue" => IssueCard,
        "library.counted" => Counted
      })
    )
  end

  defp compile!(root, opts \\ [])

  defp compile!(root, %Palette{} = palette) do
    {:ok, compiled} =
      Compiler.compile(Document.new(root, id: "bdoc_REG"), palette, declare: [{"responses", nil}])

    compiled
  end

  defp compile!(root, opts) do
    opts = Keyword.put_new(opts, :declare, [{"responses", nil}])
    {:ok, compiled} = Compiler.compile(Document.new(root, id: "bdoc_REG"), palette(), opts)
    compiled
  end

  defp start(root, opts \\ []) do
    {:ok, machine} = Statifier.compile(compile!(root, opts).scxml)
    {state, _effects} = Statifier.initialize(machine)
    state
  end

  defp deliver(state, event, data \\ :undefined) do
    {:ok, next, _effects} =
      Statifier.send_event(state, Statifier.Event.external(event, data: data))

    next
  end

  defp trail(state), do: state.datamodel["s_blk_ROOT__trail"]

  defp body_trail(state), do: state.datamodel["s_blk_F__body__trail"]

  defp visits(state), do: state.datamodel["visits"]

  defp leaves(state), do: state |> Statifier.active_leaf_states() |> Enum.sort()

  defp flatten([]), do: []
  defp flatten([top, below]), do: [top | flatten(below)]
end
