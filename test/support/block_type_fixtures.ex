defmodule StatifierBlocks.BlockTypeFixtures do
  @moduledoc """
  Test-only `StatifierBlocks.BlockType` implementations for phase 1 of
  ADR-0002. `Toy` implements nine of the ten callbacks - every one but
  `outcomes/1`, which `Outcomes` below covers - so a test can exercise
  each of them; `Minimal` implements only the five required callbacks
  so a test can confirm the four optional ones genuinely degrade rather
  than being silently required. `StringKeyedFixtures` and `PathFixtures`
  exist only to cover two of the four `fixtures/0` spellings amendment 9a
  names that `Toy`'s atom-keyed map cannot demonstrate on its own.
  `ErroringMigration` and `NoMigration` (phase 3) cover
  `Palette.resolve/2`'s two `:migration_failed` causes: a `migrate_config/2`
  that itself errors, and a type whose config shape has changed with no
  `migrate_config/2` at all.

  `Outcomes`, `OutcomeParent`, `MalformedOutcomes` and `DuplicateOutcomes`
  (sb-x5v) cover ADR-0002 amendment A's `outcomes/1`: a type that declares
  several, a container that reads its children's outcomes out of the
  summary, and the two ways a declaration is refused. They emit real
  `StatifierBlocks.Emission` trees rather than marker tuples, because what
  they are for is a compile that reaches the chart stage.

  `raw_palette/0` returns the plain `%{type_name => module}` map phase 1
  needed, kept for anything that wants the bare map. `palette/0` (phase 2)
  wraps the same map in a `StatifierBlocks.Palette`, which is what every
  phase-2-and-later test should reach for.
  """

  alias StatifierBlocks.Block
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.Emit
  alias StatifierBlocks.Emission
  alias StatifierBlocks.Palette

  defmodule Toy do
    @moduledoc """
    Implements nine of the ten `StatifierBlocks.BlockType` callbacks -
    every one but `outcomes/1` - modelled on
    ADR-0002's `MyApp.Blocks.BudgetCheck` worked example: a config-parameterized
    review slot, a cross-field validation rule that lives only in
    `validate_config/1`, and a v1 -> v2 config-key rename.
    """

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 2

    # Config-parameterized (ADR-0001 decision 5): the review slot exists
    # only when the author asked for one.
    @impl true
    def slots(%{"review_above" => ceiling}) when is_integer(ceiling),
      do: [{"review", :at_least_one, "If the amount is above the ceiling"}]

    def slots(_config), do: []

    @impl true
    def config_schema(config) do
      [
        %{
          key: "policy",
          type:
            {:select,
             [{"standard_v3", "Standard policy v3"}, {"corporate_v1", "Corporate policy v1"}]},
          label: "Policy",
          required?: true,
          default: "standard_v3"
        },
        %{
          key: "assign_to",
          type: :string,
          label: "Write decision to",
          required?: true,
          default: "decision"
        }
      ] ++ review_fields(config)
    end

    defp review_fields(%{"review_above" => _}),
      do: [
        %{
          key: "review_above",
          type: :integer,
          label: "Review above",
          required?: true,
          default: 50
        }
      ]

    defp review_fields(_), do: []

    # The authority (decision 7). The 0..100 bound and the identifier rule
    # live here and nowhere else.
    @impl true
    def validate_config(config) do
      findings =
        []
        |> check_policy(config)
        |> check_assign_to(config)
        |> check_ceiling(config)

      if findings == [], do: :ok, else: {:error, Enum.reverse(findings)}
    end

    defp check_policy(f, %{"policy" => p}) when p in ["standard_v3", "corporate_v1"], do: f
    defp check_policy(f, _), do: [{"policy", "pick a policy"} | f]

    defp check_assign_to(f, %{"assign_to" => a}) when is_binary(a) do
      if Regex.match?(~r/\A[a-z][a-z0-9_]*\z/, a),
        do: f,
        else: [{"assign_to", "must be a bare lowercase identifier"} | f]
    end

    defp check_assign_to(f, _), do: [{"assign_to", "required"} | f]

    defp check_ceiling(f, %{"review_above" => n}) when is_integer(n) and n in 0..100, do: f

    defp check_ceiling(f, %{"review_above" => _}),
      do: [{"review_above", "must be an integer from 0 to 100"} | f]

    defp check_ceiling(f, _), do: f

    @impl true
    def io(_config), do: %{consumes: ["myapp.transaction"], produces: ["decision"]}

    # ADR-0004 owns the real shape; a marker tuple exercises the callback
    # without asserting a contract this bead does not own.
    @impl true
    def emit(%Block{id: id}, context), do: {:ok, {:emitted, id, context}}

    # v1 spelled the target key `field`; v2 spells it `assign_to`.
    @impl true
    def migrate_config(1, config) do
      {value, rest} = Map.pop(config, "field", "decision")
      {:ok, Map.put(rest, "assign_to", value)}
    end

    def migrate_config(from, _config), do: {:error, {:no_migration_from, from}}

    # Atom top-level keys: the Elixir spelling written by hand.
    @impl true
    def fixtures do
      %{
        datasets: %{
          "within-budget" => %{"transaction" => %{"amount" => 120}},
          "over-budget" => %{"transaction" => %{"amount" => 940}}
        },
        expressions: %{
          "needs_review" => %{
            "source" => "amount > 500",
            "expect" => %{"within-budget" => false, "over-budget" => true}
          }
        }
      }
    end

    @impl true
    def palette_entry, do: %{label: "Budget check", group: "Authorization"}
  end

  defmodule Minimal do
    @moduledoc """
    Implements only the five required `StatifierBlocks.BlockType`
    callbacks, and nothing else. Exists to prove the optional four
    (`io/1`, `migrate_config/2`, `fixtures/0`, `palette_entry/0`) are
    genuinely optional: this module compiles with no warning under
    warnings-as-errors, and `function_exported?/3` reports each of the
    four absent.
    """

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
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}
  end

  defmodule ErroringMigration do
    @moduledoc """
    Phase 3 fixture: `current_version/0 == 3`, and a `migrate_config/2` that
    only understands `from: 2` - a block at `type_version: 1` reaches its
    catch-all error clause, exercising `Palette.resolve/2`'s
    `:migration_failed` arm for a migration that itself fails (as opposed
    to `NoMigration`'s absent-callback case below).
    """

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 3

    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config), do: []

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

    @impl true
    def migrate_config(2, config), do: {:ok, config}
    def migrate_config(from, _config), do: {:error, {:no_migration_from, from}}
  end

  defmodule NoMigration do
    @moduledoc """
    Phase 3 fixture: `current_version/0 == 2` with **no** `migrate_config/2`
    at all, so `Palette.resolve/2` reaches the absent-callback branch of
    `:migration_failed` rather than a callback that itself returns an
    error.
    """

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 2

    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config), do: []

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}
  end

  defmodule Outcomes do
    @moduledoc """
    A leaf declaring three outcomes (ADR-0002 amendment A1), deliberately
    **not** in alphabetical order: `done`, `error`, `abandoned`. Declaration
    order is what ADR-0004 decision 6's byte determinism reads, so a
    resolver that sorted the list would be visible here.

    It emits one `<final>` per declared outcome, minted through
    `StatifierBlocks.Compiler.Context.outcome_id/2`, and enters the default
    one - which is enough of a real emission to compile.
    """

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
    def outcomes(_config), do: [{"done", "Done"}, {"error", "Failed"}, {"abandoned", "Given up"}]

    @impl true
    def emit(%Block{config: config}, context) do
      finals =
        __MODULE__
        |> StatifierBlocks.BlockType.outcome_names(config)
        |> Enum.map(fn name ->
          {:ok, id} = Context.outcome_id(context, name)
          Emit.final(id)
        end)

      {:ok, Emit.state(context.state_id, Context.done_id(context), finals)}
    end
  end

  defmodule OutcomeParent do
    @moduledoc """
    A container that wires **every** outcome of every child in its `body`
    slot to its own final, reading the ids and events out of the child
    summaries rather than knowing any child's type (ADR-0004's outcome
    amendment, 2e). What a parent can see of its children's outcomes is
    therefore observable in the bytes it emits.
    """

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: [{"body", :any, "Body"}]

    @impl true
    def config_schema(_config), do: []

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(%Block{}, context) do
      done = Context.done_id(context)
      children = Context.children(context, "body")

      transitions =
        for child <- children, outcome <- child.outcomes do
          Emit.transition(event: outcome.done_event, target: done, internal: true)
        end

      refs = Enum.map(children, &Emission.child_ref(&1.block_id))
      initial = if children == [], do: done, else: hd(children).state_id

      {:ok, Emit.state(context.state_id, initial, transitions ++ refs ++ [Emit.final(done)])}
    end
  end

  defmodule MalformedOutcomes do
    @moduledoc """
    Declares an outcome name outside the role shape, so the compiler
    refuses it with an `:invalid_outcome` Emit finding against the block
    whose type declared it (ADR-0004's outcome amendment, 2f).
    """

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
    def outcomes(_config), do: [{"done", "Done"}, {"Gave Up", "Gave up"}]

    @impl true
    def emit(%Block{}, context),
      do: {:ok, Emit.state(context.state_id, Context.done_id(context), [])}
  end

  defmodule DuplicateOutcomes do
    @moduledoc """
    Declares the same outcome name twice, the other half of 2f's
    `:invalid_outcome`: two finals would carry one id, so the compiler
    refuses rather than emitting a chart whose ids collide.
    """

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
    def outcomes(_config), do: [{"done", "Done"}, {"error", "Failed"}, {"error", "Failed again"}]

    @impl true
    def emit(%Block{}, context),
      do: {:ok, Emit.state(context.state_id, Context.done_id(context), [])}
  end

  defmodule StringKeyedFixtures do
    @moduledoc """
    A one-line `fixtures/0` spelling: a map with string top-level keys,
    the JSON spelling amendment 9a says survives a file. Not a full
    `StatifierBlocks.BlockType`; it exists only for `fixtures/0`
    spelling coverage.
    """

    @doc "The string-keyed `fixtures/0` spelling."
    @spec fixtures() :: map()
    def fixtures, do: %{"version" => 1, "datasets" => %{}}
  end

  defmodule PathFixtures do
    @moduledoc """
    A one-line `fixtures/0` spelling: a binary path, amendment 9a's fourth
    spelling. Not a full `StatifierBlocks.BlockType`; it exists only for
    `fixtures/0` spelling coverage.
    """

    @doc "The path `fixtures/0` spelling."
    @spec fixtures() :: binary()
    def fixtures, do: "palette/toy.fixtures.json"
  end

  @doc """
  The plain `%{type_name => module}` map underlying `palette/0`.
  """
  @spec raw_palette() :: %{Block.type_name() => module()}
  def raw_palette do
    %{
      "toy.budget_check" => Toy,
      "toy.minimal" => Minimal,
      "toy.erroring_migration" => ErroringMigration,
      "toy.no_migration" => NoMigration
    }
  end

  @doc """
  A `StatifierBlocks.Palette` built from `raw_palette/0`, for tests that
  exercise `Palette.fetch/2` and beyond.
  """
  @spec palette() :: Palette.t()
  def palette, do: Palette.new(raw_palette())
end
