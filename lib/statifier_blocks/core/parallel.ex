defmodule StatifierBlocks.Core.Parallel do
  @moduledoc """
  `core.parallel`: one slot per lane, with no ordering between the lanes
  (ADR-0002 decision 10).

  The second config-parameterized type. `config` carries an ordered
  `"lanes"` list of bare lane names, and each lane `name` becomes the slot
  `"lane_" <> name`:

      config = %{"lanes" => ["capture", "receipt"]}

      slots(config)
      #=> [{"lane_capture", :any, "capture"}, {"lane_receipt", :any, "receipt"}]

  A lane stores its **bare name** and the slot prefixes it, where
  `StatifierBlocks.Core.Branch`'s arms store the whole slot name. The
  asymmetry is not this type's choice: it is what the ADR-0001 worked
  example stores, and the stored bytes win over any tidier scheme.

  Lane slots are `:any` - a declared-but-empty lane is an ordinary
  intermediate state, not a finding - and the *order* of the lanes in
  config is presentation order only. Nothing about a parallel block gives
  its lanes a sequence; that is the whole point of it, and it is why
  `palette_entry/0` declares `layout: :columns` so the lanes render side by
  side (ADR-0005 decision 10).

  `produces` is `:unknown` for the same reason `core.branch`'s is: joining
  the lanes' outputs is a type lattice, and ADR-0003 decision 4 refuses to
  build one.

  ## `complete`: when the block is done

  A second config key, `"complete"`, picks the completion rule
  (ADR-0004's 2026-08-29 amendment, "`core.parallel` `complete: first`"):

    * `"all"` (the default, and what an absent key reads as) is the
      statifier-native rule - a `<parallel>` is done when every region is,
      so one transition on `done.state.<run>` needs no join logic.
    * `"first"` is the racing rule - the block is done at the *first*
      lane's completion, which is one transition per lane on the
      `<parallel>` element itself, each taken on that lane's own
      `done.state.<region id>`.

  The key is read through its default everywhere, so every
  `core.parallel` stored before it existed decodes, validates, and
  compiles to the byte it did before (ADR-0001 decision 6: a stored
  `null` is *not* an absent key and is still refused).
  """

  @behaviour StatifierBlocks.BlockType

  alias StatifierBlocks.Block
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.{Config, Emit}
  alias StatifierBlocks.Emission

  @complete ["all", "first"]
  @complete_message ~s(pick "all" or "first")

  @impl true
  def current_version, do: 1

  @doc """
  One `:any` slot per well-formed lane, in config order.

  Total for any config: a lane name that could not make a usable slot name
  is skipped rather than raised on, keeping ADR-0002 decision 6's stability
  rule true mid-edit.
  """
  @impl true
  def slots(config) do
    Enum.map(lanes(config), fn lane -> {"lane_" <> lane, :any, lane} end)
  end

  @impl true
  def config_schema(_config),
    do: [
      %{
        key: "lanes",
        type: {:list, :string},
        label: "Lanes",
        required?: true,
        default: []
      },
      %{
        key: "complete",
        type:
          {:select,
           [
             {"all", "All - when every lane is done"},
             {"first", "First - when any one lane is done"}
           ]},
        label: "Continue",
        required?: false,
        default: "all"
      }
    ]

  @doc """
  The lane findings, then the `complete` one.

  `complete` is read through its default, so an *absent* key validates
  exactly as it did before the key existed and a config that carries only
  lanes still answers with only lane findings. A stored `null` is not an
  absent key: `Map.get/3` hands the `nil` straight to `one_of/2`, which
  refuses it (ADR-0001 decision 6).
  """
  @impl true
  def validate_config(config) do
    combine(check_lanes_of(config), check_complete(config))
  end

  @spec combine(
          :ok | {:error, [{String.t(), String.t()}]},
          :ok | {:error, [{String.t(), String.t()}]}
        ) ::
          :ok | {:error, [{String.t(), String.t()}]}
  defp combine(:ok, :ok), do: :ok
  defp combine(lanes, complete), do: {:error, findings(lanes) ++ findings(complete)}

  defp findings(:ok), do: []
  defp findings({:error, findings}), do: findings

  defp check_complete(config) do
    if Config.one_of(complete(config), @complete) do
      :ok
    else
      {:error, [{"complete", @complete_message}]}
    end
  end

  defp check_lanes_of(config) do
    case Map.get(config, "lanes", []) do
      lanes when is_list(lanes) -> check_lanes(lanes)
      _other -> {:error, [{"lanes", "must be a list of lane names"}]}
    end
  end

  defp check_lanes(lanes) do
    lanes
    |> Enum.reduce({[], MapSet.new()}, &check_lane/2)
    |> elem(0)
    |> Config.verdict()
  end

  defp check_lane(lane, {findings, seen}) do
    cond do
      not Config.identifier?(lane) ->
        {[
           {"lanes", ~s(a lane name must be a bare lowercase identifier, like "capture")}
           | findings
         ], seen}

      MapSet.member?(seen, lane) ->
        {[{"lanes", ~s(two lanes cannot share the name "#{lane}")} | findings], seen}

      true ->
        {findings, MapSet.put(seen, lane)}
    end
  end

  @impl true
  def io(config) do
    accepts =
      config
      |> slots()
      |> Map.new(fn {slot, _arity, _label} -> {slot, [:step]} end)

    %{kinds: [:step], produces: :unknown, slot_accepts: accepts}
  end

  @impl true
  def palette_entry,
    do: %{
      label: "Parallel",
      group: "Structure",
      description: "Runs its lanes at the same time, in no particular order.",
      icon: "view-columns",
      keywords: ["lanes", "concurrent", "fork", "at once"],
      order: 4,
      layout: :columns,
      join_label: &__MODULE__.join_label/1
    }

  @doc """
  What the join marker under the lanes reads, given the block's config.

  A `paletteEntry` callback rather than a case in a renderer: the type
  owns its own completion rule and therefore its own words, and nothing
  on the layout path learns the string `"core.parallel"` (ADR-0005
  decision 10). A host type that fans into lanes with a rule of its own
  declares its own callback and gets its own.

      iex> StatifierBlocks.Core.Parallel.join_label(%{"complete" => "first"})
      "continue at first"

      iex> StatifierBlocks.Core.Parallel.join_label(%{})
      "continue when all"
  """
  @spec join_label(Block.config()) :: String.t()
  def join_label(config) do
    if complete(config) == "first", do: "continue at first", else: "continue when all"
  end

  @doc """
  A compound state wrapping one `<parallel>` whose regions are the lanes
  (ADR-0004 decision 2), each region sequencing its own steps and finishing
  at its own `<final>`.

      <state id="s_PAR" initial="s_PAR__run">
        <transition event="done.state.s_PAR__run" target="s_PAR__done"/>
        <parallel id="s_PAR__run">
          <state id="s_PAR__lane_capture" initial="...">...<final id="s_PAR__done_lane_capture"/></state>
          <state id="s_PAR__lane_receipt" ...>
        </parallel>
        <final id="s_PAR__done"/>
      </state>

  A `<parallel>` is done when every region is, so the outer state needs one
  transition and no join logic of its own.

  The two role families are `lane_<name>` and `done_lane_<name>`. They
  cannot collide with each other whatever a lane is called, because they
  differ in their first token rather than their last - a lane named
  `capture_done` mints `lane_capture_done` and `done_lane_capture_done`, and neither is
  any other lane's id.

  A parallel with no lanes emits no `<parallel>` at all: an empty one is
  not valid SCXML, and "run nothing concurrently" is done the moment it
  starts, so the block compiles to a state whose `initial` is its `<final>`.
  That is true of both completion rules: there is no first lane to win
  and no last lane to wait for, so `complete` moves no byte of it.

  ## `complete: "first"`: one transition per lane, on the `<parallel>`

  The racing rule replaces the single `done.state.<run>` transition with
  one transition **per lane**, placed on the `<parallel>` element itself
  (ADR-0004's 2026-08-29 amendment, P1):

      <state id="s_PAR" initial="s_PAR__run">
        <parallel id="s_PAR__run">
          <transition event="done.state.s_PAR__lane_authorize" target="s_PAR__done"/>
          <transition event="done.state.s_PAR__lane_fraud_check" target="s_PAR__done"/>
          <state id="s_PAR__lane_authorize" ...>
          <state id="s_PAR__lane_fraud_check" ...>
        </parallel>
        <final id="s_PAR__done"/>
      </state>

  Three properties of that shape are decisions rather than accidents.

  **The transitions come before the regions.** Document order among the
  children of one element is the emitter's to fix, and this is the fixed
  position: the joins ahead of the lanes they join, which is the order the
  upstream ruling's worked chart is written in and the order the wrapper
  already uses for its own transition. One position, chosen once, is what
  ADR-0004 decision 6's determinism asks for; the transition set stays a
  pure function of the ordered lane list either way.

  **They are external.** The block's done `<final>` is a sibling of the
  `<parallel>`, not a descendant of it, so there is nothing for
  `type="internal"` to preserve - and exiting the `<parallel>`, with every
  region still in it, is precisely the effect wanted. Appendix D then runs
  each losing region's `<onexit>` and raises one `CancelInvoke` per live
  invocation it owns (P2). None of that is this package's to emit.

  **The `done.state.<run>` transition is dropped, not kept.** It could
  never be taken: `done.state.<run>` is raised only once every region is
  final, and the first region to reach its own `<final>` raises
  `done.state.<region>` first and exits the `<parallel>` on it. Keeping it
  would write bytes that cannot fire, which a reader of the chart - or of
  the provenance map - would have to explain to themselves. P1 says the
  transition set is per lane and that nothing joins, so it is per lane and
  nothing joins.
  """
  @impl true
  def emit(%Block{config: config}, context) do
    done = Context.done_id(context)
    complete = complete(config)

    cond do
      complete not in @complete ->
        {:error, [{"complete", @complete_message}]}

      lanes(config) == [] ->
        {:ok, Emit.state(context.state_id, done, [Emit.final(done)])}

      true ->
        with {:ok, run} <- Context.role_id(context, "run"),
             {:ok, regions} <- regions(context, lanes(config)) do
          {:ok, Emit.state(context.state_id, run, running(complete, run, regions, done))}
        end
    end
  end

  # The wrapper's children, under each completion rule. `regions` is the
  # `{region id, region}` list in lane order, which is the only thing the
  # two rules disagree about reading.
  @spec running(String.t(), String.t(), [{String.t(), Emission.t()}], String.t()) :: [
          Emission.t()
        ]
  defp running("all", run, regions, done) do
    [
      Emit.transition(event: "done.state." <> run, target: done, internal: true),
      Emission.element("parallel", [{"id", run}], Enum.map(regions, &elem(&1, 1))),
      Emit.final(done)
    ]
  end

  defp running("first", run, regions, done) do
    joins =
      Enum.map(regions, fn {region_id, _region} ->
        Emit.transition(event: "done.state." <> region_id, target: done)
      end)

    [
      Emission.element("parallel", [{"id", run}], joins ++ Enum.map(regions, &elem(&1, 1))),
      Emit.final(done)
    ]
  end

  defp regions(context, lanes) do
    Enum.reduce_while(lanes, {:ok, []}, fn lane, {:ok, acc} ->
      case region(context, lane) do
        {:ok, region} -> {:cont, {:ok, [region | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp region(context, lane) do
    with {:ok, region_id} <- Context.role_id(context, "lane_" <> lane),
         {:ok, region_done} <- Context.role_id(context, "done_lane_" <> lane) do
      {initial, transitions, refs} =
        Emit.chain(Context.children(context, "lane_" <> lane), region_done)

      {:ok,
       {region_id,
        Emit.state(region_id, initial, transitions ++ refs ++ [Emit.final(region_done)])}}
    end
  end

  # The stored completion rule, read through its default.
  defp complete(config), do: Map.get(config, "complete", "all")

  # The well-formed lane names of `config`, in stored order.
  defp lanes(config) do
    config
    |> Map.get("lanes", [])
    |> List.wrap()
    |> Enum.filter(&Config.identifier?/1)
    |> Enum.uniq()
  end
end
