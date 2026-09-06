defmodule StatifierBlocks.Compiler.BothStageFindingsTest do
  @moduledoc """
  Config and Structure are reported together (RQ-SF035-2, and the dated
  Notes of 2026-09-06 on ADR-0004 decision 10 and ADR-0011 decision 1).

  Two claims, and both are needed. The first is the change: a `:config`
  finding on one card no longer hides an unsatisfied read on another, so the
  refusal an author gets carries the union of what the two stages found.
  The second is the price of it: a block whose config Config refused
  declares nothing Structure will believe, so that block is skipped by id -
  it produces no Structure finding of its own and leaves no entry in the
  environment - while the walk continues past it.

  Without the second claim the first is worse than what it replaces: the
  refused block's own write signature is read off the config that was
  refused, so a document would start reporting reads satisfied by a type
  nobody declared.

  A pure test. Everything asserted here is decided in
  `StatifierBlocks.Compiler`, which is where both stages run.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, Palette}
  alias StatifierBlocks.CardProcessingFixtures, as: Cards

  defmodule Refused do
    @moduledoc """
    Writes `Settled` at the path its one field names, and refuses every
    config it is given.

    The two halves are the point: were its write signature believed, the
    settle step after it would read `Settled` and find it.
    """

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config),
      do: [
        %{
          key: "at",
          type: {:path, %{writes: "Settled"}},
          label: "Write the settled shape to",
          required?: true,
          default: ""
        }
      ]

    @impl true
    def validate_config(_config), do: {:error, [{"at", "this config is refused"}]}
    @impl true
    def io(_config), do: %{kinds: [:step]}
    @impl true
    def palette_entry, do: %{label: "Refused"}
    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule Accepted do
    @moduledoc "`Refused`, with the one difference the pair is here to isolate."

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    defdelegate slots(config), to: Refused
    @impl true
    defdelegate config_schema(config), to: Refused
    @impl true
    def validate_config(_config), do: :ok
    @impl true
    defdelegate io(config), to: Refused
    @impl true
    def palette_entry, do: %{label: "Accepted"}
    @impl true
    defdelegate emit(block, context), to: Refused
  end

  defp palette do
    Palette.new(
      Map.merge(Palette.core_types(), %{
        "cards.open" => Cards.Open,
        "cards.settle" => Cards.Settle,
        "cards.refused" => Refused,
        "cards.accepted" => Accepted
      })
    )
  end

  # `blk_OPEN` puts `cards.credit_txn` at the subject path; `blk_WRITE`
  # claims to put `Settled` there; `blk_STL` reads `Settled` there. Nothing
  # widens `cards.credit_txn` into `Settled`, so whether the settle step
  # refuses is exactly the question of whether `blk_WRITE`'s write was
  # believed.
  defp document(write_type) do
    Cards.document([
      Cards.open(),
      Block.new(write_type, id: "blk_WRITE", config: %{"at" => Cards.subject()}),
      Cards.settle("blk_STL", %{"expects" => "Settled"})
    ])
  end

  defp codes(findings), do: Enum.map(findings, &{&1.stage, &1.block_id, &1.code})

  # Sabotage: put `structure_stage/4` back behind `config_stage/2` in
  # `compile/3`'s `with` - red, because the refusal then carries the
  # `:config` finding alone and the author never sees the read.
  test "a config finding on one card and an unsatisfied read on another come back together" do
    assert {:error, findings} =
             Compiler.compile(document("cards.refused"), palette(), datamodel: Cards.datamodel())

    assert codes(findings) == [
             {:config, "blk_WRITE", :invalid_config},
             {:structure, "blk_STL", :type_mismatch}
           ]
  end

  # The other half of the golden: the same document with the config accepted
  # reports neither finding, which is what says the first test is reporting two
  # independent facts rather than one fact twice.
  #
  # Sabotage: made `refused_block_ids/1` answer `MapSet.new()` - red, because
  # the refused document then behaves like this one and the two goldens stop
  # disagreeing.
  test "the same document with the config accepted no longer reports either finding" do
    assert {:error, findings} =
             Compiler.compile(document("cards.accepted"), palette(), datamodel: Cards.datamodel())

    refute Enum.any?(findings, &(&1.stage in [:config, :structure])),
           "with the write believed, the read is satisfied and neither stage has anything to say"
  end

  # Sabotage: made `Environment.through/5` apply a skipped block's writes
  # anyway - red, because `blk_STL`'s read is then satisfied by a type the
  # refused config named and the `:type_mismatch` disappears.
  test "a block whose config was refused contributes nothing to the environment walk" do
    assert {:error, findings} =
             Compiler.compile(document("cards.refused"), palette(), datamodel: Cards.datamodel())

    assert Enum.any?(findings, &(&1.block_id == "blk_STL" and &1.code == :type_mismatch)),
           "the refused block's declared write must not reach the block after it"
  end

  # The walk is not shortened - what comes after a skipped block is checked
  # exactly as it was. Two settle steps after the refused block both report.
  #
  # Sabotage: made `Assignability.validate/3` return `[]` for the whole
  # document once `ctx[:skip_blocks]` is non-empty - red on the second
  # finding, which is the one that says the walk continued.
  test "the walk continues past a skipped block" do
    document =
      Cards.document([
        Cards.open(),
        Block.new("cards.refused", id: "blk_WRITE", config: %{"at" => Cards.subject()}),
        Cards.settle("blk_STL", %{"expects" => "Settled"}),
        Cards.settle("blk_STL2", %{"expects" => "Settled"})
      ])

    assert {:error, findings} =
             Compiler.compile(document, palette(), datamodel: Cards.datamodel())

    assert codes(findings) == [
             {:config, "blk_WRITE", :invalid_config},
             {:structure, "blk_STL", :type_mismatch},
             {:structure, "blk_STL2", :type_mismatch}
           ]
  end

  # Later stages are unchanged: Chart still never sees a document Structure
  # refused, so a structural cause is not reported beside its chart-stage
  # consequence.
  #
  # Sabotage: made `config_and_structure_stages/4` answer `:ok` on a
  # non-empty finding list - red, because the pipeline then runs on and the
  # emit-stage findings arrive beside the structure ones.
  test "the stages after Structure still do not run" do
    assert {:error, findings} =
             Compiler.compile(document("cards.refused"), palette(), datamodel: Cards.datamodel())

    assert Enum.map(findings, & &1.stage) |> Enum.uniq() |> Enum.sort() == [:config, :structure]
  end
end
