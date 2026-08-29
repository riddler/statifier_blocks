defmodule StatifierBlocks.BlockType do
  @moduledoc """
  The authoring-time extension seam. A host implements this behaviour once
  per palette entry; the `core.*` structural vocabulary this package will
  ship itself lands in a later record (ADR-0002 decision 10) and is not
  present yet.

  ## Purity (decision 4)

  Every callback is a pure function of its arguments: given the same
  arguments, a callback always returns the same result, and calling it has
  no side effect. Concretely, no callback may read the process dictionary,
  consult application configuration, perform IO, touch a database, read
  the system clock, or draw on randomness. This matters because validation runs
  on every edit and the compiler promises a deterministic build against a
  document hash - a callback that is not pure breaks both promises silently.

  A block type that genuinely needs external data does not reach for it
  from inside a callback. The host resolves that data itself before the
  operation and threads it in as part of `Block.config()` or the `emit/2`
  context - the callback stays a pure function of what it is handed.

  This contract is enforced by convention, not by the quality gate: no
  credo check and no custom gate stage exist for it. The two test-only
  block types in `test/support/block_type_fixtures.ex` are the
  demonstration - neither one reaches outside its arguments.

  ## Required and optional callbacks

  Five callbacks are required; a module missing one of them is not a valid
  `StatifierBlocks.BlockType` and fails to compile as one. Four are
  optional (`@optional_callbacks io: 1, migrate_config: 2, fixtures: 0,
  palette_entry: 0`); a module that implements only the five required ones
  compiles cleanly, and each optional absence degrades to a stated default
  rather than an error:

  | Callback | Required? | Absent means |
  |---|---|---|
  | `slots/1` | yes | - |
  | `config_schema/1` | yes | - |
  | `validate_config/1` | yes | - |
  | `current_version/0` | yes | - |
  | `emit/2` | yes | - |
  | `io/1` | no | assignability treats the block as unconstrained |
  | `migrate_config/2` | no | the type has never changed its config shape |
  | `fixtures/0` | no | the palette entry has no executable examples |
  | `palette_entry/0` | no | the editor falls back to the type name |

  ## Who owns what

  This record fixes the callback surface: names, arities, and where a
  callback lives. It does not fix the shape of every return value - some
  of those are owned by later records:

  | Callback | Shape owned by |
  |---|---|
  | `io/1` | ADR-0003 (assignability) |
  | `emit/2` | ADR-0004 (compiler provenance) |
  | `palette_entry/0` | ADR-0005 (LiveView editor) |
  """

  alias StatifierBlocks.Block

  @type slot_arity :: :any | :at_least_one | :exactly_one | :zero_or_one

  @typedoc "Name, arity, human label. Order is presentation order."
  @type slot_decl :: {Block.slot_name(), slot_arity(), String.t()}

  @type field_type ::
          :string
          | :integer
          | :boolean
          | {:select, [{value :: String.t(), label :: String.t()}]}
          | :expression
          | :duration
          | {:list, field_type()}

  @typedoc """
  Keys and list indexes from the config root down to one value, as
  `value_path` carries them (ADR-0002 decision 7, amended 2026-08-27).
  """
  @type value_path :: [String.t() | non_neg_integer()]

  @type field_decl :: %{
          required(:key) => String.t(),
          required(:type) => field_type(),
          required(:label) => String.t(),
          required(:required?) => boolean(),
          required(:default) => Block.json(),
          optional(:value_path) => value_path()
        }

  @typedoc "Names the offending config key; message is author-facing."
  @type finding :: {key :: String.t(), message :: String.t()}

  @doc """
  Slots this block carries given this config (ADR-0001 decision 5).

  Declared slots are the complete set for this config: a slot name a
  document uses that `slots/1` did not declare is `:undeclared_slot`, a
  finding a later record raises, not something this callback checks.

  The four `slot_arity/0` values:

    * `:any` - zero or more children
    * `:at_least_one` - one or more children
    * `:exactly_one` - exactly one child
    * `:zero_or_one` - zero or one child

  Stability rule (decision 6): for any config `validate_config/1` accepts,
  `slots/1` returns without raising.
  """
  @callback slots(Block.config()) :: [slot_decl()]

  @doc """
  Ordered form fields for this config (ADR-0002 decision 7). Takes config
  because a branch gains a condition field per arm, and fields can be
  config-parameterized the same way slots are.

  This is a rendering hint, not the authority - `validate_config/1` is.
  The seven closed `field_type/0` values are `:string`, `:integer`,
  `:boolean`, `{:select, options}`, `:expression`, `:duration`, and
  `{:list, field_type()}`.

  ## Where a field's value lives

  A declaration's `key` addresses `config[key]`, and the editor reads and
  writes exactly there. A field whose value lives elsewhere in the config
  says so explicitly with the optional `value_path` - a list of keys and
  list indexes from the config root down to the value, as
  `StatifierBlocks.Core.Branch.config_schema/1` uses for a per-arm
  condition stored at `config["arms"][i]["cond"]`.

  The `key` stays the field's identity either way: it is what
  `validate_config/1` anchors a finding to (ADR-0005 decision 11) and what
  the form keys its control by. `value_path` says only where the bytes
  are. Use `value_path/1`, `fetch_value/2` and `put_value/3` rather than
  reading the map key directly - they collapse both cases into one path.
  """
  @callback config_schema(Block.config()) :: [field_decl()]

  @doc """
  The authority on config validity (ADR-0002 decision 7). `config_schema/1`
  is a rendering hint only; this callback is where the real rules -
  bounds, cross-field checks, identifier syntax - live. Findings name a
  config key and carry author-facing text.
  """
  @callback validate_config(Block.config()) :: :ok | {:error, [finding()]}

  @doc """
  The version this module's config shape is at (ADR-0001 decision 4;
  ADR-0002 decision 8). Migration runs at resolution time, is applied in
  memory only, and is never written back by this package.
  """
  @callback current_version() :: pos_integer()

  @typedoc """
  What `emit/2` can refuse with (ADR-0004 decisions 4 and 10).

  A list of `finding/0` pairs is the ordinary case: a type that can
  validate its config but still cannot compile some combination of it
  reports findings against its own block id rather than raising.
  `{:invalid_role, block_id, role}` is what
  `StatifierBlocks.Compiler.Context.role_id/2` hands back for a role the
  compiler could not invert, propagated as-is by a type that mints a role
  from config.
  """
  @type emit_error :: [finding()] | {:invalid_role, Block.id(), String.t()}

  @doc """
  Emits this block's SCXML subtree (ADR-0004 decision 4).

  `context` is a `StatifierBlocks.Compiler.Context` carrying the block's own
  id and state id, the document id, the ordered summaries of its already
  compiled children, and decision 3's role-minting function. It carries no
  palette and no child's emitted SCXML, so an emission is a function of
  this block's config and its children's *ids* - which is what makes
  decision 6's per-block byte stability hold.

  The return is structural, never a string: see
  `StatifierBlocks.Emission`, and `StatifierBlocks.Core.Emit` for the shapes
  the shipped vocabulary uses.
  """
  @callback emit(Block.t(), StatifierBlocks.Compiler.Context.t()) ::
              {:ok, StatifierBlocks.Emission.t()} | {:error, emit_error()}

  @doc """
  Type expressions for assignability. The return shape is
  `t:StatifierBlocks.Assignability.io/0` (ADR-0003). Absent means
  assignability treats the block as unconstrained.
  """
  @callback io(Block.config()) :: StatifierBlocks.Assignability.io()

  @doc """
  In-memory upgrade from an older stored `type_version`; never written back
  by this package (ADR-0002 decision 8). Absent means the type has never
  changed its config shape.
  """
  @callback migrate_config(from :: pos_integer(), Block.config()) ::
              {:ok, Block.config()} | {:error, term()}

  @doc """
  Executable examples for this palette entry.

  > #### Provisional: the accepted spellings are not settled {: .warning}
  >
  > PROVISIONAL - see ADR-0002 decision 9. The spellings below come from an
  > amendment to that decision which has not been accepted. Until it is,
  > treat this list as the intended target rather than a settled contract.
  > The callback itself, and its `term()` return, are settled either way.

  The return value is one of the four spellings statifier-ui's
  `docs/fixture-bundles.md` defines, and that page is the authority:

    * `%StatifierUI.Fixtures{}` - the struct
    * `%{scenarios: ..., events: ..., datasets: ..., expressions: ...}` -
      **atom** top-level keys, the Elixir spelling written by hand
    * `%{"version" => 1, "datasets" => ...}` - **string** top-level keys,
      the JSON spelling that survives a file
    * `"palette/budget_check.fixtures.json"` - a binary path

  The bundle is addressed by the `type_name` the palette resolves it
  under, and discovery is per entry: one malformed bundle is reported
  against its own entry and every other entry still loads.

  The spec stays `term()` deliberately. statifier-ui names no single type
  for the union of these four spellings, and this package must not assert
  a type it does not own. Nothing here calls the loader, and the
  statifier-ui package is **not** a dependency of this one: a host that
  wants palette-entry test panels depends on it itself.

  Absent means the palette entry has no executable examples.
  """
  @callback fixtures() :: term()

  @typedoc """
  All keys optional. `icon` is a name resolved by a host-supplied
  component, never markup (ADR-0005 decision 10).
  """
  @type palette_entry :: %{
          optional(:label) => String.t(),
          optional(:group) => String.t(),
          optional(:description) => String.t(),
          optional(:icon) => String.t(),
          optional(:keywords) => [String.t()],
          optional(:order) => integer(),
          optional(:layout) => :stack | :columns,
          optional(:slot_style) => %{optional(String.t()) => :primary | :secondary | :failure},
          optional(:slot_outcome_key) => %{optional(String.t()) => String.t()}
        }

  @doc """
  Palette presentation metadata. Contents are ADR-0005's. Absent means the
  editor falls back to the type name.
  """
  @callback palette_entry() :: palette_entry()

  @optional_callbacks io: 1, migrate_config: 2, fixtures: 0, palette_entry: 0

  @doc """
  Where a field declaration's value lives, as a path from the config root.

  The declared `value_path` when there is one, and `[key]` - the default
  ADR-0002 decision 7 states - when there is not. Callers get a path
  either way and never branch on which case they are in.

  An explicitly empty `value_path` is read as no path at all rather than
  as "the config root": a field editing the whole config is not something
  decision 7 describes, and silently letting one through would let a form
  control overwrite every key the block carries.
  """
  @spec value_path(field_decl()) :: value_path()
  def value_path(%{value_path: [_first | _rest] = path}), do: path
  def value_path(%{key: key}), do: [key]

  @doc """
  The config value at `path`, or `:error` when the path does not resolve.

  `:error` is a real answer, not a failure: an arm that carries no `cond`
  yet has no value at `["arms", 0, "cond"]`, and the form renders that
  field at its default. Total over any config and any path.
  """
  @spec fetch_value(Block.json(), value_path()) :: {:ok, Block.json()} | :error
  def fetch_value(value, []), do: {:ok, value}

  def fetch_value(map, [key | rest]) when is_map(map) and is_binary(key) do
    case Map.fetch(map, key) do
      {:ok, inner} -> fetch_value(inner, rest)
      :error -> :error
    end
  end

  def fetch_value(list, [index | rest]) when is_list(list) and is_integer(index) and index >= 0 do
    case Enum.fetch(list, index) do
      {:ok, inner} -> fetch_value(inner, rest)
      :error -> :error
    end
  end

  def fetch_value(_value, _path), do: :error

  @doc """
  `config` with `path`'s value replaced, or `config` unchanged when the
  path does not lead anywhere the value could go.

  The **last** segment is written whether or not something was already
  there - an arm missing its `"cond"` is exactly the arm an author is
  about to type a condition into, and refusing that write would make the
  field permanently uneditable. Every segment before it must already
  exist: a path is a way to reach a value the block type stores, not a
  licence for a form control to invent a shape the type never wrote. A
  list index out of range writes nothing, since a list has no gap to fill.

  Only the map case needs a last-segment clause of its own. A list's does
  the same thing either way - replacing element `i` with the result of
  writing the empty path into it, which is that value - so the recursive
  clause covers a path ending at a list index too, and the empty path it
  bottoms out on addresses the config root. That is why `value_path/1`
  never returns an empty path.
  """
  @spec put_value(Block.json(), value_path(), Block.json()) :: Block.json()
  def put_value(_target, [], value), do: value

  def put_value(map, [key], value) when is_map(map) and is_binary(key),
    do: Map.put(map, key, value)

  def put_value(map, [key | rest], value) when is_map(map) and is_binary(key) do
    case Map.fetch(map, key) do
      {:ok, inner} -> Map.put(map, key, put_value(inner, rest, value))
      :error -> map
    end
  end

  def put_value(list, [index | rest], value)
      when is_list(list) and is_integer(index) and index >= 0 do
    case Enum.fetch(list, index) do
      {:ok, inner} -> List.replace_at(list, index, put_value(inner, rest, value))
      :error -> list
    end
  end

  def put_value(target, _path, _value), do: target

  # ADR-0002 decision 10's outcome names, and the shape a config key is
  # allowed to have. One regex for both, because the declaration and the
  # value it points at are the same alphabet: `outcome` names a key, the
  # key holds `abandon`, and neither is free text.
  @outcome_name ~r/\A[a-z][a-z0-9_]*\z/

  @doc """
  The config key the blocks in `slot_name` carry their outcome under, or
  `nil` when the entry declares none.

  ADR-0005 decision 10's `slot_outcome_key` (proposed there as 10f): a
  block type with a statically-named slot whose children finish the
  container in more than one way may say **where that answer lives**, so a
  consumer routes on the value without knowing which type declared it.
  `core.group` declares `%{"interrupts" => "outcome"}`; the renderer reads
  the declaration, never the type name, which is the property decision 10
  exists to preserve.

  It names a key and never a value, for `icon`'s reason: an entry carrying
  the outcome itself would be one declaration per slot for a fact that is
  per **block**, and the container does not know its children's config.
  Which outcome a given slot's completion reaches stays undeclared -
  ADR-0002's amendment A2 parks that deliberately, and this is not it.

  Total, under ADR-0002 amendment B3's refuse-do-not-truncate discipline: a
  missing declaration, a non-map, a slot the map does not name, a
  non-binary key, and a key outside `#{inspect(@outcome_name)}` all read as
  `nil`, which means the uniform rendering every consumer did before the
  declaration existed. Nothing here raises and nothing is repaired into
  something almost right.
  """
  @spec slot_outcome_key(palette_entry() | map(), Block.slot_name()) :: String.t() | nil
  def slot_outcome_key(entry, slot_name) when is_map(entry) and is_binary(slot_name) do
    with declared when is_map(declared) <- Map.get(entry, :slot_outcome_key),
         key when is_binary(key) <- Map.get(declared, slot_name),
         true <- Regex.match?(@outcome_name, key) do
      key
    else
      _refused -> nil
    end
  end

  def slot_outcome_key(_entry, _slot_name), do: nil

  @doc """
  The outcome `config` declares at `key`, or `nil`.

  The other half of `slot_outcome_key/2`: the container says where to look,
  this reads it out of one block's config. The value is an outcome name in
  ADR-0002 amendment A1's alphabet, so a config that holds something else
  there - a number, a sentence, a key that was never filled in - reads as
  no declared outcome rather than as a route nobody can render. `nil` for
  `key` is the no-declaration case, so a caller threads the pair without
  branching on it.
  """
  @spec outcome_name(Block.config(), String.t() | nil) :: String.t() | nil
  def outcome_name(config, key) when is_map(config) and is_binary(key) do
    case Map.get(config, key) do
      value when is_binary(value) ->
        if Regex.match?(@outcome_name, value), do: value

      _refused ->
        nil
    end
  end

  def outcome_name(_config, _key), do: nil
end
