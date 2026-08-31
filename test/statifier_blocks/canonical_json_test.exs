defmodule StatifierBlocks.CanonicalJsonTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Document, DocumentFixtures}

  describe "the worked example (headline acceptance test)" do
    # sabotage: in `object/1`, drop the `Enum.sort_by/2` call -> the
    # envelope and block objects encode in struct-field order instead of
    # UTF-8 key order -> red
    test "to_json/1 of the hand-built document equals the fixture bytes exactly" do
      assert Document.to_json(DocumentFixtures.worked_example()) ==
               DocumentFixtures.worked_example_json()
    end

    # sabotage: change the fixture read helper to skip
    # `String.trim_trailing/1` while a trailing newline is present in the
    # fixture file -> red (this asserts the fixture itself carries none)
    test "the fixture bytes contain no newline, and no space outside a string" do
      json = DocumentFixtures.worked_example_json()
      refute String.contains?(json, "\n")

      # Strip JSON string literals (handling `\"` inside them) before
      # checking for stray spaces, so a space inside e.g. "budget_remaining > amount"
      # doesn't false-positive.
      without_strings = Regex.replace(~r/"(?:[^"\\]|\\.)*"/, json, "")
      refute String.contains?(without_strings, " ")
    end
  end

  describe "the signup wizard (the second worked example)" do
    # sabotage: in `object/1`, drop the `Enum.sort_by/2` call -> the
    # wizard's `arm_variant_b`/`otherwise` and `body`/`interrupts` slots
    # encode in insertion order instead of UTF-8 key order -> red
    test "to_json/1 of the hand-built wizard equals the fixture bytes exactly" do
      assert Document.to_json(DocumentFixtures.signup_wizard()) ==
               DocumentFixtures.signup_wizard_json()
    end

    # sabotage: change the fixture read helper to skip
    # `String.trim_trailing/1` while a trailing newline is present in the
    # fixture file -> red (this asserts the fixture itself carries none)
    test "the wizard's fixture bytes contain no newline, and no space outside a string" do
      json = DocumentFixtures.signup_wizard_json()
      refute String.contains?(json, "\n")

      without_strings = Regex.replace(~r/"(?:[^"\\]|\\.)*"/, json, "")
      refute String.contains?(without_strings, " ")
    end

    # sabotage: make `Document.from_json/1` drop `metadata` -> red, because
    # the decoded document stops equalling the one built in memory.
    test "from_json/1 of the fixture bytes equals the hand-built wizard" do
      assert Document.from_json(DocumentFixtures.signup_wizard_json()) ==
               {:ok, DocumentFixtures.signup_wizard()}
    end
  end

  describe "key sorting" do
    # sabotage: change `Enum.sort_by(&elem(&1, 0))` to `Enum.reverse/1` in
    # `object/1` -> the metadata/config/slots keys stop being sorted -> red
    test "metadata, config, and slots encode with sorted keys regardless of insertion order" do
      root =
        Block.new("core.branch",
          id: "blk_root",
          # Reverse-sorted insertion order.
          config: %{"zeta" => 1, "alpha" => 2},
          slots: %{
            "zeta_slot" => [Block.new("core.wait", id: "blk_z")],
            "alpha_slot" => [Block.new("core.wait", id: "blk_a")]
          }
        )

      document =
        Document.new(root, metadata: %{"zeta_meta" => 1, "alpha_meta" => 2})

      json = Document.to_json(document)

      assert json =~ ~s("metadata":{"alpha_meta":2,"zeta_meta":1})
      assert json =~ ~s("config":{"alpha":2,"zeta":1})
      assert json =~ ~s("alpha_slot")
      alpha_index = :binary.match(json, "alpha_slot") |> elem(0)
      zeta_index = :binary.match(json, "zeta_slot") |> elem(0)
      assert alpha_index < zeta_index
    end

    # sabotage: sort with `Enum.sort_by(&elem(&1, 0), :desc)` -> non-ASCII
    # keys would sort by codepoint collation coincidentally matching byte
    # order for these two, so instead assert against a pair whose UTF-8
    # byte order differs from naive codepoint ordering being reversed: a
    # direct string comparison confirms byte order, not locale order
    test "non-ASCII keys sort by UTF-8 byte order, not codepoint collation" do
      root =
        Block.new("core.wait",
          id: "blk_root",
          config: %{"é" => 1, "e" => 2, "à" => 3}
        )

      document = Document.new(root)
      json = Document.to_json(document)

      # UTF-8 bytes: "e" (0x65) < "à" (0xC3 0xA0) < "é" (0xC3 0xA9)
      e_index = :binary.match(json, ~s("e":2)) |> elem(0)
      a_grave_index = :binary.match(json, ~s("à":3)) |> elem(0)
      e_acute_index = :binary.match(json, ~s("é":1)) |> elem(0)

      assert e_index < a_grave_index
      assert a_grave_index < e_acute_index
    end
  end

  describe "omission rules" do
    # sabotage: always include `slots` via `maybe_put/3` unconditionally
    # instead of `maybe_put_slots/2` -> a leaf block encodes `"slots":{}`
    # -> red
    test "a leaf block emits no slots key" do
      block = Block.new("core.wait", id: "blk_leaf")
      document = Document.new(block)

      refute Document.to_json(document) =~ ~s("slots")
    end

    # sabotage: drop the `value == %{}` guard clause in `maybe_put/3` ->
    # empty config is emitted as `"config":{}` -> red
    test "an empty config emits no config key" do
      block = Block.new("core.wait", id: "blk_leaf", config: %{})
      document = Document.new(block)

      refute Document.to_json(document) =~ ~s("config")
    end

    # sabotage: same guard removal, applied to the document's metadata
    # pair -> red
    test "empty metadata emits no metadata key" do
      document = Document.new(Block.new("core.wait", id: "blk_leaf"))

      refute Document.to_json(document) =~ ~s("metadata")
    end

    # sabotage: in `maybe_put_slots/2`, reject nothing (drop the
    # `Enum.reject/2` call) -> the empty slot survives as `"empty":[]` ->
    # red
    test "a block with one empty and one non-empty slot emits only the non-empty one" do
      child = Block.new("core.wait", id: "blk_child")

      root =
        Block.new("core.branch",
          id: "blk_root",
          slots: %{"full" => [child], "empty" => []}
        )

      json = Document.to_json(Document.new(root))

      assert json =~ ~s("slots":{"full":)
      refute json =~ ~s("empty")
    end
  end

  describe "escaping" do
    for {label, input} <- [
          {"a double quote", ~s(say "hi")},
          {"a backslash", ~s(a\\b)},
          {"a newline", "line1\nline2"},
          {"a tab", "col1\tcol2"},
          {"a control character", <<1>>},
          {"a multi-byte UTF-8 string", "café ☃"}
        ] do
      # sabotage: replace `JSON.encode!(value)` with unescaped quoting
      # (`["\"", value, "\""]`) for the binary scalar clause -> the quote,
      # backslash, newline, tab, and control-character cases in this loop
      # go red (the multi-byte UTF-8 case needs no escaping and survives)
      test "#{label} round-trips through JSON.decode/1 back to the input value" do
        input = unquote(Macro.escape(input))
        block = Block.new("core.wait", id: "blk_leaf", config: %{"v" => input})
        document = Document.new(block)

        json = Document.to_json(document)
        assert {:ok, decoded} = JSON.decode(json)
        assert decoded["root"]["config"]["v"] == input
      end
    end
  end

  describe "content_hash/1" do
    # sabotage: hash `inspect(document)` instead of `to_json(document)` ->
    # two structurally-equal documents built independently would still
    # match by coincidence of `inspect/1` on equal structs, so instead
    # sabotage by hashing a fixed string ("sha256:" <> Base.encode16(...,
    # "constant")) -> both assertions below go red
    test "is equal for two independently built equal documents" do
      build = fn ->
        Document.new(
          Block.new("core.wait", id: "blk_leaf", config: %{"a" => 1}),
          id: "bdoc_fixed",
          revision: 3
        )
      end

      assert Document.content_hash(build.()) == Document.content_hash(build.())
    end

    # sabotage: drop `maybe_put(pairs, "config", block.config)` in
    # `value/1`'s block clause so `config` is never encoded -> the two
    # documents below differ only in `config` and would encode to
    # identical bytes -> red
    test "differs when any one field differs" do
      base =
        Document.new(Block.new("core.wait", id: "blk_leaf", config: %{"a" => 1}),
          id: "bdoc_fixed",
          revision: 3
        )

      changed =
        Document.new(Block.new("core.wait", id: "blk_leaf", config: %{"a" => 2}),
          id: "bdoc_fixed",
          revision: 3
        )

      refute Document.content_hash(base) == Document.content_hash(changed)
    end

    # sabotage: drop the `"sha256:" <>` prefix -> this format assertion
    # goes red
    test "is formatted as sha256:<64 lowercase hex chars>" do
      document = Document.new(Block.new("core.wait", id: "blk_leaf"))
      assert "sha256:" <> hex = Document.content_hash(document)
      assert String.length(hex) == 64
      assert hex == String.downcase(hex)
    end
  end

  describe "datamodel (ADR-0001 decision 11)" do
    alias StatifierBlocks.Document.DatamodelEntry

    # sabotage: reverse `pairs` immediately before the join in `object/1`
    # -> the entry's own keys come out in insertion order (id, expr,
    # description) instead of sorted -> red (verified)
    test "an entry's own keys are sorted" do
      document =
        Document.new(Block.new("core.wait", id: "blk_leaf"),
          datamodel: [%DatamodelEntry{id: "targets", expr: "[]", description: "the list"}]
        )

      json = Document.to_json(document)

      assert json =~
               ~s("datamodel":[{"description":"the list","expr":"[]","id":"targets"}])
    end

    # sabotage: change `maybe_put_scalar/3`'s `nil` clause to
    # `[{key, nil} | pairs]` instead of dropping the pair -> a nil expr
    # would encode as `"expr":null` -> red
    test "a nil expr and a nil description are omitted, not encoded as null" do
      document =
        Document.new(Block.new("core.wait", id: "blk_leaf"),
          datamodel: [%DatamodelEntry{id: "targets"}]
        )

      json = Document.to_json(document)

      assert json =~ ~s("datamodel":[{"id":"targets"}])
      refute json =~ "null"
    end

    # sabotage: drop the `maybe_put_list/3` call from `encode/1` entirely
    # -> a non-empty datamodel would never reach the bytes at all -> red
    # (verified: this also fails the two tests above)
    # The second document is the worked example with its own declarations
    # taken back off (sb-vjeg migrated the shipped fixtures onto the key),
    # which is byte for byte the document as it stood before decision 11 -
    # a full, realistic tree whose bytes the key must not touch when it is
    # empty. Built by stripping rather than restated, so it keeps tracking
    # the fixture.
    test "an empty datamodel is omitted from the bytes entirely" do
      with_empty = Document.new(Block.new("core.wait", id: "blk_leaf"))
      without_key_ever_existing = %{DocumentFixtures.worked_example() | datamodel: []}

      refute Document.to_json(with_empty) =~ "datamodel"
      refute Document.to_json(without_key_ever_existing) =~ "datamodel"
    end

    # sabotage: reverse `value` in the `is_list(value)` clause before
    # mapping over it (`value |> Enum.reverse() |> Enum.map(&value/1)`)
    # -> the encoded datamodel order comes out reversed from declaration
    # order -> red (verified)
    test "list order is preserved rather than sorted" do
      document =
        Document.new(Block.new("core.wait", id: "blk_leaf"),
          datamodel: [
            %DatamodelEntry{id: "zeta"},
            %DatamodelEntry{id: "alpha"}
          ]
        )

      json = Document.to_json(document)

      assert json =~ ~s("datamodel":[{"id":"zeta"},{"id":"alpha"}])
    end

    # Pinned `:id` on both documents so only the datamodel order differs
    # - an unpinned `Document.new/2` mints a fresh random document id
    # every call, which would make the two encodings differ regardless
    # of whether the datamodel itself was sorted.
    # sabotage: sort `document.datamodel` by `& &1.id` in `encode/1`
    # before passing it to `maybe_put_list/3` -> both orderings below
    # would encode to the identical sorted bytes and this goes red
    # (verified)
    test "a reordered datamodel is different bytes" do
      forward =
        Document.new(Block.new("core.wait", id: "blk_leaf"),
          id: "bdoc_fixed",
          datamodel: [%DatamodelEntry{id: "zeta"}, %DatamodelEntry{id: "alpha"}]
        )

      backward =
        Document.new(Block.new("core.wait", id: "blk_leaf"),
          id: "bdoc_fixed",
          datamodel: [%DatamodelEntry{id: "alpha"}, %DatamodelEntry{id: "zeta"}]
        )

      refute Document.to_json(forward) == Document.to_json(backward)
    end

    # Pinned `:id` on both documents, for the same reason as the
    # reordering test above: only the datamodel entry's `description`
    # should differ between `base` and `changed`.
    # sabotage: drop `maybe_put_scalar(pairs, "description", entry.description)`
    # from `value/1`'s `%DatamodelEntry{}` clause -> two documents
    # differing only in a datamodel entry's description would encode to
    # identical bytes and hash identically -> red (verified)
    test "content_hash/1 differs for two documents differing only in an entry's description" do
      base =
        Document.new(Block.new("core.wait", id: "blk_leaf"),
          id: "bdoc_fixed",
          datamodel: [%DatamodelEntry{id: "targets", description: "one"}]
        )

      changed =
        Document.new(Block.new("core.wait", id: "blk_leaf"),
          id: "bdoc_fixed",
          datamodel: [%DatamodelEntry{id: "targets", description: "two"}]
        )

      refute Document.content_hash(base) == Document.content_hash(changed)
    end
  end

  describe "to_json/1 on an invalid document" do
    # sabotage: change `to_json/1`'s error clause to hardcode
    # `raise ArgumentError` with no message argument that mentions the
    # `RuntimeError`/`ArgumentError` distinction -> the `assert_raise`
    # exception-type check below goes red if the raise were changed to
    # `raise RuntimeError` instead
    test "raises ArgumentError, not FunctionClauseError, for a document carrying a float" do
      block = Block.new("core.wait", id: "blk_leaf", config: %{"ratio" => 1.5})
      document = Document.new(block)

      assert_raise ArgumentError, fn -> Document.to_json(document) end
    end
  end
end
