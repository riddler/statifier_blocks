defmodule StatifierBlocks.RuntimeFixtures do
  @moduledoc """
  Test-only support for `StatifierBlocks.Runtime.Subchart` (sb-6edf):
  resolver host fixtures and the small documents its tests compile as
  children.

  Every resolver here `use`s the base and is deliberately pure - it reads
  a term (a `:persistent_term` slot or a fixed module return), never a
  process - which is what keeps `start/2` observably effect-free under
  `Statifier.Testing.HandlerCase` check 1.
  """

  alias StatifierBlocks.{Block, Document, Palette}

  defmodule MapResolver do
    @moduledoc """
    Answers `resolve_chart/2` out of a map handed in through
    `:persistent_term`, keyed by document id - the case where a test wants
    to control the answer per document rather than have one fixed
    resolver's answer for the whole file.
    """

    use StatifierBlocks.Runtime.Subchart

    @key __MODULE__

    @doc "Registers `answer` as what `resolve_chart/2` returns for `document_id`."
    @spec put(String.t(), term()) :: :ok
    def put(document_id, answer), do: :persistent_term.put({@key, document_id}, answer)

    @impl true
    def resolve_chart(document_id, _ctx), do: :persistent_term.get({@key, document_id}, :error)

    @impl true
    def palette, do: Palette.core()
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
end
