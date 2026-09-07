if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.ConfigForm do
    @moduledoc """
    The selected block's config form (ADR-0005 decisions 9 and 13).

    The form is a **projection of current config, never a stateful mirror of
    it**: `StatifierBlocks.ViewModel` re-derives `config_schema/1` against the
    block's current config on every build, so a branch that gains an arm gains
    a field on the very next render with nothing here to invalidate.

    Two things this component does not do, both deliberate:

      * It does not decide what reaches the document. Decision 9's gate -
        an `:update_config` is applied only when `validate_config/1` returns
        `:ok` - lives in `StatifierBlocks.Edit.check_config/3`, which
        `StatifierBlocks.Edit.History.commit/4` calls. This component posts
        params; `StatifierBlocks.Editor` decodes them and offers the command.
      * It does not render an unresolvable block's config. There is no
        `config_schema/1` for one, and inventing a form would be guessing
        (decision 12), so `StatifierBlocks.Editor.BlockNode` shows canonical
        JSON read-only instead.

    What it draws is `StatifierBlocks.ViewModel.shown_fields/1`'s list and
    nothing else. The view model lists every declared field, `hidden?: true`
    ones included, because it is a projection of the schema; the surface
    filters (ADR-0002 decision 7, amended 2026-09-07, section F7). That
    filter is written once, in the view model, and a host drawing its own
    form calls the same function - so a change to what counts as shown
    reaches both surfaces at once, with no second copy of the predicate here
    to fall behind it. `Field.field/1` renders nothing for a hidden field
    either; the two agree, and neither is load-bearing alone.

    `form.unrouted` renders at the head. That bucket exists because
    `Core.Branch.config_schema/1` keys one field per arm by the arm's own
    slot name while `validate_config/1` also emits findings keyed `"arms"` -
    a key matching no field, because adding or removing an arm is a document
    edit, not a form value. Rendering it here is what stops such a finding
    from silently having nowhere to go.
    """

    use Phoenix.Component

    alias Phoenix.LiveView.JS
    alias StatifierBlocks.{BlockType, DurationInput}
    alias StatifierBlocks.Editor.Field
    alias StatifierBlocks.Shell
    alias StatifierBlocks.ViewModel

    attr(:node, ViewModel.Node, required: true)
    attr(:target, :any, required: true)
    attr(:class, :string, default: nil)
    attr(:expression_component, :any, default: nil)

    attr(:invoke_types, :list,
      default: [],
      doc: "Passed through to `StatifierBlocks.Editor.Field`; see its moduledoc."
    )

    attr(:path_candidates, :list,
      default: [],
      doc: "Passed through to `StatifierBlocks.Editor.Field`; see its moduledoc."
    )

    attr(:value_candidates, :map,
      default: %{},
      doc: "Passed through to `StatifierBlocks.Editor.Field`; see its moduledoc."
    )

    attr(:path_types, :map,
      default: %{},
      doc: "Passed through to `StatifierBlocks.Editor.Field`; see its moduledoc."
    )

    attr(:type_candidates, :list,
      default: [],
      doc: "Passed through to `StatifierBlocks.Editor.Field`; see its moduledoc."
    )

    attr(:event_candidates, :list,
      default: [],
      doc: "Passed through to `StatifierBlocks.Editor.Field`; see its moduledoc."
    )

    attr(:outcome_candidates, :list,
      default: [],
      doc: "Passed through to `StatifierBlocks.Editor.Field`; see its moduledoc."
    )

    attr(:fixtures, :any,
      default: nil,
      doc: """
      The `fixtures` the editor holds, `%{block_id => [TruthTable.t()]}` or
      `nil`. Read here through `StatifierBlocks.Shell.tables_for/2` for the
      selected block's rows and passed to `StatifierBlocks.Editor.Field` as
      the fixture hint; nothing else is derived from it.
      """
    )

    attr(:field_candidates, :map,
      default: %{},
      doc: """
      The values a host offers, keyed `{type_name, field_key}`. Looked up
      here for the selected node's own type and handed to
      `StatifierBlocks.Editor.Field` one field at a time; see its moduledoc
      for the two spellings.
      """
    )

    attr(:capture_pairs, :any,
      default: nil,
      doc: """
      The block's capture pairs as ordered `{target, source}` rows, or
      `nil` for a block that takes no capture map. `[]` is a block that
      takes one and has none yet, which still draws the row.
      """
    )

    attr(:capture_sources, :list,
      default: [],
      doc: """
      The source keys a captured event's example payload carries, drawn as
      the source control's `<datalist>`. Empty renders a plain input.
      """
    )

    attr(:pending, :list,
      default: [],
      doc: """
      The fields whose typed value is not in the document, in schema order.
      Empty when the block has no outstanding draft.
      """
    )

    attr(:field_focus, :any,
      default: nil,
      doc: """
      One-shot: the `config_key` of the field the source tab's click-through
      (`sb-rd29`) just asked to be focused, or `nil` for "leave focus alone".
      `StatifierBlocks.Editor` sets it on a click into a config-emitted span
      and clears it on every other route, the same discipline
      `StatifierBlocks.Editor.Drawer`'s `focus_tab` keeps for the tab strip.
      Resolved here against `@node.form.fields` rather than trusted verbatim,
      so a key belonging to some other block's form - stale, or never valid -
      focuses nothing.
      """
    )

    attr(:read_only, :boolean,
      default: false,
      doc: """
      Whether this mount edits. A read-only form is not a form: it is a
      `<div>` of the same fields drawn through `Field.field/1`'s
      **readonly** branch - label and value, no control, nothing that posts
      (ADR-0005's 2026-09-07 profile amendment, `read_only?` clause 3). A
      disabled input is a control that refuses, and what is wanted here is a
      reading, which is why the same branch `readonly?: true` already renders
      one field with is what renders all of them.
      """
    )

    attr(:debounce, :any,
      default: nil,
      doc: """
      What `phx-debounce` this form's controls carry, or `nil` for none.
      Handed to `StatifierBlocks.Editor.Field` and to the capture rows,
      which write it onto every control they render; that module's attr
      documents the accepted values and why every control means every
      control.

      The form posts `phx-change` on each change event and
      `StatifierBlocks.Editor` offers an `:update_config` for each one it
      decodes, so a host that persists on its own `on_change` writes once
      per keystroke unless it asks for something slower. Asking is what
      this attr is: how often a document is written is a decision about
      the host's storage, and the controls are this package's markup, so
      the host needs a way to say it here.

      `nil` renders no attribute anywhere, which is byte for byte what
      this component rendered before the attr existed. Nothing about
      decoding changes with it either: `decode/3` still reads only the
      params a post carried, and a field whose control did not post still
      keeps the value it had - a slower post is a *later* post, never a
      partial one.

      A read-only form draws no controls at all, so it has nothing to
      carry this and is not handed it.
      """
    )

    @doc "One block's form: unrouted findings, then a control per schema field."
    def config_form(%{read_only: true} = assigns) do
      assigns =
        assign(
          assigns,
          :fields,
          Enum.map(ViewModel.shown_fields(assigns.node), &read_only/1)
        )

      ~H"""
      <div class="sb-form sb-form--readonly" data-block-id={@node.block_id} data-read-only="true">
        <p :for={finding <- @node.form.unrouted} class={["sb-finding", severity_class(finding)]}>
          {finding.message}
        </p>
        <Field.field
          :for={field <- @fields}
          field={field}
          target={@target}
          block_id={@node.block_id}
        />
        <div :if={@capture_pairs not in [nil, []]} class="sb-capture sb-capture--readonly">
          <p class="sb-capture__label">Capture from the event</p>
          <p :for={{target, source} <- @capture_pairs} class="sb-capture__row sb-field__value">
            {target} &larr; {source}
          </p>
        </div>
      </div>
      """
    end

    def config_form(assigns) do
      assigns =
        assign(assigns, :focus_input_id, focus_input_id(assigns.node, assigns.field_focus))

      ~H"""
      <form
        id={"sb-form-" <> @node.block_id}
        class={["sb-form", @class]}
        data-block-id={@node.block_id}
        phx-change="config-change"
        phx-submit="config-change"
        phx-target={@target}
      >
        <span
          :if={@focus_input_id}
          id={"sb-config-focus-" <> @focus_input_id}
          hidden
          phx-mounted={JS.focus(to: "#" <> @focus_input_id)}
        ></span>
        <input type="hidden" name="block-id" value={@node.block_id} phx-debounce={@debounce} />
        <div :if={@pending != []} class="sb-form__pending" data-pending={length(@pending)}>
          <p class="sb-form__pending-note">
            Nothing is stored yet. {pending_sentence(@pending)}
          </p>
          <button
            type="button"
            class="sb-form__discard"
            phx-click="discard-draft"
            phx-target={@target}
            phx-value-block-id={@node.block_id}
          >
            Discard edits
          </button>
        </div>
        <p :for={finding <- @node.form.unrouted} class={["sb-finding", severity_class(finding)]}>
          {finding.message}
        </p>
        <Field.field
          :for={field <- ViewModel.shown_fields(@node)}
          field={field}
          target={@target}
          block_id={@node.block_id}
          expression_component={@expression_component}
          invoke_types={@invoke_types}
          path_candidates={@path_candidates}
          value_candidates={@value_candidates}
          path_types={@path_types}
          type_candidates={@type_candidates}
          event_candidates={@event_candidates}
          outcome_candidates={@outcome_candidates}
          candidates={candidates_for(@field_candidates, @node.type, field)}
          fixture_hint={fixture_hint(@fixtures, @node.block_id, field)}
          debounce={@debounce}
        />
        <.capture_rows
          :if={@capture_pairs != nil}
          rows={@capture_pairs}
          sources={@capture_sources}
          target={@target}
          block_id={@node.block_id}
          debounce={@debounce}
        />
      </form>
      """
    end

    attr(:rows, :list, required: true)
    attr(:sources, :list, required: true)
    attr(:target, :any, required: true)
    attr(:block_id, :string, required: true)
    attr(:debounce, :any, default: nil)

    @doc """
    The capture pairs, one two-control row each (ADR-0011 decision 10).

    A row is a datamodel path written and a path inside the firing event's
    `_event.data` read, and it is a repeated row rather than a field
    because ADR-0002 decision 7's closed field-type set has no member that
    describes a map and this record declined to add one. So the pairs have
    no `config_schema/1` declaration to render from, and they are drawn
    here from the config the editor already holds.

    There is always **one blank row at the end**, and it is what adds a
    pair: filling it writes a pair and the next blank row appears beneath
    it. Clearing both controls of a row is what removes one. That is two
    gestures rather than an add button and a remove button, and it is the
    shape the pairs already have: a map with a blank key is not a pair, so
    a row that says nothing is a row that is not there.

    A stored map has no order of its own, so the rows before the blank one
    are in their targets' sorted order - the order the emission already
    fixes, for the same reason.
    """
    def capture_rows(assigns) do
      assigns = assign(assigns, :list_id, "sb-capture-sources-" <> assigns.block_id)

      ~H"""
      <div class="sb-capture" data-capture-rows={length(@rows)}>
        <p class="sb-capture__label">Capture from the event</p>
        <div
          :for={{{target, source}, index} <- Enum.with_index(@rows ++ [{"", ""}])}
          class="sb-capture__row"
          data-capture-row={index}
        >
          <input
            class="sb-field__input sb-capture__target"
            type="text"
            id={"sb-capture-target-" <> Integer.to_string(index)}
            name={"capture[" <> Integer.to_string(index) <> "][target]"}
            value={target}
            placeholder="a datamodel path"
            spellcheck="false"
            autocomplete="off"
            phx-debounce={@debounce}
          />
          <input
            class="sb-field__input sb-capture__source"
            type="text"
            id={"sb-capture-source-" <> Integer.to_string(index)}
            name={"capture[" <> Integer.to_string(index) <> "][source]"}
            value={source}
            placeholder="a path in the event payload"
            list={if @sources != [], do: @list_id}
            spellcheck="false"
            autocomplete="off"
            phx-debounce={@debounce}
          />
        </div>
        <datalist :if={@sources != []} id={@list_id} data-capture-sources={length(@sources)}>
          <option :for={source <- @sources} value={source}></option>
        </datalist>
      </div>
      """
    end

    @doc """
    Decodes a `phx-change` payload into a config map, one field at a time
    through `StatifierBlocks.Editor.Field.decode/2`.

    Three properties, each of which is a bug if it is missing:

      * **It starts from `base`, the config the block already carries.** An
        `:update_config` command *replaces* a block's whole config, so a
        decode that built a fresh map from the schema alone would delete every
        key the schema does not name. ADR-0002 decision 7 makes
        `config_schema/1` a rendering hint rather than the authority, and
        ADR-0001 decision 9's principle - leave alone what you do not
        understand - applies to config keys as much as to block types.
      * **It is keyed off the schema, not off the params.** A param naming
        something the schema does not is ignored, so a crafted payload cannot
        inject config keys.
      * **A field whose control did not post keeps the value it had.** A
        partially rendered form does not blank out the fields it did not show.

    A fourth, added 2026-09-07 with the `hidden?` / `readonly?` flags
    (ADR-0002 decision 7's amendment, section F6, and campaign-SF036 ruling
    `RQ-SF036-15`): **a flagged field ignores any posted value for its key.**
    The decode is keyed off the schema and a hidden field is in the schema,
    so a crafted payload posting under a hidden field's key would otherwise
    be decoded through a control no form ever drew. For a `hidden?: true` or
    `readonly?: true` field the unposted branch is taken unconditionally,
    which defends a key the form withheld and touches none of the three
    properties above.

    ## Where a decoded value is written

    A field's `key` names its control; where the value goes is the field's
    `value_path` (ADR-0002 decision 7, amended 2026-08-27), which is `[key]`
    unless the block type said otherwise. `Core.Branch` is the one core type
    that says otherwise: its per-arm condition fields keep their slot-name
    keys and declare `["arms", i, "cond"]`, so a branch's conditions are
    editable here without this component ever inferring anything from the
    shape of a key. Writing through the path is also what stops a top-level
    `config["arm_approved"]` from accumulating beside the arm the author
    actually edited.

    ## The one value that is not written at all

    An empty `:duration` **omits its key** rather than storing `""`
    (ADR-0005 decision 9, amended 2026-08-29). A cleared field and a
    never-set field are the same value - there is no zero-duration
    stand-in and no third
    state for "the author touched this and then did not finish" - so the
    two have to produce the same config, and the only config an absent key
    can produce is one without the key.

    This is the only place that can perform it. `Field.decode/2` returns a
    value and every value it could return is a value the key would then
    hold; whether a key exists is a property of the map, which is this
    function's to write. The omission is still the ordinary path in every
    other respect: the resulting config goes to the same whole-config gate
    through `StatifierBlocks.Edit.check_config/3`, and a required duration
    left empty is refused there rather than here.
    """
    @spec decode([ViewModel.Field.t()], map(), StatifierBlocks.Block.config()) ::
            StatifierBlocks.Block.config()
    def decode(fields, params, base \\ %{}) when is_list(fields) and is_map(params) do
      posted = Map.get(params, "config", %{})

      fields
      |> Enum.reduce(base, fn %ViewModel.Field{} = field, config ->
        value =
          case posted_value(field, posted) do
            {:ok, raw} -> Field.decode(field.type, raw)
            :error -> field.value
          end

        path = ViewModel.Field.value_path(field)

        if omitted?(field.type, value) do
          drop_value(config, path)
        else
          BlockType.put_value(config, path, value)
        end
      end)
      |> decode_capture(params)
    end

    # The capture rows, which have no field to be decoded through: the
    # posted rows ARE the map, so a form that drew them replaces
    # `config["capture"]` wholesale and a form that did not leaves the key
    # exactly as it was.
    #
    # A row saying nothing at all is dropped, which is what makes clearing
    # a row remove its pair and the trailing blank row cost nothing. A row
    # that says only half of a pair is KEPT, at the blank key it has -
    # `validate_config/1` refuses that map and the draft holds it, so an
    # author who typed the source first sees a finding and their own bytes
    # rather than watching them vanish between keystrokes. An empty map is
    # written rather than the key dropped, which is the value
    # `validate_config/1` and `emit/2` both already read as "captures
    # nothing".
    @spec decode_capture(StatifierBlocks.Block.config(), map()) ::
            StatifierBlocks.Block.config()
    defp decode_capture(config, %{"capture" => rows}) when is_map(rows) do
      pairs =
        rows
        |> Enum.sort_by(fn {index, _row} -> row_index(index) end)
        |> Enum.map(fn {_index, row} -> {row_text(row, "target"), row_text(row, "source")} end)
        |> Enum.reject(fn {target, source} -> target == "" and source == "" end)
        |> Map.new()

      Map.put(config, "capture", pairs)
    end

    defp decode_capture(config, _no_capture_posted), do: config

    @spec row_text(term(), String.t()) :: String.t()
    defp row_text(row, key) when is_map(row) do
      case Map.get(row, key) do
        text when is_binary(text) -> String.trim(text)
        _absent_or_not_text -> ""
      end
    end

    defp row_text(_row, _key), do: ""

    # Row keys arrive as the strings a form posted, so `"10"` sorts before
    # `"2"` unless they are read as numbers. Order decides only which of two
    # rows naming one target survives the map, and it should be the one
    # further down the form rather than the one that sorts later as text.
    @spec row_index(term()) :: integer()
    defp row_index(index) when is_binary(index) do
      case Integer.parse(index) do
        {number, ""} -> number
        _not_a_number -> 0
      end
    end

    defp row_index(_index), do: 0

    # A read-only mount draws every field the way a `readonly?: true` field is
    # already drawn. The flag is set on the projection rather than a second
    # values-only renderer being written beside `Field.field/1`: the rendering
    # the amendment asks for and the rendering that flag already produces are
    # one rendering, and two spellings of one rendering is how they drift.
    @spec read_only(ViewModel.Field.t()) :: ViewModel.Field.t()
    defp read_only(field), do: %{field | readonly?: true}

    # A field the form withheld reads nothing out of the params, whatever the
    # params carry (F6 as ruled by `RQ-SF036-15`). `:error` is the same term
    # `Map.fetch/2` returns for a key that was never posted, so the reduce
    # above has one unposted branch rather than two.
    @spec posted_value(ViewModel.Field.t(), map()) :: {:ok, term()} | :error
    defp posted_value(%ViewModel.Field{hidden?: true}, _posted), do: :error
    defp posted_value(%ViewModel.Field{readonly?: true}, _posted), do: :error
    defp posted_value(%ViewModel.Field{key: key}, posted), do: Map.fetch(posted, key)

    @doc """
    The candidate list a host offered for one field, or `[]`.

    Keyed `{type_name, field_key}`: the values belong to a field of a
    block TYPE rather than to a block, because which values exist is a
    property of the deployment and the same field on two blocks of one
    type offers the same ones.
    """
    @spec candidates_for(map(), StatifierBlocks.Block.type_name(), ViewModel.Field.t()) :: term()
    def candidates_for(field_candidates, type_name, %ViewModel.Field{key: key})
        when is_map(field_candidates) do
      Map.get(field_candidates, {type_name, key}, [])
    end

    # A `:duration` is the one field type with a value that means "no key".
    # The reading is `StatifierBlocks.DurationInput`'s so that the control
    # and this function cannot disagree about which strings are empty.
    @spec omitted?(StatifierBlocks.BlockType.field_type(), term()) :: boolean()
    defp omitted?(:duration, value), do: not DurationInput.set?(value)
    defp omitted?(_type, _value), do: false

    # `BlockType` has `put_value/3` and no counterpart, because until now
    # nothing needed one. Deleting is the same walk with `Map.delete/2` at
    # the end, expressed through the public pair rather than by re-deriving
    # the traversal: a path naming something that is not there leaves the
    # config alone, which is what an omitted key already looks like.
    @spec drop_value(StatifierBlocks.Block.config(), BlockType.value_path()) ::
            StatifierBlocks.Block.config()
    defp drop_value(config, [key]) when is_map(config) and is_binary(key),
      do: Map.delete(config, key)

    defp drop_value(config, path) do
      {parent, last} = Enum.split(path, -1)

      with [key] when is_binary(key) <- last,
           {:ok, map} when is_map(map) <- BlockType.fetch_value(config, parent) do
        BlockType.put_value(config, parent, Map.delete(map, key))
      else
        _other -> config
      end
    end

    # One place spells the severity modifiers, and it is outside
    # `StatifierBlocks.Editor.*` so it is asserted with LiveView absent
    # (ADR-0005 decision 11, amended 2026-08-29 for `:info`).
    # A draft was never a command, so it cannot be undone - it can only be
    # thrown away, and that gesture has to exist somewhere. Naming the fields
    # is the other half: decision 9 commits a config as a UNIT, so a block
    # with two required fields is uncommittable until both are filled, and an
    # author who is told only "invalid" cannot tell that from a value the type
    # refused.
    @spec pending_sentence([ViewModel.Field.t()]) :: String.t()
    defp pending_sentence(fields) do
      labels = fields |> Enum.map_join(", ", & &1.label)

      "This block's config is committed as a unit, and #{labels} " <>
        "#{if length(fields) == 1, do: "is", else: "are"} not accepted yet."
    end

    # `sb-rd29`'s resolution step: a `config_key` off a source span is a
    # string that crossed a click, not a proof that this block's form still
    # has a field by that name - the selection could have moved to a
    # different block's span between the click and this render, or the
    # schema could have changed under it. Finding the field first and reading
    # its id back through `Field.input_id/1` is what keeps a stale or
    # mistargeted key from asking the browser to focus an element that is not
    # there, or, worse, one that is but belongs to someone else's field.
    @spec focus_input_id(ViewModel.Node.t(), String.t() | nil) :: String.t() | nil
    defp focus_input_id(_node, nil), do: nil

    defp focus_input_id(%ViewModel.Node{form: form}, key) do
      case form && Enum.find(form.fields, &(&1.key == key)) do
        nil -> nil
        field -> Field.input_id(field)
      end
    end

    # The hint is an `:expression` field's alone. Every other field type is
    # about something a fixture row does not bind - a duration, a flag, an
    # invoke type - so there is no path for a row's value to be an example
    # of, and dispatching on the type is what keeps this from becoming a
    # guess about what a key means (the rule the moduledoc of
    # `StatifierBlocks.Editor.Field` keeps for `placeholder`).
    #
    # The rows are the selected block's, read through `Shell.tables_for/2` -
    # the same reader the drawer's truth-table tab uses - so the two surfaces
    # cannot disagree about what a block's fixtures are.
    @spec fixture_hint(Shell.fixtures(), StatifierBlocks.Block.id(), ViewModel.Field.t()) ::
            Shell.fixture_hint() | nil
    defp fixture_hint(fixtures, block_id, %ViewModel.Field{type: :expression, value: value}),
      do: Shell.fixture_hint(fixtures, block_id, source_text(value))

    defp fixture_hint(_fixtures, _block_id, %ViewModel.Field{}), do: nil

    # An expression's stored value is the author's own source string, but a
    # field whose value has never been set carries `nil`, and a `:branch`
    # arm can carry whatever the document stored. Only a string names a path.
    @spec source_text(term()) :: String.t() | nil
    defp source_text(value) when is_binary(value), do: value
    defp source_text(_value), do: nil

    @spec severity_class(StatifierBlocks.Finding.t()) :: String.t()
    defp severity_class(finding), do: StatifierBlocks.Finding.severity_class(finding)
  end
end
