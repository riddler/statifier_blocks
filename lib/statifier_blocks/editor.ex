if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor do
    @moduledoc """
    The block editor: the only stateful module in the package's rendered half
    (ADR-0005 decisions 6, 8, 9, 13).

    Everything this component does is **translation**. Every author gesture
    reduces to one of the four commands `StatifierBlocks.Edit` defines, and
    the mutation, its inverse and the set of places a block may be dropped are
    all pure functions of `{document, palette}` that were tested with LiveView
    absent from the dependency tree. What is left here is turning a `phx-`
    event into a command, offering it to `StatifierBlocks.Edit.History`, and
    re-rendering.

    That split is the single most load-bearing constraint in ADR-0005, and the
    reason is drag-and-drop specifically: it is the interaction most likely to
    be tested by clicking around and declared fine, and the one most likely to
    corrupt a document when it is wrong. If the semantics of a drag lived
    here, they would be testable only through a browser driver.

    ## The drag, in two round-trips

    `dragstart` pushes one event. `Edit.Targets.slot_verdicts/3` runs once,
    the result goes into the drag session, and the re-render stamps
    `data-drop` on every slot - so every valid target highlights before the
    pointer has moved, and hover costs nothing. `drop` pushes the position, one
    `:move` is built and applied, and the tree re-renders. `dragend` clears the
    session. There is no third round-trip and no client-side validity logic.

    That one enumeration answers both halves of the drag. The accepting slots
    are `data-drop`; the refusing ones that have a data-flow reason to give
    (the 2026-08-29 ADR-0003 amendment's vocabulary) carry it as
    `data-drop-reason` beside it, so a later hover affordance has the reason
    already in the markup and still needs no round-trip and no JavaScript.
    The host's widening relation reaches all of this the way ADR-0003
    decision 6 says it does and the way nothing else could: through
    `palette.assignability`, consulted by the one `Assignability` the
    compiler's `validate/3` consults.

    ## The other thing a drag can carry (sb-4nep)

    A palette entry is a drag source too, and dragging one onto a gap inserts
    a block of that type there. It is the same two round-trips with the same
    one enumeration: `insert-dragstart` builds the session against a **probe**
    block of the dragged type instead of against a block the document holds,
    and `insert-drop` hands the gap's position to the same
    `insert_from_palette/3` a pick uses. The drop therefore produces decision
    2's `:insert` at a position the author named, exactly as the "+" and the
    pick do, and ADR-0005's command set is untouched - what is new is a
    gesture, not a command.

    Which is also why the position comes from the gap rather than from
    `palette_position`. Arming is how the *click* path names a destination; a
    drag names one by landing on it. A drop made while some other gap is armed
    lands where it was dropped and clears the mode, because the gesture that
    just finished is the one that said where.

    ## Config, and the gate that keeps the document sound

    ADR-0002 decision 6 guarantees `slots/1` returns without raising only for
    config `validate_config/1` accepts - and an author halfway through typing
    an identifier has invalid config almost continuously. So an
    `:update_config` reaches the document only when it validates, which
    `Edit.check_config/3` enforces inside `History.commit/4`.

    In-progress form state that does not validate lives in this component's
    `drafts` assign: never in the document, never on the undo stack. It is
    overlaid onto the selected block's form at render time - values and
    findings both - so the author keeps their keystrokes and sees findings
    about the value they are currently typing, while the tree, the slot set
    and every consumer downstream still see the last config that validated.
    Crucially, the overlay never calls `slots/1`: it touches the form and
    nothing else, which is what keeps the draft from reaching a callback that
    was only promised valid config.

    ## The datamodel, and why it is one assign and no logic

    A host may hand the editor the datamodel paths it declares. The only
    thing that buys is the undeclared-path advisory ADR-0005 amendment
    11e-11g specifies: a config field a block type annotated
    `datamodel_path?: true` whose value is not in that set gets an `:info`
    finding anchored on the field. The rule itself is
    `StatifierBlocks.Datamodel`'s and is pure, so it is tested with
    LiveView absent; what happens here is one normalization on `update/3`
    and one concatenation in `rebuild/1`, which is the same translation-only
    posture as everything else in this module.

    `nil` is the default and means *no datamodel supplied*, which per 11f
    produces nothing anywhere - the check does not run at all. That is not
    the same as an empty set, which is a host declaring that its documents
    address nothing.

    A datamodel is no longer the only thing that declares. ADR-0005
    amendment 11k reads three sources, and two of them are roots rather
    than paths: the roots the document itself declares (ADR-0001 decision
    11), which `StatifierBlocks.Datamodel` reads off the document with no
    help from here, and the roots the compile call names. The second is why
    there is a `declare` assign: this component has no compile call to read,
    so a host that will pass `declare:` to `StatifierBlocks.Compiler` passes
    the same list here. It is the same one normalization and one
    concatenation the datamodel gets - `[]` is the default and declares
    nothing, so a host that never passes it sees exactly what it saw before.

    ## The run marks a host paints

    A host replaying or executing a document has two different things to say
    about it on the canvas: **where the run is** - the blocks a step has
    activated - and **who it is waiting on** - the block whose call out to a
    handler has not come back yet, and how it came back once it did. Those are
    `active_marks` and `invoke_mark`, and they are two assigns rather than one
    because a step can carry either without the other. One seam that took both
    would make every caller holding one of them pass a placeholder for the
    other.

    They are assigns and not a new API, because every other thing a host tells
    this editor is an assign. A host that re-renders for its own reasons can
    pass them in the component call; a host reacting to a run event it received
    out of band pushes them, which is `send_update/3` and needs nothing from
    this package:

        Phoenix.LiveView.send_update(StatifierBlocks.Editor,
          id: "editor",
          active_marks: ["blk_capture"],
          invoke_mark: {"blk_authorize", "done"}
        )

    Which is exactly why a mark is held as editor state rather than read out of
    the assigns at render time. `send_update/3` delivers only the keys it
    names, so a component whose marks lived only in the assigns the host most
    recently passed would drop them on the next unrelated re-render - an author
    moving a block, a header the host redrew for its own reasons. Each mark is
    written only by an update that carries it, the way `datamodel` and
    `drawer_height` already are, so a render that says nothing about the marks
    changes nothing about them.

    A **different document** clears them, and that is the one place they part
    company with the pane folds. ADR-0005's 2026-08-30 amendment to decision 2
    exempts a fold from the document-switch reset because a fold addresses no
    block; a mark addresses exactly one, so it stops being true the moment the
    block it names is gone. Marks reset in `switch_document/2` beside
    `selected_id` and the collapsed set. A host that swaps a document and marks
    the new one in the same update is not fighting that reset: the reset runs
    first and the marks it passed are applied after.

    The active marks are also what the toolbar's `Fit active` falls back on.
    An observer watching a run is not selecting anything - the marks are the
    run's own answer to "which block matters right now" - so the control is
    enabled whenever there is a selection *or* a mark, and with nothing
    selected it fits and reveals the first marked block. The order is the
    host's: the marks are kept as the list the host passed, deduplicated only
    where the canvas asks the question as a set. With no selection and no
    marks there is nothing to fit, and the control stays disabled.

    What reaches the markup is `data-run-active`, `data-run-invoking` and -
    only for a call that has come back - `data-invoke-outcome`, on the block's
    `.sb-node`. The outcome is passed through rather than checked against a
    set: which outcomes a call can have is the block type's vocabulary, the
    one `slot_outcome_key` already reads, so a closed set here would be this
    package inventing a second one. The stylesheet tints the two the spike
    proved and leaves every other outcome the neutral treatment.

    ## Opening at a fit (sb-ehqn)

    A document wider than the canvas opens with its right-hand columns off
    the edge, and the only remedy the editor had was the author pressing
    `Fit width` on every document they opened. `fit` is the host's opt-in to
    having that press made for them: `:manual` (the default) is exactly
    today's behaviour, and `:width` or `:active` makes the editor open the
    way it looks after that button.

    It is an *opening* state and not a control, which is the whole of the
    care in it. The fit needs numbers only the browser has, so it cannot
    happen at mount; what happens at mount is that the mode is set and a fit
    is armed, and the **first measurement payload** spends it - the same
    computation `handle_event("fit", ...)` runs, on the same ladder, against
    the same measured scroller. It is spent once per open document, and
    re-armed only when the host swaps a different document in: a host
    re-renders for reasons of its own, and an attr that re-fitted on each of
    them would throw an author back to the fit every time their own header
    changed. What the attr opens is a document, though, so a different
    document is another opening and is armed from the attr the host passes in
    that same update - `:manual` or an absent attr arming nothing, exactly as
    at mount. Between one document's measurement and the next document's
    arrival the attr is inert, `zoom -/+` return the canvas to `:manual` as
    they always have, and the editor is in the state it would have been in had
    the author pressed the button themselves.

    A host that never imports the measurement hook measures nothing, so the
    fit is never armed away and never spent: the mode is set, the canvas is
    at 100%, and that is decision 7's absent-hook test holding here too.

    Between the mount and that first payload the canvas is laid out at 100%,
    which is a frame the author should not be shown: it paints the whole
    chart at full size and then snaps to the fit. So for exactly as long as
    a fit is armed the root carries `data-fit-pending`, and the stylesheet
    keeps the stage unpainted under it - the layout still happens, because
    the layout is what the hook has to measure; only the ink waits. The
    stylesheet also carries a delayed reveal so the wait cannot outlive the
    frame it exists for: a hook-less host never spends the fit, and a blank
    canvas forever would be a worse defect than the flash. Nothing about
    this is the hook's - it writes no attribute, no style and no class
    (decision 7a), and the attr is server-stamped like every other.

    ## What stays the host's

    Which palette entries a tenant may use, who may edit or publish a
    document, where it is stored, and what publishing means are all outside
    this package (decision 15).

    The 2026-08-29 shell amendment's ruling 8A adds two more, and names the
    seam for each: **slots for markup, events for actions.** The outer header -
    document identity, the document switcher, the theme control, compile and
    publish - is the `:header` slot, because markup is exactly the thing a host
    wants to own and a slot costs this package no API surface. The drawer's
    height is `on_drawer_resize` out and `drawer_height` back in, because the
    height is remembered per viewer and this package has no viewer. A host that
    renders its own publish button into the slot and receives the press as its
    own event is the intended shape; the editor draws no header of its own and
    is not waiting for permission to. So is concurrency: this is a single-session
    component, it surfaces the `revision` it loaded so a host can do
    optimistic concurrency on save, and it does not merge, rebase or resolve
    anything.

    ## The drawer tabs a host contributes

    8A's split gives the drawer to the package, and 1A's test - tabular, and
    about the whole document - governs what the package puts in it. Neither
    anticipated a host with content that passes that test: a host executing the
    open document has a run feed, and a feed of steps is a grid of rows about
    the whole document. The 2026-08-30 amendment recording the drawer's tab
    strip as a host seam transfers 1A to the host for the tabs it contributes,
    and `drawer_tabs` is where they go.

    Each entry is `%{id:, title:, content:}` with an optional `count:`. `id` is
    the host's own name for the tab and is what its DOM id and its panel's are
    built from; `title` and `count` are what the tab and the collapsed strip
    draw; `content` is a **function component** - the same seam shape `icon`
    and `expression_component` already use, for the same reason ADR-0005
    decision 9's does: HEEx has no dynamic-component tag, and a one-argument
    function returning a rendered struct is the whole of the contract. It is
    called with the tab's `id` and `count`, and with change tracking on those
    two keys only - which is why the example reaches for `assign/2` rather
    than `Map.put/3`. `StatifierBlocks.Editor.Drawer`'s moduledoc has what
    goes wrong when a host merges its own values in instead.

        Phoenix.LiveView.send_update(StatifierBlocks.Editor,
          id: "editor",
          drawer_tabs: [
            %{id: "runs", title: "Runs", count: length(events),
              content: fn assigns -> MyApp.run_feed(assign(assigns, :events, events)) end}
          ]
        )

    A function and not a slot, and the reason is the live feed the seam exists
    for. A slot's body is a closure over the *host's* assigns, which sounds
    like the shorter path to live content and is not: a `LiveComponent` is
    re-rendered when the assigns **it** was passed change, and a host assign
    read only inside a slot body is not one of them, so the appended step
    never reaches the screen. Pushing the descriptors is how every other thing
    a host tells this editor arrives, `send_update/3` included, and it is live
    for the same reason the run marks are.

    Held as editor state, like the marks and for the same reason: an update
    that says nothing about the tabs changes nothing about them. A host tab
    named for one of the package's own tabs, or repeating an id already used,
    is not drawn - `StatifierBlocks.Shell.host_tabs/1` says why.

    ## The findings number a host may show (sb-ukgu)

    A host that draws its own header usually wants to say how many findings
    the open document has, and the obvious way to get that number - counting
    whatever list the host itself passed in, or counting the compiler's raw
    output - produces a *different* number from the one the drawer's Findings
    tab reports. It has to: the drawer counts the caller's findings plus the
    `:resolution` and `:config` findings `ViewModel` derives plus the
    undeclared-path advisories, and the host's own list is only the first of
    those three. Two numbers for one document, side by side on the same
    screen, is the defect this seam closes.

    So there is one number, the drawer's, and `findings_count/3` is how a host
    reads it:

        StatifierBlocks.Editor.findings_count(document, palette,
          findings: findings,
          datamodel: datamodel
        )

    Its arguments are deliberately the assigns the host already holds and
    already passes to the component, not the editor's internal state. That is
    what makes it usable: the editor is a `LiveComponent`, so a host has no
    handle on its socket, and a number that could only be read out of that
    socket would have to be pushed back through `on_change` - late by one
    render on mount, and absent entirely for a document nobody has edited yet.
    A pure function of the same inputs is available on the host's first
    render, needs no round-trip, and cannot drift: the option keys are the
    assign names, and the component's own `rebuild/1` builds its view model
    through the very same private function this one calls.

    What comes back is `Shell.findings_count/1` over `ViewModel.findings` -
    orphans included, for the reason recorded there. A host showing a
    different number than the drawer is a bug in the host; a host showing
    none is fine.

    ## The insert mode, and the pick that lands nowhere (sb-dfyk)

    `palette_position` is a mode, and every visible part of it hangs off that
    one assign: the armed gap on the canvas, the instruction naming where the
    pick will land, the Cancel beside it, and the `Escape` binding - which is
    on the root only while the mode is open, so a resting editor holds no
    window listener for a mode nobody opened. Arming also un-collapses the
    palette, because a mode whose only instruction is inside a folded pane is
    the same defect in a different place.

    A pick made with **nothing** armed stays a no-op, and that is a ruling
    rather than an omission. The alternative on the table was appending to the
    selected container's default slot, and "default slot" is a rule no accepted
    ADR states: decision 8 ties a pick to a position the author named at a gap,
    and inventing a destination on their behalf would be a new contract written
    into a handler rather than into the record. What the no-op was missing was
    not a destination but a reason, so it now gives one - `palette_unarmed_pick`
    is that sentence, and it renders in the same region the armed case uses for
    its instruction.

    ## The selection a host can follow (`on_select`)

    The selection is editor state: it is produced by a gesture on the canvas
    and only the component knows it, so - unlike the findings number above -
    there is no pure function of the host's own assigns that answers it. What
    cannot be read has to be pushed, and `on_select` is the push.

    It is a one-argument function, called with each new selection and never
    for its return value, and it sits beside `on_change` rather than inside
    it: a document and a selection are different subjects, and a host that
    wants one should not have to receive the other. What arrives is a
    descriptor rather than a block -

    | Key | Value |
    |---|---|
    | `id` | the selected block's id |
    | `type` | the block's type name, as the document stores it |
    | `label` | the card's first line: the author's title where they gave one, the type's label otherwise |

    - because the host already holds the document it passed in, so returning
    the block's config would be a second channel for something the host can
    already read, and one that goes stale the moment the two disagree.

    Deselection calls `on_select` with `nil`, because a panel that follows the
    canvas has to be able to empty itself; a callback that only ever fired on
    a *new* block would leave the panel showing the last one forever. It fires
    when the selection changes and not otherwise - not on every render, not on
    an edit to the selected block, not on a mount with nothing selected, and
    not on re-selecting the block that is already selected.

    Nothing about it is a document edit. There is no `:select` command, and
    nothing here is serialized, stored, undone or redone. The package's own
    inspector still reads the selection out of component state: this is a seam
    out, not a rewiring of what is already inside. See ADR-0005's 2026-09-05
    amendment, *the host seams, `on_select` and a selection descriptor*.

    ## Assigns

    | Assign | Required | Meaning |
    |---|---|---|
    | `id` | yes | the LiveComponent id |
    | `document` | yes | the document being edited |
    | `palette` | yes | the host's palette |
    | `findings` | no | caller-supplied findings, merged with the two `ViewModel` derives |
    | `datamodel` | no | the paths the host declares; drives the undeclared-path advisories, and `nil` (the default) turns them off entirely |
    | `declare` | no | the `{id, expr}` roots the host will pass the compiler as `:declare`; declared roots count as declared for the advisories (11k), and `[]` (the default) declares none |
    | `on_change` | no | one-argument function called with each new document |
    | `on_select` | no | one-argument function called with each new selection: a `%{id:, type:, label:}` descriptor, or `nil` for no selection |
    | `icon` | no | function component resolving an icon *name* to markup |
    | `expression_component` | no | override for `:expression` fields (sui-bob's seam); with it unset, an `:expression` renders statifier-ui's own expression editor when that package is on the host's load path, and the package's plain source input when it is not |
    | `value_candidates` | no | the values offered per datamodel path, `%{path => [%{label:, value:} \| binary]}`; **merged over the datamodel's own `one_of` enumerations, per path**, so a path this map names uses this map's list and a path it does not name keeps what the datamodel declares. Read only by an expression editor that draws value pickers; `%{}` (the default) now means *nothing beyond what the datamodel declares* rather than nothing at all |
    | `field_candidates` | no | the values a host offers for one field, keyed `{type_name, field_key}`: `[{value, label}]` for a closed list, which a `:string` field draws as a `<select>`, or `{:open, [{value, label}]}` for an open one, drawn as a `<datalist>`. `%{}` (the default) offers none, and a field it does not name renders exactly as it did. It draws a control and decides nothing: `validate_config/1` is still the only authority on a value, and a stored value a closed list does not offer is drawn rather than rewritten |
    | `invoke_types` | no | the invoke types the host is prepared to answer; suggestions on an `invoke_type` field, never a constraint, and `[]` (the default) means *no list supplied* |
    | `chart_outcomes` | no | what the host says each of its stored documents finishes with, `%{document id => [outcome]}`; offered as candidates on a `core.subchart`'s `outcomes` field and compared against what that block declares (`StatifierBlocks.ViewModel.outcome_findings/3`). `%{}` (the default) says nothing about any chart, and a chart the map does not name is *unknown*, which is not disagreement |
    | `active_marks` | no | the block ids a run has activated; held as editor state, and cleared when the host opens a different document |
    | `invoke_mark` | no | the block a run is calling out to and how the call came back - `{block_id, outcome}`, a bare `block_id` for no answer yet, or `nil` for no call at all |
    | `theme` | no | `--sb-*` custom properties for the canvas root |
    | `fit` | no | the fit the editor **opens** in: `:manual` (the default), `:width` or `:active`; the first measurement performs it once, and an unknown value is refused into `:manual` |
    | `fixtures` | no | `%{block_id => [TruthTable.t()]}`, read by both the drawer's truth-table tab and, as of `sb-4yze`, its Fixtures tab (`refresh_fixture_runs/1` drives each row through the compiled chart), and, as of `sb-e30x`, by the inspector's config form for the fixture hint beside an `:expression` control, and, as of `sb-0l36`, by the inspector's own Fixtures tab, which shows the selected block's runs out of the same result; `nil` (the default) means *no fixtures source*, and the drawer is still there with a count of 0 |
    | `drawer_tabs` | no | tabs the host contributes to the drawer, each `%{id:, title:, content:}` with an optional `count:`; drawn beside the package's own and rendered by calling `content` |
    | `drawer_height` | no | the drawer's height in rem, remembered **by the host** per viewer (2A); bounded on the way in |
    | `on_drawer_resize` | no | one-argument function called with each new drawer height, which is how the host comes to have one to remember |
    | `class` | no | appended to the root element's own classes |
    | `history_limit` | no | bound on the undo stack; `:infinity` by default |
    """

    use Phoenix.LiveComponent

    alias StatifierBlocks.{
      Assignability,
      Block,
      BlockType,
      Connectors,
      Datamodel,
      Declarations,
      Document,
      Edit,
      Environment,
      Finding,
      Palette,
      Recipe,
      Shelf,
      ViewModel
    }

    alias StatifierBlocks.Compiler.StateId
    alias StatifierBlocks.Document.DatamodelEntry
    alias StatifierBlocks.Edit.{History, Targets}
    alias StatifierBlocks.Runtime.FixtureRuns

    alias StatifierBlocks.Editor.{
      Canvas,
      ConfigForm,
      Drawer,
      Inspector,
      PaletteBrowser,
      Toolbar
    }

    alias StatifierBlocks.Shell

    # The one type whose `event` field is offered generated completion-event
    # names (sb-82mu), and the separator the candidate labels use - the same
    # one the summary chips use for `<label> <sep> <outcome>`, so a candidate
    # and the chip it will become read alike.
    @on_event_type "core.on_event"

    # The one type whose `outcomes` field is offered the finals a host says
    # the referenced chart emits (sb-r4w7).
    @subchart_type "core.subchart"
    @candidate_separator " · "

    @impl Phoenix.LiveComponent
    def mount(socket) do
      {:ok,
       assign(socket,
         findings: [],
         datamodel: nil,
         declared_paths: nil,
         declare: [],
         host_roots: MapSet.new(),
         on_change: nil,
         on_select: nil,
         icon: nil,
         expression_component: nil,
         invoke_types: [],
         chart_outcomes: %{},
         value_candidates: %{},
         field_candidates: %{},
         theme: %{},
         class: nil,
         history_limit: :infinity,
         history: History.new(),
         selected_id: nil,
         notified_id: nil,
         collapsed_ids: MapSet.new(),
         active_marks: [],
         invoke_mark: nil,
         active_ids: MapSet.new(),
         invoking: nil,
         drag: nil,
         drafts: %{},
         declaration_draft: nil,
         pending_fields: [],
         palette_position: nil,
         palette_allowed: nil,
         palette_query: "",
         palette_sheet: false,
         palette_collapsed: false,
         palette_unarmed_pick: false,
         inspector_collapsed: false,
         fixtures: nil,
         fixture_runs: nil,
         fixture_runs_key: nil,
         inspector_tab: :config,
         drawer_open: false,
         drawer_tabs: [],
         drawer_tab_id: nil,
         drawer_tab_focus: nil,
         drawer_height: Shell.clamp_height(nil),
         on_drawer_resize: nil,
         zoom: Shell.default_zoom(),
         fit: :manual,
         fit_pending: nil,
         measured?: false,
         measurement: %{},
         viewport: nil,
         reveal: nil,
         last_error: nil
       )}
    end

    @impl Phoenix.LiveComponent
    def update(assigns, socket) do
      previous = Map.get(socket.assigns, :document)

      # Read before `assign/2` writes the host's raw attr over it: `fit` is
      # the one assign whose live value is the editor's rather than the
      # host's, because the author's own zoom moves it. See `arm_fit/4`.
      held_fit = Map.get(socket.assigns, :fit, :manual)

      {socket, swapped?} = socket |> assign(assigns) |> switch_document(previous)

      # 2A puts the remembered height on the host, so what arrives here is
      # whatever the host stored - possibly from a build with a different band,
      # possibly nothing at all. It is bounded on the way in rather than on the
      # way to the style attribute, so every reader sees one value.
      socket =
        if Map.has_key?(assigns, :drawer_height) do
          assign(socket, :drawer_height, Shell.clamp_height(assigns.drawer_height))
        else
          socket
        end

      # An opening state, so it is read only until the first measurement has
      # been taken - and a document the host swapped in is an opening of its
      # own, which is why the swap flag reaches here. See the moduledoc's
      # *opening at a fit*.
      socket =
        if Map.has_key?(assigns, :fit) do
          arm_fit(socket, held_fit, Shell.fit_mode(assigns.fit), swapped?)
        else
          socket
        end

      # Normalized once per update rather than once per render: the declared
      # set is the host's input, and it changes when the host changes it, not
      # when the author moves a block.
      socket =
        if Map.has_key?(assigns, :datamodel) do
          assign(socket, :declared_paths, Datamodel.declared_paths(assigns.datamodel))
        else
          socket
        end

      # The host's `:declare` roots, normalized on the same schedule and
      # behind the same `send_update/3` guard as the datamodel above: they
      # are the host's input too, and they change when the host changes them.
      socket =
        if Map.has_key?(assigns, :declare) do
          assign(socket, :host_roots, Datamodel.declared_roots(assigns.declare))
        else
          socket
        end

      # A mark is written only by an update that carries it. `send_update/3`
      # delivers the keys it names and nothing else, so a mark read straight
      # out of the assigns would vanish on the next re-render the host made
      # for a reason of its own. Same guard as `datamodel` above, for the same
      # reason, and after `switch_document/2` above so a host that swaps a
      # document and marks it in one update gets the marks it just passed.
      socket =
        if Map.has_key?(assigns, :active_marks) do
          marks = active_list(assigns.active_marks)

          socket |> assign(:active_marks, marks) |> assign(:active_ids, MapSet.new(marks))
        else
          socket
        end

      socket =
        if Map.has_key?(assigns, :invoke_mark) do
          assign(socket, :invoking, invoke_mark(assigns.invoke_mark))
        else
          socket
        end

      socket =
        if Map.has_key?(assigns, :history_limit) and socket.assigns.history.undo == [] do
          assign(socket, :history, History.new(limit: socket.assigns.history_limit))
        else
          socket
        end

      {:ok, rebuild(socket)}
    end

    @doc """
    How many findings the document has, from the assigns a host already holds.

    This is the same number the drawer's Findings tab reports, computed by the
    same code - see the moduledoc's *findings number a host may show* for why
    the seam takes inputs rather than reading component state, and
    `StatifierBlocks.Shell.findings_count/1` for what is inside the number.

    `opts` mirrors the assigns of the same name, and defaults to the
    component's defaults:

      * `:findings` - the caller-supplied findings, `[]` by default.
      * `:datamodel` - the paths the host declares, `nil` by default, which
        per ADR-0005 amendment 11f turns the undeclared-path advisories off
        entirely rather than declaring that the document addresses nothing.
      * `:declare` - the roots the host will pass the compiler, `[]` by
        default, which per amendment 11m declares none. The document's own
        roots need no option: they are read off `document`.
      * `:chart_outcomes` - what the host says its stored documents finish
        with, `%{}` by default, which says nothing about any chart and so
        reports no subchart disagreement (sb-r4w7).
    """
    @spec findings_count(Document.t(), Palette.t(), keyword()) :: non_neg_integer()
    def findings_count(%Document{} = document, %Palette{} = palette, opts \\ []) do
      %ViewModel{findings: findings} =
        view_model(
          document,
          palette,
          Keyword.get(opts, :findings, []),
          Keyword.get(opts, :datamodel),
          Keyword.get(opts, :declare, []),
          Keyword.get(opts, :chart_outcomes, %{})
        )

      Shell.findings_count(findings)
    end

    slot(:header,
      doc: """
      The host's outer header (8A): document identity, the document switcher,
      the theme control, compile and publish. The package renders the slot's
      markup and none of its own, and a host that fills nothing gets no header
      element at all.
      """
    )

    @impl Phoenix.LiveComponent
    def render(assigns) do
      # `declared_view` is derived before `drawer` and read back out of the
      # assigns by it, rather than derived twice: the strip's count for that
      # tab is the number of rows the panel draws, and two derivations of one
      # projection is the drift the count is supposed to report on. Its
      # `Map.get_lazy/3` there is for the other caller - `handle_event/3`'s
      # tab resolution runs against the socket's assigns, which is a render
      # earlier than this line.
      assigns = assign(assigns, :declared_view, declared_view(assigns))

      assigns =
        assigns
        |> assign(:declared_types, Datamodel.declared_types(assigns.datamodel))
        |> assign(:environment_view, environment_view(assigns))

      assigns =
        assigns
        |> assign(:drawer, drawer_view(assigns))
        |> assign(:declarations, declaration_entries(assigns))
        |> assign(:path_candidates, path_candidates(assigns))
        |> assign(:offered_values, offered_values(assigns))
        |> assign(:event_candidates, event_candidates(assigns))
        |> assign(:outcome_candidates, chart_outcome_candidates(assigns))
        |> assign(:capture_pairs, capture_pairs(assigns))
        |> assign(:capture_sources, capture_sources(assigns))
        |> assign(:declaration_refusal, declaration_refusal(assigns))
        |> assign(:marks, marks(assigns))
        |> assign(:fit_target, fit_target(assigns))
        |> assign(:depth, Shell.depth(assigns.view_model.root))
        |> assign(:block_count, Shell.block_count(assigns.view_model.root))
        |> assign(:edges, Connectors.edges(assigns.view_model.root, assigns.measurement))
        |> assign(:stage, Connectors.stage(assigns.measurement))
        |> assign(
          :insert_target,
          Shell.insert_target(assigns.view_model.root, assigns.palette_position)
        )

      ~H"""
      <div
        class={["sb-editor", @class]}
        id={@id}
        data-revision={@view_model.revision}
        data-zoom={@zoom}
        data-fit={@fit}
        data-fit-pending={@fit_pending}
        data-inserting={to_string(@palette_position != nil)}
        phx-window-keydown={@palette_position != nil && "palette-close"}
        phx-key={@palette_position != nil && "Escape"}
        phx-target={@myself}
      >
        <header :if={@header != []} class="sb-editor__header">
          {render_slot(@header)}
        </header>

        <div
          class="sb-editor__layout"
          data-palette={if @palette_collapsed, do: "collapsed", else: "expanded"}
          data-inspector={if @inspector_collapsed, do: "collapsed", else: "expanded"}
        >
          <PaletteBrowser.palette_browser
            groups={@view_model.palette_groups}
            query={@palette_query}
            allowed={@palette_allowed}
            sheet_open={@palette_sheet}
            collapsed={@palette_collapsed}
            insert_target={@insert_target}
            unarmed_pick={@palette_unarmed_pick}
            target={@myself}
            icon={@icon}
          />

          <div class="sb-editor__main">
            <Toolbar.toolbar
              zoom={@zoom}
              fit={@fit}
              depth={@depth}
              count={@block_count}
              can_undo?={History.can_undo?(@history)}
              can_redo?={History.can_redo?(@history)}
              fittable?={@fit_target != nil}
              target={@myself}
            />

            <Canvas.canvas
              root={@view_model.root}
              drag={@drag}
              selected_id={@selected_id}
              collapsed={@collapsed_ids}
              marks={@marks}
              armed={@palette_position}
              target={@myself}
              icon={@icon}
              theme={@theme}
              edges={@edges}
              stage={@stage}
              zoom={@zoom}
              viewport={@viewport}
              reveal={@reveal}
            />
          </div>

          <Inspector.inspector
            tab={@inspector_tab}
            collapsed={@inspector_collapsed}
            node={@selected_node}
            slot_label={@selected_slot}
            root={@view_model.root}
            document_findings={@view_model.findings}
            orphan_findings={@view_model.orphan_findings}
            pending={@pending_fields}
            expression_component={@expression_component}
            invoke_types={@invoke_types}
            path_candidates={@path_candidates}
            value_candidates={@offered_values}
            event_candidates={@event_candidates}
            outcome_candidates={@outcome_candidates}
            field_candidates={@field_candidates}
            capture_pairs={@capture_pairs}
            capture_sources={@capture_sources}
            fixtures={@fixtures}
            fixture_runs={@fixture_runs}
            target={@myself}
          />

          <Drawer.drawer
            view={@drawer}
            height={@drawer_height}
            root={@view_model.root}
            host_tabs={Shell.host_tabs(@drawer_tabs)}
            declarations={@declarations}
            declaration_refusal={@declaration_refusal}
            fixture_runs={@fixture_runs}
            declared_view={@declared_view}
            declared_types={@declared_types}
            environment_view={@environment_view}
            focus_tab={@drawer_tab_focus}
            target={@myself}
          />
        </div>
      </div>
      """
    end

    # -------------------------------------------------------------- events

    @impl Phoenix.LiveComponent
    def handle_event("select", %{"block-id" => id}, socket) do
      # The sheet is an overlay over the canvas below 780 (7A), so a selection
      # made from inside it has to put it away - otherwise the block the author
      # just chose is behind the thing they chose it from.
      {:noreply, socket |> assign(selected_id: id, palette_sheet: false) |> rebuild()}
    end

    # ------------------------------------------------------------ measurement
    #
    # The 2026-08-29 amendment to decision 7, and the only event in this
    # module that is not an author's intent. `StatifierBlocksMeasure` pushes
    # the boxes the browser laid out; this stores them and nothing else.
    #
    # It touches no document, no history entry, no selection, no draft and no
    # finding - which is clause 7b's distinction between an input and a
    # decision, expressed as the shape of one clause. Feed it a different
    # measurement and the same document comes back. The payload crosses from
    # the DOM, so it is decoded by a total function rather than pattern
    # matched: `Connectors.measurement/1` drops what it cannot read and
    # anything unreadable at all becomes the empty measurement, which is the
    # same state the editor holds before the first push and with no hook
    # imported at all.
    # Two values come out of one payload and they are read by different
    # things: the anchors and the stage extent are what the connectors are
    # routed from, and the scroller's own box is what the two fits are
    # computed against. Neither is a command and neither is stored anywhere
    # but here.
    def handle_event("measure", params, socket) do
      {:noreply,
       socket
       |> assign(:measurement, Connectors.measurement(params))
       |> assign(:viewport, Shell.viewport(params))
       |> open_at_fit()
       |> assign(:measured?, true)}
    end

    # ---------------------------------------------------------------- shell
    #
    # The 2026-08-29 shell amendment, and every one of its gestures is a
    # server-side command: no hook, no resize observer, no client-side state.
    # Decision 7 ships one JavaScript hook and this section adds none.

    def handle_event("zoom-in", _params, socket),
      do: {:noreply, assign(socket, zoom: Shell.zoom_in(socket.assigns.zoom), fit: :manual)}

    def handle_event("zoom-out", _params, socket),
      do: {:noreply, assign(socket, zoom: Shell.zoom_out(socket.assigns.zoom), fit: :manual)}

    # A mode AND a measurement, since the measurement hook landed. The mode is
    # still what the canvas carries as `data-fit` and what the pressed button
    # reads back; the number beside it is the largest ladder step at which the
    # measured thing fits the measured scroller, which is a fit an author can
    # see rather than a state an author has to trust. With nothing measured -
    # no hook imported, or the first frame not yet rendered - `fit_zoom/3`
    # returns the step already in force and the mode is all that changes,
    # which is exactly the behaviour that shipped before this.
    def handle_event("fit", %{"fit" => "width"}, socket) do
      {:noreply,
       socket
       |> assign(:fit, :width)
       |> assign(:zoom, fit_zoom(socket, Connectors.stage(socket.assigns.measurement)))}
    end

    # `Fit active` fits the card `fit_target/1` names - the selection, or the
    # first run mark when there is no selection - and then brings it into
    # view, and the second half is the one the server cannot do: a scroll
    # position is not a document value and no stylesheet sets one. So the
    # canvas is stamped with the block to reveal and a counter that makes the
    # stamp change, and the drag hook carries it out once per press.
    def handle_event("fit", %{"fit" => "active"}, socket) do
      case fit_target(socket.assigns) do
        nil ->
          {:noreply, socket}

        id ->
          {:noreply,
           socket
           |> assign(:fit, :active)
           |> assign(
             :zoom,
             fit_zoom(socket, Map.get(socket.assigns.measurement, Connectors.card_anchor(id)))
           )
           |> assign(:reveal, reveal(socket.assigns.reveal, id))}
      end
    end

    def handle_event("fit", _params, socket), do: {:noreply, socket}

    # The refresh is here for the same reason it is on `drawer-tab`: picking
    # the Fixtures tab is the moment its rows are first wanted, and without it
    # the tab would draw its empty state until something else moved the
    # document.
    def handle_event("inspector-tab", %{"tab" => tab}, socket),
      do:
        {:noreply,
         socket |> assign(:inspector_tab, Shell.inspector_tab(tab)) |> refresh_fixture_runs()}

    # `drawer_tab_focus` is cleared here and on every other route into the
    # drawer for the reason `StatifierBlocks.Editor.Drawer`'s moduledoc gives:
    # it is a one-shot instruction to move DOM focus, and a drawer that
    # re-opened with it still set would take focus off whatever the author was
    # on.
    def handle_event("drawer-open", _params, socket),
      do:
        {:noreply,
         socket |> assign(drawer_open: true, drawer_tab_focus: nil) |> refresh_fixture_runs()}

    def handle_event("drawer-close", _params, socket),
      do: {:noreply, assign(socket, drawer_open: false, drawer_tab_focus: nil)}

    # Tabs since R4, and the pick is remembered as `nil` until it is made:
    # `Shell.drawer_view/1` resolves an unchosen tab to whichever one actually
    # holds something, and a pick that lands here stops it resolving. Fixture
    # runs are consumed as of `sb-4yze` (`refresh_fixture_runs/1` below); the
    # datamodel view is the last reserved entry filled, and like the tabs
    # before it, it needs no second handler here - it is derived in `render/1`
    # from assigns this module already holds. Neither does a host's
    # tab: it is resolved against the ids the host is currently contributing,
    # and a pick is stored the same way whichever side named it.
    def handle_event("drawer-tab", %{"tab" => tab}, socket) do
      picked = Shell.drawer_tab(tab, host_tab_ids(socket.assigns))

      {:noreply,
       socket
       |> assign(drawer_tab_id: picked, drawer_tab_focus: nil)
       |> refresh_fixture_runs()}
    end

    # WAI-ARIA's tablist arrow keys, server-side. The drawer's moduledoc
    # carries the reasoning - why there is no hook, why activation is
    # automatic, and how focus follows - and this is the whole of the
    # mechanism: the strip reports the key and the tab it is on, and the pick
    # lands in the same assign a click lands in, beside the one-shot focus
    # instruction the strip reads back.
    #
    # A key that moves nothing answers `:noreply` with no assign at all rather
    # than re-assigning the tab it is already on: every keystroke inside the
    # strip arrives here, including the Enter and Space that activate the
    # focused button, and a handler that touched state on each of them would
    # make a diff out of typing.
    def handle_event("drawer-tab-key", %{"key" => key, "tab" => tab}, socket) do
      host_ids = host_tab_ids(socket.assigns)
      ids = Shell.drawer_tabs() ++ host_ids

      case drawer_tab_step(key, Shell.drawer_tab(tab, host_ids), ids) do
        nil ->
          {:noreply, socket}

        picked ->
          {:noreply,
           socket
           |> assign(drawer_tab_id: picked, drawer_tab_focus: picked)
           |> refresh_fixture_runs()}
      end
    end

    # 2A's resize, in one round trip. The height is bounded here and handed to
    # the host, which is where a per-viewer preference belongs: the package has
    # no viewer, and a component that persists one has quietly acquired a
    # session.
    def handle_event("drawer-resize", %{"height" => height}, socket) do
      clamped = Shell.clamp_height(height)

      case socket.assigns.on_drawer_resize do
        fun when is_function(fun, 1) -> fun.(clamped)
        _none -> :ok
      end

      {:noreply, assign(socket, :drawer_height, clamped)}
    end

    def handle_event("palette-sheet", _params, socket),
      do: {:noreply, update(socket, :palette_sheet, &(not &1))}

    # Parity item 1.1's fold, in the same shape as every other gesture in this
    # section: one boolean, one round trip, no hook. It is deliberately NOT
    # reset by `switch_document/2` alongside the sheet - the sheet covers the
    # canvas and a new document's blocks under the old one's sheet is a defect,
    # whereas a folded palette is the author saying they want the width, and
    # that preference does not stop being true because a different document
    # opened.
    #
    # The width it frees is the stylesheet's to give back: the layout carries
    # the state as `data-palette` and rebinds `--sb-palette-width`, so nothing
    # here measures anything. Below 780 there is no column to narrow and the
    # header the chevron sits in is not on screen, which is why this pairs with
    # no breakpoint of its own.
    def handle_event("palette-collapse", _params, socket),
      do: {:noreply, update(socket, :palette_collapsed, &(not &1))}

    # The other pane's fold, in the shape the one above already has: one
    # boolean, one round trip, no hook, and the width given back by the
    # stylesheet reading `data-inspector` off the layout.
    #
    # It is the second pane fold, which the shell amendment refused once and
    # ADR-0005's amendment of 2026-08-30 on the shell arrangement grants. Like
    # the palette's it is deliberately NOT reset by `switch_document/2`: a pane
    # fold addresses no block, so nothing about it stops being true when a
    # different document opens - the same sentence that amendment's decision 2
    # section writes to exempt the palette from the collapsed-ids reset.
    def handle_event("inspector-collapse", _params, socket),
      do: {:noreply, update(socket, :inspector_collapsed, &(not &1))}

    # A container folds shut. One server event, one MapSet, in the shape the
    # palette's fold above already has - and, like it, no hook and no client
    # state: the collapsed face is markup the server rendered.
    #
    # It is deliberately NOT an `Edit` command. Decision 2's four commands are
    # the DOCUMENT's algebra; which containers this author has folded shut is
    # not in the document, is not undoable, and is not serialized, so it lives
    # here beside `selected_id` and is reset by `switch_document/2` the way a
    # selection is. ADR-0005's amendment on decision 2 (2026-08-30) records
    # that, and records that the four-command set did not change to admit it.
    def handle_event("collapse-toggle", %{"block-id" => id}, socket) do
      {:noreply,
       update(socket, :collapsed_ids, fn ids ->
         if MapSet.member?(ids, id), do: MapSet.delete(ids, id), else: MapSet.put(ids, id)
       end)}
    end

    # One round-trip, one enumeration. Everything the client needs for the
    # rest of the drag is in the markup this re-render produces.
    #
    # The root is excluded before the enumeration rather than after it. It has
    # no valid target in any case - `Edit.apply/2`'s `check_not_root/2`
    # refuses a `:move` of the root, so the correct answer is the empty set,
    # and `Targets.slot_verdicts/3` (which the drag session runs) now
    # independently arrives at the same empty set (rule 4 excludes the root's
    # own subtree, which is every block). The guard stays because it says why
    # the answer is empty at the place that asks, and it short-circuits an
    # enumeration whose result is known; it is not a workaround for the `MatchError`
    # `Assignability.valid_targets/4` used to raise here (sb-rzr).
    def handle_event("dragstart", %{"block-id" => id}, socket) do
      {:noreply, assign(socket, :drag, drag_session(socket, id))}
    end

    def handle_event("dragend", _params, socket) do
      {:noreply, assign(socket, :drag, nil)}
    end

    def handle_event("drop", params, socket) do
      %{"block-id" => id, "parent-id" => parent_id, "slot" => slot, "index" => index} = params

      socket =
        socket
        |> assign(:drag, nil)
        |> commit({:move, id, {parent_id, slot, to_index(index)}})

      {:noreply, socket}
    end

    # The insert half of the drag (sb-4nep). Same two round-trips, same one
    # enumeration, same markup: what differs is that the thing being carried
    # is a TYPE the document does not hold yet rather than a block it does, so
    # the verdicts are asked of a probe block - `Targets.slot_verdicts/3`
    # against a block that is not in the document, which is the case
    # `accepted_types/3` already uses one type at a time and this uses once.
    #
    # A palette entry the palette cannot resolve gets an empty session rather
    # than an error: every slot then stamps `data-drop="no"`, which is the
    # honest answer and the one that refuses the drop in the client before it
    # is ever pushed.
    def handle_event("insert-dragstart", %{"type" => type}, socket) do
      {:noreply, assign(socket, :drag, insert_drag_session(socket, type))}
    end

    # The drop reuses the pick's path exactly - `insert_from_palette/3` mints
    # the block, commits the one `:insert`, and clears the armed mode with it.
    # The position comes from the gap rather than from `palette_position`,
    # because a drag names its destination by landing on it; arming is the
    # other gesture's way of naming the same thing.
    def handle_event("insert-drop", params, socket) do
      %{"type" => type, "parent-id" => parent_id, "slot" => slot, "index" => index} = params

      socket =
        socket
        |> assign(:drag, nil)
        |> insert_from_palette(type, {parent_id, slot, to_index(index)})

      {:noreply, socket}
    end

    def handle_event("remove", %{"block-id" => id}, socket) do
      socket =
        socket
        |> update(:selected_id, fn selected -> if selected == id, do: nil, else: selected end)
        |> update(:drafts, &Map.delete(&1, id))
        |> commit({:remove, id})

      {:noreply, socket}
    end

    def handle_event("undo", _params, socket) do
      %{history: history, palette: palette, document: document} = socket.assigns
      {:noreply, replay(socket, History.undo(history, palette, document))}
    end

    def handle_event("redo", _params, socket) do
      %{history: history, palette: palette, document: document} = socket.assigns
      {:noreply, replay(socket, History.redo(history, palette, document))}
    end

    # d8: the "+" path. The palette opens filtered by the same predicate a
    # drag uses, against a probe block of each candidate type.
    def handle_event("palette-open", params, socket) do
      %{"parent-id" => parent_id, "slot" => slot, "index" => index} = params
      position = {parent_id, slot, to_index(index)}

      {:noreply,
       assign(socket,
         palette_position: position,
         palette_allowed: accepted_types(socket, parent_id, slot),
         palette_query: "",
         palette_collapsed: false
       )}
    end

    def handle_event("palette-close", _params, socket) do
      {:noreply,
       assign(socket,
         palette_position: nil,
         palette_allowed: nil,
         palette_unarmed_pick: false
       )}
    end

    def handle_event("palette-search", %{"q" => query}, socket) do
      {:noreply, assign(socket, :palette_query, query)}
    end

    # A recipe pick and a type pick are the same gesture on the same event;
    # what differs is which of the palette's two maps the name is looked up
    # in (ADR-0005 clause 1C), so the row sends `recipe` rather than `type`
    # and this clause sits above the type one.
    def handle_event("palette-pick", %{"recipe" => name}, socket) do
      socket = assign(socket, :palette_sheet, false)
      {:noreply, insert_from_recipe(socket, name, socket.assigns.palette_position)}
    end

    def handle_event("palette-pick", %{"type" => type}, socket) do
      socket = assign(socket, :palette_sheet, false)
      {:noreply, insert_from_palette(socket, type, socket.assigns.palette_position)}
    end

    def handle_event("config-change", %{"block-id" => id} = params, socket) do
      config = ConfigForm.decode(fields_for(socket, id), params, effective_config(socket, id))
      {:noreply, change_config(socket, id, config)}
    end

    # A draft is config the document never accepted, so there is no command
    # to invert and no history entry to step back through - discarding is the
    # only way out of one, and the form returns to what the document holds.
    def handle_event("discard-draft", %{"block-id" => id}, socket) do
      {:noreply, socket |> update(:drafts, &Map.delete(&1, id)) |> rebuild()}
    end

    def handle_event("field-list-add", %{"key" => key}, socket) do
      {:noreply, update_list(socket, key, &(&1 ++ [""]))}
    end

    def handle_event("field-list-remove", %{"key" => key, "index" => index}, socket) do
      {:noreply, update_list(socket, key, &List.delete_at(&1, to_index(index)))}
    end

    # The declarations panel (the 2026-09-01 amendment, 2i-2m). Four gestures,
    # one command: each builds a candidate list with
    # `StatifierBlocks.Declarations` and hands it to `{:set_datamodel, list}`,
    # which is the only thing that writes the key.
    def handle_event("declaration-add", _params, socket) do
      {:noreply, set_declarations(socket, &Declarations.add/1)}
    end

    def handle_event("declaration-remove", %{"index" => index}, socket) do
      {:noreply, set_declarations(socket, &Declarations.remove(&1, declaration_index(index)))}
    end

    def handle_event("declaration-move", %{"index" => index, "dir" => dir}, socket) do
      {:noreply, set_declarations(socket, &Declarations.move(&1, declaration_index(index), dir))}
    end

    def handle_event("declaration-change", %{"index" => index} = params, socket) do
      {:noreply,
       set_declarations(socket, &Declarations.change(&1, declaration_index(index), params))}
    end

    # ------------------------------------------------------------ commands

    # The one place a command reaches the document. Every gesture funnels
    # here, so the gate, the undo stack and the host notification each have
    # one implementation rather than one per event.
    @spec commit(Phoenix.LiveView.Socket.t(), Edit.t()) :: Phoenix.LiveView.Socket.t()
    defp commit(socket, command) do
      %{history: history, palette: palette, document: document} = socket.assigns

      case History.commit(history, palette, document, command) do
        {:ok, new_history, new_document} ->
          socket
          |> assign(history: new_history, document: new_document, last_error: nil)
          |> notify_change(new_document)
          |> rebuild()

        {:error, reason} ->
          socket |> assign(:last_error, reason) |> rebuild()
      end
    end

    # The declarations panel's own funnel (2l). It differs from `commit/2` in
    # one way and only one: a refusal is held as a DRAFT of the list the
    # author typed, with the sentence saying why, instead of landing in
    # `last_error`. That is decision 9's draft treatment applied to the second
    # surface that has the same problem - a value the document refuses is
    # still the value the author is holding, and blanking it back to the
    # document's would delete their keystrokes to punish a typo.
    @spec set_declarations(
            Phoenix.LiveView.Socket.t(),
            ([DatamodelEntry.t()] -> [DatamodelEntry.t()])
          ) :: Phoenix.LiveView.Socket.t()
    defp set_declarations(socket, fun) do
      %{document: document} = socket.assigns
      candidate = fun.(declaration_entries(socket.assigns))

      if candidate == document.datamodel do
        # A gesture that lands on what the document already holds commits
        # nothing (2k). Every function in `StatifierBlocks.Declarations`
        # answers an out-of-range index with the list unchanged, and the ends
        # of the list answer a move the same way, so without this the first
        # row's Up would push an undo entry that undoes nothing and notify the
        # host of a document that did not move. A draft is still cleared:
        # typing back to the document's own value is exactly the author
        # resolving the refusal that produced it.
        socket |> assign(:declaration_draft, nil) |> rebuild()
      else
        commit_declarations(socket, candidate)
      end
    end

    @spec commit_declarations(Phoenix.LiveView.Socket.t(), [DatamodelEntry.t()]) ::
            Phoenix.LiveView.Socket.t()
    defp commit_declarations(socket, candidate) do
      %{history: history, palette: palette, document: document} = socket.assigns

      case History.commit(history, palette, document, {:set_datamodel, candidate}) do
        {:ok, new_history, new_document} ->
          socket
          |> assign(
            history: new_history,
            document: new_document,
            declaration_draft: nil,
            last_error: nil
          )
          |> notify_change(new_document)
          |> rebuild()

        {:error, reason} ->
          socket
          |> assign(
            :declaration_draft,
            %{entries: candidate, refusal: Declarations.refusal(reason)}
          )
          |> rebuild()
      end
    end

    # Undo and redo differ only in which stack they pop, and `History` has
    # already done that by the time this runs - so both arrive here as the
    # same result tuple and there is one place that reconciles the socket.
    # Drafts are dropped wholesale: a draft is by definition config the
    # document never accepted, and keeping one across a history move would
    # mean showing the author a value that belongs to a document state they
    # just stepped out of.
    @spec replay(Phoenix.LiveView.Socket.t(), {:ok, History.t(), Document.t()} | {:error, term()}) ::
            Phoenix.LiveView.Socket.t()
    defp replay(socket, result) do
      case result do
        {:ok, new_history, new_document} ->
          socket
          |> assign(history: new_history, document: new_document, drafts: %{}, last_error: nil)
          |> notify_change(new_document)
          |> rebuild()

        {:error, reason} ->
          socket |> assign(:last_error, reason) |> rebuild()
      end
    end

    # Ids are minted here, at gesture time, and baked into the `:insert`
    # (decision 2). That is what keeps the recorded command serializable and
    # a command log replayable: duplication and palette insertion need
    # entropy, and admitting an id generator into the pure algebra would
    # have cost it determinism.
    @spec insert_from_palette(Phoenix.LiveView.Socket.t(), Block.type_name(), Edit.target() | nil) ::
            Phoenix.LiveView.Socket.t()
    defp insert_from_palette(socket, _type, nil),
      do: assign(socket, :palette_unarmed_pick, true)

    defp insert_from_palette(socket, type, position) do
      case new_block(socket.assigns.palette, type) do
        {:ok, block} ->
          socket
          |> assign(
            palette_position: nil,
            palette_allowed: nil,
            palette_unarmed_pick: false,
            selected_id: block.id
          )
          |> commit({:insert, position, block})

        :error ->
          assign(socket, :last_error, {:unknown_block_type, type})
      end
    end

    # A recipe pick (clause 2C). The recipe is handed the armed position and
    # the document and answers with the commands that build the arrangement;
    # they go in as ONE `{:compound, commands}`, which is what makes the
    # arrangement one undo entry rather than one per block (clause 2n).
    #
    # Two refusals, and they are different in kind. `insert/2` refusing -
    # a deadline armed where the enclosing block has no interrupts rail -
    # is the ordinary case clause 3C names, and nothing is written. A list
    # that reaches outside clause 3C's bound is a recipe module's bug, and
    # it is refused HERE, before it is applied, rather than trusted.
    @spec insert_from_recipe(
            Phoenix.LiveView.Socket.t(),
            Palette.recipe_name(),
            Edit.target() | nil
          ) :: Phoenix.LiveView.Socket.t()
    defp insert_from_recipe(socket, _name, nil),
      do: assign(socket, :palette_unarmed_pick, true)

    defp insert_from_recipe(socket, name, position) do
      with {:ok, module} <- Palette.fetch_recipe(socket.assigns.palette, name),
           {:ok, commands} <- module.insert(position, socket.assigns.document),
           true <- Recipe.within_reach?(position, commands) do
        socket
        |> assign(
          palette_position: nil,
          palette_allowed: nil,
          palette_unarmed_pick: false,
          selected_id: first_inserted_id(commands) || socket.assigns.selected_id
        )
        |> commit({:compound, commands})
      else
        false -> refused(socket, {:recipe_out_of_reach, name})
        {:error, reason} -> refused(socket, reason)
      end
    end

    @spec refused(Phoenix.LiveView.Socket.t(), term()) :: Phoenix.LiveView.Socket.t()
    defp refused(socket, reason), do: socket |> assign(:last_error, reason) |> rebuild()

    @spec first_inserted_id([Edit.t()]) :: Block.id() | nil
    defp first_inserted_id(commands) do
      Enum.find_value(commands, fn
        {:insert, _target, %Block{id: id}} -> id
        _other_command -> nil
      end)
    end

    @spec new_block(Palette.t(), Block.type_name()) :: {:ok, Block.t()} | :error
    defp new_block(palette, type) do
      case Palette.fetch(palette, type) do
        {:ok, module} ->
          config =
            %{}
            |> module.config_schema()
            |> Map.new(fn %{key: key, default: default} -> {key, default} end)

          {:ok, Block.new(type, config: config, type_version: module.current_version())}

        _error ->
          :error
      end
    end

    @spec change_config(Phoenix.LiveView.Socket.t(), Block.id(), Block.config()) ::
            Phoenix.LiveView.Socket.t()
    defp change_config(socket, id, config) do
      %{history: history, palette: palette, document: document} = socket.assigns

      case History.commit(history, palette, document, {:update_config, id, config}) do
        {:ok, new_history, new_document} ->
          socket
          |> assign(history: new_history, document: new_document, last_error: nil)
          |> update(:drafts, &Map.delete(&1, id))
          |> notify_change(new_document)
          |> rebuild()

        {:error, {:invalid_config, ^id, _findings}} ->
          socket |> update(:drafts, &Map.put(&1, id, config)) |> rebuild()

        {:error, reason} ->
          socket |> assign(:last_error, reason) |> rebuild()
      end
    end

    # `key` arrives from the row's `phx-value-key`, which is the field's
    # identity rather than its address - so the rows are read and written
    # through the field's own `value_path` (ADR-0002 decision 7, amended
    # 2026-08-27), the same place the form's other writes go. A key naming
    # no field in the selected block's schema edits nothing, which is the
    # same crafted-payload guard `ConfigForm.decode/3` applies.
    @spec update_list(Phoenix.LiveView.Socket.t(), String.t(), ([term()] -> [term()])) ::
            Phoenix.LiveView.Socket.t()
    defp update_list(socket, key, fun) do
      with id when not is_nil(id) <- socket.assigns.selected_id,
           %ViewModel.Field{} = field <- Enum.find(fields_for(socket, id), &(&1.key == key)) do
        config = effective_config(socket, id)
        path = ViewModel.Field.value_path(field)

        rows =
          case BlockType.fetch_value(config, path) do
            {:ok, value} -> List.wrap(value)
            :error -> []
          end

        change_config(socket, id, BlockType.put_value(config, path, fun.(rows)))
      else
        _none -> socket
      end
    end

    # 2A: the drawer closes on a document switch. A drawer left open across one
    # would be showing the new document's blocks under the old one's subject,
    # and the selection it follows names a block that is not there any more -
    # so the selection goes with it, along with the drafts and the pending
    # insert, all three of which address ids the new document does not hold.
    #
    # `collapsed_ids` goes for the same reason and by the same rule: it is a
    # set of block ids, and a block id from the old document names nothing in
    # the new one. The palette's own fold is the deliberate exception above -
    # it addresses no block, so nothing about it stops being true.
    #
    # It answers with the socket *and* whether the identity actually changed,
    # because `arm_fit/4` needs the same answer and there is only one place
    # that knows it. The flag is returned rather than assigned: it is true for
    # the length of one `update/2` and an assign would still be true on the
    # next render, which is precisely the host re-render that must not re-fit.
    @spec switch_document(Phoenix.LiveView.Socket.t(), Document.t() | nil) ::
            {Phoenix.LiveView.Socket.t(), boolean()}
    # No previous document is the FIRST one, which is an opening like any
    # other and takes the same folds the reset below takes.
    defp switch_document(socket, nil),
      do:
        {assign(socket, :collapsed_ids, opening_folds(Map.get(socket.assigns, :document))), false}

    defp switch_document(socket, %Document{id: id}) do
      if socket.assigns.document.id == id do
        {socket, false}
      else
        socket =
          assign(socket,
            drawer_open: false,
            drawer_tab_id: nil,
            drawer_tab_focus: nil,
            selected_id: nil,
            drafts: %{},
            declaration_draft: nil,
            palette_position: nil,
            palette_allowed: nil,
            palette_unarmed_pick: false,
            palette_sheet: false,
            # A mark addresses one block, so it stops being true when that
            # block is gone. The amendment's exemption from this reset is the
            # pane folds', and for the reason that does not reach a mark: a
            # fold addresses no block at all.
            active_marks: [],
            active_ids: MapSet.new(),
            invoking: nil
          )

        # The collapsed set resets to the new document's opening folds rather
        # than to the empty set, so a document the host swaps in opens the way
        # that same document opens when it is the first one.
        #
        # Assigned on its own rather than as another key in the list above,
        # and that is load-bearing: every value in that list is a literal, and
        # a computed `MapSet` among them costs Dialyzer its read of what this
        # clause returns - it stops seeing the `true`, and reports `arm_fit/4`'s
        # swapped-document clause as unreachable.
        {assign(socket, :collapsed_ids, opening_folds(socket.assigns.document)), true}
      end
    end

    # The one fold this component starts with, rather than the empty set the
    # 2026-08-30 amendment's decision 2 section left it at: a NON-EMPTY drafts
    # shelf opens folded (`sb-e2zy`, the campaign-024 wrap ruling).
    #
    # It changes the INITIAL value and nothing else. `collapse-toggle` above
    # is untouched, the set is still per-session editor state that is neither
    # in the document nor on the undo stack, and it is still reset by the
    # document swap below - this function is what the reset resets *to*, so
    # opening a document and swapping one in behave the same way, which is
    # the sentence the fit note already had to write for its own opening.
    #
    # Non-empty only. A shelf holding nothing has nothing to hide, and its
    # tray IS the drop target an author parks the first fragment onto: an
    # editor that folded it shut would have folded away the affordance. The
    # ruling says an empty tray may stay as it is, and this is that.
    #
    # `Shelf.shelves/1` rather than a walk of the view model: the fold is
    # keyed on a block id and the document is what holds those, so this needs
    # no rebuild to have happened first. More than one shelf is a Structure
    # finding rather than this function's business (ADR-0002 G12b), so it
    # folds every one it finds instead of assuming the document is valid.
    @spec opening_folds(Document.t() | nil) :: MapSet.t(String.t())
    defp opening_folds(%Document{} = document) do
      document
      |> Shelf.shelves()
      |> Enum.filter(&stocked?/1)
      |> MapSet.new(& &1.id)
    end

    defp opening_folds(_none), do: MapSet.new()

    @spec stocked?(Block.t()) :: boolean()
    defp stocked?(%Block{slots: slots}),
      do: Enum.any?(slots, fn {_name, children} -> children != [] end)

    # Total, like every other host-input normalizer here, and for a reason
    # this one has more of than most: a host holding a run's state is holding
    # it in whatever shape its own runtime produced. The editor's answer to a
    # shape it does not recognise is to mark nothing, never to raise inside
    # somebody's render.
    #
    # The order is kept rather than normalized away, because `Fit active` with
    # nothing selected fits the first mark, and "first" has to mean the first
    # one the host named. The set the canvas asks its membership question
    # against is derived from this list at the same moment.
    @spec active_list(term()) :: [String.t()]
    defp active_list(%MapSet{} = ids), do: MapSet.to_list(ids)

    defp active_list(ids) when is_list(ids),
      do: Enum.filter(ids, &(is_binary(&1) and &1 != ""))

    defp active_list(_other), do: []

    # `{block_id, outcome}` is what the mark is: which block, and how the call
    # came back. A bare id is the same mark with no answer yet - the state a
    # call spends most of its life in - so it is worth not making a caller
    # write `{id, nil}` for it.
    @spec invoke_mark(term()) :: {String.t(), String.t() | nil} | nil
    defp invoke_mark(id) when is_binary(id) and id != "", do: {id, nil}

    defp invoke_mark({id, outcome}) when is_binary(id) and id != "",
      do: {id, outcome_text(outcome)}

    defp invoke_mark(_other), do: nil

    # The outcome reaches the markup as the host's own text. An atom is
    # accepted because a host writing Elixir has one; anything that is not a
    # word is dropped to "no answer yet", which is a state the mark already
    # has rather than a new one invented to hold junk.
    @spec outcome_text(term()) :: String.t() | nil
    defp outcome_text(outcome) when is_binary(outcome) and outcome != "", do: outcome

    defp outcome_text(outcome) when is_atom(outcome) and not is_nil(outcome),
      do: Atom.to_string(outcome)

    defp outcome_text(_other), do: nil

    # Nothing at all when nothing is marked, which is the ordinary case: a
    # document with no run over it threads `nil` down the tree, and every node
    # below skips the question instead of asking a set it knows is empty.
    @spec marks(map()) ::
            %{active: MapSet.t(String.t()), invoke: {String.t(), String.t() | nil} | nil} | nil
    defp marks(%{active_ids: active, invoking: invoking}) do
      if MapSet.size(active) == 0 and invoking == nil do
        nil
      else
        %{active: active, invoke: invoking}
      end
    end

    # What `Fit active` acts on, resolved in one place so the button's enabled
    # state and the handler's answer cannot disagree: a control that is
    # enabled and then does nothing is the defect that pairing them prevents.
    # The selection wins when there is one - it is the author's own answer to
    # which block matters - and the first mark stands in when there is not,
    # which is the whole of what an observer watching a run ever has.
    @spec fit_target(map()) :: String.t() | nil
    defp fit_target(%{selected_id: id}) when is_binary(id), do: id
    defp fit_target(%{active_marks: marks}), do: List.first(marks)

    @spec drawer_view(map()) :: Shell.drawer()
    defp drawer_view(assigns) do
      Shell.drawer_view(%{
        open?: assigns.drawer_open,
        tab: assigns.drawer_tab_id,
        fixtures: assigns.fixtures,
        findings: assigns.view_model.findings,
        orphan_findings: assigns.view_model.orphan_findings,
        host_tabs: assigns.drawer_tabs,
        declarations: assigns.document.datamodel,
        declared_view: Map.get_lazy(assigns, :declared_view, fn -> declared_view(assigns) end),
        selected_id: assigns.selected_id
      })
    end

    # The read-only declared-path view's rows. The RAW `datamodel` assign and
    # not the normalized `declared_paths` set beside it: the set has already
    # thrown the types away, and this panel is the one place the ADR-0006
    # document's shape is drawn. The roots go in normalized, because
    # `declared_roots/1` is idempotent and the assign is where that work has
    # already been done.
    @spec declared_view(map()) :: [Datamodel.declared_row()]
    defp declared_view(assigns) do
      Datamodel.declared_view(assigns.document, assigns.datamodel, assigns.host_roots)
    end

    # "What is known here" (ADR-0011 decision 9): the environment at the
    # SELECTED block's position, as rows the Datamodel tab draws. Nothing
    # selected means there is no position to answer for, and the panel says so
    # rather than showing the seed and calling it the answer.
    #
    # The position is the last step of the path from the root to the block,
    # which is the same `{parent, slot, index}` triple
    # `Assignability.seam_reasons/3` asks the walk with - the block's own
    # position, so what it shows is what that block reads against, before its
    # own writes land.
    @spec environment_view(map()) :: [%{path: String.t(), type: String.t()}] | nil
    defp environment_view(%{selected_id: id} = assigns) when is_binary(id) do
      %{document: document, palette: palette} = assigns
      ctx = assignability_context(assigns)
      declarations = Environment.declarations(ctx)

      case Document.fetch_path(document, id) do
        {:ok, [_first | _rest] = path} ->
          palette
          |> Environment.at(document, List.last(path), ctx)
          |> Enum.sort()
          |> Enum.map(fn {read_path, type} ->
            %{path: read_path, type: Environment.type_label(declarations, type)}
          end)

        _root_or_missing ->
          []
      end
    end

    defp environment_view(_nothing_selected), do: nil

    # The context every data-flow question in this component is asked with: the
    # host's datamodel document and nothing else. `:entry_type` is deliberately
    # absent - the editor is not told what enters the document, and ADR-0011
    # decision 2 seeds empty in that case - so this is one key, named once, and
    # the drop check, the walk and the Datamodel tab cannot drift apart by
    # being handed different ones.
    @spec assignability_context(map()) :: Assignability.context()
    defp assignability_context(%{datamodel: nil}), do: %{}
    defp assignability_context(%{datamodel: datamodel}), do: %{datamodel: datamodel}

    # What the panel draws: the author's refused list while one is held, and
    # the document's otherwise. The COUNT on the strip stays the document's -
    # `drawer_view/1` above is given `assigns.document.datamodel` and not this
    # - because 2A's count is a statement about the document, and a strip that
    # counted a refused draft would report a document that does not exist.
    # The declared datamodel paths an `:expression` control offers (sb-0vt).
    # Read off the ALREADY-NORMALIZED assigns rather than the raw host input:
    # `declared_paths` and `host_roots` are computed once per update above,
    # and `Datamodel.candidates/3` normalizes idempotently, so passing them
    # here reuses that work instead of re-deriving a set per render. The
    # document is passed whole because its own `datamodel` key is the third
    # declaring surface and reading it there is what stops a caller
    # forgetting it.
    @spec path_candidates(map()) :: [String.t()]
    defp path_candidates(assigns) do
      Datamodel.candidates(assigns.document, assigns.declared_paths, assigns.host_roots)
    end

    # The value half of the same question, and the reason it reads
    # `datamodel` rather than `declared_paths`: the normalized set above is a
    # `MapSet` of paths and carries no per-path shape, while the `one_of`
    # enumerations live on the ADR-0006 index the raw document builds. The
    # host's own map is merged over the derived defaults per path, which is
    # replacement at a path and not a union - see
    # `StatifierBlocks.Datamodel.value_candidates/2` and ADR-0005's
    # 2026-09-05 note.
    @spec offered_values(map()) :: %{optional(String.t()) => [Datamodel.candidate()]}
    defp offered_values(assigns) do
      Datamodel.value_candidates(assigns.datamodel, assigns.value_candidates)
    end

    # The completion events a `core.on_event`'s `event` field offers
    # (sb-82mu): every block in the enclosing body that declares outcomes,
    # crossed with those outcomes, written the way the compiler writes them.
    # It is derived here rather than in `StatifierBlocks.ViewModel` for the
    # reason `path_candidates/1` above is: it is a question about the
    # SELECTION, and the view model is a projection of the document that
    # knows nothing about which card is open.
    #
    # Offered for `core.on_event` and for nothing else. `core.send`,
    # `core.raise` and `core.await` each declare an `event` key too, and each
    # names events this list is not about, so the gate is here and the
    # control in `StatifierBlocks.Editor.Field` tests no block type at all.
    #
    # The list suggests and never constrains: `event` stays a `:string` in
    # `config_schema/1`, and a free-typed name validates exactly as it did.
    @spec event_candidates(map()) :: [%{label: String.t(), value: String.t()}]
    defp event_candidates(
           %{selected_node: %ViewModel.Node{type: @on_event_type} = node} = assigns
         ) do
      with {:ok, [_ | _] = path} <- Document.fetch_path(assigns.document, node.block_id),
           {parent_id, _slot, _index} <- List.last(path),
           %Block{} = parent <- block_by_id(assigns.document, parent_id),
           {:ok, module, resolved} <- Palette.resolve(assigns.palette, parent) do
        parent.slots
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.filter(fn {slot, _children} -> body_slot?(module, resolved.config, slot) end)
        |> Enum.flat_map(fn {_slot, children} -> children end)
        |> Enum.flat_map(&outcome_candidates(&1, assigns))
      else
        _no_enclosing_body -> []
      end
    end

    defp event_candidates(_not_an_on_event), do: []

    # The finals a `core.subchart`'s `outcomes` field offers (sb-r4w7): what
    # the host said the chart named in `chart` finishes with, and nothing
    # derived. A block type cannot read the document it references - see
    # `StatifierBlocks.Core.Subchart`'s moduledoc - so this is the one
    # candidate list in the component that is a lookup rather than a
    # derivation, and the assign is the whole of it.
    #
    # Derived here for `event_candidates/1`'s reason: it is a question about
    # the SELECTION, and the view model is a projection of the document that
    # knows nothing about which card is open. Empty for every other selection,
    # so the control in `StatifierBlocks.Editor.Field` tests no block type -
    # and `core.subchart` is the only core type with an `outcomes` key anyway.
    @spec chart_outcome_candidates(map()) :: [String.t()]
    defp chart_outcome_candidates(
           %{selected_node: %ViewModel.Node{type: @subchart_type} = node} = assigns
         ) do
      with %Block{config: config} <- block_by_id(assigns.document, node.block_id),
           chart when is_binary(chart) <- Map.get(config, "chart"),
           names when is_list(names) <- Map.get(assigns.chart_outcomes, chart) do
        Enum.filter(names, &is_binary/1)
      else
        _nothing_said_about_this_chart -> []
      end
    end

    defp chart_outcome_candidates(_not_a_subchart), do: []

    # The selected block's capture pairs, as ordered rows for the two-control
    # row the config form draws (ADR-0011 decision 10). `nil` for every other
    # selection, which is what makes the row absent rather than empty, and it
    # is derived here for `event_candidates/1`'s reason: whether a block
    # takes a capture map is a question about the SELECTION, and the form
    # component tests no block type.
    #
    # The pairs come from the block's effective config - a draft when there
    # is one - so a half-typed row survives the round trip that refuses it.
    # Sorted by target, which is the order the emission already fixes,
    # because a map has none of its own.
    @spec capture_pairs(map()) :: [{String.t(), String.t()}] | nil
    defp capture_pairs(%{selected_node: %ViewModel.Node{type: @on_event_type} = node} = assigns) do
      case Map.get(selected_config(assigns, node.block_id), "capture") do
        pairs when is_map(pairs) ->
          pairs
          |> Enum.filter(fn {target, source} -> is_binary(target) and is_binary(source) end)
          |> Enum.sort_by(fn {target, _source} -> target end)

        _absent_or_not_a_map ->
          []
      end
    end

    defp capture_pairs(_takes_no_capture), do: nil

    # The source keys a capture row offers: the payload of the event this
    # handler waits for, out of its own type's `fixtures/0` (ADR-0011
    # decision 10). A handler's fixture payload is the only place in the
    # package that knows what an event of that name actually carries, and
    # ADR-0002 decision 9's Note already makes a fixture value the hint drawn
    # beside a field.
    #
    # With no fixture there are no candidates and the control is a plain text
    # input, which is what the `{:path, opts}` amendment already says about a
    # path control with no datamodel. A bundle spelled as a path or as a
    # struct this package does not own reads as no fixture: the loader is
    # statifier-ui's, and this package does not depend on it.
    @spec capture_sources(map()) :: [String.t()]
    defp capture_sources(%{selected_node: %ViewModel.Node{type: @on_event_type} = node} = assigns) do
      with %Block{} = block <- block_by_id(assigns.document, node.block_id),
           {:ok, module, resolved} <- Palette.resolve(assigns.palette, block) do
        module
        |> fixture_events()
        |> payload_for(Map.get(resolved.config, "event"))
        |> payload_paths()
      else
        _unresolvable -> []
      end
    end

    defp capture_sources(_takes_no_capture), do: []

    # `fixtures/0`'s events, in the two map spellings this package can read
    # without the loader: atom `:events` and string `"events"`, each a map
    # from event name to one example payload.
    @spec fixture_events(module()) :: %{optional(String.t()) => term()}
    defp fixture_events(module) do
      with true <- Code.ensure_loaded?(module) and function_exported?(module, :fixtures, 0),
           bundle when is_map(bundle) <- module.fixtures(),
           events when is_map(events) <- Map.get(bundle, :events) || Map.get(bundle, "events") do
        events
      else
        _no_readable_events -> %{}
      end
    end

    # The payload the configured event name declares, or - when the config
    # names no event, or names one the bundle has no sample for - every
    # payload the bundle carries. A handler whose event is still empty is
    # offered what its type's samples know rather than nothing at all, which
    # is the same posture the fixture hint takes.
    @spec payload_for(%{optional(String.t()) => term()}, term()) :: [term()]
    defp payload_for(events, event) when is_binary(event) do
      case Map.fetch(events, event) do
        {:ok, payload} -> [payload]
        :error -> Map.values(events)
      end
    end

    defp payload_for(events, _no_event_named), do: Map.values(events)

    # A payload's leaves, as the dotted paths a capture's source names -
    # `_event.data` is the root the emission adds, so the stored source is
    # the path BELOW it. Sorted and distinct, because a suggestion list with
    # a repeat in it is a list somebody has to explain.
    @spec payload_paths([term()]) :: [String.t()]
    defp payload_paths(payloads) do
      payloads
      |> Enum.flat_map(&paths_under("", &1))
      |> Enum.uniq()
      |> Enum.sort()
    end

    @spec paths_under(String.t(), term()) :: [String.t()]
    defp paths_under(prefix, payload) when is_map(payload) do
      Enum.flat_map(payload, fn {key, value} ->
        if is_binary(key) do
          paths_under(join_path(prefix, key), value)
        else
          []
        end
      end)
    end

    defp paths_under("", _leaf), do: []
    defp paths_under(prefix, _leaf), do: [prefix]

    @spec join_path(String.t(), String.t()) :: String.t()
    defp join_path("", key), do: key
    defp join_path(prefix, key), do: prefix <> "." <> key

    # The config a selected block is being edited against: its draft when it
    # has one, and what the document holds when it does not. The same answer
    # `effective_config/2` gives an event handler, asked of assigns because
    # this one runs in `render/1`.
    @spec selected_config(map(), Block.id()) :: Block.config()
    defp selected_config(assigns, id) do
      case Map.fetch(assigns.drafts, id) do
        {:ok, draft} ->
          draft

        :error ->
          case block_by_id(assigns.document, id) do
            %Block{config: config} -> config
            _no_block -> %{}
          end
      end
    end

    # What "the enclosing body" means, asked of the declaration rather than
    # of a slot name: a slot that admits ADR-0003's `:step` kind. That is
    # `body` on `core.group` and `core.resumable_group`, and whatever a host
    # group calls the slot it declares the same way. The handler's own
    # `interrupts` slot declares `[:interrupt_handler]`, so it is excluded by
    # construction rather than by name, and a slot declaring `:any` is not a
    # body declaration - it is the absence of one.
    @spec body_slot?(module(), Block.config(), Block.slot_name()) :: boolean()
    defp body_slot?(module, config, slot) do
      case Assignability.slot_accepts(module, config, slot) do
        kinds when is_list(kinds) -> :step in kinds
        _any_or_other -> false
      end
    end

    # One body block's contribution. A type that does not IMPLEMENT
    # `outcomes/1` contributes nothing: ADR-0002 amendment A1 gives such a
    # type the default single `done`, and offering an author a generated name
    # for an outcome the type never declared is offering them a wire that is
    # not there.
    @spec outcome_candidates(Block.t(), map()) :: [%{label: String.t(), value: String.t()}]
    defp outcome_candidates(%Block{} = block, assigns) do
      with {:ok, module, resolved} <- Palette.resolve(assigns.palette, block),
           true <- declares_outcomes?(module) do
        state_id = StateId.state_id(block.id)
        label = candidate_label(assigns, block)

        for outcome <- BlockType.outcome_names(module, resolved.config) do
          %{
            label: label <> @candidate_separator <> outcome,
            value: StateId.outcome_event(state_id, outcome)
          }
        end
      else
        _no_declared_outcomes -> []
      end
    end

    @spec declares_outcomes?(module()) :: boolean()
    defp declares_outcomes?(module) do
      Code.ensure_loaded?(module) and function_exported?(module, :outcomes, 1)
    end

    # The card's own name, read off the view model through the public
    # `ViewModel.title/1` rather than re-derived from the schema here: the
    # label an author sees on the candidate has to be the label they see on
    # the card, and two derivations of one name is how those drift apart.
    @spec candidate_label(map(), Block.t()) :: String.t()
    defp candidate_label(assigns, %Block{} = block) do
      case find_node(assigns.view_model.root, block.id) do
        %ViewModel.Node{} = node -> ViewModel.title(node)
        nil -> block.type
      end
    end

    @spec block_by_id(Document.t(), Block.id()) :: Block.t() | nil
    defp block_by_id(%Document{} = document, id) do
      document |> Document.blocks() |> Enum.find(&(&1.id == id))
    end

    @spec declaration_entries(map()) :: [DatamodelEntry.t()]
    defp declaration_entries(%{declaration_draft: %{entries: entries}}), do: entries
    defp declaration_entries(assigns), do: assigns.document.datamodel

    @spec declaration_refusal(map()) :: String.t() | nil
    defp declaration_refusal(%{declaration_draft: %{refusal: refusal}}), do: refusal
    defp declaration_refusal(_assigns), do: nil

    # The ids the strip is actually carrying, which is what a `phx-value-tab`
    # payload is answered against. `Shell.host_tabs/1` is applied first for
    # the same reason it is applied to the strip: a host tab shadowing a
    # package tab, or repeating an id, never became a tab, so it cannot be
    # picked.
    # The neighbour an arrow key names, or `nil` for a key the strip does not
    # answer. Left and Right wrap, which is what WAI-ARIA's own tablist
    # example does and what a six-tab strip wants: the tab furthest from the
    # active one is one press away in the other direction rather than five in
    # this one.
    #
    # `ids` is the strip's order - the package's tabs then the host's, which
    # is how `Shell.drawer_view/1` assembles the strip - so the keys walk what
    # the author sees. An unrecognised current tab is treated as the first,
    # which is `Shell.drawer_tab/2`'s own answer to one.
    @spec drawer_tab_step(term(), Shell.tab_id(), [Shell.tab_id()]) :: Shell.tab_id() | nil
    defp drawer_tab_step(key, from, ids) do
      at = Enum.find_index(ids, &(&1 == from)) || 0
      count = length(ids)

      case key do
        "ArrowRight" -> Enum.at(ids, rem(at + 1, count))
        "ArrowLeft" -> Enum.at(ids, rem(at + count - 1, count))
        "Home" -> List.first(ids)
        "End" -> List.last(ids)
        _unanswered -> nil
      end
    end

    @spec host_tab_ids(map()) :: [Shell.host_tab_id()]
    defp host_tab_ids(assigns) do
      assigns.drawer_tabs |> Shell.host_tabs() |> Enum.map(& &1.id)
    end

    # ------------------------------------------------------------ derived

    # The view model is rebuilt from `{document, palette, findings}` after
    # every state change rather than patched. It is a projection: nothing
    # here memoizes a schema across an edit, because `config_schema/1` is a
    # function of config (ADR-0002 decision 7), not a cache of one.
    @spec rebuild(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
    defp rebuild(socket) do
      %{
        document: document,
        palette: palette,
        findings: findings,
        declared_paths: declared_paths,
        host_roots: host_roots,
        chart_outcomes: chart_outcomes
      } = socket.assigns

      view_model =
        view_model(document, palette, findings, declared_paths, host_roots, chart_outcomes)

      selected = selected_node(socket, view_model)

      socket
      |> assign(:view_model, view_model)
      |> assign(:selected_node, selected)
      |> assign(:selected_slot, Shell.slot_label(view_model.root, socket.assigns.selected_id))
      |> assign(:pending_fields, pending_fields(socket, selected))
      |> notify_select(selected)
      |> refresh_fixture_runs()
    end

    # The runs are not on `drawer()` and not in `drawer_view/1`, deliberately.
    # That function is pure, cheap and called on every render; a compile plus
    # one chart run per fixture row is none of those. So the runs are their
    # own assign, recomputed only when a surface is actually showing them -
    # see `wants_fixture_runs?/1` below - and the inputs actually moved.
    #
    # The key is compared with `==` rather than hashed: a phash2 collision
    # would render a stale verdict with nothing on screen to say so, and a
    # structural comparison is still far cheaper than the work it is
    # guarding.
    @spec refresh_fixture_runs(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
    defp refresh_fixture_runs(socket) do
      assigns = socket.assigns
      # The host's RAW `{id, expr}` list, which is what `Compiler.compile/3`'s
      # `:declare` takes. NOT `host_roots`, which is the derived MapSet of
      # root ids the advisories read - the compiler refuses it.
      declare = Map.get(assigns, :declare, [])
      key = {assigns.document, assigns.palette, assigns.fixtures, declare}

      cond do
        not wants_fixture_runs?(assigns) ->
          socket

        key == assigns.fixture_runs_key ->
          socket

        true ->
          runs =
            FixtureRuns.run(assigns.document, assigns.palette, assigns.fixtures,
              declare: declare,
              view_model: assigns.view_model
            )

          socket
          |> assign(:fixture_runs, runs)
          |> assign(:fixture_runs_key, key)
      end
    end

    # Two surfaces read the runs as of `sb-0l36`, and either one asking is
    # enough: the drawer's Fixtures tab when the drawer is open on it, and the
    # inspector's Fixtures tab when it has a block to be about. With no
    # selection the inspector's tab has no subject and draws its empty state,
    # so a compile plus a run per row would be work nothing shows.
    #
    # The key deliberately does NOT carry the selection. One run covers every
    # block - `FixtureRuns.run/4` drives the whole source - and the inspector
    # picks its own block's rows out of it at render. So changing the selection
    # changes what is on screen without re-running anything, and cannot leave
    # the previous block's verdicts up: they were never this block's rows to
    # begin with.
    @spec wants_fixture_runs?(map()) :: boolean()
    defp wants_fixture_runs?(assigns) do
      (assigns.drawer_open and drawer_view(assigns).tab == :fixtures) or
        (assigns.inspector_tab == :fixtures and assigns.selected_id != nil)
    end

    # The one composition of a view model in this component, called by
    # `rebuild/1` on every state change and by `findings_count/3` on the
    # host's behalf. It is one function rather than two identical pipelines
    # because sb-ukgu is precisely the defect that two of them produce: the
    # host's number and the drawer's number are the same number only while
    # the two pipelines agree, and nothing but sharing them keeps that true.
    #
    # The advisories go in through the same caller-findings seam every other
    # supplied finding uses, so `ViewModel.build/3` needs no notion of a
    # datamodel and the routing is the one already tested. `datamodel` is
    # whatever the host handed over or the already-normalized set the
    # component keeps - `Datamodel.findings/3` normalizes either.
    @spec view_model(Document.t(), Palette.t(), [Finding.t()], term(), term(), term()) ::
            ViewModel.t()
    defp view_model(document, palette, findings, datamodel, declare, chart_outcomes) do
      advisories = Datamodel.findings(document, palette, datamodel, declare)
      disagreements = ViewModel.outcome_findings(document, palette, chart_outcomes)

      ViewModel.build(document, palette, findings ++ advisories ++ disagreements)
    end

    # The fields the author has typed that the document does not hold.
    #
    # Decision 9 commits a config as a unit, which is the invariant that makes
    # a block type with two required fields and no usable defaults impossible
    # to fill one field at a time - fill the first and the gate refuses,
    # because the second is still empty. The draft is what carries the first
    # value forward into the second edit, and this is what says so on screen:
    # without it the author is told twice that a value they typed correctly is
    # wrong, and the revision never moves.
    #
    # Compared against the document rather than against the draft's key set,
    # so a field the author typed and then typed back is not still reported as
    # outstanding.
    @spec pending_fields(Phoenix.LiveView.Socket.t(), ViewModel.Node.t() | nil) ::
            [ViewModel.Field.t()]
    defp pending_fields(_socket, nil), do: []
    defp pending_fields(_socket, %ViewModel.Node{form: nil}), do: []

    defp pending_fields(socket, %ViewModel.Node{block_id: id, form: form}) do
      case Map.fetch(socket.assigns.drafts, id) do
        :error ->
          []

        {:ok, draft} ->
          committed = committed_config(socket.assigns.document, id)

          Enum.filter(form.fields, fn field ->
            path = ViewModel.Field.value_path(field)

            BlockType.fetch_value(draft, path) != BlockType.fetch_value(committed, path)
          end)
      end
    end

    @spec selected_node(Phoenix.LiveView.Socket.t(), ViewModel.t()) :: ViewModel.Node.t() | nil
    defp selected_node(socket, %ViewModel{root: root}) do
      case socket.assigns.selected_id do
        nil -> nil
        id -> root |> find_node(id) |> overlay_draft(socket, id)
      end
    end

    @spec find_node(ViewModel.Node.t(), Block.id()) :: ViewModel.Node.t() | nil
    defp find_node(%ViewModel.Node{block_id: id} = node, id), do: node

    defp find_node(%ViewModel.Node{slots: slots}, id) do
      slots
      |> Enum.flat_map(& &1.children)
      |> Enum.find_value(fn child -> find_node(child, id) end)
    end

    # Decision 9's draft, made visible without letting it near the document.
    # Values come from the draft so the author keeps their keystrokes;
    # findings come from `validate_config/1` on the draft so they are about
    # the value being typed rather than the last one that validated. Only
    # the form is touched - `slots/1` is never called on a draft, which is
    # the promise ADR-0002 decision 6 is owed.
    @spec overlay_draft(ViewModel.Node.t() | nil, Phoenix.LiveView.Socket.t(), Block.id()) ::
            ViewModel.Node.t() | nil
    defp overlay_draft(nil, _socket, _id), do: nil
    defp overlay_draft(%ViewModel.Node{form: nil} = node, _socket, _id), do: node

    defp overlay_draft(%ViewModel.Node{} = node, socket, id) do
      case Map.fetch(socket.assigns.drafts, id) do
        :error -> node
        {:ok, draft} -> apply_draft(node, socket.assigns.palette, draft)
      end
    end

    @spec apply_draft(ViewModel.Node.t(), Palette.t(), Block.config()) :: ViewModel.Node.t()
    defp apply_draft(%ViewModel.Node{} = node, palette, draft) do
      by_key = draft_findings(palette, node, draft)
      keys = MapSet.new(node.form.fields, & &1.key)

      fields =
        Enum.map(node.form.fields, fn field ->
          %{
            field
            | value: Map.get(draft, field.key, field.value),
              findings: Map.get(by_key, field.key, [])
          }
        end)

      unrouted =
        by_key
        |> Enum.reject(fn {key, _findings} -> MapSet.member?(keys, key) end)
        |> Enum.sort()
        |> Enum.flat_map(fn {_key, findings} -> findings end)

      %{node | form: %{node.form | fields: fields, unrouted: unrouted}}
    end

    @spec draft_findings(Palette.t(), ViewModel.Node.t(), Block.config()) ::
            %{optional(String.t()) => [Finding.t()]}
    defp draft_findings(palette, %ViewModel.Node{block_id: id, type: type}, draft) do
      with {:ok, module} <- Palette.fetch(palette, type),
           {:error, findings} <- module.validate_config(draft) do
        Enum.group_by(
          findings,
          fn {key, _message} -> key end,
          fn {key, message} -> Finding.new({:config, id, key}, :config, message) end
        )
      else
        _ok_or_missing -> %{}
      end
    end

    # d8's filter is d5's predicate, asked once per candidate type against a
    # probe block. Not a parallel implementation - the same function, with a
    # block that is not in the document yet, which is exactly the case
    # `droppable_slots_for/3` exists to serve.
    @spec accepted_types(Phoenix.LiveView.Socket.t(), Block.id(), Block.slot_name()) ::
            MapSet.t(Block.type_name())
    defp accepted_types(socket, parent_id, slot) do
      %{document: document, palette: palette} = socket.assigns
      ctx = assignability_context(socket.assigns)

      palette.types
      |> Map.keys()
      |> Enum.filter(fn type ->
        case new_block(palette, type) do
          {:ok, probe} ->
            {parent_id, slot} in Targets.droppable_slots_for(document, palette, probe, ctx)

          :error ->
            false
        end
      end)
      |> MapSet.new()
    end

    # Everything the drag needs, from one enumeration: the accepting slots,
    # and the reason for each slot that refused.
    #
    # The reasons ride *beside* `:droppable` rather than replacing it. The
    # accepting set is what decides `data-drop`, and it is a `MapSet` for
    # the membership test `Slot` runs once per rendered slot; a reason is
    # only ever read for a slot that already lost that test, so folding the
    # two into one map would make the hot path pay for the explanation.
    # Refusals with no data-flow reason (`nil`) are left out of the map
    # entirely - absent and "present, `nil`" would render identically, and
    # one of them is a lie about having asked.
    @spec drag_session(Phoenix.LiveView.Socket.t(), Block.id()) :: map()
    defp drag_session(socket, id) do
      socket
      |> slot_verdicts_for(id)
      |> session(%{block_id: id, type: nil})
    end

    # The insert session (sb-4nep). `block_id` is `nil` and stays a key: it is
    # what `BlockNode` compares a card against to grey the card being dragged,
    # and a session missing the key would raise there rather than simply match
    # no card. Nothing is being dragged out of the document, so no card greys,
    # which is the right answer and not a special case.
    @spec insert_drag_session(Phoenix.LiveView.Socket.t(), Block.type_name()) :: map()
    defp insert_drag_session(socket, type) do
      %{document: document, palette: palette} = socket.assigns

      case new_block(palette, type) do
        {:ok, probe} ->
          document
          |> Targets.slot_verdicts(palette, probe, assignability_context(socket.assigns))
          |> session(%{block_id: nil, type: type})

        :error ->
          session([], %{block_id: nil, type: type})
      end
    end

    @spec session([{{Block.id(), Block.slot_name()}, Targets.slot_verdict()}], map()) :: map()
    defp session(verdicts, carried) do
      droppable =
        for({slot_ref, :ok} <- verdicts, do: slot_ref) |> MapSet.new()

      reasons =
        for {slot_ref, {:refused, reason}} <- verdicts, reason != nil, into: %{} do
          {slot_ref, reason}
        end

      Map.merge(carried, %{droppable: droppable, reasons: reasons})
    end

    @spec slot_verdicts_for(Phoenix.LiveView.Socket.t(), Block.id()) ::
            [{{Block.id(), Block.slot_name()}, Targets.slot_verdict()}]
    defp slot_verdicts_for(socket, id) do
      %{document: document, palette: palette, view_model: view_model} = socket.assigns

      with false <- id == view_model.root.block_id,
           block when not is_nil(block) <- find_document_block(document, id) do
        Targets.slot_verdicts(document, palette, block, assignability_context(socket.assigns))
      else
        _root_or_missing -> []
      end
    end

    @spec find_document_block(Document.t(), Block.id()) :: Block.t() | nil
    defp find_document_block(document, id),
      do: Enum.find(Document.blocks(document), &(&1.id == id))

    @spec fields_for(Phoenix.LiveView.Socket.t(), Block.id()) :: [ViewModel.Field.t()]
    defp fields_for(socket, id) do
      case find_node(socket.assigns.view_model.root, id) do
        %ViewModel.Node{form: %ViewModel.Form{fields: fields}} -> fields
        _none -> []
      end
    end

    @spec effective_config(Phoenix.LiveView.Socket.t(), Block.id()) :: Block.config()
    defp effective_config(socket, id) do
      case Map.fetch(socket.assigns.drafts, id) do
        {:ok, draft} -> draft
        :error -> committed_config(socket.assigns.document, id)
      end
    end

    @spec committed_config(Document.t(), Block.id()) :: Block.config()
    defp committed_config(document, id) do
      case Enum.find(Document.blocks(document), &(&1.id == id)) do
        %Block{config: config} -> config
        nil -> %{}
      end
    end

    @spec notify_change(Phoenix.LiveView.Socket.t(), Document.t()) :: Phoenix.LiveView.Socket.t()
    defp notify_change(socket, document) do
      case socket.assigns.on_change do
        fun when is_function(fun, 1) -> fun.(document)
        _none -> :ok
      end

      socket
    end

    # `notify_change/2`'s sibling for the other subject a host may follow.
    #
    # It hangs off `rebuild/1` rather than off the handlers, because there is
    # more than one way to stop selecting a block - picking another card,
    # deleting the selected one, the host swapping the document out - and a
    # callback wired handler by handler would fire from three of them and be
    # forgotten by the fourth. `rebuild/1` runs after every one of those, and
    # the last id notified is what makes that safe: a rebuild the selection
    # did not move through - a render, an edit to the selected block,
    # re-selecting the block already selected - compares equal and says
    # nothing. A mount compares `nil` against `nil` for the same reason, so an
    # editor nobody has touched calls nothing.
    #
    # The descriptor is built from the node the view model just resolved, so
    # `label` is the line the card actually draws rather than a rule read off
    # the document a second time. A selected id the view model cannot resolve
    # descends to `nil`: the honest answer to "which block" when there is no
    # block is none, and the alternative is a descriptor whose `label` is a
    # guess.
    @spec notify_select(Phoenix.LiveView.Socket.t(), ViewModel.Node.t() | nil) ::
            Phoenix.LiveView.Socket.t()
    defp notify_select(socket, selected) do
      if socket.assigns.selected_id == socket.assigns.notified_id do
        socket
      else
        case socket.assigns.on_select do
          fun when is_function(fun, 1) -> fun.(selection(selected))
          _none -> :ok
        end

        assign(socket, :notified_id, socket.assigns.selected_id)
      end
    end

    @spec selection(ViewModel.Node.t() | nil) ::
            %{id: Block.id(), type: Block.type_name(), label: String.t()} | nil
    defp selection(nil), do: nil

    defp selection(%ViewModel.Node{block_id: id, type: type} = node),
      do: %{id: id, type: type, label: ViewModel.title(node)}

    # A DOM value, so it is a string; `to_index/1` is total because the DOM
    # is not a trusted source. A non-numeric index becomes 0, which
    # `Edit.apply/2` then accepts or refuses on its own terms.
    # The two fits, in the one shape they share: a measured box against the
    # measured scroller, resolved on the ladder. An unmeasured box on either
    # side leaves the zoom where it is - see `Shell.fit_zoom/3`.
    @spec fit_zoom(Phoenix.LiveView.Socket.t(), term()) :: pos_integer()
    defp fit_zoom(socket, box) do
      Shell.fit_zoom(box_width(box), box_width(socket.assigns.viewport), socket.assigns.zoom)
    end

    # The `fit` attr's half of the two fits (sb-ehqn). Arming is refused once
    # anything has been measured, which is what makes the attr an opening
    # state rather than a control a host re-render keeps pressing; `:manual`
    # arms nothing, so a host that names the default changes nothing at all.
    #
    # The refusal has to put `held` back rather than simply doing nothing:
    # `update/3` has already assigned the host's attr over the editor's own
    # value by the time this runs, so a later re-render would otherwise light
    # `Fit width` back up on a canvas the author has since zoomed by hand -
    # the mode saying one thing and the percentage another.
    #
    # A document the host swapped in is the exception, and it is the same rule
    # read properly rather than a hole in it: what the attr opens is a
    # document, so a *different* document is another opening and gets another
    # fit. The measurement the refusal guards on belongs to the document that
    # just left; the one that arrives is as unmeasured as it was at mount, and
    # the mode it opens at is the one the host passed in that same update -
    # `:manual` or an absent attr arming nothing, exactly as at mount.
    @spec arm_fit(Phoenix.LiveView.Socket.t(), Shell.fit_mode(), Shell.fit_mode(), boolean()) ::
            Phoenix.LiveView.Socket.t()
    defp arm_fit(socket, _held, mode, true), do: arm(socket, mode)

    defp arm_fit(socket, held, mode, false) do
      if socket.assigns.measured? do
        assign(socket, :fit, held)
      else
        arm(socket, mode)
      end
    end

    @spec arm(Phoenix.LiveView.Socket.t(), Shell.fit_mode()) :: Phoenix.LiveView.Socket.t()
    defp arm(socket, mode) do
      socket
      |> assign(:fit, mode)
      |> assign(:fit_pending, pending_fit(mode))
    end

    @spec pending_fit(Shell.fit_mode()) :: :width | :active | nil
    defp pending_fit(:manual), do: nil
    defp pending_fit(mode), do: mode

    # The armed fit, spent on the first measurement and cleared whether or not
    # it moved the canvas: an armed fit that survived its own measurement
    # would fire on the next one, which is the re-fit the attr must not do.
    #
    # `:active` resolves against the selection exactly as the button does, and
    # a mount has no selection, so opening at `:active` is today's "Fit active
    # with nothing selected" - the mode, and nothing else. It stamps no
    # reveal: a scroll the author did not ask for is a gesture, not a state.
    @spec open_at_fit(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
    defp open_at_fit(socket) do
      case socket.assigns.fit_pending do
        nil ->
          socket

        mode ->
          socket
          |> assign(:fit_pending, nil)
          |> assign(:zoom, fit_zoom(socket, pending_box(socket, mode)))
      end
    end

    @spec pending_box(Phoenix.LiveView.Socket.t(), :width | :active) :: term()
    defp pending_box(socket, :width), do: Connectors.stage(socket.assigns.measurement)

    defp pending_box(socket, :active) do
      case socket.assigns.selected_id do
        nil -> nil
        id -> Map.get(socket.assigns.measurement, Connectors.card_anchor(id))
      end
    end

    @spec box_width(term()) :: number() | nil
    defp box_width(%{width: width}), do: width
    defp box_width(_other), do: nil

    # `<n>:<block id>`, and the counter is the whole point: pressing `Fit
    # active` twice on the same block has to produce two different values or
    # the second press reveals nothing. The client compares the stamp with the
    # last one it acted on, so an unchanged stamp is a re-render rather than a
    # request and an author who scrolled away stays where they scrolled.
    @spec reveal(String.t() | nil, Block.id()) :: String.t()
    defp reveal(nil, id), do: "1:" <> id

    defp reveal(previous, id) do
      count =
        case Integer.parse(previous) do
          {count, _rest} -> count
          :error -> 0
        end

      "#{count + 1}:#{id}"
    end

    @spec to_index(term()) :: non_neg_integer()
    defp to_index(index) when is_integer(index) and index >= 0, do: index

    defp to_index(index) when is_binary(index) do
      case Integer.parse(index) do
        {int, ""} when int >= 0 -> int
        _other -> 0
      end
    end

    defp to_index(_index), do: 0

    # Strict, where `to_index/1` is forgiving, and the difference matters:
    # `to_index/1` answers 0 for anything it cannot read, and 0 is a real row
    # here. A crafted `phx-value-index` would then remove or move the FIRST
    # declaration rather than none, which is a payload editing a document.
    # An index this cannot read comes back as `:none`, which every
    # `StatifierBlocks.Declarations` function treats as out of range and
    # answers with the list unchanged.
    @spec declaration_index(term()) :: non_neg_integer() | :none
    defp declaration_index(index) when is_integer(index) and index >= 0, do: index

    defp declaration_index(index) when is_binary(index) do
      case Integer.parse(index) do
        {int, ""} when int >= 0 -> int
        _other -> :none
      end
    end

    defp declaration_index(_index), do: :none
  end
end
