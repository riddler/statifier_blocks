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
    | `:expression` | single-line source input |
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

    `:expression` renders as a plain source input here. Predicator source is
    statifier-ui's subject (sui-bob, sui-ADR-0006), and decision 9 records a
    richer affordance as a deferral, so this component accepts an
    `expression_component` override for exactly that seam.

    This module is a renderer, not a gate. Nothing here decides whether a
    value is acceptable: `validate_config/1` does, through
    `StatifierBlocks.Edit.check_config/3`, which is why an unparseable
    integer reaches the draft config as the string the author typed rather
    than being silently coerced or dropped.
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

    @doc "One field: its label, its control, and its own findings (decision 11)."
    def field(assigns) do
      ~H"""
      <div class={["sb-field", @class]} data-field={@field.key} data-field-type={type_tag(@field.type)}>
        <label class="sb-field__label" for={input_id(@field)}>
          <span class="sb-field__label-text">{@field.label}</span>
          <span :if={@field.required?} class="sb-field__required">Required</span>
        </label>
        <.control field={@field} target={@target} expression_component={@expression_component} />
        <p :for={finding <- @field.findings} class={["sb-finding", severity_class(finding)]}>
          {finding.message}
        </p>
      </div>
      """
    end

    attr(:field, ViewModel.Field, required: true)
    attr(:target, :any, required: true)
    attr(:expression_component, :any, default: nil)

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
      ~H"""
      {@expression_component.(%{
        field: @field,
        id: input_id(@field),
        name: input_name(@field),
        value: to_text(@field.value)
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
            class="sb-field__remove"
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
          class="sb-field__add"
          phx-click="field-list-add"
          phx-target={@target}
          phx-value-key={@field.key}
        >
          add
        </button>
      </div>
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

    # One place spells the severity modifiers, and it is outside
    # `StatifierBlocks.Editor.*` so it is asserted with LiveView absent
    # (ADR-0005 decision 11, amended 2026-08-29 for `:info`).
    @spec severity_class(StatifierBlocks.Finding.t()) :: String.t()
    defp severity_class(finding), do: StatifierBlocks.Finding.severity_class(finding)

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
