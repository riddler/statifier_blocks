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

    alias StatifierBlocks.BlockType
    alias StatifierBlocks.Editor.Field
    alias StatifierBlocks.ViewModel

    attr(:node, ViewModel.Node, required: true)
    attr(:target, :any, required: true)
    attr(:class, :string, default: nil)
    attr(:expression_component, :any, default: nil)

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
        <p :for={finding <- @node.form.unrouted} class={["sb-finding", severity_class(finding)]}>
          {finding.message}
        </p>
        <Field.field
          :for={field <- @node.form.fields}
          field={field}
          target={@target}
          expression_component={@expression_component}
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

        BlockType.put_value(config, ViewModel.Field.value_path(field), value)
      end)
    end

    # One place spells the severity modifiers, and it is outside
    # `StatifierBlocks.Editor.*` so it is asserted with LiveView absent
    # (ADR-0005 decision 11, amended 2026-08-29 for `:info`).
    @spec severity_class(StatifierBlocks.Finding.t()) :: String.t()
    defp severity_class(finding), do: StatifierBlocks.Finding.severity_class(finding)
  end
end
