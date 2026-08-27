defmodule StatifierBlocks.Core.Parallel do
  @moduledoc """
  `core.parallel`: one slot per lane, with no ordering between the lanes
  (ADR-0002 decision 10).

  The second config-parameterized type. `config` carries an ordered
  `"lanes"` list of bare lane names, and each lane `name` becomes the slot
  `"lane_" <> name`:

      config = %{"lanes" => ["crm", "nurture"]}

      slots(config)
      #=> [{"lane_crm", :any, "crm"}, {"lane_nurture", :any, "nurture"}]

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
  """

  @behaviour StatifierBlocks.BlockType

  alias StatifierBlocks.Block
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.{Config, Emit}
  alias StatifierBlocks.Emission

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
      }
    ]

  @impl true
  def validate_config(config) do
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
        {[{"lanes", ~s(a lane name must be a bare lowercase identifier, like "crm")} | findings],
         seen}

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
      layout: :columns
    }

  @doc """
  A compound state wrapping one `<parallel>` whose regions are the lanes
  (ADR-0004 decision 2), each region sequencing its own steps and finishing
  at its own `<final>`.

      <state id="s_PAR" initial="s_PAR__run">
        <transition event="done.state.s_PAR__run" target="s_PAR__done"/>
        <parallel id="s_PAR__run">
          <state id="s_PAR__lane_crm" initial="...">...<final id="s_PAR__done_lane_crm"/></state>
          <state id="s_PAR__lane_nurture" ...>
        </parallel>
        <final id="s_PAR__done"/>
      </state>

  A `<parallel>` is done when every region is, so the outer state needs one
  transition and no join logic of its own.

  The two role families are `lane_<name>` and `done_lane_<name>`. They
  cannot collide with each other whatever a lane is called, because they
  differ in their first token rather than their last - a lane named
  `crm_done` mints `lane_crm_done` and `done_lane_crm_done`, and neither is
  any other lane's id.

  A parallel with no lanes emits no `<parallel>` at all: an empty one is
  not valid SCXML, and "run nothing concurrently" is done the moment it
  starts, so the block compiles to a state whose `initial` is its `<final>`.
  """
  @impl true
  def emit(%Block{config: config}, context) do
    done = Context.done_id(context)

    case lanes(config) do
      [] ->
        {:ok, Emit.state(context.state_id, done, [Emit.final(done)])}

      lanes ->
        with {:ok, run} <- Context.role_id(context, "run"),
             {:ok, regions} <- regions(context, lanes) do
          children = [
            Emit.transition(event: "done.state." <> run, target: done, internal: true),
            Emission.element("parallel", [{"id", run}], regions),
            Emit.final(done)
          ]

          {:ok, Emit.state(context.state_id, run, children)}
        end
    end
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

      {:ok, Emit.state(region_id, initial, transitions ++ refs ++ [Emit.final(region_done)])}
    end
  end

  # The well-formed lane names of `config`, in stored order.
  defp lanes(config) do
    config
    |> Map.get("lanes", [])
    |> List.wrap()
    |> Enum.filter(&Config.identifier?/1)
    |> Enum.uniq()
  end
end
