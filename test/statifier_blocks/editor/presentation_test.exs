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

      # Sabotage: dropping the `:if={ViewModel.subtitle(@node)}` guard - every
      # card in the core vocabulary prints its type on both of its two lines.
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
