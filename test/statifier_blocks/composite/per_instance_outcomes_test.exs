defmodule StatifierBlocks.Composite.PerInstanceOutcomesTest do
  @moduledoc """
  A composite may declare its outcomes as a function of its own config, and
  every reader of the declared list reads that instance's (ADR-0002's
  Amendment of 2026-09-18, `C9`).

  The fixtures are a **copy** of the signup wizard's screen arrangement, cut
  down to what the four proofs need and living here rather than in the
  examples app: a `core.group` whose body presents a screen and parks, and
  whose interrupts hold one `core.on_event` per button, each naming the
  outcome its press finishes the group as. One block type stands for every
  screen in the element document below, which is the arrangement the whole
  section is about - the type cannot know at its own compile time which
  buttons the screen in front of it has.

  The four things `C9`'s closing section asks this to prove, each in its own
  describe block:

  1. **Enumeration, not transcription.** The readers of the declared list are
     enumerated by grep over `lib/` and the enumeration is pinned, so a site
     the record's own list missed is a red test rather than a silent gap.
  2. **`C3` still byte-identical.** A document holding no per-instance
     declarer compiles to the bytes it compiled to before this section, read
     from a golden recorded on `main` at `98e98ff`.
  3. **The static list unchanged.** A composite declaring `outcomes:`
     statically behaves identically at every site, keeps both
     module-compile-time refusals, and draws the same findings it drew before.
  4. **The measurement closes.** The signup Path with a per-instance screen
     composite compiles with zero findings, and the findings the type-level
     union draws are gone.

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

  # -- the element document the screen composite reads --------------------

  defmodule Screens do
    @moduledoc """
    The element half, as a module rather than a shipped JSON file: three
    screens, each with its questions and its buttons, and a button's
    `outcome` is the name its press finishes the screen as.

    The point of the fixture is that the three screens have **different**
    buttons, so one composite type cannot say at its own compile time what
    any one instance of it finishes as.
    """

    @type screen :: %{questions: [String.t()], buttons: [String.t()]}

    @screens %{
      "account" => %{
        questions: ["first_name", "email"],
        buttons: ["account_submitted"]
      },
      "plan" => %{
        questions: ["seats"],
        buttons: ["chose_personal", "chose_business", "went_back"]
      },
      "confirm" => %{
        questions: [],
        buttons: ["confirmed"]
      }
    }

    @doc "One screen, or `nil` for a key this document does not carry."
    @spec screen(term()) :: screen() | nil
    def screen(key) when is_binary(key), do: Map.get(@screens, key)
    def screen(_not_a_key), do: nil

    @doc "The outcome names a screen's buttons raise, plus the park's."
    @spec outcome_names(term()) :: [String.t()]
    def outcome_names(key) do
      case screen(key) do
        nil -> []
        %{buttons: buttons} -> buttons ++ ["timed_out"]
      end
    end

    @doc "Every outcome name any screen in this document raises, once each."
    @spec union() :: [String.t()]
    def union do
      @screens |> Map.keys() |> Enum.sort() |> Enum.flat_map(&outcome_names/1) |> Enum.uniq()
    end
  end

  # -- the subtree the two screen types share -----------------------------

  defmodule ScreenSubtree do
    @moduledoc """
    One subtree, so that the two declarations below differ in **how they
    declare their outcomes** and in nothing else - which is what makes every
    comparison in this file read as the declaration's doing.
    """

    alias StatifierBlocks.Block
    alias StatifierBlocks.Composite.PerInstanceOutcomesTest.Screens

    @doc "The group, the presentation, the park, and one handler per button."
    @spec build(map()) :: [Block.t()]
    def build(params) do
      key = params["screen"]

      [
        Block.new("core.group",
          id: "screen",
          slots: %{
            "body" => [
              Block.new("core.send",
                id: "present",
                config: %{"event" => "signup.screen." <> to_string(key) <> ".present"}
              ),
              Block.new("core.await",
                id: "park",
                config: %{
                  "event" => "signup.screen." <> to_string(key) <> ".resumed",
                  "timeout" => params["timeout"] || "1d"
                }
              )
            ],
            "interrupts" => handlers(key)
          }
        )
      ]
    end

    defp handlers(key) do
      case Screens.screen(key) do
        nil ->
          []

        %{buttons: buttons} ->
          buttons
          |> Enum.with_index(1)
          |> Enum.map(fn {outcome, position} ->
            Block.new("core.on_event",
              id: "button_" <> Integer.to_string(position),
              config: %{
                "event" => "signup." <> outcome,
                "outcome" => "abandon",
                "finish_as" => outcome
              }
            )
          end)
      end
    end
  end

  # -- the per-instance declarer, and the type-level union it replaces ----

  defmodule PerInstanceScreen do
    @moduledoc """
    `C9`'s shape: no `:outcomes` option, and a `declared_outcomes/1` that
    reads the instance's own screen out of the element document. Two blocks
    of this type in one document declare different names.
    """

    use StatifierBlocks.Composite,
      name: "signup.screen_per_instance",
      params: [
        %{key: "screen", type: :string, label: "Screen", required?: true, default: "account"},
        %{key: "timeout", type: :string, label: "Abandon after", required?: true, default: "1d"}
      ],
      palette_entry: %{label: "Screen"},
      version: 1

    alias StatifierBlocks.Composite.PerInstanceOutcomesTest.{Screens, ScreenSubtree}

    @impl StatifierBlocks.Composite
    def subtree(params), do: ScreenSubtree.build(params)

    @impl StatifierBlocks.Composite
    def declared_outcomes(config), do: Screens.outcome_names(config["screen"])
  end

  defmodule UnionScreen do
    @moduledoc """
    The arrangement `C9`'s measurement section describes, and the one the
    ruling declined: the same subtree with the **union** of every screen's
    outcome names declared statically at the type. Every instance is then
    refused, per instance, every name that instance cannot raise.
    """

    use StatifierBlocks.Composite,
      name: "signup.screen_union",
      params: [
        %{key: "screen", type: :string, label: "Screen", required?: true, default: "account"},
        %{key: "timeout", type: :string, label: "Abandon after", required?: true, default: "1d"}
      ],
      outcomes: [
        "account_submitted",
        "timed_out",
        "confirmed",
        "chose_personal",
        "chose_business",
        "went_back"
      ],
      palette_entry: %{label: "Screen (union)"},
      version: 1

    alias StatifierBlocks.Composite.PerInstanceOutcomesTest.ScreenSubtree

    @impl StatifierBlocks.Composite
    def subtree(params), do: ScreenSubtree.build(params)
  end

  defmodule StaticPlanScreen do
    @moduledoc """
    The static declarer whose list happens to fit one screen exactly. It is
    what `C9` says stays byte-identical: a composite declaring `outcomes:`
    behaves at every site as it did, and this is the one whose bytes can be
    compared because it is the one that compiles clean.
    """

    use StatifierBlocks.Composite,
      name: "signup.screen_static_plan",
      params: [
        %{key: "screen", type: :string, label: "Screen", required?: true, default: "plan"},
        %{key: "timeout", type: :string, label: "Abandon after", required?: true, default: "1d"}
      ],
      outcomes: ["chose_personal", "chose_business", "went_back", "timed_out"],
      palette_entry: %{label: "Screen (static plan)"},
      version: 1

    alias StatifierBlocks.Composite.PerInstanceOutcomesTest.ScreenSubtree

    @impl StatifierBlocks.Composite
    def subtree(params), do: ScreenSubtree.build(params)
  end

  defmodule QuietScreen do
    @moduledoc """
    The `C3` composite: the same subtree, declaring its outcomes by neither
    spelling. It answers its expansion root's derived list and is replaced by
    its expansion outright, exactly as every composite written before `C1`.
    """

    use StatifierBlocks.Composite,
      name: "signup.screen_quiet",
      params: [
        %{key: "screen", type: :string, label: "Screen", required?: true, default: "account"},
        %{key: "timeout", type: :string, label: "Abandon after", required?: true, default: "1d"}
      ],
      palette_entry: %{label: "Screen (quiet)"},
      version: 1

    alias StatifierBlocks.Composite.PerInstanceOutcomesTest.ScreenSubtree

    @impl StatifierBlocks.Composite
    def subtree(params), do: ScreenSubtree.build(params)
  end

  # -- the three `C9d` refusals, each as its own type ---------------------

  defmodule RubbishScreen do
    @moduledoc "A callback answering something that is not a list of names."

    use StatifierBlocks.Composite,
      name: "signup.screen_rubbish",
      params: [
        %{key: "screen", type: :string, label: "Screen", required?: true, default: "account"}
      ],
      palette_entry: %{label: "Screen (rubbish)"},
      version: 1

    alias StatifierBlocks.Composite.PerInstanceOutcomesTest.ScreenSubtree

    @impl StatifierBlocks.Composite
    def subtree(params), do: ScreenSubtree.build(params)

    @impl StatifierBlocks.Composite
    def declared_outcomes(_config), do: %{"confirmed" => "Confirmed"}
  end

  defmodule DoubledScreen do
    @moduledoc "A callback answering one name twice for this instance."

    use StatifierBlocks.Composite,
      name: "signup.screen_doubled",
      params: [
        %{key: "screen", type: :string, label: "Screen", required?: true, default: "account"}
      ],
      palette_entry: %{label: "Screen (doubled)"},
      version: 1

    alias StatifierBlocks.Composite.PerInstanceOutcomesTest.ScreenSubtree

    @impl StatifierBlocks.Composite
    def subtree(params), do: ScreenSubtree.build(params)

    @impl StatifierBlocks.Composite
    def declared_outcomes(_config), do: ["account_submitted", "account_submitted"]
  end

  defmodule CollidingScreen do
    @moduledoc """
    A pass-through slot the type declares, and a config whose per-instance
    name derives an outcome slot of the same spelling. Only a particular
    config can bring the two into collision, which is `C9d`'s whole point.
    """

    use StatifierBlocks.Composite,
      name: "signup.screen_colliding",
      params: [
        %{key: "screen", type: :string, label: "Screen", required?: true, default: "account"}
      ],
      slots: [%{name: "on_account_submitted", to: {"extra", "body"}}],
      palette_entry: %{label: "Screen (colliding)"},
      version: 1

    alias StatifierBlocks.Block
    alias StatifierBlocks.Composite.PerInstanceOutcomesTest.{Screens, ScreenSubtree}

    # The shared subtree plus one empty sequence for the pass-through slot to
    # map into: a pass-through slot holds the author's children and only them,
    # so it cannot map to a slot the subtree already fills.
    @impl StatifierBlocks.Composite
    def subtree(params) do
      [group] = ScreenSubtree.build(params)

      [
        %{
          group
          | slots:
              Map.update!(
                group.slots,
                "body",
                &(&1 ++ [Block.new("core.sequence", id: "extra", slots: %{"body" => []})])
              )
        }
      ]
    end

    @impl StatifierBlocks.Composite
    def declared_outcomes(config), do: Screens.outcome_names(config["screen"])
  end

  defmodule ImproperScreen do
    @moduledoc """
    A callback answering an IMPROPER list. It passes `is_list/1` and is not a
    list of names, which is the shape a total check has to be written for
    rather than reasoned about.
    """

    use StatifierBlocks.Composite,
      name: "signup.screen_improper",
      params: [
        %{key: "screen", type: :string, label: "Screen", required?: true, default: "account"}
      ],
      palette_entry: %{label: "Screen (improper)"},
      version: 1

    alias StatifierBlocks.Composite.PerInstanceOutcomesTest.ScreenSubtree

    @impl StatifierBlocks.Composite
    def subtree(params), do: ScreenSubtree.build(params)

    @impl StatifierBlocks.Composite
    def declared_outcomes(_config), do: ["account_submitted" | "timed_out"]
  end

  defmodule RaisingScreen do
    @moduledoc """
    A callback that raises rather than answering - the element document the
    host meant to read is not there, and the package author reached for an
    exception. `subtree/1` doing the same is rescued into a finding, and
    decision 1 gives this route no other option either.
    """

    use StatifierBlocks.Composite,
      name: "signup.screen_raising",
      params: [
        %{key: "screen", type: :string, label: "Screen", required?: true, default: "account"}
      ],
      palette_entry: %{label: "Screen (raising)"},
      version: 1

    alias StatifierBlocks.Composite.PerInstanceOutcomesTest.ScreenSubtree

    @impl StatifierBlocks.Composite
    def subtree(params), do: ScreenSubtree.build(params)

    @impl StatifierBlocks.Composite
    def declared_outcomes(_config), do: raise(RuntimeError, "no element document is loaded")
  end

  # -- the palette and the two documents ----------------------------------

  defp palette do
    Palette.new(
      Map.merge(Palette.core_types(), %{
        "signup.screen_per_instance" => PerInstanceScreen,
        "signup.screen_union" => UnionScreen,
        "signup.screen_static_plan" => StaticPlanScreen,
        "signup.screen_quiet" => QuietScreen,
        "signup.screen_rubbish" => RubbishScreen,
        "signup.screen_doubled" => DoubledScreen,
        "signup.screen_colliding" => CollidingScreen,
        "signup.screen_improper" => ImproperScreen,
        "signup.screen_raising" => RaisingScreen
      })
    )
  end

  defp screen_block(type, id, key, slots \\ %{}),
    do: Block.new(type, id: id, config: %{"screen" => key, "timeout" => "1d"}, slots: slots)

  # The signup Path, as a block document: three screens on one rail, in the
  # order a reader meets them. `type` is which screen composite stands for
  # them, which is the whole of the difference between the two measurements.
  defp path(type, opts \\ []) do
    plan_slots = Keyword.get(opts, :plan_slots, %{})

    Document.new(
      Block.new("core.sequence",
        id: "blk_ROOT",
        slots: %{
          "body" => [
            screen_block(type, "blk_ACCOUNT", "account"),
            screen_block(type, "blk_PLAN", "plan", plan_slots),
            screen_block(type, "blk_CONFIRM", "confirm")
          ]
        }
      ),
      id: "bdoc_signup_path"
    )
  end

  defp one_block_document(type, key),
    do:
      Document.new(
        Block.new("core.sequence",
          id: "blk_ROOT",
          slots: %{"body" => [screen_block(type, "blk_SCREEN", key)]}
        ),
        id: "bdoc_signup_path"
      )

  # -- proof 1: the enumeration --------------------------------------------

  describe "C9 proof 1: every reader of the declared list is enumerated and threaded" do
    # `C9` asks for a grep over `lib/` rather than a transcription of the
    # section's own six sites, because a site the section missed is a site
    # the rule still reaches. This test IS that grep, run against the tree
    # it is checked into, so a new reader added later either takes the
    # config or reddens this.
    #
    # Sabotage: had `outcomes_over/3` read `declared_outcomes(ref, %{})` in
    # place of the block's own config - red here on the pinned line, and red in
    # four tests across the other three describe blocks besides (verified).
    test "the readers are exactly these, and each one takes the instance's config" do
      readers =
        "lib/**/*.ex"
        |> Path.wildcard()
        |> Enum.flat_map(fn path ->
          path
          |> File.read!()
          |> String.split("\n")
          |> Enum.with_index(1)
          |> Enum.filter(fn {line, _number} ->
            String.contains?(line, "declared_outcomes(") or
              String.contains?(line, "declared_outcome_names(") or
              String.contains?(line, "Map.get(declaration, :outcomes")
          end)
          |> Enum.map(fn {line, number} -> {path, number, String.trim(line)} end)
        end)

      call_sites =
        readers
        |> Enum.reject(fn {_path, _number, line} ->
          String.starts_with?(line, "#") or String.starts_with?(line, "defp ") or
            String.starts_with?(line, "def ") or String.starts_with?(line, "@spec ") or
            String.starts_with?(line, "@callback ")
        end)
        |> Enum.map(fn {path, _number, line} -> {Path.basename(path), line} end)

      # Every call of the declared-list route carries a config. The one read
      # that does not is `static_declared_outcomes/1`'s own `Map.get` off the
      # declaration, which is the route's floor and has no instance to know
      # about.
      assert call_sites == [
               {"compiler.ex", "case Composite.declared_outcome_names(module, block.config) do"},
               {"composite.ex", "case declared_outcomes(ref, config) do"},
               {"composite.ex", "case declared_outcomes(ref, config) do"},
               {"composite.ex", "case declared_outcomes(ref, block.config) do"},
               {"composite.ex", "Map.get(declaration, :outcomes, [])"},
               {"composite.ex", ":static -> static_declared_outcomes(ref)"}
             ]
    end

    # The three public entry points the rule reaches through, each pinned at
    # the arity that carries a config. `C9c` decides that widening an
    # `@doc false` helper to carry a config is not new surface; this is what
    # it widened to.
    #
    # Sabotage: put the ref-only `declared_outcome_names/1` pass-through back
    # beside the new arity - red (verified), because the route the record calls
    # the whole of the gap in one line is then exported again.
    test "the public route is the config-carrying arity, and only that" do
      assert function_exported?(Composite, :declared_outcome_names, 2)
      refute function_exported?(Composite, :declared_outcome_names, 1)

      assert function_exported?(Composite, :unraisable_outcomes, 5)
      refute function_exported?(Composite, :unraisable_outcomes, 4)

      assert function_exported?(Composite, :declared_outcome_problems, 2)
      assert function_exported?(Composite, :per_instance_declarer?, 1)
    end

    # The behaviour's first optional callback, and the reason it is optional:
    # every composite written before this section implements neither
    # spelling, and none of them is broken by the callback's existence.
    #
    # Sabotage: dropped the `@optional_callbacks` attribute - red (verified).
    # Every composite written before this section implements neither spelling,
    # and the attribute is what keeps the callback's existence additive.
    test "declared_outcomes/1 is an optional callback on the behaviour" do
      callbacks = Composite.behaviour_info(:callbacks)
      optional = Composite.behaviour_info(:optional_callbacks)

      assert {:declared_outcomes, 1} in callbacks
      assert {:declared_outcomes, 1} in optional
      assert {:subtree, 1} in callbacks
      refute {:subtree, 1} in optional
    end

    # `per_instance_declarer?/1` is the question the whole threading turns
    # on, and `C9e` puts the data shape outside it: a `{module, state}` ref
    # is a registration whose declaration is data and cannot hold a function.
    #
    # Sabotage: answered `true` from the `{module, state}` clause - red on the
    # data arm (verified), which would then take the per-instance route `C9e`
    # deliberately leaves undecided.
    test "the question is asked of module composites only" do
      assert Composite.per_instance_declarer?(PerInstanceScreen)
      refute Composite.per_instance_declarer?(UnionScreen)
      refute Composite.per_instance_declarer?(QuietScreen)
      refute Composite.per_instance_declarer?(StatifierBlocks.Core.Sequence)
      refute Composite.per_instance_declarer?({PerInstanceScreen, %{}})
    end
  end

  # -- proof 2: C3 is still byte-identical ---------------------------------

  describe "C9 proof 2: a document with no per-instance declarer does not move" do
    # The golden was recorded from this exact document compiled on `main` at
    # `98e98ff` - the commit that carries `C9` as a record and none of its
    # code. `C3`'s byte-identity claim is what lets this section land inside
    # a release that is not otherwise breaking, and a golden taken before
    # the code existed is the only evidence for it that the code cannot
    # fake.
    #
    # Sabotage: had the `:static` arm answer the declaration's list plus the
    # root's default `done` - red against these bytes (verified), because the
    # quiet composite then compiles to a state of its own rather than being
    # replaced by its expansion.
    test "the quiet composite's bytes match the ones recorded before the code" do
      assert {:ok, compiled} = Compiler.compile(path("signup.screen_quiet"), palette())

      assert compiled.scxml ==
               File.read!("test/fixtures/composite/per_instance_absent-quiet.scxml")
    end

    # The same claim for the STATIC declarer, whose bytes this section also
    # promises not to move. It is a separate golden because the two compile
    # to genuinely different charts - one is replaced by its expansion, the
    # other survives Resolve as a state of its own - and one golden could
    # not have caught a change that moved only the second.
    #
    # Sabotage: sent every composite down the per-instance route
    # (`if composite?(ref)` in place of `if per_instance_declarer?(ref)`) - red
    # here (verified), since a static declarer then answers the callback
    # route's default of `[]` and its declared list disappears.
    test "the static declarer's bytes match the ones recorded before the code" do
      assert {:ok, compiled} =
               Compiler.compile(
                 one_block_document("signup.screen_static_plan", "plan"),
                 palette()
               )

      assert compiled.scxml ==
               File.read!("test/fixtures/composite/per_instance_absent-static-plan.scxml")
    end

    # The route itself: a composite that is not a per-instance declarer never
    # reaches the callback, so nothing about it can depend on a config at all.
    #
    # Sabotage: the same one - every composite down the per-instance route -
    # red (verified). This is the assertion that says what goes wrong when it
    # is: the static list is replaced by the callback route's empty default.
    test "a static declarer answers its own list for every config" do
      assert Composite.declared_outcome_names(UnionScreen, %{}) == Screens.union()

      assert Composite.declared_outcome_names(UnionScreen, %{"screen" => "confirm"}) ==
               Screens.union()

      assert Composite.declared_outcome_names(QuietScreen, %{"screen" => "plan"}) == []
    end
  end

  # -- proof 3: the static list is unchanged -------------------------------

  describe "C9 proof 3: a static declaration behaves as it did, refusals included" do
    # The two refusals `C9d` re-sites for a per-instance declarer stay
    # exactly where they are for a static one: at module compile time, with
    # their existing text. `C9d` says outright that it adds a second home for
    # them and does not move the first.
    #
    # Sabotage: dropped `normalize_outcomes!/1`'s duplicate guard (`if false`)
    # - red on the first assertion (verified), because the static declaration
    # then builds with a name in it twice.
    test "both module-compile-time refusals still stand over a static list" do
      assert_raise ArgumentError, ~r/declares \["went_back"\] more than once/, fn ->
        Composite.__declaration__(
          name: "signup.x",
          params: [],
          outcomes: ["went_back", "went_back"]
        )
      end

      assert_raise ArgumentError, ~r/"on_went_back".*already derives as an outcome slot/s, fn ->
        Composite.__declaration__(
          name: "signup.x",
          params: [],
          outcomes: ["went_back"],
          slots: [%{name: "on_went_back", to: {"screen", "body"}}]
        )
      end

      assert_raise ArgumentError, ~r/:outcomes must be a list of non-empty outcome name/, fn ->
        Composite.__declaration__(name: "signup.x", params: [], outcomes: [:went_back])
      end
    end

    # `C9`'s precedence clause. The two spellings are two ways to say one
    # thing and there is no reading under which both apply; letting the
    # callback win silently would make the static list's presence invisible.
    #
    # Sabotage: dropped the `refute_both_outcome_spellings!/1` call from
    # `__before_compile__/1` - red (verified): the module compiles and its
    # static list is silently never read.
    test "a type writing both spellings is refused by name as it compiles" do
      assert_raise CompileError, fn ->
        Code.eval_string("""
        defmodule StatifierBlocksTestBothSpellings do
          use StatifierBlocks.Composite,
            name: "signup.both",
            params: [],
            outcomes: ["confirmed"]

          @impl StatifierBlocks.Composite
          def subtree(_config), do: [StatifierBlocks.Block.new("core.sequence", id: "body")]

          @impl StatifierBlocks.Composite
          def declared_outcomes(_config), do: ["confirmed"]
        end
        """)
      end
    end

    # The other side of the precedence clause: a static `outcomes: []` is
    # `C1`'s absent case, already collapsed by the time the refusal runs, so
    # a type writing it beside the callback is saying one thing once.
    #
    # Sabotage: refused on anything but a non-empty list (`static == static`,
    # which is the key's presence, since `__declaration__/1` always writes the
    # key) - red, and red as a `CompileError` on the per-instance fixtures
    # above (verified). That blast radius is the point: narrowing the refusal
    # to a non-empty list is what lets a per-instance declarer exist at all.
    test "an explicit empty static list is the absent case, not a second spelling" do
      assert {{:module, module, _binary, _result}, _bindings} =
               Code.eval_string("""
               defmodule StatifierBlocksTestEmptyStaticList do
                 use StatifierBlocks.Composite,
                   name: "signup.empty_static",
                   params: [],
                   outcomes: []

                 @impl StatifierBlocks.Composite
                 def subtree(_config), do: [StatifierBlocks.Block.new("core.sequence", id: "body")]

                 @impl StatifierBlocks.Composite
                 def declared_outcomes(_config), do: ["confirmed"]
               end
               """)

      assert module.__composite__().outcomes == []
      assert Composite.per_instance_declarer?(module)
    end

    # The union type at every site `C9`'s section names, with the same
    # answers it gave before: the declaration, the callback over config, the
    # derived slots, and the raisability check. This is the "identically at
    # every site" half of proof 3.
    #
    # Sabotage: sent every composite down the per-instance route - red
    # (verified) on the declaration, the callback, the slots and the check at
    # once, which is what "identically at every site" is worth.
    test "the static declarer answers the same thing at every site" do
      assert UnionScreen.__composite__().outcomes == Screens.union()

      assert UnionScreen.outcomes(%{"screen" => "plan"}) |> Enum.map(&elem(&1, 0)) ==
               Screens.union()

      slot_names = UnionScreen.slots(%{"screen" => "plan"}) |> Enum.map(&elem(&1, 0))

      for name <- Screens.union() do
        assert ("on_" <> name) in slot_names
      end

      {members, param_map} =
        Composite.expand!(screen_block("signup.screen_union", "blk_PLAN", "plan"), UnionScreen)

      assert Composite.unraisable_outcomes(
               palette(),
               UnionScreen,
               %{"screen" => "plan"},
               members,
               param_map
             ) == ["account_submitted", "confirmed"]
    end
  end

  # -- proof 4: the measurement closes -------------------------------------

  describe "C9 proof 4: the signup Path compiles with zero findings" do
    # The measurement this section began from, re-taken here on the fixture
    # copy rather than quoted from the examples app: one type declaring the
    # union of three screens' names, three instances, and every name an
    # instance cannot raise refused against that instance. Four and two and
    # four, which is the shape `C9`'s measurement section describes.
    #
    # Sabotage: inverted `unraisable_outcomes/5`'s comparison (`Enum.filter`
    # for `Enum.reject`) - red (verified), and red in six other tests: the ten
    # findings become the names each instance CAN raise.
    test "the type-level union is refused, per instance, ten times" do
      assert {:error, findings} = Compiler.compile(path("signup.screen_union"), palette())

      assert length(findings) == 10

      assert Enum.all?(findings, &(&1.stage == :resolve))
      assert findings |> Enum.map(& &1.code) |> Enum.uniq() == [:outcome_not_raisable]
      assert findings |> Enum.map(& &1.fault) |> Enum.uniq() == [:package]

      assert findings |> Enum.frequencies_by(& &1.block_id) == %{
               "blk_ACCOUNT" => 4,
               "blk_PLAN" => 2,
               "blk_CONFIRM" => 4
             }
    end

    # And the same Path with the same subtree, declaring per instance:
    # **zero** findings. This is the whole of what `C9` is for.
    #
    # Sabotage: had `declaring_node/7` ask the question with an empty config
    # (`declared_outcome_names(module, %{})`) - red (verified). The per-instance
    # type declares nothing for an empty config, so every screen reads as a
    # non-declaring composite and none of these events is minted at all.
    test "the same Path declaring per instance compiles clean" do
      assert {:ok, compiled} = Compiler.compile(path("signup.screen_per_instance"), palette())

      # Each screen raises its own names, and no screen raises another's.
      assert compiled.scxml =~ ~s(done.outcome.s_blk_ACCOUNT.account_submitted)
      assert compiled.scxml =~ ~s(done.outcome.s_blk_PLAN.chose_personal)
      assert compiled.scxml =~ ~s(done.outcome.s_blk_PLAN.went_back)
      assert compiled.scxml =~ ~s(done.outcome.s_blk_CONFIRM.confirmed)

      refute compiled.scxml =~ ~s(done.outcome.s_blk_ACCOUNT.chose_personal)
      refute compiled.scxml =~ ~s(done.outcome.s_blk_CONFIRM.went_back)
    end

    # `C9b`, cashed on a document: "is this composite declaring?" is a
    # question about a BLOCK, and two blocks of one type answer it
    # differently. The screen key no screen carries is the empty-list arm -
    # a non-declaring instance, and `C3` is its rule.
    #
    # Sabotage: the same one - `declaring_node/7` asking with an empty config
    # - red (verified) on the declaring half, which is what says the two
    # instances are told apart by their own config and not by their type.
    test "two blocks of one type declare differently, and an empty answer is C3's case" do
      assert Composite.declared_outcome_names(PerInstanceScreen, %{"screen" => "account"}) ==
               ["account_submitted", "timed_out"]

      assert Composite.declared_outcome_names(PerInstanceScreen, %{"screen" => "confirm"}) ==
               ["confirmed", "timed_out"]

      assert Composite.declared_outcome_names(PerInstanceScreen, %{"screen" => "nowhere"}) == []

      assert {:ok, declaring} =
               Compiler.compile(
                 one_block_document("signup.screen_per_instance", "confirm"),
                 palette()
               )

      assert {:ok, quiet} =
               Compiler.compile(
                 one_block_document("signup.screen_per_instance", "nowhere"),
                 palette()
               )

      assert declaring.scxml =~ "s_blk_SCREEN__o_confirmed"
      refute quiet.scxml =~ "s_blk_SCREEN__o_"
    end

    # `C7`'s slot derivation, per instance: the slots a screen offers are the
    # buttons that screen has, and a child in one is wired the way `C7` item
    # 3 wires any other outcome slot's.
    #
    # Sabotage: had `outcome_slots/3` read the type's static list
    # (`static_declared_outcomes(ref)`) - red (verified), since a per-instance
    # declarer writes none and every instance then opens no interior at all.
    test "the derived slots are that instance's, and a child in one is wired" do
      account_slots =
        PerInstanceScreen.slots(%{"screen" => "account"}) |> Enum.map(&elem(&1, 0))

      plan_slots = PerInstanceScreen.slots(%{"screen" => "plan"}) |> Enum.map(&elem(&1, 0))

      assert "on_account_submitted" in account_slots
      refute "on_went_back" in account_slots
      assert "on_went_back" in plan_slots

      assert {:ok, compiled} =
               Compiler.compile(
                 path("signup.screen_per_instance",
                   plan_slots: %{
                     "on_went_back" => [Block.new("core.sequence", id: "blk_GOBACK")]
                   }
                 ),
                 palette()
               )

      assert compiled.scxml =~
               ~s(<transition event="done.outcome.s_blk_PLAN_button_3.went_back" ) <>
                 ~s(target="s_blk_GOBACK" type="internal"/>)
    end
  end

  # -- C9d: the three per-instance refusals --------------------------------

  describe "C9d: a refusal a per-instance declaration cannot make at compile time" do
    # The arm `C9d` left to this request: a callback answering rubbish is
    # package-author code, so the finding says `:package`. The document
    # author can do nothing about it - deleting the block would leave the
    # same type answering the same rubbish for the next one.
    #
    # Sabotage: blamed the author (`fault: :author`) - red here and on the
    # two refusals below (verified). This is the arm `C9d` left to this
    # request, so a change of mind about it is a diff against a recorded
    # expectation rather than a silent move.
    test "a non-list answer is a Resolve finding against that block" do
      assert {:error, [%Finding{} = finding]} =
               Compiler.compile(one_block_document("signup.screen_rubbish", "confirm"), palette())

      assert finding.stage == :resolve
      assert finding.code == :outcome_declaration_invalid
      assert finding.fault == :package
      assert finding.block_id == "blk_SCREEN"
      assert finding.message =~ "must answer a list of non-empty outcome name strings"
    end

    # The duplicate-name refusal, re-sited. `C9d` says the rule itself is not
    # reopened - only where it is reported moves - so the message says what
    # `normalize_outcomes!/1`'s refusal says.
    #
    # Sabotage: dropped the duplicate arm from `check_instance_outcomes/2`
    # (`false ->`) - red (verified), and a name declared twice would answer
    # twice from `outcomes/1` where an outcome is one slot.
    test "a name twice is a Resolve finding against that block" do
      assert {:error, [%Finding{} = finding]} =
               Compiler.compile(one_block_document("signup.screen_doubled", "account"), palette())

      assert finding.code == :outcome_declaration_invalid
      assert finding.fault == :package
      assert finding.message =~ ~s(["account_submitted"] more than once)
    end

    # The slot collision, re-sited. The pass-through slots are the type's and
    # the outcome slots are the instance's, so only a particular config can
    # bring the two into collision - which is why this one cannot be a
    # module-compile-time refusal for a per-instance declarer at all.
    #
    # Sabotage: never looked for the collision (`case [] do`) - red
    # (verified). The type declares no static list, so nothing else in the
    # package is in a position to find this one.
    test "a derived outcome slot colliding with a pass-through slot is a finding" do
      assert {:error, [%Finding{} = finding]} =
               Compiler.compile(
                 one_block_document("signup.screen_colliding", "account"),
                 palette()
               )

      assert finding.code == :outcome_declaration_invalid
      assert finding.fault == :package
      assert finding.message =~ ~s(["on_account_submitted"])
      assert finding.message =~ "already derives as an outcome slot"
    end

    # The instance that does not collide, of the same type. This is what says
    # the finding above is the config's doing and not the type's.
    #
    # Sabotage: reported every pass-through slot as a collision, rather than
    # the ones the instance's own names derive - red here (verified) and green
    # on the colliding instance above, which is the whole distinction.
    test "another instance of the colliding type compiles clean" do
      assert Composite.declared_outcome_problems(CollidingScreen, %{"screen" => "confirm"}) == []

      assert {:ok, _compiled} =
               Compiler.compile(
                 one_block_document("signup.screen_colliding", "confirm"),
                 palette()
               )
    end

    # The total readers - the editor's slot list and the view model's outcome
    # chips - have no stage to report a finding to, so a refused declaration
    # degrades there to `C3`'s path rather than raising or drawing names the
    # block cannot raise.
    #
    # Sabotage: dropped the duplicate arm from `check_instance_outcomes/2` -
    # red (verified) on the last assertion, since the doubled type's answer
    # then reaches `outcomes/1` as a declaration rather than degrading to
    # `C3`'s path.
    test "a refused declaration reads as non-declaring off the compiler path" do
      assert Composite.declared_outcome_names(RubbishScreen, %{"screen" => "confirm"}) == []
      assert RubbishScreen.slots(%{"screen" => "confirm"}) == []

      assert DoubledScreen.outcomes(%{"screen" => "account"}) == [{"done", "Done"}]
    end

    # An IMPROPER list passes `is_list/1` and is not a list of names, so the
    # shape check has to be written as a walk rather than as a guard plus
    # `Enum.all?/2` - which raises a `FunctionClauseError` on the tail. It is
    # a `C9d` third-arm answer like any other rubbish, not a second kind of
    # thing.
    #
    # Sabotage: put the guard-plus-`Enum.all?/2` shape check back
    # (`not (is_list(names) and Enum.all?(names, &(is_binary(&1) and &1 != "")))`)
    # - red (verified), and red by RAISING `FunctionClauseError` out of
    # `Compiler.compile/2`, which is the defect this test was written for.
    test "an improper list is a finding, and the compile does not raise" do
      assert {:error, [%Finding{} = finding]} =
               Compiler.compile(
                 one_block_document("signup.screen_improper", "account"),
                 palette()
               )

      assert finding.stage == :resolve
      assert finding.code == :outcome_declaration_invalid
      assert finding.fault == :package
      assert finding.block_id == "blk_SCREEN"
      assert finding.message =~ "must answer a list of non-empty outcome name strings"
    end

    # A callback that raises is the sibling of a `subtree/1` that raises, and
    # the compiler rescues that one into a `:composite_expansion_failed`
    # finding (`compiler.ex`, `expand/2`). Decision 1 forbids this pipeline to
    # raise and `C9d` takes no exception to it, so this route rescues too and
    # says what the exception said.
    #
    # Sabotage: dropped the `rescue` from `instance_answer/2` - red
    # (verified), raising `RuntimeError` out of `Compiler.compile/2`.
    test "a callback that raises is a finding, and the compile does not raise" do
      assert {:error, [%Finding{} = finding]} =
               Compiler.compile(one_block_document("signup.screen_raising", "account"), palette())

      assert finding.stage == :resolve
      assert finding.code == :outcome_declaration_invalid
      assert finding.fault == :package
      assert finding.block_id == "blk_SCREEN"
      assert finding.message =~ "raised"
      assert finding.message =~ "no element document is loaded"
    end

    # The other path, for both of them. The editor's slot list and the view
    # model's outcome chips have no stage to report a finding to, and the
    # comment on the read says they must be total; these are what hold it to
    # that. `Composite.outcomes/2` is the palette-carrying route a view model
    # actually uses.
    #
    # Sabotage: the same two - the guard-plus-`Enum.all?/2` check, and the
    # dropped `rescue` - red on this test each time (verified), once per
    # fixture.
    test "neither rubbish answer raises off the compiler path" do
      for module <- [ImproperScreen, RaisingScreen] do
        config = %{"screen" => "account"}

        assert Composite.declared_outcome_names(module, config) == []
        assert module.slots(config) == []
        assert module.outcomes(config) == [{"done", "Done"}]
      end

      assert Composite.outcomes(
               palette(),
               screen_block("signup.screen_improper", "blk_SCREEN", "account")
             ) == [{"done", "Done"}]

      assert Composite.outcomes(
               palette(),
               screen_block("signup.screen_raising", "blk_SCREEN", "account")
             ) == [{"done", "Done"}]
    end

    # And the refusal is reported once per block, not once per reader: the
    # read runs several times over one compile and the finding is drawn where
    # `C2` item 3's is.
    #
    # Sabotage: seeded the findings into the member reduction beside the
    # raisability check rather than in place of it - red (verified), the block
    # draws the refusal twice.
    test "a refused declaration draws exactly one finding for its block" do
      assert {:error, findings} =
               Compiler.compile(one_block_document("signup.screen_raising", "plan"), palette())

      assert length(findings) == 1
    end
  end
end
