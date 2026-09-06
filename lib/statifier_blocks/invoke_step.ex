defmodule StatifierBlocks.InvokeStep do
  @moduledoc """
  The leaf step that **names** one host invoke type, as a base a host block
  type declares itself out of (ADR-0007 decision 2).

  A host block type that calls the host and waits for it to answer is three
  facts - the invoke type it names, what its answer produces, and how the
  palette draws it - wrapped in the same hundred lines every time. This
  module is those hundred lines, written once: `use
  StatifierBlocks.InvokeStep, invoke_type: "myapp:authorize"` declares the
  behaviour and fills in every callback, and the type overrides only the
  rows where it differs.

      defmodule MyApp.Blocks.Authorize do
        use StatifierBlocks.InvokeStep,
          invoke_type: "myapp:authorize",
          produces: "myapp.authorization",
          fields: [
            %{
              key: "assign_to",
              type: {:path, %{}},
              label: "Write the decision to",
              required?: true,
              default: "cards.authorization"
            }
          ],
          palette: %{
            label: "Authorize card",
            group: "Card processing",
            description: "Authorizes the transaction against the card network.",
            icon: "credit-card",
            order: 0
          }
      end

  ## This module names invoke types; it never runs one

  The two-registry seam ADR-0002 decision 2 draws is the thing easiest to
  lose here, so it is worth saying in as many words: a block type names an
  invoke type, and a handler the host registers separately - per session,
  under st-ADR-0051 - is what runs it. Nothing in this module resolves a
  name to a handler, and `use`-ing it registers nothing. A step whose
  invoke type no handler answers is a deployment fact
  `StatifierBlocks.Compiler.InvokeTypes` reports at the one moment a caller
  holds both registries; it is not something this base can know.

  ## What it is not

  It is not a block type. It implements no `StatifierBlocks.BlockType`
  callback of its own, appears in no palette, and has no `type_name`: what
  it holds is the decisions a leaf step makes the same way every time,
  factored out so a host's twelve steps do not spell them twelve times.
  `StatifierBlocks.Core.Invoke` remains the shipped `core.invoke` type and
  is unaffected - see "The relationship to `core.invoke`" below.

  ## Every function here is pure

  ADR-0002 decision 4's purity rule reaches anything a callback calls and
  not only the callback itself, so it reaches this module in full: no
  process dictionary, no application configuration, no IO, no clock, no
  randomness. The injected callbacks are ordinary function definitions
  over their arguments and the compile-time declaration, which is what
  keeps a `use`-ing type as pure as a hand-written one.

  ## The relationship to `core.invoke`

  `StatifierBlocks.Core.Invoke` is `core.invoke`: a step with an `on_error`
  **slot**, so a failing call runs a subtree the author put there. This is
  that emission with the slot taken out. A leaf step has no children, so
  its failure path is an `error` outcome a parent may wire rather than a
  subtree the block runs, and both outcome finals are emitted
  unconditionally rather than only when a slot is occupied.

  The two share the `invoke_type` grammar (through
  `StatifierBlocks.Core.Config`), the two event names, and the rule that
  `assign_to` is written on the success transition rather than in a
  `<finalize>` - the answer is only an answer when the call succeeded, and
  `<finalize>` runs for every event the invocation delivers.

  ## What `use` injects

  | Callback | Injected default |
  |---|---|
  | `current_version/0` | `1` |
  | `slots/1` | `[]` - a leaf step has no children |
  | `config_schema/1` | `label`, then `invoke_type`, then the `:fields` given |
  | `validate_config/1` | the `invoke_type` and `assign_to` checks |
  | `io/1` | `%{kinds: [:step]}`, plus `produces` when `:produces` is given |
  | `outcomes/1` | `[{"done", "Done"}, {"error", "Error"}]` |
  | `palette_entry/0` | the `:palette` given, over this module's defaults |
  | `emit/2` | `emit/4` against the declared invoke type |
  | `migrate_config/2` | `StatifierBlocks.BlockType`'s refusing default |

  Every one is `defoverridable`. A type with extra `<param>` children calls
  `emit/4` itself; one with a tighter rule adds to `validate_config/1`; one
  that has changed its config shape overrides `current_version/0` and
  `migrate_config/2` the way any block type does.
  """

  alias StatifierBlocks.{Block, BlockType, Emission}
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.{AssignLocation, Config, Emit}

  @done_event "done.invoke"
  @error_event "error.communication.invoke"

  @invoke_type_message ~s(must look like "namespace:name", such as "myapp:authorize")

  # The wording `StatifierBlocks.Core.Invoke` uses for the same key, on
  # purpose: an author who meets `assign_to` on a core block and on a host
  # step is meeting one field, and two spellings of its complaint would
  # suggest otherwise. Both widened to the datamodel-path rule on
  # `sb-r313`, for ADR-0011 decision 13's reason - the two emit the same
  # `<assign>` element into the same datamodel.
  @assign_to_message "must be a datamodel path, like cards.authorization"

  # `label`, `group`, `icon` and `accent_token` are deliberately not among
  # the defaults. Which heading a step files under is the host domain's
  # fact, and a shared default would quietly file a signup step under card
  # processing; an invented label reads worse than the type name the editor
  # already falls back to.
  @palette_defaults %{layout: :stack, keywords: []}

  @doc """
  Declares the behaviour and injects the leaf-step defaults (ADR-0007
  decision 2). Options:

    * `:invoke_type` - **required**, the invoke type this step names when
      its config does not say otherwise. A literal in the
      `namespace:name` grammar is checked at compile time.
    * `:produces` - what a successful call produces to the next sibling
      (ADR-0003). Absent leaves the step unconstrained beyond being one.
    * `:fields` - extra field declarations, appended after `label` and
      `invoke_type` in the order given.
    * `:palette` - palette-entry keys, merged over this module's defaults.
  """
  defmacro __using__(opts) do
    invoke_type = checked_declaration(Keyword.fetch!(opts, :invoke_type))
    produces = Keyword.get(opts, :produces)
    fields = Keyword.get(opts, :fields, [])
    palette = Keyword.get(opts, :palette, Macro.escape(%{}))

    quote do
      use StatifierBlocks.BlockType

      @doc """
      The invoke type this step names when its config does not say
      otherwise.
      """
      @spec invoke_type() :: String.t()
      def invoke_type, do: unquote(invoke_type)

      @impl StatifierBlocks.BlockType
      def config_schema(_config),
        do: StatifierBlocks.InvokeStep.config_schema(unquote(invoke_type), unquote(fields))

      @impl StatifierBlocks.BlockType
      def validate_config(config) do
        []
        |> StatifierBlocks.InvokeStep.check_invoke_type(config)
        |> StatifierBlocks.InvokeStep.check_assign_to(config)
        |> StatifierBlocks.InvokeStep.verdict()
      end

      @impl StatifierBlocks.BlockType
      def io(_config), do: StatifierBlocks.InvokeStep.io(unquote(produces))

      @impl StatifierBlocks.BlockType
      def outcomes(_config), do: StatifierBlocks.InvokeStep.outcomes()

      @impl StatifierBlocks.BlockType
      def palette_entry, do: StatifierBlocks.InvokeStep.palette_entry(unquote(palette))

      @impl StatifierBlocks.BlockType
      def emit(block, context),
        do: StatifierBlocks.InvokeStep.emit(block, context, unquote(invoke_type))

      defoverridable invoke_type: 0,
                     config_schema: 1,
                     validate_config: 1,
                     io: 1,
                     outcomes: 1,
                     palette_entry: 0,
                     emit: 2
    end
  end

  # A declaration is checked where it is written, when it is written down
  # as a literal: a typo'd invoke type is a compile error rather than a
  # finding every author of every document carrying the step later meets.
  # A declaration computed from a module attribute is not a literal at
  # expansion time, so it passes through here and is checked by
  # `validate_config/1` like any stored value.
  @spec checked_declaration(term()) :: term()
  defp checked_declaration(value) when is_binary(value) do
    if Config.invoke_type?(value) do
      value
    else
      raise ArgumentError,
            ~s(invoke_type: #{inspect(value)} #{@invoke_type_message})
    end
  end

  defp checked_declaration(value), do: value

  @doc """
  The two ways a call can finish, in the order they compile in.

  Declaration order is read by ADR-0004 decision 6's byte determinism, so
  this list is never sorted.
  """
  @spec outcomes() :: [BlockType.outcome_decl()]
  def outcomes, do: [{"done", "Done"}, {"error", "Error"}]

  @doc """
  The optional `label` field: the name this particular step goes by on the
  card, above the block type's own label.

  Declaring it is the whole of what a host does to opt in - this package
  titles a card from a declared `:string` field keyed `"label"` and demotes
  the palette label to the subtitle (`StatifierBlocks.ViewModel.title/1`
  and `subtitle/1`).
  """
  @spec label_field() :: BlockType.field_decl()
  def label_field do
    %{key: "label", type: :string, label: "Label", required?: false, default: ""}
  end

  @doc """
  The `invoke_type` field, declared with the step's own invoke type as its
  default.

  It is `required?: true` with a default for `core.on_event`'s reason: the
  field is one an author must answer, and the answer is prefilled with the
  only one that is usually right.
  """
  @spec invoke_type_field(String.t()) :: BlockType.field_decl()
  def invoke_type_field(default) when is_binary(default) do
    %{key: "invoke_type", type: :string, label: "Invoke type", required?: true, default: default}
  end

  @doc """
  `label` first, then `invoke_type`, then whatever else the step declares.

  `label` leads because it is the field an author reaches for first - it is
  what the card says - and the inspector renders declaration order.
  """
  @spec config_schema(String.t(), [BlockType.field_decl()]) :: [BlockType.field_decl()]
  def config_schema(default, extra \\ []) when is_binary(default) and is_list(extra) do
    [label_field(), invoke_type_field(default) | extra]
  end

  @doc """
  The invoke type this config names: what it stored, or the step's own
  declared default when it stored nothing.

  A step whose config omits the key is naming its own invoke type, which is
  what the declared default says. The alternative is a document that cannot
  say "the usual handler" without repeating it, and the field's default is
  the one place the usual handler is written down.
  """
  @spec invoke_type(Block.config(), String.t()) :: String.t()
  def invoke_type(config, default) when is_map(config) and is_binary(default) do
    case Map.get(config, "invoke_type") do
      nil -> default
      stored -> stored
    end
  end

  @doc """
  Checks a stored `invoke_type`, and passes an absent one - see
  `invoke_type/2` for why absence is an answer rather than a gap.
  """
  @spec check_invoke_type([BlockType.finding()], Block.config()) :: [BlockType.finding()]
  def check_invoke_type(findings, config) when is_list(findings) and is_map(config) do
    case Map.get(config, "invoke_type") do
      nil ->
        findings

      stored ->
        refute_unless(findings, Config.invoke_type?(stored), "invoke_type", @invoke_type_message)
    end
  end

  @doc """
  Checks an `assign_to` the step declared as optional: a blank one is a
  step that throws its answer away, which is an answer rather than a gap.

  What it accepts is `core.assign`'s and `core.invoke`'s datamodel path -
  any non-empty value with no whitespace, dotted or not (ADR-0011 decision
  13, widened here on `sb-r313`). A step that requires the key instead -
  because a decision nobody keeps is not a decision - declares the field
  `required?: true` and adds a refusal of the blank of its own; this check
  stays blank-permissive either way, so the two compose rather than
  disagreeing about the same value. `check_identifier/4` is the shipped
  shape for a step field whose rule really is a bare identifier, which
  `assign_to` no longer is.
  """
  @spec check_assign_to([BlockType.finding()], Block.config()) :: [BlockType.finding()]
  def check_assign_to(findings, config) when is_list(findings) and is_map(config) do
    AssignLocation.check(
      findings,
      config,
      "assign_to",
      &Config.datamodel_path?/1,
      @assign_to_message
    )
  end

  @doc """
  Checks that `key` holds a bare lowercase identifier, anchoring `message`
  on that key when it does not.
  """
  @spec check_identifier([BlockType.finding()], Block.config(), String.t(), String.t()) ::
          [BlockType.finding()]
  def check_identifier(findings, config, key, message)
      when is_list(findings) and is_map(config) and is_binary(key) and is_binary(message) do
    refute_unless(findings, Config.identifier?(Map.get(config, key)), key, message)
  end

  @spec refute_unless([BlockType.finding()], boolean(), String.t(), String.t()) ::
          [BlockType.finding()]
  defp refute_unless(findings, true, _key, _message), do: findings
  defp refute_unless(findings, false, key, message), do: [{key, message} | findings]

  @doc """
  Turns an accumulated finding list into `validate_config/1`'s return,
  restoring the order the checks ran in.
  """
  @spec verdict([BlockType.finding()]) :: :ok | {:error, [BlockType.finding()]}
  def verdict(findings), do: Config.verdict(findings)

  @doc """
  A step constrains nothing beyond being a step unless it declares what a
  successful call produces (ADR-0003).
  """
  @spec io(StatifierBlocks.Assignability.produces() | nil) :: StatifierBlocks.Assignability.io()
  def io(nil), do: %{kinds: [:step]}
  def io(produces), do: %{kinds: [:step], produces: produces}

  @doc """
  A palette entry with this base's shared presentation defaults filled in.

  `attrs` wins over every default, so a step that says something is
  believed.
  """
  @spec palette_entry(BlockType.palette_entry()) :: BlockType.palette_entry()
  def palette_entry(attrs) when is_map(attrs), do: Map.merge(@palette_defaults, attrs)

  @doc """
  A `<param>` carrying a literal, for a value the block type stores rather
  than reads out of the datamodel.

  `config_key` is stamped on the emission as the provenance of the value,
  so a finding inside it points at the author's field and not at this
  module.
  """
  @spec literal_param(String.t(), String.t(), String.t()) :: Emission.t()
  def literal_param(name, value, config_key)
      when is_binary(name) and is_binary(value) and is_binary(config_key) do
    "param"
    |> Emission.element([{"expr", "'" <> value <> "'"}, {"name", name}])
    |> Emission.from_config(config_key)
  end

  @doc """
  A compound state that calls the host and finishes at the `<final>` of
  whichever outcome the call reached.

      <state id="s_blk_RCP" initial="s_blk_RCP__running">
        <state id="s_blk_RCP__running">
          <invoke type="myapp:receipt"/>
          <transition event="done.invoke" target="s_blk_RCP__o_done"/>
          <transition event="error.communication.invoke" target="s_blk_RCP__o_error"/>
        </state>
        <final id="s_blk_RCP__o_done">
          <onentry><raise event="done.outcome.s_blk_RCP.done"/></onentry>
        </final>
        <final id="s_blk_RCP__o_error">
          <onentry><raise event="done.outcome.s_blk_RCP.error"/></onentry>
        </final>
      </state>

  Both transitions match by SCXML's descriptor prefix rule and neither
  names an invocation id, which is safe for the reason `core.invoke`
  gives: they sit on the inner state, active only while this block's own
  call is outstanding, so no other invocation's completion can be selected
  by them.

  The `type` attribute is stamped as coming from `invoke_type` only when
  the author actually wrote one. A step running on the declared default
  has no config key for a finding to point at, and attributing the
  attribute to a key the document does not carry would send an author
  looking for text they never typed.

  `params` are the `<param>` children the calling type wants on the
  `<invoke>`, in the order it wants them - `literal_param/3` builds one. A
  step with nothing to send omits the argument.

  A config carrying `assign_to` puts an `<assign expr="_event.data">` on
  the success transition, writing the handler's answer to that location. A
  step that stores nothing there emits no `<assign>`, and an `assign_to`
  that is not a bare identifier is a finding on the author's key rather
  than an attribute nobody can read.
  """
  @spec emit(Block.t(), Context.t(), String.t(), [Emission.t()]) ::
          {:ok, Emission.t()} | {:error, BlockType.emit_error()}
  def emit(block, context, default, params \\ [])

  def emit(%Block{config: config}, %Context{} = context, default, params)
      when is_binary(default) and is_list(params) do
    with {:ok, running} <- Context.role_id(context, "running"),
         {:ok, done_final} <- Context.outcome_id(context, "done"),
         {:ok, error_final} <- Context.outcome_id(context, "error"),
         {:ok, invoke_type} <- checked_invoke_type(config, default),
         {:ok, result} <- assign(Map.get(config, "assign_to")) do
      inner =
        Emit.state(running, nil, [
          call(config, invoke_type, params),
          Emit.transition([event: @done_event, target: done_final], result),
          Emit.transition(event: @error_event, target: error_final)
        ])

      {:ok,
       Emit.state(context.state_id, running, [
         inner,
         Emit.final(done_final),
         Emit.final(error_final)
       ])}
    end
  end

  @spec assign(term()) :: {:ok, [Emission.t()]} | {:error, [BlockType.finding()]}
  defp assign(location) do
    case AssignLocation.location(
           location,
           "assign_to",
           &Config.datamodel_path?/1,
           @assign_to_message
         ) do
      {:ok, nil} ->
        {:ok, []}

      {:ok, path} ->
        {:ok,
         [
           "assign"
           |> Emission.element([{"expr", "_event.data"}, {"location", path}])
           |> Emission.attribute_from_config("location", "assign_to")
         ]}

      {:error, findings} ->
        {:error, findings}
    end
  end

  @spec call(Block.config(), String.t(), [Emission.t()]) :: Emission.t()
  defp call(config, invoke_type, params) do
    element = Emission.element("invoke", [{"type", invoke_type}], params)

    case Map.get(config, "invoke_type") do
      nil -> element
      _authored -> Emission.attribute_from_config(element, "type", "invoke_type")
    end
  end

  @spec checked_invoke_type(Block.config(), String.t()) ::
          {:ok, String.t()} | {:error, [BlockType.finding()]}
  defp checked_invoke_type(config, default) do
    invoke_type = invoke_type(config, default)

    if Config.invoke_type?(invoke_type) do
      {:ok, invoke_type}
    else
      {:error, [{"invoke_type", @invoke_type_message}]}
    end
  end
end
