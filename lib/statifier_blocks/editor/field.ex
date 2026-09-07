if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.Field do
    @moduledoc """
    One config field, dispatching on the closed field-type set (ADR-0005
    decision 9, ADR-0002 decision 7).

    The set is closed precisely so this renderer can be total, and the
    mapping is the record's rather than this module's:

    | Field type | Rendering |
    |---|---|
    | `:string` | single-line text input; a `<select>` over a host's closed candidate list, or a `<datalist>` over an open one, when it supplied either |
    | `:integer` | number input, step 1 |
    | `:boolean` | checkbox |
    | `{:select, choices}` | select, choices in declared order |
    | `:expression` | statifier-ui's expression editor when that package is present, else a single-line source input; a `<datalist>` over a host's candidate list, either spelling, when it supplied one |
    | `:duration` | one text control; duration strings the expression language reads, with on-screen examples |
    | `{:list, t}` | repeatable rows of `t`'s renderer, with add and remove |
    | `{:path, opts}` | single-line text input bound to a `<datalist>` of a host's candidate list, either spelling, when it supplied one, else of the declared datamodel paths; the plain input when there are neither |
    | `{:type_expr, opts}` | per `opts.arms`: a text input bound to a `<datalist>` of the document's declared type names, or an inline member-list form; a toggle when the field admits both |

    `:duration`'s row is decision 9 as amended 2026-08-29 and again
    2026-09-05 (clause 9a, one grammar). One text control, not a value/unit
    pair and not a pair with an escape hatch beside it: the compound control
    could not spell a compound duration at all, and a control plus an escape
    hatch is two ways to say one thing with a rule about which wins. The
    field reads one grammar, the examples are on screen, and an empty field
    omits the key.

    What the typed text means is `StatifierBlocks.DurationInput`'s, not this
    module's - it is a function of the text alone, so it is asserted with
    LiveView absent. Where an omitted key is omitted is
    `StatifierBlocks.Editor.ConfigForm`'s, which owns where a decoded value
    is written. This module renders the control and shows the refusal.

    The refusal shown beneath a `:duration` is the **inline** check, and it
    is earlier than decision 9's gate rather than a second one: the gate
    still decides what reaches the document, and the inline sentence tells
    the author the text is not a duration while they are still typing it.
    The sentence names what is accepted and nothing else, which is clause
    9d. Nothing here is stored - the stored form is the author's string
    verbatim, byte for byte.

    A required field is marked with the **word**, not with an asterisk
    (parity item 1.9). An asterisk is a convention that has to be learned
    from a legend the editor does not have, it is read aloud as "star", and
    it is one character wide next to a label it is easy to miss. `Required`
    says the same thing to a reader and to a screen reader, and it is the
    field record's own `required?` that decides - never a key name and never
    a type.

    Two control types carry a **placeholder**, and neither is chosen by key
    or by type name: an `:expression` says what kind of thing belongs in it,
    and a `:duration` shows the spelling it stores. A bare `:string` says
    nothing, because there is nothing a type as wide as "string" can suggest -
    which is the rule, and it is what makes the two that do say something the
    editor's own presentation rather than a special case.

    Whether a block type may declare a `placeholder` on its own fields is a
    question this module deliberately does not answer: ADR-0002 decision 7
    closes the field TYPE set, not the keys of a field record, so admitting
    one is a widening of that record and belongs to whoever amends it.

    `:expression` renders through the `expression_component` seam. Predicator
    source is statifier-ui's subject (sui-bob, sui-ADR-0006), and decision 9
    records a richer affordance as a deferral, so this component accepts an
    override for exactly that seam - and, since sb-m6e0, fills the seam
    itself when the package the deferral names is on the load path.

    ## Which control an `:expression` gets

    Three answers, in this order, and the order is the whole rule:

      1. an `expression_component` the host passed - the host asked for its
         own control and gets it, whatever else is available;
      2. `StatifierUI.Live.ExpressionInput`, when `statifier_ui` resolves -
         value picklists over the subset predicator can round-trip, a text
         input over everything else, and the author's own source string
         either way;
      3. the plain source input this package has always rendered, with the
         `<datalist>` of declared paths described below.

    `statifier_ui` is an **optional** dependency, resolved the way
    `phoenix_live_view` is: absent, clause 3 is what an `:expression`
    renders, nothing raises, and nothing warns at compile time. The
    resolution is a runtime `Code.ensure_loaded?/1` against a module read
    from `:statifier_blocks, :expression_component_module`, which is the
    same indirection statifier-ui itself uses for `Predicator.Simple` - it
    is what makes clause 3 assertable on a machine where clause 2 resolves.

    Two properties of clause 2 are load-bearing and neither is this module's
    to weaken. The component **never refuses a source string and never
    rewrites one**: source it cannot draw as rows is drawn as text. And
    every control it draws writes a *complete expression source string* into
    the same named input the text mode edits, so the document still stores
    the author's text and this package still holds no structured expression
    model of its own.

    ## `value_candidates`

    The values a host offers per datamodel path, `%{path => [candidate]}`,
    where a candidate is `%{label: , value: }` or a bare string. It reaches
    the `expression_component` beside `candidates` and is read by whatever
    is behind the seam; nothing in this package interprets it, because only
    a host knows which of its own paths have a value set at all. A path with
    no entry gets a free-text value control, which is the same "suggests,
    never constrains" posture the path `<datalist>` takes.

    ## `path_types`

    The value kind the host's datamodel document declares per path,
    `%{path => kind | {:list, kind} | {:one_of, values}}`, from
    `StatifierBlocks.Datamodel.path_types/1`. It reaches the
    `expression_component` beside `candidates` and `value_candidates`, and
    like both of those, nothing in this package interprets it.

    What is behind the seam reads a declared kind as *which operators the
    row offers and which control it draws* - so a path the document declares
    `integer` offers the numeric operators rather than the ones its current
    source happens to imply. It is not a claim about the author's source: the
    operator the source carries is still offered, the value in it is still
    kept, and a disagreement renders as an advisory beside the clause. `%{}`,
    which is what an editor with no datamodel supplies, is the behaviour
    every `:expression` field had before the map existed.

    ## `candidates`

    The values a host says belong in THIS field, supplied per
    `{type_name, field_key}` through the editor's `field_candidates`
    assign and handed down one field at a time. Two spellings, and the
    difference between them is the whole feature:

      * `[{value, label}]` - a **closed** list. On a `:string` the control
        is a `<select>`, because a host that named the values is saying
        these are the values.
      * `{:open, [{value, label}]}` - an **open** list. The control is the
        text input with a `<datalist>`, on the terms every other
        suggestion list here is on: it suggests, it does not constrain,
        and free text stays valid.

    `[]` is *no list supplied* and renders whatever the field type already
    rendered, so a host that supplies nothing loses nothing.

    Three field types read it, and the *closed* spelling means different
    things to them (sb-uw3a):

    | Field type | Closed list | Open list |
    |---|---|---|
    | `:string` | `<select>` over the offered values | text input bound to a `<datalist>` |
    | `{:path, opts}` | text input bound to a `<datalist>` | the same |
    | `:expression` | text input bound to a `<datalist>` | the same |

    A `:path` and an `:expression` type their value - the first is a path
    into the host's datamodel and the second is source the expression
    language reads - so a host list can only ever suggest on them, and
    drawing a closed one as a `<select>` would make it the authority on a
    value the field's own type already answers for. On both of them the
    host's list is read **ahead of** `path_candidates`, for the same reason
    it is read ahead of the key-chosen lists: a list keyed on this field is
    the narrower claim than the document's declarations. An `:expression`
    served by an `expression_component` is the host's own control and is
    not decorated here; it is handed `path_candidates` as `:candidates`, as
    it always was.

    Three properties, and none of them is this component's choice to make:

      * **It never decides validity.** `validate_config/1` is the
        authority (ADR-0002 decision 7), so a closed list is a control and
        not a rule. A stored value the list does not offer is drawn as its
        own selected option rather than silently rewritten to the first
        one, which is what a `<select>` would otherwise do to a document
        the moment its form was opened.
      * **It never changes what a field holds.** A `{:select, choices}`
        and a `:duration` already know what to draw and ignore it
        entirely, and on the two types that do read it beside `:string` it
        draws a suggestion and nothing else: the value stays typed by the
        control, and `:path`'s undeclared-path advisory (ADR-0005 clause
        11e) is produced from the value exactly as before.
      * **It is host state, not authoring state.** Which values exist is a
        property of the deployment the document runs in, so it arrives as
        an assign and is never stored in a block.

    It is read ahead of the three key-chosen lists below, because a list
    keyed on this field is the narrower claim.

    ## `event_candidates` (sb-82mu)

    The completion events the blocks in a `core.on_event`'s enclosing body
    raise, each `%{label: , value: }`, where the value is the generated
    `done.outcome.<state id>.<outcome>` name and the label is the sibling
    block's own label and that outcome's name. They are drawn as a
    `<datalist>` on the `event` field, on exactly the terms the
    `invoke_type` list is drawn on: the field stays a `:string`, a
    free-typed name is validated as it always was, and an empty list draws
    the plain input rather than an empty picker.

    The list is derived by `StatifierBlocks.Editor` for a selected
    `core.on_event` and is empty for every other selection, so the three
    other core types that declare an `event` key are unaffected. Nothing in
    this module tests for a block type to decide it.

    ## `outcome_candidates` (sb-r4w7)

    The outcomes a host says the chart a `core.subchart` names actually
    finishes with, as plain names. They are drawn as a `<datalist>` on the
    `outcomes` field on exactly the `invoke_type` list's terms: the field
    stays a `:string`, a free-typed name is validated as it always was, and
    an empty list draws the plain input rather than an empty picker.

    The list is looked up by `StatifierBlocks.Editor` from its
    `chart_outcomes` assign for a selected `core.subchart`, and is empty for
    every other selection. Nothing in this module tests for a block type.

    ## The fixture hint (sb-e30x)

    `fixture_hint` is `StatifierBlocks.Shell.fixture_hint/3`'s answer for
    this field, and it is drawn as a sibling element after the control: the
    exemplar the selected block's first fixture row in declaration order
    binds to the path the source names, with every distinct value that path
    takes across the block's rows on the element's `title`. ADR-0005's
    2026-09-05 note records it, and three of its properties are the reason
    it is here rather than anywhere else.

      * **It is a hint, not a `placeholder`.** The rule above - exactly two
        control types carry a placeholder, and neither is chosen by key or
        by type name - is untouched. The hint is a third element with its
        own text, not a third placeholder source.
      * **It is never an option.** Nothing about it reaches a picker, it is
        not merged with `one_of` or with a host's `value_candidates`, and it
        cannot be selected. A fixture value is an *example*, and an example
        promoted into a dropdown becomes a declaration the author never made.
      * **It adds no assign to the rendering package.** The hint is not
        passed through the `expression_component` seam and that component
        gains no key; this package draws it out of the `fixtures` the editor
        already holds. Widening another package's API to draw this package's
        own decoration is what the seam's shape exists to prevent.

    `nil` - a block with no fixture rows, or no fixtures source at all -
    draws no element, so such a block renders exactly as it did before. That
    is silence rather than an empty affordance, which is the same thing the
    empty `<datalist>` cases below do.

    ## The `:expression` path suggestions (sb-0vt)

    That plain input gains a `<datalist>` of the declared datamodel paths
    when `path_candidates` is non-empty, on exactly the `invoke_type` terms
    below: it suggests and does not constrain, free text stays valid, an
    undeclared path stays the `:info` advisory `StatifierBlocks.Datamodel`
    already produced rather than becoming a refusal, and an empty list
    renders the input the package has always rendered. The same list reaches
    the `expression_component` override as `:candidates`, so a host that
    fills the seam is handed the paths rather than re-deriving them.

    **This is the data, not the feature.** Decision 9's deferral of rich
    expression editing to statifier-ui is untouched, and one property of a
    `<datalist>` is why that matters rather than being a formality: the
    browser matches options against the input's **whole value**, so the list
    is live while the author is typing the leading path and goes quiet the
    moment the expression grows an operator. That is genuinely useful for
    the bare-path condition and for the first token of any other, and it is
    not completion. Mid-expression completion needs to know where the caret
    is inside the source, which needs either a hook this package may not add
    (decision 7's two-hook limit) or the richer component decision 9 defers -
    and it needs predicator's operator vocabulary, which px-15q tracks.

    Ordering follows the same reasoning as the clause order below: the
    override wins over the datalist, because a host that supplied a
    component asked for its own control and getting the package's suggestion
    markup stapled beside it would be the package overriding the override.

    This module is a renderer, not a gate. Nothing here decides whether a
    value is acceptable: `validate_config/1` does, through
    `StatifierBlocks.Edit.check_config/3`, which is why an unparseable
    integer reaches the draft config as the string the author typed rather
    than being silently coerced or dropped.

    ## The `{:type_expr, opts}` control

    ADR-0005 decision 9's Note of 2026-09-06. Two arms and a toggle, and
    the arm a field admits is `opts.arms` - a field declaring one arm
    draws that arm and no toggle.

    **The name arm is the `invoke_type` control's shape over a different
    feed.** A single-line text input with a `<datalist>` beside it, free
    text still valid, the plain input when the list is empty. The names are
    the datamodel document's **declarations** - the list
    `StatifierBlocks.Datamodel.declared_types/1` computes and the Datamodel
    tab already draws - arriving here as `type_candidates`. It is a
    different feed from `path_candidates`, and deliberately disjoint: the
    `types` key contributes no path, so the declared paths a
    `{:path, opts}` field suggests and the declared type names this one
    suggests share no member and are never merged. It suggests and never
    constrains.

    **The inline arm draws an ordered member list**, each row carrying the
    member's name, its type and whether the shape promises it. Adding and
    removing a row is the affordance a `{:list, t}`'s rows already have,
    on the same two events. A member's *type* control is this same control
    recursing, so a member may itself hold an inline shape and the form
    nests as a `{:list, t}` of a `{:list, t}` nests. The order the author
    writes is preserved, because that is the order an unmet-member reason
    renders in, and nothing here presents reordering as though it changed
    the value.

    **Switching arms replaces the value; it never translates it.** A name
    and a member list are not two spellings of one value, so there is
    nothing to carry across: the new arm opens empty and the edit reaches
    the document through `:update_config` exactly as every other field
    edit does.

    **A value the control cannot read renders raw** - in the name arm's
    text input, showing the bytes exactly as stored, with the field's own
    `:config` finding beneath it. Raw rather than blank, for decision 9's
    reason that a control showing nothing invites an author to save over a
    value they never saw.

    ## The `{:path, opts}` control

    Decision 7's eighth field type holds a path into the host's datamodel,
    and it reaches its control by **type**, which is the whole reason the
    type exists beside the `datamodel_path?: true` key: a host that never
    learned the key wrote `type: :string` and got neither a candidate list
    nor an advisory, and nothing in its declaration said anything was
    missing.

    The control is the same `<datalist>` of `path_candidates` the
    `:expression` input carries, on the same terms - it suggests and does
    not constrain, free text stays valid, and an empty list renders the
    plain text input a `:string` rendered, which is what "no datamodel
    supplied" looks like on screen. It is not a `{:select, choices}`,
    because the declared paths are what a host happens to have declared and
    not the set of values a field may hold: `validate_config/1` is still
    the only authority on that, and an undeclared path is still ADR-0005
    clause 11e's `:info` advisory anchored on this field's `key`, never a
    refusal.

    A host that named this field's values in `candidates` gets those in the
    datalist instead of the declared paths, on identical terms and for the
    reason the `## candidates` section above gives; the advisory is
    produced from the stored value either way.

    `opts` is read by nothing here, and its two keys are why that is worth
    saying rather than obvious. `expects` and `writes` (ADR-0011 decision
    2) are claims about the document's data flow at the path, read by
    `StatifierBlocks.Environment` and reported by
    `StatifierBlocks.Assignability` as a finding on this field's own key.
    They are not claims about the bytes this control edits, so the control
    is the same one either way and an author sees the difference in the
    findings beneath it. A `{:path, opts}` inside a `{:list, t}` renders as
    the row fallback text input, since a list row draws no suggestion
    markup for any type.

    ## The `invoke_type` suggestion list

    `invoke_types` is the one control this module chooses **by key**, and
    the exception is deliberate rather than an oversight of the rule above.
    A host that knows which invoke types it has registered can pass them as
    an editor assign, and an `invoke_type` field then renders as a text
    input bound to a `<datalist>` of those strings. With the assign absent
    or empty the same field renders as the plain text input it has always
    been, so the suggestion list is additive and a host that supplies
    nothing loses nothing.

    Three properties make this a suggestion rather than a vocabulary, and
    each of them is ADR-0004 decision 8 rather than a choice made here:

      * **Free text stays valid.** A `<datalist>` suggests; it does not
        constrain, which is exactly why it is the control used and a
        `{:select, choices}` is not. An author can type a type that is not
        on the list and the editor stores it verbatim.
      * **An unknown type stays a lint.** The two-registry check is the
        compiler's opt-in `:known_invoke_types` lint, and it reports; it
        never refuses. Nothing here changes what compiles.
      * **The handler set is deployment state, not authoring state.** Which
        types a host can actually run is a property of the deployment the
        document is run in, not of the document, so it arrives as an assign
        the host fills in and never as anything stored in the block.

    The assign shares its name with the compiler's `invoke_types` surface -
    `StatifierBlocks.Compiled`'s field and the compiler's
    `:known_invoke_types` option - and the two are separate surfaces that
    happen to describe the same vocabulary from opposite ends. The
    compiler's is *derived from a document*: the sorted set of types that
    document actually emits. This one is *supplied by a host*: the types it
    is prepared to answer. Neither reads the other.

    Keying a control on a field's key is a narrower thing than the
    `placeholder` question above, which is why it does not reopen it: a
    block type declaring an `invoke_type` field of some other type keeps
    that type's control, because this clause is reached only after every
    typed clause has had its turn.
    """

    use Phoenix.Component

    alias StatifierBlocks.{DurationInput, ViewModel}

    attr(:field, ViewModel.Field, required: true)
    attr(:target, :any, required: true)
    attr(:class, :string, default: nil)

    attr(:block_id, :string,
      default: nil,
      doc: """
      The id of the block this field belongs to, sent as `block-id` on the
      list gestures (`field-list-add`, `field-list-remove`) the way
      `config-change` and `discard-draft` already carry it. `nil` sends no
      attribute at all, so a caller that supplies none renders exactly what
      it rendered before.
      """
    )

    attr(:expression_component, :any,
      default: nil,
      doc:
        "Override for `:expression`, per ADR-0005 decision 9's seam. Receives the same assigns."
    )

    attr(:invoke_types, :list,
      default: [],
      doc: """
      The invoke types the host is prepared to answer. Suggestions for an
      `invoke_type` field, never a constraint on it; empty is *no list
      supplied* and renders the plain input.
      """
    )

    attr(:path_candidates, :list,
      default: [],
      doc: """
      The declared datamodel paths, from `StatifierBlocks.Datamodel.candidates/3`.
      Suggestions on an `:expression` field and on a `{:path, opts}` one, and
      passed to `expression_component` as `:candidates`; empty renders the
      plain input.
      """
    )

    attr(:value_candidates, :map,
      default: %{},
      doc: """
      The values a host offers per datamodel path, `%{path => [candidate]}`.
      Passed to `expression_component` as `:value_candidates` and read only
      there; `%{}` offers none and a path with no entry gets free text.
      """
    )

    attr(:type_candidates, :list,
      default: [],
      doc: """
      The document's declared type **names**, sorted, drawn as the
      `<datalist>` of a `{:type_expr, opts}` field's name arm and of every
      member type control inside its inline arm. `[]` renders the plain
      input, on the same "an empty list is markup that suggests nothing"
      terms every other feed here is under.
      """
    )

    attr(:path_types, :map,
      default: %{},
      doc: """
      The kinds the host's datamodel declares per path, from
      `StatifierBlocks.Datamodel.path_types/1`. Passed to
      `expression_component` as `:path_types` and read only there; `%{}`
      declares none and a path with no entry renders as it always did.
      """
    )

    attr(:event_candidates, :list,
      default: [],
      doc: """
      The completion events the enclosing body's blocks raise, each
      `%{label: , value: }`. Suggestions for a `core.on_event` `event` field,
      never a constraint on it; empty is *no list supplied* and renders the
      plain input.
      """
    )

    attr(:outcome_candidates, :list,
      default: [],
      doc: """
      The outcomes the host says the referenced chart finishes with, as plain
      names. Suggestions for a `core.subchart` `outcomes` field, never a
      constraint on it; empty is *no list supplied* and renders the plain
      input.
      """
    )

    attr(:candidates, :any,
      default: [],
      doc: """
      The values a host offers for this field, `[{value, label}]` for a
      closed list or `{:open, [{value, label}]}` for an open one. `[]` is
      *no list supplied* and renders the control the field type already
      rendered. Read by `:string`, `{:path, opts}` and `:expression`; on
      the last two, both spellings draw a `<datalist>` and the value stays
      typed by the control.
      """
    )

    attr(:fixture_hint, :any,
      default: nil,
      doc: """
      `StatifierBlocks.Shell.fixture_hint/3`'s answer for this field, or
      `nil`. Drawn as an element beside the control, never passed through the
      `expression_component` seam and never an option.
      """
    )

    attr(:debounce, :any,
      default: nil,
      doc: """
      What `phx-debounce` this field's controls carry, or `nil` for none.
      Written verbatim onto every form control this component renders, so
      the accepted values are LiveView's own: milliseconds as an integer
      or a string, or `:blur` for "post when the control loses focus".

      `nil` renders no attribute at all - byte for byte what this
      component rendered before the attr existed, and the behaviour
      LiveView gives a control with no `phx-debounce`, which is to post
      every change event as it happens. There is deliberately no non-`nil`
      default: a package that debounced on its own would change the event
      stream of every host already mounted on it, and how often a document
      is written is the host's decision rather than this component's.

      Every control is every control: the hidden inputs that pair a
      checkbox and stand in for an empty list carry it too. The attribute
      is inert on an input that fires no input event, and the rule a
      reader can check against the markup - no control in this form is
      missing it - is worth more than trimming an attribute that does
      nothing.

      A host's own `expression_component` override is not handed this
      value. It renders its own markup from the assigns ADR-0005 decision
      9's seam names, and how that markup rate-limits is the override's
      decision, not this component's.
      """
    )

    @doc """
    One field: its label, its control, and its own findings (decision 11).

    Two flags on the declaration change what is drawn (ADR-0002 decision 7,
    amended 2026-09-07). A `hidden?: true` field renders **nothing at all** -
    no row, no label, no control. A `readonly?: true` field renders its row
    and its label, with its **value** where a control would sit; it is not a
    disabled input and carries no form control, so it posts nothing. Both
    flags leave the field's findings visible where a row is drawn at all.
    `hidden?` wins when both are set, because a field that is not rendered
    has nothing to render as a value.
    """
    def field(%{field: %ViewModel.Field{hidden?: true}} = assigns) do
      ~H"""
      """
    end

    def field(%{field: %ViewModel.Field{readonly?: true}} = assigns) do
      ~H"""
      <div
        class={["sb-field", "sb-field--readonly", @class]}
        data-field={@field.key}
        data-field-type={type_tag(@field.type)}
        data-field-readonly="true"
      >
        <span class="sb-field__label">
          <span class="sb-field__label-text">{@field.label}</span>
          <span :if={@field.required?} class="sb-field__required">Required</span>
        </span>
        <p class="sb-field__value">{to_text(@field.value)}</p>
        <p :for={finding <- @field.findings} class={["sb-finding", severity_class(finding)]}>
          {finding.message}
        </p>
      </div>
      """
    end

    def field(assigns) do
      ~H"""
      <div class={["sb-field", @class]} data-field={@field.key} data-field-type={type_tag(@field.type)}>
        <label class="sb-field__label" for={input_id(@field)}>
          <span class="sb-field__label-text">{@field.label}</span>
          <span :if={@field.required?} class="sb-field__required">Required</span>
        </label>
        <.control
          field={@field}
          target={@target}
          block_id={@block_id}
          expression_component={resolve_expression_component(@expression_component)}
          invoke_types={@invoke_types}
          path_candidates={@path_candidates}
          value_candidates={@value_candidates}
          path_types={@path_types}
          type_candidates={@type_candidates}
          event_candidates={@event_candidates}
          outcome_candidates={@outcome_candidates}
          candidates={@candidates}
          debounce={@debounce}
        />
        <p
          :if={@fixture_hint}
          class="sb-field__fixture-hint"
          data-fixture-hint={@fixture_hint.path}
          title={hint_title(@fixture_hint)}
        >
          From fixtures, {@fixture_hint.path} is {@fixture_hint.value}
        </p>
        <p :for={finding <- @field.findings} class={["sb-finding", severity_class(finding)]}>
          {finding.message}
        </p>
      </div>
      """
    end

    attr(:field, ViewModel.Field, required: true)
    attr(:target, :any, required: true)
    attr(:block_id, :string, default: nil)
    attr(:expression_component, :any, default: nil)
    attr(:invoke_types, :list, default: [])
    attr(:path_candidates, :list, default: [])
    attr(:value_candidates, :map, default: %{})
    attr(:path_types, :map, default: %{})
    attr(:type_candidates, :list, default: [])
    attr(:event_candidates, :list, default: [])
    attr(:outcome_candidates, :list, default: [])
    attr(:candidates, :any, default: [])
    attr(:debounce, :any, default: nil)

    # A host's candidate list for THIS field, ahead of every clause that
    # chooses a control by key: a list keyed on `{type_name, key}` is the
    # narrower claim, and a host that named this field's values asked for
    # them rather than for the package's own suggestion list.
    #
    # A closed list is a `<select>` and an `{:open, list}` is a text input
    # with a `<datalist>`, which is the whole difference between the two:
    # the first says these are the values, the second says these are values.
    # Neither decides anything - `validate_config/1` is still the only
    # authority on what the field may hold, and a stored value that is not
    # on a closed list is rendered as its own selected option rather than
    # being silently rewritten to the first one on the next change event.
    defp control(
           %{field: %ViewModel.Field{type: :string}, candidates: {:open, [_ | _]}} = assigns
         ) do
      assigns =
        assigns
        |> assign(:list_id, input_id(assigns.field) <> "-candidates")
        |> assign(:offered, elem(assigns.candidates, 1))

      ~H"""
      <input
        class="sb-field__input"
        type="text"
        id={input_id(@field)}
        name={input_name(@field)}
        value={to_text(@field.value)}
        list={@list_id}
        spellcheck="false"
        autocomplete="off"
        phx-debounce={@debounce}
      />
      <datalist id={@list_id} data-field-candidates={length(@offered)}>
        <option :for={{value, label} <- @offered} value={value} label={label}></option>
      </datalist>
      """
    end

    defp control(%{field: %ViewModel.Field{type: :string}, candidates: [_ | _]} = assigns) do
      assigns =
        assigns
        |> assign(:offered, assigns.candidates)
        |> assign(:unoffered, unoffered_value(assigns.field, assigns.candidates))

      ~H"""
      <select
        class="sb-field__input"
        id={input_id(@field)}
        name={input_name(@field)}
        data-field-candidates={length(@offered)}
        phx-debounce={@debounce}
      >
        <option :if={@unoffered != nil} value={@unoffered} selected>{@unoffered}</option>
        <option :for={{value, label} <- @offered} value={value} selected={@field.value == value}>
          {label}
        </option>
      </select>
      """
    end

    # The same host list on a `:path` or an `:expression`, where it can only
    # ever SUGGEST (sb-uw3a). Both controls type their value - a path is
    # still a path and an expression still an expression, and ADR-0011
    # decision 9's surfaces are untouched by anything here - so a CLOSED
    # list draws a `<datalist>` on these two types rather than the
    # `<select>` a `:string` draws. Swapping the control would make the
    # host's list the authority on a value the field's own type already
    # answers for, and neither type has a value set a host could enumerate:
    # a path is one of the document's declarations and an expression is
    # source.
    #
    # It is read ahead of `path_candidates` for the reason it is read ahead
    # of the key-chosen lists below: a list keyed on THIS field is the
    # narrower claim than the document's declared paths, so a host that
    # named this field's values gets them instead of the package's own
    # suggestion list rather than beside it.
    defp control(
           %{
             field: %ViewModel.Field{type: :expression},
             expression_component: nil,
             candidates: {:open, [_ | _] = offered}
           } = assigns
         ) do
      suggestion_control(assigns, offered, expression_input_class(), "an expression")
    end

    defp control(
           %{
             field: %ViewModel.Field{type: :expression},
             expression_component: nil,
             candidates: [_ | _] = offered
           } = assigns
         ) do
      suggestion_control(assigns, offered, expression_input_class(), "an expression")
    end

    defp control(
           %{
             field: %ViewModel.Field{type: {:path, _opts}},
             candidates: {:open, [_ | _] = offered}
           } = assigns
         ) do
      suggestion_control(assigns, offered, "sb-field__input", nil)
    end

    defp control(
           %{field: %ViewModel.Field{type: {:path, _opts}}, candidates: [_ | _] = offered} =
             assigns
         ) do
      suggestion_control(assigns, offered, "sb-field__input", nil)
    end

    defp control(%{field: %ViewModel.Field{type: :boolean}} = assigns) do
      ~H"""
      <div class="sb-field__row">
        <input type="hidden" name={input_name(@field)} value="false" phx-debounce={@debounce} />
        <input
          class="sb-field__input"
          type="checkbox"
          id={input_id(@field)}
          name={input_name(@field)}
          value="true"
          checked={@field.value == true}
          phx-debounce={@debounce}
        />
      </div>
      """
    end

    defp control(%{field: %ViewModel.Field{type: :integer}} = assigns) do
      ~H"""
      <input
        class="sb-field__input"
        type="number"
        step="1"
        id={input_id(@field)}
        name={input_name(@field)}
        value={to_text(@field.value)}
        phx-debounce={@debounce}
      />
      """
    end

    defp control(%{field: %ViewModel.Field{type: {:select, choices}}} = assigns) do
      assigns = assign(assigns, :choices, choices)

      ~H"""
      <select
        class="sb-field__input"
        id={input_id(@field)}
        name={input_name(@field)}
        phx-debounce={@debounce}
      >
        <option :for={{value, label} <- @choices} value={value} selected={@field.value == value}>
          {label}
        </option>
      </select>
      """
    end

    defp control(
           %{
             field: %ViewModel.Field{type: :expression},
             expression_component: nil,
             path_candidates: [_first | _rest]
           } = assigns
         ) do
      assigns = assign(assigns, :list_id, input_id(assigns.field) <> "-paths")

      ~H"""
      <input
        class="sb-field__input sb-field__input--expression"
        type="text"
        id={input_id(@field)}
        name={input_name(@field)}
        value={to_text(@field.value)}
        list={@list_id}
        placeholder="an expression"
        spellcheck="false"
        autocomplete="off"
        phx-debounce={@debounce}
      />
      <datalist id={@list_id} data-path-candidates={length(@path_candidates)}>
        <option :for={path <- @path_candidates} value={path}></option>
      </datalist>
      """
    end

    defp control(
           %{field: %ViewModel.Field{type: :expression}, expression_component: nil} = assigns
         ) do
      ~H"""
      <input
        class="sb-field__input sb-field__input--expression"
        type="text"
        id={input_id(@field)}
        name={input_name(@field)}
        value={to_text(@field.value)}
        placeholder="an expression"
        spellcheck="false"
        phx-debounce={@debounce}
      />
      """
    end

    defp control(%{field: %ViewModel.Field{type: :expression}} = assigns) do
      # A function component is a one-argument function returning a rendered
      # struct, so the seam is a call rather than a registry: a host passes
      # `&MyApp.expression_input/1` and gets the same assigns this module
      # would have used. HEEx has no dynamic-component tag, and inventing a
      # module-and-behaviour indirection for one override would be more
      # machinery than the deferral is worth.
      #
      # `candidates` is additive to that map (sb-0vt), and
      # `value_candidates` (sb-m6e0) and `path_types` (sb-23e0) are additive
      # in exactly the same way. An
      # override written before either existed takes a map and ignores a key
      # it does not read, so nothing that worked stops working; an override
      # written after can offer the declared paths, and the host's own value
      # sets for them, without re-deriving either from assigns this component
      # is not handed.
      ~H"""
      {@expression_component.(%{
        field: @field,
        id: input_id(@field),
        name: input_name(@field),
        value: to_text(@field.value),
        candidates: @path_candidates,
        value_candidates: @value_candidates,
        path_types: @path_types
      })}
      """
    end

    defp control(
           %{
             field: %ViewModel.Field{type: {:path, _opts}},
             path_candidates: [_first | _rest]
           } = assigns
         ) do
      assigns = assign(assigns, :list_id, input_id(assigns.field) <> "-paths")

      ~H"""
      <input
        class="sb-field__input"
        type="text"
        id={input_id(@field)}
        name={input_name(@field)}
        value={to_text(@field.value)}
        list={@list_id}
        spellcheck="false"
        autocomplete="off"
        phx-debounce={@debounce}
      />
      <datalist id={@list_id} data-path-candidates={length(@path_candidates)}>
        <option :for={path <- @path_candidates} value={path}></option>
      </datalist>
      """
    end

    # No datamodel supplied is no candidates, and no candidates is the plain
    # text input a `:string` was - the same "empty list is no list" rule the
    # `:expression` datalist and the `invoke_type` one are under.
    defp control(%{field: %ViewModel.Field{type: {:path, _opts}}} = assigns) do
      ~H"""
      <input
        class="sb-field__input"
        type="text"
        id={input_id(@field)}
        name={input_name(@field)}
        value={to_text(@field.value)}
        phx-debounce={@debounce}
      />
      """
    end

    # ADR-0005 decision 9's Note of 2026-09-06. The field's own control is
    # the recursive one below, opened on the arm the stored value already
    # is, with the field's key and an empty index path so that the add and
    # remove gestures inside it name this field's member list.
    defp control(%{field: %ViewModel.Field{type: {:type_expr, opts}}} = assigns) do
      assigns =
        assigns
        |> assign(:arms, type_expr_arms(opts))
        |> assign(:value, assigns.field.value)
        |> assign(:key, assigns.field.key)
        |> assign(:prefix, input_name(assigns.field))
        |> assign(:base_id, input_id(assigns.field))

      ~H"""
      <.type_expr_value
        value={@value}
        arms={@arms}
        key={@key}
        prefix={@prefix}
        base_id={@base_id}
        path={[]}
        target={@target}
        block_id={@block_id}
        type_candidates={@type_candidates}
        debounce={@debounce}
      />
      """
    end

    defp control(%{field: %ViewModel.Field{type: :duration}} = assigns) do
      assigns =
        assigns
        |> assign(:reading, DurationInput.read(assigns.field.value))
        |> assign(:examples_id, input_id(assigns.field) <> "-examples")

      ~H"""
      <input
        class="sb-field__input sb-field__input--duration"
        type="text"
        id={input_id(@field)}
        name={input_name(@field)}
        value={to_text(@field.value)}
        placeholder={DurationInput.placeholder()}
        spellcheck="false"
        aria-describedby={@examples_id}
        phx-debounce={@debounce}
      />
      <p class="sb-field__examples" id={@examples_id}>
        Try {Enum.join(DurationInput.examples(), ", ")}.
      </p>
      <p :if={@reading.form == :invalid} class="sb-field__refusal" data-duration-refusal>
        {@reading.message}
      </p>
      """
    end

    defp control(%{field: %ViewModel.Field{type: {:list, inner}}} = assigns) do
      assigns =
        assigns
        |> assign(:inner, inner)
        |> assign(:rows, List.wrap(assigns.field.value))

      ~H"""
      <div class="sb-field__list">
        <div :for={{value, index} <- Enum.with_index(@rows)} class="sb-field__row" data-row={index}>
          <.row_control
            inner={@inner}
            value={value}
            id={input_id(@field) <> "-#{index}"}
            name={input_name(@field) <> "[]"}
            debounce={@debounce}
          />
          <button
            type="button"
            class="sb-button sb-field__remove"
            phx-click="field-list-remove"
            phx-target={@target}
            phx-value-key={@field.key}
            phx-value-index={index}
            phx-value-block-id={@block_id}
          >
            remove
          </button>
        </div>
        <input
          :if={@rows == []}
          type="hidden"
          name={input_name(@field) <> "[]"}
          value=""
          phx-debounce={@debounce}
        />
        <button
          type="button"
          class="sb-button sb-field__add"
          phx-click="field-list-add"
          phx-target={@target}
          phx-value-key={@field.key}
          phx-value-block-id={@block_id}
        >
          add
        </button>
      </div>
      """
    end

    # Reached only after every typed clause, so a block type that declares
    # `invoke_type` as something other than a string keeps that type's own
    # control. The empty list falls through to the plain input below, which
    # is what makes "no list supplied" and "a list that happens to be empty"
    # the same thing on screen - a `<datalist>` with no options suggests
    # nothing and would only add an element for a reader to trip over.
    defp control(
           %{field: %ViewModel.Field{key: "invoke_type"}, invoke_types: [_first | _rest]} =
             assigns
         ) do
      assigns = assign(assigns, :list_id, input_id(assigns.field) <> "-types")

      ~H"""
      <input
        class="sb-field__input"
        type="text"
        id={input_id(@field)}
        name={input_name(@field)}
        value={to_text(@field.value)}
        list={@list_id}
        spellcheck="false"
        autocomplete="off"
        phx-debounce={@debounce}
      />
      <datalist id={@list_id} data-invoke-types={length(@invoke_types)}>
        <option :for={type <- @invoke_types} value={type}></option>
      </datalist>
      """
    end

    # sb-82mu: a `core.on_event` `event` field, offered the completion events
    # its enclosing body's blocks raise. Keyed by field key and by a non-empty
    # list, exactly as `invoke_type` above is, and for the same two reasons:
    # the field stays a plain `:string` in `config_schema/1`, and an empty
    # list falls through to the plain input below rather than drawing a
    # `<datalist>` that suggests nothing.
    #
    # Three other core types declare an `event` key - `core.send`,
    # `core.raise` and `core.await` - and they name events this list is not
    # about. Nothing here tests for that: the list is derived for a selected
    # `core.on_event` and is empty for every other selection, which is where
    # the question belongs. A caller of this component that hands an `event`
    # field a list anyway gets that list, on the same "suggests, never
    # constrains" terms.
    defp control(
           %{field: %ViewModel.Field{key: "event"}, event_candidates: [_first | _rest]} = assigns
         ) do
      assigns = assign(assigns, :list_id, input_id(assigns.field) <> "-events")

      ~H"""
      <input
        class="sb-field__input"
        type="text"
        id={input_id(@field)}
        name={input_name(@field)}
        value={to_text(@field.value)}
        list={@list_id}
        spellcheck="false"
        autocomplete="off"
        phx-debounce={@debounce}
      />
      <datalist id={@list_id} data-event-candidates={length(@event_candidates)}>
        <option
          :for={candidate <- @event_candidates}
          value={candidate.value}
          label={candidate.label}
        >
        </option>
      </datalist>
      """
    end

    # sb-r4w7: a `core.subchart` `outcomes` field, offered the finals the host
    # says the referenced chart emits. Keyed by field key and by a non-empty
    # list, exactly as `invoke_type` and `event` above are, and for the same
    # reasons: the field stays a plain `:string` in `config_schema/1`, and an
    # empty list falls through to the plain input rather than drawing a
    # `<datalist>` that suggests nothing.
    #
    # No block type is tested here. `core.subchart` is the only core type
    # declaring an `outcomes` key, and the list is looked up for a selected
    # one and empty otherwise, which is where the question belongs.
    defp control(
           %{field: %ViewModel.Field{key: "outcomes"}, outcome_candidates: [_first | _rest]} =
             assigns
         ) do
      assigns = assign(assigns, :list_id, input_id(assigns.field) <> "-finals")

      ~H"""
      <input
        class="sb-field__input"
        type="text"
        id={input_id(@field)}
        name={input_name(@field)}
        value={to_text(@field.value)}
        list={@list_id}
        spellcheck="false"
        autocomplete="off"
        phx-debounce={@debounce}
      />
      <datalist id={@list_id} data-outcome-candidates={length(@outcome_candidates)}>
        <option :for={outcome <- @outcome_candidates} value={outcome}></option>
      </datalist>
      """
    end

    defp control(%{field: %ViewModel.Field{}} = assigns) do
      ~H"""
      <input
        class="sb-field__input"
        type="text"
        id={input_id(@field)}
        name={input_name(@field)}
        value={to_text(@field.value)}
        phx-debounce={@debounce}
      />
      """
    end

    attr(:inner, :any, required: true)
    attr(:value, :any, required: true)
    attr(:id, :string, required: true)
    attr(:name, :string, required: true)
    attr(:debounce, :any, default: nil)

    defp row_control(%{inner: :boolean} = assigns) do
      ~H"""
      <select class="sb-field__input" id={@id} name={@name} phx-debounce={@debounce}>
        <option value="true" selected={@value == true}>true</option>
        <option value="false" selected={@value != true}>false</option>
      </select>
      """
    end

    defp row_control(%{inner: {:select, _choices}} = assigns) do
      assigns = assign(assigns, :choices, elem(assigns.inner, 1))

      ~H"""
      <select class="sb-field__input" id={@id} name={@name} phx-debounce={@debounce}>
        <option :for={{value, label} <- @choices} value={value} selected={@value == value}>
          {label}
        </option>
      </select>
      """
    end

    defp row_control(%{inner: :integer} = assigns) do
      ~H"""
      <input
        class="sb-field__input"
        type="number"
        step="1"
        id={@id}
        name={@name}
        value={to_text(@value)}
        phx-debounce={@debounce}
      />
      """
    end

    defp row_control(assigns) do
      ~H"""
      <input
        class="sb-field__input"
        type="text"
        id={@id}
        name={@name}
        value={to_text(@value)}
        phx-debounce={@debounce}
      />
      """
    end

    @doc """
    Decodes one field's slice of a form's params back into a config value,
    dispatching on the same closed type set the renderer does.

    Total, and deliberately non-coercing at the edges: an integer field
    whose input does not parse yields the string the author typed, so
    `validate_config/1` reports it and decision 9's gate keeps it out of
    the document. Coercing to zero here would silently discard the author's
    intent and commit a value they never asked for.
    """
    @spec decode(StatifierBlocks.BlockType.field_type(), term()) :: StatifierBlocks.Block.json()
    def decode(:integer, raw) when is_binary(raw) do
      case Integer.parse(String.trim(raw)) do
        {int, ""} -> int
        _other -> raw
      end
    end

    def decode(:boolean, raw), do: raw in [true, "true", "on", "1"]

    def decode({:list, inner}, raw) when is_list(raw), do: Enum.map(raw, &decode(inner, &1))
    def decode({:list, inner}, raw), do: [decode(inner, raw)]
    def decode({:type_expr, _opts}, raw), do: decode_type_expr(raw)
    def decode(_type, raw) when is_binary(raw), do: raw
    def decode(_type, raw), do: raw

    # -- the type expression ---------------------------------------------------

    attr(:value, :any, required: true)
    attr(:arms, :list, required: true)
    attr(:key, :string, required: true)
    attr(:prefix, :string, required: true)
    attr(:base_id, :string, required: true)
    attr(:path, :list, required: true)
    attr(:target, :any, required: true)
    attr(:block_id, :string, default: nil)
    attr(:type_candidates, :list, required: true)
    attr(:debounce, :any, default: nil)

    # One type expression: the toggle when the value admits both arms, then
    # the arm itself. A member's type control is this same component with a
    # deeper `prefix` and one more index on `path`, which is what makes the
    # form nest.
    defp type_expr_value(assigns) do
      assigns =
        assigns
        |> assign(:arm, type_expr_arm(assigns.value, assigns.arms))
        |> assign(:members, type_expr_members(assigns.value))
        |> assign(:list_id, assigns.base_id <> "-types")

      ~H"""
      <div class="sb-type-expr" data-arm={@arm} data-type-expr-path={type_expr_path_param(@path)}>
        <div :if={length(@arms) > 1} class="sb-type-expr__toggle">
          <label class="sb-type-expr__arm">
            <input
              type="radio"
              name={@prefix <> "[__arm]"}
              value="name"
              checked={@arm == :name}
              id={@base_id <> "-arm-name"}
              phx-debounce={@debounce}
            /> a declared type
          </label>
          <label class="sb-type-expr__arm">
            <input
              type="radio"
              name={@prefix <> "[__arm]"}
              value="inline"
              checked={@arm == :inline}
              id={@base_id <> "-arm-inline"}
              phx-debounce={@debounce}
            /> members
          </label>
        </div>
        <input
          :if={length(@arms) == 1}
          type="hidden"
          name={@prefix <> "[__arm]"}
          value={Atom.to_string(@arm)}
          phx-debounce={@debounce}
        />
        <div :if={@arm == :name} class="sb-type-expr__name">
          <input
            class="sb-field__input"
            type="text"
            id={@base_id}
            name={@prefix <> "[name]"}
            value={type_expr_name_text(@value)}
            list={@list_id}
            spellcheck="false"
            autocomplete="off"
            phx-debounce={@debounce}
          />
          <datalist
            :if={@type_candidates != []}
            id={@list_id}
            data-type-candidates={length(@type_candidates)}
          >
            <option :for={name <- @type_candidates} value={name}></option>
          </datalist>
        </div>
        <div :if={@arm == :inline} class="sb-type-expr__members">
          <div
            :for={{member, index} <- Enum.with_index(@members)}
            class="sb-type-expr__member"
            data-member={index}
          >
            <input
              class="sb-field__input sb-type-expr__member-name"
              type="text"
              id={@base_id <> "-#{index}-name"}
              name={@prefix <> "[members][#{index}][name]"}
              value={member_name(member)}
              spellcheck="false"
              phx-debounce={@debounce}
            />
            <input
              type="hidden"
              name={@prefix <> "[members][#{index}][required?]"}
              value="false"
              phx-debounce={@debounce}
            />
            <label class="sb-type-expr__required">
              <input
                type="checkbox"
                id={@base_id <> "-#{index}-required"}
                name={@prefix <> "[members][#{index}][required?]"}
                value="true"
                checked={member_required?(member)}
                phx-debounce={@debounce}
              /> required
            </label>
            <.type_expr_value
              value={member_type(member)}
              arms={[:name, :inline]}
              key={@key}
              prefix={@prefix <> "[members][#{index}][type]"}
              base_id={@base_id <> "-#{index}-type"}
              path={@path ++ [index]}
              target={@target}
              block_id={@block_id}
              type_candidates={@type_candidates}
              debounce={@debounce}
            />
            <button
              type="button"
              class="sb-button sb-field__remove"
              phx-click="field-list-remove"
              phx-target={@target}
              phx-value-key={@key}
              phx-value-index={index}
              phx-value-path={type_expr_path_param(@path)}
              phx-value-block-id={@block_id}
            >
              remove
            </button>
          </div>
          <button
            type="button"
            class="sb-button sb-field__add"
            phx-click="field-list-add"
            phx-target={@target}
            phx-value-key={@key}
            phx-value-path={type_expr_path_param(@path)}
            phx-value-block-id={@block_id}
          >
            add
          </button>
        </div>
      </div>
      """
    end

    # Which arms the declaration admits. Both by default, and a declaration
    # naming an empty list is read as naming neither, which is a declaration
    # no control can draw - so it reads as both rather than as nothing.
    @spec type_expr_arms(map()) :: [:name | :inline]
    defp type_expr_arms(opts) do
      case Map.get(opts, :arms) do
        [_first | _rest] = arms -> Enum.filter([:name, :inline], &(&1 in arms))
        _absent_or_empty -> [:name, :inline]
      end
      |> case do
        [] -> [:name, :inline]
        arms -> arms
      end
    end

    # The arm a stored value opens on: the one it already is. A member list
    # opens the inline arm; everything else opens the name arm, which is
    # where a value the control cannot read renders raw. A field admitting
    # only the inline arm opens it for an empty value, because there is no
    # name arm to open.
    @spec type_expr_arm(term(), [:name | :inline]) :: :name | :inline
    defp type_expr_arm(value, _arms) when is_list(value), do: :inline
    defp type_expr_arm(value, arms) when is_binary(value) and value != "", do: name_arm(arms)
    defp type_expr_arm(_empty, arms), do: if(:name in arms, do: :name, else: :inline)

    @spec name_arm([:name | :inline]) :: :name | :inline
    defp name_arm(arms), do: if(:name in arms, do: :name, else: :name)

    @spec type_expr_members(term()) :: [term()]
    defp type_expr_members(value) when is_list(value), do: value
    defp type_expr_members(_not_a_member_list), do: []

    # The bytes exactly as stored, for the name arm's input. A value that is
    # neither arm renders raw rather than blank.
    @spec type_expr_name_text(term()) :: String.t()
    defp type_expr_name_text(value) when is_binary(value), do: value
    defp type_expr_name_text(nil), do: ""
    defp type_expr_name_text(value), do: to_text(value)

    # The index path of the member list a gesture is about, dot-joined.
    # Empty for the field's own list; `"0"` for the member list inside the
    # first member's type, and so on down.
    @spec type_expr_path_param([non_neg_integer()]) :: String.t()
    defp type_expr_path_param(path), do: Enum.map_join(path, ".", &Integer.to_string/1)

    @spec member_name(term()) :: String.t()
    defp member_name(%{"name" => name}) when is_binary(name), do: name
    defp member_name(_nameless), do: ""

    @spec member_required?(term()) :: boolean()
    defp member_required?(%{"required?" => required}), do: required in [true, "true", "on", "1"]
    defp member_required?(_member), do: false

    @spec member_type(term()) :: term()
    defp member_type(%{"type" => type}), do: type
    defp member_type(_member), do: ""

    # The posted slice of a type expression, back into the value a document
    # holds: a string for the name arm, a list of member objects for the
    # inline arm.
    #
    # The arm the author is on is what the toggle posted, not what the old
    # value was, which is what makes switching arms replace the value rather
    # than translate it: the arm being left still has its control in the DOM
    # and posts it, and that half is read only when the toggle names it.
    @spec decode_type_expr(term()) :: StatifierBlocks.Block.json()
    defp decode_type_expr(%{"__arm" => "inline"} = raw),
      do: decode_members(Map.get(raw, "members"))

    defp decode_type_expr(%{"__arm" => "name"} = raw), do: decode_type_name(raw)
    defp decode_type_expr(%{"members" => members}), do: decode_members(members)
    defp decode_type_expr(%{"name" => _name} = raw), do: decode_type_name(raw)
    defp decode_type_expr(raw), do: raw

    @spec decode_type_name(map()) :: String.t()
    defp decode_type_name(raw) do
      case Map.get(raw, "name") do
        text when is_binary(text) -> text
        _absent -> ""
      end
    end

    # A row saying nothing at all is dropped, which is what makes clearing a
    # row remove the member; a row that says only half of one is KEPT at the
    # blank it has, so an author who typed the type first sees their own
    # bytes rather than watching them vanish between keystrokes.
    @spec decode_members(term()) :: [map()]
    defp decode_members(rows) when is_map(rows) do
      rows
      |> Enum.sort_by(fn {index, _row} -> member_index(index) end)
      |> Enum.map(fn {_index, row} -> decode_member(row) end)
      |> Enum.reject(&blank_member?/1)
    end

    defp decode_members(_no_rows_posted), do: []

    @spec decode_member(term()) :: map()
    defp decode_member(row) when is_map(row) do
      %{
        "name" => String.trim(member_name(row)),
        "type" => decode_type_expr(Map.get(row, "type")),
        "required?" => member_required?(row)
      }
    end

    defp decode_member(_row), do: %{"name" => "", "type" => "", "required?" => false}

    @spec blank_member?(map()) :: boolean()
    defp blank_member?(%{"name" => "", "type" => type}), do: type in ["", []]
    defp blank_member?(_member), do: false

    @spec member_index(term()) :: integer()
    defp member_index(index) when is_binary(index) do
      case Integer.parse(index) do
        {number, _rest} -> number
        :error -> 0
      end
    end

    defp member_index(_index), do: 0

    @doc "The DOM id for a field's control. Part of decision 7's DOM contract."
    @spec input_id(ViewModel.Field.t()) :: String.t()
    def input_id(%ViewModel.Field{key: key}), do: "sb-field-" <> key

    @doc "The form param name a field's control posts under."
    @spec input_name(ViewModel.Field.t()) :: String.t()
    def input_name(%ViewModel.Field{key: key}), do: "config[" <> key <> "]"

    # The whole set, on `title`: one glance for the shape of a value, one
    # hover for the range of them. `Shell.fixture_hint/3` has already made
    # them distinct and put them in first-appearance order, so this only
    # spells the separator.
    @spec hint_title(StatifierBlocks.Shell.fixture_hint()) :: String.t()
    defp hint_title(%{values: values}), do: Enum.join(values, ", ")

    # One place spells the severity modifiers, and it is outside
    # `StatifierBlocks.Editor.*` so it is asserted with LiveView absent
    # (ADR-0005 decision 11, amended 2026-08-29 for `:info`).
    @spec severity_class(StatifierBlocks.Finding.t()) :: String.t()
    defp severity_class(finding), do: StatifierBlocks.Finding.severity_class(finding)

    # Clause 2 of the moduledoc's ordering: with no override supplied, an
    # `:expression` renders statifier-ui's editor when statifier-ui resolves.
    #
    # `statifier_ui` is optional, so the module is never named as a call
    # target - it is read from application config and captured dynamically.
    # That keeps the compiler quiet in a tree without the package, and it is
    # what lets a test assert the absent branch on a machine where the
    # package is present: point the key at a module that does not exist and
    # the plain input is what renders. statifier-ui reaches `Predicator.Simple`
    # the same way, for the same reason.
    @spec resolve_expression_component((map() -> term()) | nil) :: (map() -> term()) | nil
    defp resolve_expression_component(nil), do: statifier_ui_component()
    defp resolve_expression_component(component), do: component

    @spec statifier_ui_component() :: (map() -> term()) | nil
    defp statifier_ui_component do
      module =
        Application.get_env(
          :statifier_blocks,
          :expression_component_module,
          StatifierUI.Live.ExpressionInput
        )

      if Code.ensure_loaded?(module) and function_exported?(module, :expression_input, 1) do
        &module.expression_input/1
      end
    end

    # The one control a host's candidate list draws on a `:path` or an
    # `:expression`: the field's own text input, bound to a `<datalist>` of
    # the offered values. `data-field-candidates` is the same attribute the
    # `:string` controls carry, because it counts the same feed; the list id
    # ends `-candidates` rather than `-paths` so that a field offered both a
    # host list and the document's declared paths says on screen which one
    # it drew.
    @spec suggestion_control(map(), [{String.t(), String.t()}], String.t(), String.t() | nil) ::
            Phoenix.LiveView.Rendered.t()
    defp suggestion_control(assigns, offered, input_class, placeholder) do
      assigns =
        assigns
        |> assign(:offered, offered)
        |> assign(:list_id, input_id(assigns.field) <> "-candidates")
        |> assign(:input_class, input_class)
        |> assign(:placeholder, placeholder)

      ~H"""
      <input
        class={@input_class}
        type="text"
        id={input_id(@field)}
        name={input_name(@field)}
        value={to_text(@field.value)}
        list={@list_id}
        placeholder={@placeholder}
        spellcheck="false"
        autocomplete="off"
        phx-debounce={@debounce}
      />
      <datalist id={@list_id} data-field-candidates={length(@offered)}>
        <option :for={{value, label} <- @offered} value={value} label={label}></option>
      </datalist>
      """
    end

    @spec expression_input_class() :: String.t()
    defp expression_input_class, do: "sb-field__input sb-field__input--expression"

    # The value a closed list does not offer, which a `<select>` has to draw
    # as an option of its own or lose: a control whose stored value is not
    # among its options posts the FIRST option on the next change, which
    # would make opening a form rewrite a value nobody touched. An empty
    # string is such a value - a field nothing has been picked for yet
    # draws an empty row and stays empty.
    @spec unoffered_value(ViewModel.Field.t(), [{String.t(), String.t()}]) :: String.t() | nil
    defp unoffered_value(%ViewModel.Field{value: value}, candidates) do
      text = to_text(value)

      if Enum.any?(candidates, fn {offered, _label} -> offered == value end), do: nil, else: text
    end

    @spec type_tag(StatifierBlocks.BlockType.field_type()) :: String.t()
    defp type_tag({tag, _inner}), do: Atom.to_string(tag)
    defp type_tag(tag), do: Atom.to_string(tag)

    @spec to_text(term()) :: String.t()
    defp to_text(nil), do: ""
    defp to_text(value) when is_binary(value), do: value
    defp to_text(value) when is_integer(value), do: Integer.to_string(value)
    defp to_text(value), do: inspect(value)
  end
end
