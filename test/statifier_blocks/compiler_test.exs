defmodule StatifierBlocks.CompilerTest do
  use ExUnit.Case, async: true

  alias Statifier.Machine.Identity

  alias StatifierBlocks.{
    Block,
    BlockTypeFixtures,
    Compiled,
    Compiler,
    CoreFixtures,
    Document,
    Emission,
    Palette
  }

  alias StatifierBlocks.Compiler.{Context, Finding}

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

    # The stability ratchet sb-dtr asks for. ADR-0004 decision 6 makes the
    # serializer identity-bearing code; serializer_test.exs enforces only
    # *sensitivity* (a reformat moves the identity), so nothing would notice
    # a change that silently moves the worked example's bytes. Updating this
    # hash is a deliberate compiler-version bump (decision 6's third
    # determinism input), never a routine fix - a failing pin is the signal
    # the ADR asks for, not noise to be re-pinned past.
    # sabotage: append one byte to the serialized SCXML before hashing ->
    # the pinned identity moves and this goes red (verified)
    #
    # Moved once, deliberately, by ADR-0004's outcome amendment (2b/2f):
    # the default outcome's final id migrated from `s_<block>__done` to
    # `s_<block>__o_done` and each such final gained
    # `<onentry><raise event="done.outcome.<state id>.done"/></onentry>`.
    # The move was verified rather than accepted: reversing exactly those
    # two edits over the new bytes reproduces
    # `sha256:3c0f170c...` - the hash pinned before - byte for byte, so
    # nothing else in this document's emission changed.
    #
    # Moved again, deliberately, by `core.wait`'s move onto the reserved
    # send role: the wait's delayed send id migrated from
    # `s_<block>__timer` to `s_<block>__send`, and the scope around it
    # gained the `<cancel>` that role earns. Verified the same way -
    # renaming that one id back and deleting that one `<cancel>` over the
    # new bytes reproduces `sha256:0410c745...`, the hash pinned before.
    #
    # Moved a third time, deliberately, by sb-vjeg: the worked example now
    # declares the two roots its own guard reads through ADR-0001 decision
    # 11's document `datamodel` key, so the emission gained
    # `<datamodel><data id="budget_remaining"/><data id="amount"/></datamodel>`
    # ahead of the root state. Verified the same way - deleting that one
    # element from the new bytes and hashing them reproduces
    # `sha256:9e792393...`, the hash pinned before, so nothing else in this
    # document's emission moved.
    test "the worked example's chart identity is pinned" do
      assert compile_worked_example().record.chart_identity.content_hash ==
               "sha256:e89d5b21d3bd630cdffca06aa9af6e211f4977d42d021fbdb8e2d7dee70bf0ff"
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

  describe "outcomes (ADR-0004's outcome amendment, 2e and 2f)" do
    # sabotage: had `summaries/1` build every child summary with
    # `Context.summary/1` rather than the child's own declared names -> the
    # parent sees one `done` outcome per child and the two `error` and
    # `abandoned` transitions disappear (verified red)
    test "a child summary carries its type's declared outcomes, in declaration order" do
      scxml = compile!(outcome_document(), outcome_palette()).scxml

      assert wired_outcome_events(scxml) == [
               "done.outcome.s_blk_PLAIN.done",
               "done.outcome.s_blk_MANY.done",
               "done.outcome.s_blk_MANY.error",
               "done.outcome.s_blk_MANY.abandoned"
             ]
    end

    # A summary that named a final the child never emitted would be a lie
    # the compiler told its own parents, so the ids it hands out are
    # checked against the bytes the child actually wrote.
    #
    # sabotage: had `Context.summary/2` mint each entry's `state_id`
    # against a fixed block id rather than the child's -> the summary names
    # finals that are nowhere in the emission and this goes red (verified)
    test "every outcome entry names a final the child actually emitted" do
      scxml = compile!(outcome_document(), outcome_palette()).scxml

      summaries = [
        Context.summary("blk_PLAIN"),
        Context.summary("blk_MANY", ["done", "error", "abandoned"])
      ]

      for summary <- summaries, outcome <- summary.outcomes do
        assert scxml =~ ~s(<final id="#{outcome.state_id}">)
      end
    end

    # sabotage: dropped the `StateId.role?/1` arm from
    # `validate_outcomes/2` -> the malformed name is minted as a role and
    # the compile succeeds, taking this red (verified)
    test "a malformed outcome name is an :invalid_outcome finding on the block that declared it" do
      child = Block.new("toy.malformed", id: "blk_BAD")
      root = Block.new("toy.parent", id: "blk_P", slots: %{"body" => [child]})

      assert {:error, [%Finding{stage: :emit, block_id: "blk_BAD", reason: reason}]} =
               Compiler.compile(Document.new(root, id: "bdoc_MO"), outcome_palette())

      assert reason == {:invalid_outcome, "blk_BAD", "Gave Up"}
    end

    # sabotage: dropped the `MapSet.member?/2` arm from
    # `validate_outcomes/2` -> the duplicate is accepted, two finals are
    # minted under one id, and this goes red on the finding (verified)
    test "an outcome declared twice is refused, against the block that declared it" do
      child = Block.new("toy.duplicate", id: "blk_DUP")
      root = Block.new("toy.parent", id: "blk_P", slots: %{"body" => [child]})

      assert {:error, [%Finding{stage: :emit, block_id: "blk_DUP", reason: reason}]} =
               Compiler.compile(Document.new(root, id: "bdoc_DO"), outcome_palette())

      assert reason == {:invalid_outcome, "blk_DUP", "error"}
    end
  end

  defp outcome_document do
    plain = Block.new("toy.leaf", id: "blk_PLAIN")
    many = Block.new("toy.outcomes", id: "blk_MANY")

    Document.new(Block.new("toy.parent", id: "blk_P", slots: %{"body" => [plain, many]}),
      id: "bdoc_OC"
    )
  end

  defp outcome_palette do
    Palette.new(%{
      "toy.leaf" => CoreFixtures.Notify,
      "toy.parent" => BlockTypeFixtures.OutcomeParent,
      "toy.outcomes" => BlockTypeFixtures.Outcomes,
      "toy.malformed" => BlockTypeFixtures.MalformedOutcomes,
      "toy.duplicate" => BlockTypeFixtures.DuplicateOutcomes
    })
  end

  # The events the parent wired, in the order it wired them - which is the
  # order the summaries handed it, which is declaration order.
  defp wired_outcome_events(scxml) do
    ~r/<transition event="(done\.outcome\.[^"]+)"/
    |> Regex.scan(scxml)
    |> Enum.map(fn [_whole, event] -> event end)
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
