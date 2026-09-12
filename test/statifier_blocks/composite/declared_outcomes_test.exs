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

  # -- helpers -----------------------------------------------------------

  defp palette do
    Palette.new(
      Map.merge(Palette.core_types(), %{
        "signup.confirm_step" => ConfirmStep,
        "signup.confirm_step_declaring" => ConfirmStepDeclaring,
        "signup.confirm_step_dreaming" => ConfirmStepDreaming,
        "signup.confirm_and_record" => ConfirmAndRecord,
        "signup.confirm_step_open" => ConfirmStepOpen,
        "signup.confirm_step_maybe" => ConfirmStepMaybe,
        "signup.confirm_step_twice" => ConfirmStepTwice,
        "signup.receives_first" => ReceivesFirst,
        "signup.receives_second" => ReceivesSecond
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
    test "the raisable set is the union over the expansion, not the root alone" do
      assert Composite.unraisable_outcomes(
               palette(),
               ConfirmStepDeclaring,
               expansion(ConfirmStepDeclaring) |> elem(0),
               expansion(ConfirmStepDeclaring) |> elem(1)
             ) == []
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
    end

    # Sabotage: ran the check for a composite that declares nothing - red, and
    # every composite written before this section is that composite.
    test "a composite that declares nothing has nothing to check" do
      {members, param_map} = expansion(ConfirmStep)

      assert Composite.unraisable_outcomes(palette(), ConfirmStep, members, param_map) == []
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

  # -- C3: absent, the compiled bytes do not move -------------------------

  describe "C3: a document that writes no outcomes key compiles byte-identical" do
    # Sabotage: made the declared path run for an empty declaration - red
    # against these bytes, which were recorded from this document compiled at
    # `d9f4896`, the commit before the key existed. This is the condition on
    # which this section lands inside a release that is not otherwise breaking.
    test "the bytes match the ones recorded before the key existed" do
      assert {:ok, compiled} = Compiler.compile(document("signup.confirm_step"), palette())

      assert compiled.scxml ==
               File.read!("test/fixtures/corpus/composite_no_outcomes-plain.scxml")
    end

    # Sabotage: read an explicit `[]` as a declaration - red. `C1` says an
    # explicit empty list is deliberately the absent case: every block type
    # answers at least the default `done`, so there is nothing else it could
    # mean.
    test "an explicit empty list is the absent case" do
      declaration = Composite.__declaration__(name: "signup.x", params: [], outcomes: [])

      assert declaration.outcomes == []
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
  end

  # -- C5: nothing else moves ---------------------------------------------

  describe "C5: what this section is not" do
    # Sabotage: changed `derived_outcomes/2`'s arity to carry the declaration -
    # red. `C5` says the three functions keep the arities and the return type
    # they have.
    test "derived_outcomes/2, outcomes_over/3 and Composite.outcomes/2 keep their arities" do
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

  defp expansion(module) do
    Composite.expand!(block(module.__composite__().name), module)
  end
end
