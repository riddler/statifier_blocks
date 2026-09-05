if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.Field do
    @moduledoc """
    One config field, dispatching on the closed field-type set (ADR-0005
    decision 9, ADR-0002 decision 7).

    The set is closed precisely so this renderer can be total, and the
    mapping is the record's, unchanged:

    | Field type | Rendering |
    |---|---|
    | `:string` | single-line text input |
    | `:integer` | number input, step 1 |
    | `:boolean` | checkbox |
    | `{:select, choices}` | select, choices in declared order |
    | `:expression` | statifier-ui's expression editor when that package is present, else a single-line source input |
    | `:duration` | one text control; predicator duration strings primary, with on-screen examples |
    | `{:list, t}` | repeatable rows of `t`'s renderer, with add and remove |

    `:duration`'s row is decision 9 as amended 2026-08-29. One text control,
    not a value/unit pair and not a pair with an escape hatch beside it: the
    compound control could not spell `PT1H30M` at all, and a control plus an
    escape hatch is two ways to say one thing with a rule about which wins.
    Predicator duration strings are primary with the examples on screen,
    ISO-8601 stays accepted, and an empty field omits the key.

    What the typed text means is `StatifierBlocks.DurationInput`'s, not this
    module's - it is a function of the text alone, so it is asserted with
    LiveView absent. Where an omitted key is omitted is
    `StatifierBlocks.Editor.ConfigForm`'s, which owns where a decoded value
    is written. This module renders the control and shows the refusal.

    The refusal shown beneath a `:duration` is the **inline** check, and it
    is earlier than decision 9's gate rather than a second one: the gate
    still decides what reaches the document, and the inline sentence tells
    the author which spelling they are failing while they are still typing
    it. Nothing here is stored - the stored form is the author's string
    verbatim, byte for byte.

    A required field is marked with the **word**, not with an asterisk
    (parity item 1.9). An asterisk is a convention that has to be learned
    from a legend the editor does not have, it is read aloud as "star", and
    it is one character wide next to a label it is easy to miss. `Required`
    says the same thing to a reader and to a screen reader, and it is the
    field record's own `required?` that decides - never a key name and never
    a type.

    Two control types carry a **placeholder**, and neither is chosen by key
    or by type name: an `:expression` says what kind of thing belongs in it,
    and a `:duration` shows the spelling it stores. A bare `:string` says
    nothing, because there is nothing a type as wide as "string" can suggest -
    which is the rule, and it is what makes the two that do say something the
    editor's own presentation rather than a special case.

    Whether a block type may declare a `placeholder` on its own fields is a
    question this module deliberately does not answer: ADR-0002 decision 7
    closes the field TYPE set, not the keys of a field record, so admitting
    one is a widening of that record and belongs to whoever amends it.

    `:expression` renders through the `expression_component` seam. Predicator
    source is statifier-ui's subject (sui-bob, sui-ADR-0006), and decision 9
    records a richer affordance as a deferral, so this component accepts an
    override for exactly that seam - and, since sb-m6e0, fills the seam
    itself when the package the deferral names is on the load path.

    ## Which control an `:expression` gets

    Three answers, in this order, and the order is the whole rule:

      1. an `expression_component` the host passed - the host asked for its
         own control and gets it, whatever else is available;
      2. `StatifierUI.Live.ExpressionInput`, when `statifier_ui` resolves -
         value picklists over the subset predicator can round-trip, a text
         input over everything else, and the author's own source string
         either way;
      3. the plain source input this package has always rendered, with the
         `<datalist>` of declared paths described below.

    `statifier_ui` is an **optional** dependency, resolved the way
    `phoenix_live_view` is: absent, clause 3 is what an `:expression`
    renders, nothing raises, and nothing warns at compile time. The
    resolution is a runtime `Code.ensure_loaded?/1` against a module read
    from `:statifier_blocks, :expression_component_module`, which is the
    same indirection statifier-ui itself uses for `Predicator.Simple` - it
    is what makes clause 3 assertable on a machine where clause 2 resolves.

    Two properties of clause 2 are load-bearing and neither is this module's
    to weaken. The component **never refuses a source string and never
    rewrites one**: source it cannot draw as rows is drawn as text. And
    every control it draws writes a *complete expression source string* into
    the same named input the text mode edits, so the document still stores
    the author's text and this package still holds no structured expression
    model of its own.

    ## `value_candidates`

    The values a host offers per datamodel path, `%{path => [candidate]}`,
    where a candidate is `%{label: , value: }` or a bare string. It reaches
    the `expression_component` beside `candidates` and is read by whatever
    is behind the seam; nothing in this package interprets it, because only
    a host knows which of its own paths have a value set at all. A path with
    no entry gets a free-text value control, which is the same "suggests,
    never constrains" posture the path `<datalist>` takes.

    ## The fixture hint (sb-e30x)

    `fixture_hint` is `StatifierBlocks.Shell.fixture_hint/3`'s answer for
    this field, and it is drawn as a sibling element after the control: the
    exemplar the selected block's first fixture row in declaration order
    binds to the path the source names, with every distinct value that path
    takes across the block's rows on the element's `title`. ADR-0005's
    2026-09-05 note records it, and three of its properties are the reason
    it is here rather than anywhere else.

      * **It is a hint, not a `placeholder`.** The rule above - exactly two
        control types carry a placeholder, and neither is chosen by key or
        by type name - is untouched. The hint is a third element with its
        own text, not a third placeholder source.
      * **It is never an option.** Nothing about it reaches a picker, it is
        not merged with `one_of` or with a host's `value_candidates`, and it
        cannot be selected. A fixture value is an *example*, and an example
        promoted into a dropdown becomes a declaration the author never made.
      * **It adds no assign to the rendering package.** The hint is not
        passed through the `expression_component` seam and that component
        gains no key; this package draws it out of the `fixtures` the editor
        already holds. Widening another package's API to draw this package's
        own decoration is what the seam's shape exists to prevent.

    `nil` - a block with no fixture rows, or no fixtures source at all -
    draws no element, so such a block renders exactly as it did before. That
    is silence rather than an empty affordance, which is the same thing the
    empty `<datalist>` cases below do.

    ## The `:expression` path suggestions (sb-0vt)

    That plain input gains a `<datalist>` of the declared datamodel paths
    when `path_candidates` is non-empty, on exactly the `invoke_type` terms
    below: it suggests and does not constrain, free text stays valid, an
    undeclared path stays the `:info` advisory `StatifierBlocks.Datamodel`
    already produced rather than becoming a refusal, and an empty list
    renders the input the package has always rendered. The same list reaches
    the `expression_component` override as `:candidates`, so a host that
    fills the seam is handed the paths rather than re-deriving them.

    **This is the data, not the feature.** Decision 9's deferral of rich
    expression editing to statifier-ui is untouched, and one property of a
    `<datalist>` is why that matters rather than being a formality: the
    browser matches options against the input's **whole value**, so the list
    is live while the author is typing the leading path and goes quiet the
    moment the expression grows an operator. That is genuinely useful for
    the bare-path condition and for the first token of any other, and it is
    not completion. Mid-expression completion needs to know where the caret
    is inside the source, which needs either a hook this package may not add
    (decision 7's two-hook limit) or the richer component decision 9 defers -
    and it needs predicator's operator vocabulary, which px-15q tracks.

    Ordering follows the same reasoning as the clause order below: the
    override wins over the datalist, because a host that supplied a
    component asked for its own control and getting the package's suggestion
    markup stapled beside it would be the package overriding the override.

    This module is a renderer, not a gate. Nothing here decides whether a
    value is acceptable: `validate_config/1` does, through
    `StatifierBlocks.Edit.check_config/3`, which is why an unparseable
    integer reaches the draft config as the string the author typed rather
    than being silently coerced or dropped.

    ## The `invoke_type` suggestion list

    `invoke_types` is the one control this module chooses **by key**, and
    the exception is deliberate rather than an oversight of the rule above.
    A host that knows which invoke types it has registered can pass them as
    an editor assign, and an `invoke_type` field then renders as a text
    input bound to a `<datalist>` of those strings. With the assign absent
    or empty the same field renders as the plain text input it has always
    been, so the suggestion list is additive and a host that supplies
    nothing loses nothing.

    Three properties make this a suggestion rather than a vocabulary, and
    each of them is ADR-0004 decision 8 rather than a choice made here:

      * **Free text stays valid.** A `<datalist>` suggests; it does not
        constrain, which is exactly why it is the control used and a
        `{:select, choices}` is not. An author can type a type that is not
        on the list and the editor stores it verbatim.
      * **An unknown type stays a lint.** The two-registry check is the
        compiler's opt-in `:known_invoke_types` lint, and it reports; it
        never refuses. Nothing here changes what compiles.
      * **The handler set is deployment state, not authoring state.** Which
        types a host can actually run is a property of the deployment the
        document is run in, not of the document, so it arrives as an assign
        the host fills in and never as anything stored in the block.

    The assign shares its name with the compiler's `invoke_types` surface -
    `StatifierBlocks.Compiled`'s field and the compiler's
    `:known_invoke_types` option - and the two are separate surfaces that
    happen to describe the same vocabulary from opposite ends. The
    compiler's is *derived from a document*: the sorted set of types that
    document actually emits. This one is *supplied by a host*: the types it
    is prepared to answer. Neither reads the other.

    Keying a control on a field's key is a narrower thing than the
    `placeholder` question above, which is why it does not reopen it: a
    block type declaring an `invoke_type` field of some other type keeps
    that type's control, because this clause is reached only after every
    typed clause has had its turn.
    """

    use Phoenix.Component

    alias StatifierBlocks.{DurationInput, ViewModel}

    attr(:field, ViewModel.Field, required: true)
    attr(:target, :any, required: true)
    attr(:class, :string, default: nil)

    attr(:expression_component, :any,
      default: nil,
      doc:
        "Override for `:expression`, per ADR-0005 decision 9's seam. Receives the same assigns."
    )

    attr(:invoke_types, :list,
      default: [],
      doc: """
      The invoke types the host is prepared to answer. Suggestions for an
      `invoke_type` field, never a constraint on it; empty is *no list
      supplied* and renders the plain input.
      """
    )

    attr(:path_candidates, :list,
      default: [],
      doc: """
      The declared datamodel paths, from `StatifierBlocks.Datamodel.candidates/3`.
      Suggestions on an `:expression` field and passed to
      `expression_component` as `:candidates`; empty renders the plain input.
      """
    )

    attr(:value_candidates, :map,
      default: %{},
      doc: """
      The values a host offers per datamodel path, `%{path => [candidate]}`.
      Passed to `expression_component` as `:value_candidates` and read only
      there; `%{}` offers none and a path with no entry gets free text.
      """
    )

    attr(:fixture_hint, :any,
      default: nil,
      doc: """
      `StatifierBlocks.Shell.fixture_hint/3`'s answer for this field, or
      `nil`. Drawn as an element beside the control, never passed through the
      `expression_component` seam and never an option.
      """
    )

    @doc "One field: its label, its control, and its own findings (decision 11)."
    def field(assigns) do
      ~H"""
      <div class={["sb-field", @class]} data-field={@field.key} data-field-type={type_tag(@field.type)}>
        <label class="sb-field__label" for={input_id(@field)}>
          <span class="sb-field__label-text">{@field.label}</span>
          <span :if={@field.required?} class="sb-field__required">Required</span>
        </label>
        <.control
          field={@field}
          target={@target}
          expression_component={resolve_expression_component(@expression_component)}
          invoke_types={@invoke_types}
          path_candidates={@path_candidates}
          value_candidates={@value_candidates}
        />
        <p
          :if={@fixture_hint}
          class="sb-field__fixture-hint"
          data-fixture-hint={@fixture_hint.path}
          title={hint_title(@fixture_hint)}
        >
          From fixtures, {@fixture_hint.path} is {@fixture_hint.value}
        </p>
        <p :for={finding <- @field.findings} class={["sb-finding", severity_class(finding)]}>
          {finding.message}
        </p>
      </div>
      """
    end

    attr(:field, ViewModel.Field, required: true)
    attr(:target, :any, required: true)
    attr(:expression_component, :any, default: nil)
    attr(:invoke_types, :list, default: [])
    attr(:path_candidates, :list, default: [])
    attr(:value_candidates, :map, default: %{})

    defp control(%{field: %ViewModel.Field{type: :boolean}} = assigns) do
      ~H"""
      <div class="sb-field__row">
        <input type="hidden" name={input_name(@field)} value="false" />
        <input
          class="sb-field__input"
          type="checkbox"
          id={input_id(@field)}
          name={input_name(@field)}
          value="true"
          checked={@field.value == true}
        />
      </div>
      """
    end

    defp control(%{field: %ViewModel.Field{type: :integer}} = assigns) do
      ~H"""
      <input
        class="sb-field__input"
        type="number"
        step="1"
        id={input_id(@field)}
        name={input_name(@field)}
        value={to_text(@field.value)}
      />
      """
    end

    defp control(%{field: %ViewModel.Field{type: {:select, choices}}} = assigns) do
      assigns = assign(assigns, :choices, choices)

      ~H"""
      <select class="sb-field__input" id={input_id(@field)} name={input_name(@field)}>
        <option :for={{value, label} <- @choices} value={value} selected={@field.value == value}>
          {label}
        </option>
      </select>
      """
    end

    defp control(
           %{
             field: %ViewModel.Field{type: :expression},
             expression_component: nil,
             path_candidates: [_first | _rest]
           } = assigns
         ) do
      assigns = assign(assigns, :list_id, input_id(assigns.field) <> "-paths")

      ~H"""
      <input
        class="sb-field__input sb-field__input--expression"
        type="text"
        id={input_id(@field)}
        name={input_name(@field)}
        value={to_text(@field.value)}
        list={@list_id}
        placeholder="an expression"
        spellcheck="false"
        autocomplete="off"
      />
      <datalist id={@list_id} data-path-candidates={length(@path_candidates)}>
        <option :for={path <- @path_candidates} value={path}></option>
      </datalist>
      """
    end

    defp control(
           %{field: %ViewModel.Field{type: :expression}, expression_component: nil} = assigns
         ) do
      ~H"""
      <input
        class="sb-field__input sb-field__input--expression"
        type="text"
        id={input_id(@field)}
        name={input_name(@field)}
        value={to_text(@field.value)}
        placeholder="an expression"
        spellcheck="false"
      />
      """
    end

    defp control(%{field: %ViewModel.Field{type: :expression}} = assigns) do
      # A function component is a one-argument function returning a rendered
      # struct, so the seam is a call rather than a registry: a host passes
      # `&MyApp.expression_input/1` and gets the same assigns this module
      # would have used. HEEx has no dynamic-component tag, and inventing a
      # module-and-behaviour indirection for one override would be more
      # machinery than the deferral is worth.
      #
      # `candidates` is additive to that map (sb-0vt), and
      # `value_candidates` is additive in exactly the same way (sb-m6e0). An
      # override written before either existed takes a map and ignores a key
      # it does not read, so nothing that worked stops working; an override
      # written after can offer the declared paths, and the host's own value
      # sets for them, without re-deriving either from assigns this component
      # is not handed.
      ~H"""
      {@expression_component.(%{
        field: @field,
        id: input_id(@field),
        name: input_name(@field),
        value: to_text(@field.value),
        candidates: @path_candidates,
        value_candidates: @value_candidates
      })}
      """
    end

    defp control(%{field: %ViewModel.Field{type: :duration}} = assigns) do
      assigns =
        assigns
        |> assign(:reading, DurationInput.read(assigns.field.value))
        |> assign(:examples_id, input_id(assigns.field) <> "-examples")

      ~H"""
      <input
        class="sb-field__input sb-field__input--duration"
        type="text"
        id={input_id(@field)}
        name={input_name(@field)}
        value={to_text(@field.value)}
        placeholder={DurationInput.placeholder()}
        spellcheck="false"
        aria-describedby={@examples_id}
      />
      <p class="sb-field__examples" id={@examples_id}>
        Try {Enum.join(DurationInput.examples(), ", ")}, or ISO-8601 like PT1H30M.
      </p>
      <p :if={@reading.form == :invalid} class="sb-field__refusal" data-duration-refusal>
        {@reading.message}
      </p>
      """
    end

    defp control(%{field: %ViewModel.Field{type: {:list, inner}}} = assigns) do
      assigns =
        assigns
        |> assign(:inner, inner)
        |> assign(:rows, List.wrap(assigns.field.value))

      ~H"""
      <div class="sb-field__list">
        <div :for={{value, index} <- Enum.with_index(@rows)} class="sb-field__row" data-row={index}>
          <.row_control
            inner={@inner}
            value={value}
            id={input_id(@field) <> "-#{index}"}
            name={input_name(@field) <> "[]"}
          />
          <button
            type="button"
            class="sb-button sb-field__remove"
            phx-click="field-list-remove"
            phx-target={@target}
            phx-value-key={@field.key}
            phx-value-index={index}
          >
            remove
          </button>
        </div>
        <input :if={@rows == []} type="hidden" name={input_name(@field) <> "[]"} value="" />
        <button
          type="button"
          class="sb-button sb-field__add"
          phx-click="field-list-add"
          phx-target={@target}
          phx-value-key={@field.key}
        >
          add
        </button>
      </div>
      """
    end

    # Reached only after every typed clause, so a block type that declares
    # `invoke_type` as something other than a string keeps that type's own
    # control. The empty list falls through to the plain input below, which
    # is what makes "no list supplied" and "a list that happens to be empty"
    # the same thing on screen - a `<datalist>` with no options suggests
    # nothing and would only add an element for a reader to trip over.
    defp control(
           %{field: %ViewModel.Field{key: "invoke_type"}, invoke_types: [_first | _rest]} =
             assigns
         ) do
      assigns = assign(assigns, :list_id, input_id(assigns.field) <> "-types")

      ~H"""
      <input
        class="sb-field__input"
        type="text"
        id={input_id(@field)}
        name={input_name(@field)}
        value={to_text(@field.value)}
        list={@list_id}
        spellcheck="false"
        autocomplete="off"
      />
      <datalist id={@list_id} data-invoke-types={length(@invoke_types)}>
        <option :for={type <- @invoke_types} value={type}></option>
      </datalist>
      """
    end

    defp control(%{field: %ViewModel.Field{}} = assigns) do
      ~H"""
      <input
        class="sb-field__input"
        type="text"
        id={input_id(@field)}
        name={input_name(@field)}
        value={to_text(@field.value)}
      />
      """
    end

    attr(:inner, :any, required: true)
    attr(:value, :any, required: true)
    attr(:id, :string, required: true)
    attr(:name, :string, required: true)

    defp row_control(%{inner: :boolean} = assigns) do
      ~H"""
      <select class="sb-field__input" id={@id} name={@name}>
        <option value="true" selected={@value == true}>true</option>
        <option value="false" selected={@value != true}>false</option>
      </select>
      """
    end

    defp row_control(%{inner: {:select, _choices}} = assigns) do
      assigns = assign(assigns, :choices, elem(assigns.inner, 1))

      ~H"""
      <select class="sb-field__input" id={@id} name={@name}>
        <option :for={{value, label} <- @choices} value={value} selected={@value == value}>
          {label}
        </option>
      </select>
      """
    end

    defp row_control(%{inner: :integer} = assigns) do
      ~H"""
      <input
        class="sb-field__input"
        type="number"
        step="1"
        id={@id}
        name={@name}
        value={to_text(@value)}
      />
      """
    end

    defp row_control(assigns) do
      ~H"""
      <input class="sb-field__input" type="text" id={@id} name={@name} value={to_text(@value)} />
      """
    end

    @doc """
    Decodes one field's slice of a form's params back into a config value,
    dispatching on the same closed type set the renderer does.

    Total, and deliberately non-coercing at the edges: an integer field
    whose input does not parse yields the string the author typed, so
    `validate_config/1` reports it and decision 9's gate keeps it out of
    the document. Coercing to zero here would silently discard the author's
    intent and commit a value they never asked for.
    """
    @spec decode(StatifierBlocks.BlockType.field_type(), term()) :: StatifierBlocks.Block.json()
    def decode(:integer, raw) when is_binary(raw) do
      case Integer.parse(String.trim(raw)) do
        {int, ""} -> int
        _other -> raw
      end
    end

    def decode(:boolean, raw), do: raw in [true, "true", "on", "1"]

    def decode({:list, inner}, raw) when is_list(raw), do: Enum.map(raw, &decode(inner, &1))
    def decode({:list, inner}, raw), do: [decode(inner, raw)]
    def decode(_type, raw) when is_binary(raw), do: raw
    def decode(_type, raw), do: raw

    @doc "The DOM id for a field's control. Part of decision 7's DOM contract."
    @spec input_id(ViewModel.Field.t()) :: String.t()
    def input_id(%ViewModel.Field{key: key}), do: "sb-field-" <> key

    @doc "The form param name a field's control posts under."
    @spec input_name(ViewModel.Field.t()) :: String.t()
    def input_name(%ViewModel.Field{key: key}), do: "config[" <> key <> "]"

    # The whole set, on `title`: one glance for the shape of a value, one
    # hover for the range of them. `Shell.fixture_hint/3` has already made
    # them distinct and put them in first-appearance order, so this only
    # spells the separator.
    @spec hint_title(StatifierBlocks.Shell.fixture_hint()) :: String.t()
    defp hint_title(%{values: values}), do: Enum.join(values, ", ")

    # One place spells the severity modifiers, and it is outside
    # `StatifierBlocks.Editor.*` so it is asserted with LiveView absent
    # (ADR-0005 decision 11, amended 2026-08-29 for `:info`).
    @spec severity_class(StatifierBlocks.Finding.t()) :: String.t()
    defp severity_class(finding), do: StatifierBlocks.Finding.severity_class(finding)

    # Clause 2 of the moduledoc's ordering: with no override supplied, an
    # `:expression` renders statifier-ui's editor when statifier-ui resolves.
    #
    # `statifier_ui` is optional, so the module is never named as a call
    # target - it is read from application config and captured dynamically.
    # That keeps the compiler quiet in a tree without the package, and it is
    # what lets a test assert the absent branch on a machine where the
    # package is present: point the key at a module that does not exist and
    # the plain input is what renders. statifier-ui reaches `Predicator.Simple`
    # the same way, for the same reason.
    @spec resolve_expression_component((map() -> term()) | nil) :: (map() -> term()) | nil
    defp resolve_expression_component(nil), do: statifier_ui_component()
    defp resolve_expression_component(component), do: component

    @spec statifier_ui_component() :: (map() -> term()) | nil
    defp statifier_ui_component do
      module =
        Application.get_env(
          :statifier_blocks,
          :expression_component_module,
          StatifierUI.Live.ExpressionInput
        )

      if Code.ensure_loaded?(module) and function_exported?(module, :expression_input, 1) do
        &module.expression_input/1
      end
    end

    @spec type_tag(StatifierBlocks.BlockType.field_type()) :: String.t()
    defp type_tag({tag, _inner}), do: Atom.to_string(tag)
    defp type_tag(tag), do: Atom.to_string(tag)

    @spec to_text(term()) :: String.t()
    defp to_text(nil), do: ""
    defp to_text(value) when is_binary(value), do: value
    defp to_text(value) when is_integer(value), do: Integer.to_string(value)
    defp to_text(value), do: inspect(value)
  end
end
