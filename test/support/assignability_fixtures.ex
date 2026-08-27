defmodule StatifierBlocks.AssignabilityFixtures do
  @moduledoc """
  Test-only support for ADR-0003's worked example. `CoreFixtures` carries
  the `myapp.*` types the ADR-0001 worked example names, plus `sb-da9`'s
  stand-in walk; this module carries ADR-0003's own worked example instead
  - `myapp.enrich` / `myapp.score` / `myapp.notify` / `myapp.on_cancel`,
  declared with the `consumes`/`produces` the record's worked example
  gives them, plus the widening vocabulary (`myapp.lead` /
  `myapp.scored_lead` / `myapp.person`) that vocabulary needs a host
  relation to interpret.

  Two `StatifierBlocks.Assignability.Relation` implementations: `Widens`,
  the record's own `MyApp.Blocks.Types` verbatim, and `Deny`, which answers
  `false` to everything - the floor case a widen-only relation can never
  fall below, and the fixture Phase 3 and Phase 5 both need to state that.

  Phase 3 needs only these types, the two relation modules, and `palette/1`
  to point a palette at one of them. Phases 4 and 5 extend this file with
  the worked-example document itself, rather than starting a second
  support file - `test/support/` carries one subject per file, and this
  one's subject is ADR-0003's worked example end to end.
  """

  alias StatifierBlocks.{Block, Palette}

  defmodule Enrich do
    @moduledoc "`myapp.enrich`: takes a raw record, hands back a lead."

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
    def io(_config), do: %{consumes: "myapp.record", produces: "myapp.lead"}
    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule Score do
    @moduledoc "`myapp.score`: takes a lead, hands back a scored lead."

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
    def io(_config), do: %{consumes: "myapp.lead", produces: "myapp.scored_lead"}
    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule Notify do
    @moduledoc """
    `myapp.notify`: takes anyone with contact details; produces nothing
    anyone downstream wants.
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
    def io(_config), do: %{consumes: "myapp.person", produces: :unknown}
    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule OnCancel do
    @moduledoc "`myapp.on_cancel`: not a step at all - an interrupt handler."

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
    def io(_config), do: %{kinds: [:interrupt_handler]}
    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule Widens do
    @moduledoc """
    ADR-0003's own worked-example relation, verbatim: `myapp.lead` and
    `myapp.contact` both widen to `myapp.person`, and `myapp.scored_lead`
    widens to either.
    """

    @behaviour StatifierBlocks.Assignability.Relation

    @widens %{
      "myapp.lead" => ["myapp.person"],
      "myapp.contact" => ["myapp.person"],
      "myapp.scored_lead" => ["myapp.lead", "myapp.person"]
    }

    @impl true
    def assignable?(produced, consumed), do: consumed in Map.get(@widens, produced, [])
  end

  defmodule Deny do
    @moduledoc """
    The floor case: a relation module that answers `false` to every pair,
    demonstrating that a host callback can never narrow the identity
    relation - it can only fail to widen it further.
    """

    @behaviour StatifierBlocks.Assignability.Relation

    @impl true
    def assignable?(_produced, _consumed), do: false
  end

  @doc "The `myapp.*` types ADR-0003's worked example names."
  @spec host_types() :: %{Block.type_name() => module()}
  def host_types do
    %{
      "myapp.enrich" => Enrich,
      "myapp.score" => Score,
      "myapp.notify" => Notify,
      "myapp.on_cancel" => OnCancel
    }
  end

  @doc """
  The core vocabulary plus the worked example's host types, on a palette
  pointed at `assignability` (default `Widens`). Pass `nil` for the palette
  ADR-0003 decision 6 step 3 describes: no widening relation at all.
  """
  @spec palette(module() | nil) :: Palette.t()
  def palette(assignability \\ Widens) do
    Palette.new(Map.merge(Palette.core_types(), host_types()), assignability: assignability)
  end
end
