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

    ## Known gap: a field whose key does not address its value

    This function writes `config[field.key]`, and `StatifierBlocks.ViewModel`
    reads the same place to fill the control. That is the whole of the
    relationship ADR-0002 decision 7 and ADR-0005 decision 9 describe between
    a `field_decl`'s `key` and the value it edits, and it holds for every
    field type this package ships **except one**: `Core.Branch.config_schema/1`
    declares one `:expression` field per arm, keyed by the arm's own slot
    name, while the condition it edits lives at `config["arms"][i]["cond"]`.
    So a branch's condition fields render empty and are not editable here.

    That is a gap in the block type's own contract rather than something this
    component may paper over - inferring "a key of the form `arm_*` means
    reach into the `arms` list" would be the editor branching on a block
    type's internals, which is exactly the operator pre-decision ADR-0005
    exists to hold. It is reported against the records that own it. What this
    function guarantees in the meantime is the part that matters: the `arms`
    key survives every edit, so nothing is lost while the contract is settled.
    """
    @spec decode([ViewModel.Field.t()], map(), StatifierBlocks.Block.config()) ::
            StatifierBlocks.Block.config()
    def decode(fields, params, base \\ %{}) when is_list(fields) and is_map(params) do
      posted = Map.get(params, "config", %{})

      Enum.reduce(fields, base, fn %ViewModel.Field{} = field, config ->
        case Map.fetch(posted, field.key) do
          {:ok, raw} -> Map.put(config, field.key, Field.decode(field.type, raw))
          :error -> Map.put(config, field.key, field.value)
        end
      end)
    end

    @spec severity_class(StatifierBlocks.Finding.t()) :: String.t()
    defp severity_class(%StatifierBlocks.Finding{severity: :warning}), do: "sb-finding--warning"
    defp severity_class(%StatifierBlocks.Finding{}), do: "sb-finding--error"
  end
end
