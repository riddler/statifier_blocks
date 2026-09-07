defmodule StatifierBlocks.ViewModel.PromotionsTest do
  @moduledoc """
  The readers a host asks a built view model: `find_node/2`, `parent_of/2`,
  `positions/1`, `sentence/1`, `shown_fields/1`, `fields_for/2`,
  `overlay_draft/2` and `drafted_field/2`.

  Asserted over the family's two worked-example documents rather than over
  a document written here, because what these answer is "where does this
  block sit" and "what does this block say" - questions whose interesting
  cases are a nested branch, a rail, and a second child in one slot, which
  the fixtures already carry and a purpose-built root would only imitate.

  Every one of them reads the struct `build/3` returned and derives nothing
  new, so this file is pure: it names no LiveView module and carries no
  headless wrapper, which is what proves these are askable with LiveView
  off the path.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{CoreFixtures, DocumentFixtures, ViewModel}
  alias StatifierBlocks.ViewModel.{Field, Form, Node}

  doctest StatifierBlocks.ViewModel,
    only: [find_node: 2, parent_of: 2, positions: 1, sentence: 1]

  defmodule TwoFields do
    @moduledoc """
    One visible field and one hidden one, so `shown_fields/1` has a list
    to reject something from: no `core.*` type declares a hidden field and
    the flag is a declaration, never something the view model derives.
    """

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config) do
      [
        %{key: "shown", type: :string, label: "Shown", required?: false, default: ""},
        %{
          key: "kept",
          type: :string,
          label: "Kept",
          required?: false,
          default: "",
          hidden?: true
        }
      ]
    end

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(%StatifierBlocks.Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defp worked_example, do: build(DocumentFixtures.worked_example())
  defp signup_wizard, do: build(DocumentFixtures.signup_wizard())

  defp build(document), do: ViewModel.build(document, CoreFixtures.palette(), [])

  # A one-block document of the local type above, built against a palette
  # that knows it: the only way to reach a declared hidden field, since no
  # `core.*` type declares one.
  defp two_fields_view_model do
    block = StatifierBlocks.Block.new("toy.two_fields", id: "blk_TWO", config: %{})
    document = StatifierBlocks.Document.new(block, id: "bdoc_TWO")

    palette =
      StatifierBlocks.Palette.new(
        Map.merge(StatifierBlocks.Palette.core_types(), %{"toy.two_fields" => TwoFields})
      )

    ViewModel.build(document, palette, [])
  end

  describe "find_node/2" do
    # sabotage: return the first child of the first slot rather than
    # recursing into every slot -> red
    test "answers the node carrying the id, however deeply nested" do
      view_model = worked_example()

      assert %Node{block_id: "blk_CAP", type: "myapp.capture"} =
               ViewModel.find_node(view_model, "blk_CAP")
    end

    # sabotage: drop the `%__MODULE__{}` clause -> red
    test "takes a view model or a node, and finds the root itself" do
      view_model = worked_example()
      root = view_model.root

      assert ViewModel.find_node(view_model, root.block_id) == root
      assert ViewModel.find_node(root, "blk_CAP") == ViewModel.find_node(view_model, "blk_CAP")
    end

    # sabotage: fall back to the root for an unmatched id -> red
    test "answers nil for an id no block carries" do
      assert ViewModel.find_node(worked_example(), "blk_ABSENT") == nil
    end
  end

  describe "parent_of/2" do
    # sabotage: return index 0 for every child instead of the found index
    # -> red
    test "answers {parent id, slot name, index} for a block in a slot" do
      view_model = signup_wizard()

      assert {"blk_WROOT", "body", 0} = ViewModel.parent_of(view_model, "blk_VAR")
      assert {"blk_WROOT", "body", 1} = ViewModel.parent_of(view_model, "blk_WGRP")
      assert {"blk_WGRP", "body", 1} = ViewModel.parent_of(view_model, "blk_CNV")
    end

    # sabotage: search only the first slot instead of every slot -> red
    test "reaches a block held in a slot that is not the body" do
      view_model = signup_wizard()

      assert {"blk_WGRP", "interrupts", 0} = ViewModel.parent_of(view_model, "blk_WINT")
      assert {"blk_WBR", "arm_variant_b", 0} = ViewModel.parent_of(view_model, "blk_VB")
    end

    # sabotage: answer {nil, nil, 0} for the root instead of nil -> red
    test "answers nil for the root, which sits in no slot, and for an absent id" do
      view_model = signup_wizard()

      assert ViewModel.parent_of(view_model, "blk_WROOT") == nil
      assert ViewModel.parent_of(view_model, "blk_ABSENT") == nil
    end
  end

  describe "positions/1" do
    # sabotage: stop recursing after the top level -> red
    test "answers parent_of/2's tuple for every block but the root" do
      view_model = signup_wizard()
      positions = ViewModel.positions(view_model)

      ids =
        view_model
        |> ViewModel.outline()
        |> Enum.map(fn {node, _depth, _kind} -> node.block_id end)

      assert Map.keys(positions) |> Enum.sort() == (ids -- ["blk_WROOT"]) |> Enum.sort()

      for id <- Map.keys(positions) do
        assert Map.fetch!(positions, id) == ViewModel.parent_of(view_model, id)
      end
    end

    # sabotage: put the root in the map under its own id -> red
    test "leaves the root out, the way parent_of/2 answers nil for it" do
      refute Map.has_key?(ViewModel.positions(signup_wizard()), "blk_WROOT")
    end
  end

  describe "sentence/1" do
    # sabotage: return `node.sentence` with no fallback clause -> red
    test "falls back to title/1 for a node carrying no sentence of its own" do
      node = signup_wizard() |> ViewModel.find_node("blk_WGRP")

      assert ViewModel.sentence(%{node | sentence: nil}) == ViewModel.title(node)
      assert ViewModel.sentence(%{node | sentence: ""}) == ViewModel.title(node)
      assert ViewModel.title(node) != ""
    end

    # sabotage: return `title/1` unconditionally, ignoring the declared
    # sentence -> red
    test "answers the node own declared sentence where there is one" do
      view_model = worked_example()

      for {node, _depth, _kind} <- ViewModel.outline(view_model),
          is_binary(node.sentence) and node.sentence != "" do
        assert ViewModel.sentence(node) == node.sentence
      end
    end

    # sabotage: answer nil for a node whose type declares no sentence
    # -> red
    test "is never blank for any block the fixtures carry" do
      for view_model <- [worked_example(), signup_wizard()],
          {node, _depth, _kind} <- ViewModel.outline(view_model) do
        sentence = ViewModel.sentence(node)

        assert is_binary(sentence) and sentence != ""
      end
    end
  end

  describe "shown_fields/1" do
    # sabotage: return `fields` unfiltered -> red
    test "rejects the hidden fields and keeps the rest in order" do
      node = two_fields_view_model() |> ViewModel.find_node("blk_TWO")
      fields = node.form.fields

      assert Enum.map(fields, & &1.key) == ["shown", "kept"]
      assert Enum.map(ViewModel.shown_fields(node), & &1.key) == ["shown"]
      refute Enum.any?(ViewModel.shown_fields(node), & &1.hidden?)
    end

    # sabotage: reject on `readonly?` rather than `hidden?` -> red
    test "leaves a node whose fields are all visible alone" do
      node = signup_wizard() |> ViewModel.find_node("blk_WBR")

      refute node.form.fields == []
      assert ViewModel.shown_fields(node) == node.form.fields
    end

    # sabotage: raise on a node with no form instead of answering [] -> red
    test "answers [] for a node with no form" do
      assert ViewModel.shown_fields(%Node{
               block_id: "blk_NONE",
               type: "toy.none",
               type_version: 1,
               status: :resolved,
               form: nil
             }) == []
    end
  end

  describe "fields_for/2" do
    # sabotage: return the node's slots' fields rather than its form's
    # -> red
    test "answers the fields of the block carrying the id" do
      view_model = signup_wizard()
      node = ViewModel.find_node(view_model, "blk_WBR")

      assert ViewModel.fields_for(view_model, "blk_WBR") == node.form.fields
      assert ViewModel.fields_for(view_model, "blk_WBR") != []
    end

    # sabotage: raise on an absent id instead of answering [] -> red
    test "answers [] for an absent block" do
      assert ViewModel.fields_for(signup_wizard(), "blk_ABSENT") == []
    end
  end

  describe "drafted_field/2" do
    # sabotage: read the draft at `[field.key]` always, ignoring
    # value_path/1 -> red
    test "takes the draft's value at the field's value path" do
      field = %Field{
        key: "cond",
        type: :string,
        label: "Condition",
        required?: false,
        default: "",
        value: "variant == 'b'",
        value_path: ["arms", 0, "cond"]
      }

      draft = %{"arms" => [%{"cond" => "variant == 'c'"}]}

      assert ViewModel.drafted_field(field, draft).value == "variant == 'c'"
    end

    # sabotage: return the field's default rather than the field when the
    # draft is silent -> red
    test "leaves a field the draft says nothing about untouched" do
      field = %Field{
        key: "duration",
        type: :string,
        label: "Duration",
        required?: true,
        default: "1h",
        value: "48h"
      }

      assert ViewModel.drafted_field(field, %{}) == field
      assert ViewModel.drafted_field(field, %{"other" => "x"}) == field
    end
  end

  describe "overlay_draft/2" do
    # sabotage: overlay the draft onto every field rather than only where
    # the draft has a value -> red
    test "shows the draft's values and keeps the document's elsewhere" do
      view_model = worked_example()
      node = ViewModel.find_node(view_model, "blk_WAI")

      assert %Form{fields: [%Field{key: "duration", value: "48h"} | _rest]} = node.form

      drafted = ViewModel.overlay_draft(node, %{"duration" => "72h"})

      assert %Field{key: "duration", value: "72h"} = hd(drafted.form.fields)
      assert ViewModel.overlay_draft(node, %{}) == node
    end

    # sabotage: touch `slots` as well as `form` -> red
    test "touches the form and nothing else - never the slots" do
      view_model = signup_wizard()
      node = ViewModel.find_node(view_model, "blk_WBR")

      drafted = ViewModel.overlay_draft(node, %{"arms" => []})

      assert drafted.slots == node.slots
      assert drafted.status == node.status
      assert drafted.findings == node.findings
    end

    # sabotage: drop the `nil` and `form: nil` clauses -> red
    test "passes nil and a formless node straight through" do
      formless = %Node{
        block_id: "blk_NONE",
        type: "toy.none",
        type_version: 1,
        status: :resolved,
        form: nil
      }

      assert ViewModel.overlay_draft(nil, %{"a" => 1}) == nil
      assert ViewModel.overlay_draft(formless, %{"a" => 1}) == formless
    end
  end
end
