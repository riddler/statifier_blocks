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

  ## The derived finding sources, and the compiler adapter

  `build/3`'s third argument is a caller-supplied `[StatifierBlocks.Finding.t()]`.
  This module derives sources of its own, because decision 13
  puts resolution, migration and validation inside `ViewModel` rather than
  upstream of it. There are **five** of them, listed below. The count grew
  with ADR-0005 clause 11o, which superseded the "exactly two" this
  moduledoc used to say, and again with clauses 11p to 11t, which gave a
  host a whole-document rule of its own - so the number is stated here
  rather than left to a reader to count, and the list beneath it is what it
  counts:

    * `:resolution` - `Palette.resolve/2` failing on a block
      (`:unknown_block_type`, `:block_type_too_new`, `:migration_failed`),
      anchored `{:block, id}`, severity `:error`.
    * `:config` - `validate_config/1` on a resolved block, one per
      `{key, message}` pair, anchored `{:config, id, key}`, severity
      `:error`.
    * `:config` again, this time about the whole document - a palette entry
      declaring `singleton` (ADR-0005 clause 10z) that the document does not
      satisfy, anchored `{:block, root_id}`, severity `:error`. See "d10's
      cardinality declaration" below.
    * `:lint` - a summary chip the presentation cap refused, anchored
      `{:block, id}`, severity `:warning`.
    * `:lint` again, this time from a host's own whole-document rule - a
      `StatifierBlocks.DocumentValidator` in the palette's `validators`
      (ADR-0005 clauses 11p to 11t) - anchored wherever the rule says,
      severity `:warning` unless the rule says otherwise. The rule says
      where and what; this module stamps the source, which is what keeps a
      host's rule distinguishable from a declared shape's `:config`.

  `:assignability` findings are never produced here, and the two `:lint`
  producers above are the only ones that are; the rest live elsewhere -
  `StatifierBlocks.SlotValidation` (palette-aware slot arity and
  undeclared-slot checks; landed under `sb-da9`, was described here as "not
  yet built") and `Assignability.validate/3` for `:assignability`, the
  compiler's invoke-type lint for a `:lint` this module has never derived -
  and this module does not
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

  ## d10's cardinality declaration

  A palette entry may declare `singleton: :head | :anywhere` (ADR-0005
  clause 10z), and `build/3` answers it with one `:config` finding per
  violating type - never with a repair. Both values mean "the document
  holds exactly one block of this type"; `:head` additionally means it is
  the first child of the root's first slot.

  **What "the root's first slot" is**, because a root type declaring more
  than one slot leaves the phrase undefined otherwise: it is the **first
  slot the root's type declares** - `slots/1`'s list is ordered and that
  order is load-bearing everywhere else here, so the head is index 0 of
  that slot's children. A root whose type declares no slots, or does not
  resolve at all, falls back to the alphabetically first slot name the root
  block actually carries, which is the order `build_resolved_node/4`
  already puts undeclared slots in. Every `:head` finding names the slot it
  measured against, so an author with a multi-slot root is never left
  guessing which one the rule meant.

  The count is over the document's blocks by `type` and the declarations
  come from the palette, which is what lets the **zero** case exist at all:
  a type nothing in the document uses still draws its finding, because the
  palette is where the host said the document needs one. One finding per
  violating type, not one per surplus block. The anchor is `{:block,
  root_id}` - decision 11's anchor enum has no document member, this clause
  does not widen it, and the root is the one block every document has.

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

  A field declared `hidden?: true` (ADR-0002 decision 7, amended
  2026-09-07) **is still listed in `form.fields`**, carrying the flag. The
  projection is the whole schema, and hiding is a rendering claim rather
  than a filter: a host reads the list and filters by the flag to draw its
  own surface, and `StatifierBlocks.Editor.ConfigForm` - the package's own
  form - is the surface that skips them. Keeping them in the list is also
  what lets `ConfigForm.decode/3` preserve a hidden value, since that
  function is keyed off the fields it is handed.

  ## The readers a host asks the view model

  `find_node/2`, `parent_of/2`, `positions/1`, `sentence/1`,
  `shown_fields/1`, `fields_for/2`, `overlay_draft/2` and
  `drafted_field/2` answer questions about a built view model and derive
  nothing new. They are public because the reference embedder's Plan view -
  `statifier_examples`' read-and-edit page over these same documents, and
  the first consumer of every one of them - had written each of them out
  privately in order to draw a list of blocks at all. A fragment that
  answers a question about a document promotes; a fragment that decides how
  a page is arranged does not, which is why there is no layout mode here to
  go with them. The package's own editor calls these too, so the two
  surfaces cannot answer the same question differently.
  """

  alias StatifierBlocks.{
    Block,
    BlockType,
    CanonicalJson,
    Document,
    DocumentValidator,
    Finding,
    Palette,
    Shelf
  }

  alias StatifierBlocks.Core.Subchart

  defmodule Field do
    @moduledoc """
    One config field, its schema and its current value (ADR-0005 decision 9).

    `key` is the field's identity - the DOM id, the form param name, and
    what a `{:config, id, key}` finding anchors to. `value_path` is where
    the bytes live, and the two are the same place unless the block type
    said otherwise (ADR-0002 decision 7, amended 2026-08-27). `nil` means
    it did not; read it through `value_path/1` rather than the struct
    field, and the two cases collapse into one path.

    `hidden?` and `readonly?` are the block type's rendering claims about
    the field (ADR-0002 decision 7, amended 2026-09-07), carried here so a
    host draws its own surface from the same two booleans the package's own
    form reads rather than re-deriving them from a block type module. Both
    default to `false`.
    """

    @type t :: %__MODULE__{
            key: String.t(),
            type: BlockType.field_type(),
            label: String.t(),
            required?: boolean(),
            default: Block.json(),
            value: Block.json(),
            value_path: BlockType.value_path() | nil,
            hidden?: boolean(),
            readonly?: boolean(),
            findings: [Finding.t()]
          }

    @enforce_keys [:key, :type, :label, :required?, :default, :value]
    defstruct [
      :key,
      :type,
      :label,
      :required?,
      :default,
      :value,
      :value_path,
      hidden?: false,
      readonly?: false,
      findings: []
    ]

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

    `sentence` is this block as one line of prose (ADR-0005's 2026-09-07
    amendment): the string this block type's `sentence/1` callback
    returned for this config where it declares one and the return is
    usable, else the author's own `title` where they gave one, else the
    type's label falling back to the type name. It is resolved by
    `build/3` like every field beside it rather than being a function a
    consumer calls later, so a list view, an outline pane and a test read
    one field.

    It is a fourth thing a node carries, not a re-spelling of `title`:
    `ViewModel.title/1` keeps both its clauses and every consumer of it
    reads what it read before. It is **not** a chip - it is uncapped,
    appears in no chip list, and a card draws what it drew yesterday.

    An unresolvable block has no callback to ask and no label, so it lands
    on the type name as the document stores it: a list view draws a line
    for every block in the document and never a blank one.

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
            sentence: String.t() | nil,
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
      sentence: nil,
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
    One palette section: palette entries sharing `entry.group`, sorted by
    `entry.order` then `entry.label` (ADR-0005 decision 10's grouping
    rule).

    An entry is a block type or a **recipe** (ADR-0005 clause 1C), and it
    says which in `:kind`. `:name` is the name in whichever of the
    palette's two maps it came from - the two are separate namespaces, so
    the pair `{kind, name}` is what identifies an entry and `:name` alone
    is not. A type entry also carries `:type_name`, unchanged, because a
    type's name IS its `type_name`; a recipe carries no such key, having no
    `type_name` at all.
    """

    @type kind :: :type | :recipe

    @type entry :: %{
            required(:kind) => kind(),
            required(:name) => String.t(),
            required(:module) => module(),
            required(:entry) => BlockType.palette_entry(),
            optional(:type_name) => Block.type_name()
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
  refusal, and whatever the palette's `validators` return - the derived
  findings that are not errors.

  The document-level rules run after the per-block ones and before the
  `findings` argument (ADR-0005 clause 11t): the palette's own `singleton`
  declarations first, then each `StatifierBlocks.DocumentValidator` in the
  palette's list order. A palette declaring neither has nothing to run and
  builds exactly the view model it built before either existed.
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

  @typedoc """
  How a block in `outline/1`'s list is reached from the block above it
  (ADR-0005's 2026-09-07 amendment).

  A partition of how a block is **reached**, never a filter on which
  blocks are listed: arms, rails and trays are kinds, not omissions.
  """
  @type kind :: :step | :arm | :rail | :tray

  @doc """
  The document in reading order: one `{node, depth, kind}` per block,
  pre-order (ADR-0005's 2026-09-07 amendment).

  Pure, and a pure function of the view model alone - it reads `root` and
  walks the tree `build/3` already put in the struct, resolving nothing,
  calling no callback, consulting no palette and reading no findings.
  Calling it twice on one view model returns two identical lists.

  It exists so that the outline pane this package may grow, a host's own
  list view and a test asserting what a document says read one walk rather
  than three re-derivations of it. `Node.sentence` is the line each entry
  draws; `depth` is how far it is indented.

  **Every block appears exactly once.** The first entry is always
  `{root, 0, :step}`. A consumer wanting only the flow filters the list it
  was given: the walk hides nothing, because a walk that hides a failure
  rail is a walk a reviewer cannot trust to be the document.

  | `kind` | The slot the node's parent holds it in |
  |---|---|
  | `:step` | the parent's body, where `arrangement/1` is `:stack` |
  | `:arm` | one of the parent's body slots, where `arrangement/1` is `:fan` or `:lanes` |
  | `:rail` | a slot `rail?/1` accepts |
  | `:tray` | a slot `tray?/1` accepts |

  **Depth is block nesting depth and nothing else.** Every child is
  exactly one deeper than the node whose slot holds it, in all four rows:
  a slot is not an entry in the list and never consumes a level, so an
  arm's blocks are one deeper than their container and a rail's blocks sit
  at the same depth as that container's body blocks. The slot's identity
  is carried by `kind` instead, which is why `kind` exists rather than a
  second numeric column.

  `:step` versus `:arm` is `arrangement/1`'s question, asked once here
  rather than re-derived from a slot count, so a type declaring
  `layout: :columns` reads as arms for the same reason its slots sit side
  by side on the canvas and the two surfaces cannot drift apart.

  **Slot order is the canvas's order**: `body_slots/1` first, then the
  rails, then the trays, each group in `node.slots` order. Within a slot
  the order is `flow_children/1` then `shelf_children/1`, so a drafts
  shelf sits at the foot of its slot and takes that slot's kind like any
  other child - it is visited rather than skipped, because
  `flow_children/1` exists so a renderer can draw connectors past the
  shelf, not so a reader can be told the shelf is not in the document.
  `shelf?/1` and this list are what a consumer wanting the flow alone
  reads.

      iex> alias StatifierBlocks.{Block, Document, Palette, ViewModel}
      iex> root =
      ...>   Block.new("core.sequence",
      ...>     id: "root",
      ...>     slots: %{
      ...>       "body" => [
      ...>         Block.new("core.wait", id: "wait", config: %{"duration" => "30s"}),
      ...>         Block.new("core.send", id: "send", config: %{"event" => "order.paid"})
      ...>       ]
      ...>     }
      ...>   )
      iex> root |> Document.new() |> ViewModel.build(Palette.core(), []) |> ViewModel.outline()
      ...> |> Enum.map(fn {node, depth, kind} -> {node.block_id, depth, kind, node.sentence} end)
      [
        {"root", 0, :step, "Sequence"},
        {"wait", 1, :step, "Wait 30s"},
        {"send", 1, :step, "Send order.paid"}
      ]
  """
  @spec outline(t()) :: [{Node.t(), non_neg_integer(), kind()}]
  def outline(%__MODULE__{root: %Node{} = root}), do: outline_walk(root, 0, :step)

  @spec outline_walk(Node.t(), non_neg_integer(), kind()) ::
          [{Node.t(), non_neg_integer(), kind()}]
  defp outline_walk(%Node{} = node, depth, kind) do
    body_kind = if arrangement(node) == :stack, do: :step, else: :arm

    body = Enum.flat_map(body_slots(node), &outline_slot(&1, depth, body_kind))
    rails = node.slots |> Enum.filter(&rail?/1) |> Enum.flat_map(&outline_slot(&1, depth, :rail))
    trays = node.slots |> Enum.filter(&tray?/1) |> Enum.flat_map(&outline_slot(&1, depth, :tray))

    [{node, depth, kind} | body ++ rails ++ trays]
  end

  @spec outline_slot(Slot.t(), non_neg_integer(), kind()) ::
          [{Node.t(), non_neg_integer(), kind()}]
  defp outline_slot(%Slot{} = slot, depth, kind) do
    slot
    |> flow_children()
    |> Kernel.++(shelf_children(slot))
    |> Enum.flat_map(&outline_walk(&1, depth + 1, kind))
  end

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

  @doc """
  The node carrying `id`, or `nil` when no block in the tree does.

  The first consumer is the reference embedder's Plan view, which wrote
  this walk out privately in order to answer "which node is selected" -
  the question a view model that already holds the tree should answer
  itself. It takes either the view model or a node, so a caller holding
  a subtree can search inside it without reaching for `root` first.

      iex> alias StatifierBlocks.{Block, Document, Palette, ViewModel}
      iex> root =
      ...>   Block.new("core.sequence",
      ...>     id: "root",
      ...>     slots: %{"body" => [Block.new("core.wait", id: "wait", config: %{"duration" => "30s"})]}
      ...>   )
      iex> vm = root |> Document.new() |> ViewModel.build(Palette.core(), [])
      iex> ViewModel.find_node(vm, "wait").type
      "core.wait"
      iex> ViewModel.find_node(vm, "absent")
      nil
  """
  @spec find_node(t() | Node.t(), Block.id()) :: Node.t() | nil
  def find_node(%__MODULE__{root: root}, id), do: find_node(root, id)
  def find_node(%Node{block_id: id} = node, id), do: node

  def find_node(%Node{slots: slots}, id) do
    slots
    |> Enum.flat_map(& &1.children)
    |> Enum.find_value(fn child -> find_node(child, id) end)
  end

  @doc """
  Where the block carrying `id` sits: the `{parent block id, slot name,
  index}` its parent holds it at, or `nil`.

  The root has no position, which is what makes moving and deleting it
  refuse rather than raise - `StatifierBlocks.Edit.apply/2` refuses to
  remove the root too, and this is that refusal one step earlier, so a
  surface can draw no button that cannot work. An id no block carries is
  `nil` for the same reason.

  The tuple is `StatifierBlocks.Edit.target/0`: what this answers is
  directly what a command takes.

      iex> alias StatifierBlocks.{Block, Document, Palette, ViewModel}
      iex> root =
      ...>   Block.new("core.sequence",
      ...>     id: "root",
      ...>     slots: %{"body" => [Block.new("core.wait", id: "wait", config: %{"duration" => "30s"})]}
      ...>   )
      iex> vm = root |> Document.new() |> ViewModel.build(Palette.core(), [])
      iex> ViewModel.parent_of(vm, "wait")
      {"root", "body", 0}
      iex> ViewModel.parent_of(vm, "root")
      nil
  """
  @spec parent_of(t() | Node.t(), Block.id()) ::
          {Block.id(), Block.slot_name(), non_neg_integer()} | nil
  def parent_of(%__MODULE__{root: root}, id), do: parent_of(root, id)

  def parent_of(%Node{block_id: parent_id, slots: slots}, id) do
    Enum.find_value(slots, fn slot ->
      case Enum.find_index(slot.children, &(&1.block_id == id)) do
        nil -> Enum.find_value(slot.children, &parent_of(&1, id))
        index -> {parent_id, slot.name, index}
      end
    end)
  end

  @doc """
  Where every block sits, as one map from block id to
  `parent_of/2`'s tuple.

  `parent_of/2` asked of one block; this is the same answer for the whole
  document in one walk, which is what a surface drawing a row per block
  wants rather than a lookup per row. The root is absent from the map for
  the reason `parent_of/2` answers `nil` for it.

      iex> alias StatifierBlocks.{Block, Document, Palette, ViewModel}
      iex> root =
      ...>   Block.new("core.sequence",
      ...>     id: "root",
      ...>     slots: %{"body" => [Block.new("core.wait", id: "wait", config: %{"duration" => "30s"})]}
      ...>   )
      iex> root |> Document.new() |> ViewModel.build(Palette.core(), []) |> ViewModel.positions()
      %{"wait" => {"root", "body", 0}}
  """
  @spec positions(t() | Node.t()) ::
          %{Block.id() => {Block.id(), Block.slot_name(), non_neg_integer()}}
  def positions(%__MODULE__{root: root}), do: positions(root)
  def positions(%Node{} = root), do: collect_positions(root, %{})

  @spec collect_positions(Node.t(), %{
          Block.id() => {Block.id(), Block.slot_name(), non_neg_integer()}
        }) :: %{Block.id() => {Block.id(), Block.slot_name(), non_neg_integer()}}
  defp collect_positions(%Node{block_id: parent_id, slots: slots}, acc) do
    Enum.reduce(slots, acc, fn slot, slot_acc ->
      slot.children
      |> Enum.with_index()
      |> Enum.reduce(slot_acc, fn {child, index}, child_acc ->
        child_acc
        |> Map.put(child.block_id, {parent_id, slot.name, index})
        |> then(&collect_positions(child, &1))
      end)
    end)
  end

  @doc """
  A node's line of prose: its own `sentence`, else `title/1`.

  `Node.sentence` is the block type's own line where the type declares
  `sentence/1`, and `title/1` is the fallback this module already uses for
  a type that declares none - so the answer is never blank for a block the
  document holds. Every surface drawing a row writes this same two-clause
  fallback, and writing it once is what keeps two surfaces from naming one
  block differently.

  It is the arity that separates it from the two other `sentence`s in the
  package, and the three are deliberately distinct: this one takes a node
  and answers what to draw, `StatifierBlocks.BlockType.sentence/2` asks a
  block type for its own line, and this module's private `sentence/5` is
  where a built node's `sentence` field came from in the first place.

      iex> alias StatifierBlocks.{Block, Document, Palette, ViewModel}
      iex> root =
      ...>   Block.new("core.sequence",
      ...>     id: "root",
      ...>     slots: %{"body" => [Block.new("core.wait", id: "wait", config: %{"duration" => "30s"})]}
      ...>   )
      iex> vm = root |> Document.new() |> ViewModel.build(Palette.core(), [])
      iex> vm |> ViewModel.find_node("wait") |> ViewModel.sentence()
      "Wait 30s"
  """
  @spec sentence(Node.t()) :: String.t()
  def sentence(%Node{sentence: sentence}) when is_binary(sentence) and sentence != "",
    do: sentence

  def sentence(%Node{} = node), do: title(node)

  @doc """
  A node's fields with the hidden ones rejected, or `[]` for a node with
  no form.

  `hidden?` is a field flag the view model sets and every surface honours
  (ADR-0005 decision 11's field-flags amendment): the view model lists
  every declared field and the surface filters. Repeating that filter per
  surface is how a hidden field gets drawn once by accident, so it is
  written here once instead.
  """
  @spec shown_fields(Node.t()) :: [Field.t()]
  def shown_fields(%Node{form: %Form{fields: fields}}), do: Enum.reject(fields, & &1.hidden?)
  def shown_fields(%Node{}), do: []

  @doc """
  The config fields of the block carrying `id`, or `[]` when there is no
  such block or it has no form.

  `find_node/2` and `shown_fields/1`'s subject in one call: the list a
  form decoder needs in order to read a submitted form back into a config.
  """
  @spec fields_for(t() | Node.t(), Block.id()) :: [Field.t()]
  def fields_for(view_model_or_node, id) do
    case find_node(view_model_or_node, id) do
      %Node{form: %Form{fields: fields}} -> fields
      _no_node_or_form -> []
    end
  end

  @doc """
  One field, showing `draft`'s value where the draft has one.

  A field the draft says nothing about keeps the value the document holds,
  which is what makes a partially typed form show one changed row rather
  than a blank set. The draft is read at the field's
  `StatifierBlocks.ViewModel.Field.value_path/1`, so a field whose value
  lives inside a nested member is drafted the same way a flat one is.
  """
  @spec drafted_field(Field.t(), Block.config()) :: Field.t()
  def drafted_field(%Field{} = field, draft) when is_map(draft) do
    case BlockType.fetch_value(draft, Field.value_path(field)) do
      {:ok, value} -> %{field | value: value}
      :error -> field
    end
  end

  @doc """
  `node` with `draft`'s values over its form's fields, or the node
  unchanged when it has no form.

  This is the effective config a form shows beside a refused draft
  (ADR-0002 decision 9): a config the document never accepted, made
  visible without letting it near the document. Values only - only the
  form is touched, and `slots/1` is never called on a draft, which is the
  promise decision 6 is owed. This function states no opinion about
  whether the draft validates; the findings half is `overlay_findings/2`,
  and a refused `StatifierBlocks.Edit.Session.change_config/3` has already
  put the findings to hand it in the session's `draft_findings`.

  `nil` in, `nil` out, so a caller that has not resolved a selection yet
  can pipe through it.
  """
  @spec overlay_draft(Node.t() | nil, Block.config()) :: Node.t() | nil
  def overlay_draft(nil, _draft), do: nil
  def overlay_draft(%Node{form: nil} = node, _draft), do: node

  def overlay_draft(%Node{form: %Form{} = form} = node, draft) when is_map(draft) do
    %{node | form: %{form | fields: Enum.map(form.fields, &drafted_field(&1, draft))}}
  end

  @doc """
  `node` with `findings` over its form's fields, or the node unchanged
  when it has no form.

  The findings half of the pair `overlay_draft/2` opens, and the reason a
  surface no longer re-runs `c:StatifierBlocks.BlockType.validate_config/1`
  on a refused draft: `findings` are the
  `t:StatifierBlocks.BlockType.finding/0` pairs the refusal itself carried,
  which a refused `StatifierBlocks.Edit.Session.change_config/3` keeps in
  the session's `draft_findings` under the block's id.

  Routing is decision 11's, asked of the form rather than of the document:
  a finding whose key names a field on this form is that field's, and one
  whose key names no field lands in `form.unrouted`, where the form draws
  it at the head. The unrouted ones are ordered by key so a redraw does
  not move them. Every field is written, so a field the findings say
  nothing about is left with none rather than with the document's - the
  findings shown beside a draft are about the draft.

  `nil` in, `nil` out, so a caller that has not resolved a selection yet
  can pipe through it.

  ## Examples

      iex> alias StatifierBlocks.ViewModel
      iex> alias StatifierBlocks.ViewModel.{Field, Form, Node}
      iex> field = %Field{key: "after", type: :duration, label: "After", required?: true, default: nil, value: "nope"}
      iex> node = %Node{block_id: "blk_ONE", type: "core.delay", type_version: 1, status: :ok, form: %Form{fields: [field]}}
      iex> overlaid = ViewModel.overlay_findings(node, [{"after", "is not a duration"}, {"gone", "no such field"}])
      iex> Enum.map(hd(overlaid.form.fields).findings, & &1.message)
      ["is not a duration"]
      iex> Enum.map(overlaid.form.unrouted, & &1.message)
      ["no such field"]
  """
  @spec overlay_findings(Node.t() | nil, [BlockType.finding()]) :: Node.t() | nil
  def overlay_findings(nil, _findings), do: nil
  def overlay_findings(%Node{form: nil} = node, _findings), do: node

  def overlay_findings(%Node{block_id: id, form: %Form{} = form} = node, findings)
      when is_list(findings) do
    by_key =
      Enum.group_by(
        findings,
        fn {key, _message} -> key end,
        fn {key, message} -> Finding.new({:config, id, key}, :config, message) end
      )

    keys = MapSet.new(form.fields, & &1.key)

    fields =
      Enum.map(form.fields, fn field ->
        %{field | findings: Map.get(by_key, field.key, [])}
      end)

    unrouted =
      by_key
      |> Enum.reject(fn {key, _findings} -> MapSet.member?(keys, key) end)
      |> Enum.sort()
      |> Enum.flat_map(fn {_key, key_findings} -> key_findings end)

    %{node | form: %{form | fields: fields, unrouted: unrouted}}
  end

  @spec derived_findings(Document.t(), Palette.t(), BlockType.chip_labels()) :: [Finding.t()]
  defp derived_findings(%Document{} = document, %Palette{} = palette, labels) do
    per_block =
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

    per_block ++ document_rule_findings(document, palette)
  end

  # ADR-0005 clause 11t. The document-level rules, in one arm: the package's
  # own `singleton` rule first, then the palette's validators in list order,
  # and every one of them stating its findings in the same
  # `StatifierBlocks.DocumentValidator.finding_spec/0` vocabulary through the
  # same normalizer. There is one mechanism here rather than two - which is
  # the point of running the declared rule on the seam the written ones use -
  # and the source stamp is what separates them, because that is what the
  # difference actually is: `:config` says a declared shape is not satisfied,
  # `:lint` says the editor applied a rule (`11r`). Their severities differ
  # for the same reason: a declared shape not being satisfied is decision
  # 11's `:error`, and a host's rule cannot make a document not compile.
  #
  # `singleton` is not itself a `DocumentValidator`: the callback is handed
  # the document and only the document (`11q`), and this rule reads the
  # palette, which is where a host declared it.
  @spec document_rule_findings(Document.t(), Palette.t()) :: [Finding.t()]
  defp document_rule_findings(%Document{} = document, %Palette{} = palette) do
    document
    |> singleton_specs(palette)
    |> normalize_specs(:config, :error)
    |> Kernel.++(validator_findings(document, palette))
  end

  # Every validator runs, in the palette's list order, and a later one does
  # not replace an earlier one - the list is not a lookup. The order is fixed
  # by the palette rather than by a map's iteration for the reason
  # `singleton_specs/2` sorts: a findings list whose order moved between
  # builds would be a rendering that moved for no reason the author can see.
  #
  # A raise inside a host's callback is deliberately not rescued (`11r`):
  # that is the host's bug, and swallowing it would hide it at the only
  # moment it is visible.
  @spec validator_findings(Document.t(), Palette.t()) :: [Finding.t()]
  defp validator_findings(%Document{} = document, %Palette{validators: validators}) do
    Enum.flat_map(validators, fn module ->
      document |> module.validate_document() |> normalize_specs(:lint, :warning)
    end)
  end

  # Decision 10's normalizer discipline, applied to a rule's return value
  # (`11r`): a term that is not a list, and a member that is neither
  # `{anchor, message}` nor `{anchor, message, opts}`, is read as NO finding.
  # Nothing raises here and nothing is refused back at the caller. A
  # `:severity` outside the enum falls back to the default for the same
  # reason - it is a value this function did not recognise, and the finding
  # it belongs to still says something true about the document.
  @spec normalize_specs(term(), Finding.source(), Finding.severity()) :: [Finding.t()]
  defp normalize_specs(specs, source, default_severity) when is_list(specs) do
    Enum.flat_map(specs, &normalize_spec(&1, source, default_severity))
  end

  defp normalize_specs(_not_a_list, _source, _default_severity), do: []

  @spec normalize_spec(term(), Finding.source(), Finding.severity()) :: [Finding.t()]
  defp normalize_spec({anchor, message}, source, default_severity),
    do: spec_finding(anchor, message, source, default_severity)

  defp normalize_spec({anchor, message, opts}, source, default_severity) when is_list(opts) do
    if Keyword.keyword?(opts) do
      spec_finding(anchor, message, source, spec_severity(opts, default_severity))
    else
      []
    end
  end

  defp normalize_spec(_other, _source, _default_severity), do: []

  @severities [:error, :warning, :info]

  @spec spec_severity(keyword(), Finding.severity()) :: Finding.severity()
  defp spec_severity(opts, default_severity) do
    case Keyword.get(opts, :severity, default_severity) do
      severity when severity in @severities -> severity
      _unrecognised -> default_severity
    end
  end

  @spec spec_finding(term(), term(), Finding.source(), Finding.severity()) :: [Finding.t()]
  defp spec_finding(anchor, message, source, severity) when is_binary(message) do
    if anchor?(anchor) do
      [Finding.new(anchor, source, message, severity: severity)]
    else
      []
    end
  end

  defp spec_finding(_anchor, _message, _source, _severity), do: []

  # The anchor enum decision 11 has and no fourth member (`11s`). An anchor
  # naming an id the document does not hold is NOT checked here: `build/3`
  # already splits those into `orphan_findings`, which is the existing safety
  # net rather than a new refusal.
  @spec anchor?(term()) :: boolean()
  defp anchor?({:block, id}) when is_binary(id), do: true
  defp anchor?({:slot, id, name}) when is_binary(id) and is_binary(name), do: true
  defp anchor?({:config, id, key}) when is_binary(id) and is_binary(key), do: true
  defp anchor?(_other), do: false

  # ADR-0005 clause 11o. The declarations come from the palette rather than
  # from the document, which is what makes the zero case expressible: a type
  # no block in the document names still draws its finding, because the
  # palette is where the host said the document needs one. Sorted by
  # `type_name` so two palettes with the same entries derive the same list
  # in the same order - `palette.types` is a map, and a finding list whose
  # order depended on map iteration would be a rendering that moved for no
  # reason the author can see.
  @spec singleton_specs(Document.t(), Palette.t()) :: [DocumentValidator.finding_spec()]
  defp singleton_specs(%Document{} = document, %Palette{types: types} = palette) do
    blocks = Document.blocks(document)
    head = head_of_root(document, palette)

    types
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.flat_map(fn {type_name, module} ->
      case BlockType.singleton(palette_entry_with_defaults(module, type_name)) do
        nil -> []
        declared -> singleton_spec(document, blocks, type_name, module, declared, head)
      end
    end)
  end

  @spec singleton_spec(
          Document.t(),
          [Block.t()],
          Block.type_name(),
          module(),
          BlockType.singleton(),
          {Block.slot_name() | nil, Block.t() | nil}
        ) :: [DocumentValidator.finding_spec()]
  defp singleton_spec(document, blocks, type_name, module, declared, head) do
    label = singleton_label(module, type_name)
    anchor = {:block, document.root.id}

    case Enum.filter(blocks, &(&1.type == type_name)) do
      [] ->
        [{anchor, "this document needs a #{label}, and holds none"}]

      [only] ->
        misplaced_spec(document, anchor, label, declared, head, only)

      many ->
        [
          {anchor,
           "this document holds #{length(many)} #{label} blocks, and may hold exactly one"}
        ]
    end
  end

  # `:anywhere` is satisfied by the count alone; only `:head` reads a
  # position. The message names the slot it measured against, because a root
  # type declaring more than one slot leaves "the root's first slot"
  # ambiguous to everyone but this function.
  @spec misplaced_spec(
          Document.t(),
          Finding.anchor(),
          String.t(),
          BlockType.singleton(),
          {Block.slot_name() | nil, Block.t() | nil},
          Block.t()
        ) :: [DocumentValidator.finding_spec()]
  defp misplaced_spec(_document, _anchor, _label, :anywhere, _head, _only), do: []

  defp misplaced_spec(document, anchor, label, :head, {slot_name, head_block}, only) do
    if head_block && head_block.id == only.id do
      []
    else
      [
        {anchor,
         "a #{label} belongs first in #{slot_label(slot_name)}, " <>
           "and this document's is #{where_is(document, only)}"}
      ]
    end
  end

  # The head position clause 10z names: index 0 of the root's first slot.
  # "First" is the root type's own declaration order (`slots/1`), and a root
  # that declares nothing - or does not resolve - falls back to the
  # alphabetically first slot name it carries, the order
  # `build_resolved_node/4` already puts undeclared slots in.
  @spec head_of_root(Document.t(), Palette.t()) ::
          {Block.slot_name() | nil, Block.t() | nil}
  defp head_of_root(%Document{root: root}, %Palette{} = palette) do
    declared =
      case Palette.resolve(palette, root) do
        {:ok, ref, resolved} ->
          ref |> Palette.call(:slots, [resolved.config], []) |> Enum.map(&elem(&1, 0))

        {:error, _reason} ->
          []
      end

    slot_name = List.first(declared) || first_carried_slot(root)

    {slot_name, slot_name && root.slots |> Map.get(slot_name, []) |> List.first()}
  end

  @spec first_carried_slot(Block.t()) :: Block.slot_name() | nil
  defp first_carried_slot(%Block{slots: slots}) do
    slots |> Map.keys() |> Enum.sort() |> List.first()
  end

  @spec slot_label(Block.slot_name() | nil) :: String.t()
  defp slot_label(nil), do: "the root's first slot, which this root declares and carries none of"
  defp slot_label(name), do: ~s(the root's "#{name}" slot)

  @spec where_is(Document.t(), Block.t()) :: String.t()
  defp where_is(%Document{root: root} = document, %Block{} = block) do
    case Document.fetch_path(document, block.id) do
      {:ok, []} ->
        "the root itself"

      {:ok, path} ->
        {parent_id, slot_name, index} = List.last(path)
        whose = if parent_id == root.id, do: "the root's", else: "another block's"
        ~s(at position #{index + 1} of #{whose} "#{slot_name}" slot)

      :error ->
        "elsewhere in the document"
    end
  end

  # The name the finding calls the type by: the palette entry's label, or
  # the raw `type_name` when it declares none - the same fallback every
  # other reader of a palette entry uses.
  @spec singleton_label(module(), Block.type_name()) :: String.t()
  defp singleton_label(module, type_name) do
    module |> palette_entry_with_defaults(type_name) |> Map.get(:label) || type_name
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
      {:ok, ref, resolved} ->
        entry = palette_entry_with_defaults(ref, block.type)

        title_override(Palette.call(ref, :config_schema, [resolved.config], []), resolved.config) ||
          Map.get(entry, :label) || block.type

      # An unresolvable block draws its type name and nothing else
      # (`build_unresolvable_node/3` has no schema to read a title out of),
      # so that is its label here too.
      {:error, _reason} ->
        block.type
    end
  end

  @typedoc """
  What a host says each of its stored documents finishes with: the finals a
  compile with `StatifierBlocks.Compiler`'s `:child_use` option emits for
  that document, keyed by the document id an author types into a
  `core.subchart`'s `chart` field.
  """
  @type chart_outcomes :: %{optional(String.t()) => [String.t()]}

  @doc """
  The disagreements between what a `core.subchart` declares in `outcomes`
  and what the host says the chart it names actually finishes with
  (sb-r4w7).

  It is a **separate pass** rather than part of `build/3` for the reason
  `StatifierBlocks.Datamodel.findings/4` is: `chart_outcomes` is the
  host's input, not the document's, and the projection stays a function of
  the document plus the palette. The result goes in through the same
  caller-findings seam every other supplied finding uses, so there is one
  routing path and one place it is tested.

  Three rules, and the first is the one that keeps it quiet:

    * **Unknown is not disagreement.** A `chart` the map says nothing
      about produces nothing, and so does an entry holding an empty list -
      an empty list is the absence of knowledge about a chart's finals,
      not the claim that it has none. ADR-0005 amendment `11f` takes the
      same posture for a `nil` datamodel, for the same reason: a host that
      has not answered has not disagreed.
    * **The author's own list is what is compared.** `child_outcomes/1`,
      not `outcome_names/1`: the appended `error` is ADR-0068's failure
      event rather than a `<final>` the child reports.
    * **It is a `:warning`, never an error.** The document compiles either
      way. What a mismatch costs is a conditioned `done.invoke` transition
      that can never match - a dead routing arm - which is exactly the
      "compiles, and may not behave as intended" `:warning` names. The
      source is `:lint` for the reason `summary_findings/4` above is one:
      the rule is this package's reading of a host value, not the block
      type's `validate_config/1`, which cannot read the chart at all.

  Anchored `{:config, block_id, "outcomes"}`, so it renders under the
  field the author would fix it in.
  """
  @spec outcome_findings(Document.t(), Palette.t(), chart_outcomes()) :: [Finding.t()]
  def outcome_findings(%Document{} = document, %Palette{} = palette, chart_outcomes)
      when is_map(chart_outcomes) and map_size(chart_outcomes) > 0 do
    document
    |> Document.blocks()
    |> Enum.flat_map(&subchart_outcome_findings(&1, palette, chart_outcomes))
  end

  def outcome_findings(_document, _palette, _chart_outcomes), do: []

  # Gated on the module rather than on the type name: a host palette maps
  # whatever name it likes onto this module, and it is this module's reading
  # of the field - `child_outcomes/1` - that the comparison is made with.
  @spec subchart_outcome_findings(Block.t(), Palette.t(), chart_outcomes()) :: [Finding.t()]
  defp subchart_outcome_findings(%Block{id: id} = block, palette, chart_outcomes) do
    with {:ok, Subchart, %Block{config: config}} <- resolve_subchart(palette, block),
         chart when is_binary(chart) <- Map.get(config, "chart"),
         [_first | _rest] = finals <- chart_finals(chart_outcomes, chart) do
      disagreement(id, chart, Subchart.child_outcomes(config), finals)
    else
      _no_answer_about_this_chart -> []
    end
  end

  @spec resolve_subchart(Palette.t(), Block.t()) :: {:ok, module(), Block.t()} | :error
  defp resolve_subchart(palette, block) do
    case Palette.resolve(palette, block) do
      {:ok, module, resolved} -> {:ok, module, resolved}
      {:error, _reason} -> :error
    end
  end

  # Total in the value as well as the key: a host that hands over something
  # other than a list of names has said nothing this pass can read, and
  # raising on it would take the whole editor down over a seam value.
  @spec chart_finals(chart_outcomes(), String.t()) :: [String.t()] | nil
  defp chart_finals(chart_outcomes, chart) do
    case Map.get(chart_outcomes, chart) do
      names when is_list(names) -> Enum.filter(names, &is_binary/1)
      _not_a_list -> nil
    end
  end

  @spec disagreement(Block.id(), String.t(), [String.t()], [String.t()]) :: [Finding.t()]
  defp disagreement(block_id, chart, declared, finals) do
    unmatched = declared -- finals
    undeclared = finals -- declared

    case disagreement_message(chart, unmatched, undeclared) do
      nil ->
        []

      message ->
        [Finding.new({:config, block_id, "outcomes"}, :lint, message, severity: :warning)]
    end
  end

  # Both directions, in one finding rather than one per name: they are one
  # observation about one field, and an author reading four findings under
  # one input is reading the same sentence four times.
  @spec disagreement_message(String.t(), [String.t()], [String.t()]) :: String.t() | nil
  defp disagreement_message(_chart, [], []), do: nil

  defp disagreement_message(chart, unmatched, undeclared) do
    [
      unmatched != [] && "#{chart} does not finish with #{names(unmatched)}",
      undeclared != [] && "#{chart} also finishes with #{names(undeclared)}"
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.join("; ")
  end

  @spec names([String.t()]) :: String.t()
  defp names(list), do: Enum.map_join(list, ", ", &inspect/1)

  # `validate_config/1`, and the one shared check a block type does not
  # implement: a `{:type_expr, opts}` field whose stored value is not an arm
  # its declaration admits. The compiler routes the same list into its
  # `:config` stage (ADR-0002 decision 7, amended 2026-09-06), so the finding
  # an author reads under the control and the one a compile refuses on are
  # one finding rather than two implementations of it.
  @spec config_findings(Block.id(), Palette.type_ref(), Block.config()) :: [Finding.t()]
  defp config_findings(block_id, ref, config) do
    own =
      case Palette.call(ref, :validate_config, [config], :ok) do
        :ok -> []
        {:error, findings} -> findings
      end

    Enum.map(BlockType.type_expr_findings(ref, config) ++ own, fn {key, message} ->
      Finding.new({:config, block_id, key}, :config, message)
    end)
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

  @spec build_resolved_node(Block.t(), Palette.type_ref(), Block.t(), ctx()) :: Node.t()
  defp build_resolved_node(
         %Block{} = block,
         ref,
         %Block{config: config},
         {_palette, by_block, labels} = ctx
       ) do
    own_findings = Map.get(by_block, block.id, [])
    declared = Palette.call(ref, :slots, [config], [])
    declared_names = MapSet.new(declared, fn {name, _arity, _label} -> name end)

    extra_names =
      block.slots
      |> Map.keys()
      |> Enum.sort()
      |> Enum.reject(&MapSet.member?(declared_names, &1))

    slot_names = MapSet.union(declared_names, MapSet.new(extra_names))
    schema = Palette.call(ref, :config_schema, [config], [])
    schema_keys = MapSet.new(schema, & &1.key)

    {block_findings, slot_findings, config_findings, unrouted} =
      route_own_findings(own_findings, schema_keys, slot_names)

    entry = palette_entry_with_defaults(ref, block.type)

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
    title = title_override(schema, config)

    %Node{
      block_id: block.id,
      type: block.type,
      type_version: block.type_version,
      status: :ok,
      entry: entry,
      title: title,
      sentence: sentence(ref, config, entry, title, block.type),
      summary: BlockType.summary(ref, config, labels),
      summary_titles: BlockType.summary_titles(ref, config, labels),
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
      # No module to ask and no label to fall back to, so the chain's last
      # arm answers: the type name as the document stores it, which
      # `default_entry/1` has already put on the entry as its label.
      sentence: block.type,
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

  # `default:` is required of a declaration and read permissively anyway. The
  # compiler's config stage refuses a datamodel-path field that omits it, and
  # that is where a malformed declaration is meant to be caught - but the
  # editor builds a view model for documents that never reach a compile, so
  # destructuring the key here made a declaration defect surface as a
  # `FunctionClauseError` from inside the build instead of as a rendered
  # control the author can still read. A field whose declaration omits the
  # key renders with no default, exactly as one declaring `default: nil` does.
  @spec build_fields([BlockType.field_decl()], Block.config(), %{
          optional(String.t()) => [Finding.t()]
        }) ::
          [Field.t()]
  defp build_fields(schema, config, config_findings) do
    Enum.map(schema, fn %{key: key, type: type, label: label, required?: required?} = decl ->
      path = BlockType.value_path(decl)
      default = Map.get(decl, :default)

      %Field{
        key: key,
        type: type,
        label: label,
        required?: required?,
        default: default,
        value_path: Map.get(decl, :value_path),
        hidden?: Map.get(decl, :hidden?) == true,
        readonly?: Map.get(decl, :readonly?) == true,
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
  # ADR-0005's 2026-09-07 three-way chain. `declares?/1` is asked
  # separately from the reader's answer because the two records draw the
  # line in different places and both lines matter: a type that declares
  # NOTHING may land on the author's `title` (ADR-0005 row two), while a
  # declared callback that raises, throws, exits or answers something
  # unusable lands on the type's label and never on the title (ADR-0002
  # row three, restated in ADR-0005 as "never the author's `title`"). The
  # reader answers a string in both cases, so declaredness is the only
  # thing that separates them.
  @spec sentence(
          module(),
          Block.config(),
          BlockType.palette_entry(),
          String.t() | nil,
          Block.type_name()
        ) ::
          String.t()
  defp sentence(module, config, entry, title, type) do
    label = Map.get(entry, :label) || type

    if declares_sentence?(module) do
      BlockType.sentence(module, config) || label
    else
      title || label
    end
  end

  @spec declares_sentence?(Palette.type_ref()) :: boolean()
  defp declares_sentence?(ref) do
    Palette.declares?(ref, :sentence, 1)
  end

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

  @spec palette_entry_with_defaults(Palette.type_ref(), Block.type_name()) ::
          BlockType.palette_entry()
  defp palette_entry_with_defaults(ref, type_name) do
    raw = Palette.call(ref, :palette_entry, [], %{})

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

  # `palette.types` AND `palette.recipes`, each carrying its own defaulted
  # `palette_entry/0`, grouped by `entry.group` and sorted group name ->
  # `order` -> `label` (ADR-0005 decision 10's grouping rule).
  #
  # Recipes are grouped and sorted with types rather than apart from them:
  # clause 2C says a recipe draws as an entry, and where entries sit
  # relative to one another is decision 10's `group` and `order` keys doing
  # what they already do.
  @spec palette_groups(Palette.t()) :: [PaletteGroup.t()]
  defp palette_groups(%Palette{types: types, recipes: recipes}) do
    entries =
      Enum.map(types, fn {type_name, module} ->
        %{
          kind: :type,
          name: type_name,
          type_name: type_name,
          module: module,
          entry: palette_entry_with_defaults(module, type_name)
        }
      end) ++
        Enum.map(recipes, fn {name, module} ->
          %{
            kind: :recipe,
            name: name,
            module: module,
            entry: palette_entry_with_defaults(module, name)
          }
        end)

    entries
    |> Enum.group_by(& &1.entry.group)
    |> Enum.sort_by(fn {group, _entries} -> group end)
    |> Enum.map(fn {group, grouped} ->
      %PaletteGroup{
        name: group,
        entries: Enum.sort_by(grouped, &{&1.entry.order, &1.entry.label})
      }
    end)
  end
end
