defmodule StatifierBlocks.Core.Send do
  @moduledoc """
  `core.send`: a leaf step that names an event and says **when**.

  ADR-0002 decision 10 carries the row, through its 2026-08-29 amendment
  (section G2): `slots(config)` is `[]`, the config is `event` and an
  optional `delay`, and the type has the single default outcome.

  Two config fields: `event`, in the same grammar `core.raise` and
  `core.on_event` speak, and `delay`, an **optional** duration.

  ## Why this is not `core.raise` with a `delay` key

  `core.raise` names an event and hands control on, now: the event goes on
  the *internal* queue and is processed before anything else the session is
  holding, which is the property an enclosing group's interrupt rail
  depends on. A delayed send goes on the *external* queue, outlives the
  step that armed it, has to survive a restart, and is turned into a
  durable timer by infrastructure outside the interpreter (statifier-ex
  `docs/durable-timers.md`, ADR-0054/0059; the `sob-` lane). A `delay` key
  that quietly turned a raise into a durable timer would make
  `core.raise`'s whole note false half the time, so they are two types.

  ## The block finishes when the send is **armed**

  This is what separates `core.send` from `core.wait`. A wait keeps the
  chart live for the duration; a send arms an event and completes in the
  same macrostep. So there is still one outcome and still no join to
  refuse - `io/1` leaves `produces` absent rather than `:unknown`, the way
  `core.raise` and `core.wait` do.

  ## Two things it deliberately does not declare

  **No `target`.** What a target may name is not this repo's decision:
  session identity is statifier-ex's (ADR-0052) and reaching the host is
  the invoke seam st-ADR-0051 defines, which this vocabulary already spells
  `core.invoke`. A config key that validates nothing is a proposal made by
  accident. Absent a `target`, spec 6.2.2 puts the event on the running
  session's own external queue, which is exactly what `statifier_oban`
  turns into a durable timer.

  **No cancel - and that is a recorded gap, not an oversight.** A delayed
  send this block arms is never cancelled by anything this package emits:
  no `<cancel>`, and no `sendid` an author could name. A cancel names the
  send it cancels, which makes it a cross-subtree reference to another
  block - the exact shape ADR-0005 decision 13 refused - and the
  alternative that keeps the tree invariant is scope-shaped rather than
  reference-shaped: a delayed send is cancelled when the region that armed
  it is left. Which of those is right is the delayed-send lifetime ruling,
  filed here as **`sb-b4f`** and mirrored to statifier-ex as `st-q3ud`. It
  is out of scope for campaign 014 and nothing here should grow a cancel
  until it is ruled. The consequence a reader needs today: an armed send
  fires even if the block, its group, or the whole chart moved on.

  ## The delay's stored form

  `delay` is the vocabulary's first optional duration, and "no delay" is
  neither `PT0S` nor an unfinished field - an absent or empty `delay` emits
  no `delay` attribute at all, so the event goes out now.

  A present `delay` may be stored in **either** spelling: ISO-8601
  (`PT2H`), or a predicator duration string (`1h30m`, `2d`, `3d8h`). That
  two-spelling stored form is campaign 014's D4 proposal, filed as
  `sb-709` and implemented in the spike's duration control; it is a
  **recorded proposal**, not a ruling, and ADR-0002 decision 7's
  `:duration` field type is unchanged. `StatifierBlocks.Core.Duration` is
  where the compile lives and where the grammar's one home - predicator's
  own lexer - is read rather than mirrored.
  """

  @behaviour StatifierBlocks.BlockType

  alias StatifierBlocks.Block
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.{Config, Duration, Emit}
  alias StatifierBlocks.Emission

  @event_message "must be an event name, like signup.abandoned"
  @delay_message "must be a duration - 1h30m, 2d or PT2H - or empty to send now"

  @impl true
  def current_version, do: 1

  @impl true
  def slots(_config), do: []

  @doc """
  The event first, then the delay.

  The delay's default is `""` and not a duration: a send with no delay is
  the ordinary case, and `core.wait`'s `PT1H` default would author a timer
  nobody asked for.
  """
  @impl true
  def config_schema(_config),
    do: [
      %{
        key: "event",
        type: :string,
        label: "Send this event",
        required?: true,
        default: ""
      },
      %{
        key: "delay",
        type: :duration,
        label: "After",
        required?: false,
        default: ""
      }
    ]

  @impl true
  def validate_config(config) do
    []
    |> check_event(config)
    |> check_delay(config)
    |> Config.verdict()
  end

  defp check_event(findings, config) do
    if Config.event_name?(Map.get(config, "event")) do
      findings
    else
      [{"event", @event_message} | findings]
    end
  end

  # An absent key and the field's own default are both "no delay", and the
  # default is what the config form writes into every block of this type,
  # so `""` cannot be a finding. A STORED `nil` is a different thing from
  # an absent key under ADR-0001 decision 6 and reaches the refusal arm.
  defp check_delay(findings, config) do
    case Map.fetch(config, "delay") do
      :error -> findings
      {:ok, ""} -> findings
      {:ok, value} -> delay_finding(findings, value)
    end
  end

  defp delay_finding(findings, value) do
    if Duration.duration?(value), do: findings, else: [{"delay", @delay_message} | findings]
  end

  @doc """
  `core.raise`'s `io/1` exactly, and for `core.raise`'s reason: one
  outcome, so `produces` is absent rather than `:unknown`. A send reads
  nothing through the type flow - its event name and its delay are its
  own config - so there is no `consumes` either.
  """
  @impl true
  def io(_config), do: %{kinds: [:step]}

  @doc """
  The spike's descriptor declares a static `sends` badge here. ADR-0005
  decision 10's `palette_entry/0` key set has no `badge`, so there is
  nothing to declare it in yet and the icon carries the whole visual
  signal - a Phase-B gap the spike's own note already records.
  """
  @impl true
  def palette_entry,
    do: %{
      label: "Send",
      group: "Structure",
      description: "Sends an event, now or after a delay.",
      icon: "paper-airplane",
      keywords: ["send", "event", "delay", "later", "deadline", "arm"],
      order: 10
    }

  @doc """
  A compound state whose entry sends the event and immediately goes final.

      <state id="s_blk_SND" initial="s_blk_SND__done">
        <onentry><send delay="2h" event="signup.abandoned"/></onentry>
        <final id="s_blk_SND__done"/>
      </state>

  There is nothing to sequence - arming the send is instantaneous and the
  block is done the moment it is entered - so `initial` points straight at
  the `<final>` and no auxiliary state is minted. That is `core.raise`'s
  shape with a different element inside the `<onentry>`, which is the
  right way round: the difference between the two types is which queue the
  event lands on, not how long the block lasts.

  With no delay the `<send>` carries no `delay` attribute at all, so the
  event goes out on the current macrostep. `Emission.element/3` drops a
  `nil` attribute, which is how "no delay" and `delay=""` stay
  indistinguishable in the emitted bytes.

  ## `event` is attributed and `delay` is not

  ADR-0004 decision 9's annotation is for an attribute whose value is the
  author's **verbatim**. `event` is: those bytes came out of the config
  unchanged. The `delay` attribute's bytes did not - a stored `PT2H`
  emits as `2h`, and a stored `1h30m` is canonicalised through ISO-8601
  before it is rendered - so annotating it would point a runtime finding
  at a span the author never typed. `core.wait` leaves its own `delay`
  unannotated for the same reason.

  ## No `<cancel>`, and no `id` to cancel by

  The `<send>` is deliberately anonymous: minting a `sendid` here would be
  half of a cancel mechanism whose other half `sb-b4f` (mirrored as
  statifier-ex `st-q3ud`) has not ruled on, and a half-built one is worse
  than none. See the moduledoc.
  """
  @impl true
  def emit(%Block{config: config}, context) do
    done = Context.done_id(context)

    with {:ok, event} <- event(Map.get(config, "event")),
         {:ok, delay} <- delay(config) do
      send_element =
        "send"
        |> Emission.element([{"delay", delay}, {"event", event}])
        |> Emission.attribute_from_config("event", "event")

      onentry = Emission.element("onentry", [], [send_element])

      {:ok, Emit.state(context.state_id, done, [onentry, Emit.final(done)])}
    end
  end

  # `emit/2` has to answer for a config `validate_config/1` would reject
  # rather than raising on it - the compiler's Config stage makes these
  # arms unreachable in practice, never impossible (see `core.on_event`).
  defp event(event) do
    if Config.event_name?(event) do
      {:ok, event}
    else
      {:error, [{"event", @event_message}]}
    end
  end

  # `nil` here means "write no attribute", which is what an absent or
  # empty `delay` compiles to. Anything else is canonicalised to ISO-8601
  # (D4's compile step, an identity for a value already stored that way)
  # and then rendered as the shorthand `Statifier.Duration` reads.
  @spec delay(Block.config()) :: {:ok, String.t() | nil} | {:error, [{String.t(), String.t()}]}
  defp delay(config) do
    case Map.fetch(config, "delay") do
      :error -> {:ok, nil}
      {:ok, ""} -> {:ok, nil}
      {:ok, value} -> compiled(value)
    end
  end

  defp compiled(value) do
    case Duration.to_iso(value) do
      {:ok, iso} -> {:ok, Duration.to_delay(iso)}
      :error -> {:error, [{"delay", @delay_message}]}
    end
  end
end
