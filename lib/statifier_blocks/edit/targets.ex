defmodule StatifierBlocks.Edit.Targets do
  @moduledoc """
  Drop-target enumeration (ADR-0005 decision 5): which slots would accept a
  dragged block, at slot granularity rather than gap granularity.

  ## The stated reduction, from ADR-0003 positions to ADR-0005 slots

  `StatifierBlocks.Assignability.valid_targets/4` answers a finer question
  than this module needs: every `{block_id, slot_name, index}` **position**
  where a candidate may land. ADR-0005 decision 5 wants every `{block_id,
  slot_name}` **slot** that has at least one such position. This module -
  concretely, `droppable_slots/3` - bridges exactly those two functions, and
  the bridge is existential quantification over the index:

      {b, s} is droppable  <=>  exists i such that {b, s, i} is in valid_targets/4

  Decision 5's own text says "nothing in that list depends on the index
  within the slot," and that sentence is literally true of rules 1, 3 and 4
  but **not** of rule 2: `Assignability.check/5` consults an upstream seam
  and a downstream seam, both of which read the neighbours at `index - 1`
  and `index`, so both move with the index. (The third seam `check/5`
  consults, the vacated one, depends on the candidate's own *current*
  position rather than on the target index, so it is constant across a
  slot's gaps and is not part of what the reduction has to answer for.) The
  reduction is sound anyway, for three reasons:

    1. **The index-free half of rule 2 is preserved exactly.** Kind
       admission - `Assignability.admits?/3`, ADR-0003 decision 3's
       structural gate - is a function of `{parent module, parent config,
       slot, child kinds}` with no index in it. A slot that fails kind
       admission fails it at every index, so existential quantification
       drops the whole slot, which is the same verdict a per-slot rule
       would give. This is the half rule 2 is really about: an
       `interrupts` slot does not accept a step, at any index.
    2. **The index-dependent half is a seam check, and seams are
       validation, not admission.** Decision 5 says the editor never blocks
       an edit for a validation reason outside its four rules, and
       ADR-0002 decision 6 already establishes that a document mid-edit is
       allowed to be invalid. A type mismatch at one gap of an otherwise
       acceptable slot is exactly that kind of finding, not a reason to
       darken the whole slot.
    3. **The reduction is an over-approximation at gap granularity, never
       an under-approximation.** Highlighting a slot when at least one of
       its gaps accepts the block can offer the author a gap that would
       produce a `:type_mismatch` finding; it can never hide a gap that
       would have been clean. The failure mode is a finding the author can
       see and fix, not a legal arrangement they cannot reach.

  **The residue is real.** Per-slot highlighting is a superset of
  per-position validity, and a drop at a particular gap may still produce
  an assignability finding. That is the documented cost of decision 5's
  per-slot granularity, not a defect introduced here.

  `droppable_slots/3`'s signature carries no `Assignability.context()`, so
  this module calls `valid_targets/4` with `%{}` - `entry_type` absent,
  which resolves to `:unknown`, which ADR-0003 decision 5 makes the
  permissive default.

  ## Rules 3 and 4, which are this bead's alone

  `valid_targets/4` already enforces rules 1 and 2 (declared slots only,
  kind admission). It does not filter by room and does not exclude the
  candidate's own subtree - those two are added here, after the projection
  to slots:

    * **Rule 3, room.** Drop any `{b, s}` whose arity in
      `module.slots(config)` is `:exactly_one` or `:zero_or_one` and whose
      current child count (as `document` stores it) is 1 or more. A block
      already occupying such a slot excludes that slot for itself too;
      that only forbids moving a block to the position it already holds,
      which costs nothing.
    * **Rule 4, subtree.** Drop any `{b, s}` where `b` is the dragged block
      itself or a descendant of it. Computed once as a `MapSet` of ids
      walked from the dragged block the same way `Document.blocks/1` walks
      a document, so the filter is a membership test rather than a
      repeated path walk.

  ## The `droppable_slots_for/3` widening

  `droppable_slots/3` takes a `Block.id()`, per the record; a block id that
  names nothing in `document` yields `[]`. ADR-0005 decision 8 requires the
  palette's "+" button to filter using "the same predicate," and a palette
  insert has no block in the document yet to name by id - so this module
  also exports `droppable_slots_for/3`, taking a `%Block{}` that need not
  be in `document` at all. `droppable_slots/3` is implemented as a lookup
  followed by a call to `droppable_slots_for/3`: there is one
  implementation, not two. This is the third documented widening this
  module carries, alongside the two argued above.
  """

  alias StatifierBlocks.{Assignability, Block, Document, Palette}

  @doc """
  Slots that would accept `id`'s block: declared, kind-admitted (rule 1 and
  the index-free half of rule 2), with room (rule 3), and outside the
  block's own subtree (rule 4). Per-slot, not per-gap - see the moduledoc
  for the reduction this projects from.

  `id` naming no block in `document` yields `[]`: there is no block to drag,
  so there is nothing to ask `droppable_slots_for/3` about.
  """
  @spec droppable_slots(Document.t(), Palette.t(), Block.id()) ::
          [{Block.id(), Block.slot_name()}]
  def droppable_slots(%Document{} = document, %Palette{} = palette, id) do
    case find_block(document, id) do
      nil -> []
      block -> droppable_slots_for(document, palette, block)
    end
  end

  @doc """
  The same predicate as `droppable_slots/3`, taking a `%Block{}` directly
  so a block not yet in `document` - the palette's "+" button, ADR-0005
  decision 8 - can be asked the same question. `droppable_slots/3` is a
  lookup followed by a call to this function.
  """
  @spec droppable_slots_for(Document.t(), Palette.t(), Block.t()) ::
          [{Block.id(), Block.slot_name()}]
  def droppable_slots_for(%Document{} = document, %Palette{} = palette, %Block{} = block) do
    for {slot_ref, :ok} <- slot_verdicts(document, palette, block), do: slot_ref
  end

  @typedoc """
  A slot's verdict for one dragged block: `:ok` when the slot would accept
  it, `{:refused, reason}` when it would not - `reason` being the
  2026-08-29 ADR-0003 amendment's vocabulary, or `nil` when the slot's
  refusal has no data-flow reason to give (see `slot_verdicts/3`).
  """
  @type slot_verdict :: :ok | {:refused, Assignability.reason() | nil}

  @doc """
  Every slot this module considers, with its verdict for `block` - the
  accepting ones and the refusing ones, in one pass.

  `droppable_slots_for/3` keeps the `:ok` rows of this list, so the
  accepting set and the reasons for the refusing set come from one
  enumeration and one decision. The rows are
  `StatifierBlocks.Assignability.target_verdicts/4`'s positions projected
  to slots, first-appearance order preserved, with rules 3 and 4 applied
  after the projection exactly as before.

  ## What a refused slot's reason is, and when there is none

  A slot is refused when **every** gap in it was refused - that is the
  existential reduction the moduledoc argues for, read the other way round.
  So a slot-level reason exists only when the gaps agree:

    * each gap's reason is `Assignability.finding_reason/2` of its **first**
      finding, in the order `Assignability.check/5` documents - so a gap
      that fails kind admission reports `nil`, because that gate's finding
      names both kind sets itself and is the more interesting of the two
      things wrong with such a gap;
    * the slot's reason is that value when every gap gave the same non-`nil`
      one, and `nil` otherwise.

  `nil` is therefore honest rather than lossy: it says this slot has no one
  data-flow reason to show the author - because the refusal was structural
  (`:kind_not_admitted` names both kind sets itself), because it was rule 3
  or rule 4 (no room, or the block's own subtree, neither of which is an
  assignability question at all), or because different gaps refused
  differently and picking one of them would be picking arbitrarily.

  Only the two refusing arms of the vocabulary can ever appear here. The
  three untyped arms sit on seams that were *admitted*, and an admitted gap
  makes its whole slot `:ok` - which is the amendment's "the reason
  explains, it never refuses more" holding at this layer too, by
  construction rather than by discipline.

  In practice the reachable slot-level arm is `:not_assignable`, and this
  is worth saying rather than leaving to be discovered.
  `{:fixable_by, block_id}` needs every gap in a slot to name the *same*
  producing block, and a slot's gaps name different ones by construction:
  gap 0's producing side is the slot's own inbound (`:slot_entry`) or the
  candidate itself, and gap `i`'s is the sibling at `i - 1`. So a slot with
  more than one gap that refuses at all of them almost always disagrees
  with itself and reports `nil`. `{:fixable_by, _}` is a *position*-level
  answer, and it is reachable exactly where positions are: in a
  `:type_mismatch` finding, and in whatever per-gap affordance ADR-0005
  decision 5's per-slot granularity is eventually widened to allow. Nothing
  here is lost - the finding still carries it - and the per-slot attribute
  does not pretend to an answer the granularity cannot support.
  """
  @spec slot_verdicts(Document.t(), Palette.t(), Block.t()) ::
          [{{Block.id(), Block.slot_name()}, slot_verdict()}]
  def slot_verdicts(%Document{} = document, %Palette{} = palette, %Block{} = block) do
    excluded = subtree_ids(block)

    palette
    |> Assignability.target_verdicts(document, block, %{})
    |> group_by_slot()
    |> Enum.map(fn {{parent_id, slot} = slot_ref, verdicts} ->
      cond do
        MapSet.member?(excluded, parent_id) -> {slot_ref, {:refused, nil}}
        full?(document, palette, parent_id, slot) -> {slot_ref, {:refused, nil}}
        Enum.any?(verdicts, &(&1 == :ok)) -> {slot_ref, :ok}
        true -> {slot_ref, {:refused, agreed_reason(palette, verdicts)}}
      end
    end)
  end

  # Positions to slots, first-appearance order preserved and each slot's
  # gap verdicts kept in ascending index order - `target_verdicts/4`
  # already emits them that way, so this only has to not reorder them.
  @spec group_by_slot([{Assignability.target(), :ok | {:error, [Assignability.finding()]}}]) ::
          [{{Block.id(), Block.slot_name()}, [:ok | {:error, [Assignability.finding()]}]}]
  defp group_by_slot(target_verdicts) do
    target_verdicts
    |> Enum.reduce({[], %{}}, fn {{parent_id, slot, _index}, verdict}, {order, acc} ->
      key = {parent_id, slot}
      order = if Map.has_key?(acc, key), do: order, else: [key | order]
      {order, Map.update(acc, key, [verdict], &[verdict | &1])}
    end)
    |> then(fn {order, acc} ->
      order
      |> Enum.reverse()
      |> Enum.map(fn key -> {key, Enum.reverse(Map.fetch!(acc, key))} end)
    end)
  end

  # The one reason every gap agreed on, or `nil` when they did not agree or
  # when any of them had none to give.
  @spec agreed_reason(Palette.t(), [:ok | {:error, [Assignability.finding()]}]) ::
          Assignability.reason() | nil
  defp agreed_reason(palette, verdicts) do
    case verdicts |> Enum.map(&gap_reason(palette, &1)) |> Enum.uniq() do
      [single] -> single
      _disagreed_or_empty -> nil
    end
  end

  # A single gap's reason: `Assignability.finding_reason/2` of its **first**
  # finding, in the order `Assignability.check/5` documents - kind
  # admission, then the insertion seams, then the vacated one.
  #
  # Taking the first rather than the first `:type_mismatch` is the whole
  # rule, and it is what makes a structural refusal dominate. A gap that
  # fails kind admission usually fails a seam too - an interrupt rail
  # refusing a step also refuses the step's type flow - and reporting the
  # seam there would tell the author the second-most-interesting thing that
  # is wrong. `check/5` already put the findings in the order the author
  # should read them; this reads the same order rather than inventing a
  # priority beside it, so `:kind_not_admitted` yields `nil` (that gate
  # names both kind sets in its own finding) and the seam reason surfaces
  # exactly when the structural gate had nothing to say.
  @spec gap_reason(Palette.t(), :ok | {:error, [Assignability.finding()]}) ::
          Assignability.reason() | nil
  defp gap_reason(_palette, :ok), do: nil
  defp gap_reason(_palette, {:error, []}), do: nil

  defp gap_reason(palette, {:error, [first | _rest]}),
    do: Assignability.finding_reason(palette, first)

  # Rule 3: true when `slot` on `parent_id` is `:exactly_one` or
  # `:zero_or_one` and already carries a child. `parent_id` always resolves
  # here - `valid_targets/4` only ever contributed this pair because it
  # already resolved the same block through the same palette.
  @spec full?(Document.t(), Palette.t(), Block.id(), Block.slot_name()) :: boolean()
  defp full?(document, palette, parent_id, slot) do
    with parent when not is_nil(parent) <- find_block(document, parent_id),
         {:ok, module, resolved} <- Palette.resolve(palette, parent),
         {_name, arity, _label} <-
           Enum.find(module.slots(resolved.config), fn {name, _arity, _label} -> name == slot end) do
      arity in [:exactly_one, :zero_or_one] and Map.get(parent.slots, slot, []) != []
    else
      _no_match -> false
    end
  end

  @spec find_block(Document.t(), Block.id()) :: Block.t() | nil
  defp find_block(document, id), do: Enum.find(Document.blocks(document), &(&1.id == id))

  # Every id in `block`'s own subtree, `block` included - the same
  # pre-order walk `Document.blocks/1` uses, rooted here instead of at a
  # document's root.
  @spec subtree_ids(Block.t()) :: MapSet.t(Block.id())
  defp subtree_ids(%Block{id: id, slots: slots}) do
    slots
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.flat_map(fn {_slot_name, children} -> children end)
    |> Enum.reduce(MapSet.new([id]), fn child, acc -> MapSet.union(acc, subtree_ids(child)) end)
  end
end
