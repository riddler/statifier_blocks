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
    | `:duration` | structured value/unit control emitting an ISO-8601 string |
    | `{:list, t}` | repeatable rows of `t`'s renderer, with add and remove |

    `:duration` emits a string rather than a number because ADR-0001
    decision 6 forbids floats in config and "1.5 hours" has to be `PT1H30M`.
    The control exists so the author does not have to know that. A stored
    duration this module cannot parse is **not** discarded: it falls back to
    a plain text input carrying the original string, on the same principle
    as decision 12 - the editor never loses data it did not author.

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

    alias StatifierBlocks.ViewModel

    @units ~w(seconds minutes hours days)

    @doc "The unit names the `:duration` control offers, largest last."
    @spec units() :: [String.t()]
    def units, do: @units

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
          {@field.label}<span :if={@field.required?} class="sb-field__required">*</span>
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
      assigns = assign(assigns, :parsed, parse_duration(assigns.field.value))

      ~H"""
      <div :if={@parsed} class="sb-field__row">
        <input
          class="sb-field__input"
          type="number"
          step="1"
          min="0"
          id={input_id(@field)}
          name={input_name(@field) <> "[value]"}
          value={elem(@parsed, 0)}
        />
        <select class="sb-field__input" name={input_name(@field) <> "[unit]"}>
          <option :for={unit <- units()} value={unit} selected={elem(@parsed, 1) == unit}>
            {unit}
          </option>
        </select>
      </div>
      <input
        :if={is_nil(@parsed)}
        class="sb-field__input sb-field__input--expression"
        type="text"
        id={input_id(@field)}
        name={input_name(@field) <> "[raw]"}
        value={to_text(@field.value)}
      />
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

    def decode(:duration, %{"raw" => raw}), do: raw

    def decode(:duration, %{"value" => value, "unit" => unit}) do
      case decode(:integer, value) do
        int when is_integer(int) and int >= 0 -> format_duration(int, unit)
        _other -> to_text(value)
      end
    end

    def decode({:list, inner}, raw) when is_list(raw), do: Enum.map(raw, &decode(inner, &1))
    def decode({:list, inner}, raw), do: [decode(inner, raw)]
    def decode(_type, raw) when is_binary(raw), do: raw
    def decode(_type, raw), do: raw

    @doc """
    An ISO-8601 duration from a whole number of one unit. The inverse of
    `parse_duration/1` on everything `parse_duration/1` accepts.
    """
    @spec format_duration(non_neg_integer(), String.t()) :: String.t()
    def format_duration(n, "days"), do: "P#{n}D"
    def format_duration(n, "hours"), do: "PT#{n}H"
    def format_duration(n, "minutes"), do: "PT#{n}M"
    def format_duration(n, _seconds), do: "PT#{n}S"

    @doc """
    An ISO-8601 duration as `{count, unit}` in the largest unit that divides
    it evenly, or `nil` for anything this control cannot represent - a value
    with a month or year component, a fractional one, or a string that is
    not a duration at all. `nil` is what routes the value to the raw text
    fallback rather than to the structured control, which is how a duration
    the editor did not author survives being rendered.
    """
    @spec parse_duration(term()) :: {non_neg_integer(), String.t()} | nil
    def parse_duration(value) when is_binary(value) do
      case Regex.run(~r/^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$/, value) do
        nil -> nil
        [^value] -> nil
        [_all | parts] -> parts |> total_seconds() |> largest_unit()
      end
    end

    def parse_duration(_value), do: nil

    @spec total_seconds([String.t()]) :: non_neg_integer()
    defp total_seconds(parts) do
      [days, hours, minutes, seconds] =
        Enum.map(0..3, fn index -> parts |> Enum.at(index, "") |> int_or_zero() end)

      days * 86_400 + hours * 3600 + minutes * 60 + seconds
    end

    @spec int_or_zero(String.t() | nil) :: non_neg_integer()
    defp int_or_zero(nil), do: 0
    defp int_or_zero(""), do: 0
    defp int_or_zero(text), do: String.to_integer(text)

    @spec largest_unit(non_neg_integer()) :: {non_neg_integer(), String.t()}
    defp largest_unit(0), do: {0, "seconds"}

    defp largest_unit(total) do
      cond do
        rem(total, 86_400) == 0 -> {div(total, 86_400), "days"}
        rem(total, 3600) == 0 -> {div(total, 3600), "hours"}
        rem(total, 60) == 0 -> {div(total, 60), "minutes"}
        true -> {total, "seconds"}
      end
    end

    @doc "The DOM id for a field's control. Part of decision 7's DOM contract."
    @spec input_id(ViewModel.Field.t()) :: String.t()
    def input_id(%ViewModel.Field{key: key}), do: "sb-field-" <> key

    @doc "The form param name a field's control posts under."
    @spec input_name(ViewModel.Field.t()) :: String.t()
    def input_name(%ViewModel.Field{key: key}), do: "config[" <> key <> "]"

    @spec severity_class(StatifierBlocks.Finding.t()) :: String.t()
    defp severity_class(%StatifierBlocks.Finding{severity: :warning}), do: "sb-finding--warning"
    defp severity_class(%StatifierBlocks.Finding{}), do: "sb-finding--error"

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
