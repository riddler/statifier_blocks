defmodule StatifierBlocks.ViewModelTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, BlockTypeFixtures, Document, Finding, Palette, ViewModel}
  alias StatifierBlocks.ViewModel.{Field, Form, Node, PaletteGroup, Slot}

  # The palette every test in this file builds from: the real `core.*`
  # vocabulary plus `BlockTypeFixtures.Minimal`, a type that implements only
  # `StatifierBlocks.BlockType`'s five required callbacks and none of the
  # four optional ones - `toy.minimal` is therefore the one type in this
  # palette with no `palette_entry/0` at all, which is exactly what the d10
  # defaults test needs.
  defp palette do
    Palette.new(Map.merge(Palette.core_types(), BlockTypeFixtures.raw_palette()))
  end

  # A signup wizard root: a bare `core.sequence` with one child in `body`.
  # `child` is inserted as given, so a test can hand this whatever block it
  # needs to inspect once the view model is built.
  defp document_with(child) do
    root = Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [child]})
    Document.new(root, id: "bdoc_SIGNUP", revision: 3)
  end

  defp build(document, findings \\ []), do: ViewModel.build(document, palette(), findings)

  # `document.blocks/1` is pre-order, so the second element is always the
  # first child under `blk_ROOT`'s `body` slot for the documents this file
  # builds with `document_with/1`.
  defp find_node(%ViewModel{root: root}, block_id) do
    find_node(root, block_id)
  end

  defp find_node(%Node{block_id: block_id} = node, block_id), do: node

  defp find_node(%Node{slots: slots}, block_id) do
    Enum.find_value(slots, fn slot -> find_slot_node(slot, block_id) end)
  end

  defp find_slot_node(%Slot{children: children}, block_id) do
    Enum.find_value(children, fn child -> find_node(child, block_id) end)
  end

  # Every finding actually placed anywhere in `view_model`, walked from the
  # root plus `orphan_findings` - used by the conservation property below.
  defp placed_findings(%ViewModel{root: root, orphan_findings: orphan}) do
    node_findings(root) ++ orphan
  end

  defp node_findings(%Node{findings: findings, slots: slots, form: form}) do
    findings ++ Enum.flat_map(slots, &slot_findings/1) ++ form_findings(form)
  end

  defp slot_findings(%Slot{findings: findings, children: children}) do
    findings ++ Enum.flat_map(children, &node_findings/1)
  end

  defp form_findings(nil), do: []

  defp form_findings(%Form{fields: fields, unrouted: unrouted}) do
    unrouted ++ Enum.flat_map(fields, & &1.findings)
  end

  describe "d10: palette_entry defaults" do
    # Sabotage: change `default_entry/1`'s `group: "Other"` to `group:
    # "Uncategorized"` - this test fails on the group assertion. Dropping
    # `slot_outcome_key: %{}` from `@default_entry` fails it the same way,
    # which is what keeps d10's key set complete rather than nearly so.
    test "a type with no palette_entry/0 still yields every key, label the type name" do
      child = Block.new("toy.minimal", id: "blk_MIN")
      vm = build(document_with(child))
      node = find_node(vm, "blk_MIN")

      assert node.entry == %{
               label: "toy.minimal",
               group: "Other",
               description: "",
               icon: nil,
               keywords: [],
               order: 0,
               layout: :stack,
               slot_style: %{},
               slot_outcome_key: %{}
             }
    end

    # Sabotage: change `palette_entry_with_defaults/2` to return `raw`
    # verbatim instead of merging it over the defaults - this test fails
    # because `core.parallel`'s entry would carry no `label`/`group`/etc.
    test "a type with a real palette_entry/0 keeps its own values over the defaults" do
      child = Block.new("core.wait", id: "blk_W", config: %{"duration" => "PT1S"})
      vm = build(document_with(child))
      node = find_node(vm, "blk_W")

      assert node.entry.label == "Wait"
      assert node.entry.group == "Structure"
      assert node.entry.order == 5
    end
  end

  describe "d10: real presentation metadata reaching the node" do
    # Sabotage: in `build_resolved_node/4`, pass `%{}` instead of `entry` to
    # the `%Node{}` it returns - this test fails because `layout` reverts to
    # the default `:stack`.
    test "core.parallel's layout: :columns reaches the node" do
      lane = Block.new("core.wait", id: "blk_LANE", config: %{"duration" => "PT1S"})

      parallel =
        Block.new("core.parallel",
          id: "blk_PAR",
          config: %{"lanes" => ["started"]},
          slots: %{"lane_started" => [lane]}
        )

      vm = build(document_with(parallel))
      node = find_node(vm, "blk_PAR")

      assert node.entry.layout == :columns
    end

    # Sabotage: in `Core.ResumableGroup.palette_entry/0`'s call site, feed
    # `slot_style/2` a fresh `%{}` instead of `entry.slot_style` - this
    # test fails because every slot reports `:primary`.
    test "core.resumable_group's slot_style reaches its slots" do
      group =
        Block.new("core.resumable_group", id: "blk_RG", config: %{"history" => "deep"})

      vm = build(document_with(group))
      node = find_node(vm, "blk_RG")

      body = Enum.find(node.slots, &(&1.name == "body"))
      interrupts = Enum.find(node.slots, &(&1.name == "interrupts"))

      assert body.style == :primary
      assert interrupts.style == :secondary
    end
  end

  describe "d9: form fields" do
    # Sabotage: in `build_fields/3`, use `default` instead of
    # `Map.get(config, key, default)` for `value` - this test fails because
    # the field would carry the schema default rather than the stored
    # value.
    test "fields come from config_schema/1 and carry the block's current value" do
      group = Block.new("core.resumable_group", id: "blk_RG", config: %{"history" => "deep"})
      vm = build(document_with(group))
      node = find_node(vm, "blk_RG")

      assert [%Field{key: "history", value: "deep", default: "shallow"}] = node.form.fields
    end

    # Sabotage: memoize `build_resolved_node/4`'s `schema` across calls
    # (e.g. compute it once outside `build/3` and thread the same value in)
    # instead of recomputing it every `build/3` - this test fails because
    # the second view model's field list would still have one field.
    test "the schema is re-derived after a config change, not cached" do
      one_arm =
        Block.new("core.branch",
          id: "blk_BR",
          config: %{"arms" => [%{"slot" => "arm_a", "cond" => "true"}]}
        )

      two_arms =
        Block.new("core.branch",
          id: "blk_BR",
          config: %{
            "arms" => [
              %{"slot" => "arm_a", "cond" => "true"},
              %{"slot" => "arm_b", "cond" => "false"}
            ]
          }
        )

      before_node = build(document_with(one_arm)) |> find_node("blk_BR")
      after_node = build(document_with(two_arms)) |> find_node("blk_BR")

      assert length(before_node.form.fields) == 1
      assert length(after_node.form.fields) == 2
    end

    # sabotage: in `build_fields/3`, read `Map.get(config, key, default)`
    # rather than `value_at/3` - a branch arm's condition comes back as the
    # empty default, which is the "renders empty" half of the defect
    # ADR-0002 decision 7's `value_path` amendment fixes.
    test "a field with a value_path carries the value at that path" do
      branch =
        Block.new("core.branch",
          id: "blk_BR",
          config: %{
            "arms" => [
              %{"slot" => "arm_a", "cond" => "budget > 0"},
              %{"slot" => "arm_b"}
            ]
          }
        )

      node = branch |> document_with() |> build() |> find_node("blk_BR")

      assert [
               %Field{key: "arm_a", value: "budget > 0", value_path: ["arms", 0, "cond"]},
               %Field{key: "arm_b", value: "", value_path: ["arms", 1, "cond"]}
             ] = node.form.fields
    end

    # sabotage: have `Field.value_path/1` return the struct field unchanged -
    # an ordinary field answers `nil` and every caller has to branch on it.
    test "a field without one addresses its own key" do
      group = Block.new("core.resumable_group", id: "blk_RG", config: %{"history" => "deep"})

      [field] =
        group |> document_with() |> build() |> find_node("blk_RG") |> then(& &1.form.fields)

      assert field.value_path == nil
      assert Field.value_path(field) == ["history"]
    end
  end

  describe "d11 routing" do
    # Sabotage: in `route_one_finding/4`'s `{:block, _id}` clause, put
    # `finding` into `unrouted_acc` instead of `block_acc` - this test
    # fails because the finding never reaches `node.findings`.
    test "a :block anchor routes to that node's findings" do
      child = Block.new("core.wait", id: "blk_W", config: %{"duration" => "PT1S"})
      finding = Finding.new({:block, "blk_W"}, :lint, "no runtime handler registered")

      vm = build(document_with(child), [finding])
      node = find_node(vm, "blk_W")

      assert finding in node.findings
    end

    # Sabotage: in `build_resolved_node/4`, build `declared_slots` from
    # `Map.get(slot_findings, name, [])` unconditionally without ever
    # populating `slot_findings` from `route_one_finding/4` (i.e. drop the
    # `{:slot, ...}` clause's `MapSet.member?` branch and always fall to
    # the node) - this test fails because `body`'s slot never carries the
    # finding.
    test "a :slot anchor naming a slot the node carries routes to that slot's findings" do
      child = Block.new("core.wait", id: "blk_W", config: %{"duration" => "PT1S"})
      finding = Finding.new({:slot, "blk_ROOT", "body"}, :arity, "needs at least one step")

      vm = build(document_with(child), [finding])
      root_node = vm.root
      body = Enum.find(root_node.slots, &(&1.name == "body"))

      assert finding in body.findings
      refute finding in root_node.findings
    end

    # Sabotage: in `route_one_finding/4`'s `{:slot, ...}` clause, drop the
    # `else` branch (the fallback) and always insert into `slot_acc` even
    # when `name` names no real slot - this test fails because the finding
    # would vanish (never surfacing on `root_node.findings`, and never
    # matching a real slot to render it under either).
    test "a :slot anchor naming a slot the node does not carry falls back to the node's findings" do
      child = Block.new("core.wait", id: "blk_W", config: %{"duration" => "PT1S"})
      finding = Finding.new({:slot, "blk_ROOT", "no_such_slot"}, :arity, "ghost slot")

      vm = build(document_with(child), [finding])

      assert finding in vm.root.findings
      refute Enum.any?(vm.root.slots, &(finding in &1.findings))
    end

    # Sabotage: in `route_one_finding/4`'s `{:config, ...}` clause, invert
    # the `MapSet.member?/2` check - this test fails because a finding for
    # a real field would land in `unrouted` instead of the field.
    test "a :config anchor matching a schema field routes to that field's findings" do
      group = Block.new("core.resumable_group", id: "blk_RG", config: %{"history" => "deep"})
      finding = Finding.new({:config, "blk_RG", "history"}, :config, "pick shallow or deep")

      vm = build(document_with(group), [finding])
      node = find_node(vm, "blk_RG")
      field = Enum.find(node.form.fields, &(&1.key == "history"))

      assert finding in field.findings
      assert node.form.unrouted == []
    end

    # Sabotage: in `build/3`, replace the `Enum.split_with/2` call with
    # `{all_findings, []}` (route nothing to `orphan_findings`) - this test
    # fails because the ghost-anchored finding never reaches
    # `vm.orphan_findings` (and it is also silently dropped from the tree
    # entirely, since `build_node/2` only ever walks real document blocks).
    test "an anchor naming a block id not in the document lands in orphan_findings" do
      child = Block.new("core.wait", id: "blk_W", config: %{"duration" => "PT1S"})
      finding = Finding.new({:block, "blk_GHOST"}, :lint, "names nothing in this document")

      vm = build(document_with(child), [finding])

      assert finding in vm.orphan_findings
      refute finding in vm.root.findings
    end
  end

  describe "the \"arms\" case" do
    # Sabotage: in `build_resolved_node/4`, add `"arms"` to `schema_keys`
    # (`MapSet.put(MapSet.new(schema, & &1.key), "arms")`) - this test
    # fails because the finding now matches a "field" and lands in
    # `config_findings` (an empty `%Field{}` list, since no real field is
    # keyed `"arms"`), never reaching `form.unrouted`.
    test "a Core.Branch \"arms\"-keyed finding lands in form.unrouted and stays in top-level findings" do
      # No "cond" on the arm - `Core.Branch.validate_config/1` reports this
      # against `"arms"`, a key `config_schema/1` never declares as a field.
      malformed =
        Block.new("core.branch", id: "blk_BR", config: %{"arms" => [%{"slot" => "arm_a"}]})

      vm = build(document_with(malformed))
      node = find_node(vm, "blk_BR")

      assert [%Finding{anchor: {:config, "blk_BR", "arms"}} = arms_finding] = node.form.unrouted
      assert arms_finding in vm.findings
    end
  end

  describe "the conservation property" do
    # Sabotage: in `build_resolved_node/4`, hard-code `findings: []` on the
    # returned `%Node{}` instead of `findings: block_findings` - this test
    # fails because the `:lint` and `:resolution`-adjacent findings placed
    # on resolved blocks vanish from the count `placed_findings/1` walks.
    test "findings in equals findings placed, over a document mixing all five finding sources" do
      # :resolution (derived) - "signup.legacy_step" is in no palette.
      legacy =
        Block.new("signup.legacy_step", id: "blk_LEGACY", config: %{"note" => "pre-editor"})

      # :config (derived) - an invalid duration fails Core.Wait.validate_config/1.
      bad_wait =
        Block.new("core.wait", id: "blk_BADWAIT", config: %{"duration" => "not-a-duration"})

      # :arity, :assignability, :lint (caller-supplied).
      arity_finding = Finding.new({:slot, "blk_ROOT", "body"}, :arity, "too few children")

      assignability_finding =
        Finding.new({:block, "blk_BADWAIT"}, :assignability, "type mismatch")

      lint_finding = Finding.new({:block, "blk_LEGACY"}, :lint, "no runtime handler registered")

      root =
        Block.new("core.sequence",
          id: "blk_ROOT",
          slots: %{"body" => [legacy, bad_wait]}
        )

      document = Document.new(root, id: "bdoc_SIGNUP")

      vm = build(document, [arity_finding, assignability_finding, lint_finding])

      assert length(placed_findings(vm)) == length(vm.findings)
    end
  end

  describe "findings_count" do
    # Sabotage: in `findings_count/3`, drop the `children_count` term from
    # `slots_count`'s reduction - this test fails because the root's count
    # would be `0` instead of `1`, since the finding lives two levels down.
    test "covers a subtree, not only the node's own findings" do
      grandchild = Block.new("core.wait", id: "blk_GC", config: %{"duration" => "PT1S"})
      finding = Finding.new({:block, "blk_GC"}, :lint, "deep finding")

      vm = build(document_with(grandchild), [finding])

      assert vm.root.findings_count == 1
      assert vm.root.findings == []
    end
  end

  describe "d12: unresolvable blocks" do
    # Sabotage: in `build_unresolvable_node/3`, hard-code
    # `raw_config_json(%{})` instead of `raw_config_json(block.config)` -
    # this test fails because the decoded JSON would be `%{}` instead of
    # carrying `"note"`.
    test "renders status, no form, canonical config JSON, a finding, and its children" do
      grandchild = Block.new("core.wait", id: "blk_GC", config: %{"duration" => "PT1S"})

      legacy =
        Block.new("signup.legacy_step",
          id: "blk_LEGACY",
          config: %{"note" => "pre-editor"},
          slots: %{"raw_slot" => [grandchild]}
        )

      vm = build(document_with(legacy))
      node = find_node(vm, "blk_LEGACY")

      assert node.status == {:unresolvable, {:unknown_block_type, "signup.legacy_step"}}
      assert node.form == nil
      assert is_binary(node.raw_config_json)
      assert JSON.decode!(node.raw_config_json) == %{"note" => "pre-editor"}
      assert [%Finding{source: :resolution, anchor: {:block, "blk_LEGACY"}}] = node.findings

      [raw_slot] = node.slots
      assert raw_slot.name == "raw_slot"
      assert raw_slot.declared? == false
      assert raw_slot.arity == nil

      [child_node] = raw_slot.children
      assert child_node.block_id == "blk_GC"
      assert child_node.status == :ok
    end
  end

  describe "palette_groups" do
    # Sabotage: in `palette_groups/1`, sort entries by `entry.label` alone
    # (drop `entry.order` from the sort key) - this test fails because
    # "Group" (order 1) and "Resumable group" (order 2) would swap with
    # "Branch" (order 3) if alphabetical, breaking the asserted order.
    test "groups by entry.group and sorts group name -> order -> label" do
      vm = build(document_with(Block.new("core.sequence", id: "blk_SEQ")))

      # `BlockTypeFixtures.raw_palette/0` contributes "toy.budget_check" (its own
      # `palette_entry/0` puts it in "Authorization") and three types with no
      # `palette_entry/0` at all, which default to "Other" - alongside the
      # real `core.*` types, all "Structure". Three groups, sorted by
      # name: "Authorization" < "Other" < "Structure".
      assert [
               %PaletteGroup{name: "Authorization"} = authorization,
               %PaletteGroup{name: "Other"} = other,
               %PaletteGroup{name: "Structure"} = structure
             ] = vm.palette_groups

      assert Enum.map(authorization.entries, & &1.type_name) == ["toy.budget_check"]

      assert Enum.map(other.entries, & &1.type_name) == [
               "toy.erroring_migration",
               "toy.minimal",
               "toy.no_migration"
             ]

      assert Enum.map(structure.entries, & &1.entry.label) == [
               "Sequence",
               "Group",
               "Resumable group",
               "Branch",
               "Parallel",
               "Wait",
               "On event",
               "Invoke",
               "Raise",
               "Assign",
               "Send",
               "Subchart",
               "For each"
             ]
    end
  end
end
