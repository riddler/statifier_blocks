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

  alias StatifierBlocks.Block
  alias StatifierBlocks.Core.{Config, Emit}

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

  # `slot_outcome_key`, exactly as `StatifierBlocks.Core.Group` declares it
  # and for that module's reason: the rules in `interrupts` are the same
  # `core.on_event` blocks, carrying the same config key.
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
      slot_style: %{"body" => :primary, "interrupts" => :secondary},
      slot_outcome_key: %{"interrupts" => "outcome"}
    }

  @doc """
  `StatifierBlocks.Core.Group`'s shape plus a `<history>` inside the body
  region, of the type `history` names. A `"resume"` handler targets that
  history rather than the `<parallel>`, so the body re-enters where it left
  off instead of restarting - which is the whole of what this config buys,
  and why ADR-0002 decision 10 could leave it as one `:select` field.

  A config carrying neither `"shallow"` nor `"deep"` is refused here as
  well as in `validate_config/1`. The compiler runs the Config stage first,
  so that arm is unreachable through `StatifierBlocks.Compiler`; it exists
  because `emit/2` is a total function of its arguments and has to answer
  for the config it was handed rather than for the one it assumed.
  """
  @impl true
  def emit(%Block{config: config}, context) do
    case Map.get(config, "history") do
      history when history in @history -> Emit.interruptible(context, history)
      _other -> {:error, [{"history", ~s(pick "shallow" or "deep")}]}
    end
  end
end
