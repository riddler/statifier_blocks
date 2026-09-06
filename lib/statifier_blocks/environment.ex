defmodule StatifierBlocks.Environment do
  @moduledoc """
  What is known at a position: a map from datamodel path to type, carried
  through the document by a pre-order walk (ADR-0011 decision 1).

  Nothing flows between adjacent blocks. Every value a block produces is
  written to a datamodel path by name and every value it reads is read from
  one, so the data-flow question at a position is a question about the paths
  the document has written on the way there - not about the block before it.

  ## The type of a type

  A type is one of the nine the datamodel document closes its set at, the
  `name` of a `record` or `shape` that document declares, an opaque string a
  host carries, `{:list, type}`, or `:unknown`. This module mints none of
  them: every one arrives from a block's own declaration or from the
  document. `type_of/2` reads a declaration's spelling into
  `t:StatifierDatamodel.Types.t/0` and `satisfies/3` hands the pair to
  `StatifierDatamodel.Types.satisfies/3`, which is the read check
  (ADR-0011 decision 3). There is no second one here, and no `Compatibility`
  or `Coverage` module of this package's own.

  The string `"unknown"` reads as `:unknown` rather than as an opaque string
  spelled that way, so that `StatifierDatamodel.Types.to_string/1` and
  `type_of/2` are inverse over the whole grammar. It is the one
  reinterpretation of an expression a host could already have been carrying,
  and it only ever admits: an opaque `"unknown"` compared by identity was
  already satisfied against another `"unknown"`, so nothing that passed
  before is refused now.

  ## The walk

  `Document.blocks/1`'s pre-order, carrying the environment forward. For a
  block reached with environment `env`:

    * each slot the block carries is walked from `env` - the shelf is not
      entered (ADR-0003's amendment of 2026-08-31, A2), and each parked
      fragment is walked from an empty environment instead;
    * what the slots produce is merged per path by agreement (decision 4):
      a path every slot holds at one type keeps it, a path some hold and
      others do not - or hold differently - drops to `:unknown`, and a path
      no slot holds is absent;
    * the block's own write signatures are applied to the merge.

  A container with one slot merges to that slot's own answer, so a group
  body's writes leave the group. A `core.on_event` in a group's interrupt
  slot writes its captures on that arm alone, so a path only it holds leaves
  the group at `:unknown` - decision 10's answer, arrived at by decision 4
  rather than by a special case.

  ## Why the walk terminates

  It descends. `at/3` asks `StatifierBlocks.Document.fetch_path/2` for the
  path from the root to the position it was given, and then walks **down**
  that path once, carrying the environment: each step folds the siblings
  before it and moves to a strictly deeper block, and the path is finite
  because the document is a finite tree. Nothing here asks an ancestor for
  its own position, so there is no recursion to bound and a document built of
  nothing but empty sequences costs one step per level - which is also why
  the answer stays cheap enough for the editor to compute on mousedown.

  ## Signatures

  A block declares what it reads and writes on its **fields**, not on itself
  (ADR-0011 decision 2), so a finding anchors on the field key the author has
  to change:

    * `{:path, %{writes: T}}` writes `T` at the path the field's value names;
    * a `{:path, opts}` field with no `writes` key, and a field carrying
      `datamodel_path?: true`, write `:unknown` there - the path becomes
      known without becoming typed;
    * a `capture` config map writes `:unknown` at each of its keys, one per
      pair;
    * `{:path, %{expects: T}}` reads `T` there.

  `io/1`'s `consumes` and `produces` are sugar over the **subject path**,
  which the entry block's palette entry names with `subject:` (decision 6):
  `consumes` is a read there and `produces` is a write there. A document whose
  entry block declares no subject has no subject path, and the sugar is inert.
  A `produces` of `:unknown` writes nothing rather than blanking the subject -
  a container that says nothing about the subject leaves it alone, which is
  the whole gain decision 4's per-path merge exists for.
  """

  alias StatifierBlocks.{Block, BlockType, Document, Palette, Shelf}
  alias StatifierDatamodel.{Declarations, Types}

  @typedoc """
  A type at a path. One of `t:StatifierDatamodel.Types.t/0`'s inhabitants as
  a document spells it - a scalar name, a declared name, an opaque string -
  or `:unknown`, or a list of one of those.
  """
  @type type_expr :: String.t() | :unknown | {:list, type_expr()}

  @typedoc "Datamodel path to type. ADR-0011 decision 1's environment."
  @type t :: %{optional(String.t()) => type_expr()}

  @typedoc """
  The environment with the block that wrote each entry, which is what
  ADR-0011 decision 8's `upstream_ref` names. `:slot_entry` is the seed, or a
  merge whose arms agreed on a type without agreeing on who put it there.
  """
  @type annotated :: %{optional(String.t()) => {type_expr(), Block.id() | :slot_entry}}

  @typedoc """
  Caller-supplied, not stored in the document. `:datamodel` is the datamodel
  document the declarations are read from; `:entry_type` seeds the subject
  path for a document whose entry block declares no `produces` of its own.
  """
  @type context :: %{
          optional(:entry_type) => type_expr(),
          optional(:datamodel) => term()
        }

  @typedoc "A position, as ADR-0001 decision 5 defines one."
  @type target :: {Block.id(), Block.slot_name(), non_neg_integer()}

  @typedoc """
  One declared read or write: the field key it is declared on (or
  `:consumes` / `:produces` for the sugar, and `:capture` for a capture
  pair), the path it names, and the type.
  """
  @type signature :: {key :: String.t() | atom(), path :: String.t(), type_expr()}

  # The config key `core.on_event` stores its capture pairs under. It carries
  # no field declaration - ADR-0002's Note of 2026-09-05 records why - so the
  # walk reads the config directly, which is what ADR-0011 decision 2's third
  # write-signature form asks for.
  @capture_key "capture"

  @doc """
  The environment at `target`, as a map from datamodel path to type.

  `target` is a position `{parent_id, slot, index}`: the answer is what the
  block at that index sees, before its own writes are applied. Total - a
  parent no block carries, or an index past the end of a slot, answers with
  whatever the walk reached, never a raise.
  """
  @spec at(Palette.t(), Document.t(), target(), context()) :: t()
  def at(%Palette{} = palette, %Document{} = document, target, ctx \\ %{}) do
    palette |> annotated(document, target, ctx) |> strip()
  end

  @doc """
  `at/3`, keeping the block that wrote each entry.

  ADR-0011 decision 8's `{:type_mismatch, ...}` names the block whose write
  signature the read disagrees with, and this is where that name comes from.
  """
  @spec annotated(Palette.t(), Document.t(), target(), context()) :: annotated()
  def annotated(%Palette{} = palette, %Document{} = document, target, ctx \\ %{}) do
    {parent_id, slot, index} = target

    case Document.fetch_path(document, parent_id) do
      :error ->
        %{}

      {:ok, steps} ->
        {parent, env} =
          descend(
            palette,
            document,
            document.root,
            steps,
            seed_annotated(palette, document, ctx),
            ctx
          )

        into_slot(palette, document, parent, slot, index, env, ctx)
    end
  end

  # The environment reaching `parent`, found by walking **down** from the
  # root along the path `Document.fetch_path/2` already computed, rather than
  # by asking each ancestor for its own position in turn. One descent per
  # query: a document nested a thousand deep costs a thousand steps, not a
  # thousand walks of the whole document.
  @spec descend(
          Palette.t(),
          Document.t(),
          Block.t(),
          Document.path(),
          annotated(),
          context()
        ) :: {Block.t(), annotated()}
  defp descend(_palette, _document, block, [], env, _ctx), do: {block, env}

  defp descend(palette, document, block, [{_parent_id, slot, index} | rest], env, ctx) do
    case block.slots |> Map.get(slot, []) |> Enum.at(index) do
      nil ->
        {block, env}

      child ->
        env = into_slot(palette, document, block, slot, index, env, ctx)
        descend(palette, document, child, rest, env, ctx)
    end
  end

  # The environment at index `index` of `block`'s `slot`: the slot's own
  # starting environment folded over the children before it. A position past
  # the end of the slot is not a position - `index` runs from 0 to the child
  # count inclusive, the last of them being where an append lands - and holds
  # nothing rather than silently answering for the end of the slot.
  @spec into_slot(
          Palette.t(),
          Document.t(),
          Block.t(),
          Block.slot_name(),
          non_neg_integer(),
          annotated(),
          context()
        ) :: annotated()
  defp into_slot(palette, document, block, slot, index, env, ctx) do
    children = Map.get(block.slots, slot, [])

    if index > length(children) do
      %{}
    else
      children
      |> Enum.take(index)
      |> Enum.reduce(
        slot_start(palette, block, slot, env),
        &through(palette, document, &1, &2, ctx)
      )
    end
  end

  @doc """
  The environment the document opens with (ADR-0011 decision 2).

  `ctx[:entry_type]` at the subject path, and nothing else. It is ADR-0003
  decision 4's context key, kept meaning what it meant - the type entering the
  document - now that the document has a path to hold it at. A document with
  no entry block, or one whose palette entry declares no `subject:`, seeds
  empty however the context is filled: with no subject path there is nowhere
  for a subject type to be. Every read is then a read of a path the
  environment does not hold, which is an advisory and not an error, so an
  untyped document validates exactly as it did.

  The entry block's own writes are **not** applied here. Decision 2 says the
  document opens with its subject path holding its subject type, and the walk
  is what puts it there: the entry block is the first position walked, so
  every position after it sees exactly that. Applying its writes ahead of the
  walk would additionally put them in front of the entry block's *own* reads,
  and decision 1 is explicit that a block's reads are checked before its own
  writes are applied - a block does not read what it is about to write.
  """
  @spec seed(Palette.t(), Document.t(), context()) :: t()
  def seed(%Palette{} = palette, %Document{} = document, ctx \\ %{}) do
    palette |> seed_annotated(document, ctx) |> strip()
  end

  @doc """
  The datamodel path the document's subject lives at, or `nil`.

  ADR-0011 decision 6: the `subject:` key on the **entry block's**
  `palette_entry/0` - the first block of the root's `body` slot. `nil` means
  the document has no subject, and `consumes` and `produces` desugar to
  nothing at all.
  """
  @spec subject_path(Palette.t(), Document.t()) :: String.t() | nil
  def subject_path(%Palette{} = palette, %Document{} = document) do
    case entry_block(document) do
      nil ->
        nil

      block ->
        case Palette.resolve(palette, block) do
          {:ok, module, _resolved} -> subject_of(module)
          {:error, _reason} -> nil
        end
    end
  end

  @doc """
  Every read `block` declares, in `config_schema/1` order with the
  `consumes` sugar last.

  A block with three path fields declares three reads and they are
  independent (ADR-0011 decision 2).
  """
  @spec read_signatures(Palette.t(), Document.t(), Block.t()) :: [signature()]
  def read_signatures(%Palette{} = palette, %Document{} = document, %Block{} = block) do
    case Palette.resolve(palette, block) do
      {:ok, module, resolved} ->
        field_reads(module, resolved.config) ++
          sugar_read(palette, document, module, resolved.config)

      {:error, _reason} ->
        []
    end
  end

  @doc """
  Every write `block` declares, in `config_schema/1` order, then its capture
  pairs, then the `produces` sugar (ADR-0011 decision 2).
  """
  @spec write_signatures(Palette.t(), Document.t(), Block.t()) :: [signature()]
  def write_signatures(%Palette{} = palette, %Document{} = document, %Block{} = block) do
    case Palette.resolve(palette, block) do
      {:ok, module, resolved} ->
        field_writes(module, resolved.config) ++
          capture_writes(resolved.config) ++
          sugar_write(palette, document, module, resolved.config)

      {:error, _reason} ->
        []
    end
  end

  @doc """
  The declarations `ctx[:datamodel]` carries, or an empty index.

  `StatifierDatamodel.Declarations.from_document/1` is total: a datamodel
  that is not a document, or one with no `types` key, declares nothing rather
  than failing, and a walk over it produces `:unknown` and not an exception.
  """
  @spec declarations(context()) :: Declarations.t()
  def declarations(ctx) when is_map(ctx) do
    ctx |> Map.get(:datamodel) |> Declarations.from_document()
  end

  @doc """
  Reads a declared spelling into a type expression.

  Total, and it defers to `StatifierDatamodel.Types.parse/2` for everything
  the grammar already covers. Two readings are this package's own: the atom
  `:unknown` and the string `"unknown"` are both `:unknown`, and a
  `{:list, _}` is the document's own `list` - ADR-0011 decision 14 puts no
  cardinality on a read, so a list is checked as a list and its item type is
  carried for a fan-out to bind, not for the check to descend into.
  """
  @spec type_of(Declarations.t(), term()) :: Types.t()
  def type_of(_declarations, :unknown), do: :unknown
  def type_of(_declarations, "unknown"), do: :unknown
  def type_of(_declarations, {:list, _item}), do: :list
  def type_of(declarations, spelling), do: Types.parse(declarations, spelling)

  @doc """
  How a type expression is written for a human (ADR-0011 decision 9).

  A spelling that names a declaration in `declarations` renders that
  declaration's **label**, which is the human-readable name the record asks a
  finding and the Datamodel tab to carry so an author reads "Credit card
  transaction" instead of a nominal name they have to go and look up. Every
  other spelling renders exactly as it did before there were declarations:
  one of the nine scalars as its own word, an opaque string a host carries as
  itself, `:unknown` as `unknown`, and a list as what it holds.

  It is a **rendering** and nothing else. No verdict reads it, nothing
  branches on it, and a declaration whose `label` is absent renders its name
  - so a document that declares types without labelling them shows exactly
  what it showed before, rather than a blank where a name used to be.

      iex> alias StatifierBlocks.Environment
      iex> declarations = StatifierDatamodel.Declarations.from_document(%{"types" => [
      ...>   %{"name" => "cards.credit_txn", "kind" => "record",
      ...>     "label" => "Credit card transaction", "fields" => []}]})
      iex> Environment.type_label(declarations, "cards.credit_txn")
      "Credit card transaction"
      iex> Environment.type_label(declarations, "myapp.card_txn")
      "myapp.card_txn"
      iex> Environment.type_label(declarations, :unknown)
      "unknown"
      iex> Environment.type_label(declarations, {:list, "cards.credit_txn"})
      "list of Credit card transaction"
  """
  @spec type_label(Declarations.t(), term()) :: String.t()
  def type_label(_declarations, :unknown), do: "unknown"
  def type_label(declarations, {:list, item}), do: "list of " <> type_label(declarations, item)

  def type_label(declarations, spelling) when is_binary(spelling) do
    case Declarations.fetch(declarations, spelling) do
      {:ok, %{label: label}} when is_binary(label) and label != "" -> label
      _undeclared_or_unlabelled -> spelling
    end
  end

  def type_label(_declarations, other), do: inspect(other)

  @doc """
  The read check: `StatifierDatamodel.Types.satisfies/3` over the two
  spellings, and nothing else (ADR-0011 decision 3).

  The palette's host relation is not asked here. It runs **last**, after this
  returns not-satisfied, in `StatifierBlocks.Assignability.assignable?/4`.
  """
  @spec satisfies(Declarations.t(), term(), term()) :: Types.reason()
  def satisfies(declarations, held, expected) do
    Types.satisfies(declarations, type_of(declarations, held), type_of(declarations, expected))
  end

  # -- the walk --------------------------------------------------------------

  # One block's contribution: its slots merged, then its own writes. The
  # shelf is not entered and declares nothing, so it passes the environment
  # through untouched.
  @spec through(Palette.t(), Document.t(), Block.t(), annotated(), context()) :: annotated()
  defp through(palette, document, %Block{} = block, env, ctx) do
    if Shelf.shelf?(block) do
      env
    else
      env
      |> arms(palette, document, block, ctx)
      |> apply_writes(palette, document, block)
    end
  end

  # Decision 4's merge over the block's slots, each walked from the
  # environment as it reaches the container. Slots are visited in the sorted
  # order `Document.blocks/1` already fixes, so the answer does not depend on
  # how the slots map was built - and the merge is order-independent anyway.
  @spec arms(annotated(), Palette.t(), Document.t(), Block.t(), context()) :: annotated()
  defp arms(env, palette, document, %Block{slots: slots} = block, ctx) do
    case slots |> Enum.sort_by(&elem(&1, 0)) |> Enum.reject(fn {_name, kids} -> kids == [] end) do
      [] ->
        env

      populated ->
        populated
        |> Enum.map(fn {name, children} ->
          slot_env(palette, document, block, name, children, env, ctx)
        end)
        |> merge()
    end
  end

  # One slot, folded left to right. A fan-out's body sees its item and index
  # bound (decision 11) and they do not leave it: the names are scoped to the
  # body, so what the arm contributes is what it contributed before the
  # binding for those two paths.
  @spec slot_env(
          Palette.t(),
          Document.t(),
          Block.t(),
          Block.slot_name(),
          [Block.t()],
          annotated(),
          context()
        ) :: annotated()
  defp slot_env(palette, document, block, slot, children, env, ctx) do
    bound = slot_start(palette, block, slot, env)
    scoped = Map.keys(bound) -- Map.keys(env)

    walked = Enum.reduce(children, bound, &through(palette, document, &1, &2, ctx))

    walked
    |> Map.drop(scoped)
    |> Map.merge(Map.take(env, scoped))
  end

  # The environment a slot's first child sees: the environment reaching the
  # container, plus a fan-out's item and index bindings, and nothing at all
  # inside a `core.drafts` shelf - a parked fragment reads nothing as known
  # because nothing put it there.
  @spec slot_start(Palette.t(), Block.t(), Block.slot_name(), annotated()) :: annotated()
  defp slot_start(palette, %Block{} = block, slot, env) do
    if Shelf.shelf?(block) do
      %{}
    else
      Map.merge(env, fan_out_bindings(palette, block, slot, env))
    end
  end

  # Decision 11: a fan-out binds the names a child sees its item and its
  # position under, inside the body it fans out over. The names are the
  # block's own `item_as` and `index_as` with the defaults `item` and
  # `index`; the item's type is the item type of the list the block reads,
  # when the environment holds one, and the position is an integer.
  #
  # A block is a fan-out here when it declares a datamodel-path field called
  # `items` and carries a slot called `body` - a declaration-driven test
  # rather than a list of type names, so a host fan-out is bound the same way
  # `core.foreach` is.
  @spec fan_out_bindings(
          Palette.t(),
          Block.t(),
          Block.slot_name(),
          annotated()
        ) :: annotated()
  defp fan_out_bindings(palette, block, "body", env) do
    case Palette.resolve(palette, block) do
      {:ok, module, resolved} ->
        fan_out_bindings_for(module, resolved.config, block, env)

      {:error, _reason} ->
        %{}
    end
  end

  defp fan_out_bindings(_palette, _block, _slot, _env), do: %{}

  @spec fan_out_bindings_for(module(), Block.config(), Block.t(), annotated()) :: annotated()
  defp fan_out_bindings_for(module, config, block, env) do
    case items_path(module, config) do
      nil ->
        %{}

      items_path ->
        %{
          name(config, "item_as", "item") => {item_type(env, items_path), block.id},
          name(config, "index_as", "index") => {"integer", block.id}
        }
    end
  end

  @spec items_path(module(), Block.config()) :: String.t() | nil
  defp items_path(module, config) do
    config
    |> schema(module)
    |> Enum.find(&(Map.get(&1, :key) == "items" and BlockType.datamodel_path?(&1)))
    |> case do
      nil -> nil
      decl -> path_value(config, decl)
    end
  end

  @spec item_type(annotated(), String.t()) :: type_expr()
  defp item_type(env, items_path) do
    case Map.get(env, items_path) do
      {{:list, item}, _writer} -> item
      _absent_or_not_a_list -> :unknown
    end
  end

  @spec name(Block.config(), String.t(), String.t()) :: String.t()
  defp name(config, key, default) do
    case Map.get(config, key) do
      declared when is_binary(declared) and declared != "" -> declared
      _absent_or_blank -> default
    end
  end

  # Decision 4, and there is nothing else: a path every arm holds at one type
  # keeps it, a path some arms hold and others do not - or hold at a different
  # type - is `:unknown`, and a path no arm holds is absent. An arm holding a
  # path at `:unknown` agrees with nothing, which the same rule already says.
  #
  # The writer survives only when the arms agree on it too. Arms that agree on
  # a type by writing it in two places name no single declaration to change,
  # so the entry falls back to `:slot_entry` and a refusal there says
  # `:not_assignable` rather than pointing at one of them.
  @spec merge([annotated()]) :: annotated()
  defp merge([single]), do: single

  defp merge(envs) do
    count = length(envs)

    envs
    |> Enum.flat_map(&Map.keys/1)
    |> Enum.uniq()
    |> Enum.flat_map(fn path -> merged_entry(envs, path, count) end)
    |> Map.new()
  end

  @spec merged_entry([annotated()], String.t(), pos_integer()) ::
          [{String.t(), {type_expr(), Block.id() | :slot_entry}}]
  defp merged_entry(envs, path, count) do
    held = for env <- envs, {:ok, entry} <- [Map.fetch(env, path)], do: entry

    case {length(held), Enum.uniq(held)} do
      {^count, [single]} -> [{path, single}]
      {^count, entries} -> [{path, merged_disagreement(entries)}]
      _held_by_some -> [{path, {:unknown, :slot_entry}}]
    end
  end

  # Every arm holds the path, and they did not agree entry for entry. They
  # may still agree on the type and differ only on who wrote it.
  @spec merged_disagreement([{type_expr(), Block.id() | :slot_entry}]) ::
          {type_expr(), Block.id() | :slot_entry}
  defp merged_disagreement(entries) do
    case entries |> Enum.map(&elem(&1, 0)) |> Enum.uniq() do
      [single_type] -> {single_type, :slot_entry}
      _disagreed -> {:unknown, :slot_entry}
    end
  end

  @spec apply_writes(annotated(), Palette.t(), Document.t(), Block.t()) :: annotated()
  defp apply_writes(env, palette, document, %Block{} = block) do
    palette
    |> write_signatures(document, block)
    |> Enum.reduce(env, fn {_key, path, type}, acc -> Map.put(acc, path, {type, block.id}) end)
  end

  # -- the seed --------------------------------------------------------------

  @spec seed_annotated(Palette.t(), Document.t(), context()) :: annotated()
  defp seed_annotated(palette, document, ctx) do
    case {subject_path(palette, document), Map.fetch(ctx, :entry_type)} do
      {path, {:ok, entry_type}} when is_binary(path) -> %{path => {entry_type, :slot_entry}}
      _no_subject_or_no_entry_type -> %{}
    end
  end

  # The first block of the root's `body` slot (ADR-0011 decision 6).
  @spec entry_block(Document.t()) :: Block.t() | nil
  defp entry_block(%Document{root: %Block{slots: slots}}) do
    slots |> Map.get("body", []) |> List.first()
  end

  @spec subject_of(module()) :: String.t() | nil
  defp subject_of(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :palette_entry, 0) do
      case module.palette_entry() do
        %{subject: path} when is_binary(path) and path != "" -> path
        _no_subject -> nil
      end
    else
      nil
    end
  end

  # -- signatures ------------------------------------------------------------

  @spec field_reads(module(), Block.config()) :: [signature()]
  defp field_reads(module, config) do
    for decl <- schema(config, module),
        {:path, %{expects: expected}} <- [Map.get(decl, :type)],
        path = path_value(config, decl),
        path != nil do
      {decl.key, path, expected}
    end
  end

  @spec field_writes(module(), Block.config()) :: [signature()]
  defp field_writes(module, config) do
    for decl <- schema(config, module),
        BlockType.datamodel_path?(decl),
        writes?(decl),
        path = path_value(config, decl),
        path != nil do
      {decl.key, path, written_type(decl)}
    end
  end

  # Decision 2's two write forms, and the one declaration that is neither. A
  # field carrying `expects` and no `writes` is a **read**: it says what the
  # block needs at the path, not what it leaves there, and treating it as a
  # write would blank the very type it was declared to check - the record's
  # own worked shape has a settle step read the subject and expects the
  # subject to still be typed for the step after it.
  @spec writes?(BlockType.field_decl()) :: boolean()
  defp writes?(%{type: {:path, %{writes: _written}}}), do: true
  defp writes?(%{type: {:path, %{expects: _expected}}}), do: false
  defp writes?(_decl), do: true

  # A `{:path, %{writes: T}}` field writes `T`; every other declaration that
  # names a path says where without saying what, and writes `:unknown` - the
  # path becomes known without becoming typed, which is the honest reading of
  # the declaration.
  @spec written_type(BlockType.field_decl()) :: type_expr()
  defp written_type(%{type: {:path, %{writes: written}}}), do: written
  defp written_type(_decl), do: :unknown

  # Decision 2's third form. `core.on_event` stores its capture pairs as a
  # config map with no field declaration of its own (ADR-0002's Note of
  # 2026-09-05), so the pairs are read from the config: one write per pair, at
  # the pair's key, which is what puts those paths in front of ADR-0005 clause
  # 11e's declared-path advisory through the same mechanism as every other
  # datamodel path.
  @spec capture_writes(Block.config()) :: [signature()]
  defp capture_writes(config) do
    case Map.get(config, @capture_key) do
      pairs when is_map(pairs) ->
        for {path, _source} <- Enum.sort(pairs), is_binary(path), path != "" do
          {@capture_key, path, :unknown}
        end

      _absent_or_not_a_map ->
        []
    end
  end

  @spec sugar_read(Palette.t(), Document.t(), module(), Block.config()) :: [signature()]
  defp sugar_read(palette, document, module, config) do
    sugar(palette, document, module, config, :consumes)
  end

  @spec sugar_write(Palette.t(), Document.t(), module(), Block.config()) :: [signature()]
  defp sugar_write(palette, document, module, config) do
    sugar(palette, document, module, config, :produces)
  end

  # Decision 6: `consumes` is a read at the subject path and `produces` is a
  # write there. Inert with no subject path, and inert for a declaration that
  # says nothing - `:unknown`, or a `{:passthrough, slot}`, which the walk
  # already answers by carrying the slot's own writes out through the merge.
  @spec sugar(Palette.t(), Document.t(), module(), Block.config(), :consumes | :produces) ::
          [signature()]
  defp sugar(palette, document, module, config, key) do
    with path when is_binary(path) <- subject_path(palette, document),
         declared when is_binary(declared) and declared != "unknown" <-
           module |> io(config) |> Map.get(key, :unknown) do
      [{key, path, declared}]
    else
      _inert -> []
    end
  end

  @spec io(module(), Block.config()) :: map()
  defp io(module, config) do
    if Code.ensure_loaded?(module) and function_exported?(module, :io, 1) do
      module.io(config)
    else
      %{}
    end
  end

  @spec schema(Block.config(), module()) :: [BlockType.field_decl()]
  defp schema(config, module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :config_schema, 1) do
      module.config_schema(config)
    else
      []
    end
  end

  @spec path_value(Block.config(), BlockType.field_decl()) :: String.t() | nil
  defp path_value(config, decl) do
    case BlockType.fetch_value(config, BlockType.value_path(decl)) do
      {:ok, path} when is_binary(path) and path != "" -> path
      _absent_or_not_a_path -> nil
    end
  end

  # -- small shared helpers --------------------------------------------------

  @spec strip(annotated()) :: t()
  defp strip(env), do: Map.new(env, fn {path, {type, _writer}} -> {path, type} end)
end
