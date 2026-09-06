defmodule StatifierBlocks.Edit.TargetsTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.{Assignability, Block, CoreFixtures, Document, DocumentFixtures, Palette}
  alias StatifierBlocks.Edit.Targets

  # A signup wizard toy type with an `:exactly_one` slot - no shipped
  # `core.*` type declares one, and rule 3 (room) needs a slot arity that
  # can actually be full. "Highlight" is the one call-to-action the wizard
  # spotlights on a step before moving on; a step already holds it, or does
  # not yet.
  defmodule Spotlight do
    @moduledoc false
    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: [{"highlight", :exactly_one, "Highlight"}]
    @impl true
    def config_schema(_config), do: []
    @impl true
    def validate_config(_config), do: :ok
    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

    # ADR-0011 decision 6's subject path: the same one on every type here,
    # so whichever of them a document opens with names it and the
    # `consumes`/`produces` sugar desugars against it.
    @impl true
    def palette_entry, do: %{subject: "signup.applicant"}
  end

  # Two typed signup-wizard steps and a candidate that only fits at the
  # seam their shared type expression makes - so the same slot has some
  # gaps `check/5` accepts and some it refuses, which is what the
  # existential-reduction test needs (ADR-0003 decision 6 step 2's identity
  # relation, with no widening module configured).
  defmodule CaptureEmail do
    @moduledoc false
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
    def io(_config), do: %{kinds: [:step], produces: "signup.email_captured"}
    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

    # ADR-0011 decision 6's subject path: the same one on every type here,
    # so whichever of them a document opens with names it and the
    # `consumes`/`produces` sugar desugars against it.
    @impl true
    def palette_entry, do: %{subject: "signup.applicant"}
  end

  defmodule ConfirmEmail do
    @moduledoc false
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
    def io(_config),
      do: %{kinds: [:step], consumes: "signup.email_captured", produces: "signup.confirmed"}

    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

    # ADR-0011 decision 6's subject path: the same one on every type here,
    # so whichever of them a document opens with names it and the
    # `consumes`/`produces` sugar desugars against it.
    @impl true
    def palette_entry, do: %{subject: "signup.applicant"}
  end

  defmodule Personalize do
    @moduledoc "Only fits after something that has produced a confirmed signup."
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
    def io(_config), do: %{kinds: [:step], consumes: "signup.confirmed"}
    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}
  end

  defp core_palette, do: Palette.core()

  defp signup_step(type, id, opts \\ []) do
    Block.new(type, Keyword.put(opts, :id, id))
  end

  # ---------------------------------------------------------------------
  # The worked example
  # ---------------------------------------------------------------------

  describe "the ADR-0005 worked example" do
    # Sabotage: swapped the `palette`/`document` argument order in the call
    # to `Assignability.valid_targets/4` inside `droppable_slots_for/3` -
    # red with a `FunctionClauseError` (the second argument no longer
    # matches `%Document{}`), which is the whole worked example crashing
    # rather than merely returning the wrong set.
    test "droppable_slots/3 matches the real assignability relation, not the ADR's illustrative count" do
      document = DocumentFixtures.worked_example()
      palette = CoreFixtures.palette()

      result = Targets.droppable_slots(document, palette, "blk_NOT")

      # ADR-0005's own worked-example prose lists seven slots, including
      # `{"blk_GRP", "interrupts"}`, and says so *conditionally*: "present
      # only because a `myapp.notify` is assignable there; had sb-7rx's
      # relation said otherwise, it would be dark." The relation this bead
      # actually ships (`CoreFixtures.Notify` carries no `io/1`, so its
      # `kinds` default to `[:step]` per ADR-0003 decision 5) says
      # otherwise: `core.resumable_group`'s `interrupts` slot declares
      # `slot_accepts: %{"interrupts" => [:interrupt_handler]}}`, `:step`
      # does not intersect `[:interrupt_handler]`, and the slot is
      # correctly dark. Six slots, not seven - the ADR's own conditional
      # language already predicts this, and this assertion is against the
      # real, executable relation rather than the illustration.
      assert MapSet.new(result) ==
               MapSet.new([
                 {"blk_ROOT", "body"},
                 {"blk_GRP", "body"},
                 {"blk_BR", "arm_approved"},
                 {"blk_BR", "otherwise"},
                 {"blk_PAR", "lane_capture"},
                 {"blk_PAR", "lane_receipt"}
               ])

      refute {"blk_GRP", "interrupts"} in result
      refute Enum.any?(result, fn {b, _slot} -> b == "blk_NOT" end)
    end
  end

  # ---------------------------------------------------------------------
  # Rule 1: declared slots only
  # ---------------------------------------------------------------------

  describe "rule 1: declared slots only" do
    # Sabotage: in `droppable_slots_for/3`, unioned in every slot key each
    # block's `.slots` map carries (`Map.keys(block.slots)`) alongside the
    # declared ones - red, because `{"blk_WAI", "bogus"}` then appeared in
    # the result even though `core.wait` declares no slots at all.
    test "an undeclared slot key present in the document is not offered" do
      palette = core_palette()

      bogus_child = signup_step("core.wait", "blk_BOGUS_CHILD", config: %{"duration" => "1s"})

      # `core.wait` declares no slots (`slots/1` returns `[]`), but the
      # document is free to carry a stray `"bogus"` key anyway - decoding
      # never consults the registry (ADR-0001 decision 9).
      wait_with_bogus_slot =
        signup_step("core.wait", "blk_WAI",
          config: %{"duration" => "1s"},
          slots: %{"bogus" => [bogus_child]}
        )

      root =
        Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [wait_with_bogus_slot]})

      document = Document.new(root, id: "bdoc_R1_UNDECLARED")

      candidate = signup_step("core.wait", "blk_NEW", config: %{"duration" => "1s"})

      result = Targets.droppable_slots_for(document, palette, candidate)

      assert result == [{"blk_ROOT", "body"}]
      refute {"blk_WAI", "bogus"} in result
    end

    test "an unresolvable parent offers nothing" do
      palette = core_palette()

      unresolvable =
        Block.new("signup.mystery_step", id: "blk_UNRESOLVABLE", slots: %{"anything" => []})

      root = Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [unresolvable]})
      document = Document.new(root, id: "bdoc_R1_UNRESOLVABLE")

      candidate = signup_step("core.wait", "blk_NEW", config: %{"duration" => "1s"})

      result = Targets.droppable_slots_for(document, palette, candidate)

      assert result == [{"blk_ROOT", "body"}]
      refute Enum.any?(result, fn {b, _slot} -> b == "blk_UNRESOLVABLE" end)
    end
  end

  # ---------------------------------------------------------------------
  # Rule 2: the kind gate surviving the reduction
  # ---------------------------------------------------------------------

  describe "rule 2: kind admission (the index-free half of the reduction)" do
    # Sabotage: swapped `"body"`/`"interrupts"` in the two `assert`/`refute`
    # pairs below - red, since a handler was then asserted to need `"body"`
    # and a step to need `"interrupts"`, neither of which the real relation
    # grants.
    test "a handler is offered interrupts and not body; a step is offered body and not interrupts" do
      palette = core_palette()

      group = Block.new("core.resumable_group", id: "blk_GRP", config: %{"history" => "shallow"})
      root = Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [group]})
      document = Document.new(root, id: "bdoc_R2")

      handler =
        Block.new("core.on_event",
          id: "blk_HANDLER",
          config: %{"event" => "custom_interrupt", "outcome" => "abandon"}
        )

      step = signup_step("core.wait", "blk_STEP", config: %{"duration" => "1s"})

      handler_targets = Targets.droppable_slots_for(document, palette, handler)
      step_targets = Targets.droppable_slots_for(document, palette, step)

      assert {"blk_GRP", "interrupts"} in handler_targets
      refute {"blk_GRP", "body"} in handler_targets

      assert {"blk_GRP", "body"} in step_targets
      refute {"blk_GRP", "interrupts"} in step_targets
    end
  end

  # ---------------------------------------------------------------------
  # Rule 3: room
  # ---------------------------------------------------------------------

  describe "rule 3: room" do
    # Sabotage: dropped the `or full?(document, palette, parent_id, slot)`
    # disjunct from the final `Enum.reject/2` in `droppable_slots_for/3` -
    # red, `{"blk_GATE_FULL", "highlight"}` wrongly appeared in the result
    # alongside the empty gate.
    test "an occupied exactly_one slot is not offered; an empty one is" do
      palette = Palette.new(Map.merge(Palette.core_types(), %{"signup.spotlight" => Spotlight}))

      occupant = signup_step("core.wait", "blk_OCCUPANT", config: %{"duration" => "1s"})

      gate_full =
        Block.new("signup.spotlight", id: "blk_GATE_FULL", slots: %{"highlight" => [occupant]})

      gate_empty = Block.new("signup.spotlight", id: "blk_GATE_EMPTY")

      root =
        Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [gate_full, gate_empty]})

      document = Document.new(root, id: "bdoc_R3")

      candidate = signup_step("core.wait", "blk_NEW", config: %{"duration" => "1s"})

      result = Targets.droppable_slots_for(document, palette, candidate)

      refute {"blk_GATE_FULL", "highlight"} in result
      assert {"blk_GATE_EMPTY", "highlight"} in result
    end
  end

  # ---------------------------------------------------------------------
  # Rule 4: subtree exclusion
  # ---------------------------------------------------------------------

  describe "rule 4: subtree exclusion" do
    # Sabotage: dropped the `MapSet.member?(excluded, parent_id) or` half
    # of the final `Enum.reject/2` in `droppable_slots_for/3` - red,
    # dragging the outer group offered its own `body` slot (and its nested
    # group's) right back to itself.
    test "dragging a group with children offers no slot on it or any descendant" do
      palette = core_palette()

      leaf = signup_step("core.wait", "blk_LEAF", config: %{"duration" => "1s"})
      mid = Block.new("core.group", id: "blk_MID", slots: %{"body" => [leaf]})
      outer = Block.new("core.group", id: "blk_OUTER", slots: %{"body" => [mid]})
      root = Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [outer]})
      document = Document.new(root, id: "bdoc_R4")

      result = Targets.droppable_slots(document, palette, "blk_OUTER")

      assert result == [{"blk_ROOT", "body"}]
      refute Enum.any?(result, fn {b, _slot} -> b in ["blk_OUTER", "blk_MID", "blk_LEAF"] end)
    end
  end

  # ---------------------------------------------------------------------
  # The existential reduction itself
  # ---------------------------------------------------------------------

  describe "the existential reduction" do
    # Sabotage: changed the reduction from existential to universal - a
    # slot is offered only when *every* index in `valid_targets/4` for that
    # slot passes, computed by comparing the count of matching `{p, s, _}`
    # triples against the slot's total gap count - red, `{"blk_ROOT",
    # "body"}` dropped out even though it should stay offered on the
    # strength of its two clean gaps.
    test "a slot where only some indices pass check/5 is still offered, verified against valid_targets/4" do
      palette =
        Palette.new(
          Map.merge(Palette.core_types(), %{
            "signup.capture_email" => CaptureEmail,
            "signup.confirm_email" => ConfirmEmail,
            "signup.personalize" => Personalize
          })
        )

      capture = signup_step("signup.capture_email", "blk_CAPTURE")
      confirm = signup_step("signup.confirm_email", "blk_CONFIRM")
      root = Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [capture, confirm]})
      document = Document.new(root, id: "bdoc_REDUCTION")

      candidate = signup_step("signup.personalize", "blk_PERSONALIZE")

      # `body` has three gaps (0, 1, 2). Index 0's upstream is the
      # sequence's own inbound type (`:unknown` by default - the
      # permissive default admits anything); index 1 sits between
      # `capture` (produces `"signup.email_captured"`) and `confirm`, and
      # the candidate consumes `"signup.confirmed"` - a genuine mismatch;
      # index 2 sits after `confirm` (produces `"signup.confirmed"`),
      # which is exactly what the candidate consumes.
      targets = Assignability.valid_targets(palette, document, candidate, %{})
      body_targets = Enum.filter(targets, fn {p, s, _i} -> {p, s} == {"blk_ROOT", "body"} end)

      assert Enum.map(body_targets, fn {_p, _s, i} -> i end) |> Enum.sort() == [0, 2]

      droppable = Targets.droppable_slots_for(document, palette, candidate)

      assert {"blk_ROOT", "body"} in droppable
    end
  end

  # ---------------------------------------------------------------------
  # droppable_slots/3 vs droppable_slots_for/3
  # ---------------------------------------------------------------------

  describe "droppable_slots/3" do
    # Sabotage: in `droppable_slots/3`'s `nil` branch, returned a non-empty
    # placeholder (`[{"blk_ROOT", "body"}]`) instead of `[]` - red, the
    # comparison against `[]` failed.
    test "an id not in the document returns []" do
      palette = core_palette()
      root = Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => []})
      document = Document.new(root, id: "bdoc_MISSING")

      assert Targets.droppable_slots(document, palette, "blk_GHOST") == []
    end

    # Sabotage: in `droppable_slots/3`, returned `[]` unconditionally
    # instead of delegating to `droppable_slots_for/3` on a lookup hit -
    # red, both sides of the comparison stopped agreeing (the id form
    # dropped to `[]` while the fresh form kept its one slot).
    test "on a fresh palette block returns the same slots as the id form does for an equivalent block already in the tree" do
      palette = core_palette()

      in_tree = signup_step("core.wait", "blk_X", config: %{"duration" => "1s"})
      root = Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [in_tree]})
      document = Document.new(root, id: "bdoc_EQUIV")

      by_id = Targets.droppable_slots(document, palette, "blk_X")

      fresh = signup_step("core.wait", "blk_FRESH", config: %{"duration" => "1s"})
      by_fresh = Targets.droppable_slots_for(document, palette, fresh)

      assert MapSet.new(by_id) == MapSet.new(by_fresh)
      assert by_id != []
    end

    # sabotage: restore the single `{:ok, path}` clause of
    # `Assignability.vacated_seam_finding/4` - red, the call raises a
    # MatchError instead of returning `[]`. The root occupies no slot, so
    # it vacates no seam; rule 4 then excludes its own whole subtree, which
    # is every block, leaving the empty set `Edit.apply/2`'s
    # `check_not_root/2` agrees with.
    test "the document root is answerable and offers no slot" do
      palette = core_palette()

      leaf = signup_step("core.wait", "blk_LEAF", config: %{"duration" => "1s"})
      root = Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [leaf]})
      document = Document.new(root, id: "bdoc_ROOT_DRAG")

      assert Targets.droppable_slots(document, palette, "blk_ROOT") == []
    end
  end
end
