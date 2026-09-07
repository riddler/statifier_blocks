defmodule StatifierBlocks.Composite.DataTest do
  @moduledoc """
  `StatifierBlocks.Composite.Data`: the same composite, declared as data
  (ADR-0002's 2026-09-07 amendment, filed with `sb-5b7j`).

  The load-bearing test here is the **equivalence**: a data composite
  registered from a JSON-shaped map behaves as the `use`-composite of the
  same shape - the same expansion, the same param map, and the same compiled
  bytes. That is what the record buys by making the seam carry the pair
  rather than by generating a module per saved declaration, and it is what
  proves `Composite.expand/2` is still the one expansion function.

  "Guarded step" is the amendment's own worked example, in card processing,
  arriving as a row rather than as a `use` block.

  A pure test. Nothing here names LiveView, so it compiles and runs headless.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, Composite, Document, Palette}
  alias StatifierBlocks.Composite.Data

  # -- the same composite, declared twice --------------------------------

  defmodule GuardedStep do
    @moduledoc "The worked example as a `use` block: the side to match."

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

  @row %{
    "type_name" => "myapp.guarded_step",
    "version" => 1,
    "sentence" => "Call {{invoke_type}}, recording failure at {{failure_path}}",
    "palette_entry" => %{"label" => "Guarded step", "group" => "Structure", "order" => 40},
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
      }
    ]
  }

  # A template naming no param, for the tests that are about the PARAMS and
  # would otherwise have to re-declare the worked example's placeholders.
  @leaf [%{"type" => "core.assign", "id_suffix" => "leaf", "config" => %{"value" => "x"}}]

  # -- helpers -----------------------------------------------------------

  defp state do
    {:ok, state} = Data.declaration(@row)
    state
  end

  defp ref, do: {Data, state()}

  defp module_palette do
    Palette.from_modules([{"myapp.guarded_step", GuardedStep}], core: true)
  end

  defp data_palette do
    Palette.from_modules([{"myapp.guarded_step", ref()}], core: true)
  end

  defp block(id \\ "blk_AD") do
    Block.new("myapp.guarded_step",
      id: id,
      config: %{
        "invoke_type" => "myapp:authorize",
        "failure_path" => "cards.authorization.failure"
      }
    )
  end

  defp document do
    Document.new(
      Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [block()]}),
      id: "bdoc_CANONICAL"
    )
  end

  # -- the equivalence ---------------------------------------------------

  describe "a data composite behaves as the module composite of the same shape" do
    # Sabotage: made `Data.subtree/2` drop the placeholder substitution - red.
    # The expansion is the whole of what the two declarations have to agree
    # about, because everything downstream reads it and nothing else.
    test "the same expansion, block for block" do
      assert Composite.expand(block(), GuardedStep) == Composite.expand(block(), ref())
    end

    # Sabotage: minted the id as `composite_id <> "__" <> suffix` - red, both
    # here and in `expand/2`'s own refusal. The record's `blk_GS_call` shape
    # is what keeps ADR-0004 decision 3's `unstate_id/1` invertible.
    test "the ids are the composite block's own, minted from the suffixes" do
      {[root], param_map} = Composite.expand(block(), ref())

      assert root.id == "blk_AD_call"
      assert [%Block{id: "blk_AD_guard"}] = root.slots["on_error"]
      assert param_map == %{"blk_AD_call" => "invoke_type", "blk_AD_guard" => "failure_path"}
    end

    # Sabotage: hashed the whole entry rather than the module in
    # `Compiler.entries/1` - red. Byte identity across the two declarations
    # is the property consent clause 6 names, and it is what says nothing
    # downstream of the palette can tell which kind of entry it got.
    test "the same compiled bytes" do
      assert {:ok, from_module} = Compiler.compile(document(), module_palette())
      assert {:ok, from_data} = Compiler.compile(document(), data_palette())

      assert from_module.scxml == from_data.scxml
    end

    # Sabotage: answered the declaration's own `version` from a hard-coded 1
    # - red on a row stating another version. `manifest/1` reads the entry
    # through the seam, so a stateful entry is an ordinary manifest row.
    test "the same manifest entry" do
      assert Palette.manifest(module_palette()) == Palette.manifest(data_palette())
    end

    # Sabotage: skipped the `{{key}}` collapse at decode time - red, because
    # the one renderer then leaves the outer braces in place.
    test "the same sentence" do
      config = %{
        "invoke_type" => "myapp:authorize",
        "failure_path" => "cards.authorization.failure"
      }

      assert Data.sentence(state(), config) == GuardedStep.sentence(config)

      assert Data.sentence(state(), config) ==
               "Call myapp:authorize, recording failure at cards.authorization.failure"
    end

    # Sabotage: dropped the `Composite.derived_io/2` delegation - red. The
    # derived reads and writes come off the same expansion, so they cannot
    # differ between the two declarations without the expansion differing.
    test "the same io and outcomes" do
      assert Data.io(state(), %{}) == GuardedStep.io(%{})
      assert Data.outcomes(state(), %{}) == GuardedStep.outcomes(%{})
    end

    # Sabotage: returned the whole state from `__composite__/1` - red on the
    # equality, because the declaration shape carries no `:subtree` key.
    test "the same declaration" do
      assert Data.__composite__(state()) == GuardedStep.__composite__()
    end
  end

  # -- the derived block type, through the seam --------------------------

  describe "the derived block type" do
    # Sabotage: made `composite?/1` answer `false` for a pair - red. The
    # compiler, Expand and the derivations all ask this before expanding, so
    # a data composite that failed it would silently survive to Emit.
    test "composite?/1 recognises a stateful entry" do
      assert Composite.composite?(ref())
      refute Composite.composite?(Data)
      refute Composite.composite?("myapp.guarded_step")
    end

    # Sabotage: exported `slots/1` beside `slots/2` - red. A composite in
    # this campaign exposes no slot of its own (RQ-SF037-3), and the seam
    # reaches the callback at one higher arity, never at the declared one.
    test "the callbacks live at one higher arity, and only there" do
      assert Palette.declares?(ref(), :slots, 1)
      assert Palette.declares?(ref(), :config_schema, 1)
      assert Palette.declares?(ref(), :emit, 2)
      refute function_exported?(Data, :slots, 1)
      refute function_exported?(Data, :config_schema, 1)
    end

    # Sabotage: derived `slots/2` from the expansion root - red.
    test "slots/1 is [] and config_schema/1 is the params" do
      assert Palette.call(ref(), :slots, [%{}], :absent) == []

      assert [%{key: "invoke_type", type: :string}, %{key: "failure_path"}] =
               Palette.call(ref(), :config_schema, [%{}], :absent)
    end

    # Sabotage: injected `{:ok, config}` instead of ADR-0007's refusal - red.
    # A declaration is the only thing that can supply a migration and this
    # shape fixes no key for one, so a bump with stored blocks REFUSES; the
    # derived `{:ok, config}` is exactly what that injection exists to
    # refuse.
    test "a version bump with no migration key refuses every stored block" do
      {:ok, bumped} = Data.declaration(%{@row | "version" => 2})
      palette = Palette.from_modules([{"myapp.guarded_step", {Data, bumped}}], core: true)

      assert {:error, {:migration_failed, "blk_AD", {:no_migration_from, 1}}} =
               Palette.resolve(palette, %{block() | type_version: 1})
    end

    # Sabotage: returned `{:ok, _}` from `emit/3` - red. No composite block
    # survives to Emit, so reaching it means the expansion did not run.
    test "emit/2 raises if reached (RQ-SF037-6)" do
      assert_raise RuntimeError, ~r/Resolve/, fn ->
        Palette.call(ref(), :emit, [block(), nil], :never)
      end
    end
  end

  # -- the template ------------------------------------------------------

  describe "the subtree template" do
    # Sabotage: substituted a `"$param"` into a string rather than replacing
    # the value whole - red on the boolean. Whole-value substitution is the
    # whole vocabulary, so a `:boolean` param substitutes a boolean and not
    # the string "true".
    test "a placeholder is replaced whole, at the param's declared type" do
      row = %{
        "type_name" => "myapp.flagged",
        "version" => 1,
        "params" => [
          %{"key" => "on?", "type" => "boolean", "label" => "On", "default" => false}
        ],
        "subtree" => [
          %{
            "type" => "core.assign",
            "id_suffix" => "set",
            "config" => %{"path" => "cards.flag", "value" => %{"$param" => "on?"}}
          }
        ]
      }

      assert {:ok, state} = Data.declaration(row)

      block = Block.new("myapp.flagged", id: "blk_F", config: %{"on?" => true})
      {[member], _param_map} = Composite.expand(block, {Data, state})

      assert member.config["value"] === true
    end

    # Sabotage: dropped the `"$literal"` arm - red. The escape is what keeps
    # a config value that genuinely is a one-key `"$param"` map expressible.
    test ~s(a "$literal" map is its value, unsubstituted) do
      row = %{
        "type_name" => "myapp.literal",
        "version" => 1,
        "params" => [%{"key" => "p", "type" => "string", "label" => "P", "default" => ""}],
        "subtree" => [
          %{
            "type" => "core.assign",
            "id_suffix" => "set",
            "config" => %{
              "path" => "cards.raw",
              "value" => %{"$literal" => %{"$param" => "p"}}
            }
          }
        ]
      }

      assert {:ok, state} = Data.declaration(row)

      block = Block.new("myapp.literal", id: "blk_L", config: %{"p" => "substituted"})
      {[member], _param_map} = Composite.expand(block, {Data, state})

      assert member.config["value"] == %{"$param" => "p"}
    end

    # Sabotage: treated a two-key map carrying "$param" as a placeholder -
    # red. Every other JSON value is a literal, INCLUDING every other map,
    # so the arm is "exactly the single key" and not "carries the key".
    test "a map with more than one key is a literal, whatever it carries" do
      row = %{
        "type_name" => "myapp.two_key",
        "version" => 1,
        "params" => [%{"key" => "p", "type" => "string", "label" => "P", "default" => ""}],
        "subtree" => [
          %{
            "type" => "core.assign",
            "id_suffix" => "set",
            "config" => %{
              "path" => "cards.raw",
              "value" => %{"$param" => "p", "other" => 1}
            }
          }
        ]
      }

      assert {:ok, state} = Data.declaration(row)

      block = Block.new("myapp.two_key", id: "blk_T", config: %{"p" => "x"})
      {[member], _param_map} = Composite.expand(block, {Data, state})

      assert member.config["value"] == %{"$param" => "p", "other" => 1}
    end
  end

  # -- every refusal is at entry-build time ------------------------------

  describe "declaration/1 refuses at entry-build time" do
    # Sabotage: made `declaration/1` answer `{:ok, _}` for a malformed row -
    # red. `fetch/2` must not raise and a callback must be pure and total, so
    # the last moment a malformed declaration can be refused is before it is
    # in the palette.
    test "a row that is not a map" do
      assert {:error, [message]} = Data.declaration("not a row")
      assert message =~ "must be a map"
    end

    # Sabotage: accepted `"version" => 0` - red. "version" is required so a
    # declaration always has one to bump, which is the hygiene obligation the
    # record moves onto the host that edits a declaration.
    test ~s("version" must be a positive integer, and every reason comes back) do
      assert {:error, errors} =
               Data.declaration(%{
                 "type_name" => "",
                 "version" => 0,
                 "params" => [],
                 "subtree" => []
               })

      assert length(errors) == 3
      assert Enum.any?(errors, &(&1 =~ ~s("type_name")))
      assert Enum.any?(errors, &(&1 =~ ~s("version")))
      assert Enum.any?(errors, &(&1 =~ ~s("subtree")))
    end

    # Sabotage: let a `"$param"` naming an undeclared key through - red. It
    # would substitute `nil` into the expanded config at compile time, which
    # is a refusal arriving as a wrong answer.
    test ~s(a "$param" naming an undeclared key) do
      row = %{
        @row
        | "subtree" => [
            %{
              "type" => "core.assign",
              "id_suffix" => "set",
              "config" => %{"path" => %{"$param" => "no_such_param"}, "value" => ""}
            }
          ]
      }

      assert {:error, [message]} = Data.declaration(row)
      assert message =~ "undeclared params"
      assert message =~ "no_such_param"
    end

    # Sabotage: dropped the regex check - red. A suffix carrying "__" or an
    # uppercase letter mints an id ADR-0004 decision 3's `unstate_id/1`
    # stops inverting.
    test ~s(an "id_suffix" that does not match the shape) do
      for suffix <- ["Call", "call__guard", "_call", "call-guard", ""] do
        row = %{@row | "subtree" => [%{"type" => "core.assign", "id_suffix" => suffix}]}

        assert {:error, [message]} = Data.declaration(row), "accepted #{inspect(suffix)}"
        assert message =~ ~s("id_suffix")
      end
    end

    # Sabotage: compared only the top-level suffixes - red. Minting is
    # injective per composite, so a suffix is unique across the whole
    # template and not just across its head list.
    test ~s(a duplicate "id_suffix", nested included) do
      row = %{
        @row
        | "subtree" => [
            %{
              "type" => "core.invoke",
              "id_suffix" => "call",
              "slots" => %{
                "on_error" => [%{"type" => "core.assign", "id_suffix" => "call"}]
              }
            }
          ]
      }

      assert {:error, [message]} = Data.declaration(row)
      assert message =~ "duplicate"
    end

    # Sabotage: defaulted a missing `"default"` to `""` - red. F3's
    # missing-`default:` refusal applies to a param unchanged, and this is
    # where the `use` macro refuses the same thing.
    #
    # [Note 2026-09-07, sb-uzly: the second half of this test read
    # `"type" => "select"` against `unspellable field type`, because a
    # declaration held as data spelled five field types and `"select"` was
    # not one of them. ADR-0005's 2026-09-07 amendment, clause 19E, gives all
    # nine a spelling, so `"select"` is now a NAME this shape knows and the
    # refusal it earns is the one below - a `"select"` with no `"choices"`.
    # A type name none of the nine carries is what still earns the original
    # message, and it is asserted here so the arm does not go untested.]
    test "a param with no default, one whose options are missing, and one whose type is not a kind" do
      no_default = %{"key" => "p", "type" => "string", "label" => "P"}
      no_choices = %{"key" => "p", "type" => "select", "label" => "P", "default" => ""}
      no_kind = %{"key" => "p", "type" => "whatever", "label" => "P", "default" => ""}

      assert {:error, [m1 | _rest]} = Data.declaration(%{@row | "params" => [no_default]})
      assert m1 =~ ~s("default")

      assert {:error, [m2 | _rest]} = Data.declaration(%{@row | "params" => [no_choices]})
      assert m2 =~ ~s("choices")

      assert {:error, [m3 | _rest]} = Data.declaration(%{@row | "params" => [no_kind]})
      assert m3 =~ "unspellable field type"
    end

    # Sabotage: admitted an `"options"` on a scalar kind - red. There is no
    # second element on a `:string` for one to carry, so a declaration that
    # wrote one meant something the shape cannot express and saying so is
    # better than ignoring it (19E's first table row).
    test "an options beside a field type that carries none" do
      param = %{
        "key" => "p",
        "type" => "string",
        "label" => "P",
        "default" => "",
        "options" => %{}
      }

      assert {:error, [message | _rest]} = Data.declaration(%{@row | "params" => [param]})
      assert message =~ ~s("options")
    end

    # Sabotage: spelled a `{:path, opts}` signature by `inspect/1` - red.
    # ADR-0011 writes a signature as a string; a `{:list, T}` term is not
    # JSON, and half-carrying it would put a string that looks like a term
    # into a stored declaration.
    test "a path signature that is not a string, and type_expr arms that are not a subset" do
      path = %{
        "key" => "p",
        "type" => "path",
        "label" => "P",
        "default" => "",
        "options" => %{"writes" => ["Answer"]}
      }

      arms = %{
        "key" => "p",
        "type" => "type_expr",
        "label" => "P",
        "default" => "",
        "options" => %{"arms" => ["name", "shape"]}
      }

      assert {:error, [m1 | _rest]} = Data.declaration(%{@row | "params" => [path]})
      assert m1 =~ "non-empty strings"

      assert {:error, [m2 | _rest]} = Data.declaration(%{@row | "params" => [arms]})
      assert m2 =~ "subset"
    end

    # Sabotage: made `"list"`'s inner spelling a bare type name - red. The
    # inner rides the same `"type"` / `"options"` pair one level down, so an
    # unspellable inner is refused by the ordinary rule rather than by a
    # special case.
    test "a list whose inner kind is itself unspellable" do
      param = %{
        "key" => "p",
        "type" => "list",
        "label" => "P",
        "default" => [],
        "options" => %{"inner" => %{"type" => "select"}}
      }

      assert {:error, [message | _rest]} = Data.declaration(%{@row | "params" => [param]})
      assert message =~ ~s(a "list" whose inner field type)
    end

    # Sabotage: dropped the `{:list, inner}` recursion and answered
    # `{:list, :string}` outright - red on the nested arm. The four kinds
    # 19E adds are decoded into the same `field_type/0` terms a `use`
    # composite declares, which is what makes a collapsed row and its module
    # twin the same block type.
    test "the four option-carrying kinds decode into the field types they name" do
      params = [
        %{
          "key" => "s",
          "type" => "select",
          "label" => "S",
          "default" => "a",
          "options" => %{"choices" => [["a", "A"], ["b", "B"]]}
        },
        %{
          "key" => "p",
          "type" => "path",
          "label" => "P",
          "default" => "",
          "options" => %{"expects" => "Settleable"}
        },
        %{
          "key" => "l",
          "type" => "list",
          "label" => "L",
          "default" => [],
          "options" => %{
            "inner" => %{"type" => "list", "options" => %{"inner" => %{"type" => "string"}}}
          }
        },
        %{
          "key" => "t",
          "type" => "type_expr",
          "label" => "T",
          "default" => "",
          "options" => %{"arms" => ["inline"], "allow_empty?" => false}
        }
      ]

      assert {:ok, state} = Data.declaration(%{@row | "params" => params, "subtree" => @leaf})

      assert Enum.map(state.params, & &1.type) == [
               {:select, [{"a", "A"}, {"b", "B"}]},
               {:path, %{expects: "Settleable"}},
               {:list, {:list, :string}},
               {:type_expr, %{arms: [:inline], allow_empty?: false}}
             ]
    end

    # Sabotage: decoded an unknown `"palette_entry"` key with
    # `String.to_atom/1` - red. That is the atom-table allocation the record
    # rejects per-instance module generation on, arriving by another door: a
    # tenant-controlled string must never mint an atom.
    test "a palette_entry key this shape cannot spell" do
      assert {:error, [message]} =
               Data.declaration(%{@row | "palette_entry" => %{"whatever" => 1}})

      assert message =~ "cannot spell"
      assert message =~ "whatever"
    end
  end
end
