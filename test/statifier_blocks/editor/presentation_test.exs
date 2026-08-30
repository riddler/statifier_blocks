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

    defmodule NamedStep do
      @moduledoc """
      A host type whose instances are worth naming individually: it declares
      a `:string` field keyed `label`, which is the seam the card's title
      override reads. Nothing in the core vocabulary declares one - "Wait" is
      what a wait is called - so the two-line card cannot be exercised
      without a type like this.
      """

      @behaviour StatifierBlocks.BlockType

      @impl true
      def current_version, do: 1

      @impl true
      def slots(_config), do: []

      @impl true
      def config_schema(_config),
        do: [%{key: "label", type: :string, label: "Name", required?: false, default: ""}]

      @impl true
      def validate_config(_config), do: :ok

      @impl true
      def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

      @impl true
      def palette_entry, do: %{label: "Intake"}
    end

    defmodule NamedAndSummarising do
      @moduledoc """
      A host type that both names its instances and summarises them - the
      only shape that can draw both second lines at once, and therefore the
      only fixture that can prove it draws one (ADR-0005 amendment 10q).
      """

      @behaviour StatifierBlocks.BlockType

      @impl true
      def current_version, do: 1

      @impl true
      def slots(_config), do: []

      @impl true
      def config_schema(_config),
        do: [%{key: "label", type: :string, label: "Name", required?: false, default: ""}]

      @impl true
      def validate_config(_config), do: :ok

      @impl true
      def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

      @impl true
      def palette_entry, do: %{label: "Intake"}

      @impl true
      def summary(_config), do: ["from the type"]
    end

    defp both_document do
      Document.new(
        Block.new("host.both", id: "blk_both", config: %{"label" => "Collect the details"}),
        id: "doc_both"
      )
    end

    defp both_palette, do: Palette.new(%{"host.both" => NamedAndSummarising})

    # Three cards and a root: one block with a name of its own, one without,
    # and one that calls a handler. Every line of the card face is on the page
    # once, and every one of them is absent from at least one other card.
    defp named_document do
      Document.new(
        Block.new("core.sequence",
          id: "blk_named_root",
          slots: %{
            "body" => [
              Block.new("host.named",
                id: "blk_named",
                config: %{"label" => "Collect the details"}
              ),
              EditorFixtures.wait("blk_wait", "1h"),
              Block.new("core.invoke",
                id: "blk_call",
                config: %{"invoke_type" => "myapp:authorize"}
              )
            ]
          }
        ),
        id: "doc_named"
      )
    end

    defp named_palette do
      Palette.new(%{
        "core.sequence" => StatifierBlocks.Core.Sequence,
        "core.wait" => StatifierBlocks.Core.Wait,
        "core.invoke" => StatifierBlocks.Core.Invoke,
        "host.named" => NamedStep
      })
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

    describe "the card face (parity item 1.4, campaign 016)" do
      # Sabotage: rendering `@node.entry.label` again instead of
      # `ViewModel.title/1` - a block the author named reads as its type, and
      # the name they typed is visible nowhere on the canvas.
      test "a named block reads as its name over its type", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn, document: named_document(), palette: named_palette())

        assert has_element?(
                 view,
                 ~s([data-block-id="blk_named"] > .sb-node__chrome > .sb-node__label),
                 "Collect the details"
               )

        assert has_element?(
                 view,
                 ~s([data-block-id="blk_named"] > .sb-node__chrome > .sb-node__type),
                 "Intake"
               )
      end

      # An unnamed block still says its type once: the second line is either
      # the type's summary of this block's config, drawn as a chip row
      # (ADR-0002 amendment H5, ADR-0005 amendment 10q), or nothing at all,
      # and never the type label the line above already carries.
      # Sabotage: dropping the `:if={ViewModel.subtitle(@node)}` guard - the
      # unnamed cards grow a second line repeating their own title.
      test "an unnamed block says its type once", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn, document: named_document(), palette: named_palette())

        assert has_element?(
                 view,
                 ~s([data-block-id="blk_wait"] > .sb-node__chrome > .sb-node__label),
                 "Wait"
               )

        refute has_element?(
                 view,
                 ~s([data-block-id="blk_wait"] > .sb-node__chrome > .sb-node__type)
               )

        refute has_element?(
                 view,
                 ~s([data-block-id="blk_call"] > .sb-node__chrome > .sb-node__type)
               )
      end

      # ADR-0005's 2026-08-30 amendment (decision 10, the summary chip row).
      # Placement only: which chips a type declares is `card_summary_test`'s,
      # and it runs with LiveView absent.
      # Sabotage: rendering `Enum.join(chips, ", ")` into one span instead of
      # the `:for` - the row holds one chip carrying both lanes, and the card
      # is back to the joined line this amendment replaced.
      test "a multi-chip summary draws one element per chip", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: lanes_document())

        row =
          view
          |> element(~s([data-block-id="blk_lanes"] > .sb-node__chrome > .sb-node__summary))
          |> render()

        chips =
          ~r|<span[^>]*class="sb-node__chip"[^>]*>\s*([^<]*?)\s*</span>|
          |> Regex.scan(row)
          |> Enum.map(&Enum.at(&1, 1))

        assert chips == ["signup", "email"]
      end

      # The two degenerate cases 10q states: a string summary is one chip,
      # and no summary is no row rather than an empty one.
      # Sabotage: dropping the `:if={ViewModel.summary_chips(@node) != []}`
      # guard - the invoke card, which declares no summary, draws an empty
      # row element, which is chrome with nothing in it.
      test "one chip for a string summary, and no row without one", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn, document: named_document(), palette: named_palette())

        assert has_element?(
                 view,
                 ~s([data-block-id="blk_wait"] > .sb-node__chrome > ) <>
                   ~s(.sb-node__summary > .sb-node__chip),
                 "timer 1h"
               )

        refute has_element?(
                 view,
                 ~s([data-block-id="blk_call"] > .sb-node__chrome > .sb-node__summary)
               )
      end

      # A card has one second line, and a named card has already spent it on
      # the type label (H5). The host type here names its instances and
      # declares no summary, so this pins the placement rule rather than the
      # view model's exclusion, which `card_summary_test` pins directly.
      # Sabotage: giving the row the `:if={@node.summary != []}` guard
      # instead of `summary_chips/1` - a named card that also summarises
      # draws both second lines.
      test "a named card draws the type label and no chip row", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn, document: both_document(), palette: both_palette())

        assert has_element?(
                 view,
                 ~s([data-block-id="blk_both"] > .sb-node__chrome > .sb-node__label),
                 "Collect the details"
               )

        assert has_element?(
                 view,
                 ~s([data-block-id="blk_both"] > .sb-node__chrome > .sb-node__type),
                 "Intake"
               )

        refute has_element?(
                 view,
                 ~s([data-block-id="blk_both"] > .sb-node__chrome > .sb-node__summary)
               )
      end

      # Sabotage: dropping the `:if={@node.invoke_type}` guard - every card
      # draws an empty mono line, and a wait claims a third line it has
      # nothing to put on.
      test "the invoke type is a third line, and only where there is one", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn, document: named_document(), palette: named_palette())

        assert has_element?(
                 view,
                 ~s([data-block-id="blk_call"] > .sb-node__chrome > .sb-node__invoke),
                 "myapp:authorize"
               )

        refute has_element?(
                 view,
                 ~s([data-block-id="blk_wait"] > .sb-node__chrome > .sb-node__invoke)
               )
      end

      # R2 (operator ruling 2026-08-29): nothing at rest, revealed on hover or
      # selection - so the control has to be in the DOM the whole time and
      # hidden by style alone. Asserted as the attribute the stylesheet
      # selects rather than as a computed style, which LiveViewTest cannot
      # see.
      # Sabotage: dropping `data-reveal` from the button - the rest rule below
      # matches nothing, the control is visible on all forty cards again, and
      # this goes red on the attribute rather than on a screenshot.
      test "the delete control is present at rest, and says how it is revealed", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn, document: named_document(), palette: named_palette())

        assert has_element?(
                 view,
                 ~s([data-block-id="blk_wait"] > .sb-node__chrome > ) <>
                   ~s(.sb-node__remove[data-reveal="hover-or-selected"])
               )

        refute has_element?(
                 view,
                 ~s([data-block-id="blk_named_root"] > .sb-node__chrome > .sb-node__remove)
               ),
               "the root is not deletable, so the affordance is absent"
      end

      # The other half of the same contract, and the half a LiveView test
      # cannot reach: the attribute above is only worth asserting if a rule
      # actually hides the control at rest and reveals it on all three of
      # hover, focus and selection.
      # Sabotage: deleting the `opacity: 0` declaration from the rest rule -
      # the markup assertion above still passes and this goes red, which is
      # the split the two tests exist for.
      test "the stylesheet hides it at rest and reveals it three ways" do
        css = File.read!("assets/css/statifier_blocks.css")

        [_before, from_rest_rule] =
          String.split(css, ~s(.sb-node__remove[data-reveal="hover-or-selected"] {), parts: 2)

        [rest_declarations, _after] = String.split(from_rest_rule, "}", parts: 2)

        assert rest_declarations =~ "opacity: 0"

        for selector <- [
              ".sb-node__chrome:hover > .sb-node__remove",
              ".sb-node__remove:focus-visible",
              ".sb-node--selected > .sb-node__chrome > .sb-node__remove"
            ] do
          assert css =~ selector, "the reveal rule lost #{selector}"
        end
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

    describe "the container box (10c, as amended by 10h)" do
      @stylesheet "assets/css/statifier_blocks.css"

      # The record's rule, in markup terms: whether a container draws a box is
      # `ViewModel.boundary?/1` and nothing else, and the class is the whole of
      # the contract a stylesheet - this one, or a host's - reads it through.
      # `boundary?/1` itself is unchanged by this bead; what is asserted here
      # is that the two containers are distinguishable by class alone.
      # Sabotage: stamping `sb-node--boundary` unconditionally in
      # `BlockNode.block_node/1` - every container is a box again and the
      # refutation below goes red, which is the state the shipped editor was in.
      test "a container is marked a box only when it has a rail", %{conn: conn} do
        {:ok, plain, _html} = mount_editor(conn)

        assert has_element?(plain, ~s([data-block-id="blk_wizard"][data-container="true"]))
        refute has_element?(plain, ~s([data-block-id="blk_wizard"].sb-node--boundary))
        refute has_element?(plain, ~s([data-block-id="blk_variant"].sb-node--boundary))

        {:ok, railed, _html} = mount_editor(conn, document: resumable_document())

        assert has_element?(
                 railed,
                 ~s([data-block-id="blk_resume"][data-container="true"].sb-node--boundary)
               )
      end

      # And the stylesheet's half of it. A container has its box TAKEN OFF -
      # before this bead the base `.sb-node` rule drew one around every node,
      # leaf and container alike, so the boundary class only ever moved its
      # colour and every sequence on the canvas was a rectangle.
      # Sabotage: deleting the rule - a depth-7 document is nested rectangles
      # again, which is the state the shipped canvas was captured in.
      test "the box comes off a container" do
        css = File.read!(@stylesheet)

        rule = Regex.run(~r/^\.sb-node\[data-container="true"\]\s*\{(.*?)\n\}/ms, css)

        assert rule, "the scan actually found the rule"

        body = Enum.at(rule, 1)
        assert body =~ ~r/border-color:\s*transparent/
        assert body =~ ~r/background:\s*none/
        assert body =~ ~r/padding:\s*0/
      end

      # The card at the head of the body is what survives the box coming off,
      # so the card's border has to be drawn by the CARD on a container rather
      # than by the box that is no longer there.
      # Sabotage: dropping the `border` declaration from the container's chrome
      # rule - a sequence's header stops reading as a card at all, which is the
      # regression the box removal would otherwise ship.
      test "a container's own card keeps its border" do
        css = File.read!(@stylesheet)

        rule =
          Regex.run(
            ~r/^\.sb-node\[data-container="true"\] > \.sb-node__chrome\s*\{(.*?)\n\}/ms,
            css
          )

        assert rule, "the scan actually found the rule"

        body = Enum.at(rule, 1)
        assert body =~ ~r/border:\s*var\(--sb-border-width\) solid var\(--sb-border\)/
        assert body =~ ~r/width:\s*var\(--sb-card-width\)/
      end

      # A boundary's box is a box, and it is drawn around the BODY - the slot
      # box holding the body and the rail - which is where the spike draws it
      # and what a rule attached to a region needs an edge around.
      # Sabotage: leaving `.sb-node--boundary` at `border-color` on the node -
      # the rule above has already taken the node's border and padding away, so
      # an interrupt region draws no box at all and 10c loses the one case it
      # exists for.
      test "a boundary draws the box around its body, in the strong border" do
        css = File.read!(@stylesheet)

        rule = Regex.run(~r/^\.sb-node--boundary > \.sb-node__slots\s*\{(.*?)\n\}/ms, css)

        assert rule, "the scan actually found the rule"

        body = Enum.at(rule, 1)
        assert body =~ ~r/border:\s*var\(--sb-border-width\) solid var\(--sb-border-strong\)/
        assert body =~ ~r/padding:\s*var\(--sb-space\)/
      end
    end

    describe "the summary chip row's stylesheet (ADR-0005 amendment 10r)" do
      # ADR-0005 amendment 10r: the row wraps rather than clipping, because a
      # clipped row hides a lane the slots underneath it still draw.
      # Sabotage: `flex-wrap: nowrap` - a three-lane `core.parallel` loses its
      # last chip off the edge of a fixed-width card, and every test above
      # stays green because the markup is unchanged.
      test "the chip row wraps, in the cell the type label would have used" do
        css = File.read!(@stylesheet)

        row = Regex.run(~r/^\.sb-node__summary\s*\{(.*?)\n\}/ms, css)
        assert row, "the scan actually found the row rule"

        body = Enum.at(row, 1)
        assert body =~ ~r/display:\s*flex/
        assert body =~ ~r/flex-wrap:\s*wrap/

        cell =
          Regex.run(~r/^\.sb-node__chrome > \.sb-node__summary\s*\{(.*?)\n\}/ms, css)

        assert cell, "the scan actually found the placement rule"

        placement = Enum.at(cell, 1)
        assert placement =~ ~r/grid-column:\s*2/
        assert placement =~ ~r/grid-row:\s*2/
      end

      # The 2026-08-28 note on decision 14: config chips carry no accent, so
      # the card's one identity stays the tile and the stripe.
      # Sabotage: `background: var(--sb-block-accent-tint)` on the chip - a
      # third accent-bearing element inside the card, which is the tint that
      # note ratified the deletion of.
      test "a summary chip carries no accent" do
        css = File.read!(@stylesheet)

        rule = Regex.run(~r/^\.sb-node__chip\s*\{(.*?)\n\}/ms, css)

        assert rule, "the scan actually found the chip rule"

        body = Enum.at(rule, 1)
        assert body =~ ~r/color:\s*var\(--sb-fg-subtle\)/
        refute body =~ ~r/--sb-block-accent/
      end
    end

    describe "the fold's stylesheet (ADR-0005's amendment to decision 2)" do
      # The rest state is opacity, not `display: none` and not
      # `visibility: hidden`: both of those take a button out of the tab
      # order, and the fold is the keyboard path into and out of a folded
      # region.
      # Sabotage: `display: none` on the rest rule - the control leaves the
      # tab order and a keyboard can no longer reach a folded container,
      # which is the bug the `x` above already records.
      test "the fold hides by opacity, so it stays focusable" do
        css = File.read!(@stylesheet)

        rest =
          Regex.run(
            ~r/^\.sb-node__fold\[data-reveal="hover-or-selected"\]\s*\{(.*?)\n\}/ms,
            css
          )

        assert rest, "the scan actually found the rest rule"

        body = Enum.at(rest, 1)
        assert body =~ ~r/opacity:\s*0/
        refute body =~ ~r/display:\s*none/
        refute body =~ ~r/visibility:\s*hidden/
      end

      # Hover, `:focus-visible` and selection all reveal it while the
      # container is open - the same three the `x` answers to, so a card's two
      # controls appear together rather than one at a time.
      # Sabotage: dropping the `:focus-visible` selector - a keyboard user
      # tabs onto an invisible control, which is the case the global focus
      # ring cannot rescue on its own.
      test "hover, focus and selection reveal it while the container is open" do
        css = File.read!(@stylesheet)

        assert css =~ ~r/^\.sb-node__chrome:hover > \.sb-node__fold,$/m
        assert css =~ ~r/^\.sb-node__fold:focus-visible,$/m
        assert css =~ ~r/^\.sb-node--selected > \.sb-node__chrome > \.sb-node__fold \{$/m
      end

      # Every collapsed selector is scoped to `.sb-node`. `.sb-palette` has
      # carried a `data-collapsed` of its own since the pane fold shipped, so
      # a bare `[data-collapsed]` rule would reach across to it.
      # Sabotage: writing the collapsed rule as `[data-collapsed="true"]` with
      # no element - the palette picks up a card's geometry and this goes red.
      test "no collapsed rule is written unscoped" do
        css = File.read!(@stylesheet)

        unscoped =
          Regex.scan(~r/^\s*([^\n{]*\[data-collapsed[^\n{]*)\{/m, css)
          |> Enum.map(&Enum.at(&1, 1))
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 =~ ~r/^\.sb-node|^\.sb-palette/))

        assert unscoped == [], """
        Every `data-collapsed` rule names the element it is about. The palette
        and a card both carry the attribute, and an unscoped rule reaches both.

        Unscoped: #{inspect(unscoped)}
        """
      end
    end

    describe "nesting depth banding (sb-d7g, ruling D5)" do
      # The number is ROOT-RELATIVE and it is the recursion's own counter. The
      # trap this pins is `Shell.depth/1`, which is right there, is called
      # "depth", and is a subtree MAXIMUM for the toolbar: reached for here it
      # would stamp one number on every slot of a document and the bands would
      # come out flat while every unit reading "depth" stayed green.
      #
      # Three levels, because two cannot tell "one deeper than my parent" from
      # "not the root": both answer 0/1 for a two-level document.
      #
      # Sabotage: `Slot.child/1` passing `depth={@depth}` instead of
      # `@depth + 1` - the counter stops descending, every slot below the root
      # stamps 0, and this goes red on the second level.
      test "every slot carries its root-relative depth", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn, document: nested_document(), palette: nested_palette())

        assert has_element?(
                 view,
                 ~s(.sb-slot[data-parent-id="blk_depth_root"][data-slot-name="body"][data-sb-depth="0"])
               )

        assert has_element?(
                 view,
                 ~s(.sb-slot[data-parent-id="blk_depth_1"][data-slot-name="body"][data-sb-depth="1"])
               )

        assert has_element?(
                 view,
                 ~s(.sb-slot[data-parent-id="blk_depth_2"][data-slot-name="body"][data-sb-depth="2"])
               )
      end

      # The attribute is the WHOLE markup contract - "no markup beyond the
      # attribute" is the ruling - so a band that arrived as a class or as a
      # wrapper element would be a second spelling of one fact for the next
      # author to keep in sync.
      # Sabotage: adding `"sb-slot--band-#{rem(@depth, 2)}"` to the slot's
      # class list - the editor looks identical and this goes red.
      test "and nothing else: the depth is an attribute, not a class", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn, document: nested_document(), palette: nested_palette())

        refute has_element?(view, ~s([class*="sb-slot--band"]))
        refute has_element?(view, ~s(.sb-slot__band))
      end

      # Both parities, both tokens, and depth 0 left out of both. The last is
      # the load-bearing one: the outermost slot spans nearly the whole canvas,
      # so a band there is the dotted ground painted over.
      # Sabotage: adding `[data-sb-depth="0"]` to the even list - every capture
      # loses the canvas grid and this goes red naming the depth.
      test "the stylesheet bands on the parity, and leaves depth 0 alone" do
        css = File.read!(@stylesheet)

        assert [[_all, odd_list]] =
                 Regex.scan(
                   ~r/\.sb-slot:where\(([^)]*)\)\s*\{\s*background:\s*var\(--sb-band-odd\)/s,
                   css
                 )

        assert [[_all, even_list]] =
                 Regex.scan(
                   ~r/\.sb-slot:where\(([^)]*)\)\s*\{\s*background:\s*var\(--sb-band-even\)/s,
                   css
                 )

        assert odd_list =~ ~s([data-sb-depth="1"])
        assert odd_list =~ ~s([data-sb-depth="3"])
        assert even_list =~ ~s([data-sb-depth="2"])
        assert even_list =~ ~s([data-sb-depth="4"])

        refute odd_list =~ ~s([data-sb-depth="0"])
        refute even_list =~ ~s([data-sb-depth="0"])
      end

      # `:where()` is not decoration: the rail, the drop target and the
      # boundary box all paint their own grounds, and a band written as a bare
      # `.sb-slot[data-sb-depth="1"]` outweighs every one of them. The failure
      # is silent - an interrupt rail at an odd depth quietly stops being
      # tinted - so it is checked here rather than looked at.
      # Sabotage: dropping the `:where(` wrapper from either rule - the
      # selector still bands and this goes red.
      test "the parity selectors keep the specificity of the bare class" do
        css = File.read!(@stylesheet)

        bare =
          ~r/^\.sb-slot\[data-sb-depth=/m
          |> Regex.scan(css)
          |> Enum.map(fn [match] -> match end)

        assert bare == [], "a band at attribute specificity outweighs every ground below it"
      end

      # D5's other half. The region an author reads as the interrupt rules is a
      # place, and a place reads as one when it has a floor - in the warning
      # family the rail's dashed edge already uses, not in a band, because the
      # rail is not a nesting level.
      # Sabotage: deleting `background: var(--sb-warning-bg)` from
      # `.sb-slot--secondary` - the region goes back to the ground of whatever
      # depth it happens to sit at and this goes red.
      test "the interrupt rail has a ground of its own, in the warning family" do
        css = File.read!(@stylesheet)

        assert [[_all, body]] = Regex.scan(~r/\n\.sb-slot--secondary\s*\{([^}]*)\}/, css)

        assert body =~ ~r/background:\s*var\(--sb-warning-bg\)/
        assert body =~ ~r/border-left-color:\s*var\(--sb-edge-interrupt\)/
      end

      # The bands default to surfaces the theme already carries, and that is
      # what makes a host theme that never heard of these two names band
      # correctly. A literal here would band every theme in the package's own
      # light greys, which is the dark-theme failure in its purest form.
      # Sabotage: shipping `--sb-band-odd: #eceef2` - the shipped light theme
      # is unchanged, every dark host gets a pale stripe, and this goes red.
      test "the defaults chain to the surfaces rather than to a literal" do
        css = File.read!(@stylesheet)

        assert css =~ ~r/--sb-band-even:\s*var\(--sb-bg\);/
        assert css =~ ~r/--sb-band-odd:\s*var\(--sb-bg-sunken\);/
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

    # Three levels of nesting and a leaf at the bottom, all of one type: what
    # separates the depth counter from the shape of the document is that the
    # same block type appears at every level, so a rendering that read depth
    # off anything but the recursion has nothing else to read.
    defp nested_document do
      Document.new(
        Block.new("core.sequence",
          id: "blk_depth_root",
          slots: %{
            "body" => [
              Block.new("core.sequence",
                id: "blk_depth_1",
                slots: %{
                  "body" => [
                    Block.new("core.sequence",
                      id: "blk_depth_2",
                      slots: %{"body" => [EditorFixtures.wait("blk_depth_leaf", "1h")]}
                    )
                  ]
                }
              )
            ]
          }
        ),
        id: "doc_depth"
      )
    end

    defp nested_palette do
      Palette.new(%{
        "core.sequence" => StatifierBlocks.Core.Sequence,
        "core.wait" => StatifierBlocks.Core.Wait
      })
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
