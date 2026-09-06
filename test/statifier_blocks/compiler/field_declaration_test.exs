defmodule StatifierBlocks.Compiler.FieldDeclarationTest do
  @moduledoc """
  A datamodel-path field declared with no `default:` key.

  `t:StatifierBlocks.BlockType.field_decl/0` has always required the key, and
  the view model has always destructured it out of every declaration, so a
  block type that omitted it raised a `FunctionClauseError` from inside a
  render rather than saying anything about the declaration. The config stage
  refuses it instead, naming the field; the view model reads the key
  permissively so a declaration defect can still be looked at.

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

  defp palette(extra) do
    Palette.new(Map.merge(Palette.core_types(), extra))
  end

  defp document(children) do
    Document.new(
      Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => children}),
      id: "bdoc_SIGNUP"
    )
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

    # Sabotage: matched `%{type: _any}` instead of `%{type: {:path, _opts}}`
    # - red, because the string field is then refused too, which is a
    # widening of what a block type may declare that no record has taken.
    test "a field of another type is not the refusal's business" do
      doc = document([Block.new("signup.collect", id: "blk_COLLECT")])
      types = palette(%{"signup.collect" => Collect})

      assert {:ok, _compiled} = Compiler.compile(doc, types)

      assert %Field{default: nil} =
               field(ViewModel.build(doc, types, []), "blk_COLLECT", "prompt")
    end
  end
end
