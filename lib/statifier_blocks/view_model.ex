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

  `:assignability` and `:lint` findings are never produced here; their
  producers live elsewhere - `StatifierBlocks.SlotValidation`
  (palette-aware slot arity and undeclared-slot checks; landed under `sb-da9`,
  was described here as "not yet built") and `Assignability.validate/3` for
  the first, the compiler's invoke-type lint for the second - and this module
  does not
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

  alias StatifierBlocks.{Block, BlockType, CanonicalJson, Document, Finding, Palette, Shelf}

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

    `condition` is the **source text of the condition this slot is subject
    to**: the parent type's own `:expression` config field keyed by this
    slot's name, read through the `value_path` ADR-0002 decision 7 was
    amended to carry. `nil` when the type declares no such field, when the
    author has not written one yet, or when the value stored there is not a
    non-empty string.

    It is resolved here for the reason `Node.outcome` is: the rendering side
    reads one string and never learns that `core.branch` is the type whose
    arms are guarded. A host type that keys an `:expression` field by one of
    its own slot names gets the same chip, and nothing here tests a type name
    to decide it.
    """

    @type t :: %__MODULE__{
            name: Block.slot_name(),
            label: String.t(),
            arity: BlockType.slot_arity() | nil,
            style: :primary | :secondary | :failure | :tray,
            declared?: boolean(),
            outcome_key: String.t() | nil,
            children: [StatifierBlocks.ViewModel.Node.t()],
            findings: [Finding.t()],
            condition: String.t() | nil
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
      findings: [],
      condition: nil
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

    `join_label` is what the join marker under a side-by-side arrangement
    reads: the string this block type's `join_label` callback returned for
    this block's config, normalized by `StatifierBlocks.BlockType.join_label/2`,
    and `nil` when the type declared none or the callback answered with
    something the refusal set rejects (ADR-0002 amendment B). It is resolved
    here for the same reason `outcome` is - the rendering side reads a string
    and never learns that `core.parallel` is the type with a completion rule.

    It is derived for **every** node, including the ones whose slots stack
    and never draw a marker: a field that exists only sometimes is a field
    every consumer has to remember to guard, and `entry.layout` already says
    whether the marker is drawn. An unresolvable block reaches `nil` by the
    ordinary route rather than by a special case - its entry is the
    placeholder's, which declares no callback.

    `title` is the author's own name for THIS block - the value of a
    declared `:string` field keyed `label` - and `nil` when the type
    declares no such field or the config holds nothing usable there, which
    is every block in the `core.*` vocabulary. `nil` rather than "the
    entry's label repeated" so that the card can tell the two apart: a
    block with a name of its own reads as its name over its type, and a
    block without one reads as its type alone rather than as its type
    printed twice (`ViewModel.title/1` and `ViewModel.subtitle/1` are that
    pair). It is derived here for the same reason `outcome` is - the
    rendering side reads a string and never learns which key an author's
    name lives under.

    `summary_titles` is the raw text behind each chip in `summary`, `nil`
    where the chip is drawn as its type declared it (ADR-0005 decision
    10w). It is index-aligned with `summary` by construction rather than
    by maintenance - `StatifierBlocks.BlockType` derives both from one
    pass over one callback - and it is read through
    `ViewModel.summary_chip_titles/1`, which realigns it against
    `summary_chips/1` for a node built by hand.

    `invoke_type` is what this block's config carries under `invoke_type`,
    when that is a non-empty string. It is a config key rather than a type
    name, so a host type that calls out to a handler gets the same third
    line `core.invoke` does by carrying the same key, and no component
    learns that `core.invoke` exists. Whether the value is WELL FORMED is
    `validate_config/1`'s question and its answer arrives as a finding on
    the same card; hiding the string while a finding complains about it
    would be the card disagreeing with the form.
    """

    @type status :: :ok | {:unresolvable, term()}

    @type t :: %__MODULE__{
            block_id: Block.id(),
            type: Block.type_name(),
            type_version: pos_integer(),
            status: status(),
            entry: BlockType.palette_entry(),
            title: String.t() | nil,
            summary: [String.t()],
            summary_titles: [String.t() | nil],
            invoke_type: String.t() | nil,
            outcome: String.t() | nil,
            join_label: String.t() | nil,
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
      title: nil,
      summary: [],
      summary_titles: [],
      invoke_type: nil,
      outcome: nil,
      join_label: nil,
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
  Builds the view model. Derives `:resolution`, `:config` and `:lint`
  findings from `{document, palette}`, concatenates `findings` after them,
  routes every one of the combined list per the moduledoc's table, and
  groups `palette`'s types into `palette_groups`.

  The `:lint` half is the summary chips the presentation cap refused
  (`StatifierBlocks.BlockType.summary_refusals/2`), one `:warning` per
  refusal - the only derived finding here that is not an error.
  """
  @spec build(Document.t(), Palette.t(), [Finding.t()]) :: t()
  def build(%Document{} = document, %Palette{} = palette, findings) when is_list(findings) do
    labels = chip_labels(document, palette)
    all_findings = derived_findings(document, palette, labels) ++ findings
    block_ids = document |> Document.blocks() |> MapSet.new(& &1.id)

    {routed, orphan} =
      Enum.split_with(all_findings, &MapSet.member?(block_ids, finding_block_id(&1)))

    by_block = Enum.group_by(routed, &finding_block_id/1)

    %__MODULE__{
      document_id: document.id,
      revision: document.revision,
      root: build_node(document.root, {palette, by_block, labels}),
      palette_groups: palette_groups(palette),
      findings: all_findings,
      orphan_findings: orphan
    }
  end

  # `:resolution` from a block that does not resolve; `:config` from
  # `validate_config/1` on one that does. One pass, pre-order.
  @accent_token ~r/^--sb-[a-z0-9]+(-[a-z0-9]+)*$/

  # Decision 10's `slot_style` vocabulary, as widened by amendment 10g, and
  # the rail partition inside it (10h's placement row). Both are spelled once
  # here: 10i makes the closed set load-bearing - anything outside it is a
  # declaration this editor cannot read - and a second copy is how the
  # partition and the vocabulary drift apart.
  @slot_styles [:primary, :secondary, :failure, :tray]
  @rail_styles [:secondary, :failure]

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
  The name on the face of a card: the author's own, when this block carries
  one, and the block type's palette label otherwise.

  Two questions, not one, which is why this and `subtitle/1` are a pair
  rather than one field. A card answers "what is this step" with the most
  specific name available, and "what kind of step is it" underneath - and
  when the only name available IS the type's, there is nothing for the
  second line to add.

      iex> alias StatifierBlocks.ViewModel
      iex> ViewModel.title(%ViewModel.Node{
      ...>   block_id: "b", type: "core.wait", type_version: 1, status: :ok,
      ...>   entry: %{label: "Wait"}
      ...> })
      "Wait"

      iex> alias StatifierBlocks.ViewModel
      iex> ViewModel.title(%ViewModel.Node{
      ...>   block_id: "b", type: "host.step", type_version: 1, status: :ok,
      ...>   entry: %{label: "Intake"}, title: "Collect the details"
      ...> })
      "Collect the details"
  """
  @spec title(Node.t()) :: String.t()
  def title(%Node{title: title}) when is_binary(title), do: title
  def title(%Node{entry: entry, type: type}), do: Map.get(entry, :label) || type

  @doc """
  The block type's own label, drawn under the title when the title is the
  **author's** - the one thing a renamed card says nowhere else, and `nil`
  when the author's name and the type's label are the same word.

  `nil` for every block the author has not named, because there the second
  line is the type's summary of this block's config and that line is a row
  of chips rather than a string: it is `summary_chips/1`, drawn as its own
  markup (ADR-0005's 2026-08-30 amendment, decision 10, the summary chip
  row). This function and that one are the two arms ADR-0002 amendment H5
  describes, and exactly one of them answers for any card.

      iex> alias StatifierBlocks.ViewModel
      iex> ViewModel.subtitle(%ViewModel.Node{
      ...>   block_id: "b", type: "core.wait", type_version: 1, status: :ok,
      ...>   entry: %{label: "Wait"}
      ...> })
      nil

      iex> alias StatifierBlocks.ViewModel
      iex> ViewModel.subtitle(%ViewModel.Node{
      ...>   block_id: "b", type: "core.wait", type_version: 1, status: :ok,
      ...>   entry: %{label: "Wait"}, summary: ["timer 30s"]
      ...> })
      nil

      iex> alias StatifierBlocks.ViewModel
      iex> ViewModel.subtitle(%ViewModel.Node{
      ...>   block_id: "b", type: "host.step", type_version: 1, status: :ok,
      ...>   entry: %{label: "Intake"}, title: "Collect the details"
      ...> })
      "Intake"
  """
  @spec subtitle(Node.t()) :: String.t() | nil
  def subtitle(%Node{title: title, entry: entry, type: type}) when is_binary(title) do
    case Map.get(entry, :label) || type do
      ^title -> nil
      label -> label
    end
  end

  def subtitle(%Node{}), do: nil

  @doc """
  The chips on the card's second line: the type's summary of this block's
  config, one element per chip, and `[]` when there is no row to draw.

  The other arm of ADR-0002 amendment H5, and the reader ADR-0005's
  2026-08-30 amendment (decision 10, the summary chip row) describes. `[]`
  means **no row at all** rather than an empty one, which is the card every
  type had before it declared a summary: `summary/1` is optional and eight
  of the thirteen core types declare none.

  Empty for a block the author has named, because that card's second line
  is already the type's label (`subtitle/1`) and a card has one second
  line. A string summary arrives here as a one-element list, so the one-chip
  case draws one chip and no separator of any kind.

  Nothing is refused here. An over-long or newline-carrying chip was already
  dropped where the node was built (`StatifierBlocks.BlockType.summary/2`,
  under ADR-0002 B3's refuse-never-truncate discipline), so this reads what
  survived. What did not survive is not silent: `build/3` raises a `:lint`
  warning against the block for each refused chip, so the difference between
  "declared nothing" and "declared something too long" is readable.

      iex> alias StatifierBlocks.ViewModel
      iex> ViewModel.summary_chips(%ViewModel.Node{
      ...>   block_id: "b", type: "core.on_event", type_version: 1, status: :ok,
      ...>   entry: %{label: "On event"}, summary: ["Abandon", "fraud.aborted"]
      ...> })
      ["Abandon", "fraud.aborted"]

      iex> alias StatifierBlocks.ViewModel
      iex> ViewModel.summary_chips(%ViewModel.Node{
      ...>   block_id: "b", type: "core.sequence", type_version: 1, status: :ok,
      ...>   entry: %{label: "Sequence"}
      ...> })
      []

      iex> alias StatifierBlocks.ViewModel
      iex> ViewModel.summary_chips(%ViewModel.Node{
      ...>   block_id: "b", type: "host.step", type_version: 1, status: :ok,
      ...>   entry: %{label: "Intake"}, title: "Collect the details",
      ...>   summary: ["from the type"]
      ...> })
      []
  """
  @spec summary_chips(Node.t()) :: [String.t()]
  def summary_chips(%Node{title: title}) when is_binary(title), do: []
  def summary_chips(%Node{summary: summary}), do: summary

  @doc """
  The raw text behind each chip `summary_chips/1` draws, `nil` where the
  chip is drawn as its type declared it, and always exactly as long as
  `summary_chips/1`.

  ADR-0005 decision 10w's other half. A chip whose text has the shape of a
  generated done-event name is drawn as `<block label>` and the outcome,
  and the raw name goes on the chip's `title` attribute - verbatim and
  untruncated, because that is what keeps the translation lossless for an
  author reading a screenshot beside generated SCXML.

  The length is realigned against `summary_chips/1` rather than trusted,
  so a `Node` built by hand - a doctest, a host's fixture - answers one
  `nil` per chip instead of an empty list the caller would zip away.

      iex> ViewModel.summary_chip_titles(%ViewModel.Node{
      ...>   block_id: "blk_ON", type: "core.on_event", type_version: 1, status: :ok,
      ...>   entry: %{label: "On event"}, summary: ["Abandon", "fraud.aborted"]
      ...> })
      [nil, nil]
  """
  @spec summary_chip_titles(Node.t()) :: [String.t() | nil]
  def summary_chip_titles(%Node{} = node) do
    titles = node.summary_titles

    node
    |> summary_chips()
    |> Enum.with_index()
    |> Enum.map(fn {_chip, index} -> Enum.at(titles, index) end)
  end

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
  def rail?(%Slot{style: style}), do: style in @rail_styles

  @doc """
  Whether one slot is a detached shelf rather than either a body slot or an
  attached rail (ADR-0005's amendment of 2026-08-31, section 10s).

  `:tray` is deliberately **not** in the rail partition. 10h made "is this
  container a boundary box" a question asked of that partition, on 10c's
  grounds that an attached rule is about a *region* and a region needs a
  visible edge. A tray is not attached to a region; it is beside the
  document. Folding it in would put a boundary box around the root block of
  every document that has a shelf - a frame drawn around the entire
  workflow to say something about a shelf beside it (10t).

  It is not in the body partition either, which is what `body_slots/1`
  spells: a tray is not one of the things a container fans into, and its
  contents take no entry edge.
  """
  @spec tray?(Slot.t()) :: boolean()
  def tray?(%Slot{style: :tray}), do: true
  def tray?(%Slot{}), do: false

  @doc """
  Whether this node is the drafts shelf itself.

  A shelf is a child of the root's `body` like any other block, so the slot
  holding it is an ordinary `:primary` one and `tray?/1` says nothing about
  it. What has to be true of the *node* is 10u's other half: no connector
  enters the shelf and none leaves it, so it is not in its own parent's
  chain either. `flow_children/1` and `shelf_children/1` are that partition,
  and they are the rendering counterpart of ADR-0002's G9a - the sibling
  before the shelf is adjacent to the sibling after it, on the canvas for
  the same reason it is in the compiler.
  """
  @spec shelf?(Node.t()) :: boolean()
  def shelf?(%Node{type: type}), do: Shelf.shelf_type?(type)

  @doc """
  A slot's children that are in the flow: everything but a shelf.
  """
  @spec flow_children(Slot.t()) :: [Node.t()]
  def flow_children(%Slot{children: children}), do: Enum.reject(children, &shelf?/1)

  @doc """
  A slot's children that are shelves - at most one, by ADR-0002 G12b, and
  drawn after the flow children so the shelf sits at the foot of the canvas.
  """
  @spec shelf_children(Slot.t()) :: [Node.t()]
  def shelf_children(%Slot{children: children}), do: Enum.filter(children, &shelf?/1)

  @doc """
  Which edge vocabulary a slot's exit is drawn in (amendment 10h's exit-edge
  row, as ruled on `sb-67s`, 2026-08-29).

  `:interrupt` for the interrupt rail alone. A `:failure` rail's exit is
  `:flow`, the same edge an ordinary body slot leaves by: ADR-0004's
  amendment makes a failure path end in an error-outcome final whose
  completion event the PARENT continues on, so it leaves in-band, and the
  dashed exit channel with the interrupt arrowhead stays exclusively
  interrupt vocabulary. Before the ruling the spike drew a failure rail
  in-band and drew it leaving out-of-band in the same picture.

  It is total over the three styles rather than defined on rails only: the
  answer for a body slot is the same `:flow` its children already leave by,
  and a partial function here would make every caller re-derive the rail
  test this module already owns.
  """
  @spec exit_edge(Slot.t()) :: :flow | :interrupt
  def exit_edge(%Slot{style: :secondary}), do: :interrupt
  def exit_edge(%Slot{}), do: :flow

  @doc """
  How a container arranges its body slots: `:lanes`, `:fan` or `:stack`
  (ADR-0005 amendment 10b, and the campaign-012 spike's `arrangementOf`).

  One derivation, read by three consumers that would otherwise each grow
  their own: the class `BlockNode` puts on the slot box, the words the
  `ONE OF` / `ALL OF` pill reads, and `Connectors`' decision between a fan
  and a single entry edge. Three answers derived separately from the same
  two facts is how they drift, and the pill disagreeing with the layout is
  the drift a reader would see first.

  The two facts, and neither of them a type name:

    * `layout: :columns` - decision 10's own metadata - is `:lanes`, the
      concurrent arrangement. `core.parallel` declares it.
    * More than one **body** slot is `:fan`, the exclusive one.
      `core.branch` reaches it by declaring one slot per arm, and a host
      type of the same shape reaches it the same way.

  Rails are excluded from the count for the same reason `Connectors` excludes
  them: a rail is attached beside the body, so it is not one of the things
  the body fans into.

  A container with no body slot at all arranges nothing and is `:stack`,
  whatever it declares - there is no second column for a marker to sit over.
  """
  @spec arrangement(Node.t()) :: :lanes | :fan | :stack
  def arrangement(%Node{} = node) do
    case body_slots(node) do
      [] -> :stack
      body -> arrangement_of(node.entry, body)
    end
  end

  @spec arrangement_of(map(), [Slot.t()]) :: :lanes | :fan | :stack
  defp arrangement_of(%{layout: :columns}, _body), do: :lanes
  defp arrangement_of(_entry, [_one]), do: :stack
  defp arrangement_of(_entry, _several), do: :fan

  @doc """
  Every slot placed in the body flow, in order: the arrangement's columns.
  """
  @spec body_slots(Node.t()) :: [Slot.t()]
  def body_slots(%Node{slots: slots}), do: Enum.reject(slots, &(rail?(&1) or tray?(&1)))

  @doc """
  The words on the pill drawn on the edge below an arranged container, or
  `nil` when nothing is arranged (ADR-0005 amendment 10b, campaign 016).

  The distinction the pill states is the one the arrangement already makes
  and nothing else in the picture does: a fan's columns are alternatives and
  a parallel's lanes are concurrent, and side-by-side columns look identical
  either way. The spike drew the same two words off the same derivation, and
  its note is the reason this is here rather than in the renderer: the words
  are the only place the exclusive/concurrent distinction is stated.

  It is the editor's own vocabulary rather than a type's, which is what
  separates it from `join_label` - a type phrases what its columns come back
  together as, because only the type knows its completion rule, but whether
  its columns are alternatives is a fact about the arrangement this module
  already derived.
  """
  @spec fan_label(Node.t()) :: String.t() | nil
  def fan_label(%Node{} = node) do
    case arrangement(node) do
      :lanes -> "all of"
      :fan -> "one of"
      :stack -> nil
    end
  end

  @spec derived_findings(Document.t(), Palette.t(), BlockType.chip_labels()) :: [Finding.t()]
  defp derived_findings(%Document{} = document, %Palette{} = palette, labels) do
    document
    |> Document.blocks()
    |> Enum.flat_map(fn block ->
      case Palette.resolve(palette, block) do
        {:ok, module, resolved} ->
          config_findings(block.id, module, resolved.config) ++
            summary_findings(block.id, module, resolved.config, labels)

        {:error, reason} ->
          [Finding.new({:block, block.id}, :resolution, resolution_message(reason))]
      end
    end)
  end

  # ADR-0005 decision 10's 2026-08-30 Note, "the cap signals". The
  # presentation cap refuses a chip rather than truncating it (ADR-0002 B3),
  # which is the right call for the card and leaves the author with nothing
  # to look at: a lane name one character too long draws the same card as a
  # lane nobody declared. `:lint` at `:warning` is the honest severity -
  # decision 11 reserves every non-error severity to `:lint`, and the
  # document compiles either way, so this changes no verdict and only says
  # that something declared is not being drawn.
  @spec summary_findings(Block.id(), module(), Block.config(), BlockType.chip_labels()) ::
          [Finding.t()]
  defp summary_findings(block_id, module, config, labels) do
    module
    |> BlockType.summary_refusals(config, labels)
    |> Enum.map(fn refusal ->
      Finding.new(
        {:block, block_id},
        :lint,
        BlockType.summary_refusal_message(module, config, refusal, labels),
        severity: :warning
      )
    end)
  end

  # ADR-0005 decision 10w's `<block label>`: the label the named block's
  # own card draws, for every block in the document. Read from the same
  # three sources `title/1` reads, in the same order, because the chip has
  # to name the block the way the canvas names it - a chip citing a label
  # nothing on the canvas carries would be worse than the raw event name.
  #
  # It is a pre-pass rather than something the recursive walk accumulates
  # because a chip may name a block that is drawn LATER, or that is not on
  # this card's branch at all. This is the reader dependency ADR-0005's
  # Consequences names: the chip pass reads across the document rather
  # than down one block.
  @spec chip_labels(Document.t(), Palette.t()) :: BlockType.chip_labels()
  defp chip_labels(%Document{} = document, %Palette{} = palette) do
    document
    |> Document.blocks()
    |> Map.new(fn block -> {block.id, chip_label(block, palette)} end)
  end

  @spec chip_label(Block.t(), Palette.t()) :: String.t()
  defp chip_label(%Block{} = block, %Palette{} = palette) do
    case Palette.resolve(palette, block) do
      {:ok, module, resolved} ->
        entry = palette_entry_with_defaults(module, block.type)

        title_override(module.config_schema(resolved.config), resolved.config) ||
          Map.get(entry, :label) || block.type

      # An unresolvable block draws its type name and nothing else
      # (`build_unresolvable_node/3` has no schema to read a title out of),
      # so that is its label here too.
      {:error, _reason} ->
        block.type
    end
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
  @type ctx ::
          {Palette.t(), %{optional(Block.id()) => [Finding.t()]}, BlockType.chip_labels()}

  @spec build_node(Block.t(), ctx()) :: Node.t()
  defp build_node(%Block{} = block, {palette, _by_block, _labels} = ctx) do
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
         {_palette, by_block, labels} = ctx
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

    conditions = slot_conditions(schema, config)

    declared_slots =
      Enum.map(declared, fn {name, arity, label} ->
        slot =
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

        %{slot | condition: Map.get(conditions, name)}
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
      title: title_override(schema, config),
      summary: BlockType.summary(module, config, labels),
      summary_titles: BlockType.summary_titles(module, config, labels),
      invoke_type: invoke_type(config),
      join_label: BlockType.join_label(entry, config),
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
  defp build_unresolvable_node(%Block{} = block, reason, {_palette, by_block, _labels} = ctx) do
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
      # No schema, so no declared `label` field and no title override - but
      # the config is still bytes this module can read, and a block that
      # says which handler it called says it whether or not its type
      # resolves. That line is often the only clue to what the missing type
      # was.
      title: nil,
      invoke_type: invoke_type(block.config),
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
  @type slot_presentation :: {:primary | :secondary | :failure | :tray, String.t() | nil}

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

  # The condition source per key: every `:expression` field in a container's
  # own schema, read through its `value_path`, keyed by the field's key.
  #
  # The key IS the slot name for the case this exists to serve - ADR-0002
  # decision 7's amendment splits an arm's key from its value path precisely
  # so a `core.branch` arm addresses its own condition while its findings
  # keep routing by slot name - so the map is built over every expression
  # field and the caller looks its slot up in it. A field keyed by something
  # that is not a slot never matches, which is why nothing is filtered
  # against the slot set here: this function answers "what expression is
  # stored under this key", and which keys are slots is the caller's
  # question.
  #
  # An absent, blank or non-string value is dropped rather than carried as
  # `""`. A chip is a claim that a condition exists, and an arm whose
  # condition an author has not written yet already carries a finding saying
  # so; an empty chip beside that finding says the same thing twice, and says
  # it blank.
  @spec slot_conditions([BlockType.field_decl()], Block.config()) :: %{
          optional(String.t()) => String.t()
        }
  defp slot_conditions(schema, config) do
    schema
    |> Enum.filter(&(&1.type == :expression))
    |> Enum.map(fn decl -> {decl.key, value_at(config, BlockType.value_path(decl), nil)} end)
    |> Enum.filter(fn {_key, source} -> is_binary(source) and source != "" end)
    |> Map.new()
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

  # The author's own name for this block, or `nil`.
  #
  # A declared `:string` field keyed `label` is the seam, and it is the whole
  # of it: a block type that wants its instances named says so the same way it
  # declares any other field, and a type that declares none has no title
  # override rather than a special case. Read through `BlockType.value_path/1`
  # like every other field's value, so a type that stores its name somewhere
  # other than `config["label"]` is read where it actually put it.
  #
  # No block type in the `core.*` vocabulary declares one. That is the
  # intended shape rather than a gap: "Wait" is what a wait is called, and a
  # type whose steps are worth naming individually is a host's.
  @spec title_override([BlockType.field_decl()], Block.config()) :: String.t() | nil
  defp title_override(schema, config) do
    with %{} = field <- Enum.find(schema, &(&1.key == "label" and &1.type == :string)),
         {:ok, value} <- BlockType.fetch_value(config, BlockType.value_path(field)) do
      non_empty_string(value)
    else
      _undeclared_or_absent -> nil
    end
  end

  # The invoke type on the card's third line. A config key, never a type name:
  # see `Node`'s moduledoc for why a malformed value still renders.
  @spec invoke_type(Block.config()) :: String.t() | nil
  defp invoke_type(config), do: config |> Map.get("invoke_type") |> non_empty_string()

  @spec non_empty_string(term()) :: String.t() | nil
  defp non_empty_string(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: value
  end

  defp non_empty_string(_value), do: nil

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
    {slot_style(entry, name), BlockType.slot_outcome_key(entry, name)}
  end

  # 10i: a `slot_style` this editor does not know - a host declaring against
  # a newer record, or a typo - resolves to `:primary`, so the slot renders
  # as an ordinary body slot with its children still rendered, still
  # selectable and still saved. That is decision 3's total-resolution posture
  # arriving at presentation, and the same discipline ADR-0002's amendment B3
  # applies to the metadata trio: a malformed declaration in one host's
  # registry produces the ordinary card, never a broken one and never an
  # exception.
  #
  # A `slot_style` that is not a map at all is the same defect one level up -
  # a declaration this editor cannot read - and it degrades the same way
  # rather than raising `BadMapError` out of a render.
  @spec slot_style(map(), Block.slot_name()) :: :primary | :secondary | :failure | :tray
  defp slot_style(entry, name) do
    styles = Map.get(entry, :slot_style)

    case is_map(styles) and Map.get(styles, name, :primary) do
      style when style in @slot_styles -> style
      _unrecognized_or_malformed -> :primary
    end
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
