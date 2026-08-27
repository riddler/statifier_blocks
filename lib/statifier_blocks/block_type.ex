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

  @type field_decl :: %{
          key: String.t(),
          type: field_type(),
          label: String.t(),
          required?: boolean(),
          default: Block.json()
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

  @doc """
  Emits this block's SCXML subtree. `context` and the return term's real
  shape are ADR-0004's; this record fixes only that the callback lives
  here and is pure.
  """
  @callback emit(Block.t(), context :: term()) :: {:ok, term()} | {:error, term()}

  @doc """
  Type expressions for assignability. The return shape is
  `StatifierBlocks.Assignability.io/0` (ADR-0003). Absent means
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
    * `"palette/score.fixtures.json"` - a binary path

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

  @doc """
  Palette presentation metadata. Contents are ADR-0005's. Absent means the
  editor falls back to the type name.
  """
  @callback palette_entry() :: map()

  @optional_callbacks io: 1, migrate_config: 2, fixtures: 0, palette_entry: 0
end
