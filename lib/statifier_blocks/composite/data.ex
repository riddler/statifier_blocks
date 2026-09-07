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
  from the composite block's id, and `StatifierBlocks.Composite.expand/2` is
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

  `"type"` is a field type's **name as a string**, so the five field types
  that have one - `"string"`, `"integer"`, `"boolean"`, `"expression"` and
  `"duration"` - are what a declaration held as data can spell. The four
  that carry options (`{:select, choices}`, `{:list, inner}`,
  `{:path, opts}` and `{:type_expr, opts}`) are tuples rather than names and
  are refused here; a host needing one writes a `use`-composite module, and
  a spelling for them is a later record's to decide, not this module's to
  invent.

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
      of nodes.

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

  ## What this module does not decide: a migration

  A declaration is the only thing that can supply a migration, and no key is
  fixed for one. So a host that bumps `"version"` on a declaration with
  stored blocks is **choosing a refusal**: ADR-0007's injected
  `migrate_config/2` answers `{:error, {:no_migration_from, from}}`, this
  module leaves that injection alone, and `StatifierBlocks.Palette.resolve/2`
  therefore refuses every stored block of that type at the older version.
  That is not papered over with a derived `{:ok, config}`, which is exactly
  the answer ADR-0007's refusal exists to refuse. How a data composite
  declares a migration is an open question the record leaves open.

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
          subtree: [node_template(), ...]
        }

  @id_suffix ~r/\A[a-z0-9]+(_[a-z0-9]+)*\z/

  @field_types %{
    "string" => :string,
    "integer" => :integer,
    "boolean" => :boolean,
    "expression" => :expression,
    "duration" => :duration
  }

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

    errors =
      name_errors(name) ++
        version_errors(version) ++
        param_errors ++ subtree_errors ++ entry_errors ++ sentence_errors

    case errors do
      [] ->
        {:ok,
         %{
           name: name,
           params: params,
           version: version,
           sentence: sentence,
           palette_entry: entry,
           subtree: subtree
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
    Map.take(state, [:name, :params, :version, :sentence, :palette_entry])
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

  @doc "`[]`: a composite exposes no slot of its own."
  @spec slots(state(), Block.config()) :: [BlockType.slot_decl()]
  def slots(_state, _config), do: []

  @doc "The version the declaration states."
  @spec current_version(state()) :: pos_integer()
  def current_version(%{version: version}), do: version

  @doc "The declaration's palette entry."
  @spec palette_entry(state()) :: BlockType.palette_entry()
  def palette_entry(%{palette_entry: entry}), do: entry

  @doc """
  ADR-0007's injected refusal, unchanged: a declaration held as data fixes
  no migration key, so a `"version"` bump with stored blocks refuses rather
  than guessing.
  """
  @spec migrate_config(state(), pos_integer(), Block.config()) :: {:error, term()}
  def migrate_config(_state, from, _config), do: {:error, {:no_migration_from, from}}

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

  @doc "The expansion root's outcomes, over its expanded config."
  @spec outcomes(state(), Block.config()) :: [BlockType.outcome_decl()]
  def outcomes(state, config), do: Composite.derived_outcomes({__MODULE__, state}, config)

  @doc """
  The declaration's sentence template rendered over the config, or the
  palette label when it declares none.
  """
  @spec sentence(state(), Block.config()) :: String.t()
  def sentence(state, config), do: Composite.render_sentence(__composite__(state), config)

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
      not Map.has_key?(@field_types, type) ->
        {:error,
         ~s(param #{inspect(key)} declares an unspellable field type #{inspect(type)}; ) <>
           "a declaration held as data spells one of " <>
           "#{inspect(Map.keys(@field_types) |> Enum.sort())}"}

      not Map.has_key?(param, "default") ->
        {:error,
         ~s(param #{inspect(key)} is declared with no "default", so it has no ) <>
           "value to read when a config leaves it unset"}

      true ->
        unknown =
          Map.keys(param) -- (["key", "type", "label", "default"] ++ Map.keys(@param_flags))

        if unknown == [] do
          {:ok, decoded_param(key, type, label, param)}
        else
          {:error,
           ~s(param #{inspect(key)} declares unknown keys: #{inspect(Enum.sort(unknown))})}
        end
    end
  end

  defp decode_param(param),
    do:
      {:error, ~s(a param declares "key", "type", "label" and "default", got: #{inspect(param)})}

  @spec decoded_param(String.t(), String.t(), String.t(), map()) :: BlockType.field_decl()
  defp decoded_param(key, type, label, param) do
    base = %{
      key: key,
      type: Map.fetch!(@field_types, type),
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
