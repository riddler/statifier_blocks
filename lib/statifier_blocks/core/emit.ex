defmodule StatifierBlocks.Core.Emit do
  @moduledoc """
  The SCXML shapes the `core.*` vocabulary compiles to (ADR-0004 decisions
  2-4), and the small builders the core types share.

  ## The one convention everything else rests on

  Decision 2 fixes that a block compiles to exactly one state and signals
  completion with `done.state.<state id>`. SCXML raises that event when a
  **compound** state's configuration enters a `<final>` child, so every core
  type emits a compound state carrying a `<final>` under the role `"done"`,
  and arranges its own work to reach it. That is the whole of what a parent
  needs: `StatifierBlocks.Compiler.Context` hands it a child's state id and
  done event, never the child's SCXML.

  Sequencing is therefore always the same shape - transitions **on the
  parent's own state**, one per adjacent pair:

      <state id="s_SEQ" initial="s_c1">
        <transition event="done.state.s_c1" target="s_c2"/>
        <transition event="done.state.s_c2" target="s_SEQ__done"/>
        ...c1's subtree... ...c2's subtree...
        <final id="s_SEQ__done"/>
      </state>

  A transition on a compound state fires while any descendant is active, so
  the parent can wire its children without any of them knowing they were
  wired. An empty run degenerates cleanly: `initial` points straight at the
  `<final>`, and entering the block completes it.

  ## Interrupts: two regions and a two-event protocol

  `core.group` and `core.resumable_group` have to run their body while
  interrupt handlers watch for events. A handler is a block like any other
  (decision 2 admits no exception), so it compiles to a state, and a state
  only sees events while it is active - which means the handlers must run
  **concurrently with the body**. The group therefore wraps both in a
  `<parallel>`: one region for the body, one region per handler.

  That leaves one problem. What a handler's arrival should *do* - abandon
  the group, or resume it - is the handler's `outcome` config, and decision
  4 deliberately keeps a child's config out of the parent's context. The
  group cannot read it and must not try.

  So the group wires **both** outcomes unconditionally and the handler picks
  one by raising an event:

      <transition event="statifier_blocks.interrupt.abandon" target="s_G__done"/>
      <transition event="statifier_blocks.interrupt.resume"  target="s_G__run"/>

  The handler `<raise>`s whichever its config names. Nesting behaves the way
  an author would expect for free: both groups carry the same two
  transitions, the raise happens inside the inner group's region, and SCXML
  selects the transition whose source is the deepest active state - the
  inner group's. A host interrupt handler joins the protocol by raising the
  same two events; `interrupt_events/0` is where they are named.

  `core.group` has nothing to remember, so its resume target is the
  `<parallel>` itself and the body restarts. `core.resumable_group` targets
  a `<history>` inside the body region instead, of the type its `history`
  config names - which is the whole of what that config buys, and why
  ADR-0002 decision 10 could leave it as one `:select` field.
  """

  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Emission

  @abandon "statifier_blocks.interrupt.abandon"
  @resume "statifier_blocks.interrupt.resume"

  @doc """
  The two events an interrupt handler raises to tell the group it sits in
  what to do. A host handler that wants to work inside `core.group` raises
  one of these; a host group that wants to admit `core.on_event` transitions
  on both.
  """
  @spec interrupt_events() :: %{abandon: String.t(), resume: String.t()}
  def interrupt_events, do: %{abandon: @abandon, resume: @resume}

  @doc "A `<state>`; `initial` is dropped when `nil`, which is how an atomic state is written."
  @spec state(String.t(), String.t() | nil, [Emission.node_t()]) :: Emission.t()
  def state(id, initial, children) do
    Emission.element("state", [{"id", id}, {"initial", initial}], children)
  end

  @doc "A `<final>`, the state whose entry raises the owning block's `done.state`."
  @spec final(String.t()) :: Emission.t()
  def final(id), do: Emission.element("final", [{"id", id}])

  @doc """
  A `<transition>`. `opts` carries `:event`, `:cond`, `:target` and
  `:internal`; an absent one is simply not written, so an eventless
  conditional transition and an unconditional one are the same builder.

  `internal: true` writes `type="internal"`, and every transition a
  container puts **on its own state targeting one of its descendants**
  needs it. A transition is external by default, and an external
  transition exits and re-enters its source even when the target is inside
  it - which for a `<parallel>`'s region means tearing down the other
  regions mid-flight. That is not a subtlety a block-type author should
  have to rediscover, so the builders below set it and this note says why.

  `cond_key` names the config field the `cond` came from verbatim, which
  is what makes an upstream expression error the author's typo rather than
  a bug in the block type (ADR-0004 decision 9). Pass it whenever the
  condition is an author's `:expression` field rather than something the
  type composed.
  """
  @spec transition(keyword(), [Emission.node_t()]) :: Emission.t()
  def transition(opts, children \\ []) do
    element =
      Emission.element(
        "transition",
        [
          {"cond", Keyword.get(opts, :cond)},
          {"event", Keyword.get(opts, :event)},
          {"target", Keyword.get(opts, :target)},
          {"type", if(Keyword.get(opts, :internal, false), do: "internal")}
        ],
        children
      )

    case Keyword.get(opts, :cond_key) do
      nil -> element
      key -> Emission.attribute_from_config(element, "cond", key)
    end
  end

  @doc """
  Sequences `summaries` and lands on `exit_target`.

  Returns `{initial, transitions, child_refs}`: the state to enter first
  (the first child, or `exit_target` for an empty run), one transition per
  adjacent pair plus one from the last child to `exit_target`, and a
  placeholder per child for the compiler to splice.

  Each transition is attributed to **the child it leaves**, not to the
  container that emitted it (ADR-0004 decision 5). "What happens after the
  authorize step" is the fact an author would recognise, so a finding
  against that transition belongs on the authorize block than on the sequence
  around it. Attribution carries no bytes, so this changes nothing about
  the generated chart.
  """
  @spec chain([Context.child_summary()], String.t()) ::
          {String.t(), [Emission.t()], [Emission.node_t()]}
  def chain(summaries, exit_target) do
    targets = Enum.map(summaries, & &1.state_id) ++ [exit_target]

    transitions =
      summaries
      |> Enum.zip(tl(targets))
      |> Enum.map(fn {summary, target} ->
        [event: summary.done_event, target: target, internal: true]
        |> transition()
        |> Emission.attributed_to(summary.block_id)
      end)

    {hd(targets), transitions, Enum.map(summaries, &Emission.child_ref(&1.block_id))}
  end

  @doc """
  The shape every plain ordered container emits: a compound state running
  `summaries` in order and finishing at its own `<final>`.
  """
  @spec ordered(Context.t(), [Context.child_summary()]) :: {:ok, Emission.t()}
  def ordered(%Context{} = ctx, summaries) do
    done = Context.done_id(ctx)
    {initial, transitions, refs} = chain(summaries, done)

    {:ok, state(ctx.state_id, initial, transitions ++ refs ++ [final(done)])}
  end

  @doc """
  The interruptible shape: the body in one region, each handler in its own,
  and the two-event protocol wired on the group's own state.

  `history` is `nil` for a group with nothing to remember, or `"shallow"` /
  `"deep"` for one that resumes where it left off.
  """
  @spec interruptible(Context.t(), String.t() | nil) ::
          {:ok, Emission.t()} | {:error, {:invalid_role, String.t(), String.t()}}
  def interruptible(%Context{} = ctx, history) do
    body = Context.children(ctx, "body")
    handlers = Context.children(ctx, "interrupts")

    if handlers == [] do
      ordered(ctx, body)
    else
      guarded(ctx, body, handlers, history)
    end
  end

  @spec guarded(
          Context.t(),
          [Context.child_summary()],
          [Context.child_summary()],
          String.t() | nil
        ) :: {:ok, Emission.t()} | {:error, {:invalid_role, String.t(), String.t()}}
  defp guarded(ctx, body, handlers, history) do
    done = Context.done_id(ctx)

    with {:ok, run} <- Context.role_id(ctx, "run"),
         {:ok, body_id} <- Context.role_id(ctx, "body"),
         {:ok, body_done} <- Context.role_id(ctx, "body_done"),
         {:ok, history_id} <- history_id(ctx, history) do
      {initial, transitions, refs} = chain(body, body_done)

      body_region =
        state(
          body_id,
          initial,
          transitions ++ refs ++ [final(body_done)] ++ history_child(history_id, history, initial)
        )

      regions = [body_region | Enum.map(handlers, &Emission.child_ref(&1.block_id))]

      children = [
        transition(event: "done.state." <> body_id, target: done, internal: true),
        transition(event: @abandon, target: done, internal: true),
        transition(event: @resume, target: history_id || run, internal: true),
        Emission.element("parallel", [{"id", run}], regions),
        final(done)
      ]

      {:ok, state(ctx.state_id, run, children)}
    end
  end

  @spec history_id(Context.t(), String.t() | nil) ::
          {:ok, String.t() | nil} | {:error, {:invalid_role, String.t(), String.t()}}
  defp history_id(_ctx, nil), do: {:ok, nil}
  defp history_id(ctx, _history), do: Context.role_id(ctx, "history")

  @spec history_child(String.t() | nil, String.t() | nil, String.t()) :: [Emission.t()]
  defp history_child(nil, _history, _initial), do: []

  defp history_child(id, history, initial) do
    [
      Emission.element("history", [{"id", id}, {"type", history}], [transition(target: initial)])
    ]
  end
end
