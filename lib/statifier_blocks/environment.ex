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
  `name` of a `record` or `shape` that document declares, an inline unnamed
  shape as `{:shape, members}`, an opaque string a host carries,
  `{:list, type}`, or `:unknown`. A named type arrives from a block's own
  declaration or from the datamodel document; an inline shape has no
  document syntax at all and arrives from a record's own decision, which
  the fan-out envelope is today the only instance of. `type_of/2` reads a
  declaration's spelling into
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

    * `{:path, %{writes: T}}` writes `T` at the path the field's value names,
      and - where `T` names a `record` or a `shape`, or is an inline shape -
      one further entry per member of `T` beneath that path, recursively
      (the Amendment of 2026-09-07, and "Member expansion" below);
    * a `{:path, opts}` field with no `writes` key, and a field carrying
      `datamodel_path?: true`, write `:unknown` there - the path becomes
      known without becoming typed;
    * a `capture` config map writes `:unknown` at each of its keys, one per
      pair;
    * `{:path, %{expects: T}}` reads `T` there.

  ## Member expansion

  A write of a record or a shape says what lives beneath the path as well as
  at it (the Amendment of 2026-09-07). A write signature at `P` whose written
  type names a `record` or `shape` declaration, or is an inline
  `{:shape, members}`, puts an entry at `P` **and** an entry at `P.m` for
  every member `m`, at the member's own type, joined with the same dot the
  projection uses. A member that is itself a record or a shape expands again,
  to any depth; a declaration already being expanded on the same chain of
  paths contributes its entry and expands no further, so a self-referencing
  declaration is finite. Nothing expands through a `{:list, T}` in either
  direction - there is no element path to put an entry at.

  A member entry is the weaker source. An explicit write signature at `P.m`
  in the same block wins over the member derived from `P`'s type, and a
  rewrite at `P` clears the members its own previous write derived - never a
  member entry an explicit signature wrote - and derives the new type's,
  which for a scalar is none. A read a member entry refuses anchors on the
  `key` of the field that declared the write at the **root**, because a
  member entry is derived and has no control of its own.

  The seed is untouched: a declared record already reaches the environment as
  member entries through `StatifierDatamodel.Index.entries/1`, and this is
  the same expansion said on the write side.

  `io/1`'s `consumes` and `produces` are sugar over the **subject path**,
  which the entry block's palette entry names with `subject:` (decision 6):
  `consumes` is a read there and `produces` is a write there. A document whose
  entry block declares no subject has no subject path, and the sugar is inert.
  A `produces` of `:unknown` writes nothing rather than blanking the subject -
  a container that says nothing about the subject leaves it alone, which is
  the whole gain decision 4's per-path merge exists for.
  """

  alias StatifierBlocks.{Block, BlockType, Composite, Document, Palette, Shelf}
  alias StatifierDatamodel.{Declarations, Index, Types}

  @typedoc """
  A type at a path. One of `t:StatifierDatamodel.Types.t/0`'s inhabitants as
  a document spells it - a scalar name, a declared name, an opaque string -
  or `:unknown`, or a list of one of those, or an inline unnamed shape.

  The inline arm is `sd-ADR-0001`'s, cited rather than respelled here: its
  members carry exactly `name`, `type` and `required?`, member order is
  authoring order, identity is member-set-wise, and a member's type is
  never absent. A member's `type` is a spelling in this module's own
  vocabulary, so the arm recurses and a member may hold an inline shape of
  its own; `type_of/2` is where the whole term is read into
  `t:StatifierDatamodel.Types.t/0`.
  """
  @type type_expr :: String.t() | :unknown | {:list, type_expr()} | {:shape, [member()]}

  @typedoc "One member of an inline shape, as a spelling carries it."
  @type member :: %{name: String.t(), type: type_expr(), required?: boolean()}

  @typedoc "Datamodel path to type. ADR-0011 decision 1's environment."
  @type t :: %{optional(String.t()) => type_expr()}

  @typedoc """
  The environment with the block that wrote each entry, which is what
  ADR-0011 decision 8's `upstream_ref` names. `:slot_entry` is the seed, or a
  merge whose arms agreed on a type without agreeing on who put it there,
  and `:declaration` is the datamodel document itself - the writer of an
  entry the seed took from the document's own declared path types.

  The two non-block writers differ in what an author would change. Neither
  earns a `{:fixable_by, block_id}` reason, because neither is a block; a
  `:declaration` says in as many words that the host's document typed the
  path, which is the difference between "your block writes the wrong type
  here" and "the host declares this path as something else".
  """
  @type annotated :: %{
          optional(String.t()) => {type_expr(), Block.id() | :slot_entry | :declaration}
        }

  @typedoc """
  Caller-supplied, not stored in the document. `:datamodel` is the datamodel
  document the declarations are read from; `:entry_type` seeds the subject
  path for a document whose entry block declares no `produces` of its own;
  `:skip_blocks` names blocks whose own declared writes the walk leaves out.

  `:skip_blocks` is how a caller that has already refused a block's config
  keeps that block's declarations out of the answer: a write signature is
  read off a config, so a config the compiler has already refused cannot be
  trusted to say what the block writes, and an entry derived from one would
  make the next block's read disagree with a type nobody declared. The
  block's *subtree* still contributes - a child's config is its own - and
  every other position walks exactly as it did. Absent, as it is for every
  editor query, nothing is skipped.
  """
  @type context :: %{
          optional(:entry_type) => type_expr(),
          optional(:datamodel) => term(),
          optional(:skip_blocks) => MapSet.t(Block.id())
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
  The environment the document opens with (ADR-0011 decision 2, amended
  2026-09-06).

  Two sources, and the second is applied over the first:

    * every path `ctx[:datamodel]` declares, at the type it declares there,
      written by the document rather than by any block;
    * `ctx[:entry_type]` at the subject path. It is ADR-0003 decision 4's
      context key, kept meaning what it meant - the type entering the
      document - now that the document has a path to hold it at.

  A document with no entry block, or one whose palette entry declares no
  `subject:`, seeds no subject however the context is filled: with no
  subject path there is nowhere for a subject type to be.

  A type the document's blocks write still wins, by position and with no
  new rule: a seeded entry is an entry like any other, so decision 1's
  last-write-wins settles the disagreement and a block writing a path
  replaces what the declaration seeded there for every position after it.

  **A read at a declared path is now checked.** Before this it was a read
  of a path the environment did not hold, which is decision 5's `:info`;
  where the host declared the path and the document disagrees with it, it
  is decision 5's `:error`. A caller that supplies no `:datamodel` seeds
  nothing new and is unaffected in every particular.

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

  A **composite** answers here with the union of its expansion's reads, taken
  at its one position in the document: see `expansion_signatures/5`.
  """
  @spec read_signatures(Palette.t(), Document.t(), Block.t()) :: [signature()]
  def read_signatures(%Palette{} = palette, %Document{} = document, %Block{} = block) do
    case Palette.resolve(palette, block) do
      {:ok, module, resolved} ->
        if Composite.composite?(module) do
          expansion_signatures(palette, document, resolved, module, &read_signatures/3)
        else
          field_reads(module, resolved.config) ++
            sugar_read(palette, document, module, resolved.config)
        end

      {:error, _reason} ->
        []
    end
  end

  @doc """
  Every write `block` declares, in `config_schema/1` order, then its capture
  pairs, then the `produces` sugar (ADR-0011 decision 2).

  A **composite** answers here with the union of its expansion's writes, taken
  at its one position in the document: see `expansion_signatures/5`.
  """
  @spec write_signatures(Palette.t(), Document.t(), Block.t()) :: [signature()]
  def write_signatures(%Palette{} = palette, %Document{} = document, %Block{} = block) do
    case Palette.resolve(palette, block) do
      {:ok, module, resolved} ->
        if Composite.composite?(module) do
          expansion_signatures(palette, document, resolved, module, &write_signatures/3)
        else
          field_writes(module, resolved.config) ++
            capture_writes(resolved.config) ++
            sugar_write(palette, document, module, resolved.config)
        end

      {:error, _reason} ->
        []
    end
  end

  # RQ-SF037-15, ruled 2026-09-07 (shape A): a composite's read and write
  # signatures are computed at its ONE position, by running these same two
  # functions over `Composite.expand/2`'s subtree with the expanded config.
  #
  # No descent, and no second walk: `descend/6` steps into a slot, a composite
  # in this campaign exposes none (RQ-SF037-3), and the expansion is not in the
  # document (ADR-0011's Note of 2026-09-07, section 1). What is walked here is
  # the expansion the compiler will produce at Resolve, at the position the
  # composite occupies - so the block after it reads what the members left,
  # exactly as it would had the author placed those members by hand.
  #
  # The order is the expansion's own pre-order, which is what makes decision
  # 1's last-write-wins by position hold inside the union: two members writing
  # one path leave the later member's type. `config_schema/1` stays the params
  # and no `type_expr/0` arm is added; the union is obtained here rather than
  # declared anywhere.
  @spec expansion_signatures(
          Palette.t(),
          Document.t(),
          Block.t(),
          module(),
          (Palette.t(), Document.t(), Block.t() -> [signature()])
        ) :: [signature()]
  defp expansion_signatures(palette, document, block, module, signatures) do
    {members, _param_map} = Composite.expand(block, module)

    members
    |> Composite.flatten()
    |> Enum.flat_map(&signatures.(palette, document, &1))
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
  the grammar already covers. Three readings are this package's own: the
  atom `:unknown` and the string `"unknown"` are both `:unknown`, a
  `{:list, _}` is the document's own `list` - ADR-0011 decision 14 puts no
  cardinality on a read, so a list is checked as a list and its item type is
  carried for a fan-out to bind, not for the check to descend into - and an
  inline shape is **built** here rather than parsed there. That package
  reads a binary spelling and has no syntax for a shape, so a member's own
  type is read by this function recursively and the members are handed over
  as the term `StatifierDatamodel.Types.satisfies/3` takes.

      iex> alias StatifierBlocks.Environment
      iex> Environment.type_of(%{}, {:shape, [
      ...>   %{name: "index", type: "integer", required?: true}]})
      {:shape, [%{name: "index", type: :integer, required?: true}]}
  """
  @spec type_of(Declarations.t(), term()) :: Types.t()
  def type_of(_declarations, :unknown), do: :unknown
  def type_of(_declarations, "unknown"), do: :unknown
  def type_of(_declarations, {:list, _item}), do: :list

  def type_of(declarations, {:shape, members}) when is_list(members) do
    {:shape, Enum.map(members, &member_of(declarations, &1))}
  end

  def type_of(declarations, spelling), do: Types.parse(declarations, spelling)

  # A member's own type is a spelling, so the arm recurses. `required?` is
  # normalized to a boolean here rather than trusted: a stored document
  # carries whatever JSON it carries, and the member spelling admits only
  # the two values.
  @spec member_of(Declarations.t(), term()) :: Types.member()
  defp member_of(declarations, %{name: name, type: type} = member) do
    %{
      name: name,
      type: type_of(declarations, type),
      required?: Map.get(member, :required?) == true
    }
  end

  defp member_of(_declarations, other),
    do: %{name: inspect(other), type: :unknown, required?: false}

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

  def type_label(declarations, {:shape, members}) when is_list(members) do
    "{" <> Enum.map_join(members, ", ", &member_label(declarations, &1)) <> "}"
  end

  def type_label(declarations, spelling) when is_binary(spelling) do
    case Declarations.fetch(declarations, spelling) do
      {:ok, %{label: label}} when is_binary(label) and label != "" -> label
      _undeclared_or_unlabelled -> spelling
    end
  end

  def type_label(_declarations, other), do: inspect(other)

  # An unnamed shape has no name to render, so it renders its members, in
  # authoring order, each `name: type`, with a `?` after the name of a
  # member the shape does not promise - the spelling
  # `StatifierDatamodel.Types.to_string/1` prints for the same term.
  @spec member_label(Declarations.t(), term()) :: String.t()
  defp member_label(declarations, %{name: name, type: type} = member) do
    promised = if Map.get(member, :required?) == true, do: "", else: "?"
    name <> promised <> ": " <> type_label(declarations, type)
  end

  defp member_label(_declarations, other), do: inspect(other)

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

  @doc """
  Reads a stored member list into an inline shape (ADR-0002 decision 7,
  amended 2026-09-06).

  A `{:type_expr, opts}` field stores its inline arm as JSON: a list of
  objects each carrying `"name"`, `"type"` and the optional boolean
  `"required?"`. This is where those bytes become the arm decision 1
  admits, and it is the only direction that exists - an inline shape has no
  document syntax, so nothing parses one out of a binary and
  `StatifierDatamodel.Types.parse/2` never returns one.

  Member well-formedness is `sd-ADR-0001`'s and is applied rather than
  restated: a member whose name is not a non-empty string contributes
  nothing, a repeated member name keeps its first occurrence, and a
  member's type is never absent - a spelling that resolves to nothing is
  the datamodel's unknown. Member order is the order the author wrote,
  because that is the order an unmet-member reason renders in.

  Total: anything that is not a list is `:unknown`.

      iex> alias StatifierBlocks.Environment
      iex> Environment.inline_shape([
      ...>   %{"name" => "index", "type" => "integer", "required?" => true},
      ...>   %{"name" => "note", "type" => "string"}])
      {:shape, [
        %{name: "index", type: "integer", required?: true},
        %{name: "note", type: "string", required?: false}
      ]}

      iex> StatifierBlocks.Environment.inline_shape("cards.settlement")
      :unknown
  """
  @spec inline_shape(term()) :: type_expr()
  def inline_shape(members) when is_list(members) do
    {:shape,
     members
     |> Enum.flat_map(&stored_member/1)
     |> Enum.uniq_by(& &1.name)}
  end

  def inline_shape(_not_a_member_list), do: :unknown

  @spec stored_member(term()) :: [member()]
  defp stored_member(%{"name" => name} = member) when is_binary(name) and name != "" do
    [
      %{
        name: name,
        type: stored_member_type(Map.get(member, "type")),
        required?: Map.get(member, "required?") == true
      }
    ]
  end

  defp stored_member(_nameless), do: []

  @spec stored_member_type(term()) :: type_expr()
  defp stored_member_type(spelling) when is_binary(spelling) and spelling != "", do: spelling
  defp stored_member_type(members) when is_list(members), do: inline_shape(members)
  defp stored_member_type(_absent_or_malformed), do: :unknown

  # -- the walk --------------------------------------------------------------

  # One block's contribution: its slots merged, then its own writes. The
  # shelf is not entered and declares nothing, so it passes the environment
  # through untouched.
  @spec through(Palette.t(), Document.t(), Block.t(), annotated(), context()) :: annotated()
  defp through(palette, document, %Block{} = block, env, ctx) do
    cond do
      Shelf.shelf?(block) ->
        env

      skipped?(block, ctx) ->
        arms(env, palette, document, block, ctx)

      true ->
        env
        |> arms(palette, document, block, ctx)
        |> apply_writes(palette, document, block, ctx)
    end
  end

  # `:skip_blocks` membership. A context without the key skips nothing, which
  # is every caller that has not already refused a config.
  @spec skipped?(Block.t(), context()) :: boolean()
  defp skipped?(%Block{id: id}, ctx) do
    case Map.fetch(ctx, :skip_blocks) do
      {:ok, skip} -> MapSet.member?(skip, id)
      :error -> false
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

  # Decision 1's last-write-wins, and the Amendment of 2026-09-07's member
  # expansion applied with it: each signature puts its own entry, and a
  # record-typed or shape-typed one also puts an entry per member beneath it.
  #
  # Three things happen per signature, in this order. The members the
  # *previous* write at the path derived are cleared, because a stale member
  # entry beneath a path that no longer holds a record would be a claim
  # nobody is making. The signature's own entry is put. Then the members its
  # type derives are put, skipping every path this block writes explicitly -
  # the explicit signature wins over the derived member, whichever order the
  # two are declared in.
  @spec apply_writes(annotated(), Palette.t(), Document.t(), Block.t(), context()) :: annotated()
  defp apply_writes(env, palette, document, %Block{} = block, ctx) do
    declarations = declarations(ctx)
    signatures = write_signatures(palette, document, block)
    declared = MapSet.new(signatures, fn {_key, path, _type} -> path end)

    Enum.reduce(signatures, env, fn {_key, path, type}, acc ->
      acc
      |> clear_derived(declarations, path)
      |> Map.put(path, {type, block.id})
      |> put_derived(declarations, path, type, block.id, declared)
    end)
  end

  # What the write already at `path` derived, and only that. An entry a later
  # explicit signature at `path.m` replaced is no longer what the previous
  # write put there - decision 1's per-path last-write-wins already took it -
  # so the equality test leaves it alone, and the environment needs no second
  # annotation to say which entries were derived.
  @spec clear_derived(annotated(), Declarations.t(), String.t()) :: annotated()
  defp clear_derived(env, declarations, path) do
    case Map.fetch(env, path) do
      {:ok, {previous_type, writer}} ->
        declarations
        |> derived_writes(path, previous_type)
        |> Enum.reduce(env, &drop_derived(&2, &1, writer))

      :error ->
        env
    end
  end

  @spec drop_derived(
          annotated(),
          {String.t(), type_expr()},
          Block.id() | :slot_entry | :declaration
        ) :: annotated()
  defp drop_derived(env, {member_path, member_type}, writer) do
    if Map.get(env, member_path) == {member_type, writer},
      do: Map.delete(env, member_path),
      else: env
  end

  @spec put_derived(
          annotated(),
          Declarations.t(),
          String.t(),
          type_expr(),
          Block.id(),
          MapSet.t(String.t())
        ) :: annotated()
  defp put_derived(env, declarations, path, type, block_id, declared) do
    declarations
    |> derived_writes(path, type)
    |> Enum.reduce(env, fn {member_path, member_type}, acc ->
      if MapSet.member?(declared, member_path),
        do: acc,
        else: Map.put(acc, member_path, {member_type, block_id})
    end)
  end

  # Every `path.m` a write of `type` at `path` yields, depth first in member
  # order. A named declaration already being expanded on the chain of paths
  # beneath `path` is not expanded again - the same `seen` discipline
  # `sd-ADR-0001` decision 8 runs the read check under, and the one that
  # amendment's index expansion applies - so a self-referencing declaration
  # contributes its entry and terminates.
  @spec derived_writes(Declarations.t(), String.t(), type_expr()) ::
          [{String.t(), type_expr()}]
  defp derived_writes(declarations, path, type),
    do: derived_writes(declarations, path, type, MapSet.new())

  @spec derived_writes(Declarations.t(), String.t(), type_expr(), MapSet.t(String.t())) ::
          [{String.t(), type_expr()}]
  defp derived_writes(declarations, path, type, seen) do
    case expansion(declarations, type, seen) do
      :none ->
        []

      {members, deeper} ->
        Enum.flat_map(members, fn {name, member_type} ->
          member_path = path <> "." <> name

          [
            {member_path, member_type}
            | derived_writes(declarations, member_path, member_type, deeper)
          ]
        end)
    end
  end

  # The members a type expression expands into, and the chain its members are
  # expanded under. An inline shape puts no name on the chain: it is a finite
  # term and cannot reference itself. A `{:list, _}` expands into nothing in
  # either direction, and so do a scalar, an opaque string that names no
  # declaration, and `:unknown`.
  @spec expansion(Declarations.t(), type_expr(), MapSet.t(String.t())) ::
          {[{String.t(), type_expr()}], MapSet.t(String.t())} | :none
  defp expansion(_declarations, {:shape, members}, seen) when is_list(members) do
    {for(%{name: name, type: type} <- members, is_binary(name), do: {name, type}), seen}
  end

  defp expansion(_declarations, {:list, _item}, _seen), do: :none

  defp expansion(declarations, name, seen) when is_binary(name) do
    with false <- MapSet.member?(seen, name),
         {:ok, %{fields: fields}} <- Declarations.fetch(declarations, name) do
      {Enum.map(fields, &{&1.name, member_spelling(&1)}), MapSet.put(seen, name)}
    else
      _re_entered_or_undeclared -> :none
    end
  end

  defp expansion(_declarations, _no_members, _seen), do: :none

  # A declared field's type, as this module spells one. `declared_spelling/1`
  # reads the `type`/`item_type` pair a field carries in exactly the shape an
  # index entry carries it; a field whose spelling names neither the closed
  # set nor a declaration is `:unknown`, because the amendment puts an entry
  # at every member and an unnameable one is the datamodel's unknown.
  @spec member_spelling(Declarations.field()) :: type_expr()
  defp member_spelling(field), do: declared_spelling(field) || :unknown

  # -- the seed --------------------------------------------------------------

  @spec seed_annotated(Palette.t(), Document.t(), context()) :: annotated()
  defp seed_annotated(palette, document, ctx) do
    Map.merge(declared_seed(ctx), subject_seed(palette, document, ctx))
  end

  @spec subject_seed(Palette.t(), Document.t(), context()) :: annotated()
  defp subject_seed(palette, document, ctx) do
    case {subject_path(palette, document), Map.fetch(ctx, :entry_type)} do
      {path, {:ok, entry_type}} when is_binary(path) -> %{path => {entry_type, :slot_entry}}
      _no_subject_or_no_entry_type -> %{}
    end
  end

  # The document's own declared path types, marked as the declaration's.
  # This reads `Index.entries/1` and takes each entry's declared type: a
  # declaration name stays its name and a scalar stays its own spelling.
  # The Datamodel tab and the editor's typed cells draw a different
  # projection of the same index - `StatifierDatamodel.Index.path_types/1`,
  # wrapped by `StatifierBlocks.Datamodel.path_types/1` - which answers
  # value kinds for a renderer and so contributes no path for an `object`,
  # a declaration-typed or an untyped entry. Those are the entries the check
  # has the most to say about, which is why the two sets differ on purpose
  # (ADR-0011's Note of 2026-09-07).
  #
  # An entry the index cannot name a type for contributes nothing rather
  # than `:unknown`: an entry at `:unknown` and no entry at all are read
  # identically by the check, and the absent one keeps the walk's answer the
  # size of what the document actually said.
  @spec declared_seed(context()) :: annotated()
  defp declared_seed(ctx) do
    case ctx |> Map.get(:datamodel) |> Index.index() do
      nil -> %{}
      index -> index |> Index.entries() |> Enum.flat_map(&seeded_entry/1) |> Map.new()
    end
  end

  @spec seeded_entry(map()) :: [{String.t(), {type_expr(), :declaration}}]
  defp seeded_entry(entry) do
    case declared_spelling(entry) do
      nil -> []
      spelling -> [{entry.path, {spelling, :declaration}}]
    end
  end

  # An index entry's type, as this module spells one. A list carries its
  # item type where the entry declared one, which is decision 14's reading
  # of a list: the cardinality is not the check's, and the item type is
  # carried for a fan-out to bind.
  @spec declared_spelling(map()) :: type_expr() | nil
  defp declared_spelling(%{type: nil}), do: nil

  defp declared_spelling(%{type: :list} = entry) do
    {:list, entry_spelling(Map.get(entry, :item_type))}
  end

  defp declared_spelling(%{type: type}), do: entry_spelling(type)

  @spec entry_spelling(term()) :: type_expr()
  defp entry_spelling(nil), do: :unknown
  defp entry_spelling({:declared, name}) when is_binary(name), do: name
  defp entry_spelling(scalar) when is_atom(scalar), do: Atom.to_string(scalar)
  defp entry_spelling(_unnameable), do: :unknown

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
