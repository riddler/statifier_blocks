defmodule StatifierBlocks.DecodeTest do
  # async: false - the batch atom-count test below reads
  # `:erlang.system_info(:atom_count)`, a VM-global counter that every other
  # process in the VM can move. Running this module serially removes the
  # `async: true` modules from that set; it does not remove the ExUnit runner,
  # Logger, IO or lazy module loading, which is why that test measures a batch
  # against a tolerance rather than a single decode against exact zero, and
  # why the deterministic import-table test beside it is the primary check.
  use ExUnit.Case, async: false

  alias StatifierBlocks.{Block, Document, DocumentFixtures, DocumentGenerator}

  # Fixed, never seeded from the clock: a red run of the corpus tests below
  # prints the failing document's index, and `DocumentGenerator.generate/2`
  # regenerates that exact document from `{@seed, index}` alone.
  @seed 424_242
  @corpus_size 200

  # Every module that touches a value decoded from untrusted bytes. ADR-0001
  # decision 6 says none of them may intern an atom from that input.
  @decode_path_modules [
    StatifierBlocks.Decode,
    StatifierBlocks.Validation,
    StatifierBlocks.Document
  ]

  # The atom table only grows through these. The `String.*`/`List.*` forms are
  # listed for readability - the Elixir compiler rewrites them to their
  # `:erlang.*` equivalents, which is what actually lands in an import table -
  # and `binary_to_term/1,2` is here because a term it decodes may carry atoms.
  @atom_interning_mfas MapSet.new([
                         {:erlang, :binary_to_atom, 1},
                         {:erlang, :binary_to_atom, 2},
                         {:erlang, :binary_to_existing_atom, 1},
                         {:erlang, :binary_to_existing_atom, 2},
                         {:erlang, :list_to_atom, 1},
                         {:erlang, :list_to_existing_atom, 1},
                         {:erlang, :binary_to_term, 1},
                         {:erlang, :binary_to_term, 2},
                         {Module, :concat, 1},
                         {Module, :concat, 2},
                         {String, :to_atom, 1},
                         {String, :to_existing_atom, 1},
                         {List, :to_atom, 1},
                         {List, :to_existing_atom, 1}
                       ])

  # Each document below carries this many strings that have never been seen
  # before, so a decoder that interns every one of them mints that many atoms
  # per decode - and the narrowest sabotage that interns only `type` still
  # mints 2. The batch is sized so that even the narrowest one clears the
  # tolerance by an order of magnitude, and the tolerance sits about as far
  # above the worst ambient drift observed on this counter (+9 over a whole
  # suite run) in the other direction.
  @novel_strings_per_document 7
  @atom_batch_size 500
  @atom_noise_tolerance 50

  defp corpus, do: for(i <- 1..@corpus_size, do: {i, DocumentGenerator.generate(@seed, i)})

  describe "worked example (headline round trip)" do
    # sabotage: in `Decode.build_block/1`, hardcode `type_version: 1` instead
    # of reading `Map.get(map, "type_version")` -> `blk_AUTH`'s `type_version:
    # 2` decodes as `1` -> the equality assertion below goes red
    test "from_json/1 of the fixture bytes equals the hand-built document, and re-encodes to the same bytes" do
      json = DocumentFixtures.worked_example_json()

      assert {:ok, document} = Document.from_json(json)
      assert document == DocumentFixtures.worked_example()
      assert Document.to_json(document) == json
    end
  end

  describe "round-trip property (#{@corpus_size}-document corpus)" do
    # sabotage: in `Decode.decode_slots/1`, change `Map.put(acc, name,
    # decoded)` to always use the literal key `"slot"` -> every document
    # with more than one slot on some block collapses those slots into one
    # on decode -> `decoded == doc` goes red for most of the corpus
    test "decode(encode(d)) == d for every generated document" do
      for {index, document} <- corpus() do
        encoded = Document.to_json(document)

        assert {:ok, decoded} = Document.from_json(encoded),
               "seed=#{@seed} index=#{index} failed to decode its own encoding"

        assert decoded == document, "seed=#{@seed} index=#{index}"
      end
    end

    # sabotage: in `Decode.build_block/1`, swap `Map.get(map, "config", %{})`
    # for `Map.get(map, "slots", %{})` (reading the wrong key for `config`)
    # -> a document with non-empty config re-encodes with the wrong bytes ->
    # this assertion goes red for most of the corpus
    test "encode(decode(encode(d))) == encode(d) for every generated document" do
      for {index, document} <- corpus() do
        encoded = Document.to_json(document)
        assert {:ok, decoded} = Document.from_json(encoded)

        assert Document.to_json(decoded) == encoded,
               "seed=#{@seed} index=#{index}"
      end
    end
  end

  describe "identity stability" do
    # sabotage: in `Document.content_hash/1`, hash `inspect(document)`
    # instead of `to_json(document)` -> two structurally-equal documents
    # built independently (the original and the decoded copy) would still
    # coincidentally match by `inspect/1` equality, so instead sabotage by
    # appending the document's `revision` to the digest input before
    # hashing -> a decode that preserves `revision` exactly still passes,
    # so sabotage `to_json/1`'s envelope order instead: swap `"revision"`
    # for a hardcoded `0` in `CanonicalJson.encode/1` -> any generated
    # document with a nonzero revision now hashes differently after a
    # decode/re-encode round trip -> red
    test "content_hash(d) == content_hash(elem(from_json(to_json(d)), 1)) for every generated document" do
      for {index, document} <- corpus() do
        encoded = Document.to_json(document)
        assert {:ok, decoded} = Document.from_json(encoded)

        assert Document.content_hash(document) == Document.content_hash(decoded),
               "seed=#{@seed} index=#{index}"
      end
    end
  end

  describe "not_a_block_document" do
    # sabotage: change `Decode.decode_bytes/1`'s error clause to return
    # `{:ok, %{"schema_version" => 1}}` instead of `{:error,
    # :not_a_block_document}` -> a JSON parse failure now passes
    # `ensure_block_document/1`'s key check and falls through to a
    # `:malformed_envelope` refusal instead -> red (verified: this specific
    # mutation, confirmed and reverted)
    test "garbage bytes" do
      assert Document.from_json("not json at all {{{") == {:error, :not_a_block_document}
    end

    # sabotage: add an `ensure_block_document/1` clause matching
    # `is_list(term)` that returns `{:ok, %{}}` -> a JSON array now passes
    # through as an empty envelope and fails as `:malformed_envelope`
    # instead of `:not_a_block_document` -> red (verified)
    test "a JSON array" do
      assert Document.from_json("[1,2,3]") == {:error, :not_a_block_document}
    end

    # sabotage: change `ensure_block_document/1`'s `Map.has_key?(term,
    # "schema_version")` check to `true` unconditionally -> a JSON object
    # missing that key passes this gate and fails downstream as
    # `:malformed_envelope` instead of `:not_a_block_document` -> red
    # (verified)
    test "a JSON object with no schema_version key" do
      assert Document.from_json(~s({"id":"bdoc_x","revision":0,"root":{}})) ==
               {:error, :not_a_block_document}
    end
  end

  describe "unsupported_schema_version" do
    # sabotage: in `Validation.check_schema_version/1`, change the `version
    # > 0` guard to `version >= 0` -> unaffected here since 2 already
    # satisfies both, so instead sabotage by changing `check_schema_version(1)`
    # to `check_schema_version(_any)` -> version 2 would be accepted as
    # supported and this assertion goes red
    test "schema_version 2 is a recognized document with an unsupported version" do
      json = worked_example_with_schema_version(2)
      assert Document.from_json(json) == {:error, {:unsupported_schema_version, 2}}
    end
  end

  describe "duplicate_block_id" do
    # sabotage: in `Validation.validate_unique_ids/1`, change
    # `MapSet.member?(seen, id)` to always return `false` -> the second
    # sighting of a repeated id is never flagged -> red
    test "the same id on two blocks in different subtrees" do
      leaf = fn -> Block.new("core.wait", id: "blk_dup") end

      root =
        Block.new("core.branch",
          id: "blk_root",
          slots: %{"arm_a" => [leaf.()], "arm_b" => [leaf.()]}
        )

      json = Document.new(root, id: "bdoc_dup") |> to_json_ignoring_validate()

      assert Document.from_json(json) == {:error, {:duplicate_block_id, "blk_dup"}}
    end
  end

  describe "malformed_block" do
    # sabotage: in `Decode.build_block/1`, default a missing `"type"` to
    # `"core.wait"` instead of leaving it `nil` via `Map.get(map, "type")`
    # -> a block object with no `"type"` key decodes successfully instead
    # of being refused -> red
    test "a block object missing type" do
      json =
        ~s({"id":"bdoc_x","revision":0,"schema_version":1,
                 "root":{"id":"blk_root"}})
        |> String.replace(~r/\s+/, "")

      assert {:error, {:malformed_block, "blk_root", {:type, :not_a_non_empty_string}}} =
               Document.from_json(json)
    end

    # sabotage: in `Decode.decode_block/1`, drop the `Enum.find/2` unexpected
    # -key scan so a block object is built straight from its known keys with
    # no check for extras -> a block with an unrecognized key would decode
    # silently instead of refusing -> red
    test "a block object carrying an unrecognized key" do
      json =
        ~s({"id":"bdoc_x","revision":0,"schema_version":1,) <>
          ~s("root":{"id":"blk_root","type":"core.wait","type_version":1,"bogus":true}})

      assert Document.from_json(json) ==
               {:error, {:malformed_block, "blk_root", {:unexpected_key, "bogus"}}}
    end
  end

  describe "malformed_envelope" do
    # sabotage: in `Decode.decode/1`, default a missing `"id"` to
    # `"bdoc_generated"` instead of leaving it `nil` via `Map.get(envelope,
    # "id")` -> a document object with no `"id"` key decodes successfully
    # instead of being refused -> red
    test "an envelope missing id" do
      json =
        ~s({"revision":0,"schema_version":1,) <>
          ~s("root":{"id":"blk_root","type":"core.wait","type_version":1}})

      assert Document.from_json(json) ==
               {:error, {:malformed_envelope, {:id, :not_a_non_empty_string}}}
    end
  end

  describe "datamodel (ADR-0001 decision 11)" do
    alias StatifierBlocks.Document.DatamodelEntry

    # sabotage: in `decode_datamodel_entry/2`, change
    # `expr: Map.get(map, "expr")` to `expr: nil` -> a document with an
    # `expr` no longer round-trips -> red (verified: also takes the
    # bytes-side round-trip test below with it)
    test "decode(encode(d)) == d for a document with a datamodel" do
      document =
        Document.new(Block.new("core.wait", id: "blk_leaf"),
          id: "bdoc_dm",
          datamodel: [
            %DatamodelEntry{id: "targets", expr: "[]", description: "the list"},
            %DatamodelEntry{id: "parked"}
          ]
        )

      assert Document.from_json(Document.to_json(document)) == {:ok, document}
    end

    # sabotage: same target as above, checked from the bytes side instead
    # of the struct side -> a lossy round trip would still show up here
    # even if the struct-equality check above were somehow satisfied by
    # coincidence -> red (verified)
    test "encode(decode(encode(d))) == encode(d) for a document with a datamodel" do
      document =
        Document.new(Block.new("core.wait", id: "blk_leaf"),
          id: "bdoc_dm",
          datamodel: [%DatamodelEntry{id: "targets", expr: "[]", description: "the list"}]
        )

      encoded = Document.to_json(document)
      assert {:ok, decoded} = Document.from_json(encoded)
      assert Document.to_json(decoded) == encoded
    end

    # sabotage: drop `"datamodel"` from `@envelope_keys` -> an envelope
    # carrying it would be refused as `:unexpected_key` instead of
    # decoding, which is the opposite of this test's point, so instead
    # sabotage by dropping `ensure_known_envelope_keys/1` from the `with`
    # chain in `decode/1` entirely -> an envelope key outside the known
    # set would decode silently instead of being refused -> red
    test "an envelope key outside the known set is refused" do
      json =
        ~s({"id":"bdoc_x","revision":0,"schema_version":1,"bogus":true,) <>
          ~s("root":{"id":"blk_root","type":"core.wait","type_version":1}})

      assert Document.from_json(json) ==
               {:error, {:malformed_envelope, {:unexpected_key, "bogus"}}}
    end

    # sabotage: drop the `Enum.find(Map.keys(map), &(&1 not in
    # @entry_keys))` scan from `decode_datamodel_entry/2` -> an entry
    # object carrying an unrecognized key would decode silently instead
    # of being refused -> red
    test "a datamodel entry carrying an unrecognized key is refused" do
      json =
        ~s({"id":"bdoc_x","revision":0,"schema_version":1,) <>
          ~s("datamodel":[{"id":"targets","bogus":true}],) <>
          ~s("root":{"id":"blk_root","type":"core.wait","type_version":1}})

      assert Document.from_json(json) ==
               {:error,
                {:malformed_envelope, {:datamodel, {:entry, 0, {:unexpected_key, "bogus"}}}}}
    end

    # sabotage: change `Map.get(envelope, "datamodel", [])` in
    # `decode/1` to default to `nil` instead of `[]` -> an envelope with
    # no `datamodel` key would build a document whose `datamodel` field
    # is `nil`, which `Validation.check_datamodel/1`'s `is_list` guard
    # refuses, and this test's `{:ok, _}` assertion goes red -> red
    test "an absent datamodel key decodes to []" do
      json =
        ~s({"id":"bdoc_x","revision":0,"schema_version":1,) <>
          ~s("root":{"id":"blk_root","type":"core.wait","type_version":1}})

      assert {:ok, %Document{datamodel: []}} = Document.from_json(json)
    end

    # An explicit JSON `null` for `expr` is refused, distinctly from the
    # key being absent (which is `nil` too, but valid).
    # sabotage: in `reject_explicit_null/4`, change
    # `is_nil(Map.fetch!(map, key))` to `false` -> an explicit `null`
    # would pass through and build a struct indistinguishable from the
    # key being absent -> red
    test "an explicit null expr is refused, distinctly from an absent one" do
      json =
        ~s({"id":"bdoc_x","revision":0,"schema_version":1,) <>
          ~s("datamodel":[{"id":"targets","expr":null}],) <>
          ~s("root":{"id":"blk_root","type":"core.wait","type_version":1}})

      assert Document.from_json(json) ==
               {:error, {:malformed_envelope, {:datamodel, {:entry, 0, {:expr, :explicit_null}}}}}
    end

    # sabotage: same target, over `description` - change
    # `reject_explicit_null(map, "description", :description, index)`'s
    # call site to skip the check entirely (only call it for `"expr"`)
    # -> red
    test "an explicit null description is refused, distinctly from an absent one" do
      json =
        ~s({"id":"bdoc_x","revision":0,"schema_version":1,) <>
          ~s("datamodel":[{"id":"targets","description":null}],) <>
          ~s("root":{"id":"blk_root","type":"core.wait","type_version":1}})

      assert Document.from_json(json) ==
               {:error,
                {:malformed_envelope, {:datamodel, {:entry, 0, {:description, :explicit_null}}}}}
    end
  end

  describe "registry-free decode" do
    # sabotage: add a clause to `Decode.build_block/1` (or `Document.from_json/1`)
    # that pattern-matches on a known set of type names and returns
    # `{:error, {:unknown_type, type}}` for anything else -> this test,
    # which relies on an unrecognized type loading, goes red
    test "a document whose root type is unknown decodes to {:ok, _}" do
      json =
        ~s({"id":"bdoc_x","revision":0,"schema_version":1,) <>
          ~s("root":{"id":"blk_root","type":"nobody.knows.this","type_version":1}})

      assert {:ok, %Document{root: %Block{type: "nobody.knows.this"}}} = Document.from_json(json)
    end
  end

  describe "no floats" do
    # sabotage: in `Validation.canonical_json_check/2`, drop the `is_float(value)`
    # clause -> a float in `config` falls into the generic `is_integer`/catch-all
    # path instead of the named `{:float, path}` refusal -> red
    test "a float in config is refused and the reason names the float" do
      json =
        ~s({"id":"bdoc_x","revision":0,"schema_version":1,) <>
          ~s("root":{"id":"blk_root","type":"core.wait","type_version":1,) <>
          ~s("config":{"ratio":1.5}}})

      assert Document.from_json(json) ==
               {:error, {:malformed_block, "blk_root", {:config, {:float, ["ratio"]}}}}
    end

    # sabotage: same clause, but this exercises `check_metadata/1`'s call
    # into the same predicate rather than `check_config/2`'s -> dropping the
    # `is_float/1` clause turns this red too, confirming metadata is checked
    # by the same value grammar as config (Open Question 7's stricter reading)
    test "a float in metadata is refused and the reason names the float" do
      json =
        ~s({"id":"bdoc_x","revision":0,"schema_version":1,"metadata":{"weight":2.5},) <>
          ~s("root":{"id":"blk_root","type":"core.wait","type_version":1}})

      assert Document.from_json(json) ==
               {:error, {:malformed_envelope, {:metadata, {:float, ["weight"]}}}}
    end
  end

  describe "decoding does not create atoms" do
    # The end-to-end half of the property: whatever the decoder is compiled
    # from, running it over novel bytes must not grow the atom table. It is a
    # batch against a tolerance rather than one decode against exact zero
    # because `:atom_count` is VM-global and `async: false` does not stop the
    # runner, Logger or IO from interning during the window (sb-b5l: 2 red
    # runs in ~72, delta +9). See `@atom_batch_size` for how batch and
    # tolerance are sized against noise on one side and signal on the other.
    #
    # sabotage: in `Decode.build_block/1`, replace `Map.get(map, "type")`
    # with `String.to_atom(Map.get(map, "type"))` -> every novel type string
    # mints a brand-new atom on decode -> the delta assertion goes red
    test "decoding a batch of documents of novel random strings interns no atoms" do
      json = novel_document_json()

      # Warm the whole decode path once before measuring. Lazy module loading
      # interns atoms of its own, and doing it inside the measured window is
      # what made the original single-document form of this test flake.
      assert {:ok, _warmup} = Document.from_json(json)

      before_count = :erlang.system_info(:atom_count)

      for _ <- 1..@atom_batch_size do
        assert {:ok, _document} = Document.from_json(novel_document_json())
      end

      delta = :erlang.system_info(:atom_count) - before_count

      assert delta <= @atom_noise_tolerance,
             "decoding #{@atom_batch_size} documents of novel strings grew the " <>
               "atom table by #{delta} (tolerance #{@atom_noise_tolerance}); a " <>
               "decoder that interns mints #{@novel_strings_per_document} atoms " <>
               "per document, an honest one mints none"
    end

    # sabotage: in `Decode.build_block/1`, replace `Map.get(map, "type")` with
    # `String.to_atom(Map.get(map, "type"))` -> `:erlang.binary_to_atom/1`
    # (what `String.to_atom/1` compiles to) appears in `Decode`'s import
    # table -> the assertion below goes red
    test "no module on the decode path calls an atom-interning function" do
      for module <- @decode_path_modules do
        {:ok, {^module, [imports: imports]}} =
          :beam_lib.chunks(beam_path(module), [:imports])

        assert Enum.filter(imports, &MapSet.member?(@atom_interning_mfas, &1)) == [],
               "#{inspect(module)} calls an atom-interning function, so decoding " <>
                 "untrusted input can grow the VM's atom table (ADR-0001 decision 6)"
      end
    end
  end

  # --- Helpers --------------------------------------------------------------

  # Where a module's compiled `.beam` actually is on disk. Under the coverage
  # stage of the full gate the modules are cover-compiled, and `:code.which/1`
  # then answers the atom `:cover_compiled` instead of a path - so fall back to
  # the application's `ebin`, which still holds the real beam. Reading that one
  # is also what this test wants: cover-compiled bytecode carries the coverage
  # instrumentation's own calls, not just the module's.
  @spec beam_path(module()) :: charlist()
  defp beam_path(module) do
    case :code.which(module) do
      path when is_list(path) ->
        path

      _cover_compiled_or_missing ->
        ebin = :code.lib_dir(:statifier_blocks, :ebin)
        refute match?({:error, _reason}, ebin), "statifier_blocks has no ebin directory"

        ebin
        |> List.to_string()
        |> Path.join("#{module}.beam")
        |> String.to_charlist()
    end
  end

  # Canonical bytes for a valid document whose every free-form string - the
  # metadata key and value, both types, the config key and value, the slot
  # name - has never existed in this VM before. Keep the count in step with
  # `@novel_strings_per_document`.
  @spec novel_document_json() :: binary()
  defp novel_document_json do
    novel = fn -> "novel_" <> Base.encode16(:crypto.strong_rand_bytes(12), case: :lower) end

    ~s({"id":"bdoc_x","revision":0,"schema_version":1,) <>
      ~s("metadata":{"#{novel.()}":"#{novel.()}"},) <>
      ~s("root":{"id":"blk_root","type":"#{novel.()}","type_version":1,) <>
      ~s("config":{"#{novel.()}":"#{novel.()}"},) <>
      ~s("slots":{"#{novel.()}":[{"id":"blk_child","type":"#{novel.()}",) <>
      ~s("type_version":1}]}}})
  end

  # Builds canonical bytes for a document whose `root` id is duplicated
  # across two subtrees, bypassing `Document.to_json/1`'s own `validate/1`
  # call (which would refuse to encode it) - the point of this fixture is to
  # hand the decoder bytes that describe an invalid document, exactly as a
  # host's stored JSON might if it were written before this rule existed.
  @spec to_json_ignoring_validate(Document.t()) :: binary()
  defp to_json_ignoring_validate(document) do
    document
    |> StatifierBlocks.CanonicalJson.encode()
    |> IO.iodata_to_binary()
  end

  @spec worked_example_with_schema_version(pos_integer()) :: binary()
  defp worked_example_with_schema_version(version) do
    DocumentFixtures.worked_example_json()
    |> String.replace(~s("schema_version":1), ~s("schema_version":#{version}))
  end
end
