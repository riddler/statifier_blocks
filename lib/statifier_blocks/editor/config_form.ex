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

    `form.unrouted` renders at the head. That bucket exists because
    `Core.Branch.config_schema/1` keys one field per arm by the arm's own
    slot name while `validate_config/1` also emits findings keyed `"arms"` -
    a key matching no field, because adding or removing an arm is a document
    edit, not a form value. Rendering it here is what stops such a finding
    from silently having nowhere to go.
    """

    use Phoenix.Component

    alias StatifierBlocks.{BlockType, DurationInput}
    alias StatifierBlocks.Editor.Field
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

    attr(:pending, :list,
      default: [],
      doc: """
      The fields whose typed value is not in the document, in schema order.
      Empty when the block has no outstanding draft.
      """
    )

    @doc "One block's form: unrouted findings, then a control per schema field."
    def config_form(assigns) do
      ~H"""
      <form
        id={"sb-form-" <> @node.block_id}
        class={["sb-form", @class]}
        data-block-id={@node.block_id}
        phx-change="config-change"
        phx-submit="config-change"
        phx-target={@target}
      >
        <input type="hidden" name="block-id" value={@node.block_id} />
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
          :for={field <- @node.form.fields}
          field={field}
          target={@target}
          expression_component={@expression_component}
          invoke_types={@invoke_types}
          path_candidates={@path_candidates}
          value_candidates={@value_candidates}
        />
      </form>
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
    never-set field are the same value - there is no `PT0S` and no third
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

      Enum.reduce(fields, base, fn %ViewModel.Field{} = field, config ->
        value =
          case Map.fetch(posted, field.key) do
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

    @spec severity_class(StatifierBlocks.Finding.t()) :: String.t()
    defp severity_class(finding), do: StatifierBlocks.Finding.severity_class(finding)
  end
end
