defmodule StatifierBlocks.DecodeTest do
  # async: false - the atom-count test below reads
  # `:erlang.system_info(:atom_count)`, a VM-global counter. Any other
  # `async: true` module interning an atom mid-assertion would make that
  # test flake unreproducibly, so this whole module runs serially.
  use ExUnit.Case, async: false

  alias StatifierBlocks.{Block, Document, DocumentFixtures, DocumentGenerator}

  # Fixed, never seeded from the clock: a red run of the corpus tests below
  # prints the failing document's index, and `DocumentGenerator.generate/2`
  # regenerates that exact document from `{@seed, index}` alone.
  @seed 424_242
  @corpus_size 200

  defp corpus, do: for(i <- 1..@corpus_size, do: {i, DocumentGenerator.generate(@seed, i)})

  describe "worked example (headline round trip)" do
    # sabotage: in `Decode.build_block/1`, hardcode `type_version: 1` instead
    # of reading `Map.get(map, "type_version")` -> `blk_ENR`'s `type_version:
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
    # sabotage: in `Decode.build_block/1`, replace `Map.get(map, "type")`
    # with `String.to_atom(Map.get(map, "type"))` -> every novel type string
    # below mints a brand-new atom on decode -> the atom-count assertion
    # goes red
    test "decoding a document with novel random strings leaves the atom count unchanged" do
      novel = fn -> "novel_" <> Base.encode16(:crypto.strong_rand_bytes(12), case: :lower) end

      json =
        ~s({"id":"bdoc_x","revision":0,"schema_version":1,) <>
          ~s("metadata":{"#{novel.()}":"#{novel.()}"},) <>
          ~s("root":{"id":"blk_root","type":"#{novel.()}","type_version":1,) <>
          ~s("config":{"#{novel.()}":"#{novel.()}"},) <>
          ~s("slots":{"#{novel.()}":[{"id":"blk_child","type":"#{novel.()}",) <>
          ~s("type_version":1}]}}})

      before_count = :erlang.system_info(:atom_count)
      assert {:ok, _document} = Document.from_json(json)
      assert :erlang.system_info(:atom_count) == before_count
    end
  end

  # --- Helpers --------------------------------------------------------------

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
