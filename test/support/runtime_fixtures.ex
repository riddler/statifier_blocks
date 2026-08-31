defmodule StatifierBlocks.RuntimeFixtures do
  @moduledoc """
  Test-only support for `StatifierBlocks.Runtime.Subchart` (sb-6edf):
  resolver host fixtures and the small documents its tests compile as
  children.

  Every resolver here `use`s the base and is deliberately pure - it reads
  a term (a `:persistent_term` slot or a fixed module return), never a
  process - which is what keeps `start/2` observably effect-free under
  `Statifier.Testing.HandlerCase` check 1.

  Session-level support (Phase 2, sb-6edf) lives at the bottom of this
  file: `parent_document/1` and `child_document/2` build the real block
  documents a session test compiles and runs, and `run/2` and
  `await_configuration/3` drive an actual `Statifier.Session` against
  them, with the child running as a real, separately-started session -
  the engine does not propagate a parent's `:invoke_handlers` down to a
  child it starts (`deps/statifier/lib/statifier/session.ex`'s
  `start_session/4` passes only `:invoked_by`, `:datamodel`, and the
  ADR-0050 observer opts), so a child document cannot itself invoke a
  *further* subchart in these tests without a second handler registration
  this suite never makes. `FixedOutcome` exists so a child can still
  report any outcome name a test wants - `core.subchart` is the only
  shipped type with a caller-named outcome, and reaching one for real
  needs exactly the handler this file is testing, which is circular for a
  leaf fixture. `FixedOutcome` finishes at its one declared outcome
  immediately, with no invoke at all.
  """

  import ExUnit.Assertions

  alias StatifierBlocks.{Block, Compiled, Compiler, Document, Palette}
  alias StatifierBlocks.Runtime.Subchart

  defmodule FixedOutcome do
    @moduledoc """
    Test-only `StatifierBlocks.BlockType`: a leaf that declares exactly one
    outcome - `config["outcome"]` - and enters its final the moment it is
    entered. No invoke, no runtime uncertainty: this is what lets a session
    test hold the child's reported outcome name fixed while varying only
    what the parent does with it.
    """

    @behaviour StatifierBlocks.BlockType

    alias StatifierBlocks.Compiler.Context
    alias StatifierBlocks.Core.Emit

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config), do: []

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def outcomes(%{"outcome" => name}) when is_binary(name), do: [{name, name}]
    def outcomes(_config), do: [{"done", "Done"}]

    @impl true
    def emit(%Block{config: config}, context) do
      name = Map.get(config, "outcome", "done")
      {:ok, final_id} = Context.outcome_id(context, name)
      {:ok, Emit.state(context.state_id, final_id, [Emit.final(final_id)])}
    end
  end

  @fixed_outcome_type "runtime_fixture.fixed_outcome"

  @session_palette Palette.new(
                     Map.merge(Palette.core_types(), %{@fixed_outcome_type => FixedOutcome})
                   )

  @doc "The palette session-level tests compile against: the core vocabulary plus `FixedOutcome`."
  @spec session_palette() :: Palette.t()
  def session_palette, do: @session_palette

  defmodule MapResolver do
    @moduledoc """
    Answers `resolve_chart/2` out of a map handed in through
    `:persistent_term`, keyed by document id - the case where a test wants
    to control the answer per document rather than have one fixed
    resolver's answer for the whole file.

    `palette/0` carries the core vocabulary plus `FixedOutcome` (below),
    which the Phase 1 unit tests never reference and which does not change
    how any `core.*` type resolves.
    """

    use StatifierBlocks.Runtime.Subchart

    @key __MODULE__

    @doc "Registers `answer` as what `resolve_chart/2` returns for `document_id`."
    @spec put(String.t(), term()) :: :ok
    def put(document_id, answer), do: :persistent_term.put({@key, document_id}, answer)

    @impl true
    def resolve_chart(document_id, _ctx), do: :persistent_term.get({@key, document_id}, :error)

    @impl true
    def palette, do: StatifierBlocks.RuntimeFixtures.session_palette()
  end

  defmodule CycleResolver do
    @moduledoc "Fixed answer: every document id is refused as a cross-document cycle."

    use StatifierBlocks.Runtime.Subchart

    @impl true
    def resolve_chart(_document_id, _ctx), do: {:cycle, ["bdoc_A", "bdoc_B"]}

    @impl true
    def palette, do: Palette.core()
  end

  defmodule UnknownResolver do
    @moduledoc """
    Fixed answer: every document id is unknown. Deterministic and pure, so
    this is also the handler the conformance pin runs against - the stock
    `build_invoke/1` fixture's `src: nil` short-circuits before this
    resolver would ever be called.
    """

    use StatifierBlocks.Runtime.Subchart

    @impl true
    def resolve_chart(_document_id, _ctx), do: :error

    @impl true
    def palette, do: Palette.core()
  end

  defmodule NonConformingResolver do
    @moduledoc "Fixed answer outside the resolver contract, for the raising-totality test."

    use StatifierBlocks.Runtime.Subchart

    @impl true
    def resolve_chart(_document_id, _ctx), do: :banana

    @impl true
    def palette, do: Palette.core()
  end

  @doc """
  A document that compiles cleanly for child use: a bare `core.sequence`
  root, one outcome (`done`), no host types needed.
  """
  @spec trivial_child(String.t()) :: Document.t()
  def trivial_child(id \\ "bdoc_CHILD") do
    root = Block.new("core.sequence", id: "blk_SEQ")
    Document.new(root, id: id)
  end

  @doc """
  A document whose root is a `core.subchart` naming its own document id -
  `StatifierBlocks.Compiler.SelfReference`'s own refusal, so this exercises
  a real compile finding rather than a synthetic one.
  """
  @spec self_referencing_child(String.t()) :: Document.t()
  def self_referencing_child(id \\ "bdoc_SELF") do
    root = Block.new("core.subchart", id: "blk_SELF", config: %{"chart" => id})
    Document.new(root, id: id)
  end

  @doc """
  A document whose root names an invoke type no session in these tests
  registers - compiles cleanly with a warning (ADR-0004 decision 8),
  never a `child_compile_findings` refusal.
  """
  @spec unregistered_invoke_child(String.t()) :: Document.t()
  def unregistered_invoke_child(id \\ "bdoc_UNREG") do
    root =
      Block.new("core.invoke", id: "blk_INV", config: %{"invoke_type" => "unregistered:type"})

    Document.new(root, id: id)
  end

  @doc """
  A `core.subchart` root naming `:chart`, declaring `:outcomes` (a list of
  names, in the order a subchart routes them), with `:on` occupying the
  `on_<outcome>` slot for each name listed there with a trivial
  `core.sequence` child - the same always-done container
  `StatifierBlocks.Core.SubchartTest` uses to exercise an occupied slot
  without a second event.
  """
  @spec parent_document(keyword()) :: Document.t()
  def parent_document(opts \\ []) do
    chart = Keyword.fetch!(opts, :chart)
    outcomes = Keyword.get(opts, :outcomes, [])
    on = Keyword.get(opts, :on, [])

    slots =
      for outcome <- on, into: %{} do
        {"on_" <> outcome, [Block.new("core.sequence", id: "blk_ON_" <> outcome)]}
      end

    root =
      Block.new("core.subchart",
        id: "blk_ROOT",
        config: %{"chart" => chart, "outcomes" => Enum.join(outcomes, "\n")},
        slots: slots
      )

    Document.new(root, id: "bdoc_PARENT")
  end

  @doc """
  A child document whose root is `FixedOutcome`, declaring exactly the one
  outcome named `outcome` and reaching it the moment it is entered - see
  this module's moduledoc for why a leaf fixture stands in for a nested
  `core.subchart` here.
  """
  @spec child_document(String.t(), String.t()) :: Document.t()
  def child_document(outcome, id \\ "bdoc_CHILD") do
    root = Block.new(@fixed_outcome_type, id: "blk_CHILD_ROOT", config: %{"outcome" => outcome})
    Document.new(root, id: id)
  end

  @doc """
  Compiles `document` against `resolver.palette()`, compiles the result
  through `Statifier.compile/1`, and starts a real `Statifier.Session`
  with `resolver`'s own handler registered
  (`StatifierBlocks.Runtime.Subchart.handlers/1`). Returns the session;
  the caller drives it with `await_configuration/3` and stops it with
  `Statifier.Session.stop/1` when done.
  """
  @spec run(Document.t(), module()) :: Statifier.Session.server()
  def run(document, resolver) do
    {:ok, %Compiled{scxml: scxml}} =
      Compiler.compile(document, resolver.palette(), known_invoke_types: [Subchart.invoke_type()])

    {:ok, machine} = Statifier.compile(scxml)

    {:ok, session} =
      Statifier.Session.start_link(machine, invoke_handlers: Subchart.handlers(resolver))

    session
  end

  @doc """
  The settle-poll every session test drives its assertion through: mirrors
  `Statifier.Testing.HandlerCase`'s own `await_configuration/3` - a short
  sleep, a bounded number of attempts, and a `flunk` naming the observed
  configuration on timeout - rather than a bare fixed-duration sleep used
  as the sole "is it done yet" mechanism. Returns the observed
  configuration once it matches `expected`.
  """
  @spec await_configuration(Statifier.Session.server(), MapSet.t(String.t()), non_neg_integer()) ::
          MapSet.t(String.t())
  def await_configuration(session, expected, attempts \\ 200) do
    observed = Statifier.Session.status(session).configuration

    cond do
      observed == expected ->
        observed

      attempts == 0 ->
        flunk(
          "expected the session to settle at #{inspect(Enum.sort(expected))}, " <>
            "but it settled at #{inspect(Enum.sort(observed))}"
        )

      true ->
        Process.sleep(5)
        await_configuration(session, expected, attempts - 1)
    end
  end
end
