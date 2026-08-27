defmodule StatifierBlocks.Core.Branch do
  @moduledoc """
  `core.branch`: one slot per condition arm, plus `otherwise` (ADR-0002
  decision 10).

  The config-parameterized case ADR-0001 decision 5 exists for. `config`
  carries an ordered `"arms"` list, each arm a `%{"slot" => name, "cond" =>
  expression}` pair, and `slots/1` returns one slot per arm in that order
  followed by `otherwise`:

      config = %{"arms" => [%{"slot" => "arm_qualified", "cond" => "score > 80"}]}

      slots(config)
      #=> [{"arm_qualified", :at_least_one, ~s(When "qualified")},
      #=>  {"otherwise", :any, "Otherwise"}]

  Three details worth naming, because each is a place a reader would
  reasonably guess the other way:

    * **An arm stores its whole slot name**, `"arm_qualified"`, not the
      suffix. ADR-0002 decision 10's table says "slot suffix"; the ADR-0001
      worked example stores the full name, and the stored bytes are what
      this type has to read.
    * **Arms are `:at_least_one`, `otherwise` is `:any`.** ADR-0002
      decision 6's arity table names "a branch arm that must do something"
      as `:at_least_one`'s motivating case, and an empty arm compiles to a
      condition guarding nothing. An empty `otherwise` is the ordinary
      "and if not, carry on".
    * **`produces` is `:unknown`, not a join of the arms.** ADR-0003
      decision 4 is explicit: combining the arms' outputs is a type
      lattice, and this package does not build one.

  ## The schema is one `:expression` field per arm

  `config_schema/1` returns a condition field per arm, keyed by that arm's
  slot name - which is unique within the block, and is the same key
  `validate_config/1` reports findings against, so a finding routes to the
  field it is about (ADR-0005 decision 11's `{:config, block_id, key}`
  anchor).

  The `"arms"` list itself is deliberately not a field. Adding and removing
  an arm changes the block's slot set, which makes it an editor command
  over the document rather than a value typed into a form.
  """

  @behaviour StatifierBlocks.BlockType

  alias StatifierBlocks.Core.Config

  @impl true
  def current_version, do: 1

  @doc """
  One slot per well-formed arm, in config order, then `otherwise`.

  Total for any config, including config `validate_config/1` rejects:
  malformed arms are skipped rather than raised on, which is what keeps
  ADR-0002 decision 6's stability rule true while an author is mid-edit.
  """
  @impl true
  def slots(config) do
    arm_slots =
      Enum.map(arms(config), fn %{"slot" => slot} -> {slot, :at_least_one, arm_label(slot)} end)

    arm_slots ++ [{"otherwise", :any, "Otherwise"}]
  end

  @impl true
  def config_schema(config) do
    Enum.map(arms(config), fn %{"slot" => slot} ->
      %{
        key: slot,
        type: :expression,
        label: arm_label(slot),
        required?: true,
        default: ""
      }
    end)
  end

  @impl true
  def validate_config(config) do
    case Map.get(config, "arms", []) do
      arms when is_list(arms) -> check_arms(arms)
      _other -> {:error, [{"arms", "must be a list of arms"}]}
    end
  end

  defp check_arms(arms) do
    arms
    |> Enum.reduce({[], MapSet.new()}, &check_arm/2)
    |> elem(0)
    |> Config.verdict()
  end

  defp check_arm(%{"slot" => slot, "cond" => condition} = _arm, {findings, seen}) do
    cond do
      not Config.arm_slot?(slot) ->
        {[{"arms", ~s(an arm's slot must look like "arm_qualified")} | findings], seen}

      MapSet.member?(seen, slot) ->
        {[{slot, "two arms cannot share one slot"} | findings], seen}

      not Config.non_empty_string?(condition) ->
        {[{slot, "needs a condition expression"} | findings], MapSet.put(seen, slot)}

      true ->
        {findings, MapSet.put(seen, slot)}
    end
  end

  defp check_arm(_arm, {findings, seen}) do
    {[{"arms", ~s(every arm needs a "slot" and a "cond")} | findings], seen}
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
      label: "Branch",
      group: "Structure",
      description: "Takes the first arm whose condition holds, or otherwise.",
      icon: "arrows-right-left",
      keywords: ["if", "condition", "else", "when"],
      order: 3,
      layout: :stack
    }

  @doc """
  Two datasets and one condition evaluated against both, so a palette panel
  can show what an arm's expression does before the author commits to it.

  > #### Provisional: the accepted spellings are not settled {: .warning}
  >
  > PROVISIONAL - see ADR-0002 decision 9. The atom-keyed spelling below
  > comes from an amendment to that decision which has not been accepted.
  > Until it is, treat the shape as the intended target rather than a
  > settled contract. That this callback exists, and returns `term()`, is
  > settled either way.

  This is the one core type whose examples earn a bundle on their own:
  every other structural type arranges blocks and has nothing to evaluate,
  and statifier-ui's own `docs/fixture-bundles.md` names `core.sequence` as
  its example of a fragment that ships no examples.
  """
  @impl true
  def fixtures do
    %{
      datasets: %{
        "qualified" => %{"score" => 92},
        "unqualified" => %{"score" => 12}
      },
      expressions: %{
        "qualifies" => %{
          "source" => "score > 80",
          "expect" => %{"qualified" => true, "unqualified" => false}
        }
      }
    }
  end

  @impl true
  def emit(block, _context), do: Config.emit_deferred(block)

  # The well-formed arms of `config`, in stored order. Anything that is not
  # a map carrying a usable slot name is dropped: `slots/1` and
  # `config_schema/1` both have to answer for config `validate_config/1`
  # rejects, and neither may raise doing it.
  defp arms(config) do
    config
    |> Map.get("arms", [])
    |> List.wrap()
    |> Enum.filter(fn
      %{"slot" => slot} -> Config.arm_slot?(slot)
      _other -> false
    end)
    |> Enum.uniq_by(fn %{"slot" => slot} -> slot end)
  end

  # `"arm_qualified"` reads as `When "qualified"` - the suffix is the name
  # the author gave the arm.
  defp arm_label("arm_" <> suffix), do: ~s(When "#{suffix}")
end
