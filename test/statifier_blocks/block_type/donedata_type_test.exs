defmodule StatifierBlocks.BlockType.DonedataTypeTest do
  @moduledoc """
  ADR-0013 decisions 2 and 4: the optional `donedata_type/1` callback, the
  resolver every consumer reads it through, and the dormant agreement
  check between what a parent expects of a collected answer and what the
  child's root block type declares.

  The resolver half is `failure_outcomes/2`'s shape exactly - absent means
  nothing declared, and a return the spec does not describe degrades to
  nothing declared rather than crashing a compile. The check half is
  `statifier_datamodel`'s own read check, in its own direction, with the
  child as the held side because the parent is the reader.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.BlockType

  defmodule Chunk do
    @moduledoc """
    `myapp:settlement_chunk`: the root of a child chart that settles one
    chunk of a day's captures and answers with its counts.
    """

    use StatifierBlocks.BlockType

    @impl true
    def emit(_block, _context), do: {:error, :not_compiled_here}

    @impl true
    def donedata_type(config) do
      base = [
        %{name: "settled_count", path: "chunk.settled", type: :integer},
        %{name: "failed_count", path: "chunk.failed", type: :integer}
      ]

      if Map.get(config, "report_total", false),
        do: base ++ [%{name: "total_cents", path: "chunk.total", type: :integer}],
        else: base
    end
  end

  defmodule Silent do
    @moduledoc "A root that declares nothing, where every `core.*` type is."

    use StatifierBlocks.BlockType

    @impl true
    def emit(_block, _context), do: {:error, :not_compiled_here}
  end

  defmodule Nonsense do
    @moduledoc "A host type whose declaration is not one."

    use StatifierBlocks.BlockType

    @impl true
    def emit(_block, _context), do: {:error, :not_compiled_here}

    @impl true
    def donedata_type(config), do: Map.get(config, "declares", :nothing_shaped_like_a_list)
  end

  describe "donedata_type/2, the resolver (decision 2)" do
    # sabotage: had the resolver sort the list by name - the params
    # serialize in the sorted order, a host's compiled bytes move, and
    # this goes red (verified)
    test "reads the callback in declaration order, never sorted" do
      assert BlockType.donedata_type(Chunk, %{}) == [
               %{name: "settled_count", path: "chunk.settled", type: :integer},
               %{name: "failed_count", path: "chunk.failed", type: :integer}
             ]
    end

    # sabotage: read the callback with `apply/3` and no `function_exported?/3`
    # guard - a type that never declared anything raises UndefinedFunctionError
    # inside the compiler and this goes red (verified)
    test "a type that does not export it declares nothing" do
      assert BlockType.donedata_type(Silent, %{}) == []
      assert BlockType.donedata_type(NotAModuleAtAll, %{}) == []
    end

    # sabotage: dropped the sanitizer and returned the callback's value
    # straight - a host type declaring nonsense reaches the emission and
    # mints a `<param>` from a term that is not a field, and this goes red
    # (verified)
    test "any return the spec does not describe degrades to nothing declared" do
      assert BlockType.donedata_type(Nonsense, %{}) == []
      assert BlockType.donedata_type(Nonsense, %{"declares" => ["settled_count"]}) == []

      assert BlockType.donedata_type(Nonsense, %{
               "declares" => [%{name: :settled_count, path: "chunk.settled", type: :integer}]
             }) == []

      assert BlockType.donedata_type(Nonsense, %{
               "declares" => [%{name: "settled_count", type: :integer}]
             }) == []
    end

    # It is a pure function of config, like every other callback that
    # takes one: a config-parameterized declaration declares a different
    # list and nothing else changes.
    #
    # sabotage: read the callback with `config` fixed at `%{}` - the extra
    # field never appears and this goes red (verified)
    test "it is a function of the config it is handed" do
      assert BlockType.donedata_type(Chunk, %{"report_total" => true}) |> Enum.map(& &1.name) ==
               ["settled_count", "failed_count", "total_cents"]
    end
  end

  describe "agrees?/3, the dormant check (decision 4)" do
    setup do
      %{
        declarations:
          StatifierDatamodel.Declarations.from_document(%{
            "types" => [
              %{
                "name" => "cards.settlement_summary",
                "kind" => "shape",
                "label" => "Settlement summary",
                "fields" => [
                  %{"name" => "settled_count", "type" => "integer", "required?" => true},
                  %{"name" => "failed_count", "type" => "integer", "required?" => true}
                ]
              },
              %{
                "name" => "cards.settlement_run",
                "kind" => "record",
                "label" => "Settlement run",
                "fields" => [
                  %{"name" => "settled_count", "type" => "integer", "required?" => true}
                ]
              }
            ]
          })
      }
    end

    # The check's whole point, in one line: the child's declaration
    # answers the shape the parent expects of it.
    #
    # sabotage: passed the two type arguments the other way round - the
    # parent's shape is asked to satisfy the child's record, which is
    # `:not_assignable` by construction, and this goes red (verified)
    test "a child declaring every required member covers the parent's shape", ctx do
      assert BlockType.agrees?(
               ctx.declarations,
               BlockType.donedata_type(Chunk, %{}),
               "cards.settlement_summary"
             ) == :covers
    end

    # sabotage: projected the child's fields as `required?: false` - an
    # optional held field satisfies no required shape field, so every pair
    # answers `{:missing, _}` and the `:covers` assertion above goes red
    # (verified)
    test "a child missing a required member names the members it does not carry", ctx do
      thin = [%{name: "settled_count", path: "chunk.settled", type: :integer}]

      assert BlockType.agrees?(ctx.declarations, thin, "cards.settlement_summary") ==
               {:missing, ["failed_count"]}
    end

    # Dormant in the second sense decision 4 names: the covering step
    # answers only where the expected side is a `shape`, so a
    # `collect_type` naming a `record` says nothing about drift.
    test "a collect_type naming a record is not assignable, whatever the child declares", ctx do
      assert BlockType.agrees?(
               ctx.declarations,
               BlockType.donedata_type(Chunk, %{}),
               "cards.settlement_run"
             ) == :not_assignable
    end

    # Total over the two shapes every stored document is in today: no
    # declaration on either side.
    test "an absent declaration on either side is unknown, not a disagreement", ctx do
      fields = BlockType.donedata_type(Chunk, %{})

      assert BlockType.agrees?(ctx.declarations, fields, "") == :unknown
      assert BlockType.agrees?(ctx.declarations, fields, nil) == :unknown
      assert BlockType.agrees?(%{}, [], "") == :unknown
    end

    # A name the parent document does not declare is `{:opaque, name}` to
    # `Types.parse/2` - a spelling a consumer carries rather than a type
    # this check can decide - and the answer is that package's, rendered
    # as it comes rather than translated into a second vocabulary here.
    test "a collect_type naming nothing the parent declares answers as sd answers", ctx do
      assert BlockType.agrees?(
               ctx.declarations,
               BlockType.donedata_type(Chunk, %{}),
               "cards.unheard_of"
             ) == :not_assignable
    end

    # sabotage: projected the child under the fixed name with no
    # collision walk - a parent that declares that name has its own
    # declaration replaced for the length of the check, the two sides
    # become the same name, and the check answers `:identical` about a
    # shape the child does not actually cover, so this goes red (verified)
    test "the projected name never shadows a declaration the parent wrote", ctx do
      audited = %{
        name: "audited",
        type: :boolean,
        item_type: nil,
        required?: true,
        label: nil,
        one_of: nil
      }

      colliding =
        Map.put(ctx.declarations, "statifier_blocks:child_donedata", %{
          name: "statifier_blocks:child_donedata",
          kind: :shape,
          label: nil,
          fields: [audited]
        })

      assert BlockType.agrees?(
               colliding,
               BlockType.donedata_type(Chunk, %{}),
               "statifier_blocks:child_donedata"
             ) == {:missing, ["audited"]}
    end
  end
end
