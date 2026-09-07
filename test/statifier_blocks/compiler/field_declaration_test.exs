defmodule StatifierBlocks.Compiler.FieldDeclarationTest do
  @moduledoc """
  A field declared with no `default:` key, and a hidden field declared with
  an empty one.

  `t:StatifierBlocks.BlockType.field_decl/0` has always required `default:`,
  and the view model has always destructured it out of every declaration, so
  a block type that omitted it raised a `FunctionClauseError` from inside a
  render rather than saying anything about the declaration. The config stage
  refuses it instead, naming the field; the view model reads the key
  permissively so a declaration defect can still be looked at.

  The refusal covered the `{:path, opts}` arm alone until ADR-0002 decision
  7's amendment of 2026-09-07 (section F3) took the record's call and widened
  it to all nine field types. Section F4 adds the second declaration refusal
  in this file: a `hidden?: true` field whose `default:` is its type's empty
  value carries nothing and no form can ever give it anything. `:boolean` is
  the one type with no empty value, and a `readonly?: true` field takes no
  such refusal.

  The document is a signup wizard: collect an email, then confirm it.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, Document, Palette, ViewModel}
  alias StatifierBlocks.ViewModel.{Field, Form, Node, Slot}

  defmodule Confirm do
    @moduledoc "A host leaf reading the address to confirm, declared without a default."
    @behaviour StatifierBlocks.BlockType

    alias StatifierBlocks.Compiler.Context
    alias StatifierBlocks.Core.Emit

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config),
      do: [%{key: "address_from", type: {:path, %{}}, label: "Address from", required?: false}]

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(_block, %Context{} = context) do
      done = Context.done_id(context)
      {:ok, Emit.state(context.state_id, done, [Emit.final(done)])}
    end
  end

  defmodule ConfirmWithDefault do
    @moduledoc "The same leaf, declared the way the field type requires."
    @behaviour StatifierBlocks.BlockType

    alias StatifierBlocks.Compiler.Context
    alias StatifierBlocks.Core.Emit

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config) do
      [
        %{
          key: "address_from",
          type: {:path, %{}},
          label: "Address from",
          required?: false,
          default: ""
        }
      ]
    end

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(_block, %Context{} = context) do
      done = Context.done_id(context)
      {:ok, Emit.state(context.state_id, done, [Emit.final(done)])}
    end
  end

  defmodule Collect do
    @moduledoc "A host leaf whose one field is a plain string, declared without a default."
    @behaviour StatifierBlocks.BlockType

    alias StatifierBlocks.Compiler.Context
    alias StatifierBlocks.Core.Emit

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config),
      do: [%{key: "prompt", type: :string, label: "Prompt", required?: false}]

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(_block, %Context{} = context) do
      done = Context.done_id(context)
      {:ok, Emit.state(context.state_id, done, [Emit.final(done)])}
    end
  end

  defmodule CollectWithDefault do
    @moduledoc "The same plain-string leaf, declared with the required default."
    @behaviour StatifierBlocks.BlockType

    alias StatifierBlocks.Compiler.Context
    alias StatifierBlocks.Core.Emit

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config),
      do: [
        %{key: "prompt", type: :string, label: "Prompt", required?: false, default: "Your email"}
      ]

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(_block, %Context{} = context) do
      done = Context.done_id(context)
      {:ok, Emit.state(context.state_id, done, [Emit.final(done)])}
    end
  end

  defmodule Seeded do
    @moduledoc """
    A host leaf carrying the flagged pair the amendment's worked example
    uses: a readonly step name and a hidden variant seed.

    A test that needs another declaration puts one in the process dictionary
    rather than in the block's config: a block's config has to be JSON and a
    field declaration is not, so it cannot travel that way. Each test runs in
    its own process, so the override is as scoped as the test is.
    """
    @behaviour StatifierBlocks.BlockType

    alias StatifierBlocks.Compiler.Context
    alias StatifierBlocks.Core.Emit

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []

    @schema_key :sb_21gm_schema

    @doc "Declare `schema` for the next compile in this process."
    def put_schema(schema), do: Process.put(@schema_key, schema)

    @impl true
    def config_schema(_config) do
      Process.get(@schema_key) || worked_example()
    end

    defp worked_example do
      [
        %{
          key: "step_name",
          type: :string,
          label: "Step",
          required?: true,
          default: "Collect email",
          readonly?: true
        },
        %{
          key: "variant_seed",
          type: :string,
          label: "Variant seed",
          required?: false,
          default: "control",
          hidden?: true
        }
      ]
    end

    @impl true
    def validate_config(_config), do: :ok

    # The seed reaches the emission verbatim, which is what makes the "a
    # hidden value reaches the SCXML unchanged" assertion below about the
    # config rather than about this module.
    @impl true
    def emit(%Block{config: config}, %Context{} = context) do
      done = Context.done_id(context)
      seed = Map.get(config, "variant_seed", "")

      {:ok,
       Emit.state(context.state_id, nil, [
         Emit.transition([event: "myapp.seed." <> seed, target: done], []),
         Emit.final(done)
       ])}
    end
  end

  defp palette(extra) do
    Palette.new(Map.merge(Palette.core_types(), extra))
  end

  defp document(children) do
    Document.new(
      Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => children}),
      id: "bdoc_SIGNUP"
    )
  end

  defp compile_seeded do
    doc = document([Block.new("signup.seeded", id: "blk_F")])
    Compiler.compile(doc, palette(%{"signup.seeded" => Seeded}))
  end

  defp compile_hidden(type, default) do
    Seeded.put_schema([
      %{key: "f", type: type, label: "F", required?: false, default: default, hidden?: true}
    ])

    compile_seeded()
  end

  defp field(%ViewModel{root: root}, block_id, key) do
    %Node{slots: [%Slot{children: children}]} = root

    %Node{form: %Form{fields: fields}} = Enum.find(children, &(&1.block_id == block_id))
    Enum.find(fields, &(&1.key == key))
  end

  describe "a datamodel-path field with no default:" do
    # Sabotage: made `path_field_without_default?/1` answer `false` for the
    # `{:path, _}` clause - red, because the compile then succeeds and the
    # declaration defect goes back to being invisible until something
    # renders the block.
    test "is refused at compile, as a config finding naming the field" do
      doc = document([Block.new("signup.confirm", id: "blk_CONFIRM")])

      assert {:error, [finding]} =
               Compiler.compile(doc, palette(%{"signup.confirm" => Confirm}))

      assert finding.stage == :config
      assert finding.code == :invalid_config
      assert finding.block_id == "blk_CONFIRM"
      assert finding.config_key == "address_from"
      assert finding.message =~ "address_from"
      assert finding.message =~ "default:"
    end

    # Sabotage: de-duplicated the config stage's findings by code and key,
    # which is what reporting a declaration defect once per type would look
    # like - red, because only the first of the two blocks is then named and
    # the author is sent to one of the two cards they have to fix.
    test "is refused once per block, because a schema is read per config" do
      doc =
        document([
          Block.new("signup.confirm", id: "blk_ONE"),
          Block.new("signup.confirm", id: "blk_TWO")
        ])

      assert {:error, findings} =
               Compiler.compile(doc, palette(%{"signup.confirm" => Confirm}))

      assert Enum.map(findings, &{&1.block_id, &1.config_key}) == [
               {"blk_ONE", "address_from"},
               {"blk_TWO", "address_from"}
             ]
    end

    # Sabotage: replaced `Map.get(decl, :default)` in `build_fields/3` with
    # the destructure it used to be - red with a `FunctionClauseError`,
    # which is the failure this bead is about.
    test "still renders in the view model, with no default" do
      doc = document([Block.new("signup.confirm", id: "blk_CONFIRM")])
      view = ViewModel.build(doc, palette(%{"signup.confirm" => Confirm}), [])

      assert %Field{default: nil, value: nil} = field(view, "blk_CONFIRM", "address_from")
    end
  end

  describe "a declaration the field type is happy with" do
    # Sabotage: dropped the `Map.has_key?/2` test so every path field is
    # refused - red, because a correctly declared type then cannot compile
    # at all.
    test "compiles, and the declared default reaches the control" do
      doc = document([Block.new("signup.confirm", id: "blk_CONFIRM")])
      types = palette(%{"signup.confirm" => ConfirmWithDefault})

      assert {:ok, _compiled} = Compiler.compile(doc, types)

      assert %Field{default: ""} =
               field(ViewModel.build(doc, types, []), "blk_CONFIRM", "address_from")
    end

    # Sabotage: dropped the `Map.has_key?/2` test so every field is refused
    # - red, because a correctly declared plain field then cannot compile.
    test "a field of another type compiles when it declares its default" do
      doc = document([Block.new("signup.collect", id: "blk_COLLECT")])
      types = palette(%{"signup.collect" => CollectWithDefault})

      assert {:ok, _compiled} = Compiler.compile(doc, types)

      assert %Field{default: "Your email"} =
               field(ViewModel.build(doc, types, []), "blk_COLLECT", "prompt")
    end
  end

  describe "the refusal widened to every field type (ADR-0002 F3)" do
    # Sabotage: restored the `%{type: {:path, _opts}}` head the check used to
    # carry - red, because the string field is then let through again, which
    # is the narrow enforcement the amendment's section F3 replaced.
    test "a plain :string field with no default: is refused too" do
      doc = document([Block.new("signup.collect", id: "blk_COLLECT")])

      assert {:error, [finding]} =
               Compiler.compile(doc, palette(%{"signup.collect" => Collect}))

      assert finding.stage == :config
      assert finding.code == :invalid_config
      assert finding.block_id == "blk_COLLECT"
      assert finding.config_key == "prompt"
      assert finding.message =~ "prompt"
      assert finding.message =~ "default:"
    end

    # Sabotage: widened the check to only some of the nine arms - red on the
    # arm left out. The set is closed, so the table is enumerable and every
    # member is asserted rather than a representative one.
    test "every one of the nine field types is refused" do
      types = [
        :string,
        :integer,
        :boolean,
        {:select, [{"a", "A"}]},
        :expression,
        :duration,
        {:list, :string},
        {:path, %{}},
        {:type_expr, %{}}
      ]

      for type <- types do
        Seeded.put_schema([%{key: "f", type: type, label: "F", required?: false}])

        assert {:error, [%{config_key: "f"}]} = compile_seeded(),
               "#{inspect(type)} declared without default: was not refused"
      end
    end

    # Sabotage: made the finding's fault `:package` - red. ADR-0002 decision
    # 9 makes every `:config` finding the author's by construction, and
    # section F5 accepts that misattribution for a declaration defect rather
    # than widening the vocabulary.
    test "the finding's fault is :author, as decision 9 makes every :config finding" do
      doc = document([Block.new("signup.collect", id: "blk_COLLECT")])

      assert {:error, [finding]} =
               Compiler.compile(doc, palette(%{"signup.collect" => Collect}))

      assert finding.fault == :author
    end
  end

  describe "a hidden field whose default: is its type's empty value (ADR-0002 F4)" do
    # Sabotage: dropped the `hidden?: true` guard on the empty-default check
    # so every empty default is refused - red, because an ordinary field
    # defaulting to "" is the common case and the amendment refuses nothing
    # about it.
    test "the eight types with an empty value are refused, and :boolean is not" do
      refused = [
        {:string, ""},
        {:integer, ""},
        {{:select, [{"a", "A"}]}, ""},
        {:expression, ""},
        {:duration, ""},
        {{:list, :string}, []},
        {{:path, %{}}, ""},
        {{:type_expr, %{}}, ""},
        {{:type_expr, %{}}, nil}
      ]

      for {type, empty} <- refused do
        assert {:error, [%{config_key: "f", message: message}]} =
                 compile_hidden(type, empty),
               "hidden #{inspect(type)} defaulting to #{inspect(empty)} was not refused"

        assert message =~ "hidden?: true"
      end

      assert {:ok, _compiled} = compile_hidden(:boolean, false)
      assert {:ok, _compiled} = compile_hidden(:boolean, true)
    end

    # Sabotage: dropped the leading `nil` clause from `empty_default?/2` -
    # red on every row but `{:type_expr, opts}`, which is the one row whose
    # prose happened to enumerate its arms. F4's per-type empty values are a
    # floor and not a ceiling: `nil` carries nothing in exactly the sense an
    # empty string does, so it is refused as a hidden field's `default:` for
    # every row of the table, `:boolean` included - `false` is a decided
    # value, and `nil` is not `false`.
    test "nil is refused as an empty hidden default for every one of the nine types" do
      types = [
        :string,
        :integer,
        :boolean,
        {:select, [{"a", "A"}]},
        :expression,
        :duration,
        {:list, :string},
        {:path, %{}},
        {:type_expr, %{}}
      ]

      for type <- types do
        assert {:error, [%{config_key: "f", message: message}]} = compile_hidden(type, nil),
               "hidden #{inspect(type)} defaulting to nil was not refused"

        assert message =~ "hidden?: true"
      end
    end

    # Sabotage: refused a non-empty hidden default too - red, because the
    # amendment's worked example declares exactly this and must compile.
    test "a hidden field with a non-empty default compiles" do
      assert {:ok, _compiled} = compile_hidden(:string, "control")
    end

    # Sabotage: applied the refusal to `readonly?: true` as well - red. F4
    # says a readonly field takes no such refusal, because it is rendered and
    # an empty value is visible.
    test "a readonly field takes no such refusal" do
      Seeded.put_schema([
        %{key: "f", type: :string, label: "F", required?: false, default: "", readonly?: true}
      ])

      assert {:ok, _compiled} = compile_seeded()
    end

    # Sabotage: made the empty-default check run before the missing-key one
    # - red, because a hidden field declaring no `default:` at all then
    # reports the F4 message rather than the F3 one it is actually missing.
    test "a hidden field with no default: at all reports the missing-key refusal" do
      Seeded.put_schema([%{key: "f", type: :string, label: "F", required?: false, hidden?: true}])

      assert {:error, [%{message: message}]} = compile_seeded()

      assert message =~ "no default: key"
    end
  end

  describe "the flags reach the view model (ADR-0002 F7)" do
    # Sabotage: dropped `hidden?` from `build_fields/3` so it defaults false
    # - red, because a host reading the view model to draw its own surface
    # then cannot tell a hidden field from an editable one.
    test "ViewModel.Field carries both flags, and hidden fields stay in the list" do
      doc = document([Block.new("signup.seeded", id: "blk_SEED")])
      view = ViewModel.build(doc, palette(%{"signup.seeded" => Seeded}), [])

      assert %Field{readonly?: true, hidden?: false} = field(view, "blk_SEED", "step_name")

      assert %Field{hidden?: true, readonly?: false, value: "control"} =
               field(view, "blk_SEED", "variant_seed")
    end

    # Sabotage: made `build_fields/3` reject hidden fields - red, because the
    # projection is the whole schema (F7) and `ConfigForm.decode/3` is keyed
    # off the fields it is handed, so dropping them here drops the value.
    test "a field carrying neither flag reads false for both" do
      doc = document([Block.new("signup.collect", id: "blk_COLLECT")])
      view = ViewModel.build(doc, palette(%{"signup.collect" => CollectWithDefault}), [])

      assert %Field{hidden?: false, readonly?: false} = field(view, "blk_COLLECT", "prompt")
    end
  end

  describe "a hidden value is only hidden from the form" do
    # Sabotage: had the compile read the schema's `hidden?` and skip the key
    # - red. The compiler never reads the flags at all, which is the claim:
    # the seed reaches the SCXML by the same route every other config value
    # does. What a declared `default:` alone reaches is the view model and
    # the form, not the emission - the compile reads the config the document
    # holds, which is why this test writes the key.
    test "a hidden value the document carries reaches the compiled SCXML unchanged" do
      doc =
        document([
          Block.new("signup.seeded", id: "blk_SEED", config: %{"variant_seed" => "cohort_b"})
        ])

      assert {:ok, compiled} = Compiler.compile(doc, palette(%{"signup.seeded" => Seeded}))
      assert compiled.scxml =~ ~s(event="myapp.seed.cohort_b")
      refute compiled.scxml =~ ~s(event="myapp.seed.control")
    end
  end
end
