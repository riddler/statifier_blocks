defmodule StatifierBlocks.Composite.DeclaredOutcomesTest do
  @moduledoc """
  A composite declares its own outcomes (ADR-0002's Amendment of 2026-09-12,
  `C1`-`C5`): the optional `outcomes` key on both declaration forms, the label
  the declared name borrows from the member that raises it, the Resolve-stage
  finding for a name the expansion cannot raise, and the compiled bytes of a
  document that writes no key.

  The fixtures are the signup wizard's: a confirmation step that waits for an
  event, which is the smallest composite whose expansion can raise a name its
  expansion **root** cannot. The root is a `core.sequence`, which declares the
  default `done` and nothing else; the `core.await` below it declares
  `received` and `timed_out`, and before this section there was no way for the
  step to say that either of them is how it finished.

  A pure test. Nothing here names LiveView, so it compiles and runs headless.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.Compiler.Finding

  alias StatifierBlocks.{
    Block,
    Compiler,
    Composite,
    Document,
    Palette
  }

  # -- the two module composites -----------------------------------------

  # -- the subtree the three module composites share ----------------------

  defmodule ConfirmSubtree do
    @moduledoc """
    One subtree, so that the three declarations below differ in the
    `outcomes` key and in nothing else - which is what makes the byte
    comparison and the replace-not-merge comparison read as the key's doing.
    """

    alias StatifierBlocks.Block

    @doc "A sequence over an await on the confirmation event."
    @spec build(map()) :: [Block.t()]
    def build(params) do
      [
        Block.new("core.sequence",
          id: "body",
          slots: %{
            "body" => [
              Block.new("core.await",
                id: "wait",
                config: %{"event" => params["event"], "timeout" => "10m"}
              )
            ]
          }
        )
      ]
    end
  end

  defmodule ConfirmStep do
    @moduledoc """
    The `C3` case: the same subtree, declaring no `outcomes` key. It answers
    its expansion root's list, which is the `core.sequence` default, exactly
    as every composite written before this section does.
    """

    use StatifierBlocks.Composite,
      name: "signup.confirm_step",
      params: [
        %{key: "event", type: :string, label: "Confirmed by", required?: true, default: ""}
      ],
      palette_entry: %{label: "Confirm the contact"},
      version: 1

    alias StatifierBlocks.Composite.DeclaredOutcomesTest.ConfirmSubtree

    @impl StatifierBlocks.Composite
    def subtree(params), do: ConfirmSubtree.build(params)
  end

  defmodule ConfirmStepEmpty do
    @moduledoc """
    `C1`'s explicit empty list: byte for byte `ConfirmStep`'s declaration with
    `outcomes: []` written out. `C1` says the explicit list is deliberately the
    same as the absent key, so this module and `ConfirmStep` must answer the
    same derived list.
    """

    use StatifierBlocks.Composite,
      name: "signup.confirm_step_empty",
      params: [
        %{key: "event", type: :string, label: "Confirmed by", required?: true, default: ""}
      ],
      outcomes: [],
      palette_entry: %{label: "Confirm the contact"},
      version: 1

    alias StatifierBlocks.Composite.DeclaredOutcomesTest.ConfirmSubtree

    @impl StatifierBlocks.Composite
    def subtree(params), do: ConfirmSubtree.build(params)
  end

  defmodule ConfirmStepDeclaring do
    @moduledoc """
    The `C1`/`C2` case: byte for byte the subtree above, plus the two names the
    `core.await` below the root raises. The root's `done` is **not** in the
    list, which is what "replaces, not merges" buys - a composite that has said
    how it finishes can remove an outcome as well as add one.
    """

    use StatifierBlocks.Composite,
      name: "signup.confirm_step_declaring",
      params: [
        %{key: "event", type: :string, label: "Confirmed by", required?: true, default: ""}
      ],
      outcomes: ["timed_out", "received"],
      palette_entry: %{label: "Confirm the contact"},
      version: 1

    alias StatifierBlocks.Composite.DeclaredOutcomesTest.ConfirmSubtree

    @impl StatifierBlocks.Composite
    def subtree(params), do: ConfirmSubtree.build(params)
  end

  defmodule ConfirmStepDreaming do
    @moduledoc """
    A declaration naming an outcome nothing in its expansion raises. `C2`
    item 3: a Resolve finding against the composite block, never a raise.
    """

    use StatifierBlocks.Composite,
      name: "signup.confirm_step_dreaming",
      params: [
        %{key: "event", type: :string, label: "Confirmed by", required?: true, default: ""}
      ],
      outcomes: ["received", "went_back"],
      palette_entry: %{label: "Confirm the contact"},
      version: 1

    alias StatifierBlocks.Composite.DeclaredOutcomesTest.ConfirmSubtree

    @impl StatifierBlocks.Composite
    def subtree(params), do: ConfirmSubtree.build(params)
  end

  defmodule ConfirmAndRecord do
    @moduledoc """
    `C2` item 2's compositional case: a composite whose member is itself a
    composite. `timed_out` is raisable here only because the member declares
    it under this same section - the member's own expansion root raises
    `done` and nothing else.
    """

    use StatifierBlocks.Composite,
      name: "signup.confirm_and_record",
      params: [
        %{key: "event", type: :string, label: "Confirmed by", required?: true, default: ""}
      ],
      outcomes: ["timed_out"],
      palette_entry: %{label: "Confirm and record"},
      version: 1

    alias StatifierBlocks.Block

    @impl StatifierBlocks.Composite
    def subtree(params) do
      [
        Block.new("core.sequence",
          id: "body",
          slots: %{
            "body" => [
              Block.new("signup.confirm_step_declaring",
                id: "step",
                config: %{"event" => params["event"]}
              )
            ]
          }
        )
      ]
    end
  end

  defmodule ReceivesFirst do
    @moduledoc "A host leaf that raises `received`, labelled its own way."

    @behaviour StatifierBlocks.BlockType

    alias StatifierBlocks.Block

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
    def outcomes(_config), do: [{"received", "Received first"}]
    @impl true
    def palette_entry, do: %{label: "Receives first"}
    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule ReceivesSecond do
    @moduledoc "The same outcome name, a different label, later in the walk."

    @behaviour StatifierBlocks.BlockType

    alias StatifierBlocks.Block

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
    def outcomes(_config), do: [{"received", "Received second"}]
    @impl true
    def palette_entry, do: %{label: "Receives second"}
    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule ConfirmStepTwice do
    @moduledoc """
    Two members raising one name. `C1`: the label is the first such member's in
    the expansion's own order.
    """

    use StatifierBlocks.Composite,
      name: "signup.confirm_step_twice",
      params: [
        %{key: "event", type: :string, label: "Confirmed by", required?: true, default: ""}
      ],
      outcomes: ["received"],
      palette_entry: %{label: "Confirm the contact"},
      version: 1

    alias StatifierBlocks.Block

    @impl StatifierBlocks.Composite
    def subtree(_params) do
      [
        Block.new("core.sequence",
          id: "body",
          slots: %{
            "body" => [
              Block.new("signup.receives_first", id: "first"),
              Block.new("signup.receives_second", id: "second")
            ]
          }
        )
      ]
    end
  end

  defmodule ConfirmStepMaybe do
    @moduledoc """
    `C2` item 4: a subtree that is not the same shape for every config. The
    await is there only when the step is declared interruptible, so
    `timed_out` is raisable on one document and not on the next with the same
    module untouched.
    """

    use StatifierBlocks.Composite,
      name: "signup.confirm_step_maybe",
      params: [
        %{key: "event", type: :string, label: "Confirmed by", required?: true, default: ""},
        %{
          key: "interruptible",
          type: :boolean,
          label: "Interruptible",
          required?: false,
          default: false
        }
      ],
      outcomes: ["timed_out"],
      palette_entry: %{label: "Confirm the contact"},
      version: 1

    alias StatifierBlocks.Block
    alias StatifierBlocks.Composite.DeclaredOutcomesTest.ConfirmSubtree

    @impl StatifierBlocks.Composite
    def subtree(params) do
      if params["interruptible"] do
        ConfirmSubtree.build(params)
      else
        [Block.new("core.sequence", id: "body", slots: %{"body" => []})]
      end
    end
  end

  defmodule ConfirmStepOpen do
    @moduledoc """
    `C2` item 2's other half: a composite that exposes a pass-through slot and
    declares a name only the AUTHOR's filling could raise. Its own subtree is a
    bare `core.sequence`, which raises `done` and nothing else.
    """

    use StatifierBlocks.Composite,
      name: "signup.confirm_step_open",
      params: [
        %{key: "event", type: :string, label: "Confirmed by", required?: true, default: ""}
      ],
      slots: [%{name: "body", to: {"body", "body"}, label: "Then"}],
      outcomes: ["received"],
      palette_entry: %{label: "Confirm the contact"},
      version: 1

    alias StatifierBlocks.Block

    @impl StatifierBlocks.Composite
    def subtree(_params), do: [Block.new("core.sequence", id: "body", slots: %{"body" => []})]
  end

  defmodule AwaitsWithSlot do
    @moduledoc """
    A well-formed member for the item 4 fixtures below: it declares the two
    names its own `core.await` raises - so it draws no finding of its own -
    and it exposes a pass-through slot, so the composite that mints it can
    mint a child into it. Its declaration removes the root's `done`, which is
    what leaves `done` with no resolvable raiser in the expansion below.
    """

    use StatifierBlocks.Composite,
      name: "signup.awaits_with_slot",
      params: [
        %{key: "event", type: :string, label: "Confirmed by", required?: true, default: ""}
      ],
      slots: [%{name: "body", to: {"then", "body"}, label: "Then"}],
      outcomes: ["received", "timed_out"],
      palette_entry: %{label: "Await, then"},
      version: 1

    alias StatifierBlocks.Block

    @impl StatifierBlocks.Composite
    def subtree(params) do
      [
        Block.new("core.sequence",
          id: "body",
          slots: %{
            "body" => [
              Block.new("core.await",
                id: "wait",
                config: %{"event" => params["event"], "timeout" => "10m"}
              ),
              Block.new("core.group", id: "then", slots: %{"body" => []})
            ]
          }
        )
      ]
    end
  end

  defmodule ConfirmStepGhost do
    @moduledoc """
    The Note of 2026-09-13's item 4: a composite one of whose MINTED members
    carries a type the palette does not carry. The expansion root declares
    `received` and `timed_out` and so raises no `done` of its own; the only
    member that could supply `done` is the ghost, and the palette cannot
    resolve it. The declaration names `done`, so the rule is observable twice
    - in the raisable set, and in the Resolve finding the declaration draws.
    """

    use StatifierBlocks.Composite,
      name: "signup.confirm_step_ghost",
      params: [
        %{key: "event", type: :string, label: "Confirmed by", required?: true, default: ""}
      ],
      outcomes: ["done"],
      palette_entry: %{label: "Confirm the contact"},
      version: 1

    alias StatifierBlocks.Block

    @impl StatifierBlocks.Composite
    def subtree(params) do
      [
        Block.new("signup.awaits_with_slot",
          id: "step",
          config: %{"event" => params["event"]},
          slots: %{"body" => [Block.new("signup.not_in_this_palette", id: "ghost")]}
        )
      ]
    end
  end

  defmodule ConfirmStepGhostQuiet do
    @moduledoc """
    The same subtree declaring no `outcomes` key: the case that shows the rule
    adds no signal of its own. The unresolvable member is the palette's and
    the compiler's business, and the finding it already draws is the only one.
    """

    use StatifierBlocks.Composite,
      name: "signup.confirm_step_ghost_quiet",
      params: [
        %{key: "event", type: :string, label: "Confirmed by", required?: true, default: ""}
      ],
      palette_entry: %{label: "Confirm the contact"},
      version: 1

    alias StatifierBlocks.Composite.DeclaredOutcomesTest.ConfirmStepGhost

    @impl StatifierBlocks.Composite
    def subtree(params), do: ConfirmStepGhost.subtree(params)
  end

  defmodule ScreenWithBackButton do
    @moduledoc """
    The `C8` case, and the sibling of the `k2` fixture above: a composite
    whose expansion is a `core.group` with an `interrupts` rail, and whose
    declared outcome is raised by nothing but the handler on that rail.

    This is the signup wizard's screen in miniature - a step the visitor
    waits on, and a Back button that abandons it. Before `C8` the handler
    answered `A1`'s default `done`, so `went_back` was raisable by nothing
    in the expansion and `C2` item 3 refused the declaration.
    """

    use StatifierBlocks.Composite,
      name: "signup.screen_with_back",
      params: [
        %{key: "event", type: :string, label: "Confirmed by", required?: true, default: ""}
      ],
      outcomes: ["went_back"],
      palette_entry: %{label: "A screen with a Back button"},
      version: 1

    alias StatifierBlocks.Block

    @impl StatifierBlocks.Composite
    def subtree(params) do
      [
        Block.new("core.group",
          id: "body",
          slots: %{
            "body" => [
              Block.new("core.await",
                id: "wait",
                config: %{"event" => params["event"], "timeout" => "10m"}
              )
            ],
            "interrupts" => [
              Block.new("core.on_event",
                id: "back",
                config: %{
                  "event" => "signup.back_pressed",
                  "outcome" => "abandon",
                  "finish_as" => "went_back"
                }
              )
            ]
          }
        )
      ]
    end
  end

  # -- C8: a handler's named outcome is what the composite declares -------

  describe "C8: an interrupt handler names the outcome it abandons its group with" do
    # The routing proof `C8` item 8 asks for, and the third half of the gap
    # `C6` and `C7` close the other two of. The declared name is raisable by
    # exactly one thing in this expansion - the `core.on_event` on the
    # group's `interrupts` rail - so `C2` item 3's refusal is what this
    # compile would draw without the handler's `finish_as`, and the
    # unnamed sibling below pins that.
    #
    # Sabotage: had `finish_id/2` answer `Context.done_id/1` for a named
    # handler - red, and the compile refuses with `:outcome_not_raisable`
    # before the assertions, which is the walk's own measurement.
    test "a declared name a named handler raises draws no finding" do
      assert {:ok, compiled} =
               Compiler.compile(with_back_slot_child(), palette(), child_use: true)

      # The handler's own final carries the name, which is `C8` item 3.
      assert compiled.scxml =~
               ~s(<final id="s_blk_CS_back__o_went_back"><onentry>) <>
                 ~s(<raise event="done.outcome.s_blk_CS_back.went_back"/></onentry></final>)

      # And the group is abandoned first, on the watcher's own transition,
      # which `C8` item 3 keeps unchanged.
      assert compiled.scxml =~
               ~s(<transition event="signup.back_pressed" target="s_blk_CS_back__o_went_back">) <>
                 ~s(<raise event="statifier_blocks.interrupt.abandon.s_blk_CS_body"/></transition>)
    end

    # `C7` item 3's occupied arm over a handler-raised name: the routing
    # transition reaches the slot child, the child's completion reaches the
    # composite's final, and the composite raises its own outcome for the
    # enclosing body. These are the three bytes the record's measurement
    # prints.
    #
    # Sabotage: had `finish_id/2` answer `Context.done_id/1` for a named
    # handler - red, the compile refusing with `:outcome_not_raisable`
    # before the assertions.
    test "an occupied on_<name> slot runs its child before the composite's final" do
      assert {:ok, compiled} =
               Compiler.compile(with_back_slot_child(), palette(), child_use: true)

      # The event that route selects on is one the handler actually raises,
      # which is the byte `C8` item 3 adds and what makes the route live
      # rather than dead.
      assert compiled.scxml =~
               ~s(<final id="s_blk_CS_back__o_went_back"><onentry>) <>
                 ~s(<raise event="done.outcome.s_blk_CS_back.went_back"/></onentry></final>)

      # In, from the handler that raised the declared name.
      assert compiled.scxml =~
               ~s(<transition event="done.outcome.s_blk_CS_back.went_back" ) <>
                 ~s(target="s_blk_GOBACK" type="internal"/>)

      # Out, from the child to the composite's own final for that name.
      assert compiled.scxml =~
               ~s(<transition event="done.state.s_blk_GOBACK" ) <>
                 ~s(target="s_blk_CS__o_went_back" type="internal"/>)

      # And the composite finishes as the name, which is what the enclosing
      # body routes on.
      assert compiled.scxml =~
               ~s(<final id="s_blk_CS__o_went_back"><onentry>) <>
                 ~s(<raise event="done.outcome.s_blk_CS.went_back"/></onentry></final>)

      assert compiled.scxml =~ ~s(event="done.state.s_blk_CS" target="s_blk_ROOT__o_done")
    end

    # `C7` item 3's empty arm over the same name: with no child in the
    # derived slot the handler's completion reaches the composite's final
    # directly, and the slot child's two transitions are simply absent.
    #
    # Sabotage: had `finish_id/2` answer `Context.done_id/1` for a named
    # handler - red, the compile refusing with `:outcome_not_raisable`.
    test "an empty on_<name> slot reaches the composite final directly" do
      assert {:ok, compiled} =
               Compiler.compile(document("signup.screen_with_back"), palette(), child_use: true)

      assert compiled.scxml =~
               ~s(<final id="s_blk_CS_back__o_went_back"><onentry>) <>
                 ~s(<raise event="done.outcome.s_blk_CS_back.went_back"/></onentry></final>)

      assert compiled.scxml =~
               ~s(<transition event="done.outcome.s_blk_CS_back.went_back" ) <>
                 ~s(target="s_blk_CS__o_went_back" type="internal"/>)

      refute compiled.scxml =~ "s_blk_GOBACK"

      assert compiled.scxml =~
               ~s(<final id="s_blk_CS__o_went_back"><onentry>) <>
                 ~s(<raise event="done.outcome.s_blk_CS.went_back"/></onentry></final>)
    end

    # The negative half, and the measurement `C8` records: the same
    # composite whose handler carries no name is exactly the refusal the
    # walk measured, because the handler then answers `A1`'s default and
    # the declared name is raisable by nothing. This is what makes the
    # three tests above the key's doing rather than the fixture's.
    #
    # Sabotage: had `outcomes/1`'s blank arm answer `[{"went_back",
    # "went_back"}]` - red: the unnamed handler then makes the name raisable
    # and the refusal this pins disappears.
    test "the same composite whose handler is unnamed is refused, as it was before" do
      assert {:error, findings} =
               Compiler.compile(document("signup.screen_with_back_unnamed"), palette(),
                 child_use: true
               )

      assert [%Finding{} = finding] =
               Enum.filter(
                 findings,
                 &(&1.reason == {:outcome_not_raisable, "blk_CS", "went_back"})
               )

      assert finding.stage == :resolve
      assert finding.severity == :error
      assert finding.block_id == "blk_CS"
    end

    # `C6` item 5 and `C7` item 4's totality claim over the bytes this
    # request adds: the handler's own final moved to a new id, so the
    # provenance map has to answer for that id too. It reads the ids out of
    # the emitted chart rather than listing them, so a state this request
    # forgot to stamp fails it.
    #
    # Sabotage: had `finish_id/2` answer `Context.done_id/1` for a named
    # handler - red on the first assertion, the handler's named final having
    # no id in the chart to stamp.
    test "provenance stays total over the bytes a named handler adds" do
      assert {:ok, compiled} =
               Compiler.compile(with_back_slot_child(), palette(), child_use: true)

      emitted =
        ~r/ id="(s_[^"]+)"/
        |> Regex.scan(compiled.scxml)
        |> Enum.map(fn [_whole, id] -> id end)

      assert "s_blk_CS_back__o_went_back" in emitted
      assert "s_blk_CS__o_went_back" in emitted

      assert Enum.all?(emitted, &Map.has_key?(compiled.provenance.by_state_id, &1)),
             "unstamped: #{inspect(emitted -- Map.keys(compiled.provenance.by_state_id))}"

      # The handler's final is the handler block's, not the composite's.
      assert compiled.provenance.by_state_id["s_blk_CS_back__o_went_back"].block_id ==
               "blk_CS_back"

      assert compiled.provenance.by_state_id["s_blk_CS__o_went_back"].block_id == "blk_CS"
    end
  end

  defmodule ScreenWithBackButtonUnnamed do
    @moduledoc """
    Byte for byte the module above with the handler's `finish_as` left out,
    which is the state of the world the walk measured: the handler answers
    `A1`'s default `done`, nothing in the expansion raises `went_back`, and
    `C2` item 3 refuses the declaration.
    """

    use StatifierBlocks.Composite,
      name: "signup.screen_with_back_unnamed",
      params: [
        %{key: "event", type: :string, label: "Confirmed by", required?: true, default: ""}
      ],
      outcomes: ["went_back"],
      palette_entry: %{label: "A screen with a Back button"},
      version: 1

    alias StatifierBlocks.Block
    alias StatifierBlocks.Composite.DeclaredOutcomesTest.ScreenWithBackButton

    @impl StatifierBlocks.Composite
    def subtree(params) do
      [group] = ScreenWithBackButton.subtree(params)
      [handler] = group.slots["interrupts"]

      [
        %{
          group
          | slots: %{
              group.slots
              | "interrupts" => [%{handler | config: Map.delete(handler.config, "finish_as")}]
            }
        }
      ]
    end
  end

  # -- helpers -----------------------------------------------------------

  defp palette do
    Palette.new(
      Map.merge(Palette.core_types(), %{
        "signup.confirm_step" => ConfirmStep,
        "signup.confirm_step_empty" => ConfirmStepEmpty,
        "signup.confirm_step_declaring" => ConfirmStepDeclaring,
        "signup.confirm_step_dreaming" => ConfirmStepDreaming,
        "signup.confirm_and_record" => ConfirmAndRecord,
        "signup.confirm_step_open" => ConfirmStepOpen,
        "signup.confirm_step_maybe" => ConfirmStepMaybe,
        "signup.confirm_step_twice" => ConfirmStepTwice,
        "signup.receives_first" => ReceivesFirst,
        "signup.receives_second" => ReceivesSecond,
        "signup.awaits_with_slot" => AwaitsWithSlot,
        "signup.confirm_step_ghost" => ConfirmStepGhost,
        "signup.confirm_step_ghost_quiet" => ConfirmStepGhostQuiet,
        "signup.screen_with_back" => ScreenWithBackButton,
        "signup.screen_with_back_unnamed" => ScreenWithBackButtonUnnamed
      })
    )
  end

  defp block(type, id \\ "blk_CS"),
    do: Block.new(type, id: id, config: %{"event" => "signup.confirmed"})

  defp document(type, id \\ "blk_CS"),
    do:
      Document.new(
        Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [block(type, id)]}),
        id: "bdoc_declaredoutcomes"
      )

  # -- C1 and C2: the declared list, and the labels it borrows ------------

  describe "C1: the declaration takes an optional list of outcome names" do
    # Sabotage: dropped `:outcomes` from `@declaration_options` - red, because
    # the option is then refused by name at the use site.
    test "the key rides in the declaration beside the six it joins" do
      assert ConfirmStepDeclaring.__composite__().outcomes == ["timed_out", "received"]
    end

    # Sabotage: defaulted the key to `nil` rather than `[]` - red. `C1` says
    # absent is the empty list, and `C3` reads the empty list as "not declared".
    test "absent, it is the empty list" do
      assert ConfirmStep.__composite__().outcomes == []
    end

    # Sabotage: accepted a list of `{name, label}` pairs too - red. `C1` is
    # explicit that this key adds no second way to spell a label.
    test "a list of anything but non-empty name strings is refused at the use site" do
      assert_raise ArgumentError, ~r/:outcomes must be a list of non-empty outcome name/, fn ->
        Composite.__declaration__(
          name: "signup.x",
          params: [],
          outcomes: [{"timed_out", "Timed out"}]
        )
      end
    end

    # Sabotage: dropped the duplicate check - red. A name declared twice would
    # answer twice from `outcomes/1`, and an outcome is one slot.
    test "a name declared twice is refused" do
      assert_raise ArgumentError, ~r/declares \["received"\] more than once/, fn ->
        Composite.__declaration__(
          name: "signup.x",
          params: [],
          outcomes: ["received", "received"]
        )
      end
    end
  end

  describe "C2: present, the declared list replaces the derived one" do
    # Sabotage: merged the root's list into the declared one - red. The root is
    # a `core.sequence`, so `done` would come back and the declaration could
    # never remove an outcome, which is half of what it is for.
    test "outcomes/1 answers the declared names and not the expansion root's" do
      assert ConfirmStep.outcomes(%{"event" => "signup.confirmed"}) == [{"done", "Done"}]

      assert ConfirmStepDeclaring.outcomes(%{"event" => "signup.confirmed"}) == [
               {"timed_out", "Timed out"},
               {"received", "Received"}
             ]
    end

    # Sabotage: sorted the answer - red. `C1` says the names come back in the
    # order the composite declares them, and ADR-0004 decision 6's byte
    # determinism reads that order.
    test "the declared order is the answered order" do
      assert ConfirmStepDeclaring.outcomes(%{})
             |> Enum.map(&elem(&1, 0)) == ["timed_out", "received"]
    end

    # Sabotage: labelled a declared name with the name itself - red. `C1`'s
    # label rule is that the label is the one the RAISING member already wrote,
    # and `core.await` writes "Timed out" for `timed_out`.
    test "a declared name takes the label the member that raises it declares" do
      assert Composite.outcomes(palette(), block("signup.confirm_step_declaring")) == [
               {"timed_out", "Timed out"},
               {"received", "Received"}
             ]
    end

    # Sabotage: read the root's outcomes rather than the union over every
    # minted member - red. `timed_out` is raised by the `core.await` two levels
    # below the root, and the root cannot raise it at all.
    #
    # `sb-51lv`: one expansion, destructured once. Calling `expansion/1` twice
    # paired the members of one expansion with the `param_map` of a second,
    # which is exactly the pairing `unraisable_outcomes/4`'s doc forbids a
    # caller to make - true here only because `expand!/2` is deterministic.
    test "the raisable set is the union over the expansion, not the root alone" do
      {members, param_map} = expansion(ConfirmStepDeclaring)

      assert Composite.unraisable_outcomes(palette(), ConfirmStepDeclaring, members, param_map) ==
               []
    end

    # Sabotage: reduced with `Map.put/3` rather than `Map.put_new/3` - red. `C1`
    # says a name raised by more than one member takes the label of the FIRST
    # such member in the expansion's own order, which is the pre-order walk
    # `flatten/1` already defines.
    test "a name two members raise takes the first member's label" do
      block = block("signup.confirm_step_twice", "blk_TWICE")

      assert Composite.outcomes(palette(), block) == [{"received", "Received first"}]
    end

    # Sabotage: checked the declaration once per module rather than once per
    # block - red. `C2` item 4: `subtree/1` is a callback over the config, so a
    # declaration whose names are raisable for one config is caught on the
    # document that carries the other.
    test "the check is per block, because the subtree is config-dependent" do
      interruptible =
        %{
          block("signup.confirm_step_maybe", "blk_MAYBE")
          | config: %{"event" => "signup.confirmed", "interruptible" => true}
        }

      assert {:ok, _compiled} =
               Compiler.compile(
                 Document.new(
                   Block.new("core.sequence",
                     id: "blk_ROOT",
                     slots: %{"body" => [interruptible]}
                   ),
                   id: "bdoc_declaredoutcomes"
                 ),
                 palette()
               )

      assert {:error, findings} =
               Compiler.compile(document("signup.confirm_step_maybe", "blk_MAYBE"), palette())

      assert Enum.any?(
               findings,
               &(&1.reason == {:outcome_not_raisable, "blk_MAYBE", "timed_out"})
             )
    end

    # Sabotage: dropped the `param_map` filter and took the union over the
    # whole spliced return - red. What an author drops into a pass-through slot
    # must not widen what the type may declare, or the same declaration would
    # compile in one document and fail in the next.
    test "what an author fills a pass-through slot with does not widen the raisable set" do
      filled = %{
        block("signup.confirm_step_open", "blk_OPEN")
        | slots: %{
            "body" => [
              Block.new("core.await",
                id: "blk_FILL",
                config: %{"event" => "signup.confirmed", "timeout" => "10m"}
              )
            ]
          }
      }

      {members, param_map} = Composite.expand!(filled, ConfirmStepOpen)

      assert Enum.any?(Composite.flatten(members), &(&1.id == "blk_FILL"))

      assert Composite.unraisable_outcomes(palette(), ConfirmStepOpen, members, param_map) ==
               ["received"]

      # `sb-51lv`: the same document through the compiler, which is where the
      # rule is cashed. The assertion above is over the function the Resolve
      # stage calls; this one is over the stage.
      #
      # Sabotage: had `outcome_findings/5` answer `[]` unconditionally - the
      # function above still answered `["received"]`, so the first assertion
      # stayed green and this one went red on the `{:error, findings}` match
      # (six of the file's thirty-two went red in all, verified).
      assert {:error, findings} =
               Compiler.compile(
                 Document.new(
                   Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [filled]}),
                   id: "bdoc_declaredoutcomes"
                 ),
                 palette()
               )

      assert [%Finding{} = finding] =
               Enum.filter(findings, &(&1.code == :outcome_not_raisable))

      assert finding.stage == :resolve
      assert finding.block_id == "blk_OPEN"
      assert finding.reason == {:outcome_not_raisable, "blk_OPEN", "received"}
    end

    # Sabotage: ran the check for a composite that declares nothing - red, and
    # every composite written before this section is that composite.
    test "a composite that declares nothing has nothing to check" do
      {members, param_map} = expansion(ConfirmStep)

      assert Composite.unraisable_outcomes(palette(), ConfirmStep, members, param_map) == []
    end

    # The precondition, now guarded. `ref` is `expand!/2`'s own second
    # argument and the Resolve stage only ever reaches this function for a
    # block `composite?/1` answered for (`compiler.ex`'s
    # `unraisable_outcomes` call site), so a non-composite ref here is a
    # caller error and not an input. `io/2` and `outcomes/2` resolve the ref
    # themselves and refuse in `composite_ref!/2`; this one takes the ref
    # already resolved, and `declared_outcomes/1` refuses it in that same
    # shape - this package's own `ArgumentError`, naming what was handed in
    # and what to hand in instead. It used to surface as a `BadMapError`
    # from `Map.get/3` reading `:outcomes` off the `nil` `Palette.call/4`
    # answers for a module with no `__composite__/0`, which named neither.
    #
    # This test exists so that a later change to the refusal - a different
    # exception, a documented tolerance, a silent `[]` - is a diff against a
    # recorded expectation rather than a silent move.
    #
    # Sabotage: put the unguarded `Palette.call |> Map.get` pipeline back in
    # `declared_outcomes/1` - this went red, raising `BadMapError` where the
    # test expects `ArgumentError` (verified).
    test "a ref that is not a composite is a caller error, not an input" do
      {members, param_map} = expansion(ConfirmStep)

      assert_raise ArgumentError, ~r/declares no __composite__\/0/, fn ->
        Composite.unraisable_outcomes(
          palette(),
          StatifierBlocks.Core.Sequence,
          members,
          param_map
        )
      end
    end
  end

  describe "C2 item 3: a declared name the expansion cannot raise is a finding" do
    # Sabotage: raised instead of reporting - red. Decision 1 forbids this
    # pipeline to raise and `C2` item 3 takes no exception to it.
    test "the compile fails with a :resolve finding against the composite block" do
      assert {:error, findings} =
               Compiler.compile(document("signup.confirm_step_dreaming"), palette())

      assert [%Finding{} = finding] =
               Enum.filter(findings, &(&1.code == :outcome_not_raisable))

      assert finding.stage == :resolve
      assert finding.block_id == "blk_CS"
      assert finding.reason == {:outcome_not_raisable, "blk_CS", "went_back"}
      assert finding.message =~ ~s(declares the outcome "went_back")
    end

    # Sabotage: reported every declared name rather than the unraisable ones -
    # red. `received` is raised by the `core.await` and is not a finding.
    test "only the unraisable name is reported" do
      assert {:error, findings} =
               Compiler.compile(document("signup.confirm_step_dreaming"), palette())

      assert Enum.filter(findings, &(&1.code == :outcome_not_raisable))
             |> Enum.map(& &1.reason)
             |> Enum.map(&elem(&1, 2)) == ["went_back"]
    end

    # Sabotage: checked the declaration at the module's own compile time - red.
    # `C2` item 4: `subtree/1` is a callback over the config, so the check is
    # per block, and a document whose every declared name is raisable compiles.
    test "a document whose declared names are all raisable compiles" do
      assert {:ok, _compiled} =
               Compiler.compile(document("signup.confirm_step_declaring"), palette())
    end

    # Sabotage: asked each member for its DERIVED outcomes rather than through
    # `BlockType.outcomes/2` - red. A member that is itself a composite
    # contributes the names it declares under this section, which is the whole
    # of what makes the check compositional.
    test "a composite member contributes the names it declares" do
      assert {:ok, _compiled} =
               Compiler.compile(document("signup.confirm_and_record", "blk_CAR"), palette())

      assert Composite.outcomes(palette(), block("signup.confirm_and_record", "blk_CAR")) == [
               {"timed_out", "Timed out"}
             ]
    end
  end

  # -- the Note of 2026-09-13, item 4 -------------------------------------

  describe "an unresolvable minted member contributes nothing to the raisable set" do
    # Sabotage: restored the flat_map straight through `BlockType.outcomes/2`
    # - red. `member_module/2` answers `nil` for the ghost and that function is
    # total over `nil`, so the member would supply the documented `done`
    # default and the set would carry a name no member is known to raise.
    test "the raisable set is the union over the members the palette can resolve" do
      {members, param_map} = expansion(ConfirmStepGhost)

      assert Enum.any?(
               Composite.flatten(members),
               &(&1.type == "signup.not_in_this_palette")
             )

      assert Composite.unraisable_outcomes(palette(), ConfirmStepGhost, members, param_map) ==
               ["done"]
    end

    # Sabotage: the same restoration - red. The declared `done` would take the
    # ghost's `"Done"`; with the ghost absent from the set there is no member
    # to take a label from, so the Note's item 2 fallback answers the name.
    test "a declared name only the unresolvable member could supply takes no label from it" do
      assert Composite.outcomes(palette(), block("signup.confirm_step_ghost", "blk_GHOST")) ==
               [{"done", "done"}]
    end

    # Sabotage: the same restoration - red. `C2` item 3's check would pass on
    # the strength of the missing palette entry, which is the failure mode
    # this item exists to stop.
    test "the declaration draws C2 item 3's finding beside the unknown-type one" do
      assert {:error, findings} =
               Compiler.compile(document("signup.confirm_step_ghost", "blk_GHOST"), palette())

      assert [%Finding{} = unknown] = Enum.filter(findings, &(&1.code == :unknown_block_type))
      assert unknown.stage == :resolve
      assert unknown.reason == {:unknown_block_type, "signup.not_in_this_palette"}

      assert Enum.filter(findings, &(&1.code == :outcome_not_raisable))
             |> Enum.map(& &1.reason) == [{:outcome_not_raisable, "blk_GHOST", "done"}]
    end

    # Sabotage: raised a finding of its own for the unresolvable member - red.
    # The Note's item 4 narrows the set and complains about nothing; the
    # unknown type is already reported where it is reported.
    test "the unresolvable member raises nothing new of its own" do
      assert {:error, findings} =
               Compiler.compile(
                 document("signup.confirm_step_ghost_quiet", "blk_QUIET"),
                 palette()
               )

      assert findings |> Enum.map(& &1.code) |> Enum.uniq() == [:unknown_block_type]
    end
  end

  # -- C3: absent, the compiled bytes do not move -------------------------

  describe "C3: a document that writes no outcomes key compiles byte-identical" do
    # Sabotage: made the declared path run for an empty declaration - red
    # against these bytes, which were recorded from this document compiled at
    # `d9f4896`, the commit before the key existed. This is the condition on
    # which this section lands inside a release that is not otherwise breaking.
    #
    # `sb-51lv`: the golden lives under `test/fixtures/composite/` rather than
    # in `test/fixtures/corpus/`, which is `StatifierBlocks.ByteCorpus`'s own
    # directory and now holds exactly the goldens its entries name. This one
    # is read here and nowhere else, so it was never a corpus document.
    test "the bytes match the ones recorded before the key existed" do
      assert {:ok, compiled} = Compiler.compile(document("signup.confirm_step"), palette())

      assert compiled.scxml ==
               File.read!("test/fixtures/composite/composite_no_outcomes-plain.scxml")
    end

    # Sabotage: read an explicit `[]` as a declaration - red. `C1` says an
    # explicit empty list is deliberately the absent case: every block type
    # answers at least the default `done`, so there is nothing else it could
    # mean.
    #
    # `sb-51lv`: the declaration assertion alone cannot separate the two
    # paths, because `outcomes_over/3` branches on the declared list rather
    # than on the key's presence. The second assertion is the one that does:
    # `ConfirmStepEmpty` writes the key explicitly and still answers the
    # expansion root's derived list, which is `C3`'s absent case. Under the
    # sabotage the declared branch runs over an empty name list and the
    # answer is `[]` rather than the root's `done` (verified).
    test "an explicit empty list is the absent case" do
      declaration = Composite.__declaration__(name: "signup.x", params: [], outcomes: [])

      assert declaration.outcomes == []

      assert ConfirmStepEmpty.__composite__().outcomes == []

      assert Composite.outcomes(palette(), block("signup.confirm_step_empty", "blk_EMPTY")) ==
               [{"done", "Done"}]

      assert ConfirmStepEmpty.outcomes(%{"event" => "signup.confirmed"}) ==
               ConfirmStep.outcomes(%{"event" => "signup.confirmed"})
    end
  end

  # -- C4: the data spelling ----------------------------------------------

  describe "C4: Composite.Data takes the same key" do
    alias StatifierBlocks.Composite.Data

    defp row(extra \\ %{}) do
      Map.merge(
        %{
          "type_name" => "signup.confirm_step_data",
          "version" => 1,
          "params" => [
            %{"key" => "event", "type" => "string", "label" => "Confirmed by", "default" => ""}
          ],
          "subtree" => [
            %{
              "type" => "core.sequence",
              "id_suffix" => "body",
              "slots" => %{
                "body" => [
                  %{
                    "type" => "core.await",
                    "id_suffix" => "wait",
                    "config" => %{
                      "event" => %{"$param" => "event"},
                      "timeout" => "10m"
                    }
                  }
                ]
              }
            }
          ]
        },
        extra
      )
    end

    # Sabotage: left `:outcomes` out of `__composite__/1`'s `Map.take` - red.
    # The derivation reads the declaration through that one function, so a key
    # the state carries but the declaration does not is a key nothing reads.
    test "a data declaration carries the key into its state and its declaration" do
      assert {:ok, state} = Data.declaration(row(%{"outcomes" => ["timed_out"]}))
      assert state.outcomes == ["timed_out"]
      assert Data.__composite__(state).outcomes == ["timed_out"]
    end

    # Sabotage: defaulted the missing key to `nil` - red, for `C3`'s reason on
    # the module form.
    test "a data declaration that writes no key defaults to the empty list" do
      assert {:ok, state} = Data.declaration(row())
      assert state.outcomes == []
    end

    # Sabotage: answered the root's list through the data door - red. `C4` says
    # everything `C1` and `C2` say holds here unchanged, which is only true if
    # both forms reach the same derivation.
    test "a data composite answers its declared names, with the members' labels" do
      assert {:ok, state} = Data.declaration(row(%{"outcomes" => ["timed_out", "received"]}))

      ref = {Data, state}
      palette = Palette.new(Map.put(Palette.core_types(), "signup.confirm_step_data", ref))

      assert Composite.outcomes(palette, block("signup.confirm_step_data")) == [
               {"timed_out", "Timed out"},
               {"received", "Received"}
             ]
    end

    # Sabotage: accepted any list - red. The row is read by named key, and a
    # row whose value is not a list of names is a declaration error like every
    # other one this module reports rather than raises.
    test "a row whose outcomes are not names is a declaration error" do
      assert {:error, errors} = Data.declaration(row(%{"outcomes" => ["", 3]}))

      assert Enum.any?(errors, &(&1 =~ ~s("outcomes" must be a list of non-empty)))
    end

    # `sb-51lv`: `C2` item 3 through the data door. Every other assertion for
    # the unraisable-name finding above compiles a USE-form composite, so a
    # Resolve stage that reached the declaration through something only the
    # `use` form has would leave the data form unchecked and every one of
    # them green. `C4` says everything `C1` and `C2` say holds here unchanged,
    # and this is the half of `C2` with a Finding in it.
    #
    # Sabotage: had the Resolve stage run the check for module refs only
    # (`when not is_atom(module) -> []` in front of `outcome_findings/5`) -
    # this was the only one of the file's thirty-two that went red, every
    # use-form sibling included (verified).
    test "a data composite naming an unraisable outcome draws C2 item 3's finding" do
      assert {:ok, state} = Data.declaration(row(%{"outcomes" => ["received", "went_back"]}))

      palette =
        Palette.new(Map.put(Palette.core_types(), "signup.confirm_step_data", {Data, state}))

      assert {:error, findings} =
               Compiler.compile(document("signup.confirm_step_data", "blk_DATA"), palette)

      assert [%Finding{} = finding] =
               Enum.filter(findings, &(&1.code == :outcome_not_raisable))

      assert finding.stage == :resolve
      assert finding.block_id == "blk_DATA"
      assert finding.reason == {:outcome_not_raisable, "blk_DATA", "went_back"}
      assert finding.message =~ ~s(declares the outcome "went_back")
    end
  end

  # -- C5: nothing else moves ---------------------------------------------

  describe "C5: what this section is not" do
    # Sabotage: changed `derived_outcomes/2`'s arity to carry the declaration -
    # red. `C5` says the three functions keep the arities and the return type
    # they have.
    #
    # `sb-51lv`: the name says the two functions the body can see.
    # `outcomes_over/3` is private, so `function_exported?/3` answers `false`
    # for it at every arity and an assertion about it here would pin nothing;
    # `C5`'s third function is checked through `Composite.outcomes/2`, which
    # is the only door it has.
    test "derived_outcomes/2 and Composite.outcomes/2 keep their arities" do
      assert function_exported?(Composite, :derived_outcomes, 2)
      assert function_exported?(Composite, :outcomes, 2)
    end

    # Sabotage: widened the return to carry the declaredness - red. `C5`:
    # `outcomes/1` still answers `[outcome_decl()]`, which is a list of
    # `{name, label}` pairs of strings and nothing else.
    test "outcomes/1 still answers a list of name/label pairs" do
      assert Enum.all?(
               ConfirmStepDeclaring.outcomes(%{}),
               &match?({name, label} when is_binary(name) and is_binary(label), &1)
             )
    end

    # Sabotage: added `:outcomes` to the option list without adding it to the
    # `__using__` doc's list - red here only if the two lists part ways, which
    # is the invariant the comment above `@declaration_options` states.
    test "the recognized option set names the new key" do
      assert_raise ArgumentError, ~r/the recognized options are.*:outcomes/s, fn ->
        Composite.__declaration__(name: "signup.x", params: [], nonesuch: true)
      end
    end
  end

  # -- C6 and C7: the declared list is a compiled route after all ---------

  describe "C6 and C7: a declaring composite compiles to a state of its own" do
    # `sb-51lv`, `sb-qmm3` item 8 asked for an end-to-end pin that a declared
    # non-default outcome reaches an enclosing body. `C5` refused to give one
    # - "This section changes *which list a composite answers as its declared
    # outcomes*, and nothing about what an outcome is, how it is drawn, or how
    # it compiles" - and said the test below "is what will go red when one
    # is". `C6` and `C7` are that decision, and this is the same test,
    # re-pinned to them.
    #
    # What did NOT move: the two refutes. `s_blk_CS_body` is the EXPANSION
    # ROOT's state, a `core.sequence` that raises `done` and nothing else, and
    # `C6` mints on the composite BLOCK's id - `s_blk_CS`. The expansion root
    # still raises no declared name.
    #
    # What moved is the enclosing body's transition. `C6` item 1 makes the
    # composite a state enclosing its expansion, so what the body routes on is
    # `done.state.s_blk_CS` and not the expansion root's completion, and the
    # composite's own `done.outcome.s_blk_CS.*` is raised from the finals
    # `C6` item 2 mints.
    #
    # Sabotage: dropped the `declaring` arm of `expand_node/3`, so a declaring
    # composite is replaced by its expansion as before - red on the composite
    # state, on both new outcome events, and on the body's transition.
    test "the enclosing body routes the composite's own completion" do
      assert {:ok, compiled} =
               Compiler.compile(document("signup.confirm_step_declaring"), palette(),
                 child_use: true
               )

      # The declared names are still raised by the `core.await` that reaches
      # them - a member two levels below the composite block's own id.
      assert compiled.scxml =~ "done.outcome.s_blk_CS_wait.received"
      assert compiled.scxml =~ "done.outcome.s_blk_CS_wait.timed_out"

      # And still not by the expansion root, which is what `C6` narrows in
      # `C5` and what makes minting on the composite's own id the change.
      refute compiled.scxml =~ "done.outcome.s_blk_CS_body.received"
      refute compiled.scxml =~ "done.outcome.s_blk_CS_body.timed_out"

      # `C6` item 1: the composite is a state enclosing its expansion.
      assert compiled.scxml =~ ~s(<state id="s_blk_CS" initial="s_blk_CS_body">)

      # `C6` item 2: one `<final>` per declared name, each raising the
      # composite's own completion event from its `<onentry>`.
      assert compiled.scxml =~
               ~s(<final id="s_blk_CS__o_received"><onentry>) <>
                 ~s(<raise event="done.outcome.s_blk_CS.received"/></onentry></final>)

      assert compiled.scxml =~
               ~s(<final id="s_blk_CS__o_timed_out"><onentry>) <>
                 ~s(<raise event="done.outcome.s_blk_CS.timed_out"/></onentry></final>)

      # And the line that moved: the enclosing body routes the composite.
      refute compiled.scxml =~ ~s(event="done.state.s_blk_CS_body" target="s_blk_ROOT__o_done")
      assert compiled.scxml =~ ~s(event="done.state.s_blk_CS" target="s_blk_ROOT__o_done")
    end

    # `C6` item 3: a member final raising a declared name transitions to the
    # matching composite final. The `core.await` is the raiser here and the
    # transition sits on the composite's own compound state, which is what
    # lets it fire for a member any depth below.
    #
    # Sabotage: pointed `routing_transitions/1` at the member's own final
    # instead of the route's target - red, the event then targets a state
    # inside the expansion.
    test "a declared member outcome transitions to the matching composite final" do
      assert {:ok, compiled} =
               Compiler.compile(document("signup.confirm_step_declaring"), palette(),
                 child_use: true
               )

      assert compiled.scxml =~
               ~s(<transition event="done.outcome.s_blk_CS_wait.received" ) <>
                 ~s(target="s_blk_CS__o_received" type="internal"/>)

      assert compiled.scxml =~
               ~s(<transition event="done.outcome.s_blk_CS_wait.timed_out" ) <>
                 ~s(target="s_blk_CS__o_timed_out" type="internal"/>)
    end

    # `C6` item 4: "A completion the declaration does not name does not
    # finish the composite." The expansion root raises `done`, which the
    # declaration does not carry, so nothing leaves the composite's state on
    # it and the composite rests there.
    #
    # Sabotage: gave `member_chain/2` an exit target - the first route's final
    # - so the expansion's last member is chained onward the way
    # `Emit.chain/2` chains one. Red: the expansion root's completion then
    # leaves the composite.
    test "an undeclared completion leaves the composite state resting" do
      assert {:ok, compiled} =
               Compiler.compile(document("signup.confirm_step_declaring"), palette(),
                 child_use: true
               )

      # The expansion root's own completion is raised...
      assert compiled.scxml =~ "done.outcome.s_blk_CS_body.done"

      # ...and no transition anywhere selects on it or on the root's
      # `done.state`, so it reaches no composite final. (The raise inside the
      # root's own final carries the same event name, which is why these are
      # written as `<transition event=`.)
      refute compiled.scxml =~ ~s(<transition event="done.outcome.s_blk_CS_body.done")
      refute compiled.scxml =~ ~s(<transition event="done.state.s_blk_CS_body")
    end

    # `C7` item 1: one derived slot per declared name, named `on_<name>`,
    # arity `zero_or_one`, AFTER the entries `slots:` declares, and "labelled
    # from the outcome's own label" - which is the label the raising member
    # declares for that name and which the sibling `outcomes/1` callback
    # already answers from the same config.
    #
    # Sabotage: dropped the `outcome_slots/3` half of `derived_slots/2` - red,
    # the list then carries the pass-through entry alone.
    test "a declaring composite answers one on_<name> slot per declared outcome" do
      assert ConfirmStepDeclaring.slots(%{}) == [
               {"on_timed_out", :zero_or_one, "Timed out"},
               {"on_received", :zero_or_one, "Received"}
             ]

      # The pass-through entries come first, in declaration order, and the
      # derived ones are appended - so every slot that exists today keeps its
      # position.
      assert Enum.map(AwaitsWithSlot.slots(%{}), &elem(&1, 0)) == [
               "body",
               "on_received",
               "on_timed_out"
             ]
    end

    # `C7` item 1's label clause, said as an identity rather than as two
    # strings that happen to match: the slot's label IS the label the
    # sibling `outcomes/1` callback answers for the same name, from the same
    # config, because both come from `derived_outcomes/2`. A member that
    # relabels an outcome relabels its slot with it, and there is no second
    # place a label can be spelled.
    #
    # Sabotage: derived the label from the name (`"If it finishes " <> name`,
    # `core.subchart`'s wording) instead of from the outcome decl - red, the
    # two callbacks then disagree.
    test "the derived slot's label is the outcome's own label" do
      config = %{"event" => "signup.confirmed"}

      labels = Map.new(ConfirmStepDeclaring.outcomes(config))

      for {slot, _arity, label} <- ConfirmStepDeclaring.slots(config) do
        "on_" <> name = slot
        assert label == Map.fetch!(labels, name)
      end
    end

    # The other door `C7` item 1 names. A data-declared composite answers the
    # derived entries through the same `Composite.derived_slots/2`, with the
    # same labels, so the two declaration forms of one composite are one
    # composite - which is `P2`'s claim reaching the outcome slots.
    #
    # Sabotage: left `Composite.Data.slots/2` on the declaration-only
    # `derived_slots/1` - red, the data form then answers its pass-through
    # entry alone.
    test "the data declaration form answers the derived slots too" do
      assert {:ok, state} =
               Composite.Data.declaration(%{
                 "type_name" => "signup.confirm_step_data",
                 "version" => 1,
                 "params" => [
                   %{
                     "key" => "event",
                     "type" => "string",
                     "label" => "Confirmed by",
                     "required?" => true,
                     "default" => ""
                   }
                 ],
                 "subtree" => [
                   %{
                     "type" => "core.sequence",
                     "id_suffix" => "body",
                     "slots" => %{
                       "body" => [
                         %{
                           "type" => "core.await",
                           "id_suffix" => "wait",
                           "config" => %{"event" => "{{event}}", "timeout" => "10m"}
                         }
                       ]
                     }
                   }
                 ],
                 "outcomes" => ["timed_out", "received"]
               })

      config = %{"event" => "signup.confirmed"}

      assert Composite.Data.slots(state, config) == [
               {"on_timed_out", :zero_or_one, "Timed out"},
               {"on_received", :zero_or_one, "Received"}
             ]
    end

    # `C7` item 6: a name the declaration does not carry mints no slot.
    #
    # Sabotage: appended the expansion root's `done` to the declared list
    # before deriving, the way a derivation reading what the expansion can
    # raise would - red, `on_done` is then minted.
    test "an undeclared name mints no slot" do
      assert ConfirmStep.slots(%{}) == []
      refute Enum.any?(ConfirmStepDeclaring.slots(%{}), &(elem(&1, 0) == "on_done"))
    end

    # `C7` item 3, the empty slot: the declared member outcome reaches the
    # matching composite final directly, and such a composite compiles as
    # `C6` alone would compile it.
    #
    # Sabotage: targeted the slot child unconditionally in `route/1`'s target
    # - red, `route.target` would be `nil` with no child.
    test "an empty outcome slot reaches the composite final directly" do
      assert {:ok, compiled} =
               Compiler.compile(document("signup.confirm_step_declaring"), palette(),
                 child_use: true
               )

      assert compiled.scxml =~
               ~s(<transition event="done.outcome.s_blk_CS_wait.received" ) <>
                 ~s(target="s_blk_CS__o_received" type="internal"/>)
    end

    # `C7` item 3, the occupied slot: the declared member outcome reaches the
    # child filling that outcome's slot instead, and that child's completion
    # reaches the same composite final - so the composite's own
    # `done.outcome.s_blk_CS.received` fires AFTER the continuation rather
    # than instead of it, and the enclosing body still continues on the
    # composite's completion. This is the end-to-end case `k2` measured.
    #
    # Sabotage: dropped `slot_child/1`'s completion transition - red, the
    # continuation then runs and the composite never finishes.
    test "an occupied outcome slot runs its child before that outcome's final" do
      assert {:ok, compiled} = Compiler.compile(with_slot_child(), palette(), child_use: true)

      # In, from the member that raised the declared name.
      assert compiled.scxml =~
               ~s(<transition event="done.outcome.s_blk_CS_wait.received" ) <>
                 ~s(target="s_blk_GOBACK" type="internal"/>)

      # The child is a child of the composite's own state.
      assert compiled.scxml =~ ~s(<state id="s_blk_GOBACK")

      # Out, to the same final the empty slot would have reached.
      assert compiled.scxml =~
               ~s(<transition event="done.state.s_blk_GOBACK" ) <>
                 ~s(target="s_blk_CS__o_received" type="internal"/>)

      # The final is reached either way, so the composite's own outcome event
      # is raised either way, and the body routes the composite's completion.
      assert compiled.scxml =~ ~s(<raise event="done.outcome.s_blk_CS.received"/>)
      assert compiled.scxml =~ ~s(event="done.state.s_blk_CS" target="s_blk_ROOT__o_done")

      # The other declared name's slot is empty and still reaches its final.
      assert compiled.scxml =~
               ~s(<transition event="done.outcome.s_blk_CS_wait.timed_out" ) <>
                 ~s(target="s_blk_CS__o_timed_out" type="internal"/>)
    end

    # `C7` item 2: a `slots:` entry named after one of the declaration's own
    # declared outcomes is refused against the DECLARATION - the composite's
    # author is who can fix it - and never as a finding on a document. Both
    # declaration forms refuse, each in its own idiom.
    #
    # Sabotage: dropped the `refute_outcome_slot_collisions!/2` call from
    # `__declaration__/1` - red, the declaration then builds and answers a
    # duplicated slot name.
    test "a slots: entry named after a declared outcome is refused" do
      assert_raise ArgumentError, ~r/"on_received".*already derives as an outcome slot/s, fn ->
        Composite.__declaration__(
          name: "signup.colliding",
          params: [],
          outcomes: ["received"],
          slots: [%{name: "on_received", to: {"body", "body"}}]
        )
      end

      assert {:error, errors} =
               Composite.Data.declaration(%{
                 "type_name" => "signup.colliding_data",
                 "version" => 1,
                 "params" => [],
                 "subtree" => [%{"type" => "core.sequence", "id_suffix" => "body"}],
                 "outcomes" => ["received"],
                 "slots" => %{"on_received" => ["body", "body"]}
               })

      assert Enum.any?(errors, &(&1 =~ ~s("on_received")))
    end

    # `C7` item 2's other side, which "What builds this" names as its own
    # test: "one naming a name its `outcomes` does not declare is not"
    # refused. A pass-through slot called `on_<something>` for a name the
    # declaration does not carry keeps its pass-through meaning, builds, and
    # is answered.
    #
    # Sabotage: had `outcome_slot_collisions/2` match on the `"on_"` prefix
    # rather than on the declared names - red, this declaration is then
    # refused too.
    test "a slots: entry named for an outcome the declaration does not declare is not refused" do
      declaration =
        Composite.__declaration__(
          name: "signup.not_colliding",
          params: [],
          outcomes: ["received"],
          slots: [%{name: "on_abandoned", to: {"body", "body"}, label: "If abandoned"}]
        )

      assert Composite.derived_slots(declaration) == [
               {"on_abandoned", :any, "If abandoned"}
             ]

      assert Composite.outcome_slot_collisions(declaration.slots, declaration.outcomes) == []
    end

    # `C7` item 2's other half, said where a reader would look for it: the
    # refusal is what keeps a repeated name out of the answered list, which
    # both the editor's slot build and the compiler's `List.keyfind/3` read
    # assume. Nothing a declaration can write reaches `slots/1` twice.
    #
    # Sabotage: appended the derived entries twice in `derived_slots/2` - red,
    # which is the property this pins. (Making the collision a precedence
    # rule rather than a refusal is red on the test above instead: the
    # declaration then builds, and it is that build the refusal prevents.)
    test "no name is reachable twice in the answered slot list" do
      names = Enum.map(ConfirmStepDeclaring.slots(%{}), &elem(&1, 0))
      assert names == Enum.uniq(names)

      with_slot = Enum.map(AwaitsWithSlot.slots(%{}), &elem(&1, 0))
      assert with_slot == Enum.uniq(with_slot)
    end

    # The expansion members hang off a declaring composite's resolved node
    # under a slot name the compiler mints, and the spliced document the
    # Structure stage walks is rebuilt from that node - so that one key is
    # exempt from `:undeclared_slot`, which is about a slot the DOCUMENT uses
    # that its type does not declare.
    #
    # The exemption is scoped to the blocks the compiler put the key on, and
    # this pins that it is: the name is not reserved anywhere a stored
    # document passes through, so an author can write a slot with it, and one
    # who does must still be told their blocks would be dropped rather than
    # getting a green compile that silently drops them. The declaring
    # composite sits in the same document so the exemption is live while this
    # runs.
    #
    # Sabotage: dropped the `MapSet.member?(declaring, block_id)` guard from
    # `compiler_slot?/2`, which is the narrowing as it was first written -
    # red: the compile then answers `{:ok, _}` and `blk_W` is gone from the
    # chart.
    test "an author's slot of the same name still draws its undeclared-slot finding" do
      plain =
        Block.new("core.sequence",
          id: "blk_P",
          slots: %{
            ":expansion" => [Block.new("core.wait", id: "blk_W", config: %{"for" => "1m"})]
          }
        )

      document =
        Document.new(
          Block.new("core.sequence",
            id: "blk_ROOT",
            slots: %{"body" => [block("signup.confirm_step_declaring"), plain]}
          ),
          id: "bdoc_declaredoutcomes"
        )

      assert {:error, findings} = Compiler.compile(document, palette(), child_use: true)

      assert Enum.any?(findings, fn finding ->
               finding.stage == :structure and
                 finding.reason == {:undeclared_slot, "blk_P", ":expansion", 1}
             end)

      # And nothing is reported against the composite, whose key is the
      # compiler's own.
      refute Enum.any?(findings, &match?({:undeclared_slot, "blk_CS", _slot, _count}, &1.reason))
    end

    # `C6` item 5 and `C7` item 4, and the test both records delegate their
    # totality claim to. `ADR-0004`'s decision 5 keeps `by_state_id` total
    # over every state the compile emits; `C6` adds a state and two finals
    # and `C7` adds a slot child, so this asserts the map answers for EVERY
    # state id in the generated chart and that the new ones name the blocks
    # the records say they do - the composite's own bytes to the composite
    # block, the slot child's to the child, and the members' stamps
    # unchanged (`T2`-`T4`).
    #
    # It reads the ids out of the emitted SCXML rather than listing them, so
    # a state this request forgot to stamp fails it rather than going
    # unnoticed.
    #
    # Sabotage: stamped the routing transitions to the raising member instead
    # of to the composite - red before the assertions: the compile refuses
    # with `:unknown_attribution`, because a raiser deep in the expansion is
    # not a child of the composite's own node.
    test "provenance stays total over the bytes C6 and C7 add" do
      assert {:ok, compiled} = Compiler.compile(with_slot_child(), palette(), child_use: true)

      emitted =
        Regex.scan(~r/ id="(s_[^"]+)"/, compiled.scxml)
        |> Enum.map(fn [_whole, id] -> id end)

      # Every state and final the compile emitted is keyed, including the
      # three `C6` and `C7` add.
      assert "s_blk_CS" in emitted
      assert "s_blk_CS__o_received" in emitted
      assert "s_blk_CS__o_timed_out" in emitted
      assert "s_blk_GOBACK" in emitted

      assert Enum.all?(emitted, &Map.has_key?(compiled.provenance.by_state_id, &1)),
             "unstamped: #{inspect(emitted -- Map.keys(compiled.provenance.by_state_id))}"

      # The composite's own state and finals are the composite block's.
      for id <- ["s_blk_CS", "s_blk_CS__o_received", "s_blk_CS__o_timed_out"] do
        assert compiled.provenance.by_state_id[id].block_id == "blk_CS"
      end

      # The slot child's bytes are the child block's, and the members keep
      # the stamps `ADR-0004`'s `T2`-`T4` give them.
      assert compiled.provenance.by_state_id["s_blk_GOBACK"].block_id == "blk_GOBACK"
      assert compiled.provenance.by_state_id["s_blk_CS_body"].block_id == "blk_CS_body"
      assert compiled.provenance.by_state_id["s_blk_CS_wait"].block_id == "blk_CS_wait"
    end
  end

  # The `k2` fixture with a child in the composite's derived `on_received`
  # slot - the blocks an author drops in to go back when the step finishes
  # that way.
  defp with_slot_child do
    composite = %{
      block("signup.confirm_step_declaring")
      | slots: %{"on_received" => [Block.new("core.sequence", id: "blk_GOBACK")]}
    }

    Document.new(
      Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [composite]}),
      id: "bdoc_declaredoutcomes"
    )
  end

  # The `C8` fixture with a child in the composite's derived `on_went_back`
  # slot - the blocks an author drops in to go back when the Back button is
  # what finished the screen.
  defp with_back_slot_child do
    composite = %{
      block("signup.screen_with_back")
      | slots: %{"on_went_back" => [Block.new("core.sequence", id: "blk_GOBACK")]}
    }

    Document.new(
      Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [composite]}),
      id: "bdoc_declaredoutcomes"
    )
  end

  defp expansion(module) do
    Composite.expand!(block(module.__composite__().name), module)
  end
end
