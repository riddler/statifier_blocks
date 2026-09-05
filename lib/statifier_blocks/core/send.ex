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

  **No cancel block, and there will not be one.** A cancel that names the
  send it cancels is a cross-subtree reference between blocks, which is
  the exact shape the umbrella's D13 refuses - outcome paths are slots,
  never ports, and connectors are rendered, never authored - as ADR-0001's
  tree invariant and ADR-0005's amendment 10a state at record level. The
  alternative that keeps the tree invariant is scope-shaped rather than
  reference-shaped, and that is the one the 2026-08-29 delayed-send
  lifetime ruling picked. So there is no `core.cancel` type, the palette
  gains no entry, and cancellation is the compiler's to emit rather than
  an author's to draw. The next section is what ships in its place.

  ## The send carries an id, and its scope cancels it

  The `<send>` carries `id="<this block's state id>__send"`, minted
  through the context under the role `"send"` the way ADR-0004 decision 3
  requires of every derived id. Nothing authors it: no config field names
  it, the editor gains no control, and a reader of the document never sees
  it. It exists so the send can be named later, because a send with no id
  is a send nothing can cancel.

  What cancels it is a `<cancel sendid="..."/>` the **compiler** emits in
  the `<onexit>` of the nearest enclosing scope state - the sequence or
  group this block sits in, not this block's own state, and the nearest
  one when scopes nest. A delayed send therefore lives exactly as long as
  the scope that meant it to. `StatifierBlocks.Compiler.Cancels` is where
  that emission lives and why it reads the id rather than the emitter.

  Upstream owns what the pair means at runtime: a pending delayed send is
  identified by `{session scope, send id}` and nothing else, and it lives
  until it fires, is cancelled, or its run is found not live at fire time
  (statifier-ex ADR-0054 decisions 3 and 4, ADR-0060 decision 3 for
  resume).

  ## The delay's stored form

  `delay` is the vocabulary's first optional duration, and "no delay" is
  neither a zero duration nor an unfinished field - an absent or empty
  `delay` emits no `delay` attribute at all, so the event goes out now.

  A present `delay` is stored in one spelling: the duration string the
  expression language reads (`30s`, `1h30m`, `2d`, `3d8h`). That is
  ADR-0005 decision 9 as amended 2026-09-05 (clause 9a, one grammar), and
  ADR-0002 decision 7's `:duration` field type is unchanged - it still
  holds a string, and what changed is which strings.
  `StatifierBlocks.Core.Duration` is where the compile lives and where the
  grammar's one home - predicator's own lexer - is read rather than
  mirrored.
  """

  @behaviour StatifierBlocks.BlockType

  alias StatifierBlocks.Block
  alias StatifierBlocks.Compiler.{Cancels, Context}
  alias StatifierBlocks.Core.{Config, Duration, Emit}
  alias StatifierBlocks.Emission

  @event_message "must be an event name, like signup.abandoned"
  @delay_message "must be a duration like 30s or 1h30m - or empty to send now"

  @impl true
  def current_version, do: 1

  @impl true
  def slots(_config), do: []

  @doc """
  The event first, then the delay.

  The delay's default is `""` and not a duration: a send with no delay is
  the ordinary case, and `core.wait`'s `1h` default would author a timer
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
  The event name, or `nil` (ADR-0002 amendment H6).

  Only the event. The delay is the other half of what this block does and
  it is deliberately not on the card: `core.wait` already owns the timer
  chip, and a second line reading `signup.abandoned after 2h` is a
  sentence rather than a summary and would not fit under the presentation
  cap in any case.

  A value that is not an event name is no chip rather than a chip nobody
  can read - the same reading `emit/2` gives it.

      iex> StatifierBlocks.Core.Send.summary(%{"event" => "signup.abandoned"})
      "signup.abandoned"

      iex> StatifierBlocks.Core.Send.summary(%{"event" => ""})
      nil
  """
  @impl true
  def summary(config) do
    event = Map.get(config, "event")
    if Config.event_name?(event), do: event, else: nil
  end

  @doc """
  A compound state whose entry sends the event and immediately goes final.

      <state id="s_blk_SND" initial="s_blk_SND__done">
        <onentry>
          <send delay="2h" event="signup.abandoned" id="s_blk_SND__send"/>
        </onentry>
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
  unchanged. The `delay` attribute's bytes did not - the stored string is
  parsed and rendered from the normalised value, so a stored `3h2h` emits
  as `5h` - and annotating it would point a runtime finding at a span the
  author never typed. `core.wait` leaves its own `delay` unannotated for
  the same reason.

  ## The `id`, and the half of the cancel that is not here

  `id` is minted with `Context.role_id/2` under
  `StatifierBlocks.Compiler.Cancels.armed_role/0`, so the one string the
  convention turns on is written once and read back once. It is emitted
  whether or not the send is delayed: ADR-0002's amendment states the
  descriptor's id unconditionally, and an id costs nothing on a send that
  fires now.

  The matching `<cancel>` is deliberately absent from this function. It
  belongs to the enclosing scope's state, which this block cannot reach -
  ADR-0004 decision 4 gives a block type no way to write into its parent,
  and it should not gain one for this. The compiler adds it on the
  parent's own pass; see the moduledoc and
  `StatifierBlocks.Compiler.Cancels`.
  """
  @impl true
  def emit(%Block{config: config}, context) do
    done = Context.done_id(context)

    with {:ok, id} <- Context.role_id(context, Cancels.armed_role()),
         {:ok, event} <- event(Map.get(config, "event")),
         {:ok, delay} <- delay(config) do
      send_element =
        "send"
        |> Emission.element([{"delay", delay}, {"event", event}, {"id", id}])
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
  # empty `delay` compiles to. Anything else is parsed to the expression
  # language's normalised duration and rendered from it as the attribute
  # `Statifier.Duration` reads.
  @spec delay(Block.config()) :: {:ok, String.t() | nil} | {:error, [{String.t(), String.t()}]}
  defp delay(config) do
    case Map.fetch(config, "delay") do
      :error -> {:ok, nil}
      {:ok, ""} -> {:ok, nil}
      {:ok, value} -> compiled(value)
    end
  end

  defp compiled(value) do
    case Duration.parse(value) do
      {:ok, parsed} -> {:ok, Duration.to_delay(parsed)}
      :error -> {:error, [{"delay", @delay_message}]}
    end
  end
end
