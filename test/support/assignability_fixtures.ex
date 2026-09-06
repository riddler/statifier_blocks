defmodule StatifierBlocks.AssignabilityFixtures do
  @moduledoc """
  Test-only support for ADR-0003's worked example, re-expressed in the
  family's canonical credit-card example domain (the umbrella's
  `docs/terminology-firewall.md`, "Example domains"). `CoreFixtures`
  carries the `myapp.*` types the ADR-0001 worked example names, plus
  `sb-da9`'s stand-in walk; this module carries ADR-0003's own worked
  example instead - `myapp.authorize` / `myapp.settle` /
  `myapp.post_to_ledger` / `myapp.on_chargeback`, plus the widening
  vocabulary (`myapp.credit_card_txn` / `myapp.settled_txn` /
  `myapp.card_txn`) that needs a host relation to interpret.

  The re-skin is **structurally isomorphic** to the table in ADR-0003, not
  a change to it: every row still exercises the same step of decision 6's
  ordered relation. Authorize into settle is identity (step 2); settle into
  post-to-ledger is not identity and reaches the host relation (step 4);
  settle back into authorize is a `:type_mismatch` even with the relation;
  and the handler gives both directions of the kind gate. The record itself
  is unchanged and still spells its example in its own vocabulary - reading
  the two side by side means mapping the names, not the structure.

  Two `StatifierBlocks.Assignability.Relation` implementations: `Widens`,
  the record's `MyApp.Blocks.Types` re-skinned the same way, and `Deny`,
  which answers `false` to everything - the floor case a widen-only
  relation can never fall below.

  `test/support/` carries one subject per file, and this one's subject is
  ADR-0003's worked example end to end: the types, the two relation
  modules, `palette/1` to point a palette at one of them, and the
  worked-example document itself.
  """

  alias StatifierBlocks.{Assignability, Block, Document, Palette}

  defmodule Authorize do
    @moduledoc "`myapp.authorize`: takes a transaction, hands back a card authorization."

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
    def io(_config), do: %{consumes: "myapp.transaction", produces: "myapp.credit_card_txn"}
    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}

    # ADR-0011 decision 6: the subject path the document's `consumes` and
    # `produces` desugar against. Every type here names the same one, so
    # whichever of them a fixture document opens with is a real entry block.
    @impl true
    def palette_entry, do: %{label: "Authorize", subject: "cards.current_txn"}
  end

  defmodule Settle do
    @moduledoc "`myapp.settle`: takes a card authorization, hands back a settled transaction."

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
    def io(_config), do: %{consumes: "myapp.credit_card_txn", produces: "myapp.settled_txn"}
    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}

    # ADR-0011 decision 6: the subject path the document's `consumes` and
    # `produces` desugar against. Every type here names the same one, so
    # whichever of them a fixture document opens with is a real entry block.
    @impl true
    def palette_entry, do: %{label: "Settle", subject: "cards.current_txn"}
  end

  defmodule PostToLedger do
    @moduledoc """
    `myapp.post_to_ledger`: takes any card transaction; produces nothing
    anyone downstream wants.
    """

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
    def io(_config), do: %{consumes: "myapp.card_txn", produces: :unknown}
    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}

    # ADR-0011 decision 6: the subject path the document's `consumes` and
    # `produces` desugar against. Every type here names the same one, so
    # whichever of them a fixture document opens with is a real entry block.
    @impl true
    def palette_entry, do: %{label: "Post to ledger", subject: "cards.current_txn"}
  end

  defmodule OnChargeback do
    @moduledoc "`myapp.on_chargeback`: not a step at all - an interrupt handler."

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
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}

    # ADR-0011 decision 6: the subject path the document's `consumes` and
    # `produces` desugar against. Every type here names the same one, so
    # whichever of them a fixture document opens with is a real entry block.
    @impl true
    def palette_entry, do: %{label: "On chargeback", subject: "cards.current_txn"}
  end

  defmodule Widens do
    @moduledoc """
    ADR-0003's worked-example relation, re-skinned onto the canonical
    credit-card domain: `myapp.credit_card_txn` and `myapp.debit_card_txn`
    both widen to `myapp.card_txn`, and `myapp.settled_txn` widens to
    either. Same three-deep shape as the record's own `MyApp.Blocks.Types`,
    so the "widening only ever grows the accepted set" property still has
    something to grow.
    """

    @behaviour StatifierBlocks.Assignability.Relation

    @widens %{
      "myapp.credit_card_txn" => ["myapp.card_txn"],
      "myapp.debit_card_txn" => ["myapp.card_txn"],
      "myapp.settled_txn" => ["myapp.credit_card_txn", "myapp.card_txn"]
    }

    @impl true
    def assignable?(produced, consumed), do: consumed in Map.get(@widens, produced, [])
  end

  defmodule Deny do
    @moduledoc """
    The floor case: a relation module that answers `false` to every pair,
    demonstrating that a host callback can never narrow the identity
    relation - it can only fail to widen it further.
    """

    @behaviour StatifierBlocks.Assignability.Relation

    @impl true
    def assignable?(_produced, _consumed), do: false
  end

  @doc "The `myapp.*` types ADR-0003's worked example names."
  @spec host_types() :: %{Block.type_name() => module()}
  def host_types do
    %{
      "myapp.authorize" => Authorize,
      "myapp.settle" => Settle,
      "myapp.post_to_ledger" => PostToLedger,
      "myapp.on_chargeback" => OnChargeback
    }
  end

  @doc """
  The core vocabulary plus the worked example's host types, on a palette
  pointed at `assignability` (default `Widens`). Pass `nil` for the palette
  ADR-0003 decision 6 step 3 describes: no widening relation at all.
  """
  @spec palette(module() | nil) :: Palette.t()
  def palette(assignability \\ Widens) do
    Palette.new(Map.merge(Palette.core_types(), host_types()), assignability: assignability)
  end

  @doc """
  ADR-0003's own worked-example document: the ADR-0001 worked example's
  root sequence, a `myapp.settle` step (`blk_STL`) added after the authorize,
  and the resumable group (`blk_GRP`) left with empty `body`/`interrupts`
  slots - Phase 4's `check/5` table only ever asks about kind admission
  once inside them, and an empty slot is the total, permissive answer for
  everything downstream of that. Fixed ids, so a caller can name any
  position directly:

    * `"blk_ROOT"` - `core.sequence`, `body: [blk_AUTH, blk_STL, blk_GRP]`
    * `"blk_AUTH"` - `myapp.authorize`
    * `"blk_STL"` - `myapp.settle`
    * `"blk_GRP"` - `core.resumable_group`, empty `body` and `interrupts`

  Pair with `worked_example_context/0` for the entry type ADR-0003's own
  table reads from.
  """
  @spec worked_example_document() :: Document.t()
  def worked_example_document do
    authorize = Block.new("myapp.authorize", id: "blk_AUTH")
    settle = Block.new("myapp.settle", id: "blk_STL")

    group =
      Block.new("core.resumable_group", id: "blk_GRP", slots: %{"body" => [], "interrupts" => []})

    root =
      Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [authorize, settle, group]})

    Document.new(root, id: "bdoc_worked_example")
  end

  @doc "The entry type ADR-0003's worked example supplies: `\"myapp.transaction\"`."
  @spec worked_example_context() :: Assignability.context()
  def worked_example_context, do: %{entry_type: "myapp.transaction"}
end
