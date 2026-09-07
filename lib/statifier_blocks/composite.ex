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
  | `validate_config/1` | the refusals `params` declare, over the composite's config | **yes** |
  | `slots/1` | `[]` (`RQ-SF037-3`) | no |
  | `io/1` | see below | no |
  | `current_version/0` | the version the declaration states | no |
  | `outcomes/1` | the expansion root's, over its expanded config | no |
  | `sentence/1` | the declaration's template rendered over the config | **yes** |
  | `palette_entry/0` | the map the declaration states | **yes** |
  | `emit/2` | generated, and raises if reached (`RQ-SF037-6`) | no |

  `sentence/1`, `palette_entry/0` and `validate_config/1` and **no others**
  are overridable: they are the three whose answers are about presentation and
  refusal rather than about the expansion. `migrate_config/2` keeps ADR-0007's
  injected refusal unchanged, and `fixtures/0`, `failure_outcomes/1`,
  `summary/1` and `donedata_type/1` are not derived - they stay optional and
  absent unless a declaration writes them by hand.

  `validate_config/1` is left at ADR-0007's injected `:ok`, deliberately. The
  refusals a param declares are declaration-level - F3's missing `default:`,
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
    * `slot_accepts` - `%{}`; the composite declares no slots, so there is no
      slot name to accept into
    * `consumes` - the expansion root's, or absent when the root declares none
    * `produces` - the expansion root's, or absent when the root declares none

  Dropping a non-root member's sugar under-declares rather than over-declares,
  which is the safe direction `ADR-0011` decision 6 already takes.

  ### The one limitation in the derived `io/1` and `outcomes/1`

  Both rows read a **member's module**, and a `t:StatifierBlocks.Block.t/0`
  carries a type *name*. Resolving a name to a module is
  `StatifierBlocks.Palette`'s job, and neither `c:StatifierBlocks.BlockType.io/1`
  nor `c:StatifierBlocks.BlockType.outcomes/1` is handed a palette - so these
  two derivations resolve through `StatifierBlocks.Palette.core_types/0`, the
  one type map this package holds as a value. A composite whose expansion root
  is a **host** type therefore falls back: `outcomes/1` to the behaviour's
  default outcomes, and `io/1` to `[:step]` kinds with no sugar. Both
  reference composites root at `core.*` and are exact. The environment walk is
  unaffected - it has a palette, and resolves every member through it.

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

  @typedoc "The normalized declaration, as `__composite__/0` answers it."
  @type declaration :: %{
          name: Block.type_name(),
          params: [BlockType.field_decl()],
          version: pos_integer(),
          sentence: String.t() | nil,
          palette_entry: BlockType.palette_entry()
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
      def slots(_config), do: []

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
      def palette_entry, do: @composite_declaration.palette_entry

      @impl StatifierBlocks.BlockType
      def emit(%StatifierBlocks.Block{id: id, type: type}, _context) do
        raise RuntimeError,
              "#{inspect(__MODULE__)}.emit/2 was reached for block #{inspect(id)} of type " <>
                "#{inspect(type)}. A composite is replaced by its expansion at Resolve " <>
                "(ADR-0004, sb-nzc1), so no composite block survives to Emit; reaching this " <>
                "means the expansion did not run."
      end

      defoverridable sentence: 1, palette_entry: 0

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

    %{name: name, params: params, version: version, sentence: sentence, palette_entry: entry}
  end

  @doc """
  Whether `module` is a composite block type.

  The three callers of `expand/2` - the compiler at Resolve, the editor's
  Expand operation and this module's own derivations - each have to ask
  before they expand, so the question is answered once and here.
  """
  @spec composite?(module()) :: boolean()
  def composite?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :__composite__, 0)
  end

  def composite?(_module), do: false

  @doc """
  The blocks `block` stands for, and the param each one is blamed on.

  `block` is the composite block as the document stores it; `module` is its
  own module, which every caller has already resolved through
  `StatifierBlocks.Palette.fetch/2`. The return is the expanded blocks in
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
  @spec expand(Block.t(), module()) :: {[Block.t()], param_map()}
  def expand(%Block{} = block, module) when is_atom(module) do
    unless composite?(module) do
      raise ArgumentError,
            "#{inspect(module)} is not a composite block type: it does not " <>
              "use StatifierBlocks.Composite, so there is nothing to expand."
    end

    params = params_of(module, block.config)

    subtree = module.subtree(params)

    unless is_list(subtree) and subtree != [] and Enum.all?(subtree, &match?(%Block{}, &1)) do
      raise ArgumentError,
            "#{inspect(module)}.subtree/1 must answer a non-empty list of " <>
              "StatifierBlocks.Block structs, got: #{inspect(subtree)}"
    end

    check_local_ids!(subtree, module)

    members = Enum.map(subtree, &mint(&1, block.id, module))

    {members, param_map(members, params)}
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

  @doc false
  @spec derived_io(module(), Block.config()) :: Assignability.io()
  def derived_io(module, config) do
    {members, _param_map} = expand(probe_block(module, config), module)

    kinds =
      members
      |> flatten()
      |> Enum.flat_map(&Assignability.kinds(member_module(&1), &1.config))
      |> Enum.uniq()

    [root | _rest] = members
    root_io = Assignability.io(member_module(root), root.config)

    %{kinds: kinds, slot_accepts: %{}}
    |> copy_key(root_io, :consumes)
    |> copy_key(root_io, :produces)
  end

  @doc false
  @spec derived_outcomes(module(), Block.config()) :: [BlockType.outcome_decl()]
  def derived_outcomes(module, config) do
    {[root | _rest], _param_map} = expand(probe_block(module, config), module)

    BlockType.outcomes(member_module(root), root.config)
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
  @spec recipe_insert(module(), Edit.target(), StatifierBlocks.Document.t()) ::
          {:ok, [Edit.t()]} | {:error, term()}
  def recipe_insert(module, {_parent, _slot, _index} = target, _document) do
    declaration = module.__composite__()

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

  # -- expansion --------------------------------------------------------

  # The params `subtree/1` is handed: the declaration's defaults, with the
  # block's stored config over them. A document may carry a config that
  # predates a param, and a composite is not the place to discover a missing
  # key - `Palette.new_block/2` already seeds every default, and this makes a
  # hand-built config behave the same way.
  @spec params_of(module(), Block.config()) :: Block.config()
  defp params_of(module, config) do
    module.__composite__().params
    |> Map.new(fn %{key: key, default: default} -> {key, default} end)
    |> Map.merge(config)
  end

  @spec probe_block(module(), Block.config()) :: Block.t()
  defp probe_block(module, config) do
    Block.new(module.__composite__().name, id: "blk", config: config)
  end

  @spec check_local_ids!([Block.t()], module()) :: :ok
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

  @spec mint(Block.t(), Block.id(), module()) :: Block.t()
  defp mint(%Block{} = block, composite_id, module) do
    slots =
      Map.new(block.slots, fn {name, children} ->
        {name, Enum.map(children, &mint(&1, composite_id, module))}
      end)

    %{block | id: mint_id(composite_id, block.id, module), slots: slots}
  end

  @spec mint_id(Block.id(), String.t(), module()) :: Block.id()
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

  @spec member_module(Block.t()) :: module() | nil
  defp member_module(%Block{type: type}) do
    case Palette.fetch(Palette.core(), type) do
      {:ok, module} -> module
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
