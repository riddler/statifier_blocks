defmodule StatifierBlocks.Assignability do
  @moduledoc """
  May this block land in this slot? Answered by two independent gates -
  structural admission by kind tag, and data-flow compatibility by opaque
  string identity plus a host-supplied widening relation (ADR-0003).

  One implementation, consulted by both the editor (`sb-w50`) and the
  compiler (`sb-iwz`), because both are passed the same palette (ADR-0003
  decision 6).

  This module currently carries ADR-0003's seven types and four
  primitives: `io/2`, `kinds/2`, `slot_accepts/3` and `admits?/3`. These
  four are a deliberate widening of the record's own listed surface, not a
  second path around it - `check/5`, `valid_targets/4` and `validate/3`
  (later phases) are built out of them, not alongside them. They are public
  because the kind gate has to be testable in isolation, and because
  `StatifierBlocks.CoreFixtures`'s stand-in walk has to delegate to the
  shipped rule rather than keep a copy of it.

  Defaults, per ADR-0003 decision 5: an absent `io/1` callback, or a module
  that is not loadable, is `%{}`; an absent `:kinds` key is `[:step]`; an
  absent `:slot_accepts` entry for a given slot is `:any`.
  """

  alias StatifierBlocks.Block

  @typedoc "Opaque to this package. Never parsed, split, or normalized."
  @type type_expr :: String.t()

  @typedoc ~S(Structural tag. `:step` and `:interrupt_handler` ship here; hosts may mint more.)
  @type kind :: atom()

  @typedoc "What a block produces to its next sibling. See ADR-0003 decision 4."
  @type produces :: type_expr() | :unknown | {:passthrough, Block.slot_name()}

  @typedoc "The return shape of `c:StatifierBlocks.BlockType.io/1`. Every key optional."
  @type io :: %{
          optional(:kinds) => [kind()],
          optional(:consumes) => type_expr() | :unknown,
          optional(:produces) => produces(),
          optional(:slot_accepts) => %{optional(Block.slot_name()) => [kind()] | :any}
        }

  @typedoc "Caller-supplied, not stored in the document (ADR-0003 decision 4)."
  @type context :: %{optional(:entry_type) => type_expr() | :unknown}

  @typedoc "A position, as ADR-0001 decision 5 defines one."
  @type target :: {Block.id(), Block.slot_name(), non_neg_integer()}

  @type finding ::
          {:kind_not_admitted, Block.id(), Block.id(), Block.slot_name(), [kind()],
           [kind()] | :any}
          | {:type_mismatch, Block.id(), Block.id() | :slot_entry, type_expr() | :unknown,
             type_expr() | :unknown}

  @doc """
  `module.io(config)`, or `%{}` when `io/1` is absent or `module` is not
  loadable (ADR-0003 decision 5). Checked with `Code.ensure_loaded?/1` plus
  `function_exported?/3`, the pattern `StatifierBlocks.Palette.resolve/2`
  already uses.
  """
  @spec io(module(), Block.config()) :: io()
  def io(module, config) do
    if Code.ensure_loaded?(module) and function_exported?(module, :io, 1) do
      module.io(config)
    else
      %{}
    end
  end

  @doc "The block's `kinds`, defaulting to `[:step]` (ADR-0003 decision 5)."
  @spec kinds(module(), Block.config()) :: [kind()]
  def kinds(module, config), do: Map.get(io(module, config), :kinds, [:step])

  @doc """
  The accepted kinds for `slot` on `module`, defaulting to `:any` when the
  slot has no entry in `io/1`'s `:slot_accepts` map (ADR-0003 decision 5).
  """
  @spec slot_accepts(module(), Block.config(), Block.slot_name()) :: [kind()] | :any
  def slot_accepts(module, config, slot) do
    module
    |> io(config)
    |> Map.get(:slot_accepts, %{})
    |> Map.get(slot, :any)
  end

  @doc """
  ADR-0003 decision 3's structural verdict for placing `child` in `slot` of
  `parent`: `:any` admits everything, otherwise the slot's accepted kinds
  and the child's own kinds must intersect.
  """
  @spec admits?({module(), Block.config()}, Block.slot_name(), {module(), Block.config()}) ::
          boolean()
  def admits?({parent, parent_config}, slot, {child, child_config}) do
    case slot_accepts(parent, parent_config, slot) do
      :any -> true
      accepted -> Enum.any?(kinds(child, child_config), &(&1 in accepted))
    end
  end
end
