defmodule StatifierBlocks.CompositeTest do
  @moduledoc """
  `use StatifierBlocks.Composite`: the declaration, `Composite.expand/2`, the
  derived block type and the derived recipe (ADR-0002 decision 5's amendment
  of 2026-09-07, filed with `sb-2gdx`).

  Two composites, one per canonical example domain. "Guarded step" is the
  amendment's own worked example, in card processing: a call, and the failure
  recorded on the error path. "Confirm the contact" is the signup wizard's,
  and its members are host types rather than `core.*` ones, which is what
  makes it the case that exercises the walk without the `core`-only module
  resolution the derived `io/1` and `outcomes/1` fall back on.

  A pure test. Nothing here names LiveView, so it compiles and runs headless.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.Core.Invoke

  alias StatifierBlocks.{
    Assignability,
    Block,
    BlockType,
    Composite,
    Document,
    Environment,
    Palette
  }

  # -- the card-processing composite -------------------------------------

  defmodule GuardedStep do
    @moduledoc """
    The amendment's worked example: call out, and record the failure if the
    call comes back on the error path. Two params, one slot the author cannot
    reach (RQ-SF037-3).
    """

    use StatifierBlocks.Composite,
      name: "myapp.guarded_step",
      params: [
        %{key: "invoke_type", type: :string, label: "Call", required?: true, default: ""},
        %{
          key: "failure_path",
          type: :string,
          label: "Record the failure at",
          required?: true,
          default: "",
          datamodel_path?: true
        }
      ],
      sentence: "Call {invoke_type}, recording failure at {failure_path}",
      palette_entry: %{label: "Guarded step", group: "Structure", order: 40},
      version: 1

    alias StatifierBlocks.Block

    @impl StatifierBlocks.Composite
    def subtree(params) do
      [
        Block.new("core.invoke",
          id: "call",
          config: %{"invoke_type" => params["invoke_type"], "assign_to" => "", "params" => ""},
          slots: %{
            "on_error" => [
              Block.new("core.assign",
                id: "guard",
                config: %{"path" => params["failure_path"], "value" => "failed"}
              )
            ]
          }
        )
      ]
    end
  end

  # -- the signup composite ----------------------------------------------

  defmodule Reads do
    @moduledoc "A host leaf that reads one declared path and writes nothing."

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config),
      do: [
        %{
          key: "subject",
          type: {:path, %{expects: "string"}},
          label: "Read",
          required?: true,
          default: ""
        }
      ]

    @impl true
    def validate_config(_config), do: :ok
    @impl true
    def io(_config), do: %{kinds: [:step]}
    @impl true
    def palette_entry, do: %{label: "Reads"}
    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule ConfirmContact do
    @moduledoc """
    The signup wizard's composite: read the address the author names, then
    mark it confirmed at a second path. Both members are host types, so this
    is the case whose `io/1` and `outcomes/1` take the documented fallback.
    """

    use StatifierBlocks.Composite,
      name: "signup.confirm_contact",
      params: [
        %{
          key: "address_from",
          type: :string,
          label: "Address from",
          required?: true,
          default: "",
          datamodel_path?: true
        },
        %{
          key: "confirmed_at",
          type: :string,
          label: "Mark confirmed at",
          required?: true,
          default: "",
          datamodel_path?: true
        }
      ],
      palette_entry: %{label: "Confirm the contact"}

    alias StatifierBlocks.Block

    @impl StatifierBlocks.Composite
    def subtree(params) do
      [
        Block.new("signup.reads", id: "read", config: %{"subject" => params["address_from"]}),
        Block.new("core.assign",
          id: "mark",
          config: %{"path" => params["confirmed_at"], "value" => "true"}
        )
      ]
    end
  end

  # -- a card-processing composite rooted at a HOST type -----------------

  defmodule Authorizes do
    @moduledoc """
    A host leaf that authorizes a card: it declares sugar and outcomes of its
    own, neither of which `StatifierBlocks.Palette.core_types/0` carries. That
    is what makes a composite rooted at it read differently through a palette
    than through the callback.
    """

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config),
      do: [
        %{key: "invoke_type", type: :string, label: "Call", required?: true, default: ""}
      ]

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def io(_config),
      do: %{
        kinds: [:step],
        consumes: "cards.Authorization",
        produces: "cards.AuthorizationResult"
      }

    @impl true
    def outcomes(_config), do: [{"approved", "Approved"}, {"declined", "Declined"}]

    @impl true
    def palette_entry, do: %{label: "Authorizes"}
    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule Reviews do
    @moduledoc "A host leaf a reviewer picks up, declaring a kind of its own."

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []
    @impl true
    def config_schema(_config), do: []
    @impl true
    def validate_config(_config), do: :ok
    @impl true
    def io(_config), do: %{kinds: [:step, :reviewable]}
    @impl true
    def palette_entry, do: %{label: "Reviews"}
    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule AuthorizeWithDeadline do
    @moduledoc """
    The card-processing reference composite, rooted at a **host** type: the
    authorization, and the review the decline is handed to. Its exact `io` and
    `outcomes` exist only through a palette that carries `myapp.authorizes`
    and `myapp.reviews`; `io/1` and `outcomes/1` take the documented
    core-only fallback.
    """

    use StatifierBlocks.Composite,
      name: "myapp.authorize_with_deadline",
      params: [
        %{key: "invoke_type", type: :string, label: "Call", required?: true, default: ""},
        %{key: "deadline", type: :string, label: "Deadline", required?: true, default: ""},
        %{
          key: "audit_at",
          type: :string,
          label: "Audit at",
          required?: true,
          default: "cards.audit",
          hidden?: true
        }
      ],
      sentence: "Authorize with {invoke_type} inside {deadline}",
      palette_entry: %{label: "Authorize with a deadline"}

    alias StatifierBlocks.Block

    @impl StatifierBlocks.Composite
    def subtree(params) do
      [
        Block.new("myapp.authorizes",
          id: "authorize",
          config: %{"invoke_type" => params["invoke_type"]}
        ),
        Block.new("myapp.reviews", id: "review")
      ]
    end
  end

  # -- a composite whose members are not one-param-each ------------------

  defmodule TwoInOne do
    @moduledoc """
    One member carrying both params, and one member carrying neither. The
    first is blamed on `"path"`, the first param in declaration order
    (`RQ-SF038-14`); the second answers `nil`, because no param fed it.
    """

    use StatifierBlocks.Composite,
      name: "myapp.two_in_one",
      params: [
        %{key: "path", type: :string, label: "Path", required?: true, default: ""},
        %{key: "value", type: :string, label: "Value", required?: true, default: ""}
      ]

    alias StatifierBlocks.Block

    @impl StatifierBlocks.Composite
    def subtree(params) do
      [
        Block.new("core.assign",
          id: "both",
          config: %{"path" => params["path"], "value" => params["value"]}
        ),
        Block.new("core.assign",
          id: "neither",
          config: %{"path" => "cards.audit", "value" => "1"}
        )
      ]
    end
  end

  defmodule ValueFirst do
    @moduledoc """
    `TwoInOne`'s params, declared the other way round. One member carries
    both, so it proves the tie-break reads the declaration and not the
    stored config's own key order.
    """

    use StatifierBlocks.Composite,
      name: "myapp.value_first",
      params: [
        %{key: "value", type: :string, label: "Value", required?: true, default: ""},
        %{key: "path", type: :string, label: "Path", required?: true, default: ""}
      ]

    alias StatifierBlocks.Block

    @impl StatifierBlocks.Composite
    def subtree(params) do
      [
        Block.new("core.assign",
          id: "both",
          config: %{"path" => params["path"], "value" => params["value"]}
        )
      ]
    end
  end

  defmodule OwnSummary do
    @moduledoc """
    A composite that says its own card line. `summary/1` is overridable for
    `sentence/1`'s reason: what a card says is presentation, and a
    declaration whose params do not spell it says it itself.
    """

    use StatifierBlocks.Composite,
      name: "myapp.own_summary",
      params: [%{key: "lane", type: :string, label: "Lane", required?: true, default: ""}]

    alias StatifierBlocks.Block

    @impl StatifierBlocks.Composite
    def subtree(params) do
      [Block.new("core.assign", id: "mark", config: %{"path" => params["lane"], "value" => "1"})]
    end

    @impl StatifierBlocks.BlockType
    def summary(_config), do: ["one lane"]
  end

  # -- helpers -----------------------------------------------------------

  defp palette do
    Palette.new(
      Map.merge(Palette.core_types(), %{
        "myapp.authorize_with_deadline" => AuthorizeWithDeadline,
        "myapp.authorizes" => Authorizes,
        "myapp.guarded_step" => GuardedStep,
        "myapp.reviews" => Reviews,
        "myapp.two_in_one" => TwoInOne,
        "myapp.value_first" => ValueFirst,
        "signup.confirm_contact" => ConfirmContact,
        "signup.reads" => Reads
      })
    )
  end

  defp document(children) do
    Document.new(
      Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => children}),
      id: "bdoc_CANONICAL"
    )
  end

  defp guarded_step(id) do
    Block.new("myapp.guarded_step",
      id: id,
      config: %{
        "invoke_type" => "myapp:authorize",
        "failure_path" => "cards.authorization.failure"
      }
    )
  end

  defp with_deadline do
    Block.new("myapp.authorize_with_deadline",
      id: "blk_AWD",
      config: %{
        "invoke_type" => "myapp:authorize",
        "deadline" => "2h",
        "audit_at" => "cards.audit"
      }
    )
  end

  describe "the derived block type" do
    # Sabotage: made `config_schema/1` answer `[]` - red. The params are the
    # composite's schema, which is what makes the compiler's own F3/F4
    # declaration checks run over them for free.
    test "config_schema/1 is the params, in declaration order" do
      assert [%{key: "invoke_type"}, %{key: "failure_path"}] = GuardedStep.config_schema(%{})
    end

    # Sabotage: derived `slots/1` from the expansion root's slots - red.
    # RQ-SF037-3: a composite in this campaign exposes no slot of its own, so
    # an author cannot put their own block on the error path.
    test "slots/1 is [] (RQ-SF037-3)" do
      assert GuardedStep.slots(%{}) == []
    end

    # Sabotage: hard-coded 1 instead of reading the declaration - red on a
    # declaration that states another version.
    test "current_version/0 is the version the declaration states" do
      assert GuardedStep.current_version() == 1
      assert ConfirmContact.current_version() == 1
    end

    # Sabotage: dropped the root's `produces` - red. The root's sugar is
    # single-valued and the only one the union can carry; a non-root member's
    # is dropped, which under-declares rather than over-declares.
    test "io/1 is the amendment's per-key table" do
      assert GuardedStep.io(%{}) == %{kinds: [:step], slot_accepts: %{}, produces: :unknown}
    end

    # Sabotage: kept the root's `slot_accepts` - red. The composite declares
    # no slots, so there is no slot name to accept into and the root's
    # `%{"on_error" => [:step]}` is dropped with the slot it names.
    test "io/1 drops the root's slot_accepts with the slot it names" do
      assert %{slot_accepts: %{}} = GuardedStep.io(%{})
      assert %{slot_accepts: %{"on_error" => [:step]}} = Invoke.io(%{})
    end

    # Sabotage: took the last member's outcomes rather than the root's - red.
    test "outcomes/1 is the expansion root's" do
      assert GuardedStep.outcomes(%{}) == [{"done", "Done"}, {"error", "Error"}]
    end

    # Sabotage: rendered the template without substituting - red.
    test "sentence/1 renders the declaration's template over the config" do
      config = %{
        "invoke_type" => "myapp:authorize",
        "failure_path" => "cards.authorization.failure"
      }

      assert GuardedStep.sentence(config) ==
               "Call myapp:authorize, recording failure at cards.authorization.failure"
    end

    # Sabotage: answered "" for a declaration with no template - red, because
    # `BlockType.sentence/2` then falls back through a blank rather than
    # answering the label the amendment names.
    test "sentence/1 is the palette label when the declaration states no template" do
      assert ConfirmContact.sentence(%{}) == "Confirm the contact"
    end

    # Sabotage: dropped the `Map.put_new(:label, name)` - red on a
    # declaration that states a palette entry with no label.
    test "palette_entry/0 is the map the declaration states, labelled" do
      assert GuardedStep.palette_entry() == %{
               label: "Guarded step",
               group: "Structure",
               order: 40
             }

      assert TwoInOne.palette_entry() == %{label: "myapp.two_in_one"}
    end

    # Sabotage: generated an `emit/2` returning `{:ok, ...}` - red. That is
    # exactly the failure ADR-0007 refuses to inject a default to avoid: a
    # type that compiled to nothing looking complete instead of failing.
    test "emit/2 is generated and raises if reached (RQ-SF037-6)" do
      assert_raise RuntimeError, ~r/Resolve/, fn ->
        GuardedStep.emit(guarded_step("blk_GS"), nil)
      end
    end

    # Sabotage: re-marked every derived callback `defoverridable` - red. The
    # three that may be overridden are about presentation and refusal; every
    # other row is a fact about the subtree, and a declaration that overrode
    # one would contradict its own `subtree/1`.
    test "only sentence/1, palette_entry/0 and validate_config/1 are overridable" do
      overridable = fn fun_arity ->
        {name, arity} = fun_arity
        # A consumed `defoverridable` leaves the function defined exactly once.
        function_exported?(GuardedStep, name, arity)
      end

      assert Enum.all?(
               [{:sentence, 1}, {:palette_entry, 0}, {:validate_config, 1}],
               overridable
             )

      assert GuardedStep.validate_config(%{}) == :ok
    end

    # Sabotage: derived a refusal from `required?` - red, because the
    # amendment's own worked example declares two `required?: true` params
    # defaulting to "" and must land finding-free.
    test "a fresh composite from Palette.new_block/2 is finding-free" do
      assert {:ok, block} = Palette.new_block(palette(), "myapp.guarded_step")

      assert block.type == "myapp.guarded_step"
      assert block.config == %{"invoke_type" => "", "failure_path" => ""}
      assert block.type_version == GuardedStep.current_version()

      # The three schema-driven checks the compiler's Config stage runs over
      # any block. The stage itself cannot be run end to end on a composite
      # until sb-qxyh expands one at Resolve - reaching Emit raises, which is
      # the test above - so they are asserted here directly.
      assert GuardedStep.validate_config(block.config) == :ok
      assert BlockType.type_expr_findings(GuardedStep, block.config) == []

      for decl <- GuardedStep.config_schema(block.config) do
        assert Map.has_key?(decl, :default)
        refute Map.get(decl, :hidden?, false)
      end
    end

    # Sabotage: answered `true` for any module - red.
    test "composite?/1 tells a composite from an ordinary block type" do
      assert Composite.composite?(GuardedStep)
      assert Composite.composite?(ConfirmContact)
      refute Composite.composite?(StatifierBlocks.Core.Invoke)
      refute Composite.composite?(NoSuchModule)
      refute Composite.composite?(nil)
    end
  end

  describe "Composite.expand!/2" do
    # Sabotage: returned the subtree unminted - red on the ids.
    test "expands to the members, head first, with ids minted from the composite's" do
      assert {[call], param_map} = Composite.expand!(guarded_step("blk_GS"), GuardedStep)

      assert call.id == "blk_GS_call"
      assert call.type == "core.invoke"
      assert call.config["invoke_type"] == "myapp:authorize"

      assert %{"on_error" => [guard]} = call.slots
      assert guard.id == "blk_GS_guard"
      assert guard.type == "core.assign"
      assert guard.config == %{"path" => "cards.authorization.failure", "value" => "failed"}

      assert param_map == %{"blk_GS_call" => "invoke_type", "blk_GS_guard" => "failure_path"}
    end

    # Sabotage: minted with a UXID or a document counter - red. The ids are a
    # function of the composite block's id and nothing else.
    test "the ids are stable across two expansions" do
      {first, _map} = Composite.expand!(guarded_step("blk_GS"), GuardedStep)
      {second, _map} = Composite.expand!(guarded_step("blk_GS"), GuardedStep)

      assert ids(Composite.flatten(first)) == ids(Composite.flatten(second))
      assert ids(Composite.flatten(first)) == ["blk_GS_call", "blk_GS_guard"]
    end

    # Sabotage: minted with "__" as the separator - red. ADR-0004 decision 3
    # reserves "__" for the role separator and its `unstate_id/1` stops
    # inverting when a block id carries one.
    test "no minted id carries \"__\", and each is document-unique" do
      {members, _map} = Composite.expand!(guarded_step("blk_GS"), GuardedStep)
      {others, _map} = Composite.expand!(guarded_step("blk_OTHER"), GuardedStep)

      minted = ids(members) ++ ids(others)

      refute Enum.any?(minted, &String.contains?(&1, "__"))
      assert minted == Enum.uniq(minted)
      assert Enum.all?(ids(members), &String.starts_with?(&1, "blk_GS_"))
    end

    # `ADR-0002`'s Note of 2026-09-07, item 5 rules `RQ-SF038-14`: the module
    # side blames the FIRST param in declaration order when more than one
    # matches, rather than refusing to blame at all.
    #
    # Sabotage: blamed the LAST match, or went back to `nil` for a member
    # carrying two - red on `blk_X_both`, which is `"path"`, the first param
    # `TwoInOne` declares.
    test "a member carrying two params' values is blamed on the first declared" do
      block = Block.new("myapp.two_in_one", id: "blk_X", config: %{"path" => "p", "value" => "v"})

      assert {_members, param_map} = Composite.expand!(block, TwoInOne)

      assert param_map == %{"blk_X_both" => "path", "blk_X_neither" => nil}
    end

    # The tie-break is the DECLARATION's order, not the config map's or the
    # alphabet's: `TwoInOne` declares `"path"` then `"value"`, and a config
    # written the other way round blames `"path"` all the same. A map of two
    # binary keys iterates sorted, so a sabotage that reads `params` directly
    # passes the test above and fails here.
    #
    # Sabotage: ordered by `Map.keys(params)` - red, `"value"` sorts after
    # `"path"` but a reversed declaration would not.
    test "the tie-break follows the declaration, not the stored config" do
      block =
        Block.new("myapp.value_first", id: "blk_V", config: %{"path" => "p", "value" => "v"})

      assert {_members, param_map} = Composite.expand!(block, ValueFirst)

      assert param_map == %{"blk_V_both" => "value"}
    end

    # The first production embedder's shape: a wrapped member re-anchoring
    # with `config_key: nil`. Blaming the first match does not widen what is
    # blamed - a member carrying several param values that are not
    # *distinguishing* still answers `nil`, because no param fed it.
    #
    # Sabotage: dropped `distinguishing?/1` from the search - red, `""` is
    # carried by `blk_E_both` and would blame `"path"`.
    test "a member carrying only empty param values still maps to nil" do
      block = Block.new("myapp.two_in_one", id: "blk_E", config: %{"path" => "", "value" => ""})

      assert {_members, param_map} = Composite.expand!(block, TwoInOne)

      assert param_map == %{"blk_E_both" => nil, "blk_E_neither" => nil}
    end

    # Sabotage: read `block.config` directly - red on a config that predates
    # a param, where `subtree/1` then substitutes `nil`.
    test "subtree/1 is handed the declaration's defaults under the stored config" do
      block = Block.new("myapp.guarded_step", id: "blk_GS", config: %{})

      assert {[call], _map} = Composite.expand!(block, GuardedStep)
      assert call.config["invoke_type"] == ""
    end

    # Sabotage: dropped the guard - red, because a `Block.new/2` with no `:id`
    # then mints a fresh UXID on every call and the expansion stops being
    # stable, silently.
    test "a local id that looks like a minted UXID is refused" do
      defmodule Minted do
        @moduledoc false
        use StatifierBlocks.Composite,
          name: "myapp.minted",
          params: [%{key: "k", type: :string, label: "K", required?: false, default: ""}]

        @impl StatifierBlocks.Composite
        def subtree(_params), do: [StatifierBlocks.Block.new("core.assign")]
      end

      assert_raise ArgumentError, ~r/UXID/, fn ->
        Composite.expand!(Block.new("myapp.minted", id: "blk_M"), Minted)
      end
    end

    # Sabotage: dropped the uniqueness check - red, because minting is
    # injective per composite and two members would then share one id.
    test "duplicate local ids are refused" do
      defmodule Doubled do
        @moduledoc false
        use StatifierBlocks.Composite,
          name: "myapp.doubled",
          params: [%{key: "k", type: :string, label: "K", required?: false, default: ""}]

        @impl StatifierBlocks.Composite
        def subtree(_params) do
          [
            StatifierBlocks.Block.new("core.assign", id: "a", config: %{}),
            StatifierBlocks.Block.new("core.assign", id: "a", config: %{})
          ]
        end
      end

      assert_raise ArgumentError, ~r/duplicate local ids/, fn ->
        Composite.expand!(Block.new("myapp.doubled", id: "blk_D"), Doubled)
      end
    end

    # Sabotage: allowed a local id carrying "_" at its head - red, because
    # `blk_D` <> "_" <> "_x" mints `blk_D__x`.
    test "a local id that would mint \"__\" is refused" do
      defmodule Separated do
        @moduledoc false
        use StatifierBlocks.Composite,
          name: "myapp.separated",
          params: [%{key: "k", type: :string, label: "K", required?: false, default: ""}]

        @impl StatifierBlocks.Composite
        def subtree(_params),
          do: [StatifierBlocks.Block.new("core.assign", id: "_x", config: %{})]
      end

      assert_raise ArgumentError, ~r/__/, fn ->
        Composite.expand!(Block.new("myapp.separated", id: "blk_S"), Separated)
      end
    end

    # Sabotage: expanded any module with a `subtree/1` - red. Only a module
    # that declared itself a composite has a declaration to expand from.
    test "a module that is not a composite is refused" do
      assert_raise ArgumentError, ~r/not a composite/, fn ->
        Composite.expand!(Block.new("core.assign", id: "blk_A"), StatifierBlocks.Core.Assign)
      end
    end
  end

  # ADR-0002's Note of 2026-09-08, item 3 (RQ-SF039-10): one expansion, two
  # spellings. Each of the four broken-declaration shapes the record lists is
  # asserted BOTH ways here - `{:error, _}` through `expand/2` and a raise
  # through `expand!/2` - because the pair is the ruling, and a shape that
  # raised through one spelling and answered `:ok` through the other would be
  # a second implementation, which is what the record forbids.
  describe "Composite.expand/2 (the tuple spelling)" do
    defmodule EmptySubtree do
      @moduledoc false
      use StatifierBlocks.Composite,
        name: "myapp.empty_subtree",
        params: [%{key: "k", type: :string, label: "K", required?: false, default: ""}]

      @impl StatifierBlocks.Composite
      def subtree(_params), do: []
    end

    defmodule NotABlock do
      @moduledoc false
      use StatifierBlocks.Composite,
        name: "myapp.not_a_block",
        params: [%{key: "k", type: :string, label: "K", required?: false, default: ""}]

      @impl StatifierBlocks.Composite
      def subtree(_params), do: [%{id: "a", type: "core.assign"}]
    end

    defmodule DuplicateIds do
      @moduledoc false
      use StatifierBlocks.Composite,
        name: "myapp.duplicate_ids",
        params: [%{key: "k", type: :string, label: "K", required?: false, default: ""}]

      @impl StatifierBlocks.Composite
      def subtree(_params) do
        [
          StatifierBlocks.Block.new("core.assign", id: "a", config: %{}),
          StatifierBlocks.Block.new("core.assign", id: "a", config: %{})
        ]
      end
    end

    defmodule MintsSeparator do
      @moduledoc false
      use StatifierBlocks.Composite,
        name: "myapp.mints_separator",
        params: [%{key: "k", type: :string, label: "K", required?: false, default: ""}]

      @impl StatifierBlocks.Composite
      def subtree(_params), do: [StatifierBlocks.Block.new("core.assign", id: "_x", config: %{})]
    end

    # Sabotage: had `expand/2` let the raise through instead of rescuing it -
    # red on all four, because the caller that must not raise is the editor's
    # click handler. And, the other way: had `expand!/2` become the wrapper
    # and `expand/2` the raising body - red on every second assertion, because
    # the compiler's Resolve reads the raising spelling and a broken
    # declaration must still be a compile-time raise.
    test "an empty subtree: {:error, _} through expand/2, a raise through expand!/2" do
      block = Block.new("myapp.empty_subtree", id: "blk_E")

      assert {:error, reason} = Composite.expand(block, EmptySubtree)
      assert reason =~ "non-empty list"

      assert_raise ArgumentError, fn -> Composite.expand!(block, EmptySubtree) end
    end

    test "a non-block: {:error, _} through expand/2, a raise through expand!/2" do
      block = Block.new("myapp.not_a_block", id: "blk_N")

      assert {:error, reason} = Composite.expand(block, NotABlock)
      assert reason =~ "non-empty list"

      assert_raise ArgumentError, fn -> Composite.expand!(block, NotABlock) end
    end

    test "a duplicated local id: {:error, _} through expand/2, a raise through expand!/2" do
      block = Block.new("myapp.duplicate_ids", id: "blk_D")

      assert {:error, reason} = Composite.expand(block, DuplicateIds)
      assert reason =~ "duplicate local ids"

      assert_raise ArgumentError, fn -> Composite.expand!(block, DuplicateIds) end
    end

    test "a local id minting \"__\": {:error, _} through expand/2, a raise through expand!/2" do
      block = Block.new("myapp.mints_separator", id: "blk_S")

      assert {:error, reason} = Composite.expand(block, MintsSeparator)
      assert reason =~ "__"

      assert_raise ArgumentError, fn -> Composite.expand!(block, MintsSeparator) end
    end

    # Sabotage: answered the bare pair - red. The ruled return is the tagged
    # tuple over the pair, and this is the breaking part of the change.
    test "a declaration that expands answers {:ok, {blocks, param_map}}" do
      assert {:ok, {[call], param_map}} = Composite.expand(guarded_step("blk_GS"), GuardedStep)

      assert call.id == "blk_GS_call"
      assert param_map == %{"blk_GS_call" => "invoke_type", "blk_GS_guard" => "failure_path"}
    end

    # Sabotage: answered `{:ok, ...}` from a second derivation rather than
    # from `expand!/2` - red, because the two would then be free to disagree.
    test "the :ok payload is exactly what expand!/2 answers" do
      assert {:ok, pair} = Composite.expand(guarded_step("blk_GS"), GuardedStep)
      assert pair == Composite.expand!(guarded_step("blk_GS"), GuardedStep)
    end

    # Sabotage: rescued only the broken-declaration raises - red, because a
    # ref that is not a composite reaches this function from the editor too.
    test "a module that is not a composite is an {:error, _} here" do
      assert {:error, reason} =
               Composite.expand(
                 Block.new("core.assign", id: "blk_A"),
                 StatifierBlocks.Core.Assign
               )

      assert reason =~ "not a composite"
    end
  end

  describe "the environment walk at a composite's one position (RQ-SF037-15)" do
    # Sabotage: answered the composite's own `config_schema/1` - red, because
    # the params declare no path and the walk then says the composite writes
    # nothing while its expansion writes `cards.authorization.failure`.
    test "write_signatures/3 answers the expansion's writes at the composite's position" do
      block = guarded_step("blk_GS")
      document = document([block])

      assert Environment.write_signatures(palette(), document, block) == [
               {"path", "cards.authorization.failure", :unknown}
             ]
    end

    # Sabotage: descended into `block.slots` instead of the expansion - red,
    # because a composite exposes no slot and `block.slots` is empty.
    test "read_signatures/3 answers the expansion's reads" do
      block =
        Block.new("signup.confirm_contact",
          id: "blk_CC",
          config: %{
            "address_from" => "signup.contact.address",
            "confirmed_at" => "signup.contact.confirmed"
          }
        )

      document = document([block])

      assert Environment.read_signatures(palette(), document, block) == [
               {"subject", "signup.contact.address", "string"}
             ]

      assert Environment.write_signatures(palette(), document, block) == [
               {"path", "signup.contact.confirmed", :unknown}
             ]
    end

    # Sabotage: walked the members in `slots`-map order - red, because a map
    # has no order of its own and last-write-wins by position then depends on
    # the hashing.
    test "the union is taken in the expansion's own pre-order" do
      {members, _map} = Composite.expand!(guarded_step("blk_GS"), GuardedStep)

      assert ids(Composite.flatten(members)) == ["blk_GS_call", "blk_GS_guard"]
    end

    # Sabotage: made the arm apply to every block - red on an ordinary block,
    # whose own declarations are what it answers with.
    test "an ordinary block is unaffected" do
      block =
        Block.new("core.assign", id: "blk_A", config: %{"path" => "cards.audit", "value" => "1"})

      document = document([block])

      assert Environment.write_signatures(palette(), document, block) == [
               {"path", "cards.audit", :unknown}
             ]
    end

    # Sabotage: descended a slot - red. There is no slot to step into, no
    # second walk, and no extra position (ADR-0011's Note, section 1).
    test "a composite occupies one position and exposes no slot to descend" do
      block = guarded_step("blk_GS")

      assert block.slots == %{}
      assert GuardedStep.slots(block.config) == []
      assert Assignability.kinds(GuardedStep, block.config) == [:step]
    end
  end

  describe "Composite.io/2 and Composite.outcomes/2 (ADR-0002's Note, item 3)" do
    # Sabotage: resolved the members through `Palette.core()` inside `io/2` and
    # `outcomes/2` -> 3 failures (verified): this test, the outcomes one below
    # and the routed `produces/4`. This is the whole of what arity 2 buys: the
    # SAME derivation, over the palette the reader is holding.
    test "io/2 answers exactly for a composite rooted at a host type" do
      assert Composite.io(palette(), with_deadline()) == %{
               kinds: [:step, :reviewable],
               slot_accepts: %{},
               consumes: "cards.Authorization",
               produces: "cards.AuthorizationResult"
             }
    end

    # Sabotage: routed the callback through the palette too - red. Item 3 is
    # explicit that no callback gains a palette argument, so the fallback the
    # moduledoc documents has to still be `io/1`'s answer.
    test "io/1 keeps the core-only fallback the callback documents" do
      assert AuthorizeWithDeadline.io(%{}) == %{kinds: [:step], slot_accepts: %{}}
    end

    # Sabotage: took the last member's outcomes - red. The root is
    # `myapp.authorizes`, and only a palette carrying it can say so.
    test "outcomes/2 answers the host root's outcomes" do
      assert Composite.outcomes(palette(), with_deadline()) == [
               {"approved", "Approved"},
               {"declined", "Declined"}
             ]
    end

    # Sabotage: as above, on the callback - red. `[{"done", "Done"}]` is
    # `StatifierBlocks.BlockType`'s default for a name the core map does not
    # carry, which is what "falls back" means here.
    test "outcomes/1 keeps the core-only fallback the callback documents" do
      assert AuthorizeWithDeadline.outcomes(%{}) == [{"done", "Done"}]
    end

    # Sabotage: passed the caller's palette to `derived_io/2` - red here,
    # because a composite rooted at `core.*` must answer the same through
    # either door, which is what makes the routing invisible to every existing
    # reference composite.
    test "a composite rooted at core.* answers the same through both doors" do
      block = guarded_step("blk_GS")

      assert Composite.io(palette(), block) == GuardedStep.io(block.config)
      assert Composite.outcomes(palette(), block) == GuardedStep.outcomes(block.config)
    end

    # Sabotage: took the type ref as a second argument instead of resolving it
    # here - red, because then a caller could pair a block with another type's
    # entry and the expansion would be of something else.
    test "io/2 refuses a block whose type the palette does not carry" do
      assert_raise ArgumentError, ~r/is not in the palette/, fn ->
        Composite.io(Palette.new(%{}), with_deadline())
      end
    end

    # Sabotage: dropped the composite check - red. There is nothing to expand,
    # and `expand/2`'s own refusal is the one that says so.
    test "io/2 refuses a block that is not a composite" do
      assert_raise ArgumentError, ~r/is not a composite block type/, fn ->
        Composite.io(palette(), Block.new("core.assign", id: "blk_A"))
      end
    end

    # Sabotage: left `produces/4` reading `io/1` -> 1 failure (verified). That
    # reader HAS a palette, so item 3 says it resolves through it; the second
    # assertion is what it answered before.
    test "Assignability.produces/4 is routed, and read :unknown before" do
      block = with_deadline()

      assert Assignability.produces(palette(), document([block]), block, %{}) ==
               "cards.AuthorizationResult"

      assert Map.get(AuthorizeWithDeadline.io(block.config), :produces, :unknown) == :unknown
    end
  end

  describe "the derived summary/1 (ADR-0002's Note, item 4)" do
    # Sabotage: dropped the `hidden?` rejection -> 2 failures (verified), this
    # one and the `BlockType.summary/3` test, each gaining the hidden param's
    # chip. A param no form renders is not a chip either.
    test "one chip per visible param, minus the hidden ones" do
      assert AuthorizeWithDeadline.summary(with_deadline().config) == [
               "Call: myapp:authorize",
               "Deadline: 2h"
             ]
    end

    # Sabotage: kept a chip for a blank value - red. A label with nothing after
    # it says less than no chip at all.
    test "a param whose value renders blank draws no chip" do
      assert AuthorizeWithDeadline.summary(%{"invoke_type" => "myapp:authorize"}) == [
               "Call: myapp:authorize"
             ]

      assert AuthorizeWithDeadline.summary(%{}) == []
    end

    # Sabotage: derived nothing and left `summary/1` absent - red, because
    # `BlockType.summary/3` decides absence with `Palette.declares?/3` and
    # would answer `[]`.
    test "the chips reach BlockType.summary/3" do
      assert BlockType.summary(AuthorizeWithDeadline, with_deadline().config) == [
               "Call: myapp:authorize",
               "Deadline: 2h"
             ]
    end

    # Sabotage: left `summary: 1` out of `defoverridable` - red: the derived
    # chips win and the declaration cannot say its own card line.
    test "the derivation is overridable" do
      assert OwnSummary.summary(%{"lane" => "capture"}) == ["one lane"]
    end
  end

  describe "the derived recipe" do
    # Sabotage: returned the expansion rather than the composite - red. What
    # an author puts down is the composite; the expansion happens at compile.
    test "insert/2 returns exactly one :insert of the composite block" do
      target = {"blk_ROOT", "body", 0}

      assert {:ok, [{:insert, ^target, block}]} =
               GuardedStep.Recipe.insert(target, document([]))

      assert block.type == "myapp.guarded_step"
      assert block.config == %{"invoke_type" => "", "failure_path" => ""}
      assert block.type_version == 1
    end

    # Sabotage: gave the recipe its own entry - red. The recipe is a
    # compatibility surface for a host mid-migration; it draws what the type
    # draws, and a host that registers both is choosing to show two.
    test "palette_entry/0 is the block type's" do
      assert GuardedStep.Recipe.palette_entry() == GuardedStep.palette_entry()
    end

    # Sabotage: registered the composite in `recipes` only - red. A
    # composite's own palette entry is its `types` entry; the two maps are two
    # namespaces, so a host may register both and draw two entries.
    test "a composite registers in a palette like any other type" do
      registered =
        Palette.new(
          Map.merge(Palette.core_types(), %{"myapp.guarded_step" => GuardedStep}),
          recipes: %{"guarded_step" => GuardedStep.Recipe}
        )

      assert Palette.fetch(registered, "myapp.guarded_step") == {:ok, GuardedStep}
      assert Palette.fetch_recipe(registered, "guarded_step") == {:ok, GuardedStep.Recipe}

      assert {:ok, GuardedStep, resolved} =
               Palette.resolve(registered, guarded_step("blk_GS"))

      assert resolved.id == "blk_GS"
    end
  end

  describe "the declaration is checked where it is written" do
    # Sabotage: accepted a declaration with no `:name` - red, because the
    # derived recipe then has no type name to insert.
    test ":name and :params are required" do
      assert_raise ArgumentError, ~r/:name is required/, fn ->
        Composite.__declaration__(params: [])
      end

      assert_raise ArgumentError, ~r/:params is required/, fn ->
        Composite.__declaration__(name: "myapp.x")
      end
    end

    # Sabotage: accepted a param missing `default:` - red. A param is an
    # ordinary field declaration and F3 refuses a field that writes none.
    test "a param that is not a field declaration is refused" do
      assert_raise ArgumentError, ~r/field declarations/, fn ->
        Composite.__declaration__(name: "myapp.x", params: [%{key: "k"}])
      end
    end

    # Sabotage: defaulted the version to the module's - red, there is none.
    test "the version defaults to 1 and must be positive" do
      assert %{version: 1} = Composite.__declaration__(name: "myapp.x", params: [])

      assert_raise ArgumentError, ~r/positive integer/, fn ->
        Composite.__declaration__(name: "myapp.x", params: [], version: 0)
      end
    end

    # ADR-0002's Note of 2026-09-08, item 5. Sabotage: dropped the unknown-key
    # check - red on both of these, because a misspelling then compiles to the
    # default the author was trying to replace.
    test "an unknown option is refused, naming the key" do
      error =
        assert_raise ArgumentError, fn ->
          Composite.__declaration__(name: "myapp.x", params: [], verison: 2)
        end

      assert error.message =~ ":verison"

      error =
        assert_raise ArgumentError, fn ->
          Composite.__declaration__(name: "myapp.x", params: [], slot: [])
        end

      assert error.message =~ ":slot"
    end

    # Sabotage: named a recognized option in the refused set - red here, since
    # every documented option must still build a declaration.
    test "every documented option is still accepted" do
      declaration =
        Composite.__declaration__(
          name: "myapp.x",
          params: [],
          sentence: "does a thing",
          palette_entry: %{label: "Does a thing"},
          version: 3,
          slots: [%{name: "body", to: {"inner", "body"}}]
        )

      assert declaration.name == "myapp.x"
      assert declaration.sentence == "does a thing"
      assert declaration.palette_entry.label == "Does a thing"
      assert declaration.version == 3
      assert [%{name: "body", to: {"inner", "body"}}] = declaration.slots
    end

    # The refusal a host actually meets is at the `use` site, where the
    # declaration is built at compile time. Sabotage: dropped the unknown-key
    # check - red, the misspelled module compiled.
    test "the refusal is raised at the use site" do
      error =
        assert_raise ArgumentError, fn ->
          Code.eval_quoted(
            quote do
              defmodule MisspelledComposite do
                use StatifierBlocks.Composite,
                  name: "myapp.x",
                  params: [],
                  verison: 2

                @impl StatifierBlocks.Composite
                def subtree(_config), do: []
              end
            end
          )
        end

      assert error.message =~ ":verison"
      refute Code.ensure_loaded?(MisspelledComposite)
    end
  end

  defp ids(blocks), do: Enum.map(blocks, & &1.id)
end
