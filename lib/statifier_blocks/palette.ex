defmodule StatifierBlocks.Palette do
  @moduledoc """
  A palette names the block types a host makes available: a map from a
  block's `type_name` to the module implementing `StatifierBlocks.BlockType`
  for it (ADR-0002 decision 2).

  It is a **caller-supplied value**, nothing more. A palette is built once
  for an editing or compiling operation and passed explicitly into whatever
  needs it - document validation, the editor's session state, the compiler -
  the same way any other value is threaded through a pipeline. Nothing in
  this package holds a palette across operations, and no cadence beyond "one
  value per operation" is implied: a caller that wants the same set of types
  for its next operation builds (or reuses) the value again, deliberately.

  It is explicitly **not**:

    * an application-configuration lookup keyed by block type
    * a table of shared entries reachable by name from anywhere in the
      process tree
    * a lookup registered under a well-known process name
    * anything wired up automatically when this package (or a host
      application) starts

  Any of those would make two hosts sharing one runtime step on each
  other's block types - the multi-tenant property this design exists to
  keep. Two `StatifierBlocks.Palette` values built with different modules
  under the same `type_name` in the same running system resolve
  independently; neither can see or clobber the other.

  Every consumer that walks a document and resolves blocks against a
  palette carries the case where a block's `type_name` has no entry as an
  ordinary pattern-matched arm, not as an exception - `fetch/2` never
  raises, so there is nothing to rescue.
  """

  alias StatifierBlocks.{Block, Core}

  @type t :: %__MODULE__{
          types: %{optional(Block.type_name()) => module()},
          assignability: module() | nil
        }

  defstruct types: %{}, assignability: nil

  @doc """
  Builds a palette from a `type_name => module` map. Defaults to an empty
  palette.

  Options: `:assignability`, a module implementing
  `StatifierBlocks.Assignability.Relation` (ADR-0003 decision 6). Defaults
  to `nil`, meaning the palette declares no widening relation - `new(types)`
  and `new(types, assignability: nil)` are the same palette.
  """
  @spec new(%{optional(Block.type_name()) => module()}, keyword()) :: t()
  def new(types \\ %{}, opts \\ []) when is_map(types) do
    %__MODULE__{types: types, assignability: Keyword.get(opts, :assignability)}
  end

  @doc """
  The `core.*` structural vocabulary as a palette (ADR-0002 decision 10).

  The core vocabulary's entries, described in `StatifierBlocks.Core`.
  They are ordinary palette entries with no privileged path anywhere in
  this package - a palette without them is as valid as a palette with
  them, and a host that wants only some of them builds a map with only
  those.

      Palette.core()
      #=> %StatifierBlocks.Palette{types: %{"core.sequence" => ..., ...}}

  """
  @spec core() :: t()
  def core, do: new(core_types())

  @doc """
  The `type_name => module` map behind `core/0`, for a host merging the
  core vocabulary with its own entries:

      Palette.new(Map.merge(Palette.core_types(), %{"myapp.authorize" => MyApp.Blocks.Authorize}))

  A host entry sharing a name with a core one wins, because that is what
  `Map.merge/2` does and a palette is just a value: nothing in this package
  reserves the `core.` prefix, and a host deliberately swapping in its own
  `core.wait` is doing something this design allows on purpose.
  """
  @spec core_types() :: %{optional(Block.type_name()) => module()}
  def core_types do
    %{
      "core.sequence" => Core.Sequence,
      "core.group" => Core.Group,
      "core.branch" => Core.Branch,
      "core.parallel" => Core.Parallel,
      "core.wait" => Core.Wait,
      "core.resumable_group" => Core.ResumableGroup,
      "core.on_event" => Core.OnEvent,
      "core.invoke" => Core.Invoke,
      "core.raise" => Core.Raise,
      "core.assign" => Core.Assign,
      "core.send" => Core.Send,
      "core.subchart" => Core.Subchart,
      "core.foreach" => Core.Foreach
    }
  end

  @typedoc """
  One registration: the name a document uses, and the module implementing
  it. ADR-0002 decision 1 puts the string in the document and the mapping
  in the palette, so a registration carries both halves - see
  `from_modules/2` for why the name is not derived from the module.
  """
  @type registration :: {Block.type_name(), module()}

  @doc """
  Builds a palette from an **ordered, explicit list** of registrations -
  the shape a host uses to contribute its own block types.

      Palette.from_modules(
        [
          {"myapp.risk_hold", MyApp.Blocks.RiskHold},
          {"myapp.settle", MyApp.Blocks.Settle}
        ],
        core: true
      )

  This is `new/2` with the ergonomics the registration story actually
  wants, and nothing more: it is still a value, built where the editor is
  mounted and handed in explicitly. There is no global registry, no
  application-configuration lookup, and no compile- or boot-time discovery
  of modules implementing the behaviour - every reason the moduledoc gives
  for that applies here unchanged, and a discovery pass would additionally
  make two tenants in one runtime share whatever the code path happened to
  find.

  Options:

    * `:core` - when `true`, the registrations sit on top of
      `core_types/0` rather than on an empty map. Defaults to `false`, so
      `from_modules([])` is the empty palette.
    * `:assignability` - passed through to `new/2`.

  The list is ordered and **later entries win**, which is what makes it a
  list rather than a map: a host that deliberately swaps in its own
  `core.wait` writes it after `core: true` and reads the override in the
  order it happens, and the same name appearing twice in one list has an
  answer rather than a coin flip.

  ## Why a name per entry, and not a name per module

  A bare `[module]` list would be shorter, and this function does not take
  one, because nothing in `StatifierBlocks.BlockType` declares a type
  name. ADR-0002 decision 1 is explicit that the document names a type by
  string and the palette resolves the string - the mapping is the *host's*
  fact, not the module's, which is exactly what lets one module serve two
  names in two tenants' palettes. Deriving a name from a module would
  need a declaration the accepted behaviour does not have, and adding one
  is a change to that record rather than an implementation convenience.

  ## What it does not check

  It does not load the module, does not assert the behaviour, and does not
  call a callback. A palette is a value that may name a module compiled
  later, and every consumer already carries the unresolvable case as an
  ordinary arm (ADR-0002 decision 3). What it *does* refuse is an entry
  that is not a `{type_name, module}` pair at all: that is a mount-time
  programmer error with no sensible degraded reading, so it raises
  `ArgumentError` naming the offending entry rather than quietly building
  a palette missing a type the host believes it registered.
  """
  @spec from_modules([registration()], keyword()) :: t()
  def from_modules(registrations, opts \\ []) when is_list(registrations) do
    base = if Keyword.get(opts, :core, false), do: core_types(), else: %{}

    registrations
    |> Enum.reduce(base, &register/2)
    |> new(opts)
  end

  @spec register(registration(), %{optional(Block.type_name()) => module()}) ::
          %{optional(Block.type_name()) => module()}
  defp register({type_name, module}, types)
       when is_binary(type_name) and type_name != "" and is_atom(module) do
    Map.put(types, type_name, module)
  end

  defp register(entry, _types) do
    raise ArgumentError,
          "expected a {type_name, module} registration, got: #{inspect(entry)}"
  end

  @doc """
  Resolves a `type_name` to its module. Total; never raises (ADR-0002
  decision 3). `Map.fetch/2` rather than a sentinel default, so a palette
  that genuinely maps a name to `nil` stays distinguishable from a name no
  entry carries.
  """
  @spec fetch(t(), Block.type_name()) ::
          {:ok, module()}
          | {:error, {:unknown_block_type, Block.type_name()}}
  def fetch(%__MODULE__{types: types}, type_name) do
    case Map.fetch(types, type_name) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, {:unknown_block_type, type_name}}
    end
  end

  @doc """
  Resolves `block` through `palette` and, if needed, migrates its config in
  memory (ADR-0002 decision 8).

  Four distinguishable outcomes, checked in this order:

    * the block's `type` has no entry in `palette` ->
      `{:error, {:unknown_block_type, type}}`
    * `block.type_version == module.current_version()` -> `{:ok, module,
      block}`, `block` returned exactly as given
    * `block.type_version > module.current_version()` -> `{:error,
      {:block_type_too_new, block.id, block.type_version}}`. Hard error,
      never a best-effort read: the code is older than the data, and
      guessing is how a rollback corrupts documents
    * `block.type_version < module.current_version()` -> `module.migrate_config/2`
      is called once, straight from the stored version to current (never a
      version-by-version ladder). A successful migration rewrites only
      `block.config` on the returned struct; a failing one, or a module that
      does not export `migrate_config/2` at all, becomes `{:error,
      {:migration_failed, block.id, reason}}`

  The migrated config is applied to the returned struct only - `resolve/2`
  never calls `Document.to_json/1`, `from_json/1`, or anything else that
  could persist. Persisting a migration is the caller's decision. The
  returned block's `type_version` is left **as stored**, never bumped to
  `current_version()`, so the result can never be mistaken for a block that
  was migrated on disk.

  `resolve/2` takes one block, not a document - it never walks a document;
  the caller owns the walk and what to do with a per-block failure.
  """
  @spec resolve(t(), Block.t()) ::
          {:ok, module(), Block.t()}
          | {:error, {:unknown_block_type, Block.type_name()}}
          | {:error, {:block_type_too_new, Block.id(), pos_integer()}}
          | {:error, {:migration_failed, Block.id(), term()}}
  def resolve(%__MODULE__{} = palette, %Block{} = block) do
    with {:ok, module} <- fetch(palette, block.type) do
      migrate(module, block, module.current_version())
    end
  end

  @spec migrate(module(), Block.t(), pos_integer()) ::
          {:ok, module(), Block.t()}
          | {:error, {:block_type_too_new, Block.id(), pos_integer()}}
          | {:error, {:migration_failed, Block.id(), term()}}
  defp migrate(module, %Block{type_version: current} = block, current) do
    {:ok, module, block}
  end

  defp migrate(_module, %Block{type_version: stored} = block, current) when stored > current do
    {:error, {:block_type_too_new, block.id, stored}}
  end

  defp migrate(module, %Block{type_version: stored} = block, current) when stored < current do
    if Code.ensure_loaded?(module) and function_exported?(module, :migrate_config, 2) do
      case module.migrate_config(stored, block.config) do
        {:ok, config} -> {:ok, module, %{block | config: config}}
        {:error, reason} -> {:error, {:migration_failed, block.id, reason}}
      end
    else
      {:error, {:migration_failed, block.id, :no_migration_available}}
    end
  end
end
