# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*, which is the earlier
# of the two problems.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.PresentationTest do
    @moduledoc """
    ADR-0005 decision 10 rendered, and the two remaining field controls.

    The load-bearing assertion here is the negative one: `layout` and
    `slot_style` are how nested groups and lanes render distinctly **without the
    editor branching on a type name**. A host block type with the same
    structural shape gets the same rendering by declaring the same thing, which
    is the property that matters and the one the last test in this module pins
    by reading the component sources.
    """

    use StatifierBlocks.EditorLiveCase

    defmodule StackedJoin do
      @moduledoc """
      A host type that phrases a join marker but stacks its slots - the case
      that separates "this type declared words" from "this arrangement draws
      a marker". Nothing in the core vocabulary is both, so the guard would
      otherwise be asserted against a type that declares nothing and pass
      whether or not it existed.
      """

      @behaviour StatifierBlocks.BlockType

      @impl true
      def current_version, do: 1

      @impl true
      def slots(_config), do: [{"body", :zero_or_more, "Body"}]

      @impl true
      def config_schema(_config), do: []

      @impl true
      def validate_config(_config), do: :ok

      @impl true
      def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

      @impl true
      def palette_entry,
        do: %{label: "Stacked", join_label: fn _config -> "back together" end}
    end

    defmodule TwoArms do
      @moduledoc """
      A host type with two body slots and no declared `layout` - the shape
      `core.branch` has, without the name. It is what separates "this type
      said columns" from "this type has more than one body slot", and it is
      the half of `ViewModel.arrangement/1` a `layout: :columns` fixture
      cannot reach.
      """

      @behaviour StatifierBlocks.BlockType

      @impl true
      def current_version, do: 1

      @impl true
      def slots(_config), do: [{"left", :any, "Left"}, {"right", :any, "Right"}]

      @impl true
      def config_schema(_config), do: []

      @impl true
      def validate_config(_config), do: :ok

      @impl true
      def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

      @impl true
      def palette_entry, do: %{label: "Either way"}
    end

    defmodule ColumnsNoWords do
      @moduledoc """
      The other half of the same pair: a type that fans out and declares no
      words for the marker. ADR-0002 amendment B's `nil` means the editor
      uses its own word, so this is what that sentence looks like rendered.
      """

      @behaviour StatifierBlocks.BlockType

      @impl true
      def current_version, do: 1

      @impl true
      def slots(_config), do: [{"left", :zero_or_more, "Left"}, {"right", :zero_or_more, "Right"}]

      @impl true
      def config_schema(_config), do: []

      @impl true
      def validate_config(_config), do: :ok

      @impl true
      def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

      @impl true
      def palette_entry, do: %{label: "Both at once", layout: :columns}
    end

    defp lanes_document do
      Document.new(
        Block.new("core.parallel",
          id: "blk_lanes",
          config: %{"lanes" => ["signup", "email"]},
          slots: %{
            "lane_signup" => [EditorFixtures.wait("blk_l1", "1h")],
            "lane_email" => [EditorFixtures.wait("blk_l2", "2h")]
          }
        ),
        id: "doc_lanes"
      )
    end

    defp first_lanes_document do
      Document.new(
        Block.new("core.parallel",
          id: "blk_lanes",
          config: %{"lanes" => ["signup", "email"], "complete" => "first"},
          slots: %{
            "lane_signup" => [EditorFixtures.wait("blk_l1", "1h")],
            "lane_email" => [EditorFixtures.wait("blk_l2", "2h")]
          }
        ),
        id: "doc_lanes_first"
      )
    end

    # The two-armed block is NESTED rather than the root, so a container that
    # is not the root and a leaf that is not the root are both on the page:
    # `data-container` has to be read off the node's slots, and a rendering
    # that read it off `@root?` would answer correctly for a root container by
    # accident.
    defp two_armed_document do
      Document.new(
        Block.new("core.sequence",
          id: "blk_root",
          config: %{},
          slots: %{
            "body" => [
              Block.new("host.two_arms",
                id: "blk_arms",
                config: %{},
                slots: %{"left" => [EditorFixtures.wait("blk_left", "1h")], "right" => []}
              )
            ]
          }
        ),
        id: "doc_arms"
      )
    end

    defp two_armed_palette do
      Palette.new(%{
        "core.sequence" => StatifierBlocks.Core.Sequence,
        "core.wait" => StatifierBlocks.Core.Wait,
        "host.two_arms" => TwoArms
      })
    end

    defmodule GuardedArm do
      @moduledoc """
      A host type that keys an `:expression` field by one of its own slot
      names - `core.branch`'s shape without `core.branch`'s name.

      It is what separates "the editor draws a chip for a branch" from "the
      editor draws a chip for a slot its container declared a condition for".
      Only the second is a rendering rule; the first is a type name in the
      renderer, which ADR-0005 forbids and the last test in this module
      scans for.
      """

      @behaviour StatifierBlocks.BlockType

      @impl true
      def current_version, do: 1

      @impl true
      def slots(_config), do: [{"when_hot", :any, "When hot"}, {"otherwise", :any, "Otherwise"}]

      @impl true
      def config_schema(_config),
        do: [
          %{
            key: "when_hot",
            type: :expression,
            label: "When hot",
            required?: true,
            default: "",
            value_path: ["guard"]
          }
        ]

      @impl true
      def validate_config(_config), do: :ok

      @impl true
      def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

      @impl true
      def palette_entry, do: %{label: "Guarded"}
    end

    defp guarded_document do
      Document.new(
        Block.new("host.guarded", id: "blk_guarded", config: %{"guard" => "temperature > 90"}),
        id: "doc_guarded"
      )
    end

    defp resumable_document do
      Document.new(
        Block.new("core.resumable_group", id: "blk_resume", config: %{"history" => "deep"}),
        id: "doc_resume"
      )
    end

    describe "layout and slot_style (d10)" do
      # Sabotage: `BlockNode.layout_class/1` answering "sb-node__slots--stack"
      # for every node - a parallel's lanes stack and the absence of ordering
      # between them stops being visible.
      test "layout: :columns puts a parallel's lanes side by side", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: lanes_document())

        assert has_element?(view, ~s([data-block-id="blk_lanes"] > .sb-node__slots--columns))
        refute has_element?(view, ~s([data-block-id="blk_lanes"] > .sb-node__slots--stack))
      end

      # Sabotage: drop the `:if={join_label(@node)}` marker div from
      # `BlockNode.block_node/1` - the lanes fan out and nothing says what
      # happens when they are done, which is the state the shipped editor was
      # in while the callback existed and was exercised.
      test "the join marker under the lanes reads the type's own words", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: first_lanes_document())

        assert has_element?(
                 view,
                 ~s([data-block-id="blk_lanes"] > .sb-node__join > .sb-node__join-label),
                 "continue at first"
               )
      end

      # Sabotage: return `label` alone from `BlockNode.join_label/1` instead of
      # `label || @default_join_label` - a type that fans out without phrasing
      # a rule loses its marker, and amendment B's "the editor should use its
      # own word" stops being true of the editor.
      test "a side-by-side type declaring no words gets the editor's own", %{conn: conn} do
        document =
          Document.new(
            Block.new("host.columns_no_words", id: "blk_cols", config: %{}),
            id: "doc_cols"
          )

        palette = Palette.new(%{"host.columns_no_words" => ColumnsNoWords})

        {:ok, view, _html} = mount_editor(conn, document: document, palette: palette)

        # The view model carries nothing: the word below is the editor's.
        assert StatifierBlocks.ViewModel.build(document, palette, []).root.join_label == nil

        assert has_element?(
                 view,
                 ~s([data-block-id="blk_cols"] > .sb-node__join > .sb-node__join-label),
                 "continue"
               )
      end

      # Sabotage: drop the `layout: :columns` clause from
      # `BlockNode.join_label/1` so it reads the field for every node - a type
      # whose slots stack draws a marker under a single column, which says
      # nothing came back together because nothing fanned out.
      test "a type whose slots stack draws no marker, however it phrases one", %{conn: conn} do
        document =
          Document.new(
            Block.new("host.stacked_join", id: "blk_stacked", config: %{}),
            id: "doc_stacked"
          )

        palette = Palette.new(%{"host.stacked_join" => StackedJoin})

        {:ok, view, _html} = mount_editor(conn, document: document, palette: palette)

        # The words are on the view model - this refutation is about where the
        # marker is drawn, not about a type that declared nothing.
        assert StatifierBlocks.ViewModel.build(document, palette, []).root.join_label ==
                 "back together"

        refute has_element?(view, ~s([data-block-id="blk_stacked"] > .sb-node__join))
      end

      # Sabotage: `ViewModel.slot_presentation/2` returning `:primary` always -
      # the interrupts rail renders as a second body.
      test "slot_style renders an interrupts rail as secondary, and body as primary", %{
        conn: conn
      } do
        {:ok, view, _html} = mount_editor(conn, document: resumable_document())

        assert has_element?(
                 view,
                 ~s([data-slot-name="interrupts"][data-parent-id="blk_resume"].sb-slot--secondary)
               )

        refute has_element?(
                 view,
                 ~s([data-slot-name="body"][data-parent-id="blk_resume"].sb-slot--secondary)
               )
      end

      # Sabotage: `ViewModel.palette_entry_with_defaults/2` skipping the merge
      # with `@default_entry` - a type without `palette_entry/0` loses its label
      # fallback, and the unresolvable block's chrome renders blank.
      test "a block type with no palette_entry/0 still renders, on the defaults", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        assert has_element?(
                 view,
                 ~s([data-block-id="blk_track_conversion"] > .sb-node__chrome > .sb-node__label),
                 EditorFixtures.unknown_type()
               )
      end

      # Sabotage: replacing `<.icon_glyph>`'s host-component arm with one that
      # renders `@name` as raw markup - the record's "an icon is a name, never
      # markup" rule is broken and the escaped-text assertion goes red.
      test "an icon is a name passed to a host component, never markup", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        assert has_element?(
                 view,
                 ~s([data-block-id="blk_email_step"] .sb-node__icon[data-icon="clock"])
               )
      end
    end

    describe "the tier-2 layout: cards, columns and the pill (10b, campaign 016)" do
      # Sabotage: `BlockNode.layout_class/1` reading `entry.layout` again
      # instead of `ViewModel.arrangement/1` - a branch's arms stack full-width
      # once more, and every fan edge runs straight down through the arm above
      # the one it is going to (`sb-ay0`). The two assertions are the two
      # spellings that have to agree: the class the columns are laid out by,
      # and the attribute the pill is tinted off.
      test "a type with several body slots puts them side by side too", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn, document: two_armed_document(), palette: two_armed_palette())

        assert has_element?(
                 view,
                 ~s([data-block-id="blk_arms"][data-arrangement="fan"] > .sb-node__slots--columns)
               )

        refute has_element?(view, ~s([data-block-id="blk_arms"] > .sb-node__slots--stack))
      end

      # Sabotage: giving `ViewModel.fan_label/1` one word for both
      # arrangements - side-by-side columns look identical either way, so the
      # canvas stops saying whether one column runs or all of them do.
      test "the pill says one of over a fan and all of over lanes", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn, document: two_armed_document(), palette: two_armed_palette())

        assert has_element?(
                 view,
                 ~s([data-block-id="blk_arms"] > .sb-node__fan > .sb-node__fan-label),
                 "one of"
               )

        {:ok, lanes, _html} = mount_editor(conn, document: lanes_document())

        assert has_element?(
                 lanes,
                 ~s([data-block-id="blk_lanes"] > .sb-node__fan > .sb-node__fan-label),
                 "all of"
               )
      end

      # Sabotage: dropping the `:if={ViewModel.fan_label(@node)}` guard - a
      # sequence draws a pill over a single column, which claims a division
      # that is not there.
      test "a stacked container draws no pill", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: resumable_document())

        refute has_element?(view, ~s([data-block-id="blk_resume"] > .sb-node__fan))
      end

      # The pill and the join marker are hubs, not decoration: `Connectors`
      # resolves the fan and the rejoin to them when they were measured.
      # Sabotage: dropping `data-sb-anchor` from either marker - the hook stops
      # measuring it, `marker_or/3` falls back to the card and the outlet, and
      # every arm is drawn through the marker's own words.
      test "both markers carry the anchor the measurement hook reads", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: first_lanes_document())

        assert has_element?(
                 view,
                 ~s(.sb-node__fan[data-sb-anchor="#{StatifierBlocks.Connectors.fan_anchor("blk_lanes")}"])
               )

        assert has_element?(
                 view,
                 ~s(.sb-node__join[data-sb-anchor="#{StatifierBlocks.Connectors.join_anchor("blk_lanes")}"])
               )
      end

      # The card's width and centring are one CSS rule each, and both hang off
      # this attribute - a leaf's box IS its card, a container's box holds its
      # children and centres its chrome instead.
      # Sabotage: stamping `data-container` from `@root?` instead of from the
      # node's slots - every non-root container is styled as a leaf, so a
      # nested branch's box shrinks to a card width and its arms overflow it.
      # The fixture nests the container for exactly this reason: a root-only
      # document cannot tell the two readings apart.
      test "a leaf says it is not a container and a container says it is", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn, document: two_armed_document(), palette: two_armed_palette())

        assert has_element?(view, ~s([data-block-id="blk_root"][data-container="true"]))
        assert has_element?(view, ~s([data-block-id="blk_arms"][data-container="true"]))
        assert has_element?(view, ~s([data-block-id="blk_left"][data-container="false"]))
      end

      # R3's placeholder half (operator ruling 2026-08-29): an empty arm is a
      # real arm and has to look like somewhere to drop.
      # Sabotage: stamping `data-empty` off the slot's arity rather than its
      # children - a filled `:any` slot claims to be empty and keeps the
      # placeholder ring for the rest of its life.
      test "an empty slot says so, and a filled one does not", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn, document: two_armed_document(), palette: two_armed_palette())

        assert has_element?(
                 view,
                 ~s([data-parent-id="blk_arms"][data-slot-name="right"][data-empty="true"])
               )

        assert has_element?(
                 view,
                 ~s([data-parent-id="blk_arms"][data-slot-name="left"][data-empty="false"])
               )
      end

      # R3 keeps the affordance it restyles: the marker IS the gap, so the
      # server events and the keyboard path are the ones that already shipped.
      # Sabotage: moving the insertion marker onto the connector overlay - the
      # overlay is `aria-hidden` with `pointer-events: none` and is absent
      # entirely without the measure hook, so this button stops existing.
      test "the marker is still the gap's own button, with its own events", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn, document: two_armed_document(), palette: two_armed_palette())

        assert has_element?(
                 view,
                 ~s([data-parent-id="blk_arms"][data-slot="right"][data-index="0"] .sb-gap__add)
               )
      end
    end

    describe "the remaining field controls" do
      # Sabotage: `Field.control/1`'s `{:select, choices}` clause rendering the
      # choices sorted rather than in declared order.
      test "a :select renders its choices in declared order, current one selected", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: resumable_document())

        view
        |> element(~s([data-block-id="blk_resume"] > .sb-node__chrome > .sb-node__label))
        |> render_click()

        select = view |> element(~s([data-field="history"] select)) |> render()

        assert select =~ ~r/shallow.*deep/s
        assert select =~ ~s(<option value="deep" selected)
      end

      # Sabotage: `Editor.update_list/3` appending to `field.default` rather
      # than to the block's current config - the existing lanes disappear.
      test "a {:list, t} adds and removes rows without losing the ones there", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: lanes_document())

        view
        |> element(~s([data-block-id="blk_lanes"] > .sb-node__chrome > .sb-node__label))
        |> render_click()

        # An added row is empty, which `validate_config/1` rejects - so it lives
        # in the draft and the document does not move. That is decision 9's gate
        # working, not the add failing.
        html = view |> element(~s(button[phx-click="field-list-add"])) |> render_click()

        assert length(Regex.scan(~r/data-row="\d+"/, html)) == 3
        refute latest_document()

        view
        |> form(~s(#sb-form-blk_lanes), %{"config" => %{"lanes" => ["signup", "email", "sms"]}})
        |> render_change()

        assert lanes(latest_document()) == ["signup", "email", "sms"]

        view
        |> element(~s(button[phx-click="field-list-remove"][phx-value-index="1"]))
        |> render_click()

        assert lanes(latest_document()) == ["signup", "sms"]
      end

      # Sabotage: `ConfigForm.decode/3`'s list arm keeping only the first row -
      # editing one lane deletes the others.
      test "editing a {:list, t} posts every row", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: lanes_document())

        view
        |> element(~s([data-block-id="blk_lanes"] > .sb-node__chrome > .sb-node__label))
        |> render_click()

        view
        |> form(~s(#sb-form-blk_lanes), %{"config" => %{"lanes" => ["signup", "sms"]}})
        |> render_change()

        assert lanes(latest_document()) == ["signup", "sms"]
      end
    end

    describe "slot labels, lane rules and the interrupt region (1.7, campaign 016)" do
      @stylesheet "assets/css/statifier_blocks.css"

      # The spike's arm header is two lines: the arm's name in small caps, and
      # the predicate it is subject to beneath it. Without the second line a
      # branch's arms on the canvas are `WHEN "VARIANT B"` and `OTHERWISE`,
      # which names the arms and says nothing about what picks between them.
      # Sabotage: dropping the `:if={@slot.condition}` chip from `Slot.slot/1`
      # - every arm keeps its name and the canvas stops showing a single
      # condition, which is the state this parity item found the editor in.
      test "an arm's header carries its condition, in the author's own text", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        assert has_element?(
                 view,
                 ~s([data-parent-id="blk_variant"][data-slot-name="arm_variant_b"] > .sb-slot__header > .sb-slot__name > .sb-slot__condition),
                 "variant == 'b'"
               )
      end

      # The whole expression is in the `title`, because the chip is one clipped
      # line by design and a truncated predicate an author cannot read the end
      # of is worse than none.
      # Sabotage: rendering the chip without `title` - the ellipsis stays and
      # the only way to see what an arm actually tests becomes the inspector.
      test "the whole expression is on the chip, however the line is clipped", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        assert has_element?(
                 view,
                 ~s([data-slot-name="arm_variant_b"] .sb-slot__condition[title="variant == 'b'"])
               )
      end

      # A chip is a claim that a condition exists. `otherwise` is the arm that
      # is subject to none, and every slot of every stacked group is too.
      # Sabotage: rendering the chip unconditionally - `otherwise` grows an
      # empty box that reads as a condition which evaluated to nothing.
      test "a slot with no condition renders no chip, not an empty one", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn)

        assert has_element?(
                 view,
                 ~s([data-parent-id="blk_variant"][data-slot-name="otherwise"] > .sb-slot__header > .sb-slot__name > .sb-slot__label),
                 "Otherwise"
               )

        refute has_element?(
                 view,
                 ~s([data-parent-id="blk_variant"][data-slot-name="otherwise"] .sb-slot__condition)
               )
      end

      # The load-bearing negative, and the reason the derivation lives on the
      # view model rather than in the component: the chip follows a
      # DECLARATION, never a type name.
      # Sabotage: deriving the chip from `node.type == "core.branch"` - this
      # goes red, and so does the type-name scan in the last describe.
      test "a host type that guards its own arm gets the same chip", %{conn: conn} do
        palette = Palette.new(%{"host.guarded" => GuardedArm})

        {:ok, view, _html} =
          mount_editor(conn, document: guarded_document(), palette: palette)

        assert has_element?(
                 view,
                 ~s([data-parent-id="blk_guarded"][data-slot-name="when_hot"] .sb-slot__condition),
                 "temperature > 90"
               )

        refute has_element?(
                 view,
                 ~s([data-parent-id="blk_guarded"][data-slot-name="otherwise"] .sb-slot__condition)
               )
      end

      # The stylesheet half of the same item. Caps is what makes a slot label
      # read as chrome labelling a structure rather than as a name the author
      # typed, and it is the treatment the fan pill and the join marker
      # already carry.
      # Sabotage: dropping `text-transform` from `.sb-slot__label` - the spike
      # reads `WHEN "VALID"` and the editor reads `When "valid"`, which is the
      # parity gap this item names, and every markup assertion above stays
      # green through it.
      test "the label is small, caps and tracked" do
        css = File.read!(@stylesheet)
        label = Regex.run(~r/^\.sb-slot__label\s*\{(.*?)\n\}/ms, css)

        assert label, "the scan actually found the rule"
        [_all, body] = label

        assert body =~ ~r/text-transform:\s*uppercase/
        assert body =~ ~r/letter-spacing:\s*var\(--sb-tracking-caps\)/
        assert body =~ ~r/font-size:\s*var\(--sb-text-xs\)/
      end

      # The lane rule carries "these run at once" down the page, past the pill
      # at the top of the block that says it once.
      # Sabotage: hanging the rule off `.sb-node__slots--columns` instead of
      # `data-arrangement="lanes"` - a branch's arms take the accent too, and
      # the one distinction side-by-side columns have stops being drawn.
      test "a lane's header takes the accent rule, and it is read off the arrangement" do
        css = File.read!(@stylesheet)

        rule =
          Regex.run(
            ~r/^\.sb-node\[data-arrangement="lanes"\][^\{]*>\s*\.sb-slot__header\s*\{(.*?)\n\}/ms,
            css
          )

        assert rule, "the scan actually found the rule"
        [_all, body] = rule

        assert body =~ ~r/border-top:\s*var\(--sb-block-edge\)\s+solid\s+var\(--sb-block-accent\)/
      end

      # 10h's `:secondary` placement, in the colour the connector layer already
      # draws an interrupt edge in - the rail and the edge leaving it are one
      # thing and were drawn in two vocabularies.
      # Sabotage: colouring the label `--sb-fg-muted` again - two grey words
      # over a warning-coloured dashed edge read as a colour that leaked from
      # somewhere else rather than as the heading of the region below.
      test "the interrupt rail and its label take the interrupt edge's colour" do
        css = File.read!(@stylesheet)

        rail = Regex.run(~r/^\.sb-slot--secondary\s*\{(.*?)\n\}/ms, css)

        label =
          Regex.run(~r/^\.sb-slot--secondary\s*>[^\{]*\.sb-slot__label\s*\{(.*?)\n\}/ms, css)

        assert rail, "the scan actually found the rail rule"
        assert label, "the scan actually found the label rule"

        assert elem(List.to_tuple(rail), 1) =~ ~r/border-left-color:\s*var\(--sb-edge-interrupt\)/
        assert elem(List.to_tuple(label), 1) =~ ~r/color:\s*var\(--sb-edge-interrupt\)/
      end

      # The words are the block type's, not the stylesheet's: `INTERRUPT RULES`
      # is `core.resumable_group`'s own "Interrupt rules" in caps.
      # Sabotage: hard-coding the region's heading in CSS with `content:` - a
      # host type declaring `:secondary` gets someone else's words, and this
      # goes red because the type's own string is no longer in the markup.
      test "the region's heading is the type's own words", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: resumable_document())

        assert has_element?(
                 view,
                 ~s([data-parent-id="blk_resume"][data-slot-name="interrupts"].sb-slot--secondary > .sb-slot__header > .sb-slot__name > .sb-slot__label),
                 "Interrupt rules"
               )
      end
    end

    describe "the operator pre-decision" do
      # Sabotage: adding `defp layout_class(%Node{type: "core.parallel"}), do: ...`
      # to BlockNode - the type name appears in a component source and this goes
      # red with the record's sentence.
      test "no component branches on a block type name" do
        # Prose names `core.parallel` freely - explaining why there is no branch
        # on it is the opposite of branching on it. What this scans is code.
        offenders =
          "lib/statifier_blocks/editor/*.ex"
          |> Path.wildcard()
          |> Enum.filter(fn path ->
            path |> File.read!() |> code_only() =~ ~r/"[a-z_]+\.[a-z_]+"/
          end)

        assert offenders == [], """
        ADR-0005: the editor never contains a branch on a type name - not on
        `core.branch`, not on `core.parallel`, and certainly not on any host
        type. If the editor cannot render a block type through the callbacks
        alone, the deficiency is in the callback surface and gets fixed there.

        Offending files: #{inspect(offenders)}
        """
      end

      test "there is no Group component and no Parallel component" do
        modules =
          "lib/statifier_blocks/editor/*.ex" |> Path.wildcard() |> Enum.map(&Path.basename/1)

        refute "group.ex" in modules
        refute "parallel.ex" in modules
        assert "block_node.ex" in modules
      end
    end

    # Source with its doc heredocs and its `#` comments removed, so a scan for
    # a type name in *code* is not fooled by a moduledoc that explains the rule.
    defp code_only(source) do
      source
      |> String.replace(~r/"""[\s\S]*?"""/, "")
      |> String.replace(~r/^\s*#.*$/m, "")
    end

    defp lanes(document) do
      document
      |> Document.blocks()
      |> Enum.find(&(&1.id == "blk_lanes"))
      |> get_in([
        Access.key!(:config),
        "lanes"
      ])
    end
  end
end
