defmodule StatifierBlocks.Compiler.ByteCorpusTest do
  @moduledoc """
  `sb-hxs5`'s byte assertion. ADR-0002's amendment of 2026-09-06 section 6
  counts five kinds of document whose compiled bytes move; this file pins
  the complement of that list.

  The goldens under `test/fixtures/corpus/` were captured from this
  branch's base - `origin/main` at `757ff3f`, package version 0.21.0 -
  before any code of this bead was written, which is what makes the claim
  a real one rather than a restatement of today's output. Regenerating
  them from a later main would silently turn this file into a
  tautology, so a golden is only ever replaced deliberately, by a change
  that names in its own commit message which of section 6's five classes
  the document has joined.

  Two of the entries are the family's worked examples, whose `myapp.*`
  types declare no outcomes and so class nothing. The other three are the
  three shipped types that class an outcome, each with its failure slot
  **occupied** - section 2's "with the slot occupied every byte is what it
  is today", cashed.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{ByteCorpus, Compiler}

  # sabotage: emitted the shared failed final for an empty collected set
  # -> every document gains a top-level final it can never enter and this
  # goes red on ten goldens at once (verified)
  for {name, _document, _palette} <- ByteCorpus.entries(),
      {mode, _opts} <- ByteCorpus.modes() do
    test "#{name} compiles byte-identically to 0.21.0 under #{mode}" do
      {name, document, palette} =
        Enum.find(ByteCorpus.entries(), &(elem(&1, 0) == unquote(name)))

      {mode, opts} = Enum.find(ByteCorpus.modes(), &(elem(&1, 0) == unquote(mode)))

      assert {:ok, compiled} = Compiler.compile(document, palette, opts)
      assert compiled.scxml == File.read!(ByteCorpus.golden_path(name, mode))
    end
  end

  # A corpus nobody reaches proves nothing: this asserts the entries are
  # the ones the moduledoc names, so a golden quietly deleted or an entry
  # quietly dropped fails here rather than passing vacuously.
  #
  # sabotage: dropped `invoke_handled` from the corpus -> the occupied
  # `core.invoke` case stops being pinned and this goes red (verified)
  test "the corpus is the five documents, in three modes each" do
    assert Enum.map(ByteCorpus.entries(), &elem(&1, 0)) == [
             "worked_example",
             "signup_wizard",
             "invoke_handled",
             "map_handled",
             "subchart_handled"
           ]

    assert Enum.map(ByteCorpus.modes(), &elem(&1, 0)) == ["plain", "terminate", "child_use"]

    for {name, _document, _palette} <- ByteCorpus.entries(),
        {mode, _opts} <- ByteCorpus.modes() do
      assert File.exists?(ByteCorpus.golden_path(name, mode)),
             "missing golden for #{name}/#{mode}"
    end
  end
end
