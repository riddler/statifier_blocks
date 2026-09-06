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

  alias StatifierBlocks.{
    Block,
    BlockType,
    Datamodel,
    Declarations,
    Finding,
    SourceView,
    ViewModel
  }

  alias StatifierBlocks.Document.DatamodelEntry
  alias StatifierBlocks.Predicates.TruthTable

  @typedoc "Truth tables a host supplies, keyed by the block they describe."
  @type fixtures :: %{optional(Block.id()) => [TruthTable.t()]} | nil

  @typedoc """
  Which fit the canvas is in: `:manual` is every zoom an author stepped to
  themselves, and the other two are the two toolbar buttons.
  """
  @type fit_mode :: :manual | :width | :active

  @typedoc "Which of the inspector's four tabs is showing (3A)."
  @type inspector_tab :: :config | :findings | :condition | :fixtures

  @typedoc """
  Which of the drawer's own tabs is showing (1A, and the R4 ruling of
  2026-08-29 that put document findings here).

  The package's tabs are atoms and a host's are strings, which is what keeps
  the two namespaces apart without a registry: `drawer_tab/2` never turns an
  incoming tab name into an atom, so a crafted `phx-value-tab` reaches at
  worst a host tab the host itself declared.
  """
  @type drawer_tab :: :tables | :findings | :declarations | :fixtures | :datamodel | :source

  @typedoc "A host tab's id: its own name for it, and the DOM id it is stamped into."
  @type host_tab_id :: String.t()

  @typedoc "Either kind of drawer tab, as `drawer_view/1` reports the active one."
  @type tab_id :: drawer_tab() | host_tab_id()

  @typedoc """
  A tab a host contributes, as the editor's `drawer_tabs` assign carries it.

  `content` is a function component and is the editor's to call, not this
  module's - nothing here renders anything. What the shell reads is the
  descriptor: what the tab is called, and how much it holds. `count` is
  optional and absent means none.

  The editor calls `content` with `%{id: ..., count: ...}`, and a host value
  the function adds for its own markup is added with an `assign/2` call rather
  than merged into that map: a merged key is invisible to change tracking, and
  the panel then draws once and never again. `StatifierBlocks.Editor.Drawer`'s
  moduledoc carries the whole of that, and the naming rule decision 1 puts on
  this half of the package is why it is stated there and only pointed at here.
  """
  @type host_tab :: %{
          :id => host_tab_id(),
          :title => String.t(),
          optional(:count) => non_neg_integer(),
          optional(:content) => (map() -> term()),
          optional(any()) => any()
        }

  @typedoc "One entry in the drawer's tab strip: what it is called and how much it holds."
  @type drawer_tab_entry :: %{id: tab_id(), title: String.t(), count: non_neg_integer()}

  @typedoc """
  One block's findings, as the inspector's unselected Findings tab lists them.

  `block_id` is `nil` for the one group that is not about a block - the
  unanchored findings, whose anchors name ids the document does not hold.
  """
  @type findings_group :: %{
          block_id: Block.id() | nil,
          label: String.t(),
          findings: [Finding.t()]
        }

  @typedoc """
  One severity's share of a findings list, as the pill row above the list
  reports it.

  `count` is always positive: a severity with nothing at it has no pill, on
  the same reasoning the inspector's tab chip is absent at zero rather than
  reading `0` - a row of pills where two of the three say nothing is a row an
  author learns to stop reading.
  """
  @type severity_count :: %{severity: Finding.severity(), count: pos_integer()}

  @typedoc "What the drawer is showing, from its own flag, its tab and the selection."
  @type drawer :: %{
          open?: boolean(),
          tab: tab_id(),
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

  # The canvas scroller's anchor key. Reserved beside the stage's, and for the
  # same reason - see `viewport_anchor/0`.
  @viewport_anchor "viewport"

  # Tab order, and it is also the order `inspector_tab/1` resolves an unknown
  # name in: Config keeps the first position, so the tab an author selecting a
  # block almost always wants is the one an unknown name lands on. Fixtures is
  # last because it is the newest - ADR-0005's 2026-09-05 amendment
  # ("3A admits a Fixtures tab in the inspector") says so in as many words,
  # and it is the same arrival-order rule `@drawer_tabs` below follows.
  @inspector_tabs [:config, :findings, :condition, :fixtures]

  @fit_modes [:manual, :width, :active]

  # Tab order, and it is also the order the strip resolves an unchosen tab in
  # (see `drawer_view/1`). Truth tables first because they are what 2A shipped
  # the drawer for; findings second because R4 moved them here; declarations
  # third because they are the newest and the resolution order is arrival
  # order, so a document with tables in it opens where it always did. Fixtures
  # goes last for the same reason: it is the newest tab of all, and putting it
  # ahead of the other three would move a document that already has tables in
  # it off `:tables` and onto the fixtures tab the moment it also carried a
  # fixtures source - a resolution the arrival-order rule exists to prevent.
  # The datamodel view goes after fixtures on the same rule: it is newer
  # still, and it is the tab most likely to be non-empty on a document that
  # has nothing else in it, so ahead of the others it would capture the
  # unchosen resolution for almost every document a host supplies a
  # datamodel to.
  # datamodel to.
  #
  # The Source listing goes last of all, on the arrival-order rule and on its
  # own count: it is the newest, and its count is the number of lines the
  # chart was last compiled to, which is zero until something has asked for
  # a compile. So it never captures the unchosen resolution from a tab that
  # holds something, which is what the rule is for.
  @drawer_tabs [:tables, :findings, :declarations, :fixtures, :datamodel, :source]

  # "Declarations" and not "Datamodel" for the third tab, which is the name
  # the reserved place was described under. ADR-0001 11g and 11h split the
  # two artifacts and the words follow the split: an ADR-0006 datamodel
  # document describes a vocabulary, and the document's own `datamodel` key
  # declares that a root exists. The reserved place is now filled and the
  # name went where it belonged: `:datamodel` is the read-only view over the
  # vocabulary, and `:declarations` stays the editable list of roots.
  @drawer_titles %{
    tables: "Truth tables",
    findings: "Findings",
    declarations: "Declarations",
    fixtures: "Fixtures",
    datamodel: "Datamodel",
    source: "Source"
  }

  # The three declaring surfaces, in the words the read-only view puts in its
  # "Declared by" column. `StatifierBlocks.Datamodel`'s own names for them are
  # about where a path came from; these are about what an author would call
  # the thing that said so.
  @source_words %{
    datamodel: "Datamodel",
    declare: "Host",
    document: "Document"
  }

  # What a row with no ADR-0006 entry behind it says under "Type". A declared
  # root has no shape by 11l and a path set carries none at all, so the column
  # says nothing was specified rather than inventing a type for it.
  @unspecified_shape "unspecified"

  # The heading over the findings whose anchor names no block in the document.
  # A word rather than a block id, because there is no block to name.
  @unanchored_label "Unanchored"

  # Most to least urgent. It is the order `Finding.severity/0` declares and the
  # order an author triages in, and `severity_counts/1` is its only reader.
  @severity_order [:error, :warning, :info]

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
  The anchor key the canvas scroller is stamped with.

  A second reserved key beside `Connectors.stage_anchor/0`, and the reason it
  is reserved rather than derived from a block id is the same one: the stage
  is where the boxes are measured *from* and this is what they have to fit
  *into*, so neither is a block's anchor and neither can collide with one.

  It lives here rather than beside the connector anchors because nothing
  routes through it. The fits are the only thing that reads it, the fits are
  a shell arrangement, and a connector never asks how wide the scroller is.
  """
  @spec viewport_anchor() :: String.t()
  def viewport_anchor, do: @viewport_anchor

  @doc """
  The scroller's usable box out of a measurement payload, or `nil`.

  Total for `clamp_zoom/1`'s reason: the payload is a wire value and an
  editor whose viewport is unreadable is an editor whose fits decline to
  move rather than one that raises. `nil` is also what the editor holds
  before the first measurement and what it holds forever with no hook
  imported, which is why the fits below all take it as a `term()`.
  """
  @spec viewport(term()) :: %{width: float(), height: float()} | nil
  def viewport(%{"viewport" => %{"w" => w, "h" => h}}) do
    case {positive(w), positive(h)} do
      {{:ok, width}, {:ok, height}} -> %{width: width, height: height}
      _other -> nil
    end
  end

  def viewport(_other), do: nil

  @doc """
  The largest ladder step at which `content` wide fits `available` wide.

  This is the whole of what a fit computes, and both fits compute it: `Fit
  width` passes the stage's measured extent, `Fit active` passes the selected
  card's. Neither measures anything itself - the numbers arrive from the
  measurement hook - and neither lays anything out, which is the constraint
  the 2026-08-30 ruling put on this: the client measures, this picks a step
  off the same ladder the two buttons step along, and the stylesheet scales.

  With nothing measured yet, or a content box wider than any step can shrink
  to fit, the answer is the step the author is already on and the bottom of
  the ladder respectively. A fit that cannot be computed leaves the canvas
  where it is rather than jumping to a guess.
  """
  @spec fit_zoom(term(), term(), term()) :: pos_integer()
  def fit_zoom(content, available, _current)
      when is_number(content) and is_number(available) and content > 0 and available > 0 do
    @zoom_steps
    |> Enum.reverse()
    |> Enum.find(hd(@zoom_steps), &(content * &1 / 100 <= available))
  end

  def fit_zoom(_content, _available, current), do: clamp_zoom(current)

  @doc """
  The fit `value` names, or `:manual`.

  Total for `inspector_tab/1`'s reason with the source changed: this value
  arrives from a **host's** `fit` attr rather than from the DOM, and a host
  templating it from a stored preference or a query string is as likely to
  spell it wrongly as an author is to craft a payload. A fit the editor does
  not have is refused into the one every editor opens in, so the canvas is
  never stamped with a mode no stylesheet rule and no button can leave.
  """
  @spec fit_mode(term()) :: fit_mode()
  def fit_mode(value) when value in @fit_modes, do: value

  def fit_mode(value) when is_binary(value) do
    Enum.find(@fit_modes, :manual, &(Atom.to_string(&1) == value))
  end

  def fit_mode(_other), do: :manual

  @doc """
  The scaled extent of a measured box, or `nil` at 100% and unmeasured.

  A CSS transform is drawn after layout and takes no space, so a scaled stage
  alone leaves the scroller sized to the unscaled tree: zoomed in, the bottom
  right of the chart is unreachable; zoomed out, the panel scrolls over empty
  space. The wrapper around the stage is what carries the scaled size, and
  this is that size.

  `nil` at 100% is deliberate rather than an optimisation: an unzoomed editor
  then renders exactly the markup it rendered before there was a zoom at all,
  so the default case has no inline geometry to be wrong.
  """
  @spec zoom_extent(term(), term()) :: {float(), float()} | nil
  def zoom_extent(%{width: width, height: height}, zoom)
      when is_number(width) and is_number(height) do
    case clamp_zoom(zoom) do
      100 -> nil
      step -> {width * step / 100, height * step / 100}
    end
  end

  def zoom_extent(_box, _zoom), do: nil

  @doc """
  The width the stage is LAID OUT at while a zoom is applied, or `nil`.

  The wrapper `zoom_extent/2` sizes is the stage's parent, so its width is
  also the width the stage is laid out into - and that is a loop: at any step
  above 100% the wrapper is wider than the panel, the stage fills it, the
  stage's scroll extent grows, the next measurement makes the wrapper wider
  again. The live check at 150% found it immediately, at 33,554,428 pixels of
  wrapper, which is where the run stops rather than where it converges.

  Pinning the stage to the scroller's own width breaks it: the number the
  stage lays out at then comes from the panel, which no zoom moves, so the
  measurement that sizes the wrapper is the same at every step. It is the
  width the stage already had before there was a zoom - a block filling its
  scroller - said out loud because the wrapper is now between the two.

  `nil` at 100% and unmeasured, for `zoom_extent/2`'s reason: an unzoomed
  editor carries no inline geometry at all.
  """
  @spec zoom_stage_width(term(), term()) :: float() | nil
  def zoom_stage_width(%{width: width}, zoom) when is_number(width) do
    case clamp_zoom(zoom) do
      100 -> nil
      _step -> width * 1.0
    end
  end

  def zoom_stage_width(_viewport, _zoom), do: nil

  @spec positive(term()) :: {:ok, float()} | :error
  defp positive(value) when is_number(value) and value > 0, do: {:ok, value * 1.0}
  defp positive(_other), do: :error

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

  @doc "The inspector's four tabs, in the order 3A and its amendment list them."
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

  @doc """
  The drawer's own tabs, in the order the strip lists them.

  The package's, not the strip's whole set: a host's tabs follow these, and
  `drawer_view/1` is where the two are put together.
  """
  @spec drawer_tabs() :: [drawer_tab()]
  def drawer_tabs, do: @drawer_tabs

  @doc """
  The drawer tab `value` names, out of the package's tabs and `host_ids`, or
  `:tables`.

  The same shape as `inspector_tab/1` and for the same reason: the tab arrives
  from a `phx-value-tab` attribute, so an unknown one is a crafted payload
  rather than a bug, and the answer to it is the first tab.

  `host_ids` are the ids of the tabs the host is currently contributing, and
  they stay strings on the way through. A tab name is never turned into an
  atom here: the package's tabs are matched by comparing *their* names to the
  payload, and a host tab is matched by string equality against a list the
  host itself declared, so no payload can grow the atom table.
  """
  @spec drawer_tab(term(), [host_tab_id()]) :: tab_id()
  def drawer_tab(value, host_ids \\ [])

  def drawer_tab(value, _host_ids) when value in @drawer_tabs, do: value

  def drawer_tab(value, host_ids) when is_binary(value) do
    cond do
      match = Enum.find(@drawer_tabs, &(Atom.to_string(&1) == value)) -> match
      value in host_ids -> value
      true -> :tables
    end
  end

  def drawer_tab(_other, _host_ids), do: :tables

  @doc """
  The host tabs that may join the strip, in the order the host declared them.

  Two rules, and both are about the strip staying readable rather than about
  what a host is allowed to want. A host tab named for one of the package's
  own tabs is dropped, because the package's tab is the one `drawer_tab/2`
  resolves that name to and a strip with two "Findings" on it is a strip an
  author cannot use. A repeated id is dropped after its first appearance,
  because the id is stamped into the tab's DOM id and its panel's, and a
  duplicate there breaks the `aria-controls` pairing for both.

  Nothing else is filtered. Which content belongs in the drawer is 1A's test -
  tabular, and about the whole document - and the host applies it to its own
  content the same way this package applies it to its own.

  The reserved names now include `"fixtures"` (`sb-4yze`): a host tab with
  that id is dropped the same way one named `"declarations"` already is.
  """
  @spec host_tabs([host_tab()]) :: [host_tab()]
  def host_tabs(tabs) do
    reserved = Enum.map(@drawer_tabs, &Atom.to_string/1)

    tabs
    |> Enum.reject(&(&1.id in reserved))
    |> Enum.uniq_by(& &1.id)
  end

  @doc "The title a drawer tab carries, on the strip and on the tab itself."
  @spec drawer_title(drawer_tab()) :: String.t()
  def drawer_title(tab) when tab in @drawer_tabs, do: Map.fetch!(@drawer_titles, tab)

  @doc """
  The "Declared by" cell for one row of the read-only declared-path view:
  every surface that declared the path, in `Datamodel.declared_view/3`'s
  order, in one string.

      iex> StatifierBlocks.Shell.declared_by(%{sources: [:datamodel, :document]})
      "Datamodel, Document"
  """
  @spec declared_by(%{sources: [atom()]}) :: String.t()
  def declared_by(%{sources: sources}) do
    Enum.map_join(sources, ", ", &Map.get(@source_words, &1, to_string(&1)))
  end

  @doc """
  The "Type" cell for one row of the same view, as the ADR-0006 projection
  carries it.

  A `list` says what it holds when the entry named an `item_type`, because
  "list" alone is the one type in decision 4's set that does not describe a
  value on its own. Everything else is its own name, and a path no entry
  describes is `unspecified` rather than blank - a blank cell reads as a
  rendering gap, and this is a fact about the declaration.

      iex> StatifierBlocks.Shell.declared_shape(%{type: :integer, item_type: nil})
      "integer"

      iex> StatifierBlocks.Shell.declared_shape(%{type: :list, item_type: :string})
      "list of string"

      iex> StatifierBlocks.Shell.declared_shape(%{type: nil, item_type: nil})
      "unspecified"
  """
  @spec declared_shape(%{type: atom() | nil, item_type: atom() | nil}) :: String.t()
  def declared_shape(%{type: nil}), do: @unspecified_shape
  def declared_shape(%{type: :list, item_type: nil}), do: "list"
  def declared_shape(%{type: :list, item_type: item}), do: "list of #{item}"
  def declared_shape(%{type: type}), do: to_string(type)

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

  @typedoc """
  One fixture-derived hint: the path it is about, the exemplar value drawn
  beside the control, and every distinct value that path takes across the
  block's rows in first-appearance order.
  """
  @type fixture_hint :: %{path: String.t(), value: String.t(), values: [String.t()]}

  @doc """
  The fixture-derived hint for one block's condition source, or `nil`.

  ADR-0005's 2026-09-05 note, "The hint: a fixture value, drawn beside the
  field, never an option". The exemplar is what the block's **first fixture
  row in declaration order** binds to the path being edited; the whole set is
  every distinct value that path takes across the block's rows, in
  first-appearance order. Both halves come out of `tables_for/2` - the same
  reader the drawer's truth-table tab uses - so nothing is stored and nothing
  new crosses the `fixtures` seam.

  **Which path is "the path being edited"** is the one thing the record left
  to the implementing bead, because this package draws the hint beside the
  control and never sees inside it. The answer here is the path the source
  currently names, longest first so `user.age_group` is not answered by
  `user.age`, falling back to the first declared path when the source names
  none - a block whose condition is still empty gets the hint for the path its
  fixtures lead with rather than no hint at all.

  A path's declaration order is the fixture source's own `paths` list where it
  declares one; `TruthTable` derives and sorts one only when it does not.
  A row that does not bind the path contributes nothing, and a block with no
  rows - or no fixtures source at all - answers `nil`, which is what makes the
  hint absent rather than empty.

  This is a hint and never an option: nothing here reaches a picker, nothing
  is merged with `one_of` or with a host's `value_candidates`, and no value it
  answers can be selected.
  """
  @spec fixture_hint(fixtures(), Block.id() | nil, String.t() | nil) :: fixture_hint() | nil
  def fixture_hint(fixtures, block_id, source) do
    tables = tables_for(fixtures, block_id)
    rows = Enum.flat_map(tables, & &1.rows)
    paths = tables |> Enum.flat_map(&(&1.paths || [])) |> Enum.uniq()

    with path when is_binary(path) <- hint_path(paths, source),
         [exemplar | _rest] = values <- hint_values(rows, path) do
      %{path: path, value: exemplar, values: values}
    else
      _no_path_or_no_values -> nil
    end
  end

  # Longest first, so a path that is a prefix of another cannot answer for it.
  @spec hint_path([String.t()], String.t() | nil) :: String.t() | nil
  defp hint_path([], _source), do: nil

  defp hint_path([first | _rest] = paths, source) when is_binary(source) do
    named =
      paths
      |> Enum.sort_by(&(-String.length(&1)))
      |> Enum.find(&String.contains?(source, &1))

    named || first
  end

  defp hint_path([first | _rest], _source), do: first

  # Row order is declaration order - `TruthTable` keeps the rows as the source
  # wrote them - so the first value out is the first row's, and `Enum.uniq/1`
  # keeps first appearance for the rest.
  @spec hint_values([TruthTable.Row.t()], String.t()) :: [String.t()]
  defp hint_values(rows, path) do
    rows
    |> Enum.flat_map(fn %TruthTable.Row{bindings: bindings} ->
      case Map.fetch(bindings || %{}, path) do
        {:ok, value} -> [to_hint_text(value)]
        :error -> []
      end
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  @spec to_hint_text(term()) :: String.t()
  defp to_hint_text(value) when is_binary(value), do: String.trim(value)
  defp to_hint_text(value) when is_integer(value), do: Integer.to_string(value)
  defp to_hint_text(value), do: inspect(value)

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
  How many fixture rows the whole source holds - the number the Fixtures
  tab's strip carries.

  Rows and not failures, and the reason is both editorial and mechanical. The
  strip counts CONTENT, the way the tables tab counts tables and the findings
  tab counts findings; a chip reading `Fixtures 0` over forty passing rows
  says the opposite of what 2A's strip is for. And `drawer_view/1` runs on
  every render: a row count is a sum over the assign, while a failure count
  would put a compile plus one chart run per row inside every keystroke.
  """
  @spec fixture_row_count(fixtures()) :: non_neg_integer()
  def fixture_row_count(nil), do: 0

  def fixture_row_count(fixtures) do
    Enum.reduce(fixtures, 0, fn {_id, tables}, acc ->
      acc + Enum.reduce(tables, 0, fn %TruthTable{rows: rows}, inner -> inner + length(rows) end)
    end)
  end

  @doc """
  How many findings the document has - the number the Findings tab reports,
  and the one number this package means by "the document's findings".

  There is exactly one such number and this is where it is defined, so that
  the tab chip, the collapsed strip and the count a host reads through
  `StatifierBlocks.Editor.findings_count/3` cannot say three different things
  about one document. That was the defect: three call sites each counted a
  list of their own, and the lists were not the same list.

  The argument is `ViewModel.findings` - every finding the view model holds,
  derived and caller-supplied alike. **Orphans are inside it.** A finding
  anchored on a block the document no longer holds renders nowhere on the
  canvas, but it is still something wrong with this document, and a number
  that dropped it would report a document as clean while its findings list
  sat under the drawer saying otherwise.
  """
  @spec findings_count([Finding.t()]) :: non_neg_integer()
  def findings_count(findings) when is_list(findings), do: length(findings)

  @doc """
  The same findings cut by severity, for the pill row above the list.

  It is `findings_count/1` again, told a second way, and the two are pinned
  to each other by construction: summing every entry's `count` is
  `findings_count/1` again, for every list. That is the property
  `findings_groups/3` documents about its own grouping, and it is here for the
  same reason - a summary line that disagrees with the list beneath it is the
  two-numbers defect `findings_count/1` exists to close, and a pill row is a
  second place for it to reappear.

  Order is `:error`, `:warning`, `:info` - most to least urgent, which is the
  order the severities are declared in and the order an author triages in.
  A severity with nothing at it is **omitted** rather than rendered as zero,
  so the row's width is what the document actually holds.

  The argument is the same list `findings_count/1` takes: `ViewModel.findings`
  for the document, a group's or a block's list for a narrower surface.
  Orphans are inside it wherever they are inside the list handed in.
  """
  @spec severity_counts([Finding.t()]) :: [severity_count()]
  def severity_counts(findings) when is_list(findings) do
    tally = Enum.frequencies_by(findings, & &1.severity)

    for severity <- @severity_order,
        count = Map.get(tally, severity, 0),
        count > 0,
        do: %{severity: severity, count: count}
  end

  @doc """
  The document's findings grouped by the block each one is anchored to, for
  the inspector's Findings tab when nothing is selected.

  The grouping is the only thing this adds to `findings_count/1`'s list: the
  same findings, in the same order, cut into runs by their anchor's block id.
  It does not filter, and it does not re-derive - a group's findings are the
  ones handed in, so `Enum.map(groups, & &1.findings) |> List.flatten() |>
  length()` is `findings_count/1` again by construction. That is deliberate:
  a panel that showed fewer findings than the chip beside it counts is the
  same two-numbers defect `findings_count/1` exists to close.

  Group order is first appearance in `findings`, which is document order for
  everything the view model derives, and the **unanchored group is last**. An
  unanchored finding is one of `ViewModel.orphan_findings` - its anchor names
  a block id the document does not hold - and it gets a group rather than a
  filter because it is inside the number and an author who cannot see it
  reads the chip as wrong. It carries `block_id: nil`, which is what tells a
  caller there is nothing to select.

  `root` is only ever read for a label; a `nil` root labels every group with
  its block id, which is `label_for/2`'s own fallback for an id the tree does
  not hold.
  """
  @spec findings_groups(ViewModel.Node.t() | nil, [Finding.t()], Enumerable.t()) :: [
          findings_group()
        ]
  def findings_groups(root, findings, orphans) when is_list(findings) do
    orphan_set = MapSet.new(orphans || [])
    {unanchored, anchored} = Enum.split_with(findings, &MapSet.member?(orphan_set, &1))

    by_block = Enum.group_by(anchored, &finding_block_id/1)

    anchored
    |> Enum.map(&finding_block_id/1)
    |> Enum.uniq()
    |> Enum.map(
      &%{block_id: &1, label: group_label(root, &1), findings: Map.fetch!(by_block, &1)}
    )
    |> append_unanchored(unanchored)
  end

  @spec append_unanchored([findings_group()], [Finding.t()]) :: [findings_group()]
  defp append_unanchored(groups, []), do: groups

  defp append_unanchored(groups, unanchored),
    do: groups ++ [%{block_id: nil, label: @unanchored_label, findings: unanchored}]

  @spec group_label(ViewModel.Node.t() | nil, Block.id()) :: String.t()
  defp group_label(%ViewModel.Node{} = root, id), do: label_for(root, id)
  defp group_label(nil, id), do: id

  # The anchor's block id, whichever of the three shapes decision 11 gives it.
  @spec finding_block_id(Finding.t()) :: Block.id()
  defp finding_block_id(%Finding{anchor: {:config, id, _key}}), do: id
  defp finding_block_id(%Finding{anchor: {:slot, id, _name}}), do: id
  defp finding_block_id(%Finding{anchor: {:block, id}}), do: id

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

  ## A host's own tabs

  `:host_tabs` are the descriptors of the tabs the host is contributing, and
  they join the strip after the package's, in the order the host declared
  them. They are ordinary entries from there on: the strip resolves an
  unchosen tab through them on the same rule, so a document with no tables and
  no findings and a running feed opens on the feed rather than on an empty
  `Truth tables 0` - which is 2A's reasoning about the strip, not an exception
  to it.

  Only the descriptor is read here. A host tab's `content` is a function the
  editor calls when that tab is active, so nothing about what it draws is
  decided in this module.
  """
  @spec drawer_view(%{
          optional(:open?) => boolean(),
          optional(:tab) => tab_id() | nil,
          optional(:fixtures) => fixtures(),
          optional(:findings) => [Finding.t()],
          optional(:orphan_findings) => [Finding.t()],
          optional(:host_tabs) => [host_tab()],
          optional(:declarations) => [DatamodelEntry.t()],
          optional(:declared_view) => [Datamodel.declared_row()],
          optional(:source_view) => SourceView.t() | nil,
          optional(:selected_id) => Block.id() | nil
        }) :: drawer()
  def drawer_view(state) do
    fixtures = Map.get(state, :fixtures)
    selected_id = Map.get(state, :selected_id)
    findings = Map.get(state, :findings) || []
    declared_view = Map.get(state, :declared_view) || []

    own =
      Enum.map(@drawer_tabs, fn
        :tables ->
          %{id: :tables, title: drawer_title(:tables), count: table_count(fixtures)}

        :findings ->
          %{id: :findings, title: drawer_title(:findings), count: findings_count(findings)}

        :declarations ->
          %{
            id: :declarations,
            title: drawer_title(:declarations),
            count: Declarations.count(Map.get(state, :declarations))
          }

        :fixtures ->
          %{id: :fixtures, title: drawer_title(:fixtures), count: fixture_row_count(fixtures)}

        :datamodel ->
          %{
            id: :datamodel,
            title: drawer_title(:datamodel),
            count: length(declared_view)
          }

        :source ->
          %{
            id: :source,
            title: drawer_title(:source),
            count: source_count(Map.get(state, :source_view))
          }
      end)

    contributed =
      state
      |> Map.get(:host_tabs)
      |> Kernel.||([])
      |> host_tabs()
      |> Enum.map(&%{id: &1.id, title: &1.title, count: Map.get(&1, :count) || 0})

    tabs = own ++ contributed

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

  # The Source tab's count is the number of lines the chart was last compiled
  # to. It is a count of what the panel draws, like every other tab's, and it
  # is zero before the first compile because nothing here compiles anything:
  # the listing is the editor's assign, refreshed only while a surface is
  # showing it, and this function reports whatever that assign holds.
  @spec source_count(SourceView.t() | nil) :: non_neg_integer()
  defp source_count(%SourceView{line_count: count}), do: count
  defp source_count(_none), do: 0

  # An explicit pick stands, empty or not. An unchosen tab is resolved rather
  # than defaulted, so the strip carries something to open the drawer for.
  #
  # The pick is checked against the strip rather than against `@drawer_tabs`,
  # which is what makes a host tab a real pick and what makes a host tab the
  # host has since withdrawn resolve again instead of naming a panel that is
  # no longer there.
  @spec resolve_tab(tab_id() | nil, [drawer_tab_entry()]) :: tab_id()
  defp resolve_tab(tab, tabs) do
    if Enum.any?(tabs, &(&1.id == tab)) do
      tab
    else
      case Enum.find(tabs, &(&1.count > 0)) do
        nil -> :tables
        entry -> entry.id
      end
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
  def field_type_tag({:path, _opts}), do: "path"
  def field_type_tag(type) when is_atom(type), do: Atom.to_string(type)
end
