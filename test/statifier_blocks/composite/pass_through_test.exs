defmodule StatifierBlocks.Composite.PassThroughTest do
  @moduledoc """
  Pass-through slots, on a `use` composite and on a data composite alike:
  ADR-0002's pass-through amendment (P1-P9), ADR-0004's (T1-T4) and
  ADR-0011's section 2 and section 3, all three of which `sb-q183` builds.

  The worked example both records name is the signup domain's **"Guarded
  section"**: a step that calls out and records the failure on its error
  path, and a `core.group` whose `body` slot the composite exposes as its
  own. The author drops a block into that interior; the expansion carries it
  into the group, with its id unchanged.

  Two obligations are asserted rather than argued, and they are the ones the
  campaign is measured on. The SCXML a document holding a filled
  pass-through slot compiles to is byte-identical to the SCXML the same
  document compiles to after `Expand` (T4, consent clause 6), and the same
  declaration held as data expands block for block to the module twin's and
  compiles to the same bytes (P9).

  A pure test. Nothing here names LiveView, so it compiles and runs headless.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{
    Assignability,
    Block,
    Compiler,
    Composite,
    Document,
    Environment,
    Palette
  }

  alias StatifierBlocks.Compiler.Finding
  alias StatifierBlocks.Composite.Data

  # -- "Guarded section", as a module ------------------------------------

  defmodule GuardedSection do
    @moduledoc """
    The amendment's own P8: two params, one declared slot mapped into the
    `body` of the `core.group` the subtree writes as `"then"`.

    Core types throughout, so the expansion compiles and the byte-identity
    obligation can be asserted against real SCXML.
    """

    use StatifierBlocks.Composite,
      name: "myapp.guarded_section",
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
      slots: [%{name: "body", to: {"then", "body"}, label: "Then"}],
      sentence: "Call {invoke_type}, recording failure at {failure_path}",
      palette_entry: %{label: "Guarded section", group: "Structure"},
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
        ),
        Block.new("core.group", id: "then", slots: %{"body" => [], "interrupts" => []})
      ]
    end
  end

  # -- the same composite, held as data ----------------------------------

  @row %{
    "type_name" => "myapp.guarded_section",
    "version" => 1,
    "sentence" => "Call {{invoke_type}}, recording failure at {{failure_path}}",
    "palette_entry" => %{"label" => "Guarded section", "group" => "Structure"},
    "params" => [
      %{
        "key" => "invoke_type",
        "type" => "string",
        "label" => "Call",
        "required?" => true,
        "default" => ""
      },
      %{
        "key" => "failure_path",
        "type" => "string",
        "label" => "Record the failure at",
        "required?" => true,
        "default" => "",
        "datamodel_path?" => true
      }
    ],
    "slots" => %{"body" => %{"to" => ["then", "body"], "label" => "Then"}},
    "subtree" => [
      %{
        "type" => "core.invoke",
        "id_suffix" => "call",
        "config" => %{
          "invoke_type" => %{"$param" => "invoke_type"},
          "assign_to" => "",
          "params" => ""
        },
        "slots" => %{
          "on_error" => [
            %{
              "type" => "core.assign",
              "id_suffix" => "guard",
              "config" => %{"path" => %{"$param" => "failure_path"}, "value" => "failed"}
            }
          ]
        }
      },
      %{
        "type" => "core.group",
        "id_suffix" => "then",
        "slots" => %{"body" => [], "interrupts" => []}
      }
    ]
  }

  # -- the typed half: a host step that writes a record ------------------

  defmodule SignupStep do
    @moduledoc """
    ADR-0011 section 5's `myapp.signup_step`: one write signature, at the
    record type its config names. It is never compiled - the walk is what
    reads it - so `emit/2` refuses rather than emitting.
    """

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: [{"on_error", :zero_or_one, "If it fails"}]

    @impl true
    def config_schema(_config),
      do: [
        %{
          key: "assign_to",
          type: {:path, %{writes: "signup.applicant"}},
          label: "Record the applicant at",
          required?: true,
          default: ""
        }
      ]

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def io(_config), do: %{kinds: [:step], slot_accepts: %{"on_error" => [:step]}}

    @impl true
    def palette_entry, do: %{label: "Signup step"}

    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule Notify do
    @moduledoc "A leaf whose one field READS a path at `string`."

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config),
      do: [
        %{
          key: "to",
          type: {:path, %{expects: "string"}},
          label: "Notify",
          required?: true,
          default: ""
        }
      ]

    @impl true
    def validate_config(_config), do: :ok
    @impl true
    def io(_config), do: %{kinds: [:step]}
    @impl true
    def palette_entry, do: %{label: "Notify"}
    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule Marker do
    @moduledoc "A leaf that WRITES a `string` at the path its config names."

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config),
      do: [
        %{
          key: "at",
          type: {:path, %{writes: "string"}},
          label: "Mark",
          required?: true,
          default: ""
        }
      ]

    @impl true
    def validate_config(_config), do: :ok
    @impl true
    def io(_config), do: %{kinds: [:step]}
    @impl true
    def palette_entry, do: %{label: "Marker"}
    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule TypedSection do
    @moduledoc """
    ADR-0011 section 5's composite: the host step writes the applicant
    record, and the declared `body` slot maps into the group that follows it.
    """

    use StatifierBlocks.Composite,
      name: "myapp.typed_section",
      params: [
        %{
          key: "applicant_path",
          type: :string,
          label: "Record the applicant at",
          required?: true,
          default: "",
          datamodel_path?: true
        }
      ],
      slots: [%{name: "body", to: {"then", "body"}, label: "Then"}],
      version: 1

    alias StatifierBlocks.Block

    @impl StatifierBlocks.Composite
    def subtree(params) do
      [
        Block.new("myapp.signup_step",
          id: "call",
          config: %{"assign_to" => params["applicant_path"]}
        ),
        Block.new("core.group", id: "then", slots: %{"body" => []})
      ]
    end
  end

  @datamodel %{
    "version" => 1,
    "scopes" => [],
    "types" => [
      %{
        "name" => "signup.applicant",
        "kind" => "record",
        "label" => "Applicant",
        "fields" => [
          %{"name" => "email", "type" => "string", "required?" => true},
          %{"name" => "invited_at", "type" => "datetime"}
        ]
      }
    ]
  }

  # -- helpers -----------------------------------------------------------

  defp data_ref do
    {:ok, state} = Data.declaration(@row)
    {Data, state}
  end

  defp module_palette,
    do: Palette.from_modules([{"myapp.guarded_section", GuardedSection}], core: true)

  defp data_palette,
    do: Palette.from_modules([{"myapp.guarded_section", data_ref()}], core: true)

  defp typed_palette do
    Palette.from_modules(
      [
        {"myapp.typed_section", TypedSection},
        {"myapp.signup_step", SignupStep},
        {"myapp.notify", Notify},
        {"myapp.marker", Marker}
      ],
      core: true
    )
  end

  defp section(id, children, invoke_type \\ "myapp:signup") do
    Block.new("myapp.guarded_section",
      id: id,
      config: %{"invoke_type" => invoke_type, "failure_path" => "signup.failure"},
      slots: %{"body" => children}
    )
  end

  defp typed_section(id, children) do
    Block.new("myapp.typed_section",
      id: id,
      config: %{"applicant_path" => "signup.applicant"},
      slots: %{"body" => children}
    )
  end

  defp notify(id, path), do: Block.new("myapp.notify", id: id, config: %{"to" => path})

  defp document(children) do
    Document.new(
      Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => children}),
      id: "bdoc_CANONICAL"
    )
  end

  defmodule NoSlots do
    @moduledoc false
    use StatifierBlocks.Composite, name: "myapp.no_slots", params: [], version: 1

    alias StatifierBlocks.Block

    @impl StatifierBlocks.Composite
    def subtree(_params), do: [Block.new("core.group", id: "then", slots: %{"body" => []})]
  end

  # -- P1, P2, P3: the declaration -----------------------------------------

  describe "P1/P2: the declaration answers slots/1" do
    # Sabotage: left the injected `slots/1` at `[]` - red here and in every
    # card test below it, because the interior the author drops into is drawn
    # from this one answer.
    test "a module composite answers its declared slot, labelled and at :any" do
      assert GuardedSection.slots(%{}) == [{"body", :any, "Then"}]
    end

    # Sabotage: had `Data.slots/2` keep answering `[]` - red. The two kinds
    # read one declaration shape, so they cannot be allowed to disagree.
    test "a data composite answers the same, from the row's declaration-level key" do
      {Data, state} = data_ref()
      assert Data.slots(state, %{}) == [{"body", :any, "Then"}]
    end

    # Sabotage: made `:arity` default to `:one` - red. P1 argues `:any` is
    # the right default because the mapped member's own arity finding already
    # runs on the expanded tree.
    test "the label defaults to the name and the arity to :any" do
      defmodule Bare do
        @moduledoc false
        use StatifierBlocks.Composite,
          name: "myapp.bare",
          params: [],
          slots: [%{name: "body", to: {"then", "body"}}],
          version: 1

        alias StatifierBlocks.Block

        @impl StatifierBlocks.Composite
        def subtree(_params), do: [Block.new("core.group", id: "then", slots: %{"body" => []})]
      end

      assert Bare.slots(%{}) == [{"body", :any, "body"}]
    end

    # Sabotage: dropped the sugar arm from `decode_slot/2` - red. The array
    # is P2's own spelling and the map is the long form of it.
    test "the data row's plain-array sugar spells the same mapping" do
      row = %{@row | "slots" => %{"body" => ["then", "body"]}}

      assert {:ok, state} = Data.declaration(row)
      assert Data.slots(state, %{}) == [{"body", :any, "body"}]
    end

    # Sabotage: kept `slot_accepts` at the literal `%{}` - red. A slot that
    # accepts everything is not the mapped inner slot's answer, and the
    # editor's drop-check reads exactly this map.
    test "P3: slot_accepts answers the mapped inner slot's accepted kinds" do
      %{slot_accepts: accepts} = GuardedSection.io(%{})

      assert accepts == %{
               "body" => Assignability.slot_accepts(StatifierBlocks.Core.Group, %{}, "body")
             }
    end

    # The preservation half of P3, which no mutation of the new code reds on
    # its own: a composite that declares nothing still answers `%{}`, because
    # a composite still carries no interior of its own.
    test "a composite declaring no slot still answers slot_accepts as %{}" do
      assert %{slot_accepts: %{}} = NoSlots.io(%{})
    end
  end

  # -- P4: the splice ------------------------------------------------------

  describe "P4: expand/2 splices the children into the mapped inner slot" do
    # Sabotage: minted the spliced children along with the members - red on
    # the id, which T2 is entirely about: a rewritten id moves every state id
    # below it and breaks a host's saved selections.
    test "the children land in the mapped inner slot, ids unchanged" do
      block = section("blk_GX", [notify("blk_notify", "signup.applicant.email")])

      {[_call, group], _param_map} = Composite.expand!(block, GuardedSection)

      assert group.id == "blk_GX_then"
      assert [%Block{id: "blk_notify"}] = group.slots["body"]
    end

    # Sabotage: had the splice write the children into every slot key the
    # member carries rather than the mapped one - red, because the group's
    # `interrupts` rail then holds the author's step as well. The subtree
    # writes both keys for exactly this reason.
    test "only the mapped inner slot is written" do
      child = notify("blk_notify", "signup.applicant.email")
      block = section("blk_GX", [child])

      {[_call, group], _param_map} = Composite.expand!(block, GuardedSection)

      assert group.slots == %{"body" => [child], "interrupts" => []}
    end

    # Sabotage: had the splice write `nil` into the mapped slot when the
    # author filled nothing - red. P4: an unfilled slot splices nothing and
    # the mapped inner slot is left as the subtree wrote it.
    test "an unfilled declared slot splices nothing" do
      {[_call, group], _param_map} = Composite.expand!(section("blk_GX", []), GuardedSection)

      assert group.slots == %{"body" => [], "interrupts" => []}
    end

    # Sabotage: took the param map over the spliced tree - red. This is
    # ADR-0004 T3's mechanism: the expansion index maps expansion MEMBERS
    # only, and the param map is what the compiler builds it from.
    test "T3: the param map names the minted members and no spliced child" do
      block = section("blk_GX", [notify("blk_notify", "signup.applicant.email")])

      {_members, param_map} = Composite.expand!(block, GuardedSection)

      assert Map.keys(param_map) |> Enum.sort() == ["blk_GX_call", "blk_GX_guard", "blk_GX_then"]
    end

    # Sabotage: derived the minted target id in `Environment` rather than
    # through this function - red the moment `mint_id/3`'s separator moved,
    # which is the second implementation the function exists to prevent.
    test "pass_through/2 answers the mapping, minted" do
      block = section("blk_GX", [])

      assert Composite.pass_through(block, GuardedSection) == %{
               "body" => {"blk_GX_then", "body"}
             }

      assert Composite.pass_through(block, NoSlots) == %{}
    end
  end

  # -- P5: the three declaration errors ------------------------------------

  describe "P5: a mapping that does not fit its own subtree is refused" do
    # Sabotage: skipped `check_mapping!/3` for an unknown local id - red at
    # the splice instead, silently, with the children dropped on the floor.
    test "a module composite raises at expansion on an unknown local id" do
      defmodule UnknownId do
        @moduledoc false
        use StatifierBlocks.Composite,
          name: "myapp.unknown_id",
          params: [],
          slots: [%{name: "body", to: {"nowhere", "body"}}],
          version: 1

        alias StatifierBlocks.Block

        @impl StatifierBlocks.Composite
        def subtree(_params), do: [Block.new("core.group", id: "then", slots: %{"body" => []})]
      end

      assert_raise ArgumentError, ~r/no local id of the subtree/, fn ->
        Composite.expand!(Block.new("myapp.unknown_id", id: "blk_U"), UnknownId)
      end
    end

    # Sabotage: treated a missing key as an empty slot - red. P5's second
    # error is deliberate: the declaration author states where the children
    # go, in the subtree, where the mapping can be checked without a palette.
    test "a module composite raises on an inner slot the subtree does not write" do
      defmodule UnwrittenSlot do
        @moduledoc false
        use StatifierBlocks.Composite,
          name: "myapp.unwritten_slot",
          params: [],
          slots: [%{name: "body", to: {"then", "body"}}],
          version: 1

        alias StatifierBlocks.Block

        @impl StatifierBlocks.Composite
        def subtree(_params), do: [Block.new("core.group", id: "then")]
      end

      assert_raise ArgumentError, ~r/which the subtree does not write/, fn ->
        Composite.expand!(Block.new("myapp.unwritten_slot", id: "blk_U"), UnwrittenSlot)
      end
    end

    # Sabotage: merged the author's children after the subtree's - red. T1
    # fixes that the mapped inner slot "holds them and only them", and two
    # authors writing one list has no rule for the order.
    test "a module composite raises on a mapped inner slot the subtree also fills" do
      defmodule AlsoFilled do
        @moduledoc false
        use StatifierBlocks.Composite,
          name: "myapp.also_filled",
          params: [],
          slots: [%{name: "body", to: {"then", "body"}}],
          version: 1

        alias StatifierBlocks.Block

        @impl StatifierBlocks.Composite
        def subtree(_params) do
          [
            Block.new("core.group",
              id: "then",
              slots: %{"body" => [Block.new("core.assign", id: "seeded", config: %{})]}
            )
          ]
        end
      end

      assert_raise ArgumentError, ~r/which the subtree also fills/, fn ->
        Composite.expand!(Block.new("myapp.also_filled", id: "blk_U"), AlsoFilled)
      end
    end

    # Sabotage: dropped `refute_duplicates!/2` - red. Two declared slots
    # mapping to one inner slot is the same refusal for the same reason.
    test "two declared slots mapping to one inner slot are refused, as is a duplicate name" do
      assert_raise ArgumentError, ~r/more than once/, fn ->
        defmodule TwoToOne do
          @moduledoc false
          use StatifierBlocks.Composite,
            name: "myapp.two_to_one",
            params: [],
            slots: [
              %{name: "a", to: {"then", "body"}},
              %{name: "b", to: {"then", "body"}}
            ],
            version: 1

          @impl StatifierBlocks.Composite
          def subtree(_params), do: []
        end
      end

      assert_raise ArgumentError, ~r/more than once/, fn ->
        defmodule DuplicateName do
          @moduledoc false
          use StatifierBlocks.Composite,
            name: "myapp.duplicate_name",
            params: [],
            slots: [
              %{name: "body", to: {"then", "body"}},
              %{name: "body", to: {"else", "body"}}
            ],
            version: 1

          @impl StatifierBlocks.Composite
          def subtree(_params), do: []
        end
      end
    end

    # Sabotage: left the data kind to raise at its first expansion like the
    # module kind - red. `declaration/1` is "the last moment a malformed
    # declaration can be refused", and a static template is all three checks.
    test "a data composite answers all three as declaration errors" do
      for {slots, pattern} <- [
            {%{"body" => ["nowhere", "body"]}, ~r/no local id of the subtree/},
            {%{"body" => ["call", "missing"]}, ~r/which the subtree does not write/},
            {%{"body" => ["call", "on_error"]}, ~r/which the subtree also fills/}
          ] do
        assert {:error, messages} = Data.declaration(%{@row | "slots" => slots})
        assert Enum.any?(messages, &(&1 =~ pattern)), "accepted #{inspect(slots)}"
      end
    end

    # Sabotage: accepted a slot value that is neither the array nor a map
    # with `"to"` - red, because a malformed row then decodes to a mapping
    # nothing can splice.
    test "a data composite refuses a slot value in no admitted shape" do
      assert {:error, messages} = Data.declaration(%{@row | "slots" => %{"body" => "then.body"}})
      assert Enum.any?(messages, &(&1 =~ ~s(must map to [local_id, inner_slot])))

      assert {:error, [message]} = Data.declaration(%{@row | "slots" => ["body"]})
      assert message =~ ~s("slots" must be a map)
    end
  end

  # -- T1/T4: the compile, and the bytes -----------------------------------

  describe "T1/T4: the compiled bytes are the same before and after Expand" do
    # Sabotage: had `expand/2` answer the subtree without the splice - red,
    # because the author's block then vanishes from the chart entirely. This
    # is consent clause 6's obligation, asserted.
    test "a document holding a filled pass-through slot compiles to the expanded bytes" do
      block =
        section("blk_GX", [
          Block.new("core.send", id: "blk_notify", config: %{"event" => "signup.done"})
        ])

      {members, _param_map} = Composite.expand!(block, GuardedSection)

      assert {:ok, composed} = Compiler.compile(document([block]), module_palette())
      assert {:ok, expanded} = Compiler.compile(document(members), module_palette())

      assert composed.scxml == expanded.scxml
      assert composed.provenance == expanded.provenance
      assert composed.invoke_types == expanded.invoke_types
    end

    # Sabotage: minted the child's id after all - red here first, because the
    # state id the chart carries is `"s_" <> block_id` and a rewritten id is
    # visible in the bytes.
    test "T2: the spliced child's state id is the one it would have had anyway" do
      block =
        section("blk_GX", [
          Block.new("core.send", id: "blk_notify", config: %{"event" => "signup.done"})
        ])

      assert {:ok, compiled} = Compiler.compile(document([block]), module_palette())

      assert compiled.scxml =~ "s_blk_notify"
      assert compiled.scxml =~ "s_blk_GX_then"
      refute compiled.scxml =~ "s_blk_GX_notify"
    end

    # Sabotage: kept building the expansion index from `Composite.flatten/1` -
    # red. T3: a finding whose owner is a pass-through child is reported
    # against that child, with that child's own `config_key`.
    test "T3: a finding on a spliced child is the child's own, not the composite's" do
      child =
        Block.new("core.invoke",
          id: "blk_notify",
          config: %{"invoke_type" => "myapp:capture", "assign_to" => "", "params" => ""}
        )

      assert {:ok, compiled} =
               Compiler.compile(document([section("blk_GX", [child])]), module_palette(),
                 known_invoke_types: MapSet.new(["myapp:signup"])
               )

      assert [%Finding{} = warning] = compiled.warnings
      assert warning.block_id == "blk_notify"
      assert warning.config_key == nil
    end

    # Sabotage: excluded the minted members from the index along with the
    # children - red, because E3's re-anchoring is unchanged for a member the
    # author cannot see and the two arms stay the two arms they are.
    test "T3: a finding on a minted member is still re-anchored onto the composite" do
      block = section("blk_GX", [], "myapp:capture")

      assert {:ok, compiled} =
               Compiler.compile(document([block]), module_palette(),
                 known_invoke_types: MapSet.new(["myapp:signup"])
               )

      assert [%Finding{} = warning] = compiled.warnings
      assert warning.block_id == "blk_GX"
      assert warning.config_key == "invoke_type"
    end
  end

  # -- P9: the data twin ---------------------------------------------------

  describe "P9: the same declaration held as data" do
    # Sabotage: had `__composite__/1` drop the `:slots` key - red, because
    # `expand/2` then reads no mapping and the data kind silently loses the
    # children the module kind carries.
    test "the same expansion, block for block" do
      block = section("blk_GX", [notify("blk_notify", "signup.applicant.email")])

      assert Composite.expand!(block, GuardedSection) == Composite.expand!(block, data_ref())
    end

    # Sabotage: registered the data twin's slots under the node-level key -
    # red on the bytes, which is the property consent clause 6 names for the
    # two kinds as well as for the two sides of Expand.
    test "the same compiled bytes" do
      block =
        section("blk_GX", [
          Block.new("core.send", id: "blk_notify", config: %{"event" => "signup.done"})
        ])

      assert {:ok, from_module} = Compiler.compile(document([block]), module_palette())
      assert {:ok, from_data} = Compiler.compile(document([block]), data_palette())

      assert from_module.scxml == from_data.scxml
      assert from_module.provenance == from_data.provenance
    end

    # Sabotage: had `Data.__composite__/1` drop the `:slots` key - red,
    # because the data kind then splices nothing and its own hand-expansion
    # is a different document. T4's obligation holds for both kinds, and
    # asserting it only across the two would leave that untested.
    test "T4 holds for the data kind against its own hand-expansion" do
      block =
        section("blk_GX", [
          Block.new("core.send", id: "blk_notify", config: %{"event" => "signup.done"})
        ])

      {members, _param_map} = Composite.expand!(block, data_ref())

      assert {:ok, composed} = Compiler.compile(document([block]), data_palette())
      assert {:ok, expanded} = Compiler.compile(document(members), data_palette())

      assert composed.scxml == expanded.scxml
      assert composed.provenance == expanded.provenance
    end
  end

  # -- ADR-0011 sections 2 and 3: the walk ---------------------------------

  describe "ADR-0011 section 2: the walk descends at the mapped inner position" do
    # Sabotage: left `slot_start/6` answering the environment reaching the
    # composite - red. The child then reads a path nothing put an entry at,
    # which is clause 11e's `:info` and tells the author nothing.
    test "the child is read against the environment inside the mapped member" do
      document =
        document([typed_section("blk_GX", [notify("blk_notify", "signup.applicant.email")])])

      env =
        Environment.at(typed_palette(), document, {"blk_GX", "body", 0}, %{datamodel: @datamodel})

      assert env["signup.applicant"] == "signup.applicant"
      assert env["signup.applicant.email"] == "string"
      assert env["signup.applicant.invited_at"] == "datetime"
    end

    # Sabotage: applied the composite's writes to the slot's start rather
    # than walking the expansion - red, because the environment reaching the
    # composite holds neither path.
    test "the environment reaching the composite holds neither path" do
      document =
        document([typed_section("blk_GX", [notify("blk_notify", "signup.applicant.email")])])

      env =
        Environment.at(typed_palette(), document, {"blk_ROOT", "body", 0}, %{
          datamodel: @datamodel
        })

      refute Map.has_key?(env, "signup.applicant")
    end

    # Sabotage: kept the fold but dropped the read check - red. A read the
    # walk satisfies only because it descended at the mapped position is the
    # whole of section 2's worked example.
    test "a child's read of the produced path is satisfied" do
      document =
        document([typed_section("blk_GX", [notify("blk_notify", "signup.applicant.email")])])

      assert Assignability.validate(typed_palette(), document, %{datamodel: @datamodel}) == :ok
    end

    # Sabotage: attributed the finding to the composite, as section 4 of the
    # 2026-09-07 Note does for expansion content - red. Section 3: a block
    # the author placed carries its own finding, on the field they filled.
    test "section 3: a failing child read is the child's own finding" do
      document =
        document([typed_section("blk_GX", [notify("blk_notify", "signup.applicant.invited_at")])])

      assert {:error, findings} =
               Assignability.validate(typed_palette(), document, %{datamodel: @datamodel})

      assert findings == [
               {:type_mismatch, "blk_notify", "blk_GX_call", "datetime", "string",
                "signup.applicant.invited_at"}
             ]
    end

    # Two sabotages, one per half. Had `slot_start/6` answer `env` rather
    # than `%{}` for an undeclared key - red, because the walk then descends
    # it from the environment reaching the composite, where
    # `signup.applicant.invited_at` holds `datetime` and the read wanting
    # `string` is a mismatch. Dropped `declared_only/3` from `arms/5` - red
    # on the marker, because the stray key is then an arm holding nothing and
    # decision 4's merge downgrades every path the other arm alone holds. A
    # slot key the declaration does not declare is not a pass-through slot,
    # carries no mapping, and the walk reaches nothing through it.
    test "an undeclared slot key on a composite is not descended" do
      writer =
        Block.new("myapp.signup_step", id: "blk_W", config: %{"assign_to" => "signup.applicant"})

      marker = Block.new("myapp.marker", id: "blk_M", config: %{"at" => "signup.marker"})

      stray =
        Block.new("myapp.typed_section",
          id: "blk_GX",
          config: %{"applicant_path" => "signup.applicant"},
          slots: %{
            "body" => [notify("blk_body", "signup.applicant.email")],
            "stray" => [notify("blk_notify", "signup.applicant.invited_at")]
          }
        )

      document = document([writer, marker, stray])

      assert Assignability.validate(typed_palette(), document, %{datamodel: @datamodel}) == :ok

      # and the stray key is not an ARM either: an arm contributing nothing
      # would empty decision 4's merge, and the path the marker wrote before
      # the composite would not survive it.
      after_it =
        Environment.at(typed_palette(), document, {"blk_ROOT", "body", 3}, %{
          datamodel: @datamodel
        })

      assert after_it["signup.marker"] == "string"
      assert after_it["signup.applicant.invited_at"] == "datetime"
    end
  end
end
