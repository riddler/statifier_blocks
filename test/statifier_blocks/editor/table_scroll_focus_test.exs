# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.TableScrollFocusTest do
    @moduledoc """
    The truth table's scroll region: a focusable, labelled region.

    A table with more arms than the drawer is wide scrolls horizontally, and
    every cell in it is text - so before this the columns past the right edge
    were reachable with a pointer and with nothing else. The scroller carries
    `tabindex="0"` to put those columns on the keyboard's side of the line,
    and `role="region"` with the table's own name so the stop it adds
    announces as that table rather than as an unnamed group.

    The name is asserted to be the table's, not merely present: two tables in
    one panel are two stops, and two stops both announcing "region" is the
    same defect the label exists to fix.

    What is deliberately not asserted here: that arrow keys actually scroll
    the region. That is the browser's native behaviour for a focused scroll
    container - this package ships no key handler and the change that added
    the attribute was constrained to add none - so the assertion a test can
    make is that the attribute is on the element the browser needs it on. The
    scrolling itself was measured in a browser and recorded on the bead.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.Predicates.TruthTable

    @block_id "blk_BR"

    defp document do
      root =
        Block.new("core.branch",
          id: @block_id,
          config: %{"arms" => [%{"slot" => "arm_a", "cond" => "amount > 100"}]},
          slots: %{"arm_a" => [Block.new("core.sequence", id: "blk_A")]}
        )

      Document.new(root, id: "bdoc_FOCUS")
    end

    defp table(name) do
      {:ok, table} =
        TruthTable.build(
          %{name: name, columns: [%{key: "arm_a", source: "amount > 100"}]},
          [%{name: "over", bindings: %{"amount" => "500"}, expected: %{"arm_a" => true}}]
        )

      table
    end

    # Opens the drawer and lands on the block's tables tab, which is where the
    # index page's jump goes with nothing selected.
    defp open_tables(conn, tables) do
      {:ok, view, _html} =
        mount_editor(conn,
          document: document(),
          palette: Palette.core(),
          fixtures: %{@block_id => tables}
        )

      view |> element(".sb-drawer__strip") |> render_click()
      view |> element(~s(.sb-drawer__jump[phx-value-block-id="#{@block_id}"])) |> render_click()

      view
    end

    # Every scroll region in the rendered drawer, as the attributes that make
    # it a stop, in document order. Read off the whole panel rather than
    # through per-selector assertions, because the claim is about what each
    # region carries relative to the table it wraps - which one selector
    # cannot say. The pattern spans a single tag: these are attributes of one
    # `div` in the template, so `[^>]*` cannot cross into the next element.
    defp scroll_regions(html) do
      ~r/class="sb-table__scroll"([^>]*)>/
      |> Regex.scan(html, capture: :all_but_first)
      |> Enum.map(fn [attrs] ->
        %{
          tabindex: attribute(attrs, "tabindex"),
          role: attribute(attrs, "role"),
          label: attribute(attrs, "aria-label")
        }
      end)
    end

    defp attribute(attrs, name) do
      case Regex.run(~r/\s#{name}="([^"]*)"/, attrs, capture: :all_but_first) do
        [value] -> value
        nil -> nil
      end
    end

    describe "a truth table's scroll region" do
      # Sabotage: dropped `tabindex="0"` from the scroller in `drawer.ex` -
      # the attribute came back `nil` and the tab-stop assertion went red
      # while the role and label ones stayed green, which is the split the
      # keyboard defect actually had. Reverted.
      test "is a Tab stop", %{conn: conn} do
        regions = conn |> open_tables([table("arms")]) |> render() |> scroll_regions()

        assert [%{tabindex: "0"}] = regions
      end

      # Sabotage: replaced `aria-label={@table.name}` with a literal
      # `aria-label="Truth table"` - both regions came back with the same
      # name and the distinctness assertion went red. Reverted.
      test "announces as a region named for its own table", %{conn: conn} do
        regions =
          conn |> open_tables([table("arms"), table("guards")]) |> render() |> scroll_regions()

        assert [%{role: "region", label: "arms"}, %{role: "region", label: "guards"}] = regions
      end
    end
  end
end
