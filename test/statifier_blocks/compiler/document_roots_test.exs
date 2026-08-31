defmodule StatifierBlocks.Compiler.DocumentRootsTest do
  @moduledoc """
  The document's own `datamodel` key (ADR-0001 decision 11): a second
  declaration surface that follows the `:declare` compile option's roots
  rather than leading them, host-wins on a name collision.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{
    Block,
    Compiler,
    CoreFixtures,
    Document,
    DocumentFixtures,
    Palette,
    Provenance
  }

  alias StatifierBlocks.Compiler.{Finding, StateId}
  alias StatifierBlocks.Document.DatamodelEntry

  describe "the emitted <datamodel>" do
    # sabotage: change `emit_stage/3` to hoist `kept_document ++ host`
    # instead of `host ++ kept_document` -> the document's roots would
    # lead instead of follow, and this goes red (verified)
    test "holds host roots, then document roots, then block-declared roots, in that order" do
      document =
        loop_document([
          %DatamodelEntry{id: "parked", expr: "false"},
          %DatamodelEntry{id: "steps", expr: "['email', 'profile']"}
        ])

      scxml = compile!(document, declare: [{"targets", nil}])

      assert scxml =~
               ~s(<datamodel><data id="targets"/><data expr="false" id="parked"/>) <>
                 ~s(<data expr="['email', 'profile']" id="steps"/>) <>
                 ~s(<data expr="0" id="s_blk_F__i"/><data id="s_blk_F__items"/>) <>
                 ~s(<data id="step"/></datamodel>)
    end

    # sabotage: in `DeclaredRoots.document_declarations/1`, change
    # `declare(entry.id, entry.expr)` to `declare(entry.id, "'x'")` ->
    # every document root would carry a spurious `expr`, and this test
    # (which asserts no `expr` attribute at all) goes red (verified)
    test "a document root with no expr emits <data id=.../> with no expr attribute" do
      scxml = compile!(document([%DatamodelEntry{id: "targets"}]))

      assert scxml =~ ~s(<datamodel><data id="targets"/></datamodel>)
    end

    # sabotage: in `DeclaredRoots.document_declarations/1`, change
    # `declare(entry.id, entry.expr)` to `declare(entry.id, nil)` -> a
    # document root's `expr` would never reach the emitted bytes -> red
    test "a document root with an expr carries it verbatim" do
      scxml = compile!(document([%DatamodelEntry{id: "targets", expr: "'a'"}]))

      assert scxml =~ ~s(<datamodel><data expr="'a'" id="targets"/></datamodel>)
    end

    # sabotage: in `document_roots/3`, substitute a one-entry phantom
    # list whenever `entries == []` -> a document declaring no roots
    # would grow a `<datamodel>` it did not have before, and this goes
    # red (verified)
    test "a document declaring no roots emits no <datamodel> at all" do
      refute compile!(document()) =~ "<datamodel>"
      refute compile!(document([])) =~ "<datamodel>"
    end
  end

  describe "host-wins shadowing (a warning, not a refusal)" do
    setup do
      document = document([%DatamodelEntry{id: "targets", expr: "'document'"}])
      {:ok, compiled} = compile(document, declare: [{"targets", "'host'"}])

      %{compiled: compiled}
    end

    # sabotage: in `document_roots/3`, return `document` instead of
    # `kept` (stop dropping the shadowed root) -> the host's declaration
    # would collide with the document's un-dropped one inside `hoist/1`,
    # and this compile would refuse as F6 `:duplicate_binding` instead
    # of succeeding with a warning -> red
    test "compiles successfully", %{compiled: compiled} do
      assert %StatifierBlocks.Compiled{} = compiled
    end

    # sabotage: same target as above - `DeclaredRoots.shadowed/2` keeping
    # the document root instead of dropping it -> the host's expr would
    # be overwritten in the emitted bytes -> red
    test "emits the host's expr and drops the document's", %{compiled: compiled} do
      assert compiled.scxml =~ ~s(<datamodel><data expr="'host'" id="targets"/></datamodel>)
      refute compiled.scxml =~ "'document'"
    end

    # sabotage: drop the `Enum.map(shadowed_ids, &shadowed_finding(&1,
    # root_id))` call in `document_roots/3`, returning `[]` for warnings
    # unconditionally -> the shadowed collision would compile silently
    # with no warning at all -> red
    test "puts exactly one warning on Compiled.warnings", %{compiled: compiled} do
      assert [%Finding{} = finding] = compiled.warnings

      assert finding.stage == :emit
      assert finding.severity == :warning
      assert finding.code == :shadowed_document_root
      assert finding.reason == {:shadowed_document_root, "targets"}
      assert finding.block_id == "blk_ROOT"
      assert finding.config_key == nil
      assert finding.fault == :package
    end
  end

  describe "collision with a block-declared root (F6, unchanged)" do
    # sabotage: in `emit_stage/3`, prepend only `host` (drop
    # `kept_document` from what `hoist/1` walks) -> a document root
    # colliding with a block-declared one would never reach the walk at
    # all, and this compile would succeed instead of refusing -> red
    test "a document root a loop also binds is F6 :duplicate_binding against the loop" do
      document = loop_document([%DatamodelEntry{id: "step"}])

      assert {:error, [%Finding{} = finding]} =
               Compiler.compile(document, Palette.new(Palette.core_types()))

      assert finding.stage == :emit
      assert finding.code == :duplicate_binding
      assert finding.reason == {:duplicate_binding, "blk_F", "step"}
      assert finding.block_id == "blk_F"
      assert finding.config_key == "item_as"
      assert finding.fault == :author
    end
  end

  describe "provenance (decision 5)" do
    setup do
      {:ok, compiled} = compile(document([%DatamodelEntry{id: "targets"}]))
      %{compiled: compiled}
    end

    # sabotage: drop the `Enum.map/2` that stamps the owner in
    # `document_roots/3`, leaving `owner: nil` -> the serializer records
    # no span for the root's bytes, the provenance map stops being total
    # over the emitted bytes, and this goes red on `owner_at/2`
    test "a document root's bytes are owned by the root block", %{compiled: compiled} do
      offset = :binary.match(compiled.scxml, ~s(<data id="targets"/>)) |> elem(0)

      assert {:ok, owner} = Provenance.owner_at(compiled.provenance, offset)
      assert owner.block_id == "blk_ROOT"
      assert owner.role == ":datamodel"
      assert owner.config_key == nil
    end

    # sabotage: spell `@document_role` `"datamodel"` (dropping the
    # leading colon) -> `StateId.role?/1` would accept it, so this
    # surface's role would stop being distinguishable from one a block
    # mints from a state id, and this goes red
    test "the role is not one a block could mint from a state id", %{compiled: compiled} do
      offset = :binary.match(compiled.scxml, ~s(<data id="targets"/>)) |> elem(0)
      {:ok, owner} = Provenance.owner_at(compiled.provenance, offset)

      refute StateId.role?(owner.role)
    end

    # sabotage: spell `@document_role` the same as `@host_role`
    # (`":declare"`) -> a document root's provenance would become
    # indistinguishable from a host root's, and this goes red
    test "the role is distinct from the host's own @host_role", %{compiled: compiled} do
      offset = :binary.match(compiled.scxml, ~s(<data id="targets"/>)) |> elem(0)
      {:ok, owner} = Provenance.owner_at(compiled.provenance, offset)

      assert owner.role == ":datamodel"
      refute owner.role == ":declare"
    end
  end

  describe "determinism (decision 6)" do
    # sabotage: none needed beyond the sections above - this is the
    # acceptance test that the whole mechanism is order-stable end to
    # end; any sabotage above that reorders or drops a root would also
    # turn this red
    test "compiling the same document twice gives byte-identical SCXML" do
      document = document([%DatamodelEntry{id: "parked"}])
      opts = [declare: [{"targets", nil}]]

      assert compile!(document, opts) == compile!(document, opts)
    end

    # sabotage: in `CanonicalJson.encode/1`, drop
    # `maybe_put_list(pairs, "datamodel", document.datamodel)` (covered
    # directly by `CanonicalJsonTest`; exercised here end to end through
    # the compiler) -> moving the `datamodel` key would stop moving
    # `document_hash`, and this goes red
    test "moving the datamodel key moves the CompilationRecord's document_hash" do
      {:ok, without} = compile(document())
      {:ok, with_datamodel} = compile(document([%DatamodelEntry{id: "targets"}]))

      refute without.record.document_hash == with_datamodel.record.document_hash
    end
  end

  describe "the shipped fixtures declare their own roots (sb-vjeg)" do
    # Sabotage: emptied `datamodel:` in `DocumentFixtures.worked_example/0`
    # -> the guard's two roots never reach the chart, no `<datamodel>` is
    # emitted at all, and this goes red (verified)
    test "the worked example's guard roots reach the chart with no host at all" do
      assert fixture_scxml(DocumentFixtures.worked_example()) =~
               ~s(<datamodel><data id="budget_remaining"/><data id="amount"/></datamodel>)
    end

    # Sabotage: emptied `datamodel:` in `DocumentFixtures.signup_wizard/0`
    # -> the branch's root never reaches the chart and this goes red
    # (verified)
    test "the signup wizard's guard root reaches the chart with no host at all" do
      assert fixture_scxml(DocumentFixtures.signup_wizard()) =~
               ~s(<datamodel><data id="variant"/></datamodel>)
    end

    # The ratchet, derived rather than restated: whatever a shipped
    # fixture's guards come to read, the document has to declare. Reads
    # the identifiers straight off the stored conds, so adding an arm that
    # reads an undeclared root turns this red without anyone remembering
    # to update a list. A cond that ever uses a bare keyword (`true`,
    # `and`) would land here too - that is a look worth taking, not a
    # false alarm to suppress.
    #
    # Sabotage: dropped the `amount` entry from
    # `DocumentFixtures.worked_example/0`, leaving the cond that reads it
    # -> red naming `amount` (verified)
    test "every root either fixture's guards read is declared by the document" do
      for document <- [DocumentFixtures.worked_example(), DocumentFixtures.signup_wizard()] do
        declared = MapSet.new(document.datamodel, & &1.id)

        for root <- guard_roots(document) do
          assert MapSet.member?(declared, root),
                 "#{document.id} reads #{root} in a guard and does not declare it"
        end
      end
    end

    # The other direction: a declaration nothing reads is dead weight in
    # the emitted chart, and these two documents are the family's worked
    # examples - what they show is what a host copies.
    #
    # Sabotage: added `%DatamodelEntry{id: "unused"}` to
    # `DocumentFixtures.signup_wizard/0` -> red naming `unused` (verified)
    test "neither fixture declares a root its own guards never read" do
      for document <- [DocumentFixtures.worked_example(), DocumentFixtures.signup_wizard()] do
        read = MapSet.new(guard_roots(document))

        for %DatamodelEntry{id: id} <- document.datamodel do
          assert MapSet.member?(read, id),
                 "#{document.id} declares #{id} and no guard of its own reads it"
        end
      end
    end
  end

  # -- the plumbing ----------------------------------------------------------

  # The shipped fixtures reach `myapp.*` types, so they need the fixture
  # palette rather than the bare core one, and no `:declare` option at all
  # - that absence is the point.
  defp fixture_scxml(document) do
    {:ok, compiled} = Compiler.compile(document, CoreFixtures.palette())
    compiled.scxml
  end

  # Every bare identifier a `core.branch` arm's `cond` reads, with
  # single-quoted string literals taken out first so `'b'` is not mistaken
  # for a root named `b`.
  defp guard_roots(document) do
    document
    |> Document.blocks()
    |> Enum.flat_map(fn block -> Map.get(block.config, "arms", []) end)
    |> Enum.map(fn arm -> Map.get(arm, "cond", "") end)
    |> Enum.flat_map(fn cond ->
      cond
      |> String.replace(~r/'[^']*'/, " ")
      |> then(&Regex.scan(~r/[a-z][a-z0-9_]*/, &1))
      |> Enum.map(&hd/1)
    end)
    |> Enum.uniq()
  end

  FROM

  defp document(datamodel \\ []) do
    Document.new(
      Block.new("core.sequence",
        id: "blk_ROOT",
        slots: %{
          "body" => [
            Block.new("core.assign",
              id: "blk_SET",
              config: %{"path" => "targets", "value" => "'a'"}
            )
          ]
        }
      ),
      id: "bdoc_HOST",
      datamodel: datamodel
    )
  end

  # A loop over a list a document or host may declare - the same shape
  # `HostRootsTest` uses for its own block-declared-root collision cases.
  defp loop_document(datamodel) do
    Document.new(
      Block.new("core.foreach",
        id: "blk_F",
        config: %{"items" => "steps", "item_as" => "step"},
        slots: %{
          "body" => [
            Block.new("core.raise", id: "blk_R", config: %{"event" => "seen"})
          ]
        }
      ),
      id: "bdoc_LOOP",
      datamodel: datamodel
    )
  end

  defp compile(document, opts \\ []) do
    Compiler.compile(document, Palette.new(Palette.core_types()), opts)
  end

  defp compile!(document, opts \\ []) do
    {:ok, compiled} = compile(document, opts)
    compiled.scxml
  end
end
