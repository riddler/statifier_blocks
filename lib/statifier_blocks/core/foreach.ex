defmodule StatifierBlocks.Core.Foreach do
  @moduledoc """
  `core.foreach`: a container whose body runs **once per item** of a
  datamodel list (ADR-0004's 2026-08-29 amendment, F1 through F6).

  It is the first core type whose emission is not a fixed subtree, and the
  amendment exists because of that: nothing in the record said where a
  loop counter lives or whether the list is re-read between passes, and a
  block type cannot decide either on its own.

  ## The compile is a plain Appendix D loop (F1)

  Nothing here reaches outside the interpreter's ordinary macrostep
  semantics. There is no engine loop construct, no executable-content
  `<foreach>` (which cannot hold a body that waits for an event), and no
  unrolling: the body's states exist once however long the list is, so its
  provenance entries do too.

      <state id="s_blk_F" initial="s_blk_F__head">
        <onentry>
          <assign location="s_blk_F__items" expr="signup.invitees"/>
          <assign location="s_blk_F__i" expr="0"/>
        </onentry>
        <transition event="done.state.s_blk_F__body" type="internal" target="s_blk_F__head">
          <assign location="s_blk_F__i" expr="s_blk_F__i + 1"/>
        </transition>
        <state id="s_blk_F__head">
          <onentry>
            <assign location="invitee" expr="s_blk_F__items[s_blk_F__i]"/>
            <assign location="invitee_index" expr="s_blk_F__i"/>
          </onentry>
          <transition cond="s_blk_F__items[s_blk_F__i] === undefined" target="s_blk_F__o_done"/>
          <transition target="s_blk_F__body"/>
        </state>
        <state id="s_blk_F__body" initial="s_blk_INVITE">
          ...the body slot's children, sequenced...
          <final id="s_blk_F__body_done"/>
        </state>
        <final id="s_blk_F__o_done">...</final>
      </state>

  ## The loop-back transition is `type="internal"`, and must be

  A transition is external by default, and an external transition **exits
  and re-enters its own source** even when its target is inside it
  (Appendix D's `getTransitionDomain`/`findLCCA`). The loop-back
  transition's source is this block's own state, so the external form
  would re-run the `<onentry>` above on every pass - re-snapshotting the
  list and resetting the cursor to `0` - and the loop would never end.
  F4's "re-targets the head" is only true of the internal form. This is
  pinned upstream by statifier-ex's `st-wlrx` and by a runtime test here.

  ## The cursor and the snapshot are the compiler's roots (F2)

  `s_blk_<id>__i` holds the cursor and `s_blk_<id>__items` holds a
  snapshot of the list, both declared as `<data>` roots through
  `StatifierBlocks.Compiler.DeclaredRoots` and both minted through
  `StatifierBlocks.Compiler.Context.role_id/2`, so decision 3's
  uniqueness keeps them out of any name an author can write.

  The snapshot is assigned **once, at the block's `<onentry>`**, which is
  what gives the loop SCXML 4.6.3's shallow-copy behaviour: the body walks
  the list as it stood when the loop began, and a step inside the body
  that writes the source path does not change what is left to iterate.
  The cursor is reset in the same `<onentry>` as well as declared with
  `expr="0"`, which is what lets a foreach sit inside another foreach's
  body and start from the top on each of the outer loop's passes.

  ## The bindings are declared roots too (F3)

  `item_as` and `index_as` are declared `<data>` roots rather than
  anything scoped: early binding makes a root global, so they exist for
  the whole session, and predicator refuses to read a root nothing
  declared. They are re-assigned in the head state's `<onentry>` on each
  pass, from `snapshot[cursor]`.

  A consequence worth stating: after the loop ends the bindings still hold
  their last values - `item_as` holds the out-of-bounds read, `undefined`.
  A step after the loop that reads them is reading whatever the loop left,
  which is what "global" means and not something this type can narrow.

  ## Termination, and the limit it carries (F5)

  Termination is `snapshot[cursor] === undefined`: predicator indexes
  lists and reads out of bounds as `undefined`, and it has no list-length
  function, so there is no `i < len(items)` to test instead.

  The operator is `===`, strictly. Predicator's loose `==` against
  `undefined` evaluates to `:undefined` rather than to a boolean, so the
  loose form does not express a termination test at all.

  The limit the ruling documents is that a list holding a legitimate
  `undefined`/`null` item stops the loop early at that item. **In the
  resolved predicator the limit is narrower than that wording**, and this
  type is written to the narrower one: `===` is strict, so a `nil` item
  does *not* trip `=== undefined` - only an actual `:undefined` does,
  which for a list read means only an out-of-bounds index. A list holding
  `nil` items therefore iterates to its end, and a runtime test here pins
  it.

  ## Colliding bound names are refused (F6)

  A nested foreach re-using its enclosing loop's `item_as`, or an
  `index_as` equal to a root an enclosing block declares, would silently
  overwrite that binding - early binding makes these roots global, so the
  inner loop's writes are visible to the outer body after the inner loop
  ends. The compiler refuses the document with a `:duplicate_binding`
  Emit-stage finding against the inner block, carrying the config key the
  name was typed into. The check is
  `StatifierBlocks.Compiler.DeclaredRoots`', not this module's, and it is
  a narrow carve-out from decision 9's delegation rather than a general
  id-uniqueness check.

  ### Sibling loops, and what F6 does not cover

  F6's carve-out is **nesting**, and it is exactly the case where the
  overwrite would otherwise be silent. Two *sibling* loops that both call
  their item `invitee` are not that case - neither is inside the other -
  but they are still refused, one stage later: both declare a `<data>`
  root of the same name, and statifier's id-uniqueness check over the
  whole document reports `{:duplicate_id, "invitee"}` against the second
  one, mapped to that block and its `item_as` field. That is decision 9's
  delegation working as written rather than a second check here, and F6
  says as much when it describes itself as pre-empting exactly that
  finding for the nesting case.

  So a document may not have two loops binding one name anywhere, and an
  author renames one of them. **Whether sibling loops should instead
  share one declared root is not a question this type may answer**: a
  shared root is safe for loops that run one after another and is a race
  between the lanes of a `core.parallel`, and picking between them is an
  ADR-level decision about the block vocabulary, not an emitter's.
  """

  @behaviour StatifierBlocks.BlockType

  alias StatifierBlocks.Block
  alias StatifierBlocks.Compiler.{Context, DeclaredRoots, StateId}
  alias StatifierBlocks.Core.{Config, Emit}
  alias StatifierBlocks.Emission

  # The cursor and snapshot roles, minted like any other auxiliary name so
  # decision 3 owns the namespacing (F2 spells them `s_blk_<id>__i` and
  # `s_blk_<id>__items`).
  @cursor_role "i"
  @snapshot_role "items"

  @head_role "head"
  @body_role "body"
  @body_done_role "body_done"

  @body_slot "body"

  @default_item "item"

  # No whitespace and non-empty, and deliberately not a dotted-identifier
  # grammar - `core.assign`'s rule for `path`, for `core.assign`'s reason:
  # this package does not own the datamodel path grammar.
  @whitespace ~r/\s/

  @impl true
  def current_version, do: 1

  @doc """
  One `body` slot, labelled for what makes this container different from
  `core.sequence`: the steps inside it run more than once.
  """
  @impl true
  def slots(_config), do: [{@body_slot, :any, "For each item"}]

  @impl true
  def config_schema(_config),
    do: [
      %{
        key: "items",
        type: :string,
        label: "For each item in",
        required?: true,
        default: "",
        # A foreach only ever reads this path. ADR-0002 decision 7's key is
        # a boolean, so "reads" is not expressible in the declaration; the
        # editor's lint is the same either way (the path must be one the
        # host's datamodel declares).
        datamodel_path?: true
      },
      %{
        key: "item_as",
        type: :string,
        label: "Call the item",
        required?: true,
        default: @default_item
      },
      %{
        key: "index_as",
        type: :string,
        label: "Call the position (optional)",
        required?: false,
        default: ""
      }
    ]

  @impl true
  def validate_config(config) do
    []
    |> check_items(config)
    |> check_item_as(config)
    |> check_index_as(config)
    |> check_distinct(config)
    |> Config.verdict()
  end

  defp check_items(findings, config) do
    if path?(Map.get(config, "items")) do
      findings
    else
      [{"items", "must be a datamodel path naming a list, like signup.invitees"} | findings]
    end
  end

  defp check_item_as(findings, config) do
    if Config.identifier?(Map.get(config, "item_as")) do
      findings
    else
      [{"item_as", "must be a bare lowercase identifier, like invitee"} | findings]
    end
  end

  # The optional-field idiom `core.send` states: `""` is this field's own
  # default, which the config form writes into every block of this type,
  # so absent and empty are both silent.
  defp check_index_as(findings, config) do
    case Map.get(config, "index_as") do
      blank when blank in [nil, ""] ->
        findings

      value ->
        if Config.identifier?(value) do
          findings
        else
          [{"index_as", "must be a bare lowercase identifier, like position"} | findings]
        end
    end
  end

  # The one cross-field check, and it earns its place: two bindings that
  # share a name read fine and mean nothing, since the second assignment
  # in the head state's `<onentry>` would overwrite the first.
  defp check_distinct(findings, config) do
    item_as = Map.get(config, "item_as")
    index_as = Map.get(config, "index_as")

    if Config.identifier?(item_as) and item_as == index_as do
      [{"index_as", "the item and its position cannot share one name"} | findings]
    else
      findings
    end
  end

  @doc """
  `core.group`'s `io/1`: a step containing steps.

  `produces` is absent rather than `:unknown` - a foreach has one outcome,
  so there is no join to refuse, which is the distinction `core.branch`
  and `core.invoke` declare `:unknown` for. `consumes` is absent too, and
  it is the one place a reader might expect otherwise: a foreach does read
  the datamodel through `items`, but that is a config path rather than a
  value arriving through the type flow, exactly as `core.invoke` reads its
  inputs through `params`.
  """
  @impl true
  def io(_config), do: %{kinds: [:step], slot_accepts: %{@body_slot => [:step]}}

  @impl true
  def palette_entry,
    do: %{
      label: "For each",
      group: "Structure",
      description: "Runs its body once for each item in a datamodel list.",
      # `core.resumable_group`'s glyph, and the collision is argued the way
      # `core.subchart` argues its reuse of `rectangle-group`: both blocks
      # are about coming back to the same place, and the circling arrow is
      # the right picture twice.
      icon: "arrow-path",
      keywords: ["foreach", "each", "loop", "iterate", "list", "batch", "repeat"],
      order: 12,
      layout: :stack,
      slot_style: %{@body_slot => :primary},
      # What a card titled "For each invitee" cannot say on its own: the
      # steps below it run more than once.
      badge: "for each"
    }

  @doc """
  The loop, emitted (F1-F5).

  Everything in it is this block's except the transitions leaving the body
  slot's children, which `StatifierBlocks.Core.Emit.chain/2` attributes to
  the child each one leaves (decision 5). The `items` expression, the
  `item_as` location and the `index_as` location are each stamped with the
  config field they came from, so an upstream finding inside one is the
  author's typo rather than a bug in this type.
  """
  @impl true
  def emit(%Block{config: config}, context) do
    with {:ok, items} <- items(config),
         {:ok, item_as} <- item_as(config),
         {:ok, index_as} <- index_as(config),
         {:ok, cursor} <- Context.role_id(context, @cursor_role),
         {:ok, snapshot} <- Context.role_id(context, @snapshot_role),
         {:ok, head} <- Context.role_id(context, @head_role),
         {:ok, body} <- Context.role_id(context, @body_role),
         {:ok, body_done} <- Context.role_id(context, @body_done_role) do
      done = Context.done_id(context)
      read = read(snapshot, cursor)

      children =
        roots(cursor, snapshot, item_as, index_as) ++
          [
            onentry([
              assign(snapshot, items) |> Emission.attribute_from_config("expr", "items"),
              assign(cursor, "0")
            ]),
            loop_back(body, head, cursor),
            head_state(head, body, done, read, item_as, index_as, cursor),
            body_state(context, body, body_done),
            Emit.final(done)
          ]

      {:ok, Emit.state(context.state_id, head, children)}
    end
  end

  # F2/F3's four declared roots, in the order the amendment names them.
  # The cursor carries `expr="0"` as well as being reset at `<onentry>`:
  # the declaration is what an author reading the chart sees, and the
  # reset is what makes a foreach nested inside another one start from the
  # top on every pass of the outer loop.
  @spec roots(String.t(), String.t(), String.t(), String.t() | nil) :: [Emission.t()]
  defp roots(cursor, snapshot, item_as, index_as) do
    [
      DeclaredRoots.declare(cursor, "0"),
      DeclaredRoots.declare(snapshot),
      Emission.from_config(DeclaredRoots.declare(item_as), "item_as")
    ] ++ index_root(index_as)
  end

  @spec index_root(String.t() | nil) :: [Emission.t()]
  defp index_root(nil), do: []

  defp index_root(index_as),
    do: [Emission.from_config(DeclaredRoots.declare(index_as), "index_as")]

  # The loop-back transition, and the one place `internal: true` is not
  # optional: see the moduledoc.
  @spec loop_back(String.t(), String.t(), String.t()) :: Emission.t()
  defp loop_back(body, head, cursor) do
    Emit.transition(
      [event: StateId.done_event(body), target: head, internal: true],
      [assign(cursor, cursor <> " + 1")]
    )
  end

  # The head state: bind this pass's item and index, then either leave the
  # loop on the out-of-bounds read or fall into the body. The conditional
  # transition comes first because document order decides, and an
  # unconditioned transition placed before it would shadow it.
  @spec head_state(
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t(),
          String.t() | nil,
          String.t()
        ) :: Emission.t()
  defp head_state(head, body, done, read, item_as, index_as, cursor) do
    bindings =
      [Emission.attribute_from_config(assign(item_as, read), "location", "item_as")] ++
        index_binding(index_as, cursor)

    Emit.state(head, nil, [
      onentry(bindings),
      Emit.transition(cond: read <> " === undefined", target: done),
      Emit.transition(target: body)
    ])
  end

  @spec index_binding(String.t() | nil, String.t()) :: [Emission.t()]
  defp index_binding(nil, _cursor), do: []

  defp index_binding(index_as, cursor),
    do: [Emission.attribute_from_config(assign(index_as, cursor), "location", "index_as")]

  # The body, compiled once (F4): `core.sequence`'s shape, landing on a
  # completion marker rather than on an outcome final, because entering it
  # means "this pass is over" and not "this block is done".
  @spec body_state(Context.t(), String.t(), String.t()) :: Emission.t()
  defp body_state(context, body, body_done) do
    {initial, transitions, refs} =
      context
      |> Context.children(@body_slot)
      |> Emit.chain(body_done)

    Emit.state(body, initial, transitions ++ refs ++ [Emit.final(body_done)])
  end

  @spec read(String.t(), String.t()) :: String.t()
  defp read(snapshot, cursor), do: snapshot <> "[" <> cursor <> "]"

  @spec onentry([Emission.t()]) :: Emission.t()
  defp onentry(children), do: Emission.element("onentry", [], children)

  @spec assign(String.t(), String.t()) :: Emission.t()
  defp assign(location, expr),
    do: Emission.element("assign", [{"expr", expr}, {"location", location}])

  @spec items(Block.config()) :: {:ok, String.t()} | {:error, [{String.t(), String.t()}]}
  defp items(config) do
    value = Map.get(config, "items")

    if path?(value) do
      {:ok, value}
    else
      {:error, [{"items", "must be a datamodel path naming a list, like signup.invitees"}]}
    end
  end

  @spec item_as(Block.config()) :: {:ok, String.t()} | {:error, [{String.t(), String.t()}]}
  defp item_as(config) do
    value = Map.get(config, "item_as")

    if Config.identifier?(value) do
      {:ok, value}
    else
      {:error, [{"item_as", "must be a bare lowercase identifier, like invitee"}]}
    end
  end

  # `nil` for "the author did not name the position", which is the field's
  # own default and the case that emits no index binding and no index root
  # at all. A malformed value is refused rather than silently dropped.
  @spec index_as(Block.config()) ::
          {:ok, String.t() | nil} | {:error, [{String.t(), String.t()}]}
  defp index_as(config) do
    case Map.get(config, "index_as") do
      blank when blank in [nil, ""] ->
        {:ok, nil}

      value ->
        if Config.identifier?(value) do
          {:ok, value}
        else
          {:error, [{"index_as", "must be a bare lowercase identifier, like position"}]}
        end
    end
  end

  @spec path?(term()) :: boolean()
  defp path?(value),
    do: Config.non_empty_string?(value) and not Regex.match?(@whitespace, value)
end
