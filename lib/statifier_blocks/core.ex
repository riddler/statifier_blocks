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
  | `core.branch` | `#{inspect(__MODULE__)}.Branch` | one per arm, then `otherwise` |
  | `core.parallel` | `#{inspect(__MODULE__)}.Parallel` | one per lane |
  | `core.wait` | `#{inspect(__MODULE__)}.Wait` | none |
  | `core.resumable_group` | `#{inspect(__MODULE__)}.ResumableGroup` | `body`, `interrupts` |
  | `core.on_event` | `#{inspect(__MODULE__)}.OnEvent` | none |
  | `core.invoke` | `#{inspect(__MODULE__)}.Invoke` | `on_error` |

  ## Structure, not domain

  None of these types knows a host's domain, and none of them declares a
  type expression (ADR-0003 decision 1). They arrange other blocks; the
  blocks they arrange are the host's. `core.invoke` is structural in the
  same sense - it *names* an invoke type and never runs one, which is
  ADR-0002 decision 2's two-registry seam rather than domain knowledge. So every core `io/1` declares `kinds`, every
  core type that has slots declares `slot_accepts` for them, and no core
  type declares `consumes` at all - inbound type is the host's business,
  and ADR-0003 decision 5's permissive default is the honest answer.

  `produces` is declared by four of the eight. `core.sequence` declares
  `{:passthrough, "body"}`: it is transparent to type flow, so whatever its
  last step produces is what the sequence produces, computed by ADR-0003
  decision 4 rather than by anything here. `core.branch`, `core.parallel`
  and `core.invoke` declare `:unknown` outright rather than combining their
  arms', lanes' or outcomes' outputs, because combining them is the type lattice
  ADR-0003 decision 4 refuses to build - and spelling the default out is
  how that refusal stays visible to a reader. The other four leave it
  absent.

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

  ## What they compile to

  All eight emit through `#{inspect(__MODULE__)}.Emit`, which is where the
  SCXML shapes and the one convention they share are written down: a block
  is one compound state carrying a `<final>`, and completion is
  `done.state.<state id>` (ADR-0004 decision 2). Read that module before
  writing a host block type - a type that follows the same convention
  composes with these without either side knowing about the other, and a
  type that does not is a type no container can sequence after.
  """
end
