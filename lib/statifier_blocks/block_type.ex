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
  `StatifierBlocks.BlockType` and fails to compile as one. Five are
  optional (`@optional_callbacks io: 1, migrate_config: 2, fixtures: 0,
  palette_entry: 0, outcomes: 1`); a module that implements only the five
  required ones compiles cleanly, and each optional absence degrades to a
  stated default rather than an error:

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
  | `outcomes/1` | no | the block has one outcome, `{"done", "Done"}` |

  ## Who owns what

  This record fixes the callback surface: names, arities, and where a
  callback lives. It does not fix the shape of every return value - some
  of those are owned by later records:

  | Callback | Shape owned by |
  |---|---|
  | `io/1` | ADR-0003 (assignability) |
  | `emit/2` | ADR-0004 (compiler provenance) |
  | `palette_entry/0` | ADR-0005 (LiveView editor) |
  | `outcomes/1` | this record's amendment A; the emission is ADR-0004's |

  ## Declaring the defaults instead of spelling them (ADR-0007)

  `use StatifierBlocks.BlockType` declares the behaviour and injects the
  answer a type gives when it has nothing of its own to say - no slots, no
  fields, nothing to refuse, version 1, unconstrained assignability, and
  no migration. Each injected callback is `defoverridable`, so a type
  writes only the rows where it differs:

      defmodule MyApp.Blocks.Beep do
        use StatifierBlocks.BlockType

        @impl true
        def config_schema(_config), do: [%{key: "note", type: :string, label: "Note",
                                           required?: false, default: ""}]

        @impl true
        def emit(_block, context), do: {:ok, StatifierBlocks.Core.Emit.final(context.state_id)}
      end

  `emit/2` is deliberately **not** among them. There is no emission a type
  can default to, and one injected here would let a type that forgot to
  compile anything look complete instead of failing to.

  The defaults change nothing this record decides. They are ordinary
  function definitions, each a pure function of its arguments, so decision
  4 holds for a `use`-ing type exactly as it does for a hand-written one,
  and a type that writes all nine callbacks out by hand is the same type it
  was before ADR-0007 existed.
  """

  alias StatifierBlocks.Block

  @doc """
  Declares the behaviour and injects the overridable defaults ADR-0007
  decision 1 names. See the moduledoc section above for what they are and
  why `emit/2` is not one of them.
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour StatifierBlocks.BlockType

      @impl StatifierBlocks.BlockType
      def slots(_config), do: []

      @impl StatifierBlocks.BlockType
      def config_schema(_config), do: []

      @impl StatifierBlocks.BlockType
      def validate_config(_config), do: :ok

      @impl StatifierBlocks.BlockType
      def current_version, do: 1

      # `%{}` is exactly what an absent `io/1` means (ADR-0003): every key
      # of the return is optional, so an empty map constrains nothing. It
      # is injected rather than left absent so that a type widening one key
      # overrides a function instead of remembering the callback exists.
      @impl StatifierBlocks.BlockType
      def io(_config), do: %{}

      # Not `{:ok, config}`. A type at `current_version` 1 has no older
      # shape to migrate from, so every `from` reaching here names a
      # version this module has never had - and answering an unknown old
      # shape with "it is already current" is how a document from the
      # future compiles as though it were understood (ADR-0002 decision 8).
      @impl StatifierBlocks.BlockType
      def migrate_config(from, _config), do: {:error, {:no_migration_from, from}}

      defoverridable slots: 1,
                     config_schema: 1,
                     validate_config: 1,
                     current_version: 0,
                     io: 1,
                     migrate_config: 2
    end
  end

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
          optional(:value_path) => value_path(),
          optional(:datamodel_path?) => boolean()
        }

  @typedoc "Names the offending config key; message is author-facing."
  @type finding :: {key :: String.t(), message :: String.t()}

  @typedoc """
  One declared outcome: the name the compiled event carries, and human
  text on the same footing as a slot declaration's label (ADR-0002
  amendment A1).

  Names match `~r/\\A[a-z][a-z0-9_]*\\z/` and contain no `"__"` - the role
  shape ADR-0004 decision 3 mints ids under, checked by
  `StatifierBlocks.Compiler.StateId.role?/1`.
  """
  @type outcome_decl :: {name :: String.t(), label :: String.t()}

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

  ## What a field's value means

  A declaration may also carry the optional `datamodel_path?: true`,
  declaring that the field's value is a path into the host's datamodel
  (ADR-0002 decision 7, amended 2026-08-29). It is orthogonal to
  `value_path`: one says where the value lives, the other says what the
  value means, and a field may carry both, either, or neither.

  It is a claim, not a rule. `validate_config/1` remains the authority on
  validity, and the annotation buys exactly one thing: the editor checks
  the value against a host-supplied datamodel and anchors an `:info`
  advisory on the field's `key` when the path is not declared (ADR-0005
  amendment 11e-11g, implemented in `StatifierBlocks.Datamodel`). With no
  datamodel supplied nothing is produced, so a declaration carrying the
  key behaves exactly as one without it until a host opts in.

  Read it through `datamodel_path?/1`, never by matching the key: a
  declaration that omits it is the common case.
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
  What `join_label` declares: a one-argument function of the block's
  config (ADR-0002 amendment B2).

  It is the first executable thing to hang off a palette entry, so
  decision 4's purity rule applies to it in full - no process dictionary,
  no application-configuration lookup, no IO, no clock, no randomness.
  A captured
  named function (`&MyApp.Blocks.Split.join_label/1`) is the form to
  prefer over an anonymous closure, for exactly that reason: a closure
  over host state at registration time is the impurity decision 4
  forbids, wearing a shape the type system cannot tell apart from a pure
  one.
  """
  @type join_label :: (Block.config() -> String.t())

  @typedoc """
  All keys optional. `icon` is a name resolved by a host-supplied
  component, never markup (ADR-0005 decision 10).

  `accent_token`, `badge` and `join_label` are ADR-0002 amendment B's
  presentation trio, whose contents stay ADR-0005 decision 10's (B1). The
  first two are inert data and the third is code (B2); all three are read
  through a total normalizer with refuse-never-truncate semantics (B3) -
  `badge/1` and `join_label/2` here, `StatifierBlocks.ViewModel.accent_token/1`
  for the one whose value is interpolated into a style attribute.
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
          optional(:slot_outcome_key) => %{optional(String.t()) => String.t()},
          optional(:accent_token) => String.t(),
          optional(:badge) => String.t(),
          optional(:join_label) => join_label()
        }

  @doc """
  Palette presentation metadata. Contents are ADR-0005's. Absent means the
  editor falls back to the type name.
  """
  @callback palette_entry() :: palette_entry()

  @doc """
  The ways this block can finish, in a fixed order (ADR-0002 amendment A1).

  A type that does not export it has exactly one outcome, `{"done",
  "Done"}`, which is the case every accepted `core.*` type is in and none
  of them changes meaning. `outcomes/2`'s doc on this module is the
  resolver every consumer reads it through.

  It takes `config` for decision 5's reason: a type whose alternative
  paths are config-parameterized declares one outcome per arm, the same
  shape `slots/1` and `config_schema/1` already have.

  **Order is declaration order and is never sorted.** ADR-0004 decision
  6's byte determinism reads it: outcomes serialize in the order this
  callback returns them, so reordering the list moves compiled bytes.

  Stability rule (decision 6, and decision 4's purity): `outcomes/1` is a
  pure function of `config`, returns the same list for the same config,
  and returns without raising for any config `validate_config/1` accepts -
  the editor calls it mid-edit and the compiler calls it against config
  the type has already accepted.

  A name failing the role shape, or declared twice, is an
  `:invalid_outcome` Emit finding against this block (ADR-0004's
  amendment, 2f), not a raise.
  """
  @callback outcomes(Block.config()) :: [outcome_decl()]

  @typedoc """
  What a block type says about one block's config on the card's second
  line (ADR-0002 amendment H1).

  `nil` is no second line and is what a type that exports no `summary/1`
  means. A string is one summary line. A list of strings is a **chip
  list**, each entry read as one chip.

  Every shape reaches consumers as a chip list through `summary/2`, so
  nothing downstream branches on which one a type chose.
  """
  @type summary :: nil | String.t() | [String.t()]

  @doc """
  What this block's card says under its title, given this config
  (ADR-0002 amendment H1).

  Optional. A type that does not export it has no summary, which is the
  card every block type had before the callback existed, and it is the
  case eight of the thirteen `core.*` types are in.

  It exists so the editor can draw a per-type second line without ever
  naming a type: ADR-0005 decision 2 has the editor work off the
  caller-supplied palette, so a host type that declares a summary gets
  the same card face `core.wait` gets.

  The three rules `slots/1` and `config_schema/1` already carry apply
  unchanged. It is a **pure function of `config`**, it is **total** - the
  editor calls it mid-edit, so it answers for config `validate_config/1`
  rejects - and it **never raises**. A callback that raises anyway
  degrades to no summary rather than taking the canvas down (amendment
  H4), the bounded exception `join_label/2` already documents.

  Each chip is a presentation string, so amendment B3's refusal set
  governs it: an over-long chip is **dropped, not clipped**. See
  `summary/2`, which is the resolver every consumer reads it through.
  """
  @callback summary(Block.config()) :: summary()

  @optional_callbacks io: 1,
                      migrate_config: 2,
                      fixtures: 0,
                      palette_entry: 0,
                      outcomes: 1,
                      summary: 1

  # ADR-0002 amendment A1's default: a type that declares no outcomes has
  # exactly one, named `done`. Named once, here, so the compiler and the
  # editor cannot disagree about what a defaulting type declares.
  @default_outcomes [{"done", "Done"}]

  @doc """
  `module.outcomes(config)`, or `#{inspect(@default_outcomes)}` when
  `outcomes/1` is absent or `module` is not loadable (ADR-0002 amendment
  A1). Checked with `Code.ensure_loaded?/1` plus `function_exported?/3`,
  the pattern `StatifierBlocks.Palette.resolve/2` already uses.

  The list comes back in **declaration order**, never sorted: ADR-0004
  decision 6's byte determinism reads that order, and a resolver that
  tidied it would move a host's compiled bytes for no reason it could
  name.
  """
  @spec outcomes(module(), Block.config()) :: [outcome_decl()]
  def outcomes(module, config) do
    if Code.ensure_loaded?(module) and function_exported?(module, :outcomes, 1) do
      module.outcomes(config)
    else
      @default_outcomes
    end
  end

  @doc """
  The names `outcomes/2` declares, in declaration order.

  What the compiler mints ids and events from; the labels are the
  editor's.

  Total over any return value, including one the `t:outcome_decl/0` spec
  does not describe: a declaration that is not a `{name, label}` pair with
  a binary name comes back as its `inspect/1` rendering, which no role
  shape matches, so a host type that declares nonsense gets the ordinary
  `:invalid_outcome` finding naming what it wrote rather than a crash
  inside the compiler.
  """
  @spec outcome_names(module(), Block.config()) :: [String.t()]
  def outcome_names(module, config) do
    module
    |> outcomes(config)
    |> Enum.map(&outcome_name/1)
  end

  @spec outcome_name(term()) :: String.t()
  defp outcome_name({name, _label}) when is_binary(name), do: name
  defp outcome_name(malformed), do: inspect(malformed)

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
  Whether a field declaration says its value is a datamodel path
  (ADR-0002 decision 7's optional `datamodel_path?` key, amended
  2026-08-29).

  Total, and true only for the literal `true` that the amendment admits.
  Absence means what it meant before the key existed, and any other value
  - a string, `nil`, a map - reads as absence rather than as truthiness,
  on the same normalizer discipline `value_path/1` and
  `StatifierBlocks.ViewModel.accent_token/1` are under: a typo in a host's
  registry degrades to the behaviour that predates the key.

      iex> StatifierBlocks.BlockType.datamodel_path?(%{key: "path", datamodel_path?: true})
      true

      iex> StatifierBlocks.BlockType.datamodel_path?(%{key: "path"})
      false

      iex> StatifierBlocks.BlockType.datamodel_path?(%{key: "path", datamodel_path?: "yes"})
      false
  """
  @spec datamodel_path?(field_decl()) :: boolean()
  def datamodel_path?(%{datamodel_path?: true}), do: true
  def datamodel_path?(_decl), do: false

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

  # ADR-0002 amendment B3 leaves the badge and join-marker length cap to
  # ADR-0005 decision 10 and notes the spike's number, chosen so that
  # "calls the host" and "timer" fit and a sentence does not. Decision 10
  # carries no number today, so it lives here, named once, and this is the
  # value proposed to that record rather than a second opinion about it.
  @presentation_cap 24

  @doc """
  The chip a palette entry declares for its block type's card header, or
  `nil` when it declared none or declared one this package will not draw
  (ADR-0002 amendment B's `badge`).

  Total, under B3's refuse-do-not-truncate discipline. Refused: a
  non-string, an empty or all-whitespace string, one carrying a newline,
  carriage return or tab, and one longer than #{@presentation_cap}
  characters. An over-long badge is **dropped, not clipped**, and one
  carrying a newline is dropped rather than collapsed to a space: a
  truncated chip reads as a rendering bug a host files against the editor,
  where a missing chip reads as the declaration it is.

  `nil` means no chip, which is the card every block type had before the
  declaration existed. A malformed declaration in one host's registry
  produces the ordinary card, never a broken one and never an exception -
  decision 3's totality, arriving at presentation.

      iex> StatifierBlocks.BlockType.badge(%{badge: "calls the host"})
      "calls the host"

      iex> StatifierBlocks.BlockType.badge(%{badge: "a chip that says altogether too much"})
      nil

      iex> StatifierBlocks.BlockType.badge(%{})
      nil
  """
  @spec badge(palette_entry() | map()) :: String.t() | nil
  def badge(entry) when is_map(entry), do: chip(Map.get(entry, :badge))
  def badge(_entry), do: nil

  @doc """
  What the join marker under this block type's side-by-side arrangement
  says for `config`, or `nil` when the entry declares none and the editor
  should use its own word (ADR-0002 amendment B's `join_label`).

  The declaration is a one-argument function of the block's config -
  `t:join_label/0` - and it is host code on the editor's layout path, so
  two rules from amendment B2 and B3 apply and are implemented here:

    * **It is a pure function of its argument.** That is decision 4, and
      it is enforced by convention rather than by the gate, exactly as it
      is for every other callback. A host needing external data to phrase
      a marker resolves it before the operation and threads it through
      config.
    * **A raise degrades to the default.** The call happens inside a
      rescue, so a host type with a bug in its `join_label` gets an
      ordinary join marker rather than taking the canvas down. A throw and
      an exit are caught on the same grounds - B3's own heading names the
      throw. This is a deliberate, bounded exception to this package's
      "nothing rescued to a default" rule: the value being defaulted is
      one word of chrome and the alternative is a blank editor.
      `validate_config/1`, `slots/1`, `emit/2` and every other callback
      keep the rule unweakened.

  The **return** is then held to `badge/1`'s refusal set, so a callback
  that answers with a sentence, a newline, or something that is not a
  string at all reads as no declaration rather than as a broken marker.
  A declaration that is not a one-argument function is refused without
  being called.

      iex> StatifierBlocks.BlockType.join_label(%{join_label: fn _config -> "all lanes" end}, %{})
      "all lanes"

      iex> StatifierBlocks.BlockType.join_label(%{join_label: fn _config -> raise "boom" end}, %{})
      nil

      iex> StatifierBlocks.BlockType.join_label(%{join_label: "not a function"}, %{})
      nil
  """
  @spec join_label(palette_entry() | map(), Block.config()) :: String.t() | nil
  def join_label(entry, config) when is_map(entry) do
    case Map.get(entry, :join_label) do
      declared when is_function(declared, 1) -> declared |> call_join_label(config) |> chip()
      _refused -> nil
    end
  end

  def join_label(_entry, _config), do: nil

  @doc """
  The chips `module.summary(config)` declares, or `[]` (ADR-0002
  amendment H2).

  The one shape every consumer reads: a possibly-empty list of chips. A
  `nil`, a module that does not export `summary/1`, and a module that is
  not loadable all come back `[]`; a string comes back as a one-element
  list; a list comes back filtered. Absence is checked with
  `Code.ensure_loaded?/1` plus `function_exported?/3`, the pattern
  `outcomes/2` already uses.

  Each chip is held to `badge/1`'s refusal set, unchanged: a non-string,
  an empty or all-whitespace string, one carrying a newline, carriage
  return or tab, and one longer than #{@presentation_cap} characters are
  **refused, never truncated** (amendment H3). A refused chip is dropped
  and its siblings survive, so one over-long lane name costs its own chip
  and nothing else. A summary whose every chip is refused is `[]`, which
  is the card that type had before it declared one.

  A callback that raises, throws or exits answers `[]` on the grounds
  `join_label/2` documents: this is host code on the editor's layout
  path, and the value being defaulted is one line of chrome.

      iex> StatifierBlocks.BlockType.summary(StatifierBlocks.Core.Send, %{"event" => "order.paid"})
      ["order.paid"]

      iex> StatifierBlocks.BlockType.summary(StatifierBlocks.Core.Sequence, %{})
      []

      iex> StatifierBlocks.BlockType.summary(NoSuchModule, %{})
      []
  """
  @spec summary(module(), Block.config()) :: [String.t()]
  def summary(module, config) do
    module
    |> declared_chips(config)
    |> Enum.map(&chip/1)
    |> Enum.reject(&is_nil/1)
  end

  @typedoc """
  Why one declared summary chip is not drawn, in the vocabulary of
  ADR-0002 amendment B3's refusal set as `chip/1` applies it.

  `:not_a_string` is anything that is not a binary, `:blank` an empty or
  all-whitespace string, `:multiline` one carrying a newline, carriage
  return or tab, and `:too_long` one past `#{@presentation_cap}`
  characters. The order is `chip/1`'s own: a string that is both
  newline-carrying and over-long reads as `:multiline`, because that is
  the arm that refused it.
  """
  @type summary_refusal_reason :: :too_long | :blank | :multiline | :not_a_string

  @doc """
  The chips `summary/2` dropped, as `{index, reason}` in declaration order.

  ADR-0005 decision 10's 2026-08-30 Note, "the cap signals". Refusing a
  chip removes the evidence that anything was declared, so the card of a
  block whose lane name is one character too long is indistinguishable
  from the card of a block that declared no lane at all. This is the
  reader that says which - the editor turns each entry into a `:lint`
  warning against the block (`StatifierBlocks.ViewModel`), and nothing
  about the card, the cap or `summary/2` moves to make that possible.

  `index` is the zero-based position in the list the type declared, so it
  survives a refusal in front of it - `summary/2`'s output has already
  closed the gap and cannot be indexed against. Total for the same
  reasons `summary/2` is: a type that exports no `summary/1`, a module
  that does not exist, and a callback that raises all answer `[]`, which
  is "nothing was refused" and is honest in each case.

      iex> StatifierBlocks.BlockType.summary_refusals(StatifierBlocks.Core.Parallel, %{"lanes" => ["capture", "balance_check_and_fraud_review"]})
      [{1, :too_long}]

      iex> StatifierBlocks.BlockType.summary_refusals(StatifierBlocks.Core.Wait, %{"duration" => "30s"})
      []

      iex> StatifierBlocks.BlockType.summary_refusals(NoSuchModule, %{})
      []
  """
  @spec summary_refusals(module(), Block.config()) ::
          [{non_neg_integer(), summary_refusal_reason()}]
  def summary_refusals(module, config) do
    module
    |> declared_chips(config)
    |> Enum.with_index()
    |> Enum.flat_map(fn {declared, index} ->
      case chip_refusal(declared) do
        nil -> []
        reason -> [{index, reason}]
      end
    end)
  end

  @doc """
  What one `summary_refusals/2` entry says to an author, in the words a
  `:lint` finding carries.

  The message names the chip's position, its length and the cap, because
  those are the three facts an author needs to fix the declaration and
  none of them is visible on a card that simply drew nothing. Position is
  one-based here and zero-based in the tuple: the tuple indexes a list and
  the sentence counts chips.

  The cap lives in this module (ADR-0002 amendment H's Consequences: one
  number in one place), so the sentence is built here rather than by the
  editor.
  Total: an entry naming a position the type no longer declares still
  answers a sentence.

      iex> StatifierBlocks.BlockType.summary_refusal_message(StatifierBlocks.Core.Parallel, %{"lanes" => ["capture", "balance_check_and_fraud_review"]}, {1, :too_long})
      "summary chip 2 is 30 characters; the cap is 24, so it is not drawn"
  """
  @spec summary_refusal_message(
          module(),
          Block.config(),
          {non_neg_integer(), summary_refusal_reason()}
        ) :: String.t()
  def summary_refusal_message(module, config, {index, reason}) do
    module
    |> declared_chips(config)
    |> Enum.at(index)
    |> refusal_message(index, reason)
  end

  @spec refusal_message(term(), non_neg_integer(), summary_refusal_reason()) :: String.t()
  defp refusal_message(declared, index, :too_long) when is_binary(declared) do
    "summary chip #{index + 1} is #{String.length(declared)} characters; " <>
      "the cap is #{@presentation_cap}, so it is not drawn"
  end

  defp refusal_message(_declared, index, :too_long) do
    "summary chip #{index + 1} is longer than the cap of #{@presentation_cap} " <>
      "characters, so it is not drawn"
  end

  defp refusal_message(_declared, index, :blank),
    do: "summary chip #{index + 1} is blank, so it is not drawn"

  defp refusal_message(_declared, index, :multiline),
    do: "summary chip #{index + 1} carries a line break or a tab, so it is not drawn"

  defp refusal_message(_declared, index, :not_a_string),
    do: "summary chip #{index + 1} is not a string, so it is not drawn"

  # The one declaration pass `summary/2` and `summary_refusals/2` share, so
  # the chips that are drawn and the chips that are refused can never be
  # computed from two different readings of the same callback.
  @spec declared_chips(module(), Block.config()) :: [term()]
  defp declared_chips(module, config) do
    if Code.ensure_loaded?(module) and function_exported?(module, :summary, 1) do
      module
      |> call_summary(config)
      |> List.wrap()
    else
      []
    end
  end

  # H4's degradation, on the same grounds and with the same shape as
  # `call_join_label/2`: the rescued value is never inspected, because
  # what comes back is the ordinary card either way.
  @spec call_summary(module(), Block.config()) :: term()
  defp call_summary(module, config) do
    module.summary(config)
  rescue
    _raised -> []
  catch
    :throw, _thrown -> []
    :exit, _reason -> []
  end

  # B3's "a callback that raises degrades to the default", widened to a
  # throw and an exit because a host callback that does either leaves the
  # layout pass in the same place a raise does. The rescued value is never
  # inspected: what comes back is the editor's own word either way.
  @spec call_join_label(join_label(), Block.config()) :: term()
  defp call_join_label(declared, config) do
    declared.(config)
  rescue
    _raised -> nil
  catch
    :throw, _thrown -> nil
    :exit, _reason -> nil
  end

  # The one refusal set B3's badge row and join-marker row share. Refuse,
  # never truncate, and never repair: every arm answers `nil`, which every
  # caller already renders as the default it owns.
  @spec chip(term()) :: String.t() | nil
  defp chip(text) do
    case chip_refusal(text) do
      nil -> text
      _refused -> nil
    end
  end

  # The same refusal set, answering *which* arm refused rather than only
  # that one did. `chip/1` is defined in terms of it so the drawn chip and
  # the reported refusal cannot disagree, and the arm order is the one B3's
  # table reads in.
  @spec chip_refusal(term()) :: summary_refusal_reason() | nil
  defp chip_refusal(text) when is_binary(text) do
    cond do
      String.trim(text) == "" -> :blank
      String.contains?(text, ["\n", "\r", "\t"]) -> :multiline
      String.length(text) > @presentation_cap -> :too_long
      true -> nil
    end
  end

  defp chip_refusal(_refused), do: :not_a_string
end
