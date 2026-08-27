defmodule StatifierBlocks.AssignabilityTest do
  @moduledoc """
  Phase 1: the four structural primitives ADR-0003 decision 5 defaults and
  decision 3 defines. Phase 3: the ordered data-flow relation
  (`assignable?/3`) and `inbound_type/4`, including the `produces`
  resolution it depends on. Phase 4: `check/5`, decision 7's one decision
  function. `valid_targets/4` and `validate/3` are later phases and are not
  exercised here.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Assignability, AssignabilityFixtures, Block, Document, Palette}
  alias StatifierBlocks.AssignabilityFixtures.{Deny, Widens}
  alias StatifierBlocks.BlockTypeFixtures.Minimal

  defmodule Step do
    @moduledoc "A leaf block tagged `:step`, nothing else."

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []
    @impl true
    def config_schema(_config), do: []
    @impl true
    def validate_config(_config), do: :ok
    @impl true
    def io(_config), do: %{kinds: [:step]}
    @impl true
    def emit(_block, _context), do: {:error, :not_implemented}
  end

  defmodule Handler do
    @moduledoc "A leaf block tagged `:interrupt_handler`, nothing else."

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []
    @impl true
    def config_schema(_config), do: []
    @impl true
    def validate_config(_config), do: :ok
    @impl true
    def io(_config), do: %{kinds: [:interrupt_handler]}
    @impl true
    def emit(_block, _context), do: {:error, :not_implemented}
  end

  defmodule Group do
    @moduledoc """
    A container with two slots: `"body"` accepts `:step` only, `"interrupts"`
    accepts `:interrupt_handler` only - the two-kind palette Phase 1's test
    exercises both directions over.
    """

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: [{"body", :any, "Body"}, {"interrupts", :any, "Interrupts"}]
    @impl true
    def config_schema(_config), do: []
    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def io(_config),
      do: %{
        kinds: [:step],
        slot_accepts: %{"body" => [:step], "interrupts" => [:interrupt_handler]}
      }

    @impl true
    def emit(_block, _context), do: {:error, :not_implemented}
  end

  defmodule Anything do
    @moduledoc "A container whose slot declares no `:slot_accepts` entry."

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: [{"body", :any, "Body"}]
    @impl true
    def config_schema(_config), do: []
    @impl true
    def validate_config(_config), do: :ok
    @impl true
    def io(_config), do: %{kinds: [:step]}
    @impl true
    def emit(_block, _context), do: {:error, :not_implemented}
  end

  describe "the four defaults, for a module with no io/1" do
    # sabotage: change io/2's else branch from `%{}` to a non-empty map ->
    # this assertion goes red
    test "io/2 is %{} when io/1 is absent" do
      assert Assignability.io(Minimal, %{}) == %{}
    end

    # sabotage: change kinds/2's default from `[:step]` to `[]` -> this
    # assertion goes red
    test "kinds/2 defaults to [:step] when io/1 is absent" do
      assert Assignability.kinds(Minimal, %{}) == [:step]
    end

    # sabotage: change slot_accepts/3's default from `:any` to `[]` -> this
    # assertion goes red
    test "slot_accepts/3 defaults to :any when io/1 is absent" do
      assert Assignability.slot_accepts(Minimal, %{}, "body") == :any
    end

    # sabotage: n/a directly - this is the composition of the two defaults
    # above (kinds/2 [:step], slot_accepts/3 :any), and either sabotage
    # above already reds it. Recorded to pin the composed behaviour.
    test "admits?/3 admits an unconstrained child into an unconstrained slot" do
      assert Assignability.admits?({Minimal, %{}}, "body", {Minimal, %{}})
    end
  end

  describe "the :any arm" do
    # sabotage: change admits?/3's :any clause to `_ -> false` -> this
    # assertion goes red
    test "a slot with no :slot_accepts entry admits any kind" do
      assert Assignability.admits?({Anything, %{}}, "body", {Handler, %{}})
      assert Assignability.admits?({Anything, %{}}, "body", {Step, %{}})
    end
  end

  describe "the intersection arm" do
    # sabotage: change admits?/3's intersection clause from `Enum.any?` to
    # always `true` -> this assertion goes red
    test "a step is refused by a slot that accepts only interrupt handlers" do
      refute Assignability.admits?({Group, %{}}, "interrupts", {Step, %{}})
    end

    # sabotage: change admits?/3's intersection clause from `Enum.any?` to
    # always `false` -> this assertion goes red
    test "an interrupt handler is admitted by a slot that accepts it" do
      assert Assignability.admits?({Group, %{}}, "interrupts", {Handler, %{}})
    end
  end

  describe "both directions of a two-kind palette" do
    # sabotage: swap the "body" and "interrupts" entries in Group.io/1's
    # slot_accepts map -> both assertions below go red, each in the
    # direction that now admits the wrong kind
    test "a step goes in body and not interrupts; a handler goes the other way" do
      assert Assignability.admits?({Group, %{}}, "body", {Step, %{}})
      refute Assignability.admits?({Group, %{}}, "body", {Handler, %{}})
      assert Assignability.admits?({Group, %{}}, "interrupts", {Handler, %{}})
      refute Assignability.admits?({Group, %{}}, "interrupts", {Step, %{}})
    end
  end

  # Phase 3: a relation module that raises if it is ever consulted. Used to
  # prove step 4 is genuinely unreached until identity has already failed.
  defmodule RaisingRelation do
    @moduledoc false

    @behaviour StatifierBlocks.Assignability.Relation

    @impl true
    def assignable?(_produced, _consumed), do: raise("assignable?/2 should not be called here")
  end

  describe "assignable?/3 - :unknown permissiveness" do
    # sabotage: delete the `assignable?(_palette, :unknown, _consumed)` head
    # -> this assertion goes red
    test ":unknown produced is assignable to anything" do
      assert Assignability.assignable?(Palette.new(%{}), :unknown, "myapp.person")
    end

    # sabotage: delete the `assignable?(_palette, _produced, :unknown)` head
    # -> this assertion goes red
    test "anything is assignable to :unknown consumed" do
      assert Assignability.assignable?(Palette.new(%{}), "myapp.person", :unknown)
    end
  end

  describe "assignable?/3 - identity" do
    # sabotage: delete the `assignable?(_palette, same, same)` head -> this
    # assertion goes red (no module on the palette, so step 4 would refuse)
    test "identical type expressions are assignable with no module on the palette" do
      assert Assignability.assignable?(Palette.new(%{}), "myapp.person", "myapp.person")
    end

    # sabotage: change the identity clause's `do: true` to `do: false` ->
    # this assertion goes red
    test "host module is consulted only after identity has already failed" do
      palette = Palette.new(%{}, assignability: RaisingRelation)
      assert Assignability.assignable?(palette, "myapp.person", "myapp.person")
    end
  end

  describe "assignable?/3 - no module on the palette" do
    # sabotage: change `assignable?(%Palette{assignability: nil}, ...)` to
    # `do: true` -> this assertion goes red
    test "a non-identical pair is refused when the palette carries no relation" do
      refute Assignability.assignable?(Palette.new(%{}), "myapp.scored_lead", "myapp.person")
    end
  end

  describe "assignable?/3 - reflexivity, with and without a host module" do
    # sabotage: n/a directly - covered by the identity-clause sabotage above;
    # this pins the property across every palette shape the relation sees.
    test "every type expression is assignable to itself, whatever the palette carries" do
      for palette <- [
            Palette.new(%{}),
            Palette.new(%{}, assignability: Widens),
            Palette.new(%{}, assignability: Deny)
          ],
          type <- ["myapp.record", "myapp.lead", "myapp.scored_lead", "myapp.person"] do
        assert Assignability.assignable?(palette, type, type),
               "#{inspect(palette.assignability)} refused #{type} against itself"
      end
    end

    # sabotage: n/a directly - Deny answering false to everything cannot
    # narrow identity either, because step 2 never reaches it; pins that
    # the floor case is still reflexive.
    test "a module that denies everything cannot narrow reflexivity" do
      palette = Palette.new(%{}, assignability: Deny)
      assert Assignability.assignable?(palette, "myapp.person", "myapp.person")
    end
  end

  describe "assignable?/3 - monotonicity" do
    @fixed_types [:unknown, "myapp.record", "myapp.lead", "myapp.scored_lead", "myapp.person"]

    # sabotage: change the module-consulting clause to `do: false`
    # unconditionally -> this assertion goes red the moment a widened pair
    # (e.g. "myapp.scored_lead"/"myapp.person") is accepted without the
    # module but not with it - impossible, so instead sabotage by making
    # `Widens.assignable?/2` return `false` unconditionally, which removes
    # every non-identity pair from the with-module set and breaks the
    # inclusion this test asserts wherever the plain relation is not itself
    # a superset (it is not, since Widens legitimately grows the set)
    test "the with-module accepted set is a superset of the without-module set" do
      without = Palette.new(%{})
      with_module = Palette.new(%{}, assignability: Widens)

      for produced <- @fixed_types, consumed <- @fixed_types do
        if Assignability.assignable?(without, produced, consumed) do
          assert Assignability.assignable?(with_module, produced, consumed),
                 "#{inspect(produced)} -> #{inspect(consumed)} accepted without the module " <>
                   "but refused with it"
        end
      end

      # The floor case: a module that denies everything grows nothing, so
      # the "superset" is an equality.
      with_deny = Palette.new(%{}, assignability: Deny)

      for produced <- @fixed_types, consumed <- @fixed_types do
        assert Assignability.assignable?(without, produced, consumed) ==
                 Assignability.assignable?(with_deny, produced, consumed)
      end

      # And the module genuinely grows the set for at least one pair, so
      # this isn't a vacuous inclusion.
      assert Assignability.assignable?(with_module, "myapp.scored_lead", "myapp.person")
      refute Assignability.assignable?(without, "myapp.scored_lead", "myapp.person")
    end
  end

  describe "inbound_type/4 - index > 0" do
    # sabotage: change the `index > 0` guard to `index >= 0` -> this test
    # itself still passes (index 1 - 1 still finds the right sibling), but
    # every index-0 test below goes red instead, since `index - 1` is now
    # `-1` and `Enum.at/2` returns nil for it - confirming the guard, not
    # just the arithmetic, is load-bearing
    test "the inbound type is the resolved produces of the previous sibling" do
      enrich = Block.new("myapp.enrich", id: "blk_enr")
      score = Block.new("myapp.score", id: "blk_scr")
      root = Block.new("core.sequence", id: "blk_root", slots: %{"body" => [enrich, score]})
      document = Document.new(root, id: "bdoc_a")
      palette = AssignabilityFixtures.palette()

      assert Assignability.inbound_type(palette, document, {"blk_root", "body", 1}, %{}) ==
               "myapp.lead"
    end
  end

  describe "inbound_type/4 - index 0 inside a nested container" do
    # sabotage: change the `index == 0` clause to look up `parent_id`'s
    # inbound at the parent's *own* slot/index of 0 unconditionally instead
    # of recursing through `fetch_path/2` -> this assertion goes red for a
    # container that is itself nested past the root
    test "index 0 falls back to the parent block's own inbound type" do
      inner = Block.new("core.sequence", id: "blk_inner", slots: %{"body" => []})
      root = Block.new("core.sequence", id: "blk_root", slots: %{"body" => [inner]})
      document = Document.new(root, id: "bdoc_b")
      palette = AssignabilityFixtures.palette()
      ctx = %{entry_type: "myapp.record"}

      assert Assignability.inbound_type(palette, document, {"blk_inner", "body", 0}, ctx) ==
               "myapp.record"
    end
  end

  describe "inbound_type/4 - the root" do
    # sabotage: change `Map.get(ctx, :entry_type, :unknown)` to always
    # `:unknown` -> this assertion goes red
    test "the root takes ctx[:entry_type]" do
      root = Block.new("core.sequence", id: "blk_root", slots: %{"body" => []})
      document = Document.new(root, id: "bdoc_c")
      palette = AssignabilityFixtures.palette()

      assert Assignability.inbound_type(
               palette,
               document,
               {"blk_root", "body", 0},
               %{entry_type: "myapp.record"}
             ) == "myapp.record"
    end

    # sabotage: change the default from `:unknown` to `"myapp.record"` ->
    # this assertion goes red
    test "the root with no entry type in ctx is :unknown" do
      root = Block.new("core.sequence", id: "blk_root", slots: %{"body" => []})
      document = Document.new(root, id: "bdoc_d")
      palette = AssignabilityFixtures.palette()

      assert Assignability.inbound_type(palette, document, {"blk_root", "body", 0}, %{}) ==
               :unknown
    end
  end

  describe "inbound_type/4 - passthrough" do
    # sabotage: change `resolve_produces({:passthrough, slot}, ...)` to
    # return `:unknown` unconditionally -> this assertion goes red
    test "a passthrough sequence carries a type out past itself" do
      enrich = Block.new("myapp.enrich", id: "blk_enr")
      nested = Block.new("core.sequence", id: "blk_nested", slots: %{"body" => [enrich]})
      notify = Block.new("myapp.notify", id: "blk_not")

      root =
        Block.new("core.sequence", id: "blk_root", slots: %{"body" => [nested, notify]})

      document = Document.new(root, id: "bdoc_e")
      palette = AssignabilityFixtures.palette()

      assert Assignability.inbound_type(palette, document, {"blk_root", "body", 1}, %{}) ==
               "myapp.lead"
    end

    # sabotage: change the empty-slot branch of `resolve_produces` from
    # `own_inbound_type(...)` to `:unknown` -> this assertion goes red
    test "an empty passthrough sequence falls back to its own inbound type" do
      empty_seq = Block.new("core.sequence", id: "blk_empty", slots: %{"body" => []})
      notify = Block.new("myapp.notify", id: "blk_not")

      root =
        Block.new("core.sequence", id: "blk_root", slots: %{"body" => [empty_seq, notify]})

      document = Document.new(root, id: "bdoc_f")
      palette = AssignabilityFixtures.palette()
      ctx = %{entry_type: "myapp.record"}

      assert Assignability.inbound_type(palette, document, {"blk_root", "body", 1}, ctx) ==
               "myapp.record"
    end

    # sabotage: n/a directly (a wrong-answer sabotage is already covered
    # above) - this test exists to catch a *hang*, not a wrong value: were
    # `produces/4` to recurse without ever reaching a strictly earlier
    # pre-order position, this test would time out rather than assert red.
    # Confirmed by temporarily replacing the empty-slot fallback with a
    # self-call (`resolve_produces({:passthrough, slot}, ...)` again on the
    # same arguments) and observing the test hang past its timeout.
    test "a passthrough chain deep enough that a non-terminating implementation would hang completes" do
      depth = 2_000
      enrich = Block.new("myapp.enrich", id: "blk_leaf")

      chain =
        Enum.reduce(1..depth, enrich, fn i, acc ->
          Block.new("core.sequence", id: "blk_seq#{i}", slots: %{"body" => [acc]})
        end)

      notify = Block.new("myapp.notify", id: "blk_not")
      root = Block.new("core.sequence", id: "blk_root", slots: %{"body" => [chain, notify]})
      document = Document.new(root, id: "bdoc_g")
      palette = AssignabilityFixtures.palette()

      task =
        Task.async(fn ->
          Assignability.inbound_type(palette, document, {"blk_root", "body", 1}, %{})
        end)

      assert Task.await(task, 5_000) == "myapp.lead"
    end
  end

  describe "inbound_type/4 - totality" do
    # sabotage: remove the `nil -> :unknown` else arm from the `index > 0`
    # clause -> this raises instead of returning :unknown
    test "an unknown parent_id resolves to :unknown rather than raising" do
      root = Block.new("core.sequence", id: "blk_root", slots: %{"body" => []})
      document = Document.new(root, id: "bdoc_h")
      palette = AssignabilityFixtures.palette()

      assert Assignability.inbound_type(palette, document, {"blk_missing", "body", 1}, %{}) ==
               :unknown
    end

    # sabotage: same else arm - an index past the end of a real slot's
    # children must also degrade rather than raise
    test "an index past the end of the slot resolves to :unknown" do
      enrich = Block.new("myapp.enrich", id: "blk_enr")
      root = Block.new("core.sequence", id: "blk_root", slots: %{"body" => [enrich]})
      document = Document.new(root, id: "bdoc_i")
      palette = AssignabilityFixtures.palette()

      assert Assignability.inbound_type(palette, document, {"blk_root", "body", 5}, %{}) ==
               :unknown
    end
  end

  # A container whose `body` slot requires `:step` and whose `interrupts`
  # slot requires `:interrupt_handler` - `check/5`'s kind-admission tests
  # reuse this rather than adding a fourth palette-only fixture.
  defmodule GroupType do
    @moduledoc "A `core.group`-shaped container, under its own type name."

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: [{"body", :any, "Body"}, {"interrupts", :any, "Interrupts"}]
    @impl true
    def config_schema(_config), do: []
    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def io(_config),
      do: %{slot_accepts: %{"body" => [:step], "interrupts" => [:interrupt_handler]}}

    @impl true
    def emit(_block, _context), do: {:error, :not_implemented}
  end

  # An `io/1` that declares a `produces` no other fixture uses, so the
  # downstream seam test can construct a mismatch without needing a
  # candidate whose `produces` accidentally matches something the widening
  # relation already carries.
  defmodule Weird do
    @moduledoc "Produces `\"myapp.other\"`, wanted by nothing in the fixtures."

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []
    @impl true
    def config_schema(_config), do: []
    @impl true
    def validate_config(_config), do: :ok
    @impl true
    def io(_config), do: %{produces: "myapp.other"}
    @impl true
    def emit(_block, _context), do: {:error, :not_implemented}
  end

  describe "check/5 - insert" do
    # sabotage: change `kind_admission_finding/5`'s `if admits?(...)` branch
    # to always take the finding branch -> this assertion goes red
    test "an accepted insert is :ok" do
      root = Block.new("core.sequence", id: "blk_root", slots: %{"body" => []})
      document = Document.new(root, id: "bdoc_ins_ok")
      candidate = Block.new("myapp.enrich", id: "blk_cand")
      palette = AssignabilityFixtures.palette()

      assert Assignability.check(
               palette,
               document,
               {"blk_root", "body", 0},
               candidate,
               %{entry_type: "myapp.record"}
             ) == :ok
    end

    # sabotage: change `upstream_seam_finding/5` to always return `nil` ->
    # this assertion goes red
    test "a :type_mismatch on the upstream seam names the upstream block id" do
      score = Block.new("myapp.score", id: "blk_scr")
      root = Block.new("core.sequence", id: "blk_root", slots: %{"body" => [score]})
      document = Document.new(root, id: "bdoc_ins_upstream")
      candidate = Block.new("myapp.enrich", id: "blk_cand")
      palette = AssignabilityFixtures.palette()

      assert Assignability.check(palette, document, {"blk_root", "body", 1}, candidate, %{}) ==
               {:error,
                [{:type_mismatch, "blk_cand", "blk_scr", "myapp.scored_lead", "myapp.record"}]}
    end

    # sabotage: change `downstream_seam_finding/4` to always return `nil` ->
    # this assertion goes red
    test "a :type_mismatch on the downstream seam" do
      score = Block.new("myapp.score", id: "blk_scr")
      root = Block.new("core.sequence", id: "blk_root", slots: %{"body" => [score]})
      document = Document.new(root, id: "bdoc_ins_downstream")
      candidate = Block.new("weird", id: "blk_cand")
      palette = AssignabilityFixtures.palette() |> add_type("weird", Weird)

      assert Assignability.check(palette, document, {"blk_root", "body", 0}, candidate, %{}) ==
               {:error, [{:type_mismatch, "blk_scr", "blk_cand", "myapp.other", "myapp.lead"}]}
    end

    # sabotage: change `upstream_ref/2`'s `index == 0` clause to look up a
    # sibling instead of returning `:slot_entry` -> this assertion goes red
    test "a :type_mismatch at index 0 names :slot_entry" do
      root = Block.new("core.sequence", id: "blk_root", slots: %{"body" => []})
      document = Document.new(root, id: "bdoc_ins_slot_entry")
      candidate = Block.new("myapp.score", id: "blk_cand")
      palette = AssignabilityFixtures.palette()

      assert Assignability.check(
               palette,
               document,
               {"blk_root", "body", 0},
               candidate,
               %{entry_type: "myapp.record"}
             ) ==
               {:error, [{:type_mismatch, "blk_cand", :slot_entry, "myapp.record", "myapp.lead"}]}
    end

    # sabotage: change `kind_admission_finding/5`'s finding branch to
    # report `slot_accepts(...)` before `kinds(...)` swapped, i.e. carry the
    # candidate's kinds and the slot's accepts in the wrong tuple slots ->
    # this assertion goes red
    test "a :kind_not_admitted finding carries the candidate's kinds and the slot's accepted list" do
      group = Block.new("grouptype", id: "blk_grp", slots: %{"body" => [], "interrupts" => []})
      document = Document.new(group, id: "bdoc_ins_kind")
      candidate = Block.new("step", id: "blk_cand")
      palette = Palette.new(%{"grouptype" => GroupType, "step" => Step})

      assert Assignability.check(palette, document, {"blk_grp", "interrupts", 0}, candidate, %{}) ==
               {:error,
                [
                  {:kind_not_admitted, "blk_cand", "blk_grp", "interrupts", [:step],
                   [:interrupt_handler]}
                ]}
    end
  end

  describe "check/5 - move" do
    # sabotage: change `check/5`'s `vacated_finding = vacated_seam_finding(...)`
    # line to `vacated_finding = nil` -> this assertion goes red (the error
    # list comes back empty and the result is `:ok`)
    test "a move clean at the insertion point is refused at the vacated seam" do
      a = Block.new("myapp.enrich", id: "blk_a")
      b = Block.new("myapp.score", id: "blk_b")
      c = Block.new("myapp.enrich", id: "blk_c")
      root = Block.new("core.sequence", id: "blk_root", slots: %{"body" => [a, b, c]})
      document = Document.new(root, id: "bdoc_mv_vacated")
      palette = AssignabilityFixtures.palette()

      assert Assignability.check(palette, document, {"blk_root", "body", 3}, b, %{}) ==
               {:error, [{:type_mismatch, "blk_c", "blk_a", "myapp.lead", "myapp.record"}]}
    end

    # sabotage: remove the `nil -> nil` clause from `vacated_seam_finding/6`'s
    # `Enum.at(children, index + 1)` case -> raises instead of finding
    # nothing to check
    test "a move whose vacated slot has no block after the candidate has nothing to check there" do
      enrich = Block.new("myapp.enrich", id: "blk_enr")

      group =
        Block.new("core.group", id: "blk_grp", slots: %{"body" => [enrich], "interrupts" => []})

      score = Block.new("myapp.score", id: "blk_scr")
      root = Block.new("core.sequence", id: "blk_root", slots: %{"body" => [group, score]})
      document = Document.new(root, id: "bdoc_mv_no_after")
      palette = AssignabilityFixtures.palette()

      assert Assignability.check(palette, document, {"blk_grp", "body", 1}, score, %{}) == :ok
    end
  end

  describe "check/5 - degradation" do
    # sabotage: change `resolve_module_config/2`'s `{:error, _reason}` clause
    # to `raise "unresolvable"` -> this test raises instead of asserting
    test "a candidate whose type is not in the palette is permissive" do
      root = Block.new("core.sequence", id: "blk_root", slots: %{"body" => []})
      document = Document.new(root, id: "bdoc_unresolvable")
      candidate = Block.new("nope.unknown", id: "blk_cand")
      palette = AssignabilityFixtures.palette()

      assert Assignability.check(palette, document, {"blk_root", "body", 0}, candidate, %{}) ==
               :ok
    end
  end

  describe "check/5 - the ADR-0003 worked-example table" do
    # Rows for "before blk_ENR" and "after blk_ENR" isolate exactly the
    # upstream seam the ADR's own table names, the same way the two
    # dedicated seam tests above do - an empty slot with nothing downstream,
    # rather than the shared worked-example document, because inserting a
    # hypothetical candidate *before* an existing occupant would also run
    # the downstream seam against that occupant's `consumes`, which is not
    # what either row is stating a verdict about.

    # sabotage: n/a directly - identical code path to "an accepted insert
    # is :ok" above; recorded here to pin the table's own row rather than
    # duplicate the mutation.
    test "before blk_ENR: entry type identity admits enrich" do
      root = Block.new("core.sequence", id: "blk_root", slots: %{"body" => []})
      document = Document.new(root, id: "bdoc_row1")
      candidate = Block.new("myapp.enrich", id: "blk_enr_candidate")
      palette = AssignabilityFixtures.palette()

      assert Assignability.check(
               palette,
               document,
               {"blk_root", "body", 0},
               candidate,
               %{entry_type: "myapp.record"}
             ) == :ok
    end

    # sabotage: n/a directly - identical code path to the two tests above;
    # pins the table's second row.
    test "after blk_ENR: enrich's produces identity admits score" do
      enrich = Block.new("myapp.enrich", id: "blk_enr")
      root = Block.new("core.sequence", id: "blk_root", slots: %{"body" => [enrich]})
      document = Document.new(root, id: "bdoc_row2")
      candidate = Block.new("myapp.score", id: "blk_scr_candidate")
      palette = AssignabilityFixtures.palette()

      assert Assignability.check(palette, document, {"blk_root", "body", 1}, candidate, %{}) ==
               :ok
    end

    # sabotage: n/a directly - covered by "assignable?/3 - monotonicity"
    # above; this row pins the same widening at the `check/5` level, against
    # the shared worked-example document.
    test "after blk_SCR: the host relation widens scored_lead to notify's person" do
      document = AssignabilityFixtures.worked_example_document()
      candidate = Block.new("myapp.notify", id: "blk_not_candidate")
      palette = AssignabilityFixtures.palette()

      assert Assignability.check(
               palette,
               document,
               {"blk_ROOT", "body", 2},
               candidate,
               AssignabilityFixtures.worked_example_context()
             ) == :ok
    end

    # sabotage: n/a directly - covered by "a :type_mismatch on the upstream
    # seam names the upstream block id" above; this row pins the same
    # mismatch against the shared worked-example document.
    test "after blk_SCR: scored_lead does not widen to enrich's record" do
      document = AssignabilityFixtures.worked_example_document()
      candidate = Block.new("myapp.enrich", id: "blk_enr_candidate")
      palette = AssignabilityFixtures.palette()

      assert Assignability.check(
               palette,
               document,
               {"blk_ROOT", "body", 2},
               candidate,
               AssignabilityFixtures.worked_example_context()
             ) ==
               {:error,
                [
                  {:type_mismatch, "blk_enr_candidate", "blk_SCR", "myapp.scored_lead",
                   "myapp.record"}
                ]}
    end

    # sabotage: n/a directly - covered by "a :kind_not_admitted finding
    # carries the candidate's kinds and the slot's accepted list" above.
    test "inside interrupts: notify is [:step], not admitted" do
      document = AssignabilityFixtures.worked_example_document()
      candidate = Block.new("myapp.notify", id: "blk_not_candidate")
      palette = AssignabilityFixtures.palette()

      assert Assignability.check(
               palette,
               document,
               {"blk_GRP", "interrupts", 0},
               candidate,
               AssignabilityFixtures.worked_example_context()
             ) ==
               {:error,
                [
                  {:kind_not_admitted, "blk_not_candidate", "blk_GRP", "interrupts", [:step],
                   [:interrupt_handler]}
                ]}
    end

    # sabotage: n/a directly - covered by "an accepted insert is :ok" above.
    test "inside interrupts: on_cancel is [:interrupt_handler], admitted" do
      document = AssignabilityFixtures.worked_example_document()
      candidate = Block.new("myapp.on_cancel", id: "blk_cancel_candidate")
      palette = AssignabilityFixtures.palette()

      assert Assignability.check(
               palette,
               document,
               {"blk_GRP", "interrupts", 0},
               candidate,
               AssignabilityFixtures.worked_example_context()
             ) == :ok
    end

    # sabotage: n/a directly - covered by "a :kind_not_admitted finding
    # carries the candidate's kinds and the slot's accepted list" above.
    test "inside body: on_cancel is [:interrupt_handler], not admitted" do
      document = AssignabilityFixtures.worked_example_document()
      candidate = Block.new("myapp.on_cancel", id: "blk_cancel_candidate")
      palette = AssignabilityFixtures.palette()

      assert Assignability.check(
               palette,
               document,
               {"blk_GRP", "body", 0},
               candidate,
               AssignabilityFixtures.worked_example_context()
             ) ==
               {:error,
                [
                  {:kind_not_admitted, "blk_cancel_candidate", "blk_GRP", "body",
                   [:interrupt_handler], [:step]}
                ]}
    end

    # sabotage: change `assignable?/3`'s `%Palette{assignability: nil}`
    # clause from `do: false` to `do: true` -> this assertion goes red,
    # because the row would then stay :ok with the module dropped
    test "dropping assignability from the palette flips the widened row to :type_mismatch" do
      document = AssignabilityFixtures.worked_example_document()
      candidate = Block.new("myapp.notify", id: "blk_not_candidate")
      palette = AssignabilityFixtures.palette(nil)

      assert Assignability.check(
               palette,
               document,
               {"blk_ROOT", "body", 2},
               candidate,
               AssignabilityFixtures.worked_example_context()
             ) ==
               {:error,
                [
                  {:type_mismatch, "blk_not_candidate", "blk_SCR", "myapp.scored_lead",
                   "myapp.person"}
                ]}
    end
  end

  defp add_type(%Palette{types: types} = palette, type_name, module) do
    %{palette | types: Map.put(types, type_name, module)}
  end
end
