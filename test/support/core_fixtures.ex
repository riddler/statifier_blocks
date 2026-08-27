defmodule StatifierBlocks.CoreFixtures do
  @moduledoc """
  Test-only support for the `core.*` vocabulary (ADR-0002 decision 10).

  Two things live here, and neither belongs in `lib/`:

    * the `myapp.*` block types the ADR-0001 worked example names, so that
      example can be checked against **real** core types with only its host
      types stubbed;
    * `check/2`, a palette-aware walk of a document reporting resolution,
      config, arity, undeclared-slot and kind findings. The shipped version
      of that walk is `sb-da9`'s.

  `check/2` is deliberately blunt and deliberately test-only. When `sb-da9`
  lands, the tests move over to it and this module loses everything but the
  `myapp.*` types.
  """

  alias StatifierBlocks.{Assignability, Block, Core, Document, Palette}

  defmodule Enrich do
    @moduledoc """
    `myapp.enrich`: the worked example's first step, at `type_version: 2`,
    so the document's stored version resolves without a migration.
    """

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 2

    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config),
      do: [
        %{key: "invoke_type", type: :string, label: "Invoke", required?: true, default: ""},
        %{key: "timeout", type: :duration, label: "Timeout", required?: false, default: "PT30S"}
      ]

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def io(_config), do: %{kinds: [:step], produces: "record"}

    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule Notify do
    @moduledoc "`myapp.notify`: a leaf step with no declared type expressions."

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config),
      do: [%{key: "invoke_type", type: :string, label: "Invoke", required?: true, default: ""}]

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule CrmPush do
    @moduledoc "`myapp.crm_push`: a leaf step consuming what `Enrich` produces."

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config),
      do: [%{key: "invoke_type", type: :string, label: "Invoke", required?: true, default: ""}]

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def io(_config), do: %{kinds: [:step], consumes: "record"}

    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule OnEvent do
    @moduledoc """
    `myapp.on_event`: a **host's** interrupt handler, tagged
    `:interrupt_handler` like `StatifierBlocks.Core.OnEvent` is.

    It exists to demonstrate ADR-0003 decision 3's deliberate consequence:
    a group admits it without knowing it exists, and it names no group it
    is allowed inside. The worked example uses this rather than the core
    type, which is why the core placement property needs its own test.
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
    def io(_config), do: %{kinds: [:interrupt_handler]}

    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  @doc "The `myapp.*` types the ADR-0001 worked example names."
  @spec host_types() :: %{Block.type_name() => module()}
  def host_types do
    %{
      "myapp.enrich" => Enrich,
      "myapp.notify" => Notify,
      "myapp.crm_push" => CrmPush,
      "myapp.on_event" => OnEvent
    }
  end

  @doc "The real core vocabulary plus the worked example's host types."
  @spec palette() :: Palette.t()
  def palette, do: Palette.new(Map.merge(Palette.core_types(), host_types()))

  @doc "Every module in the core vocabulary, sorted by `type_name`."
  @spec core_modules() :: [{Block.type_name(), module()}]
  def core_modules, do: Enum.sort(Palette.core_types())

  @doc """
  A config each core type accepts, for the conformance test's "every
  callback answers for a config this type says is valid" pass.
  """
  @spec valid_config(module()) :: Block.config()
  def valid_config(Core.Branch),
    do: %{"arms" => [%{"slot" => "arm_qualified", "cond" => "score > 80"}]}

  def valid_config(Core.Parallel), do: %{"lanes" => ["crm", "nurture"]}
  def valid_config(Core.Wait), do: %{"duration" => "PT48H"}
  def valid_config(Core.ResumableGroup), do: %{"history" => "deep"}
  def valid_config(Core.OnEvent), do: %{"event" => "order.cancelled", "outcome" => "abandon"}
  def valid_config(_module), do: %{}

  @doc """
  `validate_config/1` through a variable, so a test may pattern-match both
  arms of it. Called on a literal module, the compiler narrows the return
  of a type that only ever answers `:ok` and flags the `{:error, _}` arm as
  unreachable - which is a true statement about that one type and a false
  one about the contract every type has to satisfy.
  """
  @spec validate(module(), Block.config()) ::
          :ok | {:error, [{String.t(), String.t()}]}
  def validate(module, config), do: module.validate_config(config)

  @doc "`fixtures/0`'s bundle, or `:none` when the optional callback is absent."
  @spec fixtures(module()) :: {:ok, term()} | :none
  def fixtures(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :fixtures, 0),
      do: {:ok, module.fixtures()},
      else: :none
  end

  @doc """
  Walks `document` against `palette`, returning every finding in pre-order.
  An empty list means the document is valid against the real block types.

  Five kinds of finding, in the order each block is checked:
  `{:unresolvable, ...}`, `{:config, ...}`, `{:undeclared_slot, ...}`,
  `{:arity, ...}`, `{:kind_not_admitted, ...}`.
  """
  @spec check(Palette.t(), Document.t()) :: [tuple()]
  def check(%Palette{} = palette, %Document{root: root}), do: check_block(palette, root)

  defp check_block(palette, %Block{} = block) do
    case Palette.resolve(palette, block) do
      {:ok, module, resolved} -> check_resolved(palette, module, resolved)
      {:error, reason} -> [{:unresolvable, block.id, reason}]
    end
  end

  defp check_resolved(palette, module, %Block{} = block) do
    declared = module.slots(block.config)

    Enum.concat([
      config_findings(module, block),
      undeclared_findings(declared, block),
      arity_findings(declared, block),
      kind_findings(palette, module, declared, block),
      children_findings(palette, block)
    ])
  end

  defp config_findings(module, block) do
    case module.validate_config(block.config) do
      :ok -> []
      {:error, findings} -> Enum.map(findings, fn {key, msg} -> {:config, block.id, key, msg} end)
    end
  end

  defp undeclared_findings(declared, block) do
    names = MapSet.new(declared, fn {name, _arity, _label} -> name end)

    block.slots
    |> Map.keys()
    |> Enum.sort()
    |> Enum.reject(&MapSet.member?(names, &1))
    |> Enum.map(&{:undeclared_slot, block.id, &1})
  end

  defp arity_findings(declared, block) do
    for {name, arity, _label} <- declared,
        children = Map.get(block.slots, name, []),
        not satisfies?(arity, length(children)),
        do: {:arity, block.id, name, arity, length(children)}
  end

  defp satisfies?(:any, _count), do: true
  defp satisfies?(:at_least_one, count), do: count >= 1
  defp satisfies?(:exactly_one, count), do: count == 1
  defp satisfies?(:zero_or_one, count), do: count <= 1

  # Kind admission needs the child's module, so an unresolvable child is
  # skipped here rather than reported twice - its own pass already named it.
  defp kind_findings(palette, module, declared, block) do
    for {name, _arity, _label} <- declared,
        child <- Map.get(block.slots, name, []),
        {:ok, child_module} <- [Palette.fetch(palette, child.type)],
        not Assignability.admits?({module, block.config}, name, {child_module, child.config}),
        do: {:kind_not_admitted, child.id, block.id, name}
  end

  defp children_findings(palette, block) do
    block.slots
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.flat_map(fn {_name, children} ->
      Enum.flat_map(children, &check_block(palette, &1))
    end)
  end
end
