defmodule StatifierBlocks.CoreFixtures do
  @moduledoc """
  Test-only support for the `core.*` vocabulary (ADR-0002 decision 10).

  Two things live here, and neither belongs in `lib/`:

    * the `myapp.*` block types the family's two worked examples name - the
      ADR-0001 credit-card authorization flow and the signup wizard with
      A/B testing (the umbrella's `docs/terminology-firewall.md`, "Example
      domains") - so each example can be checked against **real** core
      types with only its host types stubbed;
    * `check/2`, a palette-aware walk of a document reporting resolution,
      config, arity, undeclared-slot and kind findings. The shipped version
      of that walk is `sb-da9`'s.

  `check/2` is deliberately blunt and deliberately test-only. When `sb-da9`
  lands, the tests move over to it and this module loses everything but the
  `myapp.*` types.
  """

  alias StatifierBlocks.{Assignability, Block, Core, Document, Emission, Palette}
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.Emit

  defmodule Authorize do
    @moduledoc """
    `myapp.authorize`: the worked example's first step, at
    `type_version: 2`, so the document's stored version resolves without a
    migration.

    `StatifierBlocks.AssignabilityFixtures` carries a second, thinner stub
    under the same type name for ADR-0003's worked example. The two never
    share a palette, and this one sits at version 2 on purpose - that is
    the property the ADR-0001 example is here to demonstrate.
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
        %{key: "timeout", type: :duration, label: "Timeout", required?: false, default: "30s"}
      ]

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def io(_config), do: %{kinds: [:step], produces: "myapp.credit_card_txn"}

    @impl true
    def emit(%Block{} = block, context),
      do: StatifierBlocks.CoreFixtures.invoke_leaf(block, context)
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
    def emit(%Block{} = block, context),
      do: StatifierBlocks.CoreFixtures.invoke_leaf(block, context)
  end

  defmodule Capture do
    @moduledoc "`myapp.capture`: a leaf step consuming what `Authorize` produces."

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
    def io(_config), do: %{kinds: [:step], consumes: "myapp.credit_card_txn"}

    @impl true
    def emit(%Block{} = block, context),
      do: StatifierBlocks.CoreFixtures.invoke_leaf(block, context)
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
    def emit(%Block{} = block, context),
      do: StatifierBlocks.CoreFixtures.handler_leaf(block, context)
  end

  defmodule AssignVariant do
    @moduledoc """
    `myapp.assign_variant`: the signup wizard's first step, which puts the
    visitor in an A/B bucket and hands the bucket downstream.
    """

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
    def io(_config), do: %{kinds: [:step], produces: "myapp.variant"}

    @impl true
    def emit(%Block{} = block, context),
      do: StatifierBlocks.CoreFixtures.invoke_leaf(block, context)
  end

  defmodule SignupStep do
    @moduledoc "`myapp.signup_step`: one screen of the wizard, in one variant."

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config),
      do: [
        %{key: "invoke_type", type: :string, label: "Invoke", required?: true, default: ""},
        %{key: "step", type: :string, label: "Step", required?: true, default: ""}
      ]

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def io(_config), do: %{kinds: [:step]}

    @impl true
    def emit(%Block{} = block, context),
      do: StatifierBlocks.CoreFixtures.invoke_leaf(block, context)
  end

  defmodule Conversion do
    @moduledoc "`myapp.conversion`: records the conversion event against the bucket."

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config),
      do: [
        %{key: "invoke_type", type: :string, label: "Invoke", required?: true, default: ""},
        %{key: "event", type: :string, label: "Event", required?: true, default: ""}
      ]

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def io(_config), do: %{kinds: [:step], consumes: "myapp.variant"}

    @impl true
    def emit(%Block{} = block, context),
      do: StatifierBlocks.CoreFixtures.invoke_leaf(block, context)
  end

  @doc """
  The emission a host's invoking leaf produces: one compound state that
  starts an `<invoke>` on entry and finishes when the invocation reports
  back, either way.

  It is here rather than in `lib/` because the invoking leaf is exactly the
  block type a host writes and this package does not ship - `core.*` is
  structure, never domain (ADR-0002 decision 10). What it demonstrates is
  the convention `StatifierBlocks.Core.Emit` documents: one compound state,
  one `<final>`, completion signalled by `done.state`.
  """
  @spec invoke_leaf(Block.t(), Context.t()) :: {:ok, Emission.t()}
  def invoke_leaf(%Block{config: config}, %Context{} = context) do
    done = Context.done_id(context)
    {:ok, running} = Context.role_id(context, "running")
    {:ok, invocation} = Context.role_id(context, "invocation")

    invoke =
      Emission.element("invoke", [
        {"id", invocation},
        {"type", Map.get(config, "invoke_type", "")}
      ])

    state =
      Emit.state(running, nil, [
        invoke,
        Emit.transition(event: "done.invoke." <> invocation, target: done),
        Emit.transition(event: "error.execution", target: done)
      ])

    {:ok, Emit.state(context.state_id, running, [state, Emit.final(done)])}
  end

  @doc """
  The emission a host's interrupt handler produces: the same shape
  `StatifierBlocks.Core.OnEvent` uses, raising one of the two protocol
  events `StatifierBlocks.Core.Emit.interrupt_events/0` names.

  Its presence is the point of the `myapp.on_event` fixture: a host handler
  joins the protocol by raising the same events, and the group admits it
  through kind tags without either type naming the other.
  """
  @spec handler_leaf(Block.t(), Context.t()) :: {:ok, Emission.t()}
  def handler_leaf(%Block{config: config}, %Context{} = context) do
    done = Context.done_id(context)
    {:ok, armed} = Context.role_id(context, "armed")

    outcome =
      case Map.get(config, "outcome") do
        "resume" -> Emit.interrupt_events().resume
        _abandon -> Emit.interrupt_events().abandon
      end

    watcher =
      Emit.state(armed, nil, [
        Emit.transition([event: Map.get(config, "event", "myapp.interrupt"), target: done], [
          Emission.element("raise", [{"event", outcome}])
        ])
      ])

    {:ok, Emit.state(context.state_id, armed, [watcher, Emit.final(done)])}
  end

  @doc "The `myapp.*` types the two worked examples name."
  @spec host_types() :: %{Block.type_name() => module()}
  def host_types do
    %{
      "myapp.authorize" => Authorize,
      "myapp.notify" => Notify,
      "myapp.capture" => Capture,
      "myapp.on_event" => OnEvent,
      "myapp.assign_variant" => AssignVariant,
      "myapp.signup_step" => SignupStep,
      "myapp.conversion" => Conversion
    }
  end

  @doc "The real core vocabulary plus both worked examples' host types."
  @spec palette() :: Palette.t()
  def palette, do: Palette.new(Map.merge(Palette.core_types(), host_types()))

  @doc "Every module in the core vocabulary, sorted by `type_name`."
  @spec core_modules() :: [{Block.type_name(), module()}]
  def core_modules, do: Enum.sort(Palette.core_types())

  @doc """
  Durations in the spelling a `:duration` field no longer reads, assembled
  from their parts rather than written out anywhere.

  `sb-4r1p` retired that spelling, and ADR-0005 decision 9's 2026-09-05
  amendment (clause 9d) keeps it out of every message, hint, example and
  doc line this package ships. The refusals still have to be pinned
  against real values of it - a refusal asserted only against `soon`
  proves nothing about the form that was retired - so the values are
  assembled here from a designator, a date half and a time half. Nothing
  in `lib/` or `test/` then carries one as a literal, which is what keeps
  a repo-wide sweep for it clean.

      iex> StatifierBlocks.CoreFixtures.retired_durations() |> Enum.all?(&(StatifierBlocks.Core.Duration.parse(&1) == :error))
      true

  """
  @spec retired_durations() :: [String.t()]
  def retired_durations do
    for {date, time} <- [
          {"", "30S"},
          {"", "48H"},
          {"", "1H30M"},
          {"", "0S"},
          {"1D", ""},
          {"2W", ""},
          {"1Y", ""},
          {"1D", "6H"},
          {"1Y2M3D", "4H5M6S"}
        ] do
      "P" <> date <> if time == "", do: "", else: "T" <> time
    end
  end

  @doc """
  A config each core type accepts, for the conformance test's "every
  callback answers for a config this type says is valid" pass.
  """
  @spec valid_config(module()) :: Block.config()
  def valid_config(Core.Branch),
    do: %{"arms" => [%{"slot" => "arm_approved", "cond" => "budget_remaining > amount"}]}

  def valid_config(Core.Parallel), do: %{"lanes" => ["capture", "receipt"]}
  def valid_config(Core.Wait), do: %{"duration" => "48h"}
  def valid_config(Core.Await), do: %{"event" => "order.approved", "timeout" => "48h"}
  def valid_config(Core.ResumableGroup), do: %{"history" => "deep"}
  def valid_config(Core.OnEvent), do: %{"event" => "order.cancelled", "outcome" => "abandon"}
  def valid_config(Core.Raise), do: %{"event" => "signup.abandoned"}
  def valid_config(Core.Assign), do: %{"path" => "review.parked", "value" => "false"}
  def valid_config(Core.Send), do: %{"event" => "signup.abandoned", "delay" => "2h"}

  def valid_config(Core.Subchart),
    do: %{
      "chart" => "bdoc_01JWIZ",
      "outcomes" => "done\nabandoned",
      "assign_to" => "eligibility",
      "params" => "email=signup.email"
    }

  def valid_config(Core.Foreach),
    do: %{"items" => "signup.invitees", "item_as" => "invitee", "index_as" => "position"}

  def valid_config(Core.Map),
    do: %{
      "items" => "signup.invitees",
      "chart" => "bdoc_01JWIZ",
      "collect" => "answers",
      "on" => "all"
    }

  def valid_config(Core.Invoke),
    do: %{
      "invoke_type" => "myapp:authorize",
      "assign_to" => "authorization",
      "params" => "amount=order.amount"
    }

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
