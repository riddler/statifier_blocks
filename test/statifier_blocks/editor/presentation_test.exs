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
