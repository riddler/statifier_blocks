defmodule StatifierBlocks.FieldTypeBindingTest do
  # ADR-0002 decision 7, amended 2026-09-28: a block type's declared field
  # types are binding. The package holds a config to them before
  # `validate_config/1`, at the compiler's `:config` stage, the edit gate and
  # the view model, judged through the one field-type mapping.
  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, BlockType, Compiler, Document, Edit, Palette, ViewModel}
  alias StatifierBlocks.ViewModel.Node

  defmodule LaxNotice do
    @moduledoc false
    # A library-loan host type whose validate_config/1 accepts anything, so
    # every refusal below is the binding check's own. One field per arm of
    # the closed field-type set, a field at a path of string keys, one at a
    # list position, and two declarations the mapping cannot read.
    use StatifierBlocks.BlockType

    @impl true
    def config_schema(_config) do
      [
        field("subject", :string, "Overdue"),
        field("renewal_rule", :expression, "true"),
        field("grace", :duration, "P7D"),
        field("patron_path", {:path, %{}}, "patron.email"),
        field("days_late", :integer, 1),
        field("waived", :boolean, false),
        field("channel", {:select, [{"email", "Email"}, {"letter", "Letter"}]}, "email"),
        field("copies", {:list, :string}, []),
        field("manifest", {:type_expr, %{}}, ""),
        Map.put(field("branch", :string, ""), :value_path, ["desk", "branch"]),
        Map.put(field("first_item", :string, ""), :value_path, ["items", 0, "title"]),
        field("speed", {:select, []}, "slow"),
        field("tiers", {:list, {:select, [{1, "One"}]}}, [])
      ]
    end

    defp field(key, type, default),
      do: %{key: key, type: type, label: key, required?: false, default: default}

    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule StrictNotice do
    @moduledoc false
    # A host type whose validate_config/1 also refuses a non-string subject,
    # so the order of the two sets of findings can be read.
    use StatifierBlocks.BlockType

    @impl true
    def config_schema(_config),
      do: [%{key: "subject", type: :string, label: "Subject", required?: true, default: ""}]

    @impl true
    def validate_config(%{"subject" => subject}) when not is_binary(subject),
      do: {:error, [{"subject", "must be text"}]}

    def validate_config(_config), do: :ok

    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defp findings(config), do: BlockType.field_type_findings(LaxNotice, config)

  defp keys(config), do: config |> findings() |> Enum.map(&elem(&1, 0))

  describe "each arm through the one mapping" do
    # Sabotage: `json_type?("string", value)` answering `true` for any value
    # -> the four string arms admit an integer and this goes red.
    test "a string arm refuses a value that is not a string, and admits one that is" do
      for key <- ["subject", "renewal_rule", "grace", "patron_path"] do
        assert keys(%{key => 7}) == [key], key
        assert keys(%{key => ["a"]}) == [key], key
        assert keys(%{key => "text"}) == [], key
      end
    end

    # Sabotage: `json_type?("integer", value)` answering `true` -> the
    # string and the boolean are admitted and this goes red.
    test "the integer arm refuses a string and a boolean" do
      assert keys(%{"days_late" => "three"}) == ["days_late"]
      assert keys(%{"days_late" => true}) == ["days_late"]
      assert keys(%{"days_late" => 3}) == []
    end

    # Sabotage: `json_type?("boolean", value)` answering `true` -> the
    # string "yes" is admitted and this goes red.
    test "the boolean arm refuses anything but true and false" do
      assert keys(%{"waived" => "yes"}) == ["waived"]
      assert keys(%{"waived" => 0}) == ["waived"]
      assert keys(%{"waived" => true}) == []
      assert keys(%{"waived" => false}) == []
    end

    # Sabotage: `enum_admits?/2` answering `true` -> the pigeon is
    # admitted and this goes red.
    test "the select arm refuses a value that is not one of its choices" do
      assert keys(%{"channel" => "pigeon"}) == ["channel"]
      assert keys(%{"channel" => 1}) == ["channel"]
      assert keys(%{"channel" => "letter"}) == []
    end

    # Sabotage: `items_admit?/2` answering `true` -> the integer element is
    # admitted and this goes red.
    test "the list arm refuses a non-list and a list with an element its inner type refuses" do
      assert keys(%{"copies" => "branch"}) == ["copies"]
      assert keys(%{"copies" => ["branch", 7]}) == ["copies"]
      assert keys(%{"copies" => ["branch", nil]}) == ["copies"]
      assert keys(%{"copies" => ["branch", "desk"]}) == []
      assert keys(%{"copies" => []}) == []
    end

    # Sabotage: the `{:type_expr, _opts}` clause of `field_type_finding/2`
    # removed -> the integer draws a second finding from the binding check
    # and the compile below carries two, red.
    test "a type_expr field is left to type_expr_findings/2, with no second finding" do
      assert keys(%{"manifest" => 7}) == []
      assert keys(%{"manifest" => %{"name" => "x"}}) == []

      assert [{"manifest", _message}] =
               BlockType.type_expr_findings(LaxNotice, %{"manifest" => 7})

      assert [finding] = compile_findings(LaxNotice, %{"manifest" => 7})
      assert finding.config_key == "manifest"
    end

    # Sabotage: `declared/1`'s `:integer` clause answering "a string" ->
    # the message names the wrong type and this goes red.
    test "a finding names the field's key and its declared type" do
      assert [{"days_late", message}] = findings(%{"days_late" => "three"})
      assert message == "the days_late field is declared an integer, and holds a string"

      assert [{"channel", message}] = findings(%{"channel" => "pigeon"})

      assert message ==
               ~s(the channel field is declared one of "email", "letter", and holds "pigeon")
    end
  end

  describe "what the binding check does not judge" do
    # Sabotage: the `when not is_nil(value)` guard dropped from
    # `field_type_finding/2` -> every null is refused and this goes red.
    test "an absent key and a null are left to validate_config/1" do
      assert findings(%{}) == []

      for key <- ["subject", "days_late", "waived", "channel", "copies"] do
        assert keys(%{key => nil}) == [], key
      end
    end

    # Sabotage: `binding_schema/1`'s `:error` answered as `{:ok, %{"type" =>
    # "string"}}` -> the unreadable select refuses the integer and this goes red.
    test "a declaration the mapping cannot read is not judged" do
      assert keys(%{"speed" => 3}) == []
      assert keys(%{"tiers" => "not a list"}) == []
    end

    # Sabotage: `Enum.all?(path, &is_binary/1)` dropped from
    # `field_type_finding/2` -> the positional title is judged and the second
    # assertion goes red.
    test "a field is judged at a path of string keys, never at a list position" do
      assert keys(%{"desk" => %{"branch" => 4}}) == ["branch"]
      assert keys(%{"items" => [%{"title" => 4}]}) == []
    end

    test "a path that reaches no value is the absent case" do
      assert keys(%{"desk" => "front"}) == []
      assert keys(%{"desk" => ["front"]}) == []
      assert keys(%{"desk" => %{}}) == []
    end

    test "a declaration list that is not declarations is not judged" do
      assert BlockType.field_type_findings({__MODULE__.Stateful, [%{nope: 1}]}, %{"a" => 1}) ==
               []
    end
  end

  defmodule Stateful do
    @moduledoc false
    # A `{module, state}` entry whose state is the declaration list it answers.
    def config_schema(fields, _config), do: fields
  end

  # --- the three config seams --------------------------------------------------

  defp palette(module), do: Palette.new(Map.put(Palette.core_types(), "library.notice", module))

  defp document(config) do
    block = Block.new("library.notice", id: "blk_NOTICE", config: config)
    root = Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [block]})
    Document.new(root, id: "bdoc_notices")
  end

  defp compile_findings(module, config) do
    case Compiler.compile(document(config), palette(module)) do
      {:ok, _compiled} -> []
      {:error, findings} -> for finding <- findings, finding.stage == :config, do: finding
    end
  end

  defp gate(module, config) do
    Edit.check_config(
      palette(module),
      document(%{"subject" => "Overdue"}),
      {:update_config, "blk_NOTICE", config}
    )
  end

  defp field_messages(module, config) do
    %Node{form: form} =
      config
      |> document()
      |> ViewModel.build(palette(module), [])
      |> Map.fetch!(:root)
      |> Map.fetch!(:slots)
      |> Enum.flat_map(& &1.children)
      |> Enum.find(&(&1.block_id == "blk_NOTICE"))

    for field <- form.fields, finding <- field.findings, do: {field.key, finding.message}
  end

  describe "the three config seams" do
    # Sabotage: `types` dropped from `Compiler.config_findings/2`'s list ->
    # the lax type's integer subject compiles and this goes red.
    test "the compiler's :config stage refuses a value its declared type refuses" do
      assert [finding] = compile_findings(LaxNotice, %{"subject" => 42})
      assert finding.config_key == "subject"
      assert finding.block_id == "blk_NOTICE"
      assert finding.message =~ "declared a string"
      assert compile_findings(LaxNotice, %{"subject" => "Overdue"}) == []
    end

    # Sabotage: `BlockType.field_type_findings/2` dropped from
    # `Edit.config_findings/2` -> the gate answers :ok and this goes red.
    test "the edit gate refuses a value its declared type refuses" do
      assert {:error, {:invalid_config, "blk_NOTICE", [{"subject", message}]}} =
               gate(LaxNotice, %{"subject" => 42})

      assert message =~ "declared a string"
      assert gate(LaxNotice, %{"subject" => "Overdue"}) == :ok
    end

    # Sabotage: `BlockType.field_type_findings/2` dropped from
    # `ViewModel.config_findings/3` -> the field carries no finding, red.
    test "the view model places the finding under the field" do
      assert [{"subject", message}] = field_messages(LaxNotice, %{"subject" => 42})
      assert message =~ "declared a string"
      assert field_messages(LaxNotice, %{"subject" => "Overdue"}) == []
    end

    # Sabotage: `own` placed ahead of the type checks in
    # `Edit.config_findings/2` -> the order assertion goes red.
    test "the binding findings come first and validate_config/1 still runs, at all three" do
      config = %{"subject" => 42}
      binding = "the subject field is declared a string, and holds an integer"

      assert {:error, {:invalid_config, "blk_NOTICE", gated}} = gate(StrictNotice, config)
      assert gated == [{"subject", binding}, {"subject", "must be text"}]

      assert Enum.map(compile_findings(StrictNotice, config), & &1.message) ==
               [binding, "must be text"]

      assert field_messages(StrictNotice, config) ==
               [{"subject", binding}, {"subject", "must be text"}]
    end
  end
end
