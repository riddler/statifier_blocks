/*
 * spike/js/targets.js - drop-target enumeration, mirrored.
 *
 * A client-side mirror of `StatifierBlocks.Edit.Targets.droppable_slots/3`
 * (ADR-0005 decision 5): which slots would accept a dragged block, computed
 * ONCE per drag, at slot granularity rather than gap granularity.
 *
 * This is the module the whole pre-hover-validity requirement rests on. The
 * brief asks that every valid slot highlight at drag start rather than
 * lighting up one at a time under the pointer, and that is only possible
 * because the valid-target set is a pure function of `{document, registry,
 * dragged block}` with no browser anywhere near it. In the shipped editor
 * this runs on the server and the answer reaches the client as `data-drop`
 * attributes; in the spike it runs here and stamps the same attributes. The
 * DOM contract is the same either way.
 *
 * ## The four rules
 *
 * A slot accepts the dragged block when all four hold:
 *
 *   1. **The slot is declared** - the parent resolves through the registry,
 *      and `slots()` on the parent's CURRENT config lists this slot name.
 *   2. **Assignability accepts it** - consulted through one predicate and
 *      nothing else.
 *   3. **The slot has room** - an `exactly_one` or `zero_or_one` slot that is
 *      already occupied is not a target. A drop never silently replaces a
 *      child; the author removes first.
 *   4. **The slot is not inside the dragged block's own subtree** - a block
 *      cannot become its own descendant.
 *
 * ## What rule 2 means here, precisely
 *
 * Upstream, rule 2 is `Assignability.check/5`, which is two things at once:
 * kind admission (ADR-0003 decision 3's structural gate, index-free) and the
 * data-flow SEAM checks, which read the neighbours at the target index and
 * therefore do move with it.
 *
 * The spike mirrors the kind-admission half only. That is deliberate and it
 * is safe in the one direction that matters: decision 5 already accepts a
 * per-slot over-approximation - highlighting a slot when at least one of its
 * gaps admits the block can offer a gap that later yields a `type_mismatch`
 * finding, and can never hide a gap that would have been clean. Dropping the
 * seam half moves further in that same direction (more slots highlighted,
 * never fewer), so nothing the spike offers is a placement the shipped editor
 * would have forbidden under rules 1, 3 or 4. What it does NOT model is the
 * finding an author would see afterwards, and the findings pane is a later
 * bead's subject.
 *
 * The residue is real and worth naming rather than hiding: per-slot
 * highlighting is a superset of per-position validity, and per-slot
 * highlighting WITHOUT the seams is a superset of that again.
 *
 * ## Unresolvable parents (ADR-0005 decision 12)
 *
 * Rule 1 excludes an unresolvable parent outright, so such a block offers no
 * slots at all - not even a reorder among the children it already has. That
 * was once a divergence from decision 12's prose, which said the reorder was
 * permitted; the operator ruled on 2026-08-28 (sb-cvo) that d12's sentence
 * was the error and this enumeration is correct as written. The prose now
 * says the reorder is not offered, and keeps order-asks-the-parent's-type-
 * nothing as the reason a future enumeration that expresses it would be an
 * additive extension rather than a reversal.
 */

import { blocks, findBlock, slotChildren, subtreeIds } from "./document.js";
import { admits, describe, resolveBlock } from "./palette.js";

const CLOSED_ARITIES = ["exactly_one", "zero_or_one"];

/**
 * The slots that would accept the block carrying `id`. An `id` naming no
 * block in `doc` yields `[]`: there is nothing to drag, so there is nothing
 * to ask about.
 *
 * Returns `[{ parentId, slot }]` in a deterministic order - the document's
 * pre-order, then each block's declared slot order - so two calls with the
 * same arguments always produce the same list.
 */
export function droppableSlots(doc, registry, id) {
  const node = findBlock(doc, id);
  return node ? droppableSlotsFor(doc, registry, node) : [];
}

/**
 * The same predicate, taking a block directly so one not yet in `doc` can be
 * asked the same question - which is what ADR-0005 decision 8's "+" button
 * needs, since a palette insert has no block in the document to name by id.
 * `droppableSlots` is a lookup followed by a call to this function: there is
 * one implementation, not two.
 */
export function droppableSlotsFor(doc, registry, candidate) {
  // Rule 4, computed once as a set so the filter is a membership test rather
  // than a repeated path walk.
  const excluded = subtreeIds(candidate);

  // The candidate's own kinds degrade permissively when it does not resolve
  // (ADR-0003 decision 5), which is what keeps an unresolvable block
  // movable - decision 12 promises it may be selected, moved and deleted.
  const candidateView = describe(registry, candidate);
  const found = [];

  for (const parent of blocks(doc)) {
    if (excluded.has(parent.id)) continue;

    // Rule 1's first half: the parent must resolve. A block whose type does
    // not resolve contributes no positions - there is no module to ask for a
    // declared slot set, so this is an absence of targets rather than a
    // refusal.
    const resolved = resolveBlock(registry, parent);
    if (!resolved.ok) continue;

    const { descriptor, block: resolvedParent } = resolved.value;

    // Rule 1's second half: the DECLARED slots given this parent's current
    // config, never the slot keys the stored document happens to carry.
    for (const slot of descriptor.slots(resolvedParent.config)) {
      if (!admits(descriptor, resolvedParent.config, slot.name, candidateView.descriptor,
        candidateView.block.config)) {
        continue;
      }

      if (isFull(parent, slot)) continue;

      found.push({ parentId: parent.id, slot: slot.name });
    }
  }

  return found;
}

/*
 * Rule 3. A block already occupying such a slot excludes that slot for itself
 * too; that only forbids moving a block to the position it already holds,
 * which costs nothing.
 */
function isFull(parent, slot) {
  return CLOSED_ARITIES.includes(slot.arity) && slotChildren(parent, slot.name).length > 0;
}

/**
 * Whether one particular `{ parentId, slot }` is in the droppable set - the
 * question a `dragover` handler asks. Built on `droppableSlotsFor` so there
 * is still one predicate; a drag session computes the set once at
 * `dragstart` and consults `slotKey` against it rather than calling this per
 * hover.
 */
export function isDroppable(doc, registry, candidate, parentId, slot) {
  return droppableSlotsFor(doc, registry, candidate).some(
    (found) => found.parentId === parentId && found.slot === slot
  );
}

/** A stable string key for a `{ parentId, slot }` pair, for Set membership. */
export const slotKey = ({ parentId, slot }) => `${parentId}\u0000${slot}`;

/** The droppable set as a Set of `slotKey`s - what a drag session holds. */
export function droppableSlotSet(doc, registry, candidate) {
  return new Set(droppableSlotsFor(doc, registry, candidate).map(slotKey));
}
