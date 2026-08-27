defmodule StatifierBlocks.Compiler.ProvenanceTest do
  @moduledoc """
  The provenance map as the compiler actually builds it (ADR-0004 decision
  5), over the ADR-0001 worked example rather than a hand-written map.

  The record's acceptance property is that the map is **total over the
  emission** and that its two keys agree, so both are stated here as
  properties over the artifact rather than as spot checks: an unowned byte
  and a disagreeing state are each a compiler bug, and each is checkable.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Compiler, CoreFixtures, DocumentFixtures, Provenance}
  alias StatifierBlocks.Compiler.StateId

  setup do
    document = DocumentFixtures.worked_example()
    {:ok, compiled} = Compiler.compile(document, CoreFixtures.palette())

    %{document: document, compiled: compiled}
  end

  # Sabotage: made `Serializer.record_span/3` skip elements whose owner
  # carries a role - red with several hundred unowned offsets, which is
  # what "total over the emission" means.
  test "every byte of the generated chart has an owner", ctx do
    %{scxml: scxml, provenance: provenance} = ctx.compiled

    unmapped =
      for offset <- 0..(byte_size(scxml) - 1),
          match?({:error, _reason}, Provenance.owner_at(provenance, offset)),
          do: offset

    assert unmapped == []
  end

  # The same property over a corpus rather than one document. The
  # generator draws arbitrary type names and slot names, so most of what
  # it produces does not compile at all; the ones that do are the point,
  # and each is a shape nobody wrote by hand.
  #
  # Sabotage: attributed the `<scxml>` element to `nil` - red here, as it
  # is on the worked example above. This test adds breadth rather than a
  # distinct failure mode: it is the same property over shapes nobody
  # chose, which is what catches the case a hand-written example misses.
  test "the map is total over a generated corpus, not just the worked example" do
    compiled =
      for index <- 0..199,
          {:ok, artifact} <-
            [
              Compiler.compile(
                StatifierBlocks.DocumentGenerator.generate(20_260_826, index),
                CoreFixtures.palette()
              )
            ],
          do: artifact

    assert length(compiled) > 10

    for artifact <- compiled do
      unmapped =
        Enum.filter(0..(byte_size(artifact.scxml) - 1), fn offset ->
          match?({:error, _reason}, Provenance.owner_at(artifact.provenance, offset))
        end)

      assert unmapped == []
    end
  end

  # Sabotage: made `record_state/2` store `Provenance.owner(id)` - a fresh
  # owner with no role - instead of the resolved one, and the two keys
  # stopped agreeing on every auxiliary state.
  test "the span-keyed and state-keyed lookups agree on every generated state", ctx do
    %{scxml: scxml, provenance: provenance} = ctx.compiled

    disagreements =
      for {state_id, owner} <- provenance.by_state_id do
        {start, _length} = :binary.match(scxml, ~s(id="#{state_id}"))
        {:ok, by_span} = Provenance.owner_at(provenance, start + 4)
        {state_id, by_span, owner}
      end
      |> Enum.reject(fn {_id, by_span, owner} -> by_span == owner end)

    assert disagreements == []
  end

  # Sabotage: dropped the `s_` prefix guard from `StateId.unstate_id/1` -
  # red, because `by_state_id` then also carries ids this package never
  # minted.
  test "every block in the document has its own state in the map", ctx do
    for block <- StatifierBlocks.Document.blocks(ctx.document) do
      state_id = StateId.state_id(block.id)

      assert {:ok, owner} = Provenance.owner_of_state(ctx.compiled.provenance, state_id)
      assert owner == Provenance.owner(block.id)
    end
  end

  # Sabotage: made `Attribution.role/2` return the owner unchanged - red,
  # because an auxiliary state then reports role `nil` and a highlighting
  # caller cannot tell a block's own state from one it minted.
  test "an auxiliary state carries the role its block minted it under", ctx do
    provenance = ctx.compiled.provenance

    assert {:ok, %{block_id: "blk_AUTH", role: nil}} =
             Provenance.owner_of_state(provenance, "s_blk_AUTH")

    assert {:ok, %{block_id: "blk_AUTH", role: "running"}} =
             Provenance.owner_of_state(provenance, "s_blk_AUTH__running")

    assert {:ok, %{block_id: "blk_AUTH", role: "done"}} =
             Provenance.owner_of_state(provenance, "s_blk_AUTH__done")
  end

  # Sabotage: removed the `Emission.attributed_to/2` call from
  # `Core.Emit.chain/2` - red, because the transition then belongs to the
  # sequence that emitted it rather than the step it leaves.
  test "a sequencing transition belongs to the child it leaves, not the container", ctx do
    %{scxml: scxml, provenance: provenance} = ctx.compiled

    {offset, _length} = :binary.match(scxml, ~s(<transition event="done.state.s_blk_AUTH"))

    assert {:ok, %{block_id: "blk_AUTH", role: nil, config_key: nil}} =
             Provenance.owner_at(provenance, offset)
  end

  # Sabotage: made `Emission.attribute_from_config/3` a no-op - red,
  # because the `cond` value's span then carries no config key and the
  # fault split has nothing to turn on.
  test "an arm's cond value carries the config key the author typed it into", ctx do
    %{scxml: scxml, provenance: provenance} = ctx.compiled

    {element, _length} = :binary.match(scxml, ~s(<transition cond="budget_remaining))
    {value, _length} = :binary.match(scxml, "budget_remaining &gt; amount")

    assert {:ok, %{block_id: "blk_BR", role: "pick", config_key: nil}} =
             Provenance.owner_at(provenance, element)

    assert {:ok, %{block_id: "blk_BR", role: "pick", config_key: "arm_approved"}} =
             Provenance.owner_at(provenance, value)
  end

  # Sabotage: attributed the `<scxml>` element to `nil` instead of the root
  # block - red, because the offsets outside any state then have no owner
  # and the map stops being total.
  test "the chart-level element is attributed to the root block", ctx do
    assert {:ok, %{block_id: "blk_ROOT", role: nil, config_key: nil}} =
             Provenance.owner_at(ctx.compiled.provenance, 0)
  end

  # Sabotage: made `Serializer.serialize/1` collect its spans through a
  # map rather than keeping the list it built - red, because the whole-
  # document span then sorts to the front instead of closing the list.
  #
  # The list is a list, and it is in the order the serializer closed each
  # element: innermost first, the `<scxml>` element last. That is what
  # makes it deterministic, which decision 6 needs and a map cannot give.
  test "the spans close innermost-first, with the whole document last", ctx do
    %{scxml: scxml, provenance: provenance} = ctx.compiled

    assert {{0, whole}, %{block_id: "blk_ROOT", role: nil}} = List.last(provenance.spans)
    assert whole == byte_size(scxml)
    assert length(provenance.spans) > 1
  end

  # Sabotage: made `palette_hash/1` fold in `:erlang.unique_integer/0` -
  # red, because a second compile of an unchanged document then produces a
  # different record and "same triple, same artifact" stops holding.
  test "two compiles of one document produce equal artifacts", ctx do
    {:ok, again} = Compiler.compile(ctx.document, CoreFixtures.palette())

    assert again.scxml == ctx.compiled.scxml
    assert again.provenance == ctx.compiled.provenance
    assert again.record == ctx.compiled.record
  end

  # Sabotage: made `Provenance.to_json/1` encode the spans as a map keyed
  # by start offset - red, because the round trip then loses the ordering
  # the artifact was built with.
  test "the map a host stores beside the chart reads back equal", ctx do
    assert {:ok, decoded} =
             ctx.compiled.provenance |> Provenance.to_json() |> Provenance.from_json()

    assert decoded == ctx.compiled.provenance
  end

  # Sabotage: made `Compiler.compile/3` compute the identity over
  # `inspect(emission)` rather than the serialized bytes - red, because the
  # engine's own hash of the same bytes then differs.
  test "highlighting works end to end: a running configuration maps back to blocks", ctx do
    {:ok, machine} = Statifier.compile(ctx.compiled.scxml, chart_name: ctx.document.id)
    {state, _effects} = Statifier.initialize(machine)

    blocks =
      state
      |> Statifier.active_leaf_states()
      |> Enum.to_list()
      |> then(&Provenance.owners_of_states(ctx.compiled.provenance, &1))
      |> Enum.map(& &1.block_id)

    assert "blk_AUTH" in blocks
  end
end
