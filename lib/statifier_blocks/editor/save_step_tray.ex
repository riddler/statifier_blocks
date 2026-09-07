if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.SaveStepTray do
    @moduledoc """
    The marking step of the "Save as a step" gesture (ADR-0005 part (iii),
    amended 2026-09-07, clause `18E`).

    `18E` says the proposed params are the values the author marks, and every
    value differing from its field's default where they mark none. So the
    gesture cannot be a single button - there is a choice in it - and it does
    not need to be more than a list: one checkbox per config field in the
    selected subtree, a Save, and a Cancel.

    What it deliberately does **not** draw is a name field or a preview.
    Naming the type is the host's act (`15E`), and a package that drew a name
    field would be drawing a decision it cannot make.

    It is a presentation module in the sense every other file beside it is:
    it renders what it is handed and decides nothing. Which rows exist, which
    boxes are ticked, and what Save does are `StatifierBlocks.Editor`'s.
    """

    use Phoenix.Component

    attr(:rows, :list,
      required: true,
      doc: """
      One entry per block in the selected subtree - `%{block_id:, label:,
      fields: [%{key:, label:, marked?:}]}` - built by the editor from the
      palette's own `config_schema/1`, so the fields the author sees here are
      the fields their form draws.
      """
    )

    attr(:target, :any, required: true)

    @doc "The tray, or nothing at all when no gesture is open."
    @spec save_step_tray(map()) :: Phoenix.LiveView.Rendered.t()
    def save_step_tray(assigns) do
      ~H"""
      <section class="sb-save-step" aria-label="Save as a step">
        <p class="sb-save-step__hint">
          Tick the values this step should ask for. Tick none and every value
          that differs from its default is asked for.
        </p>
        <div :for={row <- @rows} class="sb-save-step__block">
          <p class="sb-save-step__block-label">{row.label}</p>
          <label :for={field <- row.fields} class="sb-save-step__field">
            <input
              type="checkbox"
              checked={field.marked?}
              phx-click="save-as-step-mark"
              phx-target={@target}
              phx-value-block-id={row.block_id}
              phx-value-field-key={field.key}
            />
            {field.label}
          </label>
        </div>
        <div class="sb-save-step__actions">
          <button
            type="button"
            class="sb-button sb-save-step__confirm"
            phx-click="save-as-step-confirm"
            phx-target={@target}
          >
            Save as a step
          </button>
          <button
            type="button"
            class="sb-button sb-save-step__cancel"
            phx-click="save-as-step-cancel"
            phx-target={@target}
          >
            Cancel
          </button>
        </div>
      </section>
      """
    end
  end
end
