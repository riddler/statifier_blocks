defmodule StatifierBlocks.Core.Raise do
  @moduledoc """
  `core.raise`: a leaf that raises one event for an enclosing group's
  interrupt rail (ADR-0002 decision 10's amendment, section D).

  One config field, `event`. There is no slot and nothing to sequence -
  the block's whole job is to put one name on the internal queue and let
  whatever is listening decide what that means.

  ## PROPOSED emission (ADR-0002 amendment section D2, not yet ruled)

  Section D2 leaves two things open and assigns both to ADR-0004: whether
  a raise compiles to `<raise>` or to a zero-delay `<send>`, and whether a
  raise may carry a payload. This module proceeds on a **recorded
  proposal**, not a ruling:

    * it emits `<raise>`;
    * it carries no payload.

  **Why `<raise>`.** The event has to be in-session and synchronous: a
  raised event goes on the *internal* queue and is processed before any
  external event the session is holding, which is exactly the property the
  enclosing group's interrupt rail depends on, and the property
  `core.on_event` already relies on when it raises the two protocol events
  to tell its group what to do. A zero-delay `<send>` goes to the
  *external* queue instead - it would be observably different timing, not
  a spelling variant of the same thing.

  **Why no payload.** A payload field would need ADR-0002 decision 7's
  closed field-type set to grow, which section D2 says explicitly and which
  is not this module's call to make.

  A ruling that goes the other way on either point is a change to `emit/2`
  and its tests. Nothing in the declaration surface - `config_schema/1`,
  `slots/1`, `io/1` - turns on it, because none of those three describe how
  the event gets onto a queue.

  What D2 *did* settle, so a reader here is not misled: the send-to-catch
  relationship is deliberately not an edge in the document. It is two
  blocks naming one string, with the enclosing group's rail as where the
  catch lives - `core.raise` never names the handler it wakes, and never
  could, since which group is "enclosing" is a document-shape fact this
  type does not see.
  """

  @behaviour StatifierBlocks.BlockType

  alias StatifierBlocks.Block
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.{Config, Emit}
  alias StatifierBlocks.Emission

  @impl true
  def current_version, do: 1

  @impl true
  def slots(_config), do: []

  @impl true
  def config_schema(_config),
    do: [
      %{
        key: "event",
        type: :string,
        label: "Raise this event",
        required?: true,
        default: ""
      }
    ]

  @impl true
  def validate_config(config) do
    if Config.event_name?(Map.get(config, "event")) do
      :ok
    else
      {:error, [{"event", "must be an event name, like signup.abandoned"}]}
    end
  end

  @doc """
  A raise has one outcome, so there is no join to refuse: `produces` is
  absent rather than `:unknown`, the way `core.wait` - the other
  single-outcome leaf - declares its `io/1`.
  """
  @impl true
  def io(_config), do: %{kinds: [:step]}

  @impl true
  def palette_entry,
    do: %{
      label: "Raise",
      group: "Structure",
      description: "Raises an event for an enclosing group's interrupt rules.",
      icon: "megaphone",
      keywords: ["raise", "event", "signal", "interrupt", "abandon"],
      order: 8
    }

  @doc """
  A compound state whose entry raises `event` and immediately goes final.

      <state id="s_blk_RAI" initial="s_blk_RAI__done">
        <onentry><raise event="signup.abandoned"/></onentry>
        <final id="s_blk_RAI__done"/>
      </state>

  There is nothing here to sequence - the raise itself is instantaneous
  and the block's own state is done the moment it is entered - so `initial`
  points straight at the `<final>` and no auxiliary state is minted.

  `event` is annotated with `attribute_from_config/3`: the `<raise>`
  element is this block's own, but the attribute *value* is the author's,
  which is what puts an upstream finding against it on the author rather
  than on this type (ADR-0004 decision 9).
  """
  @impl true
  def emit(%Block{config: config}, context) do
    done = Context.done_id(context)

    with {:ok, event} <- event_name(Map.get(config, "event")) do
      raise_element =
        "raise"
        |> Emission.element([{"event", event}])
        |> Emission.attribute_from_config("event", "event")

      onentry = Emission.element("onentry", [], [raise_element])

      {:ok, Emit.state(context.state_id, done, [onentry, Emit.final(done)])}
    end
  end

  # `emit/2` has to answer for a config `validate_config/1` would reject
  # rather than raising on it - the compiler's Config stage makes that arm
  # unreachable in practice, never impossible (see `core.on_event`).
  defp event_name(event) do
    if Config.event_name?(event) do
      {:ok, event}
    else
      {:error, [{"event", "must be an event name, like signup.abandoned"}]}
    end
  end
end
