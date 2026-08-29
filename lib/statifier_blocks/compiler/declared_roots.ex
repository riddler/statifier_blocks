defmodule StatifierBlocks.Compiler.DeclaredRoots do
  @moduledoc """
  How a block type contributes a **compiler-declared `<data>` root** to the
  chart's one top-level `<datamodel>` (ADR-0004's 2026-08-29 foreach
  amendment, F2 and F3), and the collision refusal F6 records.

  Until `core.foreach` there was no such thing: every core type wrote into
  the datamodel the host had already declared, and the compiler emitted no
  `<datamodel>` at all. A loop cannot. Its cursor and its snapshot of the
  list are the compiler's own state, its `item_as`/`index_as` bindings are
  roots an author named, and predicator refuses to read a root nothing
  declared - so the four names have to be declared somewhere, and early
  binding means "somewhere" is the top of the document, before any state
  is entered.

  ## The mechanism: declare in place, hoist once

  A block type emits `declare/2` elements **among its own state's
  children**, where everything else it emits already is, and the compiler
  lifts every one of them out of the assembled emission into a single
  top-level `<datamodel>` just before serialization (`hoist/1`).

  Declaring in place rather than through a new `StatifierBlocks.BlockType`
  callback is what keeps this small. A callback would be a change to
  ADR-0002's declaration surface for one block type's benefit; a `<data>`
  element is something `emit/2` can already return, it goes through
  `StatifierBlocks.Compiler.Attribution` on the ordinary path, and so it
  arrives here already carrying the owner and the config key a finding
  against it needs. Nothing about the block type's contract changes.

  ### Determinism (decision 6)

  `hoist/1` walks the assembled tree in document order and emits the roots
  in the order it meets them, outermost first. The walk is over lists, in
  the order `emit/2` built them, so the same document produces the same
  bytes - the property decision 6 requires and the reason no sort happens
  here. A document declaring no roots gets **no `<datamodel>` element at
  all**, so every chart this package compiled before this mechanism
  existed still compiles to the same bytes.

  ### Provenance (decision 5)

  A hoisted element is moved, never rebuilt: it carries the owner
  Attribution stamped on it, so the provenance map stays total over the
  bytes it becomes. The `<datamodel>` wrapper belongs to no block and is
  attributed to the root block, exactly as `<scxml>` is.

  ## F6: `:duplicate_binding`

  Early binding makes a declared root global, so a nested loop re-using an
  enclosing loop's `item_as` would overwrite the outer binding and the
  outer body would carry on with the inner loop's last item. The compiler
  refuses the document instead: a root declared **inside** the subtree of
  a block that already declares the same name is a `:duplicate_binding`
  finding, reported by `StatifierBlocks.Compiler` as an Emit-stage error
  against the block whose binding collides, carrying the `config_key` the
  name was typed into (`item_as` or `index_as`) and therefore the author's
  fault.

  The rule this module applies is **nesting**, not the whole document -
  "collide across nesting", as F6 words it - and that is deliberately the
  narrow carve-out from decision 9's delegation rather than a general
  id-uniqueness check. Two roots of one name that are *not* nested are
  still refused, one stage later and by the delegated check: statifier's
  own id-uniqueness pass reports `{:duplicate_id, name}` over the two
  `<data>` elements, and `StatifierBlocks.Compiler.Chart` maps it back to
  the declaring block and its config field. F6 describes itself as
  pre-empting exactly that finding for the case where the overwrite would
  otherwise be silent, and pre-empting it anywhere else would be a
  widening of decision 9 this module has no mandate for.

  Author-declared `<data>` ids, F6's other half, are covered by the same
  walk the day they exist: the package has no author-facing `<data>`
  declaration concept today - no block type emits one and no config field
  declares one - so the only roots in the tree are the compiler's own.
  Nothing here special-cases `core.foreach`, so an author declaration
  arriving as a `<data>` element is checked against the loops beneath it
  without this module being touched.
  """

  alias StatifierBlocks.{Block, Emission}

  @data "data"
  @datamodel "datamodel"

  @typedoc """
  One collision: the block whose binding collides, the config key it was
  typed into (`nil` for a root no author named), and the offending name.
  """
  @type finding :: {:duplicate_binding, Block.id() | nil, String.t() | nil, String.t()}

  @doc """
  A `<data>` declaration for the root `id`, optionally with an initial
  `expr`.

  A root declared with no `expr` reads as `undefined` until something
  assigns it, which is what the loop's bindings want: `item_as` means
  nothing until the head state's first pass binds it.
  """
  @spec declare(String.t(), String.t() | nil) :: Emission.t()
  def declare(id, expr \\ nil) when is_binary(id) do
    Emission.element(@data, [{"id", id}, {"expr", expr}])
  end

  @doc """
  Lifts every `<data>` element out of `emission`, returning the stripped
  tree and the roots in document order.

  `{:error, findings}` when a root is declared inside the subtree of a
  block that already declares the same name (F6).
  """
  @spec hoist(Emission.t()) ::
          {:ok, {Emission.t(), [Emission.t()]}} | {:error, [finding()]}
  def hoist(%Emission{} = emission) do
    {stripped, roots, findings} = lift(emission, MapSet.new())

    case findings do
      [] -> {:ok, {stripped, roots}}
      _collisions -> {:error, findings}
    end
  end

  @doc """
  The top-level `<datamodel>` holding `roots`, or nothing at all when
  there are none.

  A list rather than a value, so the caller splices it into `<scxml>`'s
  children without a conditional - and so "no roots, no element" is this
  module's decision rather than every caller's.
  """
  @spec datamodel([Emission.t()]) :: [Emission.t()]
  def datamodel([]), do: []
  def datamodel(roots) when is_list(roots), do: [Emission.element(@datamodel, [], roots)]

  # The walk. `in_scope` is the set of root names declared by enclosing
  # elements - which, because a block's emission nests inside its
  # parent's, is exactly "declared by an enclosing block".
  @spec lift(Emission.node_t(), MapSet.t(String.t())) ::
          {Emission.node_t(), [Emission.t()], [finding()]}
  defp lift(%Emission{children: children} = emission, in_scope) do
    {declarations, rest} = Enum.split_with(children, &data?/1)
    {own_roots, scope, own_findings} = own(declarations, in_scope)
    {kept, nested_roots, nested_findings} = descend(rest, scope)

    {%{emission | children: kept}, own_roots ++ nested_roots, own_findings ++ nested_findings}
  end

  # A `{:child, _}` placeholder. Unreachable in the compiler - the
  # children are spliced before this runs - and answered rather than
  # matched away, because a walk that raises on a shape it can be handed
  # is a walk with a second contract nobody wrote down.
  defp lift(other, _in_scope), do: {other, [], []}

  @spec own([Emission.t()], MapSet.t(String.t())) ::
          {[Emission.t()], MapSet.t(String.t()), [finding()]}
  defp own(declarations, in_scope) do
    {roots, scope, findings} =
      Enum.reduce(declarations, {[], in_scope, []}, fn declaration, {roots, scope, findings} ->
        name = name(declaration)

        if MapSet.member?(scope, name) do
          {roots, scope, [collision(declaration, name) | findings]}
        else
          {[declaration | roots], MapSet.put(scope, name), findings}
        end
      end)

    {Enum.reverse(roots), scope, Enum.reverse(findings)}
  end

  @spec descend([Emission.node_t()], MapSet.t(String.t())) ::
          {[Emission.node_t()], [Emission.t()], [finding()]}
  defp descend(children, scope) do
    {kept, roots, findings} =
      Enum.reduce(children, {[], [], []}, fn child, {kept, roots, findings} ->
        {stripped, child_roots, child_findings} = lift(child, scope)

        {[stripped | kept], [child_roots | roots], [child_findings | findings]}
      end)

    {Enum.reverse(kept), roots |> Enum.reverse() |> Enum.concat(),
     findings |> Enum.reverse() |> Enum.concat()}
  end

  @spec data?(Emission.node_t()) :: boolean()
  defp data?(%Emission{name: @data}), do: true
  defp data?(_node), do: false

  @spec name(Emission.t()) :: String.t()
  defp name(%Emission{attributes: attributes}) do
    case List.keyfind(attributes, "id", 0) do
      {"id", id} -> id
      nil -> ""
    end
  end

  @spec collision(Emission.t(), String.t()) :: finding()
  defp collision(%Emission{owner: %{block_id: block_id, config_key: config_key}}, name),
    do: {:duplicate_binding, block_id, config_key, name}

  defp collision(%Emission{}, name), do: {:duplicate_binding, nil, nil, name}
end
