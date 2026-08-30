defmodule StatifierBlocks.Shell do
  @moduledoc """
  The shell's arrangement, as pure functions (ADR-0005, the 2026-08-29 shell
  amendment: rulings 1A, 2A, 3A, 7A, 8A).

  The amendment records where each region of the editor goes and what kind of
  content it holds. Almost none of that is markup. Which zoom step a "+"
  reaches, how deep the tree is, which of five states the drawer is in, which
  block ids the drawer's index page offers, and which of a block's fields are
  conditions are all questions with answers, and every one of them is decided
  here rather than in a `~H` template - the same split decision 13 draws and
  the same reason: a template is testable only with LiveView present, and
  these answers are the part worth testing.

  So this module is `lib/statifier_blocks/`, not `lib/statifier_blocks/editor/`.
  Nothing in it sits behind the LiveView-presence guard the editor's own
  modules are wrapped in, and the headless suite exercises all of it
  (ADR-0005 decision 1).

  ## The drawer is five states, not a boolean

  `drawer_view/1` is the whole of 2A that is not CSS. A drawer is never
  open-or-gone: collapsed it is a strip carrying a title and a count, and open
  with nothing to show it is an index page listing the blocks that do own a
  table. Both of those are states an author reaches through a sequence of
  gestures rather than by looking at a screenshot, which is why they are
  computed by a function with a return value instead of by three `:if`
  attributes.

  The drawer does not own a selection. Its subject is the selected block and
  it follows the canvas, because a drawer that pinned its own subject would be
  a second cursor in the editor.

  ## Fixtures arrive built

  `fixtures` is `%{block_id => [TruthTable.t()]}`, or `nil` for *no fixtures
  source* - which is a different state from a source that holds nothing, and
  the strip says `(0)` for both while the drawer still exists. This package
  deliberately does not invent a fixture-bundle format: ADR-0002 decision 9
  puts that convention in statifier-ui, so what crosses this seam is tables a
  host already built with `StatifierBlocks.Predicates.TruthTable.build/2`.
  """

  alias StatifierBlocks.{Block, BlockType, Finding, ViewModel}
  alias StatifierBlocks.Predicates.TruthTable

  @typedoc "Truth tables a host supplies, keyed by the block they describe."
  @type fixtures :: %{optional(Block.id()) => [TruthTable.t()]} | nil

  @typedoc "Which of the inspector's three tabs is showing (3A)."
  @type inspector_tab :: :config | :findings | :condition

  @typedoc """
  Which of the drawer's tabs is showing (1A, and the R4 ruling of
  2026-08-29 that put document findings here).
  """
  @type drawer_tab :: :tables | :findings

  @typedoc "One entry in the drawer's tab strip: what it is called and how much it holds."
  @type drawer_tab_entry :: %{id: drawer_tab(), title: String.t(), count: non_neg_integer()}

  @typedoc "What the drawer is showing, from its own flag, its tab and the selection."
  @type drawer :: %{
          open?: boolean(),
          tab: drawer_tab(),
          tabs: [drawer_tab_entry()],
          status: :closed | :no_fixtures | :no_selection | :none_for_block | :ready,
          subject_id: Block.id() | nil,
          tables: [TruthTable.t()],
          findings: [Finding.t()],
          orphans: MapSet.t(Finding.t()),
          count: non_neg_integer(),
          jumps: [Block.id()],
          title: String.t()
        }

  # A fixed ladder rather than a multiplier, so "+" from any state lands
  # somewhere a second author would also land, and so the percentage in the
  # toolbar is a round number an author can say out loud.
  @zoom_steps [50, 67, 80, 90, 100, 110, 125, 150, 175, 200]
  @default_zoom 100

  @inspector_tabs [:config, :findings, :condition]

  # Tab order, and it is also the order the strip resolves an unchosen tab in
  # (see `drawer_view/1`). Truth tables first because they are what 2A shipped
  # the drawer for; findings second because R4 moved them here.
  @drawer_tabs [:tables, :findings]

  @drawer_titles %{tables: "Truth tables", findings: "Findings"}

  # Rem, and the drawer's own. The floor is a strip plus one row of a table -
  # below it the drawer is open and shows nothing, which is a worse state than
  # collapsed - and the ceiling leaves the canvas taller than the drawer.
  @min_height 6.0
  @max_height 32.0
  @default_height 14.0

  @doc "The zoom ladder the toolbar steps along, ascending."
  @spec zoom_steps() :: [pos_integer()]
  def zoom_steps, do: @zoom_steps

  @doc "100%, where the canvas opens."
  @spec default_zoom() :: pos_integer()
  def default_zoom, do: @default_zoom

  @doc """
  The nearest ladder step to `percent`.

  Total, because the value can arrive from a `phx-value-` attribute and the
  DOM is not a trusted source: anything unreadable resolves to the default
  rather than raising or leaving the canvas at a size no control can undo.
  """
  @spec clamp_zoom(term()) :: pos_integer()
  def clamp_zoom(percent) when is_integer(percent),
    do: Enum.min_by(@zoom_steps, &abs(&1 - percent))

  def clamp_zoom(percent) when is_binary(percent) do
    case Integer.parse(percent) do
      {value, _rest} -> clamp_zoom(value)
      :error -> @default_zoom
    end
  end

  def clamp_zoom(_other), do: @default_zoom

  @doc "One step up the ladder, or the top of it."
  @spec zoom_in(term()) :: pos_integer()
  def zoom_in(percent) do
    current = clamp_zoom(percent)
    Enum.find(@zoom_steps, List.last(@zoom_steps), &(&1 > current))
  end

  @doc "One step down the ladder, or the bottom of it."
  @spec zoom_out(term()) :: pos_integer()
  def zoom_out(percent) do
    current = clamp_zoom(percent)

    @zoom_steps
    |> Enum.reverse()
    |> Enum.find(hd(@zoom_steps), &(&1 < current))
  end

  @doc """
  How many blocks the tree holds, the root included.

  The toolbar's count, and the reason it is here rather than inline: it is a
  fold over the same recursion `depth/1` walks, and both are read once per
  render over a tree that can be thousands of nodes.
  """
  @spec block_count(ViewModel.Node.t()) :: pos_integer()
  def block_count(%ViewModel.Node{slots: slots}) do
    Enum.reduce(slots, 1, fn slot, acc ->
      acc + Enum.reduce(slot.children, 0, &(block_count(&1) + &2))
    end)
  end

  @doc """
  How deep the tree nests, the root counting as 1.

  Depth is a document metric and not a layout one - the canvas draws columns
  from slot metadata rather than from depth (decision 10) - so this is what
  the toolbar reports and nothing reads it to decide a style.
  """
  @spec depth(ViewModel.Node.t()) :: pos_integer()
  def depth(%ViewModel.Node{slots: slots}) do
    slots
    |> Enum.flat_map(& &1.children)
    |> Enum.map(&depth/1)
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end

  @doc """
  The drawer's height in rem, clamped to the band the layout can hold.

  Total for `clamp_zoom/1`'s reason and one more: this value round-trips
  through a **host**. 2A puts the remembered height on the host's side, so the
  number arriving on mount is whatever the host stored last time, and a host
  that stored `nil`, a string, or a value from an older band gets a drawer
  rather than a crash.
  """
  @spec clamp_height(term()) :: float()
  def clamp_height(rem) when is_number(rem),
    do: rem |> max(@min_height) |> min(@max_height) |> :erlang.float()

  def clamp_height(rem) when is_binary(rem) do
    case Float.parse(rem) do
      {value, _rest} -> clamp_height(value)
      :error -> @default_height
    end
  end

  def clamp_height(_other), do: @default_height

  @doc "The height band the resize control offers: `{min, max, default}` in rem."
  @spec height_band() :: {float(), float(), float()}
  def height_band, do: {@min_height, @max_height, @default_height}

  @doc "The inspector's three tabs, in the order 3A lists them."
  @spec inspector_tabs() :: [inspector_tab()]
  def inspector_tabs, do: @inspector_tabs

  @doc """
  The tab `value` names, or `:config`.

  The tab arrives from a `phx-value-tab` attribute, so an unknown one is a
  crafted payload rather than a bug, and the answer to it is the first tab.
  """
  @spec inspector_tab(term()) :: inspector_tab()
  def inspector_tab(value) when value in @inspector_tabs, do: value

  def inspector_tab(value) when is_binary(value) do
    Enum.find(@inspector_tabs, :config, &(Atom.to_string(&1) == value))
  end

  def inspector_tab(_other), do: :config

  @doc "The drawer's tabs, in the order the strip lists them."
  @spec drawer_tabs() :: [drawer_tab()]
  def drawer_tabs, do: @drawer_tabs

  @doc """
  The drawer tab `value` names, or `:tables`.

  The same shape as `inspector_tab/1` and for the same reason: the tab arrives
  from a `phx-value-tab` attribute, so an unknown one is a crafted payload
  rather than a bug, and the answer to it is the first tab.
  """
  @spec drawer_tab(term()) :: drawer_tab()
  def drawer_tab(value) when value in @drawer_tabs, do: value

  def drawer_tab(value) when is_binary(value) do
    Enum.find(@drawer_tabs, :tables, &(Atom.to_string(&1) == value))
  end

  def drawer_tab(_other), do: :tables

  @doc "The title a drawer tab carries, on the strip and on the tab itself."
  @spec drawer_title(drawer_tab()) :: String.t()
  def drawer_title(tab) when tab in @drawer_tabs, do: Map.fetch!(@drawer_titles, tab)

  @doc """
  Every finding about the selected block, in one list (3A).

  3A's rule is that the inspector is about the selected block and the document
  goes to the drawer, so this is deliberately narrower than
  `ViewModel.findings` - it is the block's own findings, its slots' findings,
  and the findings routed to its form's fields. The document-level panel
  decision 13 names is untouched and still shows everything.

  Not the subtree: a container whose child has a finding is not itself the
  thing to fix, and `ViewModel.Node.findings_count` already carries the
  subtree number for the badge that wants it.
  """
  @spec block_findings(ViewModel.Node.t() | nil) :: [StatifierBlocks.Finding.t()]
  def block_findings(nil), do: []

  def block_findings(%ViewModel.Node{findings: findings, slots: slots, form: form}) do
    findings ++ Enum.flat_map(slots, & &1.findings) ++ form_findings(form)
  end

  @spec form_findings(ViewModel.Form.t() | nil) :: [StatifierBlocks.Finding.t()]
  defp form_findings(nil), do: []

  defp form_findings(%ViewModel.Form{fields: fields, unrouted: unrouted}),
    do: Enum.flat_map(fields, & &1.findings) ++ unrouted

  @doc """
  The selected block's condition-bearing fields, in form order.

  A condition is an `:expression` field and nothing else identifies one:
  `core.branch` keys one per arm by the arm's slot name and reads it through
  `value_path: ["arms", i, "cond"]` (ADR-0002 decision 10), and a host type
  declaring `:expression` gets the same treatment without the editor learning
  its name. That is decision 2's rule - the editor never branches on a type -
  applied to the Condition tab.
  """
  @spec condition_fields(ViewModel.Form.t() | nil) :: [ViewModel.Field.t()]
  def condition_fields(nil), do: []

  def condition_fields(%ViewModel.Form{fields: fields}),
    do: Enum.filter(fields, &condition?/1)

  @spec condition?(ViewModel.Field.t()) :: boolean()
  defp condition?(%ViewModel.Field{type: :expression}), do: true
  defp condition?(%ViewModel.Field{type: {:list, :expression}}), do: true
  defp condition?(%ViewModel.Field{type: _other}), do: false

  @doc "The condition source a field carries, as a string a template can render."
  @spec condition_source(ViewModel.Field.t()) :: String.t()
  def condition_source(%ViewModel.Field{value: value}) when is_binary(value), do: value
  def condition_source(%ViewModel.Field{value: nil}), do: ""
  def condition_source(%ViewModel.Field{value: value}), do: to_string(value)

  @doc """
  The label of the slot the block carrying `block_id` sits in.

  `"root"` for the document's own root, which sits in no slot, and `nil` for
  an id no node in `root` carries - a selection that went away between two
  builds reaches that, and it is the same answer as no selection at all.

  It is the slot's **label**, not its name, for the reason the inspector's
  header status reads a type's label: both are the vocabulary the canvas
  already shows the author, and a raw `arm_approved` beside a card reading
  `When approved` is the editor naming one thing two ways.

  Here rather than on `ViewModel.Node` because a node does not know where it
  sits - the containment is the parent's, and a field duplicating it on every
  child is a second copy of the tree's shape that a re-parenting edit has to
  remember to update.
  """
  @spec slot_label(ViewModel.Node.t(), Block.id() | nil) :: String.t() | nil
  def slot_label(_root, nil), do: nil
  def slot_label(%ViewModel.Node{block_id: id}, id), do: "root"
  def slot_label(%ViewModel.Node{} = root, id), do: find_slot_label(root, id)

  @spec find_slot_label(ViewModel.Node.t(), Block.id()) :: String.t() | nil
  defp find_slot_label(%ViewModel.Node{slots: slots}, id) do
    Enum.find_value(slots, fn %ViewModel.Slot{} = slot ->
      if Enum.any?(slot.children, &(&1.block_id == id)),
        do: slot.label,
        else: Enum.find_value(slot.children, &find_slot_label(&1, id))
    end)
  end

  @typedoc """
  Where an armed insertion would land, in the two names the author already
  reads off the canvas: the slot's label and the holding block's title.
  """
  @type insert_target :: %{slot: String.t(), parent: String.t()}

  @doc """
  The names of the position a palette pick would insert at, or `nil`.

  `nil` for no armed position at all, and `nil` again for a position naming a
  block or a slot this view model does not hold - a gap armed just before an
  edit removed the block under it reaches the second, and there is nothing
  truthful to say about it. Both answers are the same to a caller, because
  both mean "there is no destination to name".

  The labels rather than the raw ids for the reason `slot_label/2` gives:
  `arm_approved` under `blk_wizard` is the editor naming, in an instruction
  meant to orient someone, two things the canvas never showed them.

  Pure, and here rather than in the component, so the sentence the palette
  prints is asserted directly instead of through markup.
  """
  @spec insert_target(ViewModel.Node.t(), StatifierBlocks.Edit.target() | nil) ::
          insert_target() | nil
  def insert_target(_root, nil), do: nil

  def insert_target(%ViewModel.Node{} = root, {parent_id, slot_name, _index}) do
    with %ViewModel.Node{} = parent <- find_node(root, parent_id),
         %ViewModel.Slot{} = slot <- Enum.find(parent.slots, &(&1.name == slot_name)) do
      %{slot: slot.label, parent: ViewModel.title(parent)}
    else
      _no_such_parent_or_slot -> nil
    end
  end

  @spec find_node(ViewModel.Node.t(), Block.id()) :: ViewModel.Node.t() | nil
  defp find_node(%ViewModel.Node{block_id: id} = node, id), do: node

  defp find_node(%ViewModel.Node{slots: slots}, id) do
    Enum.find_value(slots, fn %ViewModel.Slot{children: children} ->
      Enum.find_value(children, &find_node(&1, id))
    end)
  end

  @doc """
  The tables `fixtures` holds for one block, or `[]`.

  `nil` fixtures - no source at all - answers `[]` like a source that holds
  nothing for the block. The two are told apart by `drawer_view/1`, which is
  the only caller that has anything different to say about them.
  """
  @spec tables_for(fixtures(), Block.id() | nil) :: [TruthTable.t()]
  def tables_for(nil, _block_id), do: []
  def tables_for(_fixtures, nil), do: []
  def tables_for(fixtures, block_id), do: Map.get(fixtures, block_id, [])

  @doc "Every block id the fixtures source has a table for, sorted."
  @spec table_block_ids(fixtures()) :: [Block.id()]
  def table_block_ids(nil), do: []

  def table_block_ids(fixtures) do
    fixtures
    |> Enum.reject(fn {_id, tables} -> tables == [] end)
    |> Enum.map(fn {id, _tables} -> id end)
    |> Enum.sort()
  end

  @doc """
  How many tables the whole source holds - the number the collapsed strip
  carries.

  The count is the document's and not the selection's on purpose (2A): the
  strip is what makes the drawer's content discoverable from any state, and a
  strip reading `(0)` because nothing is selected would teach an author the
  document has no tables.
  """
  @spec table_count(fixtures()) :: non_neg_integer()
  def table_count(nil), do: 0

  def table_count(fixtures),
    do: Enum.reduce(fixtures, 0, fn {_id, tables}, acc -> acc + length(tables) end)

  @doc """
  What the drawer shows, from its own open flag, its tab, the fixtures source,
  the document's findings and the selection (2A, and R4).

  Two tabs since R4 (operator, 2026-08-29): truth tables, and the
  document-level findings that used to render as a block under the canvas.
  Both are tabular and about the whole document, which is 1A's admission test.
  The tab decides the `title` and the `count` the strip carries, so a
  collapsed drawer says what it is holding rather than naming one tab forever.

  The truth-table statuses are unchanged and stay on `status`, because they
  describe that tab's content and nothing about the findings tab depends on
  them:

    * `:closed` - the strip, with the active tab's count.
    * `:no_fixtures` - open, with no fixtures source at all. Nothing to index.
    * `:no_selection` - open, nothing selected: the index page, listing every
      block that owns a table.
    * `:none_for_block` - open, a block selected that owns none: the index
      page again, which is 2A's answer to the spike's cold-start gap.
    * `:ready` - the selected block's tables.

  ## The unchosen tab

  `:tab` is `nil` until an author picks one, and an unchosen drawer resolves
  to **the first tab in `drawer_tabs/0` order with a non-zero count, or
  `:tables` when every count is zero**. The rule is 2A's own: the strip exists
  so the drawer's content is discoverable from any state, and a strip reading
  `Truth tables 0` on a document with four findings in it hides the only thing
  the drawer currently holds. Ties never arise - the order is the tie-break -
  and once the author picks a tab the pick stands, empty or not, because at
  that point the strip is reporting a choice rather than making one.
  """
  @spec drawer_view(%{
          optional(:open?) => boolean(),
          optional(:tab) => drawer_tab() | nil,
          optional(:fixtures) => fixtures(),
          optional(:findings) => [Finding.t()],
          optional(:orphan_findings) => [Finding.t()],
          optional(:selected_id) => Block.id() | nil
        }) :: drawer()
  def drawer_view(state) do
    fixtures = Map.get(state, :fixtures)
    selected_id = Map.get(state, :selected_id)
    findings = Map.get(state, :findings) || []

    tabs =
      Enum.map(@drawer_tabs, fn
        :tables -> %{id: :tables, title: drawer_title(:tables), count: table_count(fixtures)}
        :findings -> %{id: :findings, title: drawer_title(:findings), count: length(findings)}
      end)

    tab = resolve_tab(Map.get(state, :tab), tabs)
    active = Enum.find(tabs, &(&1.id == tab))

    base = %{
      open?: Map.get(state, :open?, false) == true,
      tab: tab,
      tabs: tabs,
      status: :closed,
      subject_id: nil,
      tables: [],
      findings: findings,
      orphans: MapSet.new(Map.get(state, :orphan_findings) || []),
      count: active.count,
      jumps: table_block_ids(fixtures),
      title: active.title
    }

    if base.open?, do: opened(base, fixtures, selected_id), else: %{base | jumps: []}
  end

  # An explicit pick stands, empty or not. An unchosen tab is resolved rather
  # than defaulted, so the strip carries something to open the drawer for.
  @spec resolve_tab(drawer_tab() | nil, [drawer_tab_entry()]) :: drawer_tab()
  defp resolve_tab(tab, _tabs) when tab in @drawer_tabs, do: tab

  defp resolve_tab(_unchosen, tabs) do
    case Enum.find(tabs, &(&1.count > 0)) do
      nil -> :tables
      entry -> entry.id
    end
  end

  @spec opened(drawer(), fixtures(), Block.id() | nil) :: drawer()
  defp opened(base, nil, _selected_id), do: %{base | status: :no_fixtures}
  defp opened(base, _fixtures, nil), do: %{base | status: :no_selection}

  defp opened(base, fixtures, selected_id) do
    case tables_for(fixtures, selected_id) do
      [] -> %{base | status: :none_for_block, subject_id: selected_id}
      tables -> %{base | status: :ready, subject_id: selected_id, tables: tables}
    end
  end

  @doc """
  A label for a block id, for the index page's jump list.

  The type name, because the index page is read before anything is selected
  and a block's label is its type's - `ViewModel` has already resolved that,
  so this walks the rendered tree rather than the document and gets the
  unresolvable case (decision 12) right for free.
  """
  @spec label_for(ViewModel.Node.t(), Block.id()) :: String.t()
  def label_for(%ViewModel.Node{} = root, id), do: find_label(root, id) || id

  @spec find_label(ViewModel.Node.t(), Block.id()) :: String.t() | nil
  defp find_label(%ViewModel.Node{block_id: id, type: type, entry: entry}, id),
    do: Map.get(entry, :label) || type

  defp find_label(%ViewModel.Node{slots: slots}, id) do
    slots
    |> Enum.flat_map(& &1.children)
    |> Enum.find_value(&find_label(&1, id))
  end

  @doc """
  A cell's status as one word an author reads, per
  `StatifierBlocks.Predicates.TruthTable.Cell`'s five values.

  Words rather than colour: the five statuses are not a severity ramp - an
  `:undecidable` cell is not a worse `:mismatch` - and a reader who cannot
  tell two hues apart gets the same table as everyone else.
  """
  @spec cell_word(TruthTable.Cell.t()) :: String.t()
  def cell_word(%TruthTable.Cell{status: :match}), do: "match"
  def cell_word(%TruthTable.Cell{status: :mismatch}), do: "mismatch"
  def cell_word(%TruthTable.Cell{status: :unchecked}), do: "unchecked"
  def cell_word(%TruthTable.Cell{status: :error}), do: "error"
  def cell_word(%TruthTable.Cell{status: :undecidable}), do: "undecidable"

  @doc "The value type a field declares, as a stable `data-` string."
  @spec field_type_tag(BlockType.field_type()) :: String.t()
  def field_type_tag({:list, inner}), do: "list:" <> field_type_tag(inner)
  def field_type_tag({:select, _options}), do: "select"
  def field_type_tag(type) when is_atom(type), do: Atom.to_string(type)
end
