defmodule StatifierBlocks.Core.Wait do
  @moduledoc """
  `core.wait`: a leaf whose whole meaning is its config (ADR-0002 decision
  10).

  No slots, one `:duration` field. The duration is a string rather than a
  number of seconds because ADR-0001 decision 6 forbids floats in
  `config`, and a bare integer would have to carry its unit somewhere
  else.

  One spelling is accepted: the duration string the expression language
  reads (`"30s"`, `"1h30m"`, `"2d"`, `"3d8h"`), which is the form the
  author types. What was typed is what `config` holds, verbatim;
  `StatifierBlocks.Core.Duration` parses it and renders the `delay`
  attribute at emit time. That is ADR-0005 decision 9 as amended
  2026-09-05 (clause 9a, one grammar), and it is the whole of why a
  `"48h"` this type once refused is a duration and why a `"500ms"` it
  could not express now is one too.

  This type validates the *string*; it does not resolve it to a number of
  milliseconds, mint a timer, or know that durable timers exist. Turning it
  into a delayed send is the compiler's job.
  """

  @behaviour StatifierBlocks.BlockType

  alias StatifierBlocks.Block
  alias StatifierBlocks.Compiler.{Cancels, Context}
  alias StatifierBlocks.Core.{Duration, Emit}
  alias StatifierBlocks.Emission

  # One sentence at both refusal sites, naming what is accepted and
  # nothing else (ADR-0005 clause 9d). `core.send`'s own message reads the
  # same way and adds its "or empty to send now" - the shapes differ
  # because a wait's duration is required.
  @duration_message "must be a duration like 30s or 1h30m"

  @impl true
  def current_version, do: 1

  @impl true
  def slots(_config), do: []

  @impl true
  def config_schema(_config),
    do: [
      %{
        key: "duration",
        type: :duration,
        label: "Wait for",
        required?: true,
        default: "1h"
      }
    ]

  @impl true
  def validate_config(config) do
    case Map.fetch(config, "duration") do
      {:ok, duration} ->
        if Duration.duration?(duration) do
          :ok
        else
          {:error, [{"duration", @duration_message}]}
        end

      :error ->
        {:error, [{"duration", "required"}]}
    end
  end

  @doc """
  A wait constrains nothing and is constrained by nothing beyond being a
  step: it declares `kinds` and leaves `consumes` and `produces` to
  ADR-0003 decision 5's permissive default, since waiting transforms no
  data.
  """
  @impl true
  def io(_config), do: %{kinds: [:step]}

  @impl true
  def palette_entry,
    do: %{
      label: "Wait",
      group: "Structure",
      description: "Pauses for a fixed duration before continuing.",
      icon: "clock",
      keywords: ["delay", "timer", "pause", "sleep"],
      order: 5
    }

  @doc """
  `timer <duration>` for the stored duration, or `nil` (ADR-0002
  amendment H6).

  The stored bytes rather than the compiled ones: a `3h2h` emits as `5h`
  but the card reads `timer 3h2h`, showing the author their own spelling,
  which is what the inspector field beside it holds.

  Read with no default, exactly as `emit/2` reads it. A wait with no
  duration stored has nothing to say yet, and a card that filled in the
  schema's `1h` would be asserting a value while the finding
  `validate_config/1` files says the key is required.

      iex> StatifierBlocks.Core.Wait.summary(%{"duration" => "30s"})
      "timer 30s"

      iex> StatifierBlocks.Core.Wait.summary(%{})
      nil
  """
  @impl true
  def summary(config) do
    case Map.get(config, "duration") do
      duration when is_binary(duration) ->
        if String.trim(duration) == "", do: nil, else: "timer " <> duration

      _absent_or_malformed ->
        nil
    end
  end

  @doc """
  A compound state that sends itself a delayed event on entry and finishes
  when that event arrives.

      <state id="s_WAI" initial="s_WAI__waiting">
        <state id="s_WAI__waiting">
          <onentry><send delay="48h" event="statifier_blocks.wait.blk_WAI" id="s_WAI__send"/></onentry>
          <transition event="statifier_blocks.wait.blk_WAI" target="s_WAI__done"/>
        </state>
        <final id="s_WAI__done"/>
      </state>

  The event name carries the block id, so two waits in the same chart never
  wake each other. `<send>` names no `target`, which under spec 6.2.2 is
  the running session's own external queue - and a delayed send on that
  queue is exactly what `statifier_oban` turns into a durable timer. This
  type still does not know durable timers exist; it emits an ordinary
  delayed send and the host's session decides what backs it.

  ## The send id rides the reserved role

  The id is minted with `Context.role_id/2` under
  `StatifierBlocks.Compiler.Cancels.armed_role/0`, the same reserved role
  `core.send` mints under, so `StatifierBlocks.Compiler.Cancels` reaches
  this send as it reaches any other: a wait left before its delay elapses -
  by an interrupt, by a losing `complete: first` lane, by an abandoned
  group - has its timer cancelled in the enclosing scope's `<onexit>`. The
  wait's own state bounds only what the interpreter holds; a delayed send
  a durable host has already scheduled outlives the state that armed it
  unless something cancels it.

  ## The duration is compiled, not read out

  The stored value is the author's own spelling, so the emitted `delay`
  attribute is not simply those bytes: the string is parsed to the
  expression language's normalised duration and rendered from it. Both
  steps live in `StatifierBlocks.Core.Duration` - `parse/1` then
  `to_delay/1`, exactly the pair `core.send` calls - which is why the
  component-to-unit table that used to sit here is now in that module's
  moduledoc and nowhere else. Two duration tables would be two grammars
  the day one of them was edited.

  The attribute is left unannotated for the reason `core.send`'s emit
  writes out: ADR-0004 decision 9 annotates an attribute whose value is
  the author's verbatim, and these bytes are not - a repeated unit
  accumulates and a fraction expands, so `3h2h` emits `5h`.
  """
  @impl true
  def emit(%Block{id: block_id, config: config}, context) do
    done = Context.done_id(context)

    with {:ok, waiting} <- Context.role_id(context, "waiting"),
         {:ok, send_id} <- Context.role_id(context, Cancels.armed_role()),
         {:ok, delay} <- delay(Map.get(config, "duration")) do
      event = "statifier_blocks.wait." <> block_id

      send_element =
        Emission.element("send", [{"delay", delay}, {"event", event}, {"id", send_id}])

      armed =
        Emit.state(waiting, nil, [
          Emission.element("onentry", [], [send_element]),
          Emit.transition(event: event, target: done)
        ])

      {:ok, Emit.state(context.state_id, waiting, [armed, Emit.final(done)])}
    end
  end

  # `1h30m` -> `1h30m`, `3h2h` -> `5h`, `1.5s` -> `1s500ms`. Returns an
  # ordinary Emit finding rather than raising for a duration
  # `validate_config/1` would have rejected, since `emit/2` has to answer
  # for the config it was handed.
  @spec delay(term()) :: {:ok, String.t()} | {:error, [{String.t(), String.t()}]}
  defp delay(duration) do
    case Duration.parse(duration) do
      {:ok, parsed} -> {:ok, Duration.to_delay(parsed)}
      :error -> {:error, [{"duration", @duration_message}]}
    end
  end
end
