defmodule StatifierBlocks.Core.Drafts do
  @moduledoc """
  `core.drafts`: the document's shelf, holding fragments an author has built
  but has not placed (ADR-0002's amendment of 2026-08-31, section G9).

  One slot, `body`, holding anything. Nothing in it is in the flow, nothing
  in it compiles, and nothing downstream reads the order it sits in - that
  order is *shelf order*, where the author put things down, and it is
  stable, hashed and undoable like any other slot's order without meaning
  sequencing.

  ## What makes the shelf a shelf

  Three declarations and one compiler rule, and the three declarations are
  ordinary:

    * `io/1` returns `kinds: [:draft_shelf]`, a kind minted for this type
      (ADR-0003's amendment of the same date, section A1). Every slot in
      the shipped `core.*` vocabulary accepts `[:step]` or
      `[:interrupt_handler]`, so a block declaring only `:draft_shelf` is
      refused by all of them through the intersection ADR-0003 decision 3
      already performs - no new rule, no per-type list, and a host
      container declaring `slot_accepts: [:step]` refuses a shelf without
      knowing this type exists.
    * `slot_accepts: %{"body" => :any}` is the most permissive declaration
      ADR-0003 admits, and it is deliberate: a shelf that refused the
      fragment an author most needed to put down would be worse than no
      shelf (A1). It buys no suspension of the Config stage - a
      half-configured parked fragment is still told so (G9c).
    * `palette_entry/0` declares `slot_style: %{"body" => :tray}`, the
      fourth style ADR-0005's amendment of the same date adds. A tray draws
      no boundary box and no connectors, because an order the compiler is
      defined never to read must not be drawn as though it meant something
      (10u).

  The compiler rule is G9a: the shelf is removed from the root's child list
  before anything reads sequencing, which is what
  `StatifierBlocks.Shelf` and `StatifierBlocks.Compiler` implement between
  them.

  ## Two facts the kind cannot carry

  That the root's `body` admits a shelf anyway, and that a document carries
  at most one, are a depth constraint and a cardinality constraint. Neither
  is an intersection of a parent's `slot_accepts` with a child's `kinds`,
  so neither is expressible here; both are Structure-stage findings owned
  by `StatifierBlocks.Shelf` (G12, campaign-024 ruling R-b).

  ## Against `core.placeholder`

  The two types are opposites and shipped together on purpose (G10a). A
  shelf holds work that is **not** in the flow and says nothing about it;
  `StatifierBlocks.Core.Placeholder` **is** in the flow and says something
  is missing from it.

  ## The word "drafts"

  A *draft fragment* is a block subtree stored in this slot - in the
  canonical bytes, in the document hash, on the undo stack. ADR-0005
  decision 9's *config draft* is an uncommitted form value that never
  reaches the document. They share a word and nothing else (G9d).
  """

  @behaviour StatifierBlocks.BlockType

  alias StatifierBlocks.Core.Emit

  @impl true
  def current_version, do: 1

  @impl true
  def slots(_config), do: [{"body", :any, "Drafts"}]

  @impl true
  def config_schema(_config), do: []

  @doc """
  Always `:ok`. A shelf declares no config fields, so there is nothing for
  an author to get wrong.
  """
  @impl true
  def validate_config(_config), do: :ok

  @doc """
  `kinds: [:draft_shelf]` and a `body` that accepts everything (A1).

  There is no `consumes` and no `produces`: a block that is never at either
  end of a seam has nothing to say about one, and `outcomes/1` is left to
  the default for the same reason - a shelf is not a step and is never
  sequenced into or out of, so no consumer ever asks (G9).
  """
  @impl true
  def io(_config),
    do: %{
      kinds: [:draft_shelf],
      slot_accepts: %{"body" => :any}
    }

  @impl true
  def palette_entry,
    do: %{
      label: "Drafts",
      group: "Structure",
      description: "Holds fragments that are not in the flow yet.",
      icon: "inbox",
      keywords: ["shelf", "tray", "parked", "unplaced", "scratch"],
      order: 14,
      layout: :stack,
      slot_style: %{"body" => :tray}
    }

  @doc """
  **The compiler never calls this.** ADR-0004's amendment of 2026-08-31,
  section D1, is explicit: the Emit stage does not call `emit/2` on the
  shelf or on anything under it, so a shelved block type is not
  emitting-and-discarded, it is never asked. The shelf is pruned from the
  resolved tree before the Chart-use and Emit stages run.

  The callback still has to exist, because `StatifierBlocks.BlockType`
  requires it and there is no emission a type may decline to have. It
  answers with the smallest inert thing a container can be - an empty
  compound state whose `initial` points straight at its own `<final>`,
  which is `StatifierBlocks.Core.Emit.ordered/2`'s degenerate case - rather
  than refusing, because a refusal here would be a guarantee traded for a
  gesture: it would satisfy nothing D1 claims and it would make the shared
  conformance pass exempt this one type from the shape every other core
  type answers in.

  What actually holds D1 up is the elision plus its acceptance property:
  two documents alike in everything except the contents of their shelf
  compile to byte-identical SCXML, and so does the same document with the
  shelf deleted. That is asserted directly against `Compiler.compile/3`,
  which is the only place the guarantee can be broken and therefore the
  only place worth testing it.
  """
  @impl true
  def emit(_block, context), do: Emit.ordered(context, [])
end
