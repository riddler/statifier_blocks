defmodule StatifierBlocks.Compiler.SlotFindingsTest do
  @moduledoc """
  The `:structure` stage's two new finding kinds, `:slot_arity_violated`
  and `:undeclared_slot` (ADR-0002 decision 6, sb-da9), through
  `Compiler.compile/3`.

  This file does not re-assert what `compiler/findings_test.exs` already
  owns for the `:structure` stage: no generic document-order test, no
  generic path-presence test, no generic stage-ordering test. That file's
  `describe "decision 10: ordered, typed, and always naming a block"`
  states those properties once, generally, and this file only adds what is
  specific to the two new finding kinds - including the one case that
  necessarily overlaps, the together-not-short-circuit rule, which only
  becomes expressible once a second `:structure` finding source exists.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, CoreFixtures, Document, DocumentFixtures, Palette}
  alias StatifierBlocks.Compiler.{Context, Finding}
  alias StatifierBlocks.Core.Emit

  defmodule Producer do
    @moduledoc "A host leaf that produces a token type for the next block."
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
    def io(_config), do: %{kinds: [:step], produces: "myapp.token"}

    @impl true
    def emit(_block, context) do
      done = Context.done_id(context)
      {:ok, Emit.state(context.state_id, done, [Emit.final(done)])}
    end
  end

  defmodule GatedGroup do
    @moduledoc """
    A host container with one required slot and an inbound type nothing
    in these tests ever produces - the shape needed to put a slot finding
    and an assignability finding on the same block.
    """

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: [{"items", :at_least_one, "Items"}]
    @impl true
    def config_schema(_config), do: []
    @impl true
    def validate_config(_config), do: :ok
    @impl true
    def io(_config), do: %{kinds: [:step], consumes: "myapp.other_token"}

    @impl true
    def emit(_block, context) do
      done = Context.done_id(context)
      {:ok, Emit.state(context.state_id, done, [Emit.final(done)])}
    end
  end

  # Sabotage: made `structure_stage/3` return `:ok` when `slot_findings` is
  # non-empty but `assignability_findings` is empty - red, because a
  # document with only a slot finding then compiled clean.
  test "an empty :at_least_one arm fails the compile with a slot_arity_violated finding" do
    document =
      Document.new(
        Block.new("core.sequence",
          id: "blk_ROOT",
          slots: %{
            "body" => [
              Block.new("core.branch",
                id: "blk_BRANCH",
                config: %{"arms" => [%{"slot" => "arm_review", "cond" => "true"}]}
              )
            ]
          }
        ),
        id: "bdoc_cards"
      )

    assert {:error, [finding]} = Compiler.compile(document, CoreFixtures.palette())

    assert %Finding{
             stage: :structure,
             block_id: "blk_BRANCH",
             fault: :author,
             code: :slot_arity_violated
           } = finding

    assert finding.message =~ "arm_review"
  end

  # Sabotage: dropped the `slot_finding/1` clause for `:undeclared_slot` so
  # the reason fell through unmapped - red with a `FunctionClauseError`
  # instead of a finding.
  test "an undeclared slot key fails the compile with an undeclared_slot finding" do
    document =
      Document.new(
        Block.new("core.sequence",
          id: "blk_ROOT",
          slots: %{
            "body" => [
              Block.new("myapp.notify",
                id: "blk_NOTIFY",
                config: %{"invoke_type" => "cards:notify"},
                slots: %{
                  "stray" => [
                    Block.new("myapp.notify",
                      id: "blk_STRAY",
                      config: %{"invoke_type" => "cards:notify"}
                    )
                  ]
                }
              )
            ]
          }
        ),
        id: "bdoc_cards"
      )

    result = Compiler.compile(document, CoreFixtures.palette())
    refute match?({:ok, _}, result)

    assert {:error, [finding]} = result

    assert %Finding{
             stage: :structure,
             block_id: "blk_NOTIFY",
             fault: :author,
             code: :undeclared_slot
           } = finding

    assert finding.message =~ "stray"
  end

  # Sabotage: made `structure_stage/3` return early on `slot_findings`
  # instead of concatenating with `assignability_findings` - red, because
  # the type mismatch below then never reached the report.
  test "a slot finding and an assignability finding on the same block are both reported, slot first" do
    document =
      Document.new(
        Block.new("core.sequence",
          id: "blk_ROOT",
          slots: %{
            "body" => [
              Block.new("myapp.producer", id: "blk_PRODUCER"),
              Block.new("myapp.gated_group", id: "blk_GATED")
            ]
          }
        ),
        id: "bdoc_cards"
      )

    palette =
      Palette.new(
        Map.merge(Palette.core_types(), %{
          "myapp.producer" => Producer,
          "myapp.gated_group" => GatedGroup
        })
      )

    assert {:error, findings} = Compiler.compile(document, palette)

    assert Enum.map(findings, &{&1.block_id, &1.code}) == [
             {"blk_GATED", :slot_arity_violated},
             {"blk_GATED", :type_mismatch}
           ]
  end

  # Not redundant with `compiler/findings_test.exs`'s first-failing-stage
  # test: that one pins Structure against Chart. This one pins the
  # Config-before-Structure edge, which is where SlotValidation's
  # `slots/1` stability precondition is bought (only accepted config ever
  # reaches Structure).
  #
  # Sabotage: swapped `config_stage/1` and `structure_stage/3` in
  # `compile/3`'s `with` - red, because Structure then saw the rejected
  # config first and the finding's stage came back `:structure`.
  test "Structure still runs only after Config, so a rejected config reports only :config findings" do
    document =
      Document.new(
        Block.new("core.sequence",
          id: "blk_ROOT",
          slots: %{
            "body" => [
              Block.new("core.branch",
                id: "blk_BRANCH",
                config: %{"arms" => [%{"slot" => "arm_review", "cond" => ""}]}
              )
            ]
          }
        ),
        id: "bdoc_cards"
      )

    assert {:error, findings} = Compiler.compile(document, CoreFixtures.palette())
    assert Enum.map(findings, & &1.stage) |> Enum.uniq() == [:config]
  end

  # Sabotage: made `structure_stage/3` return `{:error, []}` instead of
  # `:ok` whenever the concatenated finding list was empty - red on both
  # fixtures, since neither compiles at all once Structure always fails.
  test "the worked example and the signup wizard still compile" do
    assert {:ok, _compiled} =
             Compiler.compile(DocumentFixtures.worked_example(), CoreFixtures.palette())

    assert {:ok, _compiled} =
             Compiler.compile(DocumentFixtures.signup_wizard(), CoreFixtures.palette())
  end
end
