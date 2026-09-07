defmodule StatifierBlocks.Composite do
  @moduledoc """
  A block type derived from **params** plus a **pure subtree** (ADR-0002
  decision 5's amendment of 2026-09-07).

  `use StatifierBlocks.Composite` is a second `use` macro on the declaration
  surface `StatifierBlocks.BlockType` owns. Where `use StatifierBlocks.BlockType`
  injects a *fixed* answer per callback (ADR-0007), this one injects answers
  **derived from a declaration**: the params an author fills in, and the
  `subtree/1` those params stand for.

  ## The declaration

      defmodule MyApp.GuardedStep do
        use StatifierBlocks.Composite,
          name: "myapp.guarded_step",
          params: [
            %{key: "invoke_type", type: :string, label: "Call",
              required?: true, default: ""},
            %{key: "failure_path", type: :string, label: "Record the failure at",
              required?: true, default: "", datamodel_path?: true}
          ],
          sentence: "Call {invoke_type}, recording failure at {failure_path}",
          palette_entry: %{label: "Guarded step", group: "Structure"},
          version: 1

        @impl true
        def subtree(params) do
          [
            Block.new("core.invoke",
              id: "call",
              config: %{"invoke_type" => params["invoke_type"], "assign_to" => ""},
              slots: %{"on_error" => [
                Block.new("core.assign",
                  id: "guard",
                  config: %{"path" => params["failure_path"], "value" => "failed"})
              ]}
            )
          ]
        end
      end

  `params` is a `[t:StatifierBlocks.BlockType.field_decl/0]` in decision 7's
  shape - no new key, no new field type. Every flag decision 7 and its
  amendments give a field means here exactly what it means on any other
  declared field, and the F3 and F4 refusals apply to a param declaration
  unchanged: because the composite's `config_schema/1` **is** the params, the
  compiler's own declaration checks run over them for free.

  `subtree/1` is **pure** in decision 4's sense - same params in, same subtree
  out, forever - and answers a **non-empty** list of `t:StatifierBlocks.Block.t/0`
  whose **head is the expansion root**. Several derivations below read that
  block and no other.

  ## The ids the subtree mints

  The ids a `subtree/1` writes are **local**: `expand/2` mints each expanded
  block's real id from the composite block's own id, as
  `composite_id <> "_" <> local_id`. They are not fresh UXIDs and not a
  counter over the document, and two properties follow:

    * **No `__`.** `ADR-0004` decision 3 derives a state id as `"s_" <> block_id`
      or `"s_" <> block_id <> "__" <> role`, and its invertibility rests on a
      block id containing no `__`. `expand/2` refuses a local id that would
      put one there.
    * **Document-unique, for free.** The composite block's id is
      document-unique, opaque and never reused (`ADR-0001` decision 3), and
      minting is injective over it, so the members inherit all three.

  A local id that looks like a freshly minted UXID (`"blk_"`-prefixed) is
  refused: `StatifierBlocks.Block.new/2` mints one when a declaration writes
  no `:id`, and a minted id is different on every call, which would make
  `subtree/1` impure and the expansion unstable.

  ## What the `use` derives

  | Callback | The composite's answer | Overridable |
  |---|---|---|
  | `config_schema/1` | `params`, in declaration order | no |
  | `validate_config/1` | **not derived**: `ADR-0007`'s injected `:ok` stands, and the refusals `params` declare are run by the compile over `config_schema/1` (see below) | **yes** |
  | `slots/1` | the declared pass-through slots, in declaration order (`RQ-SF038-5`) | no |
  | `io/1` | see below | no |
  | `current_version/0` | the version the declaration states | no |
  | `outcomes/1` | the expansion root's, over its expanded config | no |
  | `sentence/1` | the declaration's template rendered over the config | **yes** |
  | `summary/1` | one chip per visible param (`RQ-SF038-14`) | **yes** |
  | `palette_entry/0` | the map the declaration states | **yes** |
  | `emit/2` | generated, and raises if reached (`RQ-SF037-6`) | no |

  `sentence/1`, `summary/1`, `palette_entry/0` and `validate_config/1` and
  **no others** are overridable: they are the four whose answers are about
  presentation and refusal rather than about the expansion. `migrate_config/2`
  keeps ADR-0007's injected refusal unchanged, and `fixtures/0`,
  `failure_outcomes/1` and `donedata_type/1` are not derived - they stay
  optional and absent unless a declaration writes them by hand.

  ### The derived `summary/1`

  `ADR-0002`'s Note of 2026-09-07, item 4: the chips are the declaration's
  `params`, minus those declared `hidden?: true`. `hidden?` is a rendering
  claim (`block_type.ex`, "the field is **never rendered by any form**"), so a
  param the author has already said no form draws is not a chip either - the
  same reading `StatifierBlocks.ViewModel` takes of the flag. Each surviving
  param draws as `"<label>: <value>"`, and a param whose value renders blank
  draws no chip at all rather than a label with nothing after it.

  The value is read with `Map.get/2` on the param's `:key`, which is the
  reading `render_sentence/2` beside it already takes of the same declaration:
  a composite's params are its own config's keys, and the two derivations that
  read them cannot be allowed to disagree about which key a param is at.

  It is **overridable** for `sentence/1`'s reason - a declaration whose card
  wants to say something the params cannot spell says it itself.

  `validate_config/1` is left at ADR-0007's injected `:ok`, deliberately -
  the macro never redefines it, and the row above states what the compile
  guarantees rather than a generated function (`ADR-0002`'s Note of
  2026-09-07, correction 2). The refusals a param declares are
  declaration-level - F3's missing `default:`,
  F4's empty hidden default, and `{:type_expr, opts}`' `allow_empty?` - and
  the compile already runs every one of them over `config_schema/1`, which for
  a composite is the params. `required?` is a rendering hint and never an
  authority (`block_type.ex`, "This is a rendering hint, not the authority"),
  so it raises no finding here either: that is what makes the amendment's own
  worked example - two `required?: true` params defaulting to `""` - land
  finding-free out of `StatifierBlocks.Palette.new_block/2`. A composite with
  a cross-param refusal its params cannot state as a single field's flag
  overrides the callback, which is why it is one of the three that may be.

  `emit/2` exists because the behaviour requires it and ADR-0007 deliberately
  injects no default for it. It **raises**, because the compiler expands a
  composite at Resolve and no composite block survives to Emit (`sb-nzc1`).

  ## What a composite reads and writes

  A composite's reads and writes, as the environment walk consumes them, are
  the **union of its expanded members'**, each taken over that member's
  expanded config, at the composite's **one** position in the document
  (`RQ-SF037-15`, ruled 2026-09-07: shape (A)). That union is computed by
  `StatifierBlocks.Environment.read_signatures/3` and `write_signatures/3` -
  the same two functions, run over `expand/2`'s subtree - and not by `io/1`,
  which is single-valued in `consumes` and `produces` and carries no per-path
  read or write at all.

  The derived `io/1` therefore answers, per key of
  `t:StatifierBlocks.Assignability.io/0`:

    * `kinds` - the members' `kinds` concatenated in expansion order, de-duplicated
    * `slot_accepts` - one entry per **declared pass-through slot**, at the
      mapped inner slot's own accepted kinds; `%{}` for a composite that
      declares none, which is every composite written before `RQ-SF038-5`
    * `consumes` - the expansion root's, or absent when the root declares none
    * `produces` - the expansion root's, or absent when the root declares none

  Dropping a non-root member's sugar under-declares rather than over-declares,
  which is the safe direction `ADR-0011` decision 6 already takes.

  ### The callbacks are core-only, and a reader with a palette is not

  Both rows read a **member's module**, and a `t:StatifierBlocks.Block.t/0`
  carries a type *name*. Resolving a name to a module is
  `StatifierBlocks.Palette`'s job, and neither `c:StatifierBlocks.BlockType.io/1`
  nor `c:StatifierBlocks.BlockType.outcomes/1` is handed a palette - so the two
  **callbacks** resolve members through `StatifierBlocks.Palette.core/0`,
  whose types are `StatifierBlocks.Palette.core_types/0`, the one type map this
  package holds as a value. A composite whose expansion root is a **host** type
  therefore falls back *in the callback*: `outcomes/1` to the behaviour's
  default outcomes, and `io/1` to `[:step]` kinds with no sugar.

  That fallback is the callbacks' answer and stays their answer (`ADR-0002`'s
  Note of 2026-09-07, item 3: no `@callback` is added, removed or re-arity'd,
  and neither derivation gains a palette argument). What a **reader holding a
  palette** does instead is call `io/2` and `outcomes/2` below, which take the
  palette as their first argument and resolve every member through it - so the
  same composite is exact wherever a palette is in hand and takes the
  documented fallback only where none is.

  The environment walk needs neither: it recurses into
  `StatifierBlocks.Environment.read_signatures/3` and `write_signatures/3` over
  the expansion, so no composite reaches its `io/1` there at all.

  ## The derived recipe

  The declaration also derives a `StatifierBlocks.Recipe` at `<Module>.Recipe`,
  whose `insert/2` returns exactly **one `:insert` of the composite block** at
  the armed target and whose `palette_entry/0` is the block type's. One
  command, not the expansion: what an author puts down is the composite, and
  the expansion happens at compile.

  It is a compatibility surface for a host that already ships the arrangement
  as a recipe. **A composite's own palette entry is its `types` entry**;
  `StatifierBlocks.Palette` keeps types and recipes in two maps, so a host that
  registers both is choosing to show two entries.
  """

  alias StatifierBlocks.{Assignability, Block, BlockType, Edit, Palette}

  @typedoc """
  Each expanded block's id to the **param key** that produced it, or to `nil`
  for a block no *single* param is responsible for.

  `ADR-0004`'s amendment (`sb-nzc1`) re-anchors a finding raised inside an
  expansion against the composite block, carrying the key this map names -
  and `config_key: nil` when it names none, which is the honest answer both
  when no param fed the block and when two did.
  """
  @type param_map :: %{optional(Block.id()) => String.t() | nil}

  @typedoc """
  One declared **pass-through slot**: a slot the composite exposes, and the
  `{local_id, inner_slot}` of the expansion member its children are spliced
  into (`ADR-0002`'s pass-through amendment, P1).

  `:label` and `:arity` are forced rather than added: a
  `t:StatifierBlocks.BlockType.slot_decl/0` is the 3-tuple
  `{name, arity, label}` and two of the three have nowhere else to come from.
  """
  @type pass_through_decl :: %{
          name: Block.slot_name(),
          to: {String.t(), Block.slot_name()},
          label: String.t(),
          arity: BlockType.slot_arity()
        }

  @typedoc "The normalized declaration, as `__composite__/0` answers it."
  @type declaration :: %{
          name: Block.type_name(),
          params: [BlockType.field_decl()],
          version: pos_integer(),
          sentence: String.t() | nil,
          palette_entry: BlockType.palette_entry(),
          slots: [pass_through_decl()]
        }

  @separator "_"

  @doc """
  The blocks this composite stands for, given its params.

  Pure in ADR-0002 decision 4's sense: same params in, same subtree out,
  forever, no I/O, no clock, no process dictionary. The list is **non-empty**
  and its **head is the expansion root**. The ids are **local** - `expand/2`
  mints the document's ids from the composite block's own id.
  """
  @callback subtree(Block.config()) :: [Block.t()]

  @doc """
  Declares a composite block type from `opts`.

  Options:

    * `:name` (**required**) - the composite's block type name, as a document
      stores it and a palette keys it. A block type does not otherwise know
      its own type name, and the derived recipe needs one to insert.
    * `:params` (**required**) - `[t:StatifierBlocks.BlockType.field_decl/0]`.
      Each declares `:key`, `:type`, `:label`, `:required?` and `:default`.
    * `:sentence` - a template whose `{param_key}` placeholders are replaced
      by the config's values. Absent means the palette label.
    * `:palette_entry` - `t:StatifierBlocks.BlockType.palette_entry/0`.
      Defaults to `%{label: name}`; a map without a `:label` gets `name`.
    * `:version` - the stored `type_version` this declaration is current at.
      Defaults to `1`.
    * `:slots` - the **pass-through slots** this composite exposes, a list of
      `t:pass_through_decl/0` maps carrying `:name` and `:to`, with optional
      `:label` (defaulting to `:name`) and `:arity` (defaulting to `:any`).
      Defaults to `[]`, which is every composite written before `RQ-SF038-5`.

  The using module must define `subtree/1`.
  """
  defmacro __using__(opts) do
    quote do
      use StatifierBlocks.BlockType

      @behaviour StatifierBlocks.Composite

      @composite_declaration StatifierBlocks.Composite.__declaration__(unquote(opts))

      @doc false
      @spec __composite__() :: StatifierBlocks.Composite.declaration()
      def __composite__, do: @composite_declaration

      @impl StatifierBlocks.BlockType
      def config_schema(_config), do: @composite_declaration.params

      @impl StatifierBlocks.BlockType
      def slots(_config), do: StatifierBlocks.Composite.derived_slots(@composite_declaration)

      @impl StatifierBlocks.BlockType
      def current_version, do: @composite_declaration.version

      @impl StatifierBlocks.BlockType
      def io(config), do: StatifierBlocks.Composite.derived_io(__MODULE__, config)

      @impl StatifierBlocks.BlockType
      def outcomes(config), do: StatifierBlocks.Composite.derived_outcomes(__MODULE__, config)

      @impl StatifierBlocks.BlockType
      def sentence(config),
        do: StatifierBlocks.Composite.render_sentence(@composite_declaration, config)

      @impl StatifierBlocks.BlockType
      def summary(config),
        do: StatifierBlocks.Composite.derived_summary(@composite_declaration, config)

      @impl StatifierBlocks.BlockType
      def palette_entry, do: @composite_declaration.palette_entry

      @impl StatifierBlocks.BlockType
      def emit(%StatifierBlocks.Block{id: id, type: type}, _context) do
        raise RuntimeError,
              "#{inspect(__MODULE__)}.emit/2 was reached for block #{inspect(id)} of type " <>
                "#{inspect(type)}. A composite is replaced by its expansion at Resolve " <>
                "(ADR-0004, sb-nzc1), so no composite block survives to Emit; reaching this " <>
                "means the expansion did not run."
      end

      defoverridable sentence: 1, summary: 1, palette_entry: 0

      @before_compile StatifierBlocks.Composite
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    unless Module.defines?(env.module, {:subtree, 1}) do
      raise CompileError,
        file: env.file,
        line: env.line,
        description:
          "#{inspect(env.module)} uses StatifierBlocks.Composite but defines no subtree/1. " <>
            "A composite is params plus a pure subtree; there is nothing to expand without it."
    end

    owner = env.module

    Module.create(
      Module.concat(owner, Recipe),
      quote do
        @moduledoc """
        The recipe derived from `#{inspect(unquote(owner))}`'s declaration.

        `insert/2` puts down one composite block, not its expansion.
        """

        @behaviour StatifierBlocks.Recipe

        @impl StatifierBlocks.Recipe
        def insert(target, document),
          do: StatifierBlocks.Composite.recipe_insert(unquote(owner), target, document)

        @impl StatifierBlocks.Recipe
        def palette_entry, do: unquote(owner).palette_entry()
      end,
      Macro.Env.location(env)
    )

    nil
  end

  @doc false
  @spec __declaration__(keyword()) :: declaration()
  def __declaration__(opts) when is_list(opts) do
    name = required_option(opts, :name)
    params = required_option(opts, :params)

    unless is_binary(name) and name != "" do
      raise ArgumentError, "use StatifierBlocks.Composite: :name must be a non-empty string"
    end

    unless is_list(params) and Enum.all?(params, &param?/1) do
      raise ArgumentError,
            "use StatifierBlocks.Composite: :params must be a list of field declarations, " <>
              "each carrying :key, :type, :label, :required? and :default"
    end

    version = Keyword.get(opts, :version, 1)

    unless is_integer(version) and version > 0 do
      raise ArgumentError, "use StatifierBlocks.Composite: :version must be a positive integer"
    end

    sentence = Keyword.get(opts, :sentence)

    unless is_nil(sentence) or is_binary(sentence) do
      raise ArgumentError, "use StatifierBlocks.Composite: :sentence must be a string"
    end

    entry = opts |> Keyword.get(:palette_entry, %{}) |> Map.put_new(:label, name)

    slots = opts |> Keyword.get(:slots, []) |> normalize_slots!()

    %{
      name: name,
      params: params,
      version: version,
      sentence: sentence,
      palette_entry: entry,
      slots: slots
    }
  end

  @doc """
  Whether `module` is a composite block type.

  The three callers of `expand/2` - the compiler at Resolve, the editor's
  Expand operation and this module's own derivations - each have to ask
  before they expand, so the question is answered once and here.
  """
  @spec composite?(Palette.type_ref()) :: boolean()
  def composite?({module, _state}) when is_atom(module) do
    Palette.declares?({module, nil}, :__composite__, 0)
  end

  def composite?(module) when is_atom(module) do
    Palette.declares?(module, :__composite__, 0)
  end

  def composite?(_ref), do: false

  @doc """
  The blocks `block` stands for, and the param each one is blamed on.

  `block` is the composite block as the document stores it; `ref` is its
  own palette entry - a module, or a `{module, state}` pair - which every
  caller has already resolved through `StatifierBlocks.Palette.fetch/2`.
  Every read of the declaration below goes through
  `StatifierBlocks.Palette.call/4`, so a data composite expands through
  this same function and nothing here knows which kind it got. The return is the expanded blocks in
  document order - **head first, and the head is the expansion root** -
  together with the `t:param_map/0` over every block in the expansion,
  nested members included.

  This is the **one** expansion function. The compiler reads it at Resolve,
  the editor's Expand operation reads it to replace a composite block with
  its expansion in the document, and nothing else answers "what does this
  composite stand for" - three implementations would be three chances for the
  compiled chart and the expanded document to disagree.

  Raises when the declaration is broken: a `subtree/1` that answers an empty
  list, a non-block, a duplicated local id, or a local id that would mint an
  id carrying `__`.
  """
  @spec expand(Block.t(), Palette.type_ref()) :: {[Block.t()], param_map()}
  def expand(%Block{} = block, ref) do
    unless composite?(ref) do
      raise ArgumentError,
            "#{inspect(ref)} is not a composite block type: it does not " <>
              "use StatifierBlocks.Composite, so there is nothing to expand."
    end

    params = params_of(ref, block.config)

    subtree = Palette.call(ref, :subtree, [params], nil)

    unless is_list(subtree) and subtree != [] and Enum.all?(subtree, &match?(%Block{}, &1)) do
      raise ArgumentError,
            "#{inspect(ref)}.subtree/1 must answer a non-empty list of " <>
              "StatifierBlocks.Block structs, got: #{inspect(subtree)}"
    end

    check_local_ids!(subtree, ref)
    check_mapping!(subtree, declared_slots(ref), ref)

    members = Enum.map(subtree, &mint(&1, block.id, ref))

    # `ADR-0004`'s T3: the expansion index maps expansion MEMBERS only, so
    # the param map - which is what the compiler builds that index from - is
    # taken over the minted members BEFORE the author's children are spliced
    # in. A pass-through child has no entry in it and is therefore never
    # re-anchored onto the composite.
    param_map = param_map(members, params)

    {splice(members, block, declared_slots(ref)), param_map}
  end

  @doc """
  The pass-through slots `block`'s type declares, each resolved to the
  **minted** id of the member its children are spliced into.

  `%{}` for a composite that declares none, which is every composite written
  before `ADR-0002`'s pass-through amendment. `ref` is the block's own
  palette entry, already resolved, exactly as `expand/2` takes it.

  It exists because the environment walk has to find the mapped inner
  position (`ADR-0011`'s amendment of 2026-09-07, section 2) and minting is
  this module's rule: a caller deriving the id itself would be a second
  implementation of `mint_id/3`.
  """
  @spec pass_through(Block.t(), Palette.type_ref()) ::
          %{optional(Block.slot_name()) => {Block.id(), Block.slot_name()}}
  def pass_through(%Block{} = block, ref) do
    ref
    |> declared_slots()
    |> Map.new(fn %{name: name, to: {local_id, inner_slot}} ->
      {name, {mint_id(block.id, local_id, ref), inner_slot}}
    end)
  end

  @doc false
  @spec derived_slots(declaration()) :: [BlockType.slot_decl()]
  def derived_slots(%{slots: slots}),
    do: Enum.map(slots, fn %{name: name, arity: arity, label: label} -> {name, arity, label} end)

  def derived_slots(_no_slots_key), do: []

  @doc """
  `subtree`'s three pass-through refusals, as a list of messages, or `[]`.

  `expand/2` raises them for a module composite, whose subtree exists only
  once it has params; `StatifierBlocks.Composite.Data.declaration/1` answers
  them as declaration errors, its subtree being a static template. One
  implementation, so the two kinds cannot disagree about what a broken
  mapping is (`ADR-0002`'s pass-through amendment, P5).
  """
  @spec mapping_errors([Block.t()], [pass_through_decl()]) :: [String.t()]
  def mapping_errors(subtree, slots) when is_list(subtree) and is_list(slots) do
    by_id = Map.new(flatten(subtree), &{&1.id, &1})

    Enum.flat_map(slots, &mapping_error(by_id, &1))
  end

  @spec mapping_error(%{optional(String.t()) => Block.t()}, pass_through_decl()) :: [String.t()]
  defp mapping_error(by_id, %{name: name, to: {local_id, inner_slot}}) do
    case Map.fetch(by_id, local_id) do
      :error ->
        [
          "slot #{inspect(name)} maps to #{inspect(local_id)}, which is no local id of the subtree"
        ]

      {:ok, member} ->
        inner_slot_error(name, local_id, inner_slot, Map.fetch(member.slots, inner_slot))
    end
  end

  @spec inner_slot_error(
          Block.slot_name(),
          String.t(),
          Block.slot_name(),
          {:ok, [Block.t()]} | :error
        ) :: [String.t()]
  defp inner_slot_error(name, local_id, inner_slot, :error) do
    [
      "slot #{inspect(name)} maps to slot #{inspect(inner_slot)} of #{inspect(local_id)}, " <>
        "which the subtree does not write. A member that means to receive children writes " <>
        "the empty slot explicitly."
    ]
  end

  defp inner_slot_error(_name, _local_id, _inner_slot, {:ok, []}), do: []

  defp inner_slot_error(name, local_id, inner_slot, {:ok, _filled}) do
    [
      "slot #{inspect(name)} maps to slot #{inspect(inner_slot)} of #{inspect(local_id)}, " <>
        "which the subtree also fills. The mapped inner slot holds the author's children " <>
        "and only them."
    ]
  end

  @doc """
  Every block in an expansion, in pre-order: each block, then its slot
  children.

  Slots are visited in sorted slot-name order, so the walk is deterministic
  for a `slots` map that has no order of its own. `ADR-0011`'s
  last-write-wins by position holds inside the union in exactly that order.
  """
  @spec flatten([Block.t()]) :: [Block.t()]
  def flatten(blocks) when is_list(blocks) do
    Enum.flat_map(blocks, fn %Block{} = block ->
      children =
        block.slots
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.flat_map(fn {_name, kids} -> flatten(kids) end)

      [block | children]
    end)
  end

  @doc """
  `block`'s io, with every member resolved through `palette` (`ADR-0002`'s
  Note of 2026-09-07, item 3).

  The exact answer for a composite whose expansion root is a **host** type,
  which `c:StatifierBlocks.BlockType.io/1` cannot give: the callback is handed
  a config and nothing else, so it resolves members through
  `StatifierBlocks.Palette.core/0` and falls back for a name that map does not
  carry. This is what a reader **holding a palette** calls instead - the whole
  of the difference is which palette the members are resolved through, and the
  per-key table above is unchanged.

  `block` is the composite block as the document stores it, and `palette` must
  carry its type: the type name is resolved here rather than taken as a second
  argument, so a caller cannot pair a block with another type's entry. The
  config is read **as handed** - `resolve/2`'s migration, if the caller ran
  one, is already on the block it passes.

  Raises for a `block` whose type is not a composite, for `expand/2`'s reason:
  there is nothing to derive from. Ask `composite?/1` first, which is what
  every routed reader does.
  """
  @spec io(Palette.t(), Block.t()) :: Assignability.io()
  def io(%Palette{} = palette, %Block{} = block) do
    io_over(palette, block, composite_ref!(palette, block))
  end

  @doc """
  `block`'s outcomes - its expansion root's, over the root's expanded config -
  with the root resolved through `palette` (`ADR-0002`'s Note of 2026-09-07,
  item 3).

  `io/2`'s companion, and everything that doc says about the palette, the
  block, the config and the refusal holds here unchanged.
  """
  @spec outcomes(Palette.t(), Block.t()) :: [BlockType.outcome_decl()]
  def outcomes(%Palette{} = palette, %Block{} = block) do
    outcomes_over(palette, block, composite_ref!(palette, block))
  end

  @doc false
  @spec derived_io(Palette.type_ref(), Block.config()) :: Assignability.io()
  def derived_io(ref, config) do
    io_over(Palette.core(), probe_block(ref, config), ref)
  end

  @doc false
  @spec derived_outcomes(Palette.type_ref(), Block.config()) :: [BlockType.outcome_decl()]
  def derived_outcomes(ref, config) do
    outcomes_over(Palette.core(), probe_block(ref, config), ref)
  end

  # The one derivation both the callback and `io/2` run; they differ in the
  # palette the members are resolved through and in nothing else.
  @spec io_over(Palette.t(), Block.t(), Palette.type_ref()) :: Assignability.io()
  defp io_over(%Palette{} = palette, %Block{} = block, ref) do
    {members, _param_map} = expand(block, ref)

    kinds =
      members
      |> flatten()
      |> Enum.flat_map(&Assignability.kinds(member_module(&1, palette), &1.config))
      |> Enum.uniq()

    [root | _rest] = members
    root_io = Assignability.io(member_module(root, palette), root.config)

    %{kinds: kinds, slot_accepts: slot_accepts(members, declared_slots(ref), block.id, palette)}
    |> copy_key(root_io, :consumes)
    |> copy_key(root_io, :produces)
  end

  # P3: each declared slot answers the MAPPED INNER slot's own accepted kinds,
  # read from the member the local id names and resolved through the palette
  # in hand - `Palette.core/0` behind the callback, the caller's own behind
  # `io/2`, which is the whole of the difference.
  @spec slot_accepts([Block.t()], [pass_through_decl()], Block.id(), Palette.t()) ::
          %{optional(Block.slot_name()) => [Assignability.kind()] | :any}
  defp slot_accepts(_members, [], _composite_id, _palette), do: %{}

  defp slot_accepts(members, slots, composite_id, palette) do
    by_id = Map.new(flatten(members), &{&1.id, &1})

    Map.new(slots, fn %{name: name, to: {local_id, inner_slot}} ->
      case Map.fetch(by_id, composite_id <> @separator <> local_id) do
        {:ok, member} ->
          {name,
           Assignability.slot_accepts(member_module(member, palette), member.config, inner_slot)}

        :error ->
          {name, :any}
      end
    end)
  end

  @spec outcomes_over(Palette.t(), Block.t(), Palette.type_ref()) :: [BlockType.outcome_decl()]
  defp outcomes_over(%Palette{} = palette, %Block{} = block, ref) do
    {[root | _rest], _param_map} = expand(block, ref)

    BlockType.outcomes(member_module(root, palette), root.config)
  end

  @spec composite_ref!(Palette.t(), Block.t()) :: Palette.type_ref()
  defp composite_ref!(%Palette{} = palette, %Block{type: type}) do
    case Palette.fetch(palette, type) do
      {:ok, ref} ->
        ref

      {:error, _unknown} ->
        raise ArgumentError,
              "#{inspect(type)} is not in the palette handed to " <>
                "StatifierBlocks.Composite.io/2 or outcomes/2, so its expansion " <>
                "cannot be derived. Resolve the block through the palette first."
    end
  end

  @doc false
  @spec derived_summary(declaration(), Block.config()) :: [String.t()]
  def derived_summary(%{params: params}, config) do
    params
    |> Enum.reject(&Map.get(&1, :hidden?, false))
    |> Enum.map(fn %{key: key} = param ->
      {Map.get(param, :label, key), to_text(Map.get(config, key))}
    end)
    |> Enum.reject(fn {_label, value} -> String.trim(value) == "" end)
    |> Enum.map(fn {label, value} -> label <> ": " <> value end)
  end

  @doc false
  @spec render_sentence(declaration(), Block.config()) :: String.t()
  def render_sentence(%{sentence: nil} = declaration, _config),
    do: Map.get(declaration.palette_entry, :label, declaration.name)

  def render_sentence(%{sentence: template, params: params}, config) do
    Enum.reduce(params, template, fn %{key: key}, rendered ->
      String.replace(rendered, "{" <> key <> "}", to_text(Map.get(config, key)))
    end)
  end

  @doc false
  @spec recipe_insert(Palette.type_ref(), Edit.target(), StatifierBlocks.Document.t()) ::
          {:ok, [Edit.t()]} | {:error, term()}
  def recipe_insert(ref, {_parent, _slot, _index} = target, _document) do
    declaration = Palette.call(ref, :__composite__, [], nil)

    config = Map.new(declaration.params, fn %{key: key, default: default} -> {key, default} end)

    block =
      Block.new(declaration.name, config: config, type_version: declaration.version)

    {:ok, [{:insert, target, block}]}
  end

  # -- declaration ------------------------------------------------------

  @spec required_option(keyword(), atom()) :: term()
  defp required_option(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} ->
        value

      :error ->
        raise ArgumentError, "use StatifierBlocks.Composite: #{inspect(key)} is required"
    end
  end

  @spec param?(term()) :: boolean()
  defp param?(%{key: key, type: _type, label: _label, required?: _required} = decl)
       when is_binary(key),
       do: Map.has_key?(decl, :default)

  defp param?(_other), do: false

  # P1's shape, plus the two refusals that need no subtree: a duplicate
  # `:name` and two declared slots mapping to one inner slot. The three that
  # read the subtree are `expand/2`'s, because a module composite has no
  # subtree until it has params.
  @spec normalize_slots!(term()) :: [pass_through_decl()]
  defp normalize_slots!(slots) when is_list(slots) do
    decls = Enum.map(slots, &normalize_slot!/1)

    refute_duplicates!(Enum.map(decls, & &1.name), ":slots declares the slot name")
    refute_duplicates!(Enum.map(decls, & &1.to), ":slots maps two slots to the inner slot")

    decls
  end

  defp normalize_slots!(other) do
    raise ArgumentError,
          "use StatifierBlocks.Composite: :slots must be a list of maps carrying " <>
            ":name and :to, got: #{inspect(other)}"
  end

  @spec normalize_slot!(term()) :: pass_through_decl()
  defp normalize_slot!(%{name: name, to: {local_id, inner_slot}} = decl)
       when is_binary(name) and name != "" and is_binary(local_id) and local_id != "" and
              is_binary(inner_slot) and inner_slot != "" do
    %{
      name: name,
      to: {local_id, inner_slot},
      label: Map.get(decl, :label, name),
      arity: Map.get(decl, :arity, :any)
    }
  end

  defp normalize_slot!(other) do
    raise ArgumentError,
          "use StatifierBlocks.Composite: each :slots entry is a map with :name (a slot " <>
            "name) and :to ({local_id, inner_slot}), got: #{inspect(other)}"
  end

  @spec refute_duplicates!([term()], String.t()) :: :ok
  defp refute_duplicates!(values, what) do
    case values -- Enum.uniq(values) do
      [] ->
        :ok

      duplicates ->
        raise ArgumentError,
              "use StatifierBlocks.Composite: #{what} " <>
                "#{inspect(Enum.uniq(duplicates))} more than once. A pass-through slot " <>
                "and the inner slot it maps to are one-to-one: two authors writing one " <>
                "list has no rule for the order."
    end
  end

  # -- expansion --------------------------------------------------------

  # The params `subtree/1` is handed: the declaration's defaults, with the
  # block's stored config over them. A document may carry a config that
  # predates a param, and a composite is not the place to discover a missing
  # key - `Palette.new_block/2` already seeds every default, and this makes a
  # hand-built config behave the same way.
  @spec params_of(Palette.type_ref(), Block.config()) :: Block.config()
  defp params_of(ref, config) do
    ref
    |> Palette.call(:__composite__, [], nil)
    |> Map.fetch!(:params)
    |> Map.new(fn %{key: key, default: default} -> {key, default} end)
    |> Map.merge(config)
  end

  @spec probe_block(Palette.type_ref(), Block.config()) :: Block.t()
  defp probe_block(ref, config) do
    name = ref |> Palette.call(:__composite__, [], nil) |> Map.fetch!(:name)

    Block.new(name, id: "blk", config: config)
  end

  @spec check_local_ids!([Block.t()], Palette.type_ref()) :: :ok
  defp check_local_ids!(subtree, module) do
    ids = subtree |> flatten() |> Enum.map(& &1.id)

    Enum.each(ids, fn id ->
      unless is_binary(id) and id != "" do
        raise ArgumentError,
              "#{inspect(module)}.subtree/1 answered a block with a non-string id: #{inspect(id)}"
      end

      if String.starts_with?(id, "blk_") do
        raise ArgumentError,
              "#{inspect(module)}.subtree/1 answered a block whose id #{inspect(id)} looks like " <>
                "a freshly minted UXID. A subtree writes stable LOCAL ids; expand/2 mints the " <>
                "document's ids from the composite block's own id."
      end
    end)

    duplicates = ids -- Enum.uniq(ids)

    if duplicates != [] do
      raise ArgumentError,
            "#{inspect(module)}.subtree/1 answered duplicate local ids: " <>
              "#{inspect(Enum.uniq(duplicates))}. Minting is injective per composite, so the " <>
              "local ids must be unique within one subtree."
    end

    :ok
  end

  @spec declared_slots(Palette.type_ref()) :: [pass_through_decl()]
  defp declared_slots(ref) do
    ref
    |> Palette.call(:__composite__, [], nil)
    |> Map.get(:slots, [])
  end

  @spec check_mapping!([Block.t()], [pass_through_decl()], Palette.type_ref()) :: :ok
  defp check_mapping!(_subtree, [], _ref), do: :ok

  defp check_mapping!(subtree, slots, ref) do
    case mapping_errors(subtree, slots) do
      [] ->
        :ok

      errors ->
        raise ArgumentError,
              "#{inspect(ref)}'s pass-through declaration does not fit its own subtree: " <>
                Enum.join(errors, "; ") <> "."
    end
  end

  # P4: the composite block's own children under the declared slot are placed
  # in the mapped inner slot of the member minted from the local id, in their
  # stored order, NOT minted - they arrived carrying a document id already.
  @spec splice([Block.t()], Block.t(), [pass_through_decl()]) :: [Block.t()]
  defp splice(members, _block, []), do: members

  defp splice(members, %Block{} = block, slots) do
    Enum.reduce(slots, members, fn %{name: name, to: {local_id, inner_slot}}, acc ->
      case Map.get(block.slots, name, []) do
        [] -> acc
        children -> put_children(acc, block.id <> @separator <> local_id, inner_slot, children)
      end
    end)
  end

  @spec put_children([Block.t()], Block.id(), Block.slot_name(), [Block.t()]) :: [Block.t()]
  defp put_children(members, minted_id, inner_slot, children) do
    Enum.map(members, fn
      %Block{id: ^minted_id} = member ->
        %{member | slots: Map.put(member.slots, inner_slot, children)}

      %Block{} = member ->
        %{
          member
          | slots:
              Map.new(member.slots, fn {name, kids} ->
                {name, put_children(kids, minted_id, inner_slot, children)}
              end)
        }
    end)
  end

  @spec mint(Block.t(), Block.id(), Palette.type_ref()) :: Block.t()
  defp mint(%Block{} = block, composite_id, module) do
    slots =
      Map.new(block.slots, fn {name, children} ->
        {name, Enum.map(children, &mint(&1, composite_id, module))}
      end)

    %{block | id: mint_id(composite_id, block.id, module), slots: slots}
  end

  @spec mint_id(Block.id(), String.t(), Palette.type_ref()) :: Block.id()
  defp mint_id(composite_id, local_id, module) do
    minted = composite_id <> @separator <> local_id

    if String.contains?(minted, "__") do
      raise ArgumentError,
            "#{inspect(module)}.subtree/1's local id #{inspect(local_id)} mints " <>
              ~s(#{inspect(minted)}, which carries "__". ADR-0004 decision 3 reserves "__" ) <>
              "for the role separator and its unstate_id/1 stops inverting when a block id " <>
              "carries one."
    end

    minted
  end

  # A block is blamed on the one param whose value it carries. Two params
  # feeding one member, or none, is `nil` - "no single param is responsible",
  # which is the map's own wording and the honest answer in both directions.
  @spec param_map([Block.t()], Block.config()) :: param_map()
  defp param_map(members, params) do
    members
    |> flatten()
    |> Map.new(fn %Block{id: id, config: config} -> {id, blamed_param(config, params)} end)
  end

  @spec blamed_param(Block.config(), Block.config()) :: String.t() | nil
  defp blamed_param(config, params) do
    carried = values(config)

    blamed =
      for {key, value} <- params,
          distinguishing?(value),
          Enum.any?(carried, &(&1 === value)),
          do: key

    case blamed do
      [one] -> one
      _none_or_many -> nil
    end
  end

  # An empty param value carries nothing and would match every empty config
  # field in the expansion, which is a blame no author could act on.
  @spec distinguishing?(term()) :: boolean()
  defp distinguishing?(value), do: value not in [nil, "", [], %{}, false]

  @spec values(term()) :: [term()]
  defp values(value) when is_map(value), do: value |> Map.values() |> Enum.flat_map(&values/1)
  defp values(value) when is_list(value), do: Enum.flat_map(value, &values/1)
  defp values(value), do: [value]

  # -- member modules ---------------------------------------------------

  # `nil` for a name the palette does not carry, which is what puts
  # `Assignability`'s and `BlockType`'s documented defaults in front of the
  # member: an unresolvable member degrades rather than raising (ADR-0003
  # decision 5).
  @spec member_module(Block.t(), Palette.t()) :: Palette.type_ref() | nil
  defp member_module(%Block{type: type}, %Palette{} = palette) do
    case Palette.fetch(palette, type) do
      {:ok, ref} -> ref
      {:error, _unknown} -> nil
    end
  end

  @spec copy_key(map(), map(), atom()) :: map()
  defp copy_key(io, root_io, key) do
    case Map.fetch(root_io, key) do
      {:ok, value} -> Map.put(io, key, value)
      :error -> io
    end
  end

  @spec to_text(term()) :: String.t()
  defp to_text(nil), do: ""
  defp to_text(value) when is_binary(value), do: value
  defp to_text(value), do: to_string(value)
end
