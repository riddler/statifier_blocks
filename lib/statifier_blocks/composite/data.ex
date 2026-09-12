defmodule StatifierBlocks.Composite.Data do
  @moduledoc """
  A composite whose declaration arrives as **data** rather than as a `use`
  block (ADR-0002's 2026-09-07 amendment).

  `use StatifierBlocks.Composite` derives a block type from a declaration
  written in Elixir at compile time. This module derives the *same* block
  type from the *same* declaration written as a JSON-shaped map at run time,
  and it is the one **stateful** module this package ships: it is registered
  as the `{module, state}` half of a `t:StatifierBlocks.Palette.type_ref/0`,
  where `state` is the declaration.

      {:ok, state} = StatifierBlocks.Composite.Data.declaration(row)

      Palette.from_modules(
        [{"myapp.guarded_step", {StatifierBlocks.Composite.Data, state}}],
        core: true
      )

  The forcing case is a host whose **users** save composites. A host that
  lets a tenant build one in a browser has no compile step in that loop:
  what the tenant saved is a row, and what the palette must carry is that
  row.

  ## Why this module is stateful rather than generated

  The obvious alternative - generate a module per saved composite - is
  **rejected** by the record on four grounds, each an existing decision
  rather than a taste: it mints atoms a tenant controls into a table that is
  never collected; a generated module is not a value, and ADR-0002 decision
  2 requires one; two tenants naming a composite the same thing collide on
  one module name in one code server; and a module that can be purged
  weakens decision 3's totality. So there is one module, and the
  declaration rides beside it.

  Nothing in this package may reach a stateful module except through
  `StatifierBlocks.Palette.call/4`. That is why this module does **not**
  `@behaviour StatifierBlocks.BlockType`: it implements the behaviour's
  callbacks at **one higher arity**, with the state first, and the seam is
  what does the arithmetic. The behaviour itself is untouched - fourteen
  callbacks at the arities it declares.

  ## Everything the composite amendment decides holds here unchanged

  `slots/1` is `[]`, `config_schema/1` is the params, `emit/2` raises, the
  expansion root is the subtree's head, ids are minted deterministically
  from the composite block's id, and `StatifierBlocks.Composite.expand!/2` is
  the one expansion function - a data composite is expanded by the *same*
  function over the *same* subtree, which is why it answers the environment
  walk the same way and compiles to the same bytes.

  What differs is only where the subtree comes from: a `use`-composite
  writes a `subtree/1` **function**, and a declaration held as data holds a
  **template** instead.

  ## The declaration

  | Key | Required | Shape |
  |---|---|---|
  | `"type_name"` | yes | the name the document uses, and the key this entry is registered under |
  | `"version"` | yes | a positive integer; `current_version/0` answers it |
  | `"params"` | yes | a list of field declarations, JSON-shaped (below) |
  | `"subtree"` | yes | a non-empty list of template nodes (below); the head is the expansion root |
  | `"palette_entry"` | no | the map `palette_entry/0` answers, with string keys |
  | `"sentence"` | no | a template string; `{{key}}` is replaced by the param's value rendered as a string |
  | `"slots"` | no | defaults to `%{}`; the pass-through slots this composite exposes, each mapped to the `[local_id, inner_slot]` it stands for (below) |
  | `"migrations"` | no | defaults to `[]`; the ordered migration steps `migrate_config/3` walks from a stored version to the declaration's current one (below) |
  | `"outcomes"` | no | defaults to `[]`; a JSON array of outcome **names** this composite declares, which replaces the expansion root's derived list and is checked against what the `"subtree"`'s members can raise (ADR-0002's Amendment of 2026-09-12, `C4`) |

  **Two of the three overridables have a key here; the third cannot.** A
  `use`-composite may override `sentence/1`, `palette_entry/0` and
  `validate_config/1`. The first two are values, so they are the
  `"sentence"` and `"palette_entry"` keys. The third is a **function**, and
  a declaration held as data cannot hold one - the same ground the subtree
  is a template rather than a `subtree/1`. So a data composite gets
  `validate_config/1` as its params alone refuse it, and a cross-param
  refusal is one of the two things a host must still write a
  `use`-composite module for (the other being a sentence that is not a
  substitution). That is a cost of the data shape, not an oversight.

  ### `"params"` is decision 7's `t:StatifierBlocks.BlockType.field_decl/0`, in JSON

  Each entry is a map with string keys: `"key"`, `"type"`, `"label"`,
  `"default"`, and whichever of `"required?"`, `"value_path"`,
  `"datamodel_path?"`, `"hidden?"` and `"readonly?"` the declaration writes.
  No new key and no new field type is introduced here, and every refusal
  decision 7 and its amendments state applies to a param unchanged.

  `"type"` is a field type's **name as a string**, and all nine of decision
  7's field types now have one (ADR-0005's 2026-09-07 amendment, clause
  `19E`). The five that carry nothing - `"string"`, `"integer"`,
  `"boolean"`, `"expression"` and `"duration"` - are the name alone, and an
  `"options"` on one of them is refused. The four that carry options
  (`{:select, choices}`, `{:list, inner}`, `{:path, opts}` and
  `{:type_expr, opts}`) are the name plus **one optional `"options"` key**,
  which is what the tuple's second element rides in:

  | `"type"` | `"options"` | The `t:StatifierBlocks.BlockType.field_type/0` built |
  |---|---|---|
  | `"select"` | `%{"choices" => [[value, label], ...]}`, a non-empty list of two-element lists of strings | `{:select, [{value, label}, ...]}` |
  | `"path"` | the path options map: whichever of `"expects"` and `"writes"` the field declares, each a type expression as ADR-0011 spells one - a non-empty string | `{:path, %{expects: T}}` / `{:path, %{writes: T}}` / `{:path, %{}}` |
  | `"list"` | `%{"inner" => ...}`, whose value is itself a `"type"` / `"options"` pair - the same spelling, one level down | `{:list, inner}` |
  | `"type_expr"` | `%{"arms" => ["name", "inline"], "allow_empty?" => false}`, both keys optional and `"arms"` any non-empty subset | `{:type_expr, %{arms: [:name, :inline], allow_empty?: bool}}` |

  `"select"`'s choices are **pairs and not a map** because `{:select,
  choices}` is an *ordered* list and a JSON object does not promise order.
  `"path"`'s options are the map itself rather than a wrapper, because
  `path_opts` is already a map with two optional keys - and its values are
  the strings ADR-0011 already writes, so a `writes:` carrying a
  `{:list, T}` or a `{:shape, members}` term has no spelling here and is
  refused rather than half-carried. `"list"` recurses through the same
  spelling, so an inner kind that is itself unspellable makes the whole
  field unspellable by the ordinary rule rather than by a special case.
  `"type_expr"` needs nothing from `statifier_datamodel`: the value such a
  field holds is already JSON (`StatifierBlocks.BlockType`'s
  `t:StatifierBlocks.BlockType.type_expr_opts/0`), so the spelling carries
  `opts` and no type expression crosses a package boundary.

  The list is **decoded once**, when the entry is built, and
  `config_schema/1` answers the decoded list. It is not decoded per call,
  because decision 4 makes `config_schema/1` pure and a decode that could
  fail on the hot path is a callback that can fail. That is also why
  `declaration/1` refuses a param with no `"default"` rather than leaving
  F3's missing-`default:` refusal to the compile: this is the last moment a
  malformed declaration can be refused, and it is where the `use` macro
  refuses the same thing.

  ### The subtree template

  A template node is a map with string keys:

      %{
        "type"      => "core.invoke",
        "id_suffix" => "call",
        "config"    => %{"invoke_type" => %{"$param" => "invoke_type"},
                         "assign_to"   => ""},
        "slots"     => %{"on_error" => [ ...nodes... ]}
      }

    * **`"type"`** is a `type_name` resolvable in the same palette. It is
      not checked here - the palette is not built yet - and an unresolvable
      one is the compiler's ordinary unknown-block-type arm on the expanded
      block, which decision 3 already makes total.
    * **`"id_suffix"`** matches `~r/\\A[a-z0-9]+(_[a-z0-9]+)*\\z/` and is
      unique within one declaration. The minted id is the composite block's
      own id, an underscore, and the suffix, so a `blk_GS` composite mints
      `blk_GS_call`. That pattern can produce no `__`, which is what keeps
      ADR-0004 decision 3's uniqueness argument and its `unstate_id/1`
      invertibility holding.
    * **`"config"`** is a map of the type's config keys to JSON values.
    * **`"slots"`** is optional, defaulting to `%{}`: a slot name to a list
      of nodes. This is the **node-level** key; the declaration-level
      `"slots"` below is a different one, and the nesting says which is
      meant - the node-level one is reached only through `"subtree"`.

  ### The declaration-level `"slots"` key: pass-through slots

  Optional, defaulting to `%{}`: a map of the slot name the composite
  exposes to the `[local_id, inner_slot]` it maps to - a two-element JSON
  array, because JSON has no tuple. A value may instead be a map carrying
  `"to"` and the optional `"label"` (defaulting to the slot name) and
  `"arity"` (one of `"any"`, `"one"`, `"zero_or_one"`, `"one_or_more"`,
  defaulting to `"any"`); the array is sugar for that map with the two
  defaults. It decodes to the same list `use StatifierBlocks.Composite`'s
  `:slots` option writes, so `slots/2` here and `slots/1` there answer the
  same thing from the same shape.

  A mapping that does not fit its own subtree is refused **here**, where
  a module composite's is refused at its first expansion: the template is
  static, so `declaration/1` sees all three cases - a `local_id` naming no
  node, an `inner_slot` the named node's own `"slots"` does not write, and
  a mapped inner slot the template also fills - and this is the last moment
  a malformed declaration can be refused. Two slots mapped to one inner
  slot is refused with them.

  ### The placeholder vocabulary is one arm, and one escape

  A map with exactly the single key `"$param"`, whose value is a declared
  param key, is a placeholder: it is replaced **whole** by that param's
  value, at that param's declared type, so a `:boolean` param substitutes a
  boolean and not the string `"true"`. A map with exactly the single key
  `"$literal"` is its value, unsubstituted - the escape that keeps a config
  value which genuinely is a one-key `"$param"` map expressible. Every other
  JSON value is a literal, including every other map. A `"$param"` naming an
  undeclared key is refused by `declaration/1`.

  **Whole-value substitution is the whole vocabulary, and that is a
  decision, not an omission.** There is no interpolation of a param into a
  larger string, no expression, no conditional and no default-if-blank. The
  reason is `Collapse`: the gesture that lifts an arrangement's config
  values into params emits **whole** values, so whole-value substitution is
  exactly the arm it needs. A template arm `Collapse` cannot emit would
  exist only for a declaration written by hand, in a feature whose whole
  point is declarations that were not.

  ## `param_map` is derived here, not declared

  A node is attributed to param key *K* when the placeholders in **its own
  `"config"`**, not its slots' children, name exactly one distinct param,
  and to `nil` when they name none or more than one. That is what makes a
  finding inside an expansion attributable for a declaration nobody wrote by
  hand, and it is the same answer `StatifierBlocks.Composite`'s own
  `param_map` reaches by comparing values.

  ## The declaration-level `"migrations"` key

  Optional, defaulting to `[]`: an ordered list of migration steps, each a
  map with string keys carrying `"from"` and at least one of `"rename"`,
  `"drop"` and `"default"` (ADR-0002's 2026-09-07 migrations amendment).

      %{
        "from"    => 1,
        "rename"  => %{"limit" => "amount_limit"},
        "drop"    => ["legacy_mode"],
        "default" => %{"currency" => "USD"}
      }

    * **`"from"`** (required) is a positive integer, the `type_version` the
      step carries a config **from**; the step carries it to `from + 1`.
    * **`"rename"`** is a map of old config key to new config key. The value
      moves; nothing else about it changes.
    * **`"drop"`** is a list of config keys removed.
    * **`"default"`** is a map of config key to a JSON value, the keys the
      old config **gains** with that value.

  **Within one step the three parts run in a fixed order: `rename`, then
  `drop`, then `default`**, so `"drop"` and `"default"` are written in the
  names the step produces rather than the names it consumes. A key named by
  both `"drop"` and `"default"` in one step is a contradiction rather than
  an ordering question, and is refused.

  The `"from"` values are **strictly ascending and contiguous**, and the last
  is `version - 1`: a list that cannot carry its own earliest version to its
  current one is broken, not usable-in-part. `migrate_config/3` applies every
  step at or above the stored version and below `"version"`, in ascending
  order, in **one** call - `StatifierBlocks.Palette.resolve/2`'s one-call rule
  is untouched, and the ladder runs inside the call.

  A step naming an **unknown key** is refused. Known is defined by walking
  the chain **backwards** from the declared param keys - the shape at
  `"version"` - undoing each step in descending `"from"` order and, within a
  step, in the reverse of the forward order: undo `"default"` (each key must
  be present; remove it), then `"drop"` (each key must be absent; add it),
  then `"rename"` (each new name present and each old name absent; put the
  old name back). A declaration states its current params and not the shape
  it started from, so the current end of the chain is the only known one.
  A step's values are **not** type-checked here, for the reason a template
  node's `"config"` values are not: the migrated config meets decision 7's
  refusals at the compile, exactly as a stored config does.

  Every one of these refusals is `declaration/1`'s, at entry-build time, so a
  palette can never hold a broken chain and `migrate_config/3` can never meet
  one.

  ### `"default"` here is not a param's `"default"`

  A param's `"default"` is decision 7's `field_decl/0` key, one level inside
  `"params"`, and it is the value a **new** block starts with. A step's
  `"default"` is one level inside `"migrations"` and it is the value an
  **old stored** block's config gains. The nesting depth says which is meant.

  ### What a step cannot express is still a refusal

  `rename`, `drop` and `default` are the whole vocabulary: no value
  transform, no merge, no split, no conditional. A declaration held as data
  cannot hold a function, the same ground the subtree is a template. So a
  change no step can express keeps the answer it has: the declaration writes
  no step for that version, a block stored **below the earliest step's
  `"from"`** answers `{:error, {:no_migration_from, from}}`, and a host that
  needs more writes a `use`-composite module and its own `migrate_config/2`.
  A declaration that writes no `"migrations"` key, or writes the empty list,
  keeps that refusal for every stored version.

  **A module composite is untouched.** `use StatifierBlocks.Composite` gains
  no `migrations:` option: a module composite has the whole of Elixir for the
  job and writes `migrate_config/2` itself, with ADR-0007's injected refusal
  as the default for one that does not.

  ## The hygiene obligation a bump is for

  `StatifierBlocks.Palette.manifest/1`'s entries are `{name, version}` and
  the compiler's `palette_hash/1` triples are `{type_name, module,
  version}`, where every data composite's module element is this one. So
  both distinguish two data composites by **type name and version**, and
  neither distinguishes two revisions of one declaration registered under
  one name at one version. `StatifierBlocks.CompilationRecord` already says
  the hash is "a hygiene aid, not a commitment"; what this module adds is
  who carries it: `"version"` is **required**, and a host that changes a
  data composite's `params` or `subtree` bumps it.
  """

  alias StatifierBlocks.{Block, BlockType, Composite}

  @typedoc """
  One template node, decoded: the member's type name, its local id suffix,
  its config template and its slot templates.
  """
  @type node_template :: %{
          type: Block.type_name(),
          id_suffix: String.t(),
          config: %{optional(String.t()) => term()},
          slots: %{optional(Block.slot_name()) => [node_template()]}
        }

  @typedoc """
  One migration step, decoded: the `type_version` it carries a config from,
  and the three parts, each defaulting to empty.

  The parts run `rename`, then `drop`, then `default` (ADR-0002's
  migrations amendment, M2).
  """
  @type migration_step :: %{
          from: pos_integer(),
          rename: %{optional(String.t()) => String.t()},
          drop: [String.t()],
          default: %{optional(String.t()) => term()}
        }

  @typedoc """
  The decoded declaration - what a palette entry carries beside this module.

  `StatifierBlocks.Palette` treats it as opaque; this is the one shape this
  package declares for a stateful entry's `state`, and a host's own stateful
  type declares its own.
  """
  @type state :: %{
          name: Block.type_name(),
          params: [BlockType.field_decl()],
          version: pos_integer(),
          sentence: String.t() | nil,
          palette_entry: BlockType.palette_entry(),
          subtree: [node_template(), ...],
          slots: [Composite.pass_through_decl()],
          migrations: [migration_step()],
          outcomes: [String.t()]
        }

  @id_suffix ~r/\A[a-z0-9]+(_[a-z0-9]+)*\z/

  # The five field types whose whole spelling is their name. An `"options"`
  # beside one of them is refused: there is no second element to carry.
  @plain_field_types %{
    "string" => :string,
    "integer" => :integer,
    "boolean" => :boolean,
    "expression" => :expression,
    "duration" => :duration
  }

  # The four that carry options, spelled as the name plus `"options"`
  # (ADR-0005's 2026-09-07 amendment, clause 19E).
  @option_field_types ~w(select path list type_expr)

  @field_types Map.keys(@plain_field_types) ++ @option_field_types

  @path_opt_keys %{"expects" => :expects, "writes" => :writes}

  @type_expr_arms %{"name" => :name, "inline" => :inline}

  @param_flags %{
    "required?" => :required?,
    "value_path" => :value_path,
    "datamodel_path?" => :datamodel_path?,
    "hidden?" => :hidden?,
    "readonly?" => :readonly?
  }

  @entry_keys %{
    "label" => :label,
    "group" => :group,
    "description" => :description,
    "icon" => :icon,
    "keywords" => :keywords,
    "order" => :order,
    "accent_token" => :accent_token,
    "badge" => :badge,
    "subject" => :subject,
    "default_config" => :default_config
  }

  # -- the declaration ---------------------------------------------------

  @doc """
  Decodes a stored declaration into the `state` a palette entry carries, or
  refuses it with every reason it found.

  **Every refusal is here, at entry-build time, and not at call time.** That
  placement is forced by decision 4 and decision 3 together: a callback must
  be pure and total, and `StatifierBlocks.Palette.fetch/2` must not raise,
  so the last moment a malformed declaration can be refused is before it is
  in the palette. A host registers `{module, state}` only on the `:ok`.

      iex> alias StatifierBlocks.Composite.Data
      iex> {:ok, state} =
      ...>   Data.declaration(%{
      ...>     "type_name" => "myapp.guarded_step",
      ...>     "version" => 1,
      ...>     "params" => [
      ...>       %{"key" => "invoke_type", "type" => "string",
      ...>         "label" => "Call", "required?" => true, "default" => ""}
      ...>     ],
      ...>     "subtree" => [
      ...>       %{"type" => "core.invoke", "id_suffix" => "call",
      ...>         "config" => %{"invoke_type" => %{"$param" => "invoke_type"},
      ...>                       "assign_to" => ""}}
      ...>     ]
      ...>   })
      iex> state.name
      "myapp.guarded_step"
      iex> state.params
      [%{key: "invoke_type", type: :string, label: "Call", required?: true, default: ""}]

      iex> alias StatifierBlocks.Composite.Data
      iex> Data.declaration(%{"type_name" => "x", "version" => 0,
      ...>                    "params" => [], "subtree" => []})
      {:error,
       [
         ~s("version" must be a positive integer, got: 0),
         ~s("subtree" must be a non-empty list of template nodes, got: [])
       ]}
  """
  @spec declaration(term()) :: {:ok, state()} | {:error, [String.t()]}
  def declaration(row) when is_map(row) do
    name = row["type_name"]
    version = row["version"]
    {params, param_errors} = decode_params(row["params"])
    keys = MapSet.new(params, & &1.key)
    {subtree, subtree_errors} = decode_subtree(row["subtree"], keys)
    {entry, entry_errors} = decode_entry(row["palette_entry"], name)
    {sentence, sentence_errors} = decode_sentence(row["sentence"], params)
    {slots, slot_errors} = decode_slots(row["slots"], subtree, params, subtree_errors)

    {migrations, migration_errors} =
      decode_migrations(row["migrations"], version, params, param_errors)

    {outcomes, outcome_errors} = decode_outcomes(row["outcomes"])

    errors =
      name_errors(name) ++
        version_errors(version) ++
        param_errors ++
        subtree_errors ++
        entry_errors ++ sentence_errors ++ slot_errors ++ migration_errors ++ outcome_errors

    case errors do
      [] ->
        {:ok,
         %{
           name: name,
           params: params,
           version: version,
           sentence: sentence,
           palette_entry: entry,
           subtree: subtree,
           slots: slots,
           migrations: migrations,
           outcomes: outcomes
         }}

      errors ->
        {:error, errors}
    end
  end

  def declaration(row), do: {:error, ["a declaration must be a map, got: #{inspect(row)}"]}

  # -- the callbacks, each at one higher arity ---------------------------

  @doc """
  The declaration, in the shape `c:StatifierBlocks.Composite.subtree/1`'s
  `use` counterpart answers it.

  A `use`-composite reads a module attribute the macro wrote at compile
  time. This module has no such attribute to read - its declaration arrives
  at run time - so it answers the state, which is the whole reason the
  declaration **is** the state rather than a pointer to one. The `:subtree`
  template is not part of the declaration shape and is read by `subtree/2`.
  """
  @spec __composite__(state()) :: Composite.declaration()
  def __composite__(state) do
    Map.take(state, [:name, :params, :version, :sentence, :palette_entry, :slots, :outcomes])
  end

  @doc """
  The blocks this composite stands for, given its params: the template with
  its placeholders substituted.

  Pure in decision 4's sense, for the reason a `use`-composite's `subtree/1`
  is: the template is a value, substitution is total over it, and the same
  params answer the same blocks forever.
  """
  @spec subtree(state(), Block.config()) :: [Block.t()]
  def subtree(%{subtree: template}, params) do
    Enum.map(template, &instantiate(&1, params))
  end

  @doc "The declaration's params, in declaration order."
  @spec config_schema(state(), Block.config()) :: [BlockType.field_decl()]
  def config_schema(%{params: params}, _config), do: params

  @doc """
  The declared pass-through slots, in declaration order, and `[]` for a
  declaration that names none - the same answer, from the same shape, that
  a `use`-composite's `slots/1` gives (`ADR-0002`'s pass-through amendment,
  P2).
  """
  @spec slots(state(), Block.config()) :: [BlockType.slot_decl()]
  def slots(state, _config), do: Composite.derived_slots(__composite__(state))

  @doc "The version the declaration states."
  @spec current_version(state()) :: pos_integer()
  def current_version(%{version: version}), do: version

  @doc "The declaration's palette entry."
  @spec palette_entry(state()) :: BlockType.palette_entry()
  def palette_entry(%{palette_entry: entry}), do: entry

  @doc """
  Walks the declared `"migrations"` chain once, from the stored version to
  the declaration's current one (ADR-0002's migrations amendment, M3).

  Every step at or above `from` and below `"version"` runs, in ascending
  `"from"` order, and the result comes back as one `{:ok, config}`. A stored
  version **below the earliest step's `"from"`** - which includes every
  version when the declaration writes no steps - is ADR-0007's refusal,
  unchanged: a declaration says which versions it carries forward, and one
  it wrote no step for is one it does not claim to understand (M6).

  The chain was validated at `declaration/1`, so this function cannot meet a
  gap, an out-of-order step or an unknown key (M5).
  """
  @spec migrate_config(state(), pos_integer(), Block.config()) ::
          {:ok, Block.config()} | {:error, term()}
  def migrate_config(%{migrations: steps, version: version}, from, config) do
    case Enum.filter(steps, &(&1.from >= from and &1.from < version)) do
      [%{from: ^from} | _rest] = applicable ->
        {:ok, Enum.reduce(applicable, config, &apply_step/2)}

      _none_or_starting_above ->
        {:error, {:no_migration_from, from}}
    end
  end

  # `rename`, then `drop`, then `default` (M2). A `"rename"` whose old key
  # the stored config never carried moves nothing rather than writing `nil`;
  # a `"default"` ADDS its key, so a stored config that already carries one
  # keeps its own value - `"drop"` is the vocabulary's only removal.
  @spec apply_step(migration_step(), Block.config()) :: Block.config()
  defp apply_step(%{rename: rename, drop: drop, default: default}, config) do
    renamed =
      Enum.reduce(rename, config, fn {old, new}, acc ->
        case Map.pop(acc, old, :absent) do
          {:absent, _acc} -> acc
          {value, rest} -> Map.put(rest, new, value)
        end
      end)

    dropped = Map.drop(renamed, drop)

    Enum.reduce(default, dropped, fn {key, value}, acc -> Map.put_new(acc, key, value) end)
  end

  @doc """
  ADR-0007's injected `:ok`, for the reason the `use`-composite leaves it
  there: the refusals a param declares are declaration-level, and the
  compile already runs every one of them over `config_schema/1`, which for a
  composite is the params.
  """
  @spec validate_config(state(), Block.config()) :: :ok
  def validate_config(_state, _config), do: :ok

  @doc "The derived `io/1`, over the same expansion."
  @spec io(state(), Block.config()) :: StatifierBlocks.Assignability.io()
  def io(state, config), do: Composite.derived_io({__MODULE__, state}, config)

  @doc """
  The declaration's `"outcomes"` names, or - for a declaration that writes
  none - the expansion root's outcomes, over its expanded config.

  `ADR-0002`'s Amendment of 2026-09-12, `C4`: the data spelling of the same
  declaration key, read through the same derivation, so a data composite and
  the module composite of the same shape answer the same list.
  """
  @spec outcomes(state(), Block.config()) :: [BlockType.outcome_decl()]
  def outcomes(state, config), do: Composite.derived_outcomes({__MODULE__, state}, config)

  @doc """
  The declaration's sentence template rendered over the config, or the
  palette label when it declares none.
  """
  @spec sentence(state(), Block.config()) :: String.t()
  def sentence(state, config), do: Composite.render_sentence(__composite__(state), config)

  @doc """
  The declaration's chips: one per param the config gives a value to, minus
  those declared `hidden?: true`.

  The same derivation the `use` block injects (ADR-0002's Note of
  2026-09-07, item 4), reached at one higher arity like every other callback
  here - so a data composite's card draws the summary its module twin draws.
  """
  @spec summary(state(), Block.config()) :: [String.t()]
  def summary(state, config), do: Composite.derived_summary(__composite__(state), config)

  @doc """
  Raises. A composite is replaced by its expansion at Resolve, so no
  composite block survives to Emit; reaching this means the expansion did
  not run.
  """
  @spec emit(state(), Block.t(), term()) :: no_return()
  def emit(_state, %Block{id: id, type: type}, _context) do
    raise RuntimeError,
          "#{inspect(__MODULE__)}.emit/2 was reached for block #{inspect(id)} of type " <>
            "#{inspect(type)}. A composite is replaced by its expansion at Resolve " <>
            "(ADR-0004, sb-nzc1), so no composite block survives to Emit; reaching this " <>
            "means the expansion did not run."
  end

  # -- template instantiation --------------------------------------------

  @spec instantiate(node_template(), Block.config()) :: Block.t()
  defp instantiate(%{type: type, id_suffix: suffix, config: config, slots: slots}, params) do
    Block.new(type,
      id: suffix,
      config: substitute(config, params),
      slots:
        Map.new(slots, fn {name, kids} -> {name, Enum.map(kids, &instantiate(&1, params))} end)
    )
  end

  # The placeholder vocabulary: one arm, one escape, and every other value a
  # literal. A one-key `"$param"` map is replaced WHOLE, at the param's
  # declared type; a one-key `"$literal"` map is its value, which is what
  # keeps a config value that genuinely is a `"$param"` map expressible.
  @spec substitute(term(), Block.config()) :: term()
  defp substitute(%{"$param" => key} = node, params) when map_size(node) == 1,
    do: Map.get(params, key)

  defp substitute(%{"$literal" => value} = node, _params) when map_size(node) == 1,
    do: value

  defp substitute(value, params) when is_map(value),
    do: Map.new(value, fn {k, v} -> {k, substitute(v, params)} end)

  defp substitute(value, params) when is_list(value), do: Enum.map(value, &substitute(&1, params))

  defp substitute(value, _params), do: value

  # -- decoding ----------------------------------------------------------

  @spec name_errors(term()) :: [String.t()]
  defp name_errors(name) when is_binary(name) and name != "", do: []

  defp name_errors(name),
    do: [~s("type_name" must be a non-empty string, got: #{inspect(name)})]

  @spec version_errors(term()) :: [String.t()]
  defp version_errors(version) when is_integer(version) and version > 0, do: []

  defp version_errors(version),
    do: [~s("version" must be a positive integer, got: #{inspect(version)})]

  @spec decode_params(term()) :: {[BlockType.field_decl()], [String.t()]}
  defp decode_params(params) when is_list(params) do
    {decoded, errors} =
      params
      |> Enum.map(&decode_param/1)
      |> Enum.split_with(&match?({:ok, _decl}, &1))

    duplicates =
      decoded |> Enum.map(fn {:ok, decl} -> decl.key end) |> then(&(&1 -- Enum.uniq(&1)))

    duplicate_errors =
      if duplicates == [],
        do: [],
        else: [~s("params" declares duplicate keys: #{inspect(Enum.uniq(duplicates))})]

    {Enum.map(decoded, fn {:ok, decl} -> decl end),
     Enum.map(errors, fn {:error, message} -> message end) ++ duplicate_errors}
  end

  defp decode_params(params),
    do: {[], [~s("params" must be a list of field declarations, got: #{inspect(params)})]}

  @spec decode_param(term()) :: {:ok, BlockType.field_decl()} | {:error, String.t()}
  defp decode_param(%{"key" => key, "type" => type, "label" => label} = param)
       when is_binary(key) and is_binary(label) do
    cond do
      not Map.has_key?(param, "default") ->
        {:error,
         ~s(param #{inspect(key)} is declared with no "default", so it has no ) <>
           "value to read when a config leaves it unset"}

      (unknown = param_unknown_keys(param)) != [] ->
        {:error, ~s(param #{inspect(key)} declares unknown keys: #{inspect(unknown)})}

      true ->
        case decode_field_type(type, Map.get(param, "options", :absent)) do
          {:ok, field_type} -> {:ok, decoded_param(key, field_type, label, param)}
          {:error, message} -> {:error, ~s(param #{inspect(key)} ) <> message}
        end
    end
  end

  defp decode_param(param),
    do:
      {:error, ~s(a param declares "key", "type", "label" and "default", got: #{inspect(param)})}

  @spec param_unknown_keys(map()) :: [String.t()]
  defp param_unknown_keys(param) do
    known = ["key", "type", "label", "default", "options"] ++ Map.keys(@param_flags)

    (Map.keys(param) -- known) |> Enum.sort()
  end

  # Clause 19E's table, read the other way: a `"type"` name and an optional
  # `"options"` map become one `t:StatifierBlocks.BlockType.field_type/0`.
  # Every refusal names what it could not spell, because this is the last
  # moment a malformed declaration can be refused.
  @spec decode_field_type(term(), term()) :: {:ok, BlockType.field_type()} | {:error, String.t()}
  defp decode_field_type(type, :absent) when is_map_key(@plain_field_types, type),
    do: {:ok, Map.fetch!(@plain_field_types, type)}

  defp decode_field_type(type, _options) when is_map_key(@plain_field_types, type),
    do:
      {:error,
       ~s(declares an "options" beside the field type #{inspect(type)}, which carries none)}

  defp decode_field_type("select", %{"choices" => choices} = options)
       when map_size(options) == 1 do
    if is_list(choices) and choices != [] and Enum.all?(choices, &choice_pair?/1) do
      {:ok, {:select, Enum.map(choices, fn [value, label] -> {value, label} end)}}
    else
      {:error,
       ~s(declares "select" choices that are not a non-empty list of ) <>
         "[value, label] string pairs, got: #{inspect(choices)}"}
    end
  end

  defp decode_field_type("select", options),
    do:
      {:error, ~s(declares "select" with no "choices" in its "options", got: #{inspect(options)})}

  defp decode_field_type("path", :absent), do: {:ok, {:path, %{}}}

  defp decode_field_type("path", options) when is_map(options) do
    case Map.keys(options) -- Map.keys(@path_opt_keys) do
      [] ->
        decode_path_opts(options)

      unknown ->
        {:error,
         ~s(declares "path" options this shape cannot spell: #{inspect(Enum.sort(unknown))})}
    end
  end

  defp decode_field_type("path", options),
    do: {:error, ~s(declares "path" options that are not a map, got: #{inspect(options)})}

  defp decode_field_type("list", %{"inner" => inner} = options)
       when map_size(options) == 1 and is_map(inner) do
    case Map.keys(inner) -- ["type", "options"] do
      [] ->
        case decode_field_type(Map.get(inner, "type"), Map.get(inner, "options", :absent)) do
          {:ok, decoded} -> {:ok, {:list, decoded}}
          {:error, message} -> {:error, ~s(declares a "list" whose inner field type ) <> message}
        end

      unknown ->
        {:error,
         ~s(declares a "list" whose "inner" carries unknown keys: #{inspect(Enum.sort(unknown))})}
    end
  end

  defp decode_field_type("list", options),
    do:
      {:error,
       ~s(declares "list" with no "inner" field type in its "options", got: #{inspect(options)})}

  defp decode_field_type("type_expr", :absent), do: {:ok, {:type_expr, %{}}}

  defp decode_field_type("type_expr", options) when is_map(options) do
    case Map.keys(options) -- ["arms", "allow_empty?"] do
      [] ->
        decode_type_expr_opts(options)

      unknown ->
        {:error,
         ~s(declares "type_expr" options this shape cannot spell: #{inspect(Enum.sort(unknown))})}
    end
  end

  defp decode_field_type("type_expr", options),
    do: {:error, ~s(declares "type_expr" options that are not a map, got: #{inspect(options)})}

  defp decode_field_type(type, _options),
    do:
      {:error,
       ~s(declares an unspellable field type #{inspect(type)}; a declaration held as ) <>
         "data spells one of #{inspect(Enum.sort(@field_types))}"}

  @spec choice_pair?(term()) :: boolean()
  defp choice_pair?([value, label]) when is_binary(value) and is_binary(label), do: true
  defp choice_pair?(_choice), do: false

  # ADR-0011 writes a path signature as a string, and that is the whole of
  # what this shape carries: a `{:list, T}` or a `{:shape, members}` term is
  # not JSON, so a field declaring one has no spelling here and is refused
  # rather than half-carried.
  @spec decode_path_opts(map()) :: {:ok, BlockType.field_type()} | {:error, String.t()}
  defp decode_path_opts(options) do
    bad = for {key, value} <- options, not (is_binary(value) and value != ""), do: key

    if bad == [] do
      {:ok,
       {:path, Map.new(options, fn {key, value} -> {Map.fetch!(@path_opt_keys, key), value} end)}}
    else
      {:error,
       ~s(declares "path" signatures that are not non-empty strings: #{inspect(Enum.sort(bad))})}
    end
  end

  @spec decode_type_expr_opts(map()) :: {:ok, BlockType.field_type()} | {:error, String.t()}
  defp decode_type_expr_opts(options) do
    arms = Map.get(options, "arms", :absent)
    allow_empty? = Map.get(options, "allow_empty?", :absent)

    cond do
      arms != :absent and not admitted_arms?(arms) ->
        {:error,
         ~s(declares "type_expr" arms that are not a non-empty subset of ) <>
           ~s(["name", "inline"], got: #{inspect(arms)})}

      allow_empty? != :absent and not is_boolean(allow_empty?) ->
        {:error,
         ~s(declares a "type_expr" "allow_empty?" that is not a boolean, got: ) <>
           inspect(allow_empty?)}

      true ->
        opts =
          %{}
          |> put_unless_absent(:arms, arms, &Enum.map(&1, fn arm -> @type_expr_arms[arm] end))
          |> put_unless_absent(:allow_empty?, allow_empty?, & &1)

        {:ok, {:type_expr, opts}}
    end
  end

  @spec admitted_arms?(term()) :: boolean()
  defp admitted_arms?(arms) when is_list(arms) and arms != [],
    do: arms == Enum.uniq(arms) and Enum.all?(arms, &is_map_key(@type_expr_arms, &1))

  defp admitted_arms?(_arms), do: false

  @spec put_unless_absent(map(), atom(), term(), (term() -> term())) :: map()
  defp put_unless_absent(opts, _key, :absent, _decode), do: opts
  defp put_unless_absent(opts, key, value, decode), do: Map.put(opts, key, decode.(value))

  @spec decoded_param(String.t(), BlockType.field_type(), String.t(), map()) ::
          BlockType.field_decl()
  defp decoded_param(key, type, label, param) do
    base = %{
      key: key,
      type: type,
      label: label,
      required?: Map.get(param, "required?", false),
      default: Map.fetch!(param, "default")
    }

    Enum.reduce(@param_flags, base, fn {string_key, atom_key}, decl ->
      case Map.fetch(param, string_key) do
        {:ok, value} -> Map.put(decl, atom_key, value)
        :error -> decl
      end
    end)
  end

  @spec decode_subtree(term(), MapSet.t(String.t())) :: {[node_template()], [String.t()]}
  defp decode_subtree(subtree, keys) when is_list(subtree) and subtree != [] do
    {decoded, errors} =
      subtree
      |> Enum.map(&decode_node(&1, keys))
      |> Enum.split_with(&match?({:ok, _node}, &1))

    nodes = Enum.map(decoded, fn {:ok, node} -> node end)

    suffixes = nodes |> Enum.flat_map(&suffixes/1)
    duplicates = suffixes -- Enum.uniq(suffixes)

    duplicate_errors =
      if duplicates == [],
        do: [],
        else: [
          ~s("subtree" declares duplicate "id_suffix" values: ) <>
            "#{inspect(Enum.uniq(duplicates))}; minting is injective per composite, so a " <>
            "suffix is unique within one declaration"
        ]

    {nodes, Enum.map(errors, fn {:error, message} -> message end) ++ duplicate_errors}
  end

  defp decode_subtree(subtree, _keys),
    do: {[], [~s("subtree" must be a non-empty list of template nodes, got: #{inspect(subtree)})]}

  @spec decode_node(term(), MapSet.t(String.t())) :: {:ok, node_template()} | {:error, String.t()}
  defp decode_node(%{"type" => type, "id_suffix" => suffix} = node, keys)
       when is_binary(type) and type != "" and is_binary(suffix) do
    config = Map.get(node, "config", %{})
    slots = Map.get(node, "slots", %{})

    cond do
      not Regex.match?(@id_suffix, suffix) ->
        {:error,
         ~s(the "id_suffix" #{inspect(suffix)} must match ) <>
           "#{inspect(Regex.source(@id_suffix))}: the minted id is the composite block's own " <>
           ~s(id, an underscore and the suffix, and it can carry no "__")}

      not is_map(config) ->
        {:error, ~s(node #{inspect(suffix)}'s "config" must be a map, got: #{inspect(config)})}

      not is_map(slots) ->
        {:error, ~s(node #{inspect(suffix)}'s "slots" must be a map, got: #{inspect(slots)})}

      true ->
        decode_node_body(type, suffix, config, slots, keys)
    end
  end

  defp decode_node(node, _keys),
    do: {:error, ~s(a template node declares "type" and "id_suffix", got: #{inspect(node)})}

  @spec decode_node_body(
          Block.type_name(),
          String.t(),
          map(),
          map(),
          MapSet.t(String.t())
        ) :: {:ok, node_template()} | {:error, String.t()}
  defp decode_node_body(type, suffix, config, slots, keys) do
    undeclared = config |> placeholders() |> Enum.reject(&MapSet.member?(keys, &1)) |> Enum.sort()

    children =
      Map.new(slots, fn {name, kids} ->
        {name,
         if is_list(kids) do
           Enum.map(kids, &decode_node(&1, keys))
         else
           [{:error, ~s(slot #{inspect(name)} must carry a list of nodes, got: #{inspect(kids)})}]
         end}
      end)

    child_errors =
      children
      |> Enum.flat_map(fn {_name, results} -> results end)
      |> Enum.flat_map(fn
        {:error, message} -> [message]
        {:ok, _node} -> []
      end)

    cond do
      undeclared != [] ->
        {:error,
         ~s(node #{inspect(suffix)}'s config names undeclared params: ) <>
           "#{inspect(undeclared)}"}

      child_errors != [] ->
        {:error, Enum.join(child_errors, "; ")}

      true ->
        {:ok,
         %{
           type: type,
           id_suffix: suffix,
           config: config,
           slots:
             Map.new(children, fn {name, results} ->
               {name, Enum.map(results, fn {:ok, node} -> node end)}
             end)
         }}
    end
  end

  # Every param key a config template names, at any depth, so a placeholder
  # naming a key no param declares is refused where every other refusal is.
  @spec placeholders(term()) :: [String.t()]
  defp placeholders(%{"$param" => key} = node) when map_size(node) == 1, do: [key]
  defp placeholders(%{"$literal" => _value} = node) when map_size(node) == 1, do: []

  defp placeholders(value) when is_map(value),
    do: value |> Map.values() |> Enum.flat_map(&placeholders/1)

  defp placeholders(value) when is_list(value), do: Enum.flat_map(value, &placeholders/1)
  defp placeholders(_value), do: []

  @spec suffixes(node_template()) :: [String.t()]
  defp suffixes(%{id_suffix: suffix, slots: slots}) do
    [suffix | Enum.flat_map(slots, fn {_name, kids} -> Enum.flat_map(kids, &suffixes/1) end)]
  end

  # P2's declaration-level `"slots"` key: a map of slot name to
  # `[local_id, inner_slot]`, or to a map carrying `"to"` and the optional
  # `"label"` and `"arity"`, the array being sugar for the map with the two
  # defaults. It is a SIBLING of `"subtree"`, not the node-level `"slots"`
  # key inside it, and the nesting is what says which is meant.
  #
  # P5's three subtree-dependent refusals are answered HERE rather than at
  # the first expansion, because a data composite's subtree is a static
  # template: this is the last moment a malformed declaration can be
  # refused, which is what `declaration/1` is for.
  @spec decode_slots(term(), [node_template()], [BlockType.field_decl()], [String.t()]) ::
          {[Composite.pass_through_decl()], [String.t()]}
  defp decode_slots(nil, _subtree, _params, _subtree_errors), do: {[], []}

  defp decode_slots(slots, subtree, params, subtree_errors) when is_map(slots) do
    {decoded, errors} =
      slots
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {name, value} -> decode_slot(name, value) end)
      |> Enum.split_with(&match?({:ok, _decl}, &1))

    decls = Enum.map(decoded, fn {:ok, decl} -> decl end)
    messages = Enum.map(errors, fn {:error, message} -> message end)

    {decls,
     messages ++
       duplicate_target_errors(decls) ++ mapping_errors(decls, subtree, params, subtree_errors)}
  end

  defp decode_slots(slots, _subtree, _params, _subtree_errors),
    do:
      {[],
       [
         ~s("slots" must be a map of slot name to [local_id, inner_slot], got: ) <>
           "#{inspect(slots)}"
       ]}

  @spec decode_slot(term(), term()) :: {:ok, Composite.pass_through_decl()} | {:error, String.t()}
  defp decode_slot(name, [local_id, inner_slot])
       when is_binary(name) and name != "" and is_binary(local_id) and local_id != "" and
              is_binary(inner_slot) and inner_slot != "" do
    {:ok, %{name: name, to: {local_id, inner_slot}, label: name, arity: :any}}
  end

  defp decode_slot(name, %{"to" => [_local_id, _inner_slot] = to} = value) when is_binary(name) do
    with {:ok, decl} <- decode_slot(name, to),
         {:ok, arity} <- decode_arity(Map.get(value, "arity")) do
      {:ok, %{decl | label: label_value(Map.get(value, "label"), name), arity: arity}}
    else
      {:error, message} -> {:error, message}
    end
  end

  defp decode_slot(name, value),
    do:
      {:error,
       ~s(slot #{inspect(name)} must map to [local_id, inner_slot] or to a map carrying "to", ) <>
         "got: #{inspect(value)}"}

  @spec label_value(term(), String.t()) :: String.t()
  defp label_value(label, _name) when is_binary(label) and label != "", do: label
  defp label_value(_absent_or_blank, name), do: name

  @spec decode_arity(term()) :: {:ok, BlockType.slot_arity()} | {:error, String.t()}
  defp decode_arity(nil), do: {:ok, :any}
  defp decode_arity("any"), do: {:ok, :any}
  defp decode_arity("one"), do: {:ok, :one}
  defp decode_arity("zero_or_one"), do: {:ok, :zero_or_one}
  defp decode_arity("one_or_more"), do: {:ok, :one_or_more}

  defp decode_arity(other),
    do:
      {:error,
       ~s("arity" must be one of "any", "one", "zero_or_one", "one_or_more", got: ) <>
         "#{inspect(other)}"}

  @spec duplicate_target_errors([Composite.pass_through_decl()]) :: [String.t()]
  defp duplicate_target_errors(decls) do
    targets = Enum.map(decls, & &1.to)

    case targets -- Enum.uniq(targets) do
      [] ->
        []

      duplicates ->
        [
          ~s("slots" maps more than one slot to ) <>
            "#{inspect(Enum.uniq(duplicates))}; the mapped inner slot holds one author's " <>
            "children and only them"
        ]
    end
  end

  # The subtree as blocks, over the params' own defaults, which is what
  # `StatifierBlocks.Composite.mapping_errors/2` reads: the template's
  # `"id_suffix"` values ARE the local ids, and substitution touches config
  # and never a slot key. A subtree that did not decode is not checked -
  # its own errors are the ones to fix first.
  @spec mapping_errors(
          [Composite.pass_through_decl()],
          [node_template()],
          [BlockType.field_decl()],
          [String.t()]
        ) :: [String.t()]
  defp mapping_errors([], _subtree, _params, _subtree_errors), do: []
  defp mapping_errors(_decls, _subtree, _params, [_ | _]), do: []

  defp mapping_errors(decls, subtree, params, []) do
    defaults = Map.new(params, fn %{key: key, default: default} -> {key, default} end)

    Composite.mapping_errors(Enum.map(subtree, &instantiate(&1, defaults)), decls)
  end

  # -- the migrations chain ----------------------------------------------
  #
  # M5's refusals, every one of them here at entry-build time: the shape of
  # the list, the shape of each step, the chain's arithmetic, and the
  # backwards walk that defines "unknown key". A host registers `{module,
  # state}` only on the `:ok`, so a palette can never hold a broken chain
  # and `migrate_config/3` can never meet one.
  @spec decode_migrations(term(), term(), [BlockType.field_decl()], [String.t()]) ::
          {[migration_step()], [String.t()]}
  defp decode_migrations(nil, _version, _params, _param_errors), do: {[], []}

  defp decode_migrations(migrations, version, params, param_errors) when is_list(migrations) do
    {decoded, errors} =
      migrations
      |> Enum.map(&decode_migration_step/1)
      |> Enum.split_with(&match?({:ok, _step}, &1))

    steps = Enum.map(decoded, fn {:ok, step} -> step end)
    messages = Enum.map(errors, fn {:error, message} -> message end)

    case messages do
      # A step that did not decode is not walked: its own error is the one to
      # fix first, and the chain's arithmetic over a partial list says
      # nothing true.
      [] ->
        {steps, chain_errors(steps, version) ++ unknown_key_errors(steps, params, param_errors)}

      messages ->
        {steps, messages}
    end
  end

  defp decode_migrations(migrations, _version, _params, _param_errors),
    do: {[], [~s("migrations" must be a list of migration steps, got: #{inspect(migrations)})]}

  @spec decode_migration_step(term()) :: {:ok, migration_step()} | {:error, String.t()}
  defp decode_migration_step(step) when is_map(step) do
    with :ok <- step_key_errors(step),
         {:ok, from} <- step_from(step),
         {:ok, rename} <- step_rename(Map.get(step, "rename", %{}), from),
         {:ok, drop} <- step_drop(Map.get(step, "drop", []), from),
         {:ok, default} <- step_default(Map.get(step, "default", %{}), from),
         :ok <- step_part_present(step, from),
         :ok <- step_overlap_errors(drop, default, from) do
      {:ok, %{from: from, rename: rename, drop: drop, default: default}}
    end
  end

  defp decode_migration_step(step),
    do: {:error, "a migration step must be a map, got: #{inspect(step)}"}

  # Refused BY NAME, which is the practice `decode_param/1` already follows.
  @step_keys ~w(from rename drop default)

  @spec step_key_errors(map()) :: :ok | {:error, String.t()}
  defp step_key_errors(step) do
    case Map.keys(step) -- @step_keys do
      [] ->
        :ok

      unknown ->
        {:error,
         "a migration step declares keys this shape cannot spell: #{inspect(Enum.sort(unknown))}"}
    end
  end

  @spec step_from(map()) :: {:ok, pos_integer()} | {:error, String.t()}
  defp step_from(%{"from" => from}) when is_integer(from) and from > 0, do: {:ok, from}

  defp step_from(%{"from" => from}),
    do: {:error, ~s(a migration step's "from" must be a positive integer, got: #{inspect(from)})}

  defp step_from(_step), do: {:error, ~s(a migration step declares no "from")}

  @spec step_rename(term(), pos_integer()) ::
          {:ok, %{optional(String.t()) => String.t()}} | {:error, String.t()}
  defp step_rename(rename, from) when is_map(rename) do
    if Enum.all?(rename, fn {old, new} -> filled?(old) and filled?(new) end),
      do: {:ok, rename},
      else:
        {:error,
         step_message(from, ~s("rename" must map non-empty strings to non-empty strings), rename)}
  end

  defp step_rename(rename, from),
    do: {:error, step_message(from, ~s("rename" must be a map), rename)}

  @spec step_drop(term(), pos_integer()) :: {:ok, [String.t()]} | {:error, String.t()}
  defp step_drop(drop, from) when is_list(drop) do
    if Enum.all?(drop, &filled?/1),
      do: {:ok, drop},
      else: {:error, step_message(from, ~s("drop" must be a list of non-empty strings), drop)}
  end

  defp step_drop(drop, from),
    do: {:error, step_message(from, ~s("drop" must be a list of non-empty strings), drop)}

  # A step's values are NOT type-checked here, for the reason a template
  # node's `"config"` values are not: the migrated config meets decision 7's
  # refusals at the compile, exactly as a stored config does, and a check
  # here would duplicate one that already runs and can already fail.
  @spec step_default(term(), pos_integer()) ::
          {:ok, %{optional(String.t()) => term()}} | {:error, String.t()}
  defp step_default(default, from) when is_map(default) do
    if Enum.all?(Map.keys(default), &filled?/1),
      do: {:ok, default},
      else:
        {:error,
         step_message(from, ~s("default" must be a map with non-empty string keys), default)}
  end

  defp step_default(default, from),
    do: {:error, step_message(from, ~s("default" must be a map), default)}

  # A step with no part is refused rather than treated as a no-op: its
  # `"from"` would claim a version bump that changed nothing, and a version
  # bump that changed nothing is the hygiene obligation's business.
  @spec step_part_present(map(), pos_integer()) :: :ok | {:error, String.t()}
  defp step_part_present(step, from) do
    if Enum.any?(@step_keys -- ["from"], &Map.has_key?(step, &1)),
      do: :ok,
      else:
        {:error, ~s(migration step "from" #{from} carries none of "rename", "drop" and "default")}
  end

  # The one genuinely ambiguous overlap - a key named by both `"drop"` and
  # `"default"` in one step - is a contradiction rather than an ordering
  # question.
  @spec step_overlap_errors([String.t()], map(), pos_integer()) :: :ok | {:error, String.t()}
  defp step_overlap_errors(drop, default, from) do
    case Enum.filter(drop, &Map.has_key?(default, &1)) do
      [] ->
        :ok

      both ->
        {:error,
         ~s(migration step "from" #{from} names ) <>
           ~s(#{inspect(Enum.sort(Enum.uniq(both)))} in both "drop" and "default")}
    end
  end

  @spec step_message(pos_integer(), String.t(), term()) :: String.t()
  defp step_message(from, what, got),
    do: ~s(migration step "from" #{from}: ) <> what <> ", got: #{inspect(got)}"

  @spec filled?(term()) :: boolean()
  defp filled?(value), do: is_binary(value) and value != ""

  # Strictly ascending, contiguous, and ending at `version - 1`. There is no
  # partial chain: a list that cannot carry its own earliest version to its
  # current one is broken, not usable-in-part. A `"version"` that did not
  # itself decode is not compared against - its own error comes back.
  @spec chain_errors([migration_step()], term()) :: [String.t()]
  defp chain_errors([], _version), do: []

  defp chain_errors(steps, version) when is_integer(version) and version > 0 do
    froms = Enum.map(steps, & &1.from)
    contiguous = Enum.to_list(hd(froms)..(version - 1)//1)

    if froms == contiguous do
      []
    else
      [
        ~s("migrations" must declare strictly ascending, contiguous "from" values ending at ) <>
          ~s["version" - 1 (#{version - 1}), got: #{inspect(froms)}]
      ]
    end
  end

  defp chain_errors(_steps, _version), do: []

  # M4: the chain is checked BACKWARDS. A declaration states its current
  # params and does not state the shape it started from, so the current end
  # of the chain is the only known one. Start from the declared param keys -
  # the shape at `"version"` - and undo each step in descending `"from"`
  # order, and within a step in the reverse of the forward order. Params
  # that did not decode are not walked against.
  @spec unknown_key_errors([migration_step()], [BlockType.field_decl()], [String.t()]) ::
          [String.t()]
  defp unknown_key_errors(_steps, _params, [_error | _rest]), do: []

  defp unknown_key_errors(steps, params, []) do
    {_keys, errors} =
      steps
      |> Enum.sort_by(& &1.from, :desc)
      |> Enum.reduce({MapSet.new(params, & &1.key), []}, &undo_step/2)

    Enum.reverse(errors)
  end

  @spec undo_step(migration_step(), {MapSet.t(String.t()), [String.t()]}) ::
          {MapSet.t(String.t()), [String.t()]}
  defp undo_step(%{from: from, rename: rename, drop: drop, default: default}, acc) do
    acc
    |> undo_default(default, from)
    |> undo_drop(drop, from)
    |> undo_rename(rename, from)
  end

  # Each defaulted key must be IN the running set; remove it.
  defp undo_default({keys, errors}, default, from) do
    Enum.reduce(default, {keys, errors}, fn {key, _value}, {keys, errors} ->
      if MapSet.member?(keys, key) do
        {MapSet.delete(keys, key), errors}
      else
        {keys,
         [
           unknown_key(from, "default", key, "the shape above this step does not declare it")
           | errors
         ]}
      end
    end)
  end

  # Each dropped key must be ABSENT from the running set; add it.
  defp undo_drop({keys, errors}, drop, from) do
    Enum.reduce(drop, {keys, errors}, fn key, {keys, errors} ->
      if MapSet.member?(keys, key) do
        {keys,
         [
           unknown_key(from, "drop", key, "the shape above this step still declares it")
           | errors
         ]}
      else
        {MapSet.put(keys, key), errors}
      end
    end)
  end

  # Each new name must be IN the set and each old name ABSENT; replace the
  # new name with the old.
  defp undo_rename({keys, errors}, rename, from) do
    Enum.reduce(rename, {keys, errors}, fn {old, new}, {keys, errors} ->
      cond do
        not MapSet.member?(keys, new) ->
          {keys,
           [
             unknown_key(from, "rename", new, "the shape above this step does not declare it")
             | errors
           ]}

        MapSet.member?(keys, old) ->
          {keys,
           [
             unknown_key(from, "rename", old, "the shape above this step already declares it")
             | errors
           ]}

        true ->
          {keys |> MapSet.delete(new) |> MapSet.put(old), errors}
      end
    end)
  end

  @spec unknown_key(pos_integer(), String.t(), String.t(), String.t()) :: String.t()
  defp unknown_key(from, part, key, why),
    do:
      ~s(migration step "from" #{from} names an unknown key #{inspect(key)} in ) <>
        ~s("#{part}": #{why})

  @spec decode_entry(term(), term()) :: {BlockType.palette_entry(), [String.t()]}
  defp decode_entry(nil, name), do: {%{label: label_for(name)}, []}

  defp decode_entry(entry, name) when is_map(entry) do
    unknown = Map.keys(entry) -- Map.keys(@entry_keys)

    if unknown == [] do
      decoded =
        Map.new(entry, fn {key, value} -> {Map.fetch!(@entry_keys, key), value} end)

      {Map.put_new(decoded, :label, label_for(name)), []}
    else
      {%{},
       [
         ~s("palette_entry" declares keys this shape cannot spell: ) <>
           "#{inspect(Enum.sort(unknown))}"
       ]}
    end
  end

  defp decode_entry(entry, _name),
    do: {%{}, [~s("palette_entry" must be a map, got: #{inspect(entry)})]}

  # `C4`: a JSON array of outcome NAMES. The row is read by named key beside
  # the keys `declaration/1` already reads, and adding it neither adds a
  # row-level unknown-key refusal nor relies on one - this module has never
  # had the `use` form's `refute_unknown_options!/1`.
  @spec decode_outcomes(term()) :: {[String.t()], [String.t()]}
  defp decode_outcomes(nil), do: {[], []}

  defp decode_outcomes(names) when is_list(names) do
    cond do
      not Enum.all?(names, &(is_binary(&1) and &1 != "")) ->
        {[],
         [
           ~s("outcomes" must be a list of non-empty outcome name strings, got: ) <>
             inspect(names)
         ]}

      names -- Enum.uniq(names) != [] ->
        {[],
         [
           ~s("outcomes" declares ) <>
             inspect(Enum.uniq(names -- Enum.uniq(names))) <>
             " more than once; an outcome name is declared exactly once"
         ]}

      true ->
        {names, []}
    end
  end

  defp decode_outcomes(names),
    do: {[], [~s("outcomes" must be a list of outcome names, got: #{inspect(names)})]}

  @spec label_for(term()) :: String.t()
  defp label_for(name) when is_binary(name), do: name
  defp label_for(_name), do: ""

  # The record spells a data declaration's placeholders `{{key}}` while a
  # `use`-composite's `:sentence` spells them `{key}`. They are ONE
  # rendering: the double-brace spelling is collapsed here, once, for the
  # keys this declaration actually declares, so
  # `StatifierBlocks.Composite.render_sentence/2` stays the one renderer and
  # a data composite and the module composite of the same shape answer the
  # same line.
  @spec decode_sentence(term(), [BlockType.field_decl()]) :: {String.t() | nil, [String.t()]}
  defp decode_sentence(nil, _params), do: {nil, []}

  defp decode_sentence(template, params) when is_binary(template) do
    collapsed =
      Enum.reduce(params, template, fn %{key: key}, rendered ->
        String.replace(rendered, "{{" <> key <> "}}", "{" <> key <> "}")
      end)

    {collapsed, []}
  end

  defp decode_sentence(template, _params),
    do: {nil, [~s("sentence" must be a string, got: #{inspect(template)})]}
end
