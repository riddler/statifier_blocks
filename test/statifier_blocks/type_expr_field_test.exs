defmodule StatifierBlocks.TypeExprFieldTest do
  @moduledoc """
  ADR-0002 decision 7 as amended 2026-09-06: the ninth member of the closed
  field-type set, its two arms, and the one shared check that refuses a
  value which is not an arm the field admits.

  The control is `StatifierBlocks.Editor.TypeExprControlTest`'s; this file
  is the field type, the term this package builds from the stored bytes,
  and the read check reaching the inline arm.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, BlockType, Compiler, Document, Environment, Palette, Shell}

  defmodule Typed do
    @moduledoc """
    A block type whose one field is a type expression.

    `opts` is what a block type declares, so the declarations under test are
    read off the block's own config here - `arms` and `allow_empty` as JSON
    carries them - rather than four modules being written out.
    """

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(config) do
      [
        %{
          key: "summary",
          type: {:type_expr, opts(config)},
          label: "Each answer is a",
          required?: false,
          default: ""
        }
      ]
    end

    defp opts(config) do
      %{}
      |> arms(Map.get(config, "arms"))
      |> allow_empty(Map.get(config, "allow_empty"))
    end

    defp arms(opts, names) when is_list(names) do
      Map.put(opts, :arms, Enum.map(names, &String.to_existing_atom/1))
    end

    defp arms(opts, _absent), do: opts

    defp allow_empty(opts, empty?) when is_boolean(empty?),
      do: Map.put(opts, :allow_empty?, empty?)

    defp allow_empty(opts, _absent), do: opts

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def io(_config), do: %{kinds: [:step]}

    @impl true
    def palette_entry, do: %{label: "Typed"}

    @impl true
    def emit(%StatifierBlocks.Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  @declarations %{
    "types" => [
      %{
        "name" => "cards.settlement",
        "kind" => "record",
        "label" => "Settlement",
        "fields" => [%{"name" => "amount_minor", "type" => "integer", "required?" => true}]
      }
    ]
  }

  @members [
    %{"name" => "amount_minor", "type" => "integer", "required?" => true},
    %{"name" => "note", "type" => "string"}
  ]

  defp palette, do: Palette.new(Map.put(Palette.core_types(), "myapp.typed", Typed))

  defp document(config) do
    block = Block.new("myapp.typed", id: "blk_TYP", config: config)
    root = Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [block]})
    Document.new(root, id: "bdoc_type_expr")
  end

  defp config_findings(config, opts \\ []) do
    assert {:error, findings} = Compiler.compile(document(config), palette(), opts)

    for finding <- findings, finding.stage == :config, do: finding
  end

  describe "the two arms the shared check admits" do
    # Sabotage: `stored_arm/2` answering `:name` for a list - the member
    # list is read as a name, the inline-only field below stops refusing,
    # and the second half of this test goes red (verified).
    test "a name and a member list are both an arm where the field admits both" do
      assert config_findings(%{"summary" => "cards.settlement"}) == []
      assert config_findings(%{"summary" => @members}) == []

      # And a value that is neither is refused, which is what tells the two
      # apart from bytes that are no arm at all.
      assert [finding] = config_findings(%{"summary" => 7})
      assert finding.message =~ "takes the name of a declared type or an inline shape"
    end

    # Sabotage: dropped the `:name in arms` test from `type_expr_finding/2`
    # - a name is admitted whatever the declaration says and this goes red
    # (verified).
    test "a name is refused where the field admits the inline arm alone" do
      config = %{"arms" => ["inline"], "summary" => "cards.settlement"}

      assert [finding] = config_findings(config)
      assert finding.message =~ "takes an inline shape"
      assert finding.config_key == "summary"
      assert finding.block_id == "blk_TYP"
    end

    # Sabotage: same clause with `:inline` - a member list is admitted on a
    # name-only field and this goes red (verified).
    test "a member list is refused where the field admits the name arm alone" do
      config = %{"arms" => ["name"], "summary" => @members}

      assert [finding] = config_findings(config)
      assert finding.message =~ "takes the name of a type the datamodel document declares"
    end
  end

  describe "the absent arm" do
    # Sabotage: `stored_arm/2` answering `:name` for `""` - the empty value
    # stops being the absent arm, the `allow_empty?: false` field stops
    # refusing, and the second assertion goes red (verified).
    test "an absent value is today's behaviour unless the field refuses one" do
      assert config_findings(%{}) == []
      assert config_findings(%{"summary" => ""}) == []
      assert config_findings(%{"summary" => nil}) == []

      refusing = %{"allow_empty" => false}

      assert [finding] = config_findings(refusing)
      assert finding.message =~ "does not admit an empty one"
      assert [_finding] = config_findings(Map.put(refusing, "summary", ""))
    end
  end

  describe "what is not a refusal" do
    # Sabotage: `type_expr_finding/2` answering a finding for a name that
    # `Declarations.fetch/2` does not resolve - the undeclared name starts
    # refusing and this goes red (verified).
    test "a name the document does not declare, and a compile with no datamodel" do
      config = %{"summary" => "cards.nothing_declares_this"}

      assert config_findings(config) == []
      assert config_findings(config, datamodel: @declarations) == []
    end
  end

  describe "the field is a type and never a path" do
    # Sabotage: added a `{:type_expr, _}` clause to `datamodel_path?/1`
    # answering true - the field draws path candidates it has no use for
    # and this goes red (verified).
    test "datamodel_path?/1 is false for it, and it has its own data tag" do
      [decl] = Typed.config_schema(%{})
      assert decl.type == {:type_expr, %{}}

      refute BlockType.datamodel_path?(decl)
      assert Shell.field_type_tag(decl.type) == "type_expr"
    end
  end

  describe "the term this package builds from the stored bytes" do
    # Sabotage: `stored_member/1` keeping a member whose name is empty -
    # the nameless row reaches the shape and the first assertion goes red
    # (verified).
    test "a member list becomes an inline shape, and the datamodel's rules are applied" do
      assert Environment.inline_shape(@members) ==
               {:shape,
                [
                  %{name: "amount_minor", type: "integer", required?: true},
                  %{name: "note", type: "string", required?: false}
                ]}

      # A member with no usable name contributes nothing, a repeated name
      # keeps its first occurrence, and a member's type is never absent.
      assert Environment.inline_shape([
               %{"name" => "", "type" => "string"},
               %{"type" => "string"},
               %{"name" => "amount_minor", "type" => "integer", "required?" => true},
               %{"name" => "amount_minor", "type" => "string"},
               %{"name" => "note"}
             ]) ==
               {:shape,
                [
                  %{name: "amount_minor", type: "integer", required?: true},
                  %{name: "note", type: :unknown, required?: false}
                ]}

      # The spelling recurses: a member may hold a member list of its own.
      assert Environment.inline_shape([%{"name" => "inner", "type" => @members}]) ==
               {:shape,
                [
                  %{
                    name: "inner",
                    required?: false,
                    type:
                      {:shape,
                       [
                         %{name: "amount_minor", type: "integer", required?: true},
                         %{name: "note", type: "string", required?: false}
                       ]}
                  }
                ]}

      # Total: anything that is not a list is the datamodel's unknown.
      assert Environment.inline_shape("cards.settlement") == :unknown
      assert Environment.inline_shape(nil) == :unknown
    end
  end

  describe "the read check reaches the inline arm" do
    # Sabotage: dropped `type_of/2`'s `{:shape, members}` clause - the term
    # falls through to `parse/2`, which answers `:unknown`, and every
    # assertion here goes permissive rather than deciding (verified).
    test "an inline shape is checked through the datamodel's own satisfies/3" do
      declarations = Environment.declarations(%{datamodel: @declarations})
      shape = Environment.inline_shape(@members)

      narrower =
        Environment.inline_shape([%{"name" => "note", "type" => "string", "required?" => true}])

      # A declared record covers an inline shape member-wise.
      assert Environment.satisfies(declarations, "cards.settlement", narrower) ==
               {:missing, ["note"]}

      assert Environment.satisfies(declarations, "cards.settlement", shape) == :covers

      # An inline shape held never satisfies a declared record: a record's
      # identity is nominal and an unnamed shape has no name to be it by.
      assert Environment.satisfies(declarations, shape, "cards.settlement") == :not_assignable

      # And an unmet member is named rather than merely refused.
      assert Environment.satisfies(declarations, narrower, shape) == {:missing, ["amount_minor"]}
    end

    # Sabotage: `member_label/2` dropping the `?` on an unpromised member -
    # the rendering stops distinguishing the two and this goes red
    # (verified).
    test "an inline shape renders as its members, in authoring order" do
      assert Environment.type_label(%{}, Environment.inline_shape(@members)) ==
               "{amount_minor: integer, note?: string}"
    end
  end
end
