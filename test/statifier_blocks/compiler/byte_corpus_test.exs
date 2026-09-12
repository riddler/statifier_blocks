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

  Six of the fifteen have been replaced once, deliberately, by ADR-0010
  decision 8 (`sb-p8lh`): `worked_example` and `signup_wizard` each hold an
  interruptible group, and decision 8e says in as many words that the
  compiled chart of every such document changes. Their goldens were
  re-captured on that change; the other nine still carry the 0.21.0 bytes
  and are what `StatifierBlocks.Compiler.InterruptsTest` cashes 8e's other
  half against - a document with no such group compiles byte-identical.

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
    test "#{name} compiles byte-identically to its golden under #{mode}" do
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

  # `sb-hykt` (SF041): the donedata key the failure seam mints moved to
  # `statifier_persistence:execution_status` (`statifier_persistence`
  # ADR-0011 decision 4), and the four goldens of the two documents that
  # DO mint a failure-classed final were re-baselined in that same
  # request. This pins the complement the campaign consent asks a test to
  # prove: a document with no failure-classed final compiles byte for
  # byte to what it compiled to before the key moved.
  #
  # The proof is that these three entries' nine goldens were NOT touched
  # by that request - they still carry the bytes captured at 0.21.0 (and,
  # for the two worked examples, at ADR-0010 decision 8) - so the
  # assertion below reads pre-rename bytes out of the tree and compares
  # them against today's compiler. The `refute` is the second half: no
  # key in the `statifier_persistence:` namespace appears at all, so the
  # entries are genuinely the no-failure-classed-final case and the
  # comparison is not passing because both sides moved together.
  #
  # `invoke_handled` is the one of the three whose type classes an
  # outcome; its failure slot is occupied, so nothing propagates to the
  # root and no reserved param is minted. The two worked examples declare
  # no outcomes and class nothing.
  #
  # sabotage: minted the reserved param unconditionally rather than on
  # `failure?` -> all nine of these compiles gain a param their golden
  # does not have and this goes red (verified)
  test "a document with no failure-classed final compiles byte-identically across the rename" do
    for name <- ["worked_example", "signup_wizard", "invoke_handled"],
        {mode, opts} <- ByteCorpus.modes() do
      {^name, document, palette} =
        Enum.find(ByteCorpus.entries(), &(elem(&1, 0) == name))

      assert {:ok, compiled} = Compiler.compile(document, palette, opts)

      refute compiled.scxml =~ "statifier_persistence:",
             "#{name}/#{mode} mints a reserved persistence param"

      assert compiled.scxml == File.read!(ByteCorpus.golden_path(name, mode)),
             "#{name}/#{mode} moved"
    end
  end
end
