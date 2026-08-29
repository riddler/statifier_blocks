defmodule StatifierBlocks.ViewModel do
  @moduledoc """
  Everything the editor renders, derived from `{document, palette,
  findings}` (ADR-0005 decisions 9, 10, 11, 12, 13).

  This is the load-bearing module decision 13 names: it is where
  resolution, migration, validation, and `palette_entry/0` lookup happen,
  and it produces a structure in which every block already carries its
  declared slots, its form fields, its presentation metadata, and its
  findings routed to the position that renders them. It lives outside
  `StatifierBlocks.Editor.*` despite being an editor concern, and it names
  no LiveView module - the components downstream of it are close to
  mechanical, reading a view model and emitting markup with no palette
  lookups and no callback invocations of their own.

  ## Two derived finding sources, and the compiler adapter

  `build/3`'s third argument is a caller-supplied `[StatifierBlocks.Finding.t()]`.
  This module derives exactly two sources of its own, because decision 13
  puts resolution, migration and validation inside `ViewModel` rather than
  upstream of it:

    * `:resolution` - `Palette.resolve/2` failing on a block
      (`:unknown_block_type`, `:block_type_too_new`, `:migration_failed`),
      anchored `{:block, id}`, severity `:error`.
    * `:config` - `validate_config/1` on a resolved block, one per
      `{key, message}` pair, anchored `{:config, id, key}`, severity
      `:error`.

  `:arity`, `:assignability` and `:lint` findings are never produced here;
  their producers live elsewhere - `StatifierBlocks.SlotValidation`
  (palette-aware slot arity and undeclared-slot checks; landed under `sb-da9`,
  was described here as "not yet built"), `Assignability.validate/3`, and
  the compiler's invoke-type lint respectively - and this module does not
  adapt `StatifierBlocks.Compiler.Finding` into `StatifierBlocks.Finding`
  to manufacture them. That adapter is a real, mechanical possibility
  (`Compiler.Finding` carries `block_id` and `config_key`, which map onto
  `{:config, id, key}` / `{:block, id}` cleanly), and it landed instead as
  `StatifierBlocks.Finding.from_compiler/2` (`sb-kmk`) - `ViewModel` still
  derives no findings from it; callers adapt compiler findings themselves
  and pass the result to `build/3` as caller-supplied findings. Derived
  and caller-supplied findings are concatenated - derived first - into one
  list, which is both `t().findings` and the document-level panel's source.

  ## Routing, and the case that must not vanish

  Each finding in the concatenated list is placed by its anchor:

  | Anchor | Position in the view model |
  |---|---|
  | any anchor naming a block id not in the document | `t().orphan_findings` |
  | `{:block, id}` | that node's `findings` |
  | `{:slot, id, name}` | that slot's `findings` (a slot name the node does not carry falls back to the node's `findings`) |
  | `{:config, id, key}`, `key` matches a `config_schema/1` field | that field's `findings` |
  | `{:config, id, key}`, `key` matches **no** field | that node's `form.unrouted` |

  The fourth row exists because `Core.Branch.config_schema/1` keys one
  field per arm by the arm's own slot name, but `validate_config/1` also
  emits findings keyed `"arms"` - a key that matches no field, because
  adding or removing an arm is a document edit, not a form value
  (`core/branch.ex`). `form.unrouted` is rendered at the head of the
  config form for exactly this case, and an unresolvable node - which has
  no form at all - folds the same case into its own `findings` instead of
  discarding it.

  No route drops a finding: every arm of the table above lands somewhere,
  and `t().findings_count` accumulates the same placements. A node's
  `findings_count` covers its whole subtree - its own findings, its slots'
  findings, its form's field and unrouted findings, plus every child's own
  `findings_count` - so a collapsed subtree can carry a count badge
  (decision 11's last sentence) without walking back down into it.

  ## d10's defaults

  `palette_entry/0` is optional, and every one of its keys has a
  default (decision 10) so a block type that implements none of it still
  renders: `label` defaults to the type name, `group` to `"Other"`,
  `description` to `""`, `icon` to `nil`, `keywords` to `[]`, `order` to
  `0`, `layout` to `:stack`, `slot_style` to `%{}`, and `slot_outcome_key`
  (decision 10's proposed 10f) to `%{}`.

  ## d10's outcome declaration

  A container whose statically-named slot holds blocks that finish it in
  more than one way may declare, per slot, the config key those blocks
  carry the answer under - `core.group` says
  `slot_outcome_key: %{"interrupts" => "outcome"}`. Two things come out of
  it here, both read through `BlockType`'s total normalizers: the slot
  carries the declared key as `Slot.outcome_key`, and every child in that
  slot carries the resolved value as `Node.outcome`. A malformed
  declaration, or a child whose config holds no well-formed outcome name,
  is `nil` in both places - the uniform rendering, never a broken one
  (ADR-0002 amendment B3).

  ## d12: unresolvable nodes

  A block whose type does not resolve renders with its type name, a
  `status: {:unresolvable, reason}` carrying `Palette.resolve/2`'s own
  error term, `form: nil`, its config as canonical-JSON text in
  `raw_config_json` (there is no `config_schema/1` to drive a form and
  inventing one would be guessing), a `:resolution` finding, and **its
  existing children rendered normally, recursively** with raw slot names -
  the document's `slots` map preserved every one of them, decoding never
  having consulted a registry.

  ## d9: the form is a projection, never cached

  A resolved node's `form.fields` come from `module.config_schema/1`
  called against the block's **current** config, every time `build/3`
  runs. Nothing here memoizes a schema across an edit: a branch that gains
  an arm gains a field the very next time `build/3` is called, because the
  schema is a function of config (ADR-0002 decision 7), not a cache of one.
  """

  alias StatifierBlocks.{Block, BlockType, CanonicalJson, Document, Finding, Palette}

  defmodule Field do
    @moduledoc """
    One config field, its schema and its current value (ADR-0005 decision 9).

    `key` is the field's identity - the DOM id, the form param name, and
    what a `{:config, id, key}` finding anchors to. `value_path` is where
    the bytes live, and the two are the same place unless the block type
    said otherwise (ADR-0002 decision 7, amended 2026-08-27). `nil` means
    it did not; read it through `value_path/1` rather than the struct
    field, and the two cases collapse into one path.
    """

    @type t :: %__MODULE__{
            key: String.t(),
            type: BlockType.field_type(),
            label: String.t(),
            required?: boolean(),
            default: Block.json(),
            value: Block.json(),
            value_path: BlockType.value_path() | nil,
            findings: [Finding.t()]
          }

    @enforce_keys [:key, :type, :label, :required?, :default, :value]
    defstruct [:key, :type, :label, :required?, :default, :value, :value_path, findings: []]

    @doc "Where this field's value lives, defaulting to `[key]`."
    @spec value_path(t()) :: BlockType.value_path()
    def value_path(%__MODULE__{value_path: [_first | _rest] = path}), do: path
    def value_path(%__MODULE__{key: key}), do: [key]
  end

  defmodule Form do
    @moduledoc """
    A resolved node's config form: its fields, plus any `:config` finding
    whose key matched no field (ADR-0005 decision 11's fourth routing row).
    """

    @type t :: %__MODULE__{fields: [Field.t()], unrouted: [Finding.t()]}

    defstruct fields: [], unrouted: []
  end

  defmodule Slot do
    @moduledoc """
    One named slot: declared or raw, with its children and its own findings.

    `outcome_key` is the container's `slot_outcome_key` declaration for
    this slot, normalized (ADR-0005 decision 10, proposed 10f) - the config
    key each child in this slot carries its outcome under, or `nil` when
    the type declared none. It is here as well as on the children so that a
    consumer can ask the question of the slot without walking into it.
    """

    @type t :: %__MODULE__{
            name: Block.slot_name(),
            label: String.t(),
            arity: BlockType.slot_arity() | nil,
            style: :primary | :secondary | :failure,
            declared?: boolean(),
            outcome_key: String.t() | nil,
            children: [StatifierBlocks.ViewModel.Node.t()],
            findings: [Finding.t()]
          }

    @enforce_keys [:name, :label, :declared?]
    defstruct [
      :name,
      :label,
      arity: nil,
      style: :primary,
      declared?: true,
      outcome_key: nil,
      children: [],
      findings: []
    ]
  end

  defmodule Node do
    @moduledoc """
    One block, rendered: its resolved status, its presentation metadata,
    its slots (recursive), its form, and its own findings.

    `outcome` is the outcome this block produces for the slot it sits in,
    when the **parent's** type declared a `slot_outcome_key` for that slot
    and this block's config holds a well-formed outcome name there; `nil`
    otherwise, which is every block whose parent declared nothing. It is
    resolved here rather than by a consumer so that the picture-drawing
    side reads one field instead of a metadata key plus a config lookup,
    and so it never learns that `core.on_event` is the type with an
    `outcome`.
    """

    @type status :: :ok | {:unresolvable, term()}

    @type t :: %__MODULE__{
            block_id: Block.id(),
            type: Block.type_name(),
            type_version: pos_integer(),
            status: status(),
            entry: BlockType.palette_entry(),
            outcome: String.t() | nil,
            slots: [StatifierBlocks.ViewModel.Slot.t()],
            form: StatifierBlocks.ViewModel.Form.t() | nil,
            raw_config_json: String.t() | nil,
            findings: [Finding.t()],
            findings_count: non_neg_integer()
          }

    @enforce_keys [:block_id, :type, :type_version, :status]
    defstruct [
      :block_id,
      :type,
      :type_version,
      :status,
      entry: %{},
      outcome: nil,
      slots: [],
      form: nil,
      raw_config_json: nil,
      findings: [],
      findings_count: 0
    ]
  end

  defmodule PaletteGroup do
    @moduledoc """
    One palette section: types sharing `entry.group`, sorted by
    `entry.order` then `entry.label` (ADR-0005 decision 10's grouping
    rule).
    """

    @type entry :: %{
            type_name: Block.type_name(),
            module: module(),
            entry: BlockType.palette_entry()
          }

    @type t :: %__MODULE__{name: String.t(), entries: [entry()]}

    @enforce_keys [:name]
    defstruct [:name, entries: []]
  end

  @type t :: %__MODULE__{
          document_id: Document.id(),
          revision: non_neg_integer(),
          root: Node.t(),
          palette_groups: [PaletteGroup.t()],
          findings: [Finding.t()],
          orphan_findings: [Finding.t()]
        }

  @enforce_keys [:document_id, :revision, :root]
  defstruct [
    :document_id,
    :revision,
    :root,
    palette_groups: [],
    findings: [],
    orphan_findings: []
  ]

  @default_entry %{
    group: "Other",
    description: "",
    icon: nil,
    keywords: [],
    order: 0,
    layout: :stack,
    slot_style: %{},
    slot_outcome_key: %{}
  }

  @doc """
  Builds the view model. Derives `:resolution` and `:config` findings from
  `{document, palette}`, concatenates `findings` after them, routes every
  one of the combined list per the moduledoc's table, and groups
  `palette`'s types into `palette_groups`.
  """
  @spec build(Document.t(), Palette.t(), [Finding.t()]) :: t()
  def build(%Document{} = document, %Palette{} = palette, findings) when is_list(findings) do
    all_findings = derived_findings(document, palette) ++ findings
    block_ids = document |> Document.blocks() |> MapSet.new(& &1.id)

    {routed, orphan} =
      Enum.split_with(all_findings, &MapSet.member?(block_ids, finding_block_id(&1)))

    by_block = Enum.group_by(routed, &finding_block_id/1)

    %__MODULE__{
      document_id: document.id,
      revision: document.revision,
      root: build_node(document.root, {palette, by_block}),
      palette_groups: palette_groups(palette),
      findings: all_findings,
      orphan_findings: orphan
    }
  end

  # `:resolution` from a block that does not resolve; `:config` from
  # `validate_config/1` on one that does. One pass, pre-order.
  @accent_token ~r/^--sb-[a-z0-9]+(-[a-z0-9]+)*$/

  @doc """
  The custom-property NAME a palette entry declares as its block type's
  accent, or `nil` when it declared none or declared one this package will
  not put in a style attribute (ADR-0005 decision 14's `accent_token`).

  This is the **consumption** half of that seam. The editor stamps the name
  on the block's card and its palette row and rebinds `--sb-block-accent`
  there; two rules in the stylesheet read that property - an icon tile and
  a card stripe - and they are the only two, which is what keeps a block
  type's identity from becoming a rule per type. The editor never learns a
  type name at any point in that path.

  A descriptor carries a name and never a colour, on the same discipline
  `icon` is under: a block type naming a hex value would be deciding what
  it looks like in themes it has never seen. The value is the theme's.

  Total, and validating for the reason the spike's `theme.js` was: the
  return value is interpolated into a `style` attribute, so anything but an
  anchored `--sb-*` name resolves to `nil` and the card falls back to the
  editor's accent. A typo in a host's registry degrades to the default
  rather than producing a broken card or an injection point - ADR-0002
  amendment B3's discipline, arriving at one more key.

      iex> StatifierBlocks.ViewModel.accent_token(%{accent_token: "--sb-accent-invoke"})
      "--sb-accent-invoke"

      iex> StatifierBlocks.ViewModel.accent_token(%{accent_token: "red; background: url(x)"})
      nil

      iex> StatifierBlocks.ViewModel.accent_token(%{})
      nil
  """
  @spec accent_token(map()) :: String.t() | nil
  def accent_token(entry) when is_map(entry) do
    case Map.get(entry, :accent_token) do
      name when is_binary(name) -> if Regex.match?(@accent_token, name), do: name
      _undeclared_or_malformed -> nil
    end
  end

  def accent_token(_entry), do: nil

  @doc """
  Whether a container draws as a boundary box: true when ANY of its slots
  declares a rail style (ADR-0005 amendment 10c, as amended by 10h).

  The partition is the **rail** partition, `:secondary` and `:failure`
  alike, not the `:secondary` partition. 10c's stated reason - an attached
  rule is about a region, so the region needs a visible edge - is as true of
  a failure path as of an interrupt, and deriving both the rail placement
  and the boundary from one partition is what kept decision 13's recursion
  from acquiring a branch.

  Drawing a box around every container instead turns a deeply nested
  document into nested rectangles that read as noise, which is why this
  reads metadata rather than depth.
  """
  @spec boundary?(Node.t()) :: boolean()
  def boundary?(%Node{slots: slots}), do: Enum.any?(slots, &rail?/1)

  @doc """
  Whether one slot is placed as an attached rail rather than in the body
  flow: `:secondary` and `:failure`, and nothing else (amendment 10h's
  placement row).

  10i's posture applies above this: a `slot_style` value this editor does
  not know resolves to `:primary` before it ever reaches here, so a host
  declaring against a newer record gets an ordinary body slot rather than a
  raise or a dropped slot.
  """
  @spec rail?(Slot.t()) :: boolean()
  def rail?(%Slot{style: style}), do: style in [:secondary, :failure]

  @spec derived_findings(Document.t(), Palette.t()) :: [Finding.t()]
  defp derived_findings(%Document{} = document, %Palette{} = palette) do
    document
    |> Document.blocks()
    |> Enum.flat_map(fn block ->
      case Palette.resolve(palette, block) do
        {:ok, module, resolved} ->
          config_findings(block.id, module, resolved.config)

        {:error, reason} ->
          [Finding.new({:block, block.id}, :resolution, resolution_message(reason))]
      end
    end)
  end

  @spec config_findings(Block.id(), module(), Block.config()) :: [Finding.t()]
  defp config_findings(block_id, module, config) do
    case module.validate_config(config) do
      :ok ->
        []

      {:error, findings} ->
        Enum.map(findings, fn {key, message} ->
          Finding.new({:config, block_id, key}, :config, message)
        end)
    end
  end

  @spec resolution_message(
          {:unknown_block_type, Block.type_name()}
          | {:block_type_too_new, Block.id(), pos_integer()}
          | {:migration_failed, Block.id(), term()}
        ) :: String.t()
  defp resolution_message({:unknown_block_type, type_name}),
    do: "unknown block type #{inspect(type_name)}"

  defp resolution_message({:block_type_too_new, id, version}),
    do: "block #{id} is at type_version #{version}, newer than this palette's module supports"

  defp resolution_message({:migration_failed, id, reason}),
    do: "block #{id} failed to migrate its config: #{inspect(reason)}"

  @spec finding_block_id(Finding.t()) :: Block.id()
  defp finding_block_id(%Finding{anchor: {:config, id, _key}}), do: id
  defp finding_block_id(%Finding{anchor: {:slot, id, _name}}), do: id
  defp finding_block_id(%Finding{anchor: {:block, id}}), do: id

  @typedoc "Threaded through the recursive walk instead of two positional arguments."
  @type ctx :: {Palette.t(), %{optional(Block.id()) => [Finding.t()]}}

  @spec build_node(Block.t(), ctx()) :: Node.t()
  defp build_node(%Block{} = block, {palette, _by_block} = ctx) do
    case Palette.resolve(palette, block) do
      {:ok, module, resolved} -> build_resolved_node(block, module, resolved, ctx)
      {:error, reason} -> build_unresolvable_node(block, reason, ctx)
    end
  end

  @spec build_resolved_node(Block.t(), module(), Block.t(), ctx()) :: Node.t()
  defp build_resolved_node(
         %Block{} = block,
         module,
         %Block{config: config},
         {_palette, by_block} = ctx
       ) do
    own_findings = Map.get(by_block, block.id, [])
    declared = module.slots(config)
    declared_names = MapSet.new(declared, fn {name, _arity, _label} -> name end)

    extra_names =
      block.slots
      |> Map.keys()
      |> Enum.sort()
      |> Enum.reject(&MapSet.member?(declared_names, &1))

    slot_names = MapSet.union(declared_names, MapSet.new(extra_names))
    schema = module.config_schema(config)
    schema_keys = MapSet.new(schema, & &1.key)

    {block_findings, slot_findings, config_findings, unrouted} =
      route_own_findings(own_findings, schema_keys, slot_names)

    entry = palette_entry_with_defaults(module, block.type)

    declared_slots =
      Enum.map(declared, fn {name, arity, label} ->
        build_slot(
          name,
          label,
          arity,
          true,
          slot_presentation(entry, name),
          Map.get(block.slots, name, []),
          Map.get(slot_findings, name, []),
          ctx
        )
      end)

    extra_slots =
      Enum.map(extra_names, fn name ->
        build_slot(
          name,
          name,
          nil,
          false,
          slot_presentation(entry, name),
          Map.get(block.slots, name, []),
          Map.get(slot_findings, name, []),
          ctx
        )
      end)

    slots = declared_slots ++ extra_slots
    form = %Form{fields: build_fields(schema, config, config_findings), unrouted: unrouted}

    %Node{
      block_id: block.id,
      type: block.type,
      type_version: block.type_version,
      status: :ok,
      entry: entry,
      slots: slots,
      form: form,
      raw_config_json: nil,
      findings: block_findings,
      findings_count: findings_count(block_findings, slots, form)
    }
  end

  # No `@spec` here: `default_entry/1`'s literal map (see its own comment)
  # makes this function's success typing narrower than `Node.t()` in a way
  # dialyzer's `invalid_contract` check rejects even though the value it
  # returns is a perfectly good `Node.t()` at runtime. `build_node/2`,
  # this function's only caller, is what carries the public contract.
  @spec build_unresolvable_node(
          Block.t(),
          {:unknown_block_type, Block.type_name()}
          | {:block_type_too_new, Block.id(), pos_integer()}
          | {:migration_failed, Block.id(), term()},
          ctx()
        ) ::
          map()
  defp build_unresolvable_node(%Block{} = block, reason, {_palette, by_block} = ctx) do
    own_findings = Map.get(by_block, block.id, [])
    slot_names = block.slots |> Map.keys() |> MapSet.new()

    # No schema exists for an unresolvable block, so every `:config`
    # finding matches no field - `route_own_findings/3` puts all of them
    # in `unrouted`. There is no form to render them under here, so they
    # fold into this node's own `findings` instead of vanishing.
    {block_findings, slot_findings, _config_findings, unrouted} =
      route_own_findings(own_findings, MapSet.new(), slot_names)

    block_findings = block_findings ++ unrouted

    slots =
      block.slots
      |> Map.keys()
      |> Enum.sort()
      |> Enum.map(fn name ->
        build_slot(
          name,
          name,
          nil,
          false,
          {:primary, nil},
          Map.get(block.slots, name, []),
          Map.get(slot_findings, name, []),
          ctx
        )
      end)

    %Node{
      block_id: block.id,
      type: block.type,
      type_version: block.type_version,
      status: {:unresolvable, reason},
      entry: default_entry(block.type),
      slots: slots,
      form: nil,
      raw_config_json: raw_config_json(block.config),
      findings: block_findings,
      findings_count: findings_count(block_findings, slots, nil)
    }
  end

  @spec raw_config_json(Block.config()) :: String.t()
  defp raw_config_json(config), do: config |> CanonicalJson.encode_term() |> IO.iodata_to_binary()

  @typedoc """
  What the parent's `palette_entry/0` says about ONE slot: how it is placed
  (decision 10's `slot_style`) and where its children carry their outcome
  (decision 10's `slot_outcome_key`, proposed as 10f). Passed as a pair
  rather than as two arguments because `build_slot/8` is already at the
  arity the style guide allows, and because the two are read together.
  """
  @type slot_presentation :: {:primary | :secondary | :failure, String.t() | nil}

  @spec build_slot(
          Block.slot_name(),
          String.t(),
          BlockType.slot_arity() | nil,
          boolean(),
          slot_presentation(),
          [Block.t()],
          [Finding.t()],
          ctx()
        ) :: Slot.t()
  defp build_slot(name, label, arity, declared?, presentation, children_blocks, findings, ctx) do
    {style, outcome_key} = presentation

    %Slot{
      name: name,
      label: label,
      arity: arity,
      declared?: declared?,
      style: style,
      outcome_key: outcome_key,
      children: Enum.map(children_blocks, &build_child(&1, outcome_key, ctx)),
      findings: findings
    }
  end

  # A child node, plus the one fact only its PARENT's slot declaration can
  # supply: which outcome this block produces for the slot it sits in. The
  # config read happens here, where the block is still in hand, so nothing
  # downstream needs a block's config to answer it.
  @spec build_child(Block.t(), String.t() | nil, ctx()) :: Node.t()
  defp build_child(%Block{} = block, outcome_key, ctx) do
    node = build_node(block, ctx)
    %{node | outcome: BlockType.outcome_name(block.config, outcome_key)}
  end

  @spec build_fields([BlockType.field_decl()], Block.config(), %{
          optional(String.t()) => [Finding.t()]
        }) ::
          [Field.t()]
  defp build_fields(schema, config, config_findings) do
    Enum.map(schema, fn %{
                          key: key,
                          type: type,
                          label: label,
                          required?: required?,
                          default: default
                        } = decl ->
      path = BlockType.value_path(decl)

      %Field{
        key: key,
        type: type,
        label: label,
        required?: required?,
        default: default,
        value_path: Map.get(decl, :value_path),
        value: value_at(config, path, default),
        findings: Map.get(config_findings, key, [])
      }
    end)
  end

  # A declared `value_path` is read exactly as `config[key]` always was:
  # the value if it is there, the field's default if it is not. Both cases
  # go through `BlockType.fetch_value/2` so the un-pathed field and the
  # pathed one cannot drift apart.
  @spec value_at(Block.config(), BlockType.value_path(), Block.json()) :: Block.json()
  defp value_at(config, path, default) do
    case BlockType.fetch_value(config, path) do
      {:ok, value} -> value
      :error -> default
    end
  end

  # Places one block's own findings into four buckets, by anchor:
  # `{:block, _}` -> `block_findings`; `{:slot, _, name}` -> `slot_findings`
  # when `name` is in `slot_names`, else `block_findings` (the fallback
  # decision 11's table names); `{:config, _, key}` -> `config_findings`
  # when `key` is in `schema_keys`, else `unrouted`. Total over every
  # anchor a `StatifierBlocks.Finding.t()` can carry - nothing is dropped.
  @spec route_own_findings([Finding.t()], MapSet.t(String.t()), MapSet.t(Block.slot_name())) ::
          {[Finding.t()], %{optional(Block.slot_name()) => [Finding.t()]},
           %{optional(String.t()) => [Finding.t()]}, [Finding.t()]}
  defp route_own_findings(own_findings, schema_keys, slot_names) do
    {block_r, slot_r, config_r, unrouted_r} =
      Enum.reduce(own_findings, {[], %{}, %{}, []}, fn finding, acc ->
        route_one_finding(finding, acc, schema_keys, slot_names)
      end)

    slot_r = Map.new(slot_r, fn {name, list} -> {name, Enum.reverse(list)} end)
    config_r = Map.new(config_r, fn {key, list} -> {key, Enum.reverse(list)} end)

    {Enum.reverse(block_r), slot_r, config_r, Enum.reverse(unrouted_r)}
  end

  # One finding routed into one of the four accumulators
  # `route_own_findings/3` folds over. Split out to a function per anchor
  # tag rather than a `case` inside the reducer, keeping the reduction
  # itself within credo's nesting-depth limit.
  @spec route_one_finding(
          Finding.t(),
          {[Finding.t()], %{optional(Block.slot_name()) => [Finding.t()]},
           %{optional(String.t()) => [Finding.t()]}, [Finding.t()]},
          MapSet.t(String.t()),
          MapSet.t(Block.slot_name())
        ) ::
          {[Finding.t()], %{optional(Block.slot_name()) => [Finding.t()]},
           %{optional(String.t()) => [Finding.t()]}, [Finding.t()]}
  defp route_one_finding(
         %Finding{anchor: {:block, _id}} = finding,
         acc,
         _schema_keys,
         _slot_names
       ) do
    {block_acc, slot_acc, config_acc, unrouted_acc} = acc
    {[finding | block_acc], slot_acc, config_acc, unrouted_acc}
  end

  defp route_one_finding(
         %Finding{anchor: {:slot, _id, name}} = finding,
         acc,
         _schema_keys,
         slot_names
       ) do
    {block_acc, slot_acc, config_acc, unrouted_acc} = acc

    if MapSet.member?(slot_names, name) do
      {block_acc, Map.update(slot_acc, name, [finding], &[finding | &1]), config_acc,
       unrouted_acc}
    else
      {[finding | block_acc], slot_acc, config_acc, unrouted_acc}
    end
  end

  defp route_one_finding(
         %Finding{anchor: {:config, _id, key}} = finding,
         acc,
         schema_keys,
         _slot_names
       ) do
    {block_acc, slot_acc, config_acc, unrouted_acc} = acc

    if MapSet.member?(schema_keys, key) do
      {block_acc, slot_acc, Map.update(config_acc, key, [finding], &[finding | &1]), unrouted_acc}
    else
      {block_acc, slot_acc, config_acc, [finding | unrouted_acc]}
    end
  end

  @spec findings_count([Finding.t()], [Slot.t()], Form.t() | nil) :: non_neg_integer()
  defp findings_count(block_findings, slots, form) do
    slots_count =
      Enum.reduce(slots, 0, fn slot, acc ->
        children_count = Enum.reduce(slot.children, 0, &(&1.findings_count + &2))
        acc + length(slot.findings) + children_count
      end)

    form_count =
      case form do
        nil ->
          0

        %Form{fields: fields, unrouted: unrouted} ->
          Enum.reduce(fields, length(unrouted), &(length(&1.findings) + &2))
      end

    length(block_findings) + slots_count + form_count
  end

  @spec slot_presentation(map(), Block.slot_name()) :: slot_presentation()
  defp slot_presentation(entry, name) do
    {Map.get(entry.slot_style, name, :primary), BlockType.slot_outcome_key(entry, name)}
  end

  @spec palette_entry_with_defaults(module(), Block.type_name()) :: BlockType.palette_entry()
  defp palette_entry_with_defaults(module, type_name) do
    raw =
      if Code.ensure_loaded?(module) and function_exported?(module, :palette_entry, 0) do
        module.palette_entry()
      else
        %{}
      end

    default_entry(type_name) |> Map.merge(raw)
  end

  # `BlockType.palette_entry/0`'s type declares every key `optional/1`,
  # which is right for the callback (a host module may omit any of them)
  # but wrong for this literal: `@default_entry` plus `:label` always
  # carries all eight keys, and dialyzer's success typing for a map that
  # provably always has a key is a poor match for a spec that says the key
  # might be absent. `map()` is the honest spec for this private helper;
  # `palette_entry_with_defaults/2`, which is what every caller outside
  # this function actually sees, is the one whose spec carries the real
  # (optional) callback type.
  @spec default_entry(Block.type_name()) :: map()
  defp default_entry(type_name), do: Map.put(@default_entry, :label, type_name)

  # `palette.types`, each carrying its own defaulted `palette_entry/0`,
  # grouped by `entry.group` and sorted group name -> `order` -> `label`
  # (ADR-0005 decision 10's grouping rule).
  @spec palette_groups(Palette.t()) :: [PaletteGroup.t()]
  defp palette_groups(%Palette{types: types}) do
    types
    |> Enum.map(fn {type_name, module} ->
      {type_name, module, palette_entry_with_defaults(module, type_name)}
    end)
    |> Enum.group_by(fn {_type_name, _module, entry} -> entry.group end)
    |> Enum.sort_by(fn {group, _entries} -> group end)
    |> Enum.map(fn {group, entries} ->
      %PaletteGroup{
        name: group,
        entries:
          entries
          |> Enum.sort_by(fn {_type_name, _module, entry} -> {entry.order, entry.label} end)
          |> Enum.map(fn {type_name, module, entry} ->
            %{type_name: type_name, module: module, entry: entry}
          end)
      }
    end)
  end
end
