defmodule StatifierBlocks.CompilerTest do
  use ExUnit.Case, async: true

  alias Statifier.Machine.Identity
  alias StatifierBlocks.{Block, Compiled, Compiler, Document, Emission, Palette}
  alias StatifierBlocks.Compiler.{Context, Finding}
  alias StatifierBlocks.CoreFixtures

  @worked_example "test/fixtures/documents/worked_example.json"

  defmodule Exploding do
    @moduledoc false
    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []
    @impl true
    def config_schema(_config), do: []
    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(_block, _context), do: {:error, [{"boom", "this type refuses to compile"}]}
  end

  defmodule BadRole do
    @moduledoc false
    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []
    @impl true
    def config_schema(_config), do: []
    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(_block, context), do: Context.role_id(context, "Not A Role")
  end

  defmodule Orphaner do
    @moduledoc false
    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []
    @impl true
    def config_schema(_config), do: []
    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(_block, context) do
      {:ok,
       Emission.element("state", [{"id", context.state_id}], [
         Emission.child_ref("blk_NOT_MY_CHILD")
       ])}
    end
  end

  defmodule Picky do
    @moduledoc false
    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []
    @impl true
    def config_schema(_config), do: []
    @impl true
    def validate_config(_config), do: {:error, [{"nope", "never valid"}]}
    @impl true
    def emit(_block, _context), do: {:error, [{"nope", "unreachable"}]}
  end

  describe "the worked example (ADR-0001 decision 11)" do
    # sabotage: change Core.Sequence.emit/2 to emit its children's states
    # without the chaining transitions -> statifier reports unreachable
    # states and this assertion goes red (verified)
    test "compiles to SCXML the engine's own validator accepts" do
      compiled = compile_worked_example()

      assert {:ok, machine} =
               Statifier.compile(compiled.scxml, chart_name: compiled.record.document_id)

      assert Statifier.Machine.identity(machine).content_hash =~ ~r/\Asha256:[0-9a-f]{64}\z/
    end

    # sabotage: drop the `initial` attribute from the <scxml> element ->
    # the root block's state is no longer named and this goes red (verified)
    test "names the document on <scxml> and points initial at the root block's state" do
      compiled = compile_worked_example()

      assert compiled.scxml =~ ~s(initial="s_blk_ROOT")
      assert compiled.scxml =~ ~s(name="bdoc_01JDOC")
    end

    # sabotage: make Core.Emit.ordered/2 omit the <final> child -> a block's
    # state stops raising done.state and every id below stays absent from
    # the emission, taking this assertion red (verified)
    test "every block in the document owns a state in the emission" do
      compiled = compile_worked_example()

      for block <- Document.blocks(document()) do
        assert compiled.scxml =~ ~s(id="s_#{block.id}")
      end
    end
  end

  describe "determinism (decision 6)" do
    # sabotage: replace the palette_hash digest's Enum.sort with the bare
    # list -> two palettes built in different orders disagree, which this
    # test's second half catches (verified)
    test "the same triple compiles to byte-identical SCXML and an equal record" do
      first = compile_worked_example()
      second = compile_worked_example()

      assert first.scxml == second.scxml
      assert first.record == second.record
    end

    # A block's `slots` field is a map, and a map is the one thing decision
    # 6 forbids iterating: `slots/1` declaration order is the authority
    # (ADR-0002 decision 6 made that order meaningful), not the slot names'
    # sort order. `core.parallel` is where the two differ observably.
    #
    # sabotage: sort Core.Parallel.lanes/1 -> the slots the type declares
    # stop following config order, the two lanes swap in the emission, and
    # this goes red (verified)
    test "slots are emitted in slots/1 declaration order, not sorted-name order" do
      root =
        Block.new("core.parallel",
          id: "blk_PAR",
          config: %{"lanes" => ["receipt", "capture"]},
          slots: %{"lane_receipt" => [leaf("blk_N")], "lane_capture" => [leaf("blk_C")]}
        )

      scxml = compile!(Document.new(root), toy_palette()).scxml

      assert index(scxml, "s_blk_PAR__lane_receipt") < index(scxml, "s_blk_PAR__lane_capture")
    end

    # sabotage: compile the `metadata` map into the emission -> the two
    # documents below stop agreeing and this goes red (verified)
    test "a metadata-only edit produces identical SCXML and identical chart identity" do
      base = document()
      edited = %{base | metadata: %{"name" => "Something else entirely"}}

      first = compile!(base)
      second = compile!(edited)

      assert first.scxml == second.scxml
      assert Identity.matches?(first.record.chart_identity, second.record.chart_identity)
      refute first.record.document_hash == second.record.document_hash
    end
  end

  describe "the compilation record (decision 7)" do
    # sabotage: put the document revision in chart_version -> this
    # assertion goes red, and so does the resume property below (verified)
    test "chart_name carries the document id and chart_version stays nil" do
      record = compile_worked_example().record

      assert record.chart_identity.name == record.document_id
      assert record.chart_identity.version == nil
    end

    # The resume-compatibility reasoning of decision 7, checked against
    # statifier 2.x's own comparison rather than against a restatement of it.
    #
    # sabotage: as above -> a saved revision no longer matches its own
    # recompile and this goes red (verified)
    test "a revision bump alone still matches the identity a running session holds" do
      saved = compile_worked_example().record.chart_identity
      resaved = compile!(%{document() | revision: 18}).record.chart_identity

      assert Identity.matches?(saved, resaved)
    end

    # sabotage: make chart_identity a construction of %Identity{} rather
    # than Identity.of_source/2 over the serialized bytes -> the engine's
    # own hash of the same bytes stops agreeing and this goes red (verified)
    test "chart identity is the engine's hash of the bytes the compiler wrote" do
      compiled = compile_worked_example()
      {:ok, machine} = Statifier.compile(compiled.scxml, chart_name: compiled.record.document_id)

      assert Identity.matches?(
               Statifier.Machine.identity(machine),
               compiled.record.chart_identity
             )
    end

    # sabotage: drop `module` from the palette_hash triples -> swapping one
    # entry for another module under the same name stops moving the hash,
    # which is exactly the surprising recompile the field exists to make
    # visible, and this goes red (verified)
    test "palette_hash moves when a resolved entry's module changes" do
      document = Document.new(leaf("blk_ONLY"), id: "bdoc_PH", revision: 0)

      one = compile!(document, Palette.new(%{"toy.leaf" => CoreFixtures.Notify}))
      two = compile!(document, Palette.new(%{"toy.leaf" => CoreFixtures.Capture}))

      refute one.record.palette_hash == two.record.palette_hash
    end

    # sabotage: change document_hash to hash something other than
    # Document.to_json/1 -> this goes red (verified)
    test "document_hash is the document's own content hash" do
      assert compile_worked_example().record.document_hash == Document.content_hash(document())
    end

    # sabotage: change @compiler_version -> this goes red until mix.exs
    # moves with it, which is the drift the assertion exists to catch
    # (verified)
    test "compiler_version is this package's version" do
      assert Compiler.compiler_version() == Mix.Project.config()[:version]
      assert compile_worked_example().record.compiler_version == Compiler.compiler_version()
    end
  end

  describe "totality and stage ordering (decisions 1 and 10)" do
    # sabotage: remove the document_stage/1 guard -> Document.to_json/1
    # raises out of compile/3 and this goes red (verified)
    test "a structurally invalid document is a finding, never a raise" do
      document = %Document{Document.new(leaf("blk_A")) | schema_version: 99}

      assert {:error, [%Finding{stage: :document}]} =
               Compiler.compile(document, CoreFixtures.palette())
    end

    # sabotage: make resolve/2 return {:ok, ...} for an unknown type ->
    # this goes red (verified)
    test "an unresolvable block type stops the compile at Resolve" do
      document = Document.new(Block.new("nobody.knows", id: "blk_X"), id: "bdoc_R")

      assert {:error, [finding]} = Compiler.compile(document, CoreFixtures.palette())
      assert %Finding{stage: :resolve, block_id: "blk_X"} = finding
      assert finding.reason == {:unknown_block_type, "nobody.knows"}
    end

    # sabotage: make orphan_findings/2 return [] -> only the parent's own
    # failure is reported and this goes red (verified)
    test "Resolve reports every failure in the stage, including under an unresolvable parent" do
      child = Block.new("also.unknown", id: "blk_CHILD")
      root = Block.new("nobody.knows", id: "blk_X", slots: %{"body" => [child]})

      assert {:error, findings} = Compiler.compile(Document.new(root), CoreFixtures.palette())
      assert Enum.map(findings, & &1.block_id) == ["blk_X", "blk_CHILD"]
    end

    # sabotage: run config_stage/1 before resolve_stage/2 -> the compile
    # reports a config finding for a type it never resolved and this goes
    # red (verified)
    test "Config runs only once Resolve has succeeded" do
      document = Document.new(Block.new("toy.picky", id: "blk_P"), id: "bdoc_C")
      palette = Palette.new(%{"toy.picky" => Picky})

      assert {:error, [%Finding{stage: :config, config_key: "nope", block_id: "blk_P"}]} =
               Compiler.compile(document, palette)
    end

    # sabotage: make emit_findings/2 drop the block id -> this goes red
    # (verified)
    test "an emit/2 refusal names the block it came from" do
      document = Document.new(Block.new("toy.boom", id: "blk_B"), id: "bdoc_E")
      palette = Palette.new(%{"toy.boom" => Exploding})

      assert {:error, [%Finding{stage: :emit, block_id: "blk_B", config_key: "boom"}]} =
               Compiler.compile(document, palette)
    end

    # sabotage: drop the {:invalid_role, ...} clause from emit_findings/2 ->
    # the reason falls through to the generic arm and this goes red (verified)
    test "a role the compiler cannot invert is an Emit-stage :invalid_role finding" do
      document = Document.new(Block.new("toy.role", id: "blk_R"), id: "bdoc_I")
      palette = Palette.new(%{"toy.role" => BadRole})

      assert {:error, [%Finding{stage: :emit, reason: reason}]} =
               Compiler.compile(document, palette)

      assert reason == {:invalid_role, "blk_R", "Not A Role"}
    end

    # sabotage: make substitute/2 leave an unknown placeholder in place ->
    # the serializer raises instead and this goes red (verified)
    test "a placeholder naming a block that is not a child is reported, never serialized" do
      document = Document.new(Block.new("toy.orphan", id: "blk_O"), id: "bdoc_O")
      palette = Palette.new(%{"toy.orphan" => Orphaner})

      assert {:error, [%Finding{stage: :emit, block_id: "blk_O", reason: reason}]} =
               Compiler.compile(document, palette)

      assert reason == {:unspliced_child, "blk_NOT_MY_CHILD"}
    end

    # sabotage: make compile/3 return the artifact on any arm -> this goes
    # red (verified)
    test "compile/3 never partially succeeds" do
      document = Document.new(Block.new("nobody.knows", id: "blk_X"), id: "bdoc_P")

      refute match?({:ok, %Compiled{}}, Compiler.compile(document, CoreFixtures.palette()))
    end
  end

  defp compile_worked_example, do: compile!(document())

  defp compile!(document, palette \\ CoreFixtures.palette()) do
    {:ok, compiled} = Compiler.compile(document, palette)
    compiled
  end

  defp document do
    {:ok, document} = Document.from_json(File.read!(@worked_example))
    document
  end

  defp leaf(id), do: Block.new("toy.leaf", id: id)

  defp toy_palette,
    do: Palette.new(Map.merge(Palette.core_types(), %{"toy.leaf" => CoreFixtures.Notify}))

  defp index(haystack, needle) do
    [{start, _length}] = Regex.run(~r/#{Regex.escape(needle)}/, haystack, return: :index)
    start
  end
end
