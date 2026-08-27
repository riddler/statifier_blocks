defmodule StatifierBlocks.BlockTypeFixtures do
  @moduledoc """
  Test-only `StatifierBlocks.BlockType` implementations for phase 1 of
  ADR-0002. `Toy` implements all nine callbacks so a test can exercise
  every one of them; `Minimal` implements only the five required callbacks
  so a test can confirm the four optional ones genuinely degrade rather
  than being silently required. `StringKeyedFixtures` and `PathFixtures`
  exist only to cover two of the four `fixtures/0` spellings amendment 9a
  names that `Toy`'s atom-keyed map cannot demonstrate on its own.
  `ErroringMigration` and `NoMigration` (phase 3) cover
  `Palette.resolve/2`'s two `:migration_failed` causes: a `migrate_config/2`
  that itself errors, and a type whose config shape has changed with no
  `migrate_config/2` at all.

  `raw_palette/0` returns the plain `%{type_name => module}` map phase 1
  needed, kept for anything that wants the bare map. `palette/0` (phase 2)
  wraps the same map in a `StatifierBlocks.Palette`, which is what every
  phase-2-and-later test should reach for.
  """

  alias StatifierBlocks.Block
  alias StatifierBlocks.Palette

  defmodule Toy do
    @moduledoc """
    Implements all nine `StatifierBlocks.BlockType` callbacks, modelled on
    ADR-0002's `MyApp.Blocks.Score` worked example: a config-parameterized
    review slot, a cross-field validation rule that lives only in
    `validate_config/1`, and a v1 -> v2 config-key rename.
    """

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 2

    # Config-parameterized (ADR-0001 decision 5): the review slot exists
    # only when the author asked for one.
    @impl true
    def slots(%{"review_below" => floor}) when is_integer(floor),
      do: [{"review", :at_least_one, "If the score is below the floor"}]

    def slots(_config), do: []

    @impl true
    def config_schema(config) do
      [
        %{
          key: "model",
          type: {:select, [{"lead_v3", "Lead score v3"}, {"account_v1", "Account score v1"}]},
          label: "Model",
          required?: true,
          default: "lead_v3"
        },
        %{
          key: "assign_to",
          type: :string,
          label: "Write score to",
          required?: true,
          default: "score"
        }
      ] ++ review_fields(config)
    end

    defp review_fields(%{"review_below" => _}),
      do: [
        %{
          key: "review_below",
          type: :integer,
          label: "Review below",
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
        |> check_model(config)
        |> check_assign_to(config)
        |> check_floor(config)

      if findings == [], do: :ok, else: {:error, Enum.reverse(findings)}
    end

    defp check_model(f, %{"model" => m}) when m in ["lead_v3", "account_v1"], do: f
    defp check_model(f, _), do: [{"model", "pick a model"} | f]

    defp check_assign_to(f, %{"assign_to" => a}) when is_binary(a) do
      if Regex.match?(~r/\A[a-z][a-z0-9_]*\z/, a),
        do: f,
        else: [{"assign_to", "must be a bare lowercase identifier"} | f]
    end

    defp check_assign_to(f, _), do: [{"assign_to", "required"} | f]

    defp check_floor(f, %{"review_below" => n}) when is_integer(n) and n in 0..100, do: f

    defp check_floor(f, %{"review_below" => _}),
      do: [{"review_below", "must be an integer from 0 to 100"} | f]

    defp check_floor(f, _), do: f

    @impl true
    def io(_config), do: %{consumes: ["record"], produces: ["score"]}

    # ADR-0004 owns the real shape; a marker tuple exercises the callback
    # without asserting a contract this bead does not own.
    @impl true
    def emit(%Block{id: id}, context), do: {:ok, {:emitted, id, context}}

    # v1 spelled the target key `field`; v2 spells it `assign_to`.
    @impl true
    def migrate_config(1, config) do
      {value, rest} = Map.pop(config, "field", "score")
      {:ok, Map.put(rest, "assign_to", value)}
    end

    def migrate_config(from, _config), do: {:error, {:no_migration_from, from}}

    # Atom top-level keys: the Elixir spelling written by hand.
    @impl true
    def fixtures do
      %{
        datasets: %{
          "hot-lead" => %{"record" => %{"pages_viewed" => 14}},
          "cold-lead" => %{"record" => %{"pages_viewed" => 1}}
        },
        expressions: %{
          "needs_review" => %{
            "source" => "score < 50",
            "expect" => %{"hot-lead" => false, "cold-lead" => true}
          }
        }
      }
    end

    @impl true
    def palette_entry, do: %{label: "Score record", group: "Enrichment"}
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
      "toy.score" => Toy,
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
