defmodule StatifierBlocks.Composite.CollapseTest do
  @moduledoc """
  `StatifierBlocks.Composite.Collapse`: the arrangement an author built by
  hand, read back as the declaration that stands for it (ADR-0005 part
  (iii) as amended 2026-09-07, clauses `15E` to `20E`; filed with
  `sb-uzly`).

  Two load-bearing properties, and everything else here is a refusal.

  The first is **byte identity**: the declaration a collapse proposes,
  named and registered, expands to the same blocks and compiles to the same
  bytes as the `use`-composite twin of the same shape - with the twin
  written with the `id_suffix`es `18E`'s minting rule produces, which is the
  consequence `18E` states rather than leaves to be found.

  The second is that **the proposer writes nothing**: it takes a document
  and answers a map, and the document it was given is the document it
  leaves.

  Both worked examples are ADR-0005's own, in the signup domain: "Guarded
  step" collapsed, and "Guarded section" - the same arrangement with its
  inner `on_error` slot left unfilled, proposing a pass-through slot.

  A pure test. Nothing here names LiveView, so it compiles and runs
  headless.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, Composite, Document, Edit, Palette}
  alias StatifierBlocks.Composite.{Collapse, Data}

  # -- the arrangement the author built ----------------------------------

  defp guarded_step_arrangement do
    Block.new("core.invoke",
      id: "blk_7",
      config: %{"invoke_type" => "myapp:signup", "assign_to" => ""},
      slots: %{
        "on_error" => [
          Block.new("core.assign",
            id: "blk_9",
            config: %{"path" => "signup.verification.failure", "value" => "failed"}
          )
        ]
      }
    )
  end

  defp guarded_section_arrangement do
    Block.new("core.invoke",
      id: "blk_7",
      config: %{"invoke_type" => "myapp:signup", "assign_to" => ""},
      slots: %{"on_error" => []}
    )
  end

  defp document(blocks) when is_list(blocks) do
    Document.new(Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => blocks}),
      id: "bdoc_SIGNUP"
    )
  end

  defp document(block), do: document([block])

  defp propose(document, ids, opts \\ []),
    do: Collapse.propose(document, Palette.core(), ids, opts)

  # -- 15E: the storable row, minus its name -----------------------------

  describe "propose/3 answers the storable row without its name" do
    # Sabotage: had `propose/3` mint `"type_name" => block.type` - red. A
    # type name is a key in the HOST's palette namespace and a package that
    # minted one would be minting a collision it cannot see, so the row is
    # not a declaration until the host has performed the naming.
    test "no type_name, no sentence, no palette_entry, and version 1" do
      {:ok, row} = propose(document(guarded_step_arrangement()), ["blk_7", "blk_9"])

      refute Map.has_key?(row, "type_name")
      refute Map.has_key?(row, "sentence")
      refute Map.has_key?(row, "palette_entry")
      assert row["version"] == 1
      assert Map.keys(row) |> Enum.sort() == ["params", "subtree", "version"]
    end

    # Sabotage: dropped the `"type_name"` refusal from `Data.declaration/1`
    # - red. The refusal IS the seam: it is what makes naming the host's act
    # rather than a step a package could have skipped.
    test "Data.declaration/1 refuses the row until the host names it" do
      {:ok, row} = propose(document(guarded_step_arrangement()), ["blk_7", "blk_9"])

      assert {:error, errors} = Data.declaration(row)
      assert Enum.any?(errors, &(&1 =~ ~s("type_name")))
      assert {:ok, _state} = Data.declaration(Map.put(row, "type_name", "myapp.guarded_step"))
    end

    # Sabotage: made `propose/3` commit the compound `replacement/4` builds
    # - red. The gesture edits no document and the package persists nothing
    # (16E, epic ruling R5), which is a property of the PROPOSER before it is
    # a property of the editor that calls it.
    test "the document it was given is the document it leaves" do
      document = document(guarded_step_arrangement())

      assert {:ok, _row} = propose(document, ["blk_7", "blk_9"])
      assert document == document(guarded_step_arrangement())
    end
  end

  # -- the worked example, clause by clause ------------------------------

  describe "the Guarded step worked example" do
    # Sabotage: carried a marked value as a literal instead of a placeholder
    # - red. This is ADR-0005's own worked example transcribed, so it is the
    # one test that fails if any of 15E, 18E, 19E or 20E is read differently
    # from the record.
    test "the marked collapse is the record's row, key for key" do
      {:ok, row} =
        propose(document(guarded_step_arrangement()), ["blk_7", "blk_9"],
          marks: %{"blk_7" => ["invoke_type"], "blk_9" => ["path"]}
        )

      assert row == %{
               "version" => 1,
               "params" => [
                 %{
                   "key" => "invoke_type",
                   "type" => "string",
                   "label" => "Invoke type",
                   "required?" => true,
                   "default" => "myapp:signup"
                 },
                 %{
                   "key" => "path",
                   "type" => "string",
                   "label" => "Write to",
                   "required?" => true,
                   "datamodel_path?" => true,
                   "default" => "signup.verification.failure"
                 }
               ],
               "subtree" => [
                 %{
                   "type" => "core.invoke",
                   "id_suffix" => "invoke",
                   "config" => %{
                     "invoke_type" => %{"$param" => "invoke_type"},
                     "assign_to" => ""
                   },
                   "slots" => %{
                     "on_error" => [
                       %{
                         "type" => "core.assign",
                         "id_suffix" => "assign",
                         "config" => %{
                           "path" => %{"$param" => "path"},
                           "value" => "failed"
                         }
                       }
                     ]
                   }
                 }
               ]
             }
    end

    # Sabotage: minted the suffix from the block's id - red. A document id is
    # arbitrary (`blk_7`) and need not match `@id_suffix`; a type segment
    # always does.
    test "id_suffix is minted from the type segment, with a positional discriminator" do
      arrangement =
        Block.new("core.sequence",
          id: "blk_1",
          slots: %{
            "body" => [
              Block.new("core.assign", id: "blk_2", config: %{"path" => "a", "value" => "1"}),
              Block.new("core.assign", id: "blk_3", config: %{"path" => "b", "value" => "2"}),
              Block.new("core.assign", id: "blk_4", config: %{"path" => "c", "value" => "3"})
            ]
          }
        )

      {:ok, row} = propose(document(arrangement), ["blk_1", "blk_2", "blk_3", "blk_4"])

      assert [%{"id_suffix" => "sequence", "slots" => %{"body" => body}}] = row["subtree"]
      assert Enum.map(body, & &1["id_suffix"]) == ["assign", "assign_2", "assign_3"]
    end

    # Sabotage: dropped the collision rule and left every param on its bare
    # key - red on `Data.declaration/1`, which refuses duplicate param keys.
    # Two `core.assign`s in one arrangement is a perfectly ordinary thing to
    # want to save, so refusing it was never the answer (18E).
    test "colliding param keys take <id_suffix>_<field key> and the rest keep theirs" do
      arrangement =
        Block.new("core.sequence",
          id: "blk_1",
          slots: %{
            "body" => [
              Block.new("core.assign", id: "blk_2", config: %{"path" => "a", "value" => "1"}),
              Block.new("core.assign", id: "blk_3", config: %{"path" => "b", "value" => "1"})
            ]
          }
        )

      {:ok, row} =
        propose(document(arrangement), ["blk_1", "blk_2", "blk_3"],
          marks: %{"blk_2" => ["path", "value"], "blk_3" => ["path"]}
        )

      assert Enum.map(row["params"], & &1["key"]) == ["assign_path", "value", "assign_2_path"]
      assert {:ok, _state} = Data.declaration(Map.put(row, "type_name", "myapp.two_assigns"))
    end

    # Sabotage: marked every value rather than the ones that differ - red.
    # A value left at its field's default is a value the author never chose,
    # and a param whose default is the field's default parameterises nothing.
    test "with nothing marked, every value differing from its field default is a param" do
      {:ok, row} = propose(document(guarded_step_arrangement()), ["blk_7", "blk_9"])

      assert Enum.map(row["params"], & &1["key"]) == ["invoke_type", "path", "value"]
      refute "assign_to" in Enum.map(row["params"], & &1["key"])
    end

    # Sabotage: made `substitute/2` the escape's only reader and dropped the
    # wrap - red. A config value that genuinely IS a one-key `"$param"` map
    # would otherwise be substituted at expansion time.
    test "a config value that is itself a placeholder map is escaped" do
      arrangement =
        Block.new("core.assign",
          id: "blk_2",
          config: %{"path" => "a", "value" => %{"$param" => "not a param"}}
        )

      {:ok, row} = propose(document(arrangement), ["blk_2"], marks: %{"blk_2" => ["path"]})

      assert [%{"config" => config}] = row["subtree"]
      assert config["value"] == %{"$literal" => %{"$param" => "not a param"}}
    end
  end

  # -- 12E: exactly one subtree under one parent -------------------------

  describe "12E stands: exactly one subtree under one parent" do
    # Sabotage: took the first id as the root and ignored the rest - red on
    # both arms. A composite takes one position, so a selection that is two
    # roots has no position to take.
    test "two siblings are refused" do
      arrangement =
        Block.new("core.sequence",
          id: "blk_1",
          slots: %{
            "body" => [
              Block.new("core.assign", id: "blk_2", config: %{"path" => "a", "value" => "1"}),
              Block.new("core.assign", id: "blk_3", config: %{"path" => "b", "value" => "2"})
            ]
          }
        )

      assert {:error, {:not_one_subtree, ["blk_2", "blk_3"]}} =
               propose(document(arrangement), ["blk_2", "blk_3"])
    end

    # Sabotage: dropped the whole-subtree check and kept only the
    # one-root check - red. A partial subtree with a child left outside is
    # the case the one-root check alone admits.
    test "a partial subtree with a child left outside is refused" do
      assert {:error, {:not_one_subtree, ["blk_7"]}} =
               propose(document(guarded_step_arrangement()), ["blk_7"])
    end

    test "an empty selection and an id the document does not hold are refused" do
      document = document(guarded_step_arrangement())

      assert {:error, {:not_one_subtree, []}} = propose(document, [])
      assert {:error, {:no_such_block, "blk_NOPE"}} = propose(document, ["blk_NOPE"])
    end

    # Sabotage: let the root through - red. The root has no target a
    # composite could take, which is the same ground Expand refuses it on.
    test "the document root is refused" do
      document = document([])

      assert {:error, {:cannot_collapse_root, "blk_ROOT"}} = propose(document, ["blk_ROOT"])
    end
  end

  # -- 19E: all nine field kinds have a spelling -------------------------

  describe "19E: the four option-carrying kinds round-trip through declaration/1" do
    # Sabotage: spelled `{:select, choices}` as a JSON object - red, because
    # an object does not promise the order the control draws in.
    test "select's choices are ordered [value, label] pairs" do
      {:ok, row} =
        propose(
          document(
            Block.new("core.parallel",
              id: "blk_2",
              config: %{"lanes" => ["ok"], "complete" => "first"}
            )
          ),
          ["blk_2"],
          marks: %{"blk_2" => ["complete"]}
        )

      assert [%{"key" => "complete", "type" => "select", "options" => %{"choices" => choices}}] =
               row["params"]

      assert Enum.all?(
               choices,
               &match?([value, label] when is_binary(value) and is_binary(label), &1)
             )

      assert {:ok, state} = Data.declaration(Map.put(row, "type_name", "myapp.joined"))
      assert [%{key: "complete", type: {:select, decoded}}] = state.params
      assert decoded == Enum.map(choices, fn [value, label] -> {value, label} end)
    end

    # Sabotage: spelled `{:path, opts}` inside a wrapper key - red. `path_opts`
    # is already a map with two optional keys and there is nothing to
    # translate, which is why the options ARE the map.
    test "path's options are the map itself, empty where the field declares neither key" do
      {:ok, row} =
        propose(
          document(
            Block.new("core.invoke",
              id: "blk_7",
              config: %{"invoke_type" => "myapp:signup", "assign_to" => "signup.answer"}
            )
          ),
          ["blk_7"],
          marks: %{"blk_7" => ["assign_to"]}
        )

      assert [%{"key" => "assign_to", "type" => "path", "options" => %{}}] = row["params"]

      assert {:ok, state} = Data.declaration(Map.put(row, "type_name", "myapp.called"))
      assert [%{key: "assign_to", type: {:path, %{}}}] = state.params
    end

    # Sabotage: made the inner spelling a bare type name rather than the
    # same `"type"` / `"options"` pair - red one level down, which is where
    # an unspellable inner kind has to be refused by the ordinary rule.
    test "list recurses through the same spelling" do
      {:ok, row} =
        propose(
          document(Block.new("core.parallel", id: "blk_2", config: %{"lanes" => ["ok"]})),
          ["blk_2"],
          marks: %{"blk_2" => ["lanes"]}
        )

      assert [%{"key" => "lanes", "type" => "list", "options" => options}] = row["params"]
      assert options == %{"inner" => %{"type" => "string"}}

      assert {:ok, state} = Data.declaration(Map.put(row, "type_name", "myapp.fanned"))
      assert [%{key: "lanes", type: {:list, :string}}] = state.params
    end

    # Sabotage: reached for a `statifier_datamodel` arm to carry the value -
    # red, and wrong besides: the value a `{:type_expr, opts}` field holds is
    # already JSON, so the spelling carries `opts` and nothing crosses a
    # package boundary (RQ-SF038-2, sd OUT).
    test "type_expr spells its arms and allow_empty? and needs no datamodel arm" do
      {:ok, row} =
        propose(
          document(
            Block.new("core.on_event",
              id: "blk_2",
              config: %{"event" => "signup.submitted", "payload" => "SignupSubmitted"}
            )
          ),
          ["blk_2"],
          marks: %{"blk_2" => ["payload"]}
        )

      assert [%{"key" => "payload", "type" => "type_expr", "options" => options}] = row["params"]
      assert options["arms"] == ["name", "inline"]

      assert {:ok, state} = Data.declaration(Map.put(row, "type_name", "myapp.heard"))
      assert [%{key: "payload", type: {:type_expr, %{arms: [:name, :inline]}}}] = state.params
    end

    # Sabotage: refused by arrangement rather than by field - red. "This
    # arrangement cannot be saved" is not actionable; "the `collect` field on
    # `blk_2` cannot be saved" is - the author can go and look at it.
    test "a value no spelling carries is refused by block id and field key" do
      arrangement =
        Block.new("core.map",
          id: "blk_2",
          config: %{
            "items" => "signup.applicants",
            "collect" => "signup.answers",
            "collect_type" => "Answer"
          }
        )

      assert {:error, {:unspellable_field, "blk_2", "collect"}} =
               propose(document(arrangement), ["blk_2"], marks: %{"blk_2" => ["collect"]})
    end
  end

  # -- 20E: an unfilled slot is proposed as a pass-through slot ----------

  describe "20E: the Guarded section worked example" do
    # Sabotage: refused the selection the way 13E did - red. 13E's premise
    # was that a composite had no slots to expose an opening through, and
    # SF038 removes that premise.
    test "an unfilled slot is admitted and proposed as a pass-through slot" do
      {:ok, row} =
        propose(document(guarded_section_arrangement()), ["blk_7"],
          marks: %{"blk_7" => ["invoke_type"]}
        )

      assert row["slots"] == %{"on_error" => ["invoke", "on_error"]}

      assert [
               %{
                 "id_suffix" => "invoke",
                 "slots" => %{"on_error" => []},
                 "config" => %{"invoke_type" => %{"$param" => "invoke_type"}}
               }
             ] = row["subtree"]
    end

    # Sabotage: hoisted a filled slot's children out into a proposed slot -
    # red. A Collapse that silently turned a filled slot into an opening
    # would be deciding for the author that the blocks they put there were an
    # example rather than the thing.
    test "a filled slot is not proposed and its children are not lifted" do
      {:ok, row} =
        propose(document(guarded_step_arrangement()), ["blk_7", "blk_9"],
          marks: %{"blk_7" => ["invoke_type"]}
        )

      refute Map.has_key?(row, "slots")
      assert [%{"slots" => %{"on_error" => [%{"type" => "core.assign"}]}}] = row["subtree"]
    end

    # Sabotage: capped the proposal at one slot - red. Nothing in 12E or in
    # the pass-through shape counts them, and a rule admitting one and
    # refusing two would be an arbitrary line.
    test "more than one unfilled slot proposes more than one, with no cap" do
      arrangement =
        Block.new("core.sequence",
          id: "blk_1",
          slots: %{
            "body" => [
              Block.new("core.invoke",
                id: "blk_7",
                config: %{"invoke_type" => "myapp:signup", "assign_to" => ""},
                slots: %{"on_error" => []}
              ),
              Block.new("core.invoke",
                id: "blk_8",
                config: %{"invoke_type" => "myapp:capture", "assign_to" => ""},
                slots: %{"on_error" => []}
              )
            ]
          }
        )

      {:ok, row} = propose(document(arrangement), ["blk_1", "blk_7", "blk_8"])

      assert row["slots"] == %{
               "invoke_on_error" => ["invoke", "on_error"],
               "invoke_2_on_error" => ["invoke_2", "on_error"]
             }
    end
  end

  # -- the byte identity, against the twin 18E's rule mints --------------

  defmodule GuardedStep do
    @moduledoc """
    The `use`-composite twin of the collapsed "Guarded step", written with
    the `id_suffix`es `18E`'s minting rule produces - `invoke` and `assign`
    rather than ADR-0002's authored `call` and `guard`, which is the
    consequence `18E` states.
    """

    use StatifierBlocks.Composite,
      name: "myapp.guarded_step",
      params: [
        %{
          key: "invoke_type",
          type: :string,
          label: "Invoke type",
          required?: true,
          default: "myapp:signup"
        },
        %{
          key: "path",
          type: :string,
          label: "Write to",
          required?: true,
          datamodel_path?: true,
          default: "signup.verification.failure"
        }
      ],
      version: 1

    alias StatifierBlocks.Block

    @impl StatifierBlocks.Composite
    def subtree(params) do
      [
        Block.new("core.invoke",
          id: "invoke",
          config: %{"invoke_type" => params["invoke_type"], "assign_to" => ""},
          slots: %{
            "on_error" => [
              Block.new("core.assign",
                id: "assign",
                config: %{"path" => params["path"], "value" => "failed"}
              )
            ]
          }
        )
      ]
    end
  end

  describe "the collapsed declaration and its use-composite twin" do
    setup do
      {:ok, row} =
        propose(document(guarded_step_arrangement()), ["blk_7", "blk_9"],
          marks: %{"blk_7" => ["invoke_type"], "blk_9" => ["path"]}
        )

      {:ok, state} = Data.declaration(Map.put(row, "type_name", "myapp.guarded_step"))

      composite =
        Block.new("myapp.guarded_step",
          id: "blk_AD",
          config: %{
            "invoke_type" => "myapp:signup",
            "path" => "signup.verification.failure"
          }
        )

      %{row: row, ref: {Data, state}, composite: composite}
    end

    # Sabotage: dropped `"assign_to" => ""` from the template - red. The
    # expansion is the whole of what the two declarations have to agree
    # about, because everything downstream reads it and nothing else.
    test "expand to the same blocks, id for id", %{ref: ref, composite: composite} do
      assert Composite.expand!(composite, GuardedStep) == Composite.expand!(composite, ref)

      {[root], _param_map} = Composite.expand!(composite, ref)
      assert root.id == "blk_AD_invoke"
      assert [%Block{id: "blk_AD_assign"}] = root.slots["on_error"]
    end

    # Sabotage: minted the suffix from the id - red here, which is exactly
    # the consequence 18E states: `blk_GS_call` against `blk_GS_invoke`.
    # Byte identity is consent clause 6's obligation, and this is the test
    # that carries it for Collapse.
    test "compile to the same bytes", %{ref: ref, composite: composite} do
      document = document(composite)

      assert {:ok, from_module} =
               Compiler.compile(
                 document,
                 Palette.from_modules([{"myapp.guarded_step", GuardedStep}], core: true)
               )

      assert {:ok, from_collapse} =
               Compiler.compile(
                 document,
                 Palette.from_modules([{"myapp.guarded_step", ref}], core: true)
               )

      assert from_module.scxml == from_collapse.scxml
    end

    # Sabotage: expanded the composite to the arrangement's own ids - red.
    # The composite the author gets back has to expand to the arrangement
    # they started with, which is what makes 17E's swap safe to offer.
    test "the composite expands to the arrangement it was collapsed from", %{
      ref: ref,
      composite: composite
    } do
      {[root], _param_map} = Composite.expand!(composite, ref)
      original = guarded_step_arrangement()

      assert root.type == original.type
      assert root.config == original.config
      assert [expanded_child] = root.slots["on_error"]
      assert [original_child] = original.slots["on_error"]
      assert expanded_child.type == original_child.type
      assert expanded_child.config == original_child.config
    end
  end

  # -- 20E, the data half: a proposed pass-through slot, expanded ---------

  defmodule GuardedSection do
    @moduledoc """
    The `use`-composite twin of the collapsed "Guarded section": the same one
    member, and the same pass-through slot `propose/3` proposes for its
    unfilled `on_error`, spelled as `ADR-0002`'s pass-through amendment
    fixes it.
    """

    use StatifierBlocks.Composite,
      name: "myapp.guarded_section",
      params: [
        %{
          key: "invoke_type",
          type: :string,
          label: "Invoke type",
          required?: true,
          default: "myapp:signup"
        }
      ],
      slots: [%{name: "on_error", to: {"invoke", "on_error"}}],
      version: 1

    alias StatifierBlocks.Block

    @impl StatifierBlocks.Composite
    def subtree(params) do
      [
        Block.new("core.invoke",
          id: "invoke",
          config: %{"invoke_type" => params["invoke_type"], "assign_to" => ""},
          slots: %{"on_error" => []}
        )
      ]
    end
  end

  describe "20E: the proposed pass-through slot, registered and expanded" do
    setup do
      {:ok, row} =
        propose(document(guarded_section_arrangement()), ["blk_7"],
          marks: %{"blk_7" => ["invoke_type"]}
        )

      {:ok, state} = Data.declaration(Map.put(row, "type_name", "myapp.guarded_section"))

      composite =
        Block.new("myapp.guarded_section",
          id: "blk_AD",
          config: %{"invoke_type" => "myapp:signup"},
          slots: %{
            "on_error" => [
              Block.new("core.assign",
                id: "blk_notify",
                config: %{"path" => "signup.verification.failure", "value" => "failed"}
              )
            ]
          }
        )

      %{row: row, ref: {Data, state}, composite: composite}
    end

    # Sabotage: had `Data.declaration/1` drop the row's `"slots"` key - red.
    # `propose/3` emits the mapping in the array shape P2 fixes, and a decode
    # that ignored it would make the proposal a slot nothing can fill.
    test "the proposed row declares the slot the module twin declares", %{ref: {Data, state}} do
      assert Data.slots(state, %{}) == GuardedSection.slots(%{})
    end

    # Sabotage: spliced the children before taking the param map - red on the
    # map, which is ADR-0004 T3's mechanism, and green everywhere else, which
    # is why the assertion names it explicitly.
    test "the same expansion, block for block", %{ref: ref, composite: composite} do
      assert Composite.expand!(composite, GuardedSection) == Composite.expand!(composite, ref)

      {[root], param_map} = Composite.expand!(composite, ref)

      assert root.id == "blk_AD_invoke"
      assert [%Block{id: "blk_notify"}] = root.slots["on_error"]
      assert Map.keys(param_map) == ["blk_AD_invoke"]
    end

    # Sabotage: minted the spliced child's id along with the members - red.
    # Byte identity across the two declarations is consent clause 6's
    # obligation, and the child's stored id is what T2 keeps unchanged.
    test "the same compiled bytes", %{ref: ref, composite: composite} do
      document = document(composite)

      assert {:ok, from_module} =
               Compiler.compile(
                 document,
                 Palette.from_modules([{"myapp.guarded_section", GuardedSection}], core: true)
               )

      assert {:ok, from_collapse} =
               Compiler.compile(
                 document,
                 Palette.from_modules([{"myapp.guarded_section", ref}], core: true)
               )

      assert from_module.scxml == from_collapse.scxml
      assert from_module.provenance == from_collapse.provenance
      assert from_module.scxml =~ "s_blk_notify"
    end
  end

  # -- 17E: the replacement compound -------------------------------------

  describe "replacement/4" do
    # Sabotage: inserted before removing - red on the position. Removing
    # first and inserting at the freed index is Expand's ordering read
    # backwards, and one remove with one insert is one undo entry.
    test "removes the arrangement and inserts one composite at its own target" do
      # The arrangement is SECOND in the slot on purpose: a target read off
      # the document rather than assumed is only visible where index 0 is the
      # wrong answer.
      document =
        document([
          Block.new("core.assign", id: "blk_0", config: %{"path" => "a", "value" => "1"}),
          guarded_step_arrangement()
        ])

      {:ok, row} =
        propose(document, ["blk_7", "blk_9"],
          marks: %{"blk_7" => ["invoke_type"], "blk_9" => ["path"]}
        )

      assert {:ok, {:compound, [{:remove, "blk_7"}, {:insert, target, block}]}} =
               Collapse.replacement(document, "blk_7", "myapp.guarded_step", row)

      assert target == {"blk_ROOT", "body", 1}
      assert block.type == "myapp.guarded_step"

      assert block.config == %{
               "invoke_type" => "myapp:signup",
               "path" => "signup.verification.failure"
             }
    end

    # Sabotage: raised on a missing id - red. `replacement/4` is a public
    # function a host calls with whatever it holds, and it refuses rather
    # than raising for the reason every other seam here does.
    test "refuses the root and an id the document does not hold" do
      document = document(guarded_step_arrangement())

      assert {:error, {:cannot_collapse_root, "blk_ROOT"}} =
               Collapse.replacement(document, "blk_ROOT", "myapp.x", %{})

      assert {:error, {:no_such_block, "blk_NOPE"}} =
               Collapse.replacement(document, "blk_NOPE", "myapp.x", %{})
    end

    # Sabotage: inserted the composite at a fixed index 0 rather than at the
    # arrangement's own target - red on a document where the arrangement is
    # not first. The compound is one undo entry (2n, 3E), so undoing it has
    # to put the author back exactly where they were: not nearly, byte for
    # byte.
    test "the compound undone is byte-identical to the document it was built from" do
      document =
        document([
          Block.new("core.assign", id: "blk_0", config: %{"path" => "a", "value" => "1"}),
          guarded_step_arrangement()
        ])

      {:ok, row} =
        propose(document, ["blk_7", "blk_9"],
          marks: %{"blk_7" => ["invoke_type"], "blk_9" => ["path"]}
        )

      {:ok, compound} = Collapse.replacement(document, "blk_7", "myapp.guarded_step", row)

      assert {:ok, swapped, inverse} = Edit.apply(document, compound)
      refute swapped == document

      assert {:ok, restored, _redo} = Edit.apply(swapped, inverse)
      assert restored == document
    end

    # Sabotage: had the compound applied here rather than answered - red.
    # Nothing in this package commits it: a host that saves a declaration and
    # never swaps the arrangement out has done a legitimate thing.
    test "answers the compound and commits nothing" do
      document = document(guarded_step_arrangement())

      assert {:ok, {:compound, _commands}} =
               Collapse.replacement(document, "blk_7", "myapp.guarded_step", %{"params" => []})

      assert document == document(guarded_step_arrangement())
    end
  end
end
