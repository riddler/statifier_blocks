defmodule StatifierBlocks.Core.Branch do
  @moduledoc """
  `core.branch`: one slot per condition arm, plus `otherwise` (ADR-0002
  decision 10) and `undecided` (ADR-0012 decision 2).

  The config-parameterized case ADR-0001 decision 5 exists for. `config`
  carries an ordered `"arms"` list, each arm a `%{"slot" => name, "cond" =>
  expression}` pair, and `slots/1` returns one slot per arm in that order
  followed by `otherwise` and `undecided`:

      config = %{"arms" => [%{"slot" => "arm_approved", "cond" => "budget_remaining > amount"}]}

      slots(config)
      #=> [{"arm_approved", :at_least_one, ~s(When "approved")},
      #=>  {"otherwise", :any, "Otherwise"},
      #=>  {"undecided", :any, "Cannot be decided"}]

  ## The third slot is the reading, not a third destination

  A predicator condition has three readings and the compiled chart used to
  have two destinations. A comparison against an operand it cannot compare
  - an unbound datamodel path being the ordinary case - produces neither
  `true` nor `false` but predicator's `:undefined` sentinel, which the
  engine turns into "the transition is not taken, plus one
  `error.execution`". So an undecided condition behaved exactly as a false
  one. ADR-0012 gives that reading a slot of its own, and the whole of the
  compiled difference is one synthesized guard transition - see `emit/2`.

  Wiring is what turns the difference on: a branch that leaves `undecided`
  empty compiles to the bytes it compiled to at 0.20.0, `error.execution`
  included (ADR-0012 decision 3).

  Three details worth naming, because each is a place a reader would
  reasonably guess the other way:

    * **`undecided` is a slot, not an outcome.** `outcomes/1` is
      untouched: `slots/1` says where children live and `outcomes/1` says
      how finishing can differ (ADR-0002 amendment A2). An undecided
      condition changes which children run; it does not change how the
      branch finishes.
    * **An arm stores its whole slot name**, `"arm_approved"`, not the
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

  The condition itself is not stored under that key, though: it lives at
  `config["arms"][i]["cond"]`, so each field also declares the `value_path`
  ADR-0002 decision 7 was amended to carry (2026-08-27) -
  `["arms", i, "cond"]`, with `i` the arm's index in the **stored** list.
  Key and value path are two different questions about one field, and this
  is the core type that has to answer them differently: the editor reads
  and writes the condition through the path while findings and the form
  control keep addressing the arm by name.

  The `"arms"` list itself is deliberately not a field. Adding and removing
  an arm changes the block's slot set, which makes it an editor command
  over the document rather than a value typed into a form.
  """

  @behaviour StatifierBlocks.BlockType

  alias StatifierBlocks.Block
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.{Config, Emit}

  @impl true
  def current_version, do: 1

  @doc """
  One slot per well-formed arm, in config order, then `otherwise`, then
  `undecided`.

  Total for any config, including config `validate_config/1` rejects:
  malformed arms are skipped rather than raised on, which is what keeps
  ADR-0002 decision 6's stability rule true while an author is mid-edit.

  `undecided` is ADR-0012 decision 2: a slot rather than an outcome,
  `:any` for the same reason `otherwise` is, and labelled
  `"Cannot be decided"` because that label is the whole of the
  explanation an author gets in the editor. It cannot collide with an
  arm, whose slot name must match `arm_[a-z][a-z0-9_]*`.
  """
  @impl true
  def slots(config) do
    arm_slots =
      Enum.map(arms(config), fn %{"slot" => slot} -> {slot, :at_least_one, arm_label(slot)} end)

    arm_slots ++ [{"otherwise", :any, "Otherwise"}, {"undecided", :any, "Cannot be decided"}]
  end

  @doc """
  One `:expression` condition field per arm, keyed by the arm's slot name
  and reading through `value_path: ["arms", index, "cond"]`.

  `index` is the arm's position in the **stored** list rather than among
  the well-formed ones, so an arm below a malformed one still addresses
  its own condition while an author is mid-edit. See the moduledoc for why
  the key and the path answer two different questions.
  """
  @impl true
  def config_schema(config) do
    Enum.map(indexed_arms(config), fn {%{"slot" => slot}, index} ->
      %{
        key: slot,
        type: :expression,
        label: arm_label(slot),
        required?: true,
        default: "",
        value_path: ["arms", index, "cond"]
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
        {[{"arms", ~s(an arm's slot must look like "arm_approved")} | findings], seen}

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
  `N arms + otherwise`, counting the well-formed arms (ADR-0002 amendment
  H6).

  A count rather than a list of conditions: an arm's condition is an
  expression, and an expression is not a chip. `otherwise` is named
  rather than counted because it is always there - `slots/1` appends it
  to every branch, including one with no arms at all, and a card reading
  `1 arm` would be under-reporting the paths out of the block by one.

  Counted through the same filter `slots/1` and `config_schema/1` read
  arms through, so a malformed arm an author is mid-edit on is not
  counted and the card agrees with the slot list.

  `undecided` is not named here, in either direction. ADR-0012 decision 9
  asks for `"1 arm + otherwise + undecided"` on a branch that **wires**
  the slot, and this callback cannot answer that: `@callback
  summary(Block.config())` is handed the config alone
  (`lib/statifier_blocks/block_type.ex:609`), and whether a slot holds
  children is a fact about the block's `slots` map rather than its
  config. Widening the callback to see the block is a contract change no
  record has asked for, so the card reads exactly as it did at 0.20.0 -
  which is decision 9's own answer for every unwired branch, and an
  under-report by one for a wired one.

      iex> StatifierBlocks.Core.Branch.summary(%{"arms" => [%{"slot" => "arm_approved", "cond" => "x"}]})
      "1 arm + otherwise"

      iex> StatifierBlocks.Core.Branch.summary(%{})
      nil
  """
  @impl true
  def summary(config) do
    case length(arms(config)) do
      0 -> nil
      1 -> "1 arm + otherwise"
      count -> "#{count} arms + otherwise"
    end
  end

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
        "approved" => %{"budget_remaining" => 500, "amount" => 120},
        "declined" => %{"budget_remaining" => 100, "amount" => 340}
      },
      expressions: %{
        "approves" => %{
          "source" => "budget_remaining > amount",
          "expect" => %{"approved" => true, "declined" => false}
        }
      }
    }
  end

  @doc """
  A compound state whose `initial` is a transient `pick` state carrying one
  conditional transition per arm, in config order, then an unconditional
  one for `otherwise` (ADR-0004 decision 2 names this shape).

      <state id="s_BR" initial="s_BR__pick">
        <state id="s_BR__pick">
          <transition cond="budget_remaining &gt; amount" target="s_blk_A"/>
          <transition target="s_blk_B"/>
        </state>
        <transition event="done.state.s_blk_A" target="s_BR__done"/>
        ...
        <final id="s_BR__done"/>
      </state>

  An arm's `cond` is the author's `:expression` config passed through
  verbatim into predicator's datamodel - the compiler ships no expression
  checking of its own (ADR-0004 decision 9), so a typo there surfaces as an
  upstream compile error routed back through provenance by sb-qz0.

  Each arm's steps are sequenced the same way a `core.sequence`'s are, and
  every arm's last step transitions to the block's own `<final>`, so a
  branch is done when whichever arm it took is done. An empty `otherwise`
  transitions there directly.

  ## The `undecided` guard, when the slot is wired

  A branch whose `undecided` slot holds at least one child emits **one**
  extra transition, and it sits after every arm and before `otherwise`
  (ADR-0012 decision 4). Its condition is composed from the arms' own
  sources:

      not ((c1) === false and (c2) === false and ... and (cn) === false)

  Strict equality is the one comparison predicator answers with a boolean
  when handed its `:undefined` sentinel, so each conjunct is `true`
  exactly when that arm decided `false`, and the negation is `true`
  exactly when at least one arm did not decide (ADR-0012 decision 5).
  Ordering is what keeps the guard that simple: by the time it is reached
  no arm decided `true`, so "some arm was undecided" is all that is left
  to test, and an earlier undecided arm never shadows a later decided one
  (decision 6).

  Two things the guard deliberately does not do. It does not rewrite the
  arms' own transitions into `(ci) === true`, because a prefix on the
  author's source would offset every provenance span composed inside it;
  the arms keep the author's bytes. And it carries **no `cond_key`**,
  because it is the type's composition rather than an author's
  `:expression` field - a typo in `ci` surfaces on that arm's own
  transition, which does carry the key.

  An arm that *errors* rather than going undecided makes the guard error
  the same way, so the guard is not taken and the block falls to
  `otherwise` - which is where that arm already sent it. Wiring the slot
  therefore adds a second `error.execution` for such an arm and routes
  nothing differently (ADR-0012 decisions 5 and 7). A branch with no
  usable condition emits no guard at all.
  """
  @impl true
  def emit(%Block{config: config}, context) do
    done = Context.done_id(context)

    with {:ok, pick} <- Context.role_id(context, "pick") do
      branches =
        arm_branches(config, context) ++
          guard_branch(config, Context.children(context, "undecided")) ++
          [{nil, nil, Context.children(context, "otherwise")}]

      picks =
        Enum.map(branches, fn {condition, key, children} ->
          Emit.transition(cond: condition, cond_key: key, target: entry(children, done))
        end)

      chained = Enum.map(branches, fn {_cond, _key, children} -> Emit.chain(children, done) end)
      transitions = Enum.flat_map(chained, fn {_initial, transitions, _refs} -> transitions end)
      refs = Enum.flat_map(chained, fn {_initial, _transitions, refs} -> refs end)

      children =
        [Emit.state(pick, nil, picks)] ++ transitions ++ refs ++ [Emit.final(done)]

      {:ok, Emit.state(context.state_id, pick, children)}
    end
  end

  # `{cond, config key, children}` per well-formed arm, in config order.
  # `arms/1` has already dropped anything that could not name a slot, and
  # `slots/1` declared the same list, so every slot named here is one the
  # compiler walked.
  #
  # The config key is the **arm's slot name**, because that is what
  # `config_schema/1` keys the arm's `:expression` field by and therefore
  # what an editor anchors a finding to (ADR-0005 decision 11). ADR-0004's
  # worked example writes `key: "arms"` in its illustration, which predates
  # this type's per-arm schema; the key that routes a finding to the field
  # the author typed into is the one that matters, and it is this one.
  defp arm_branches(config, context) do
    Enum.map(arms(config), fn %{"slot" => slot} = arm ->
      {Map.get(arm, "cond"), slot, Context.children(context, slot)}
    end)
  end

  # `[]` or the one guard branch of ADR-0012 decisions 4 and 5, in the
  # same `{cond, config key, children}` shape the arms use so it takes its
  # place in the emission by position alone.
  #
  # Two conditions have to hold before a guard is emitted, and each maps to
  # a sentence in the record. The slot has to be **wired**, because an
  # unwired one compiles to 0.20.0's bytes (decision 3). And there has to be
  # at least one condition that could go undecided: "a branch with no
  # well-formed arm emits no guard transition" (decision 5).
  #
  # The `key` is `nil`, which is `Emit.transition/2`'s rule for a condition
  # the type composed rather than one the author typed.
  defp guard_branch(_config, []), do: []

  defp guard_branch(config, children) do
    case arm_conditions(config) do
      [] ->
        []

      conditions ->
        conjunction = Enum.map_join(conditions, " and ", &"(#{&1}) === false")
        [{"not (#{conjunction})", nil, children}]
    end
  end

  # The arms' conditions, in config order, read through the same filter
  # `slots/1` and `arm_branches/2` read arms through, and then narrowed to
  # the arms that actually carry a condition.
  #
  # That second step is forced rather than chosen: `arms/1` admits an arm
  # whose `"cond"` is missing or blank - `validate_config/1` reports it, but
  # `slots/1` may not raise on config an author is mid-edit on - and such an
  # arm compiles to an *unconditional* transition ahead of the guard, which
  # makes the guard unreachable anyway. Splicing its empty source into the
  # conjunction would emit `(() === false)` and fail the whole document's
  # upstream compile, so a branch mid-edit would take the rest of the
  # document down with it.
  defp arm_conditions(config) do
    config
    |> arms()
    |> Enum.map(&Map.get(&1, "cond"))
    |> Enum.filter(&Config.non_empty_string?/1)
  end

  defp entry([], done), do: done
  defp entry([first | _rest], _done), do: first.state_id

  # The well-formed arms of `config`, in stored order. Anything that is not
  # a map carrying a usable slot name is dropped: `slots/1` and
  # `config_schema/1` both have to answer for config `validate_config/1`
  # rejects, and neither may raise doing it.
  defp arms(config) do
    config |> indexed_arms() |> Enum.map(&elem(&1, 0))
  end

  # The same arms, each paired with **its index in the stored list** rather
  # than its index among the well-formed ones. That distinction is the
  # whole point of pairing them: the two numbers differ the moment an
  # author leaves a malformed arm above a good one mid-edit, and a
  # `value_path` built from the filtered position would then address a
  # different arm's condition.
  defp indexed_arms(config) do
    config
    |> Map.get("arms", [])
    |> List.wrap()
    |> Enum.with_index()
    |> Enum.filter(fn
      {%{"slot" => slot}, _index} -> Config.arm_slot?(slot)
      _other -> false
    end)
    |> Enum.uniq_by(fn {%{"slot" => slot}, _index} -> slot end)
  end

  # `"arm_approved"` reads as `When "approved"` - the suffix is the name
  # the author gave the arm.
  defp arm_label("arm_" <> suffix), do: ~s(When "#{suffix}")
end
