defmodule StatifierBlocks.Core.ResumableGroup do
  @moduledoc """
  `core.resumable_group`: a group whose `config` carries a history mode
  (ADR-0002 decision 10).

  The same two slots as `StatifierBlocks.Core.Group` - `body` and
  `interrupts` - plus one `:select` field deciding what re-entering the
  group after an interrupt returns to:

  | `history` | Means |
  |---|---|
  | `"shallow"` | re-enter at the top-level step the group was last in |
  | `"deep"` | re-enter at the exact position, however deeply nested |

  The mode is *only* config. ADR-0005 decision 10 is explicit that it needs
  no editor support whatsoever: it renders through the ordinary form
  machinery like any other `:select`, and the presentation metadata this
  type carries is about its two slots, not about resuming.

  `history` is required rather than defaulted-when-absent. The schema
  declares a default of `"shallow"`, so the editor fills it in on insert,
  and a stored document missing it is a finding an author can see and fix -
  which is the outcome a silent default would hide, on the one field whose
  value changes where a workflow resumes.
  """

  @behaviour StatifierBlocks.BlockType

  alias StatifierBlocks.Core.Config

  @history ["shallow", "deep"]

  @impl true
  def current_version, do: 1

  @impl true
  def slots(_config),
    do: [
      {"body", :any, "Steps"},
      {"interrupts", :any, "Interrupt rules"}
    ]

  @impl true
  def config_schema(_config),
    do: [
      %{
        key: "history",
        type:
          {:select,
           [
             {"shallow", "Shallow - the last top-level step"},
             {"deep", "Deep - the exact position"}
           ]},
        label: "Resume at",
        required?: true,
        default: "shallow"
      }
    ]

  @impl true
  def validate_config(config) do
    if Config.one_of(Map.get(config, "history"), @history) do
      :ok
    else
      {:error, [{"history", ~s(pick "shallow" or "deep")}]}
    end
  end

  @impl true
  def io(_config),
    do: %{
      kinds: [:step],
      slot_accepts: %{"body" => [:step], "interrupts" => [:interrupt_handler]}
    }

  @impl true
  def palette_entry,
    do: %{
      label: "Resumable group",
      group: "Structure",
      description: "A group that remembers where it was when it resumes.",
      icon: "arrow-path",
      keywords: ["history", "resume", "interrupt"],
      order: 2,
      layout: :stack,
      slot_style: %{"body" => :primary, "interrupts" => :secondary}
    }

  @impl true
  def emit(block, _context), do: Config.emit_deferred(block)
end
