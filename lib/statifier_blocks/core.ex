defmodule StatifierBlocks.Core do
  @moduledoc """
  The `core.*` structural vocabulary: the block types this package ships
  itself (ADR-0002 decision 10).

  Every one of them is an ordinary `StatifierBlocks.BlockType` - there is no
  privileged path for a core type, and a host that wants a container this
  package does not ship writes one the same way these are written. They are
  reached through `StatifierBlocks.Palette.core/0`, and a host merges them
  with its own entries through `StatifierBlocks.Palette.core_types/0`.

  | Block type | Module | Slots |
  |---|---|---|
  | `core.sequence` | `#{inspect(__MODULE__)}.Sequence` | `body` |
  | `core.group` | `#{inspect(__MODULE__)}.Group` | `body`, `interrupts` |
  | `core.branch` | `#{inspect(__MODULE__)}.Branch` | one per arm, then `otherwise`, then `undecided` |
  | `core.parallel` | `#{inspect(__MODULE__)}.Parallel` | one per lane |
  | `core.wait` | `#{inspect(__MODULE__)}.Wait` | none |
  | `core.await` | `#{inspect(__MODULE__)}.Await` | none |
  | `core.resumable_group` | `#{inspect(__MODULE__)}.ResumableGroup` | `body`, `interrupts` |
  | `core.on_event` | `#{inspect(__MODULE__)}.OnEvent` | none |
  | `core.invoke` | `#{inspect(__MODULE__)}.Invoke` | `on_error` |
  | `core.raise` | `#{inspect(__MODULE__)}.Raise` | none |
  | `core.assign` | `#{inspect(__MODULE__)}.Assign` | none |
  | `core.send` | `#{inspect(__MODULE__)}.Send` | none |
  | `core.subchart` | `#{inspect(__MODULE__)}.Subchart` | one per declared outcome, `on_error` last |
  | `core.foreach` | `#{inspect(__MODULE__)}.Foreach` | `body` |
  | `core.map` | `#{inspect(__MODULE__)}.Map` | `on_done`, `on_error` |
  | `core.drafts` | `#{inspect(__MODULE__)}.Drafts` | `body` |
  | `core.placeholder` | `#{inspect(__MODULE__)}.Placeholder` | none |

  ## Structure, not domain

  None of these types knows a host's domain, and none of them declares a
  type expression (ADR-0003 decision 1). They arrange other blocks; the
  blocks they arrange are the host's. `core.invoke` is structural in the
  same sense - it *names* an invoke type and never runs one, which is
  ADR-0002 decision 2's two-registry seam rather than domain knowledge, and
  `core.subchart` is that seam again: it names another chart and the
  host-registered invoke type that runs one, and `core.map` is that same
  seam over a list - it names a chart, a datamodel path and a fan-out
  invoke type, and the host's handler is what starts one run per item. So every core `io/1` declares `kinds`, every
  core type that has slots declares `slot_accepts` for them, and no core
  type declares `consumes` at all - inbound type is the host's business,
  and ADR-0003 decision 5's permissive default is the honest answer.

  `core.placeholder` is the one type that declares no `io/1` at all, and
  ADR-0003's amendment of 2026-08-31, section A3, is why: a gap goes
  wherever a step goes and constrains neither neighbour, so decision 5's
  permissive default taken in full - `kinds: [:step]`, `consumes` and
  `produces` both `:unknown` - is the honest answer, and declaring anything
  narrower would be this package deciding what an author's unwritten step
  was going to do.

  `produces` is declared by six of the core types. `core.sequence` declares
  `{:passthrough, "body"}`: it is transparent to type flow, so whatever its
  last step produces is what the sequence produces, computed by ADR-0003
  decision 4 rather than by anything here. `core.branch`, `core.parallel`,
  `core.invoke`, `core.subchart` and `core.map` declare `:unknown` outright rather than combining their
  arms', lanes' or outcomes' outputs, because combining them is the type lattice
  ADR-0003 decision 4 refuses to build - and spelling the default out is
  how that refusal stays visible to a reader. The rest leave it absent.

  ## Placement is kind tags, and nothing else

  `core.on_event` may appear inside an `interrupts` slot and nowhere else,
  and nothing but an interrupt handler may appear inside one. Both
  directions fall out of two declarations - `core.on_event` tagging itself
  `kinds: [:interrupt_handler]`, and the group types naming
  `"interrupts" => [:interrupt_handler]` in `slot_accepts` - evaluated by
  ADR-0003 decision 3's intersection rule.

  **There is deliberately no special-cased validation rule for it here.**
  ADR-0002 decision 10 originally recorded one and withdrew it at
  acceptance; a host group type with an `interrupts` slot gets the same
  constraint by declaring the same thing, and `core.on_event` never has to
  enumerate the groups it is allowed inside.

  `core.drafts` is the same mechanism reaching its limit rather than an
  exception to it. Its `kinds: [:draft_shelf]` is refused by every slot in
  this vocabulary through the same intersection, with no new rule. The two
  things kinds cannot say - that the root's `body` admits a shelf anyway,
  and that a document carries at most one - are a depth constraint and a
  cardinality constraint, and `StatifierBlocks.Shelf` carries those two and
  only those two, as Structure-stage findings (ADR-0002's amendment of
  2026-08-31, section G12, campaign-024 ruling R-b).

  ## What they compile to

  Every core type emits through `#{inspect(__MODULE__)}.Emit`, which is
  where the SCXML shapes and the one convention they share are written
  down: a block is one compound state carrying a `<final>`, and completion is
  `done.state.<state id>` (ADR-0004 decision 2). Read that module before
  writing a host block type - a type that follows the same convention
  composes with these without either side knowing about the other, and a
  type that does not is a type no container can sequence after.
  """
end
