# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes these from a headless *run*; this
# guard is what keeps them out of a headless *compile*, which is the earlier
# of the two problems. The pure half of the profile - which tabs a list
# leaves, and what happens to an id the package cannot resolve - is in
# `StatifierBlocks.ProfilesTest`, deliberately outside this guard.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.ProfileTest do
    @moduledoc """
    The `profile` assign at the mount (ADR-0005's 2026-09-07 amendment).

    Four claims only exist once there is markup and a socket. A profile naming
    one drawer tab draws one strip button. An id the package cannot resolve
    draws nothing and raises nothing, so the mount still renders. A read-only
    mount draws no form control and no palette column and refuses no document.
    And `on_change` never fires on one, however the gesture arrives.

    The fifth is the one the amendment is built around: **a host that passes
    no profile gets the editor it had before the assign existed.** It is
    asserted here as byte identity over every fixture document - the unprofiled
    render against the render of a mount naming `%{}` and of one naming the
    default map, which are the two ways a host reaches the default by
    accident. The rest of the suite is the other half of that oracle: every
    render assertion in it was written against the unprofiled editor and none
    of them was touched.
    """

    use StatifierBlocks.EditorLiveCase

    @default %{
      drawer_tabs: :all,
      inspector_tabs: :all,
      palette_groups: :all,
      toolbar: :all,
      read_only?: false
    }

    defp editor(view), do: view |> element("#editor") |> render()

    defp select(view, id) do
      view
      |> element(~s([data-block-id="#{id}"] > .sb-node__chrome > .sb-node__label))
      |> render_click()

      view
    end

    defp open_drawer(view) do
      view |> element("button.sb-drawer__strip") |> render_click()
      view
    end

    # A gesture with no control left to send it: routed to the component the
    # way a crafted payload reaches it, which is the only way these arrive at
    # a read-only mount.
    defp crafted(view, event, params \\ %{}) do
      view |> with_target("#editor") |> render_click(event, params)
      view
    end

    defp fixtures do
      [
        {"signup_wizard", EditorFixtures.signup_wizard()},
        {"credit_card", EditorFixtures.credit_card()},
        {"invoke_step", EditorFixtures.invoke_step()}
      ]
    end

    describe "the default profile" do
      # Sabotage: `normalize_profile/1` defaulting a missing key to `[]` rather
      # than `:all` - the one shape of the default that would silently remove
      # a surface a host never named. Ran red on every fixture.
      test "renders byte-identically to the unprofiled editor, for every fixture", %{conn: conn} do
        for {name, document} <- fixtures() do
          {:ok, plain, _html} = mount_editor(conn, document: document)
          {:ok, empty, _html} = mount_editor(conn, document: document, profile: %{})
          {:ok, full, _html} = mount_editor(conn, document: document, profile: @default)

          assert editor(empty) == editor(plain), "#{name} moved under an empty profile"
          assert editor(full) == editor(plain), "#{name} moved under the default profile"
        end
      end

      test "a profile naming one key leaves every other surface alone", %{conn: conn} do
        {:ok, plain, _html} = mount_editor(conn)
        {:ok, view, _html} = mount_editor(conn, profile: %{read_only?: false})

        assert editor(view) == editor(plain)
      end
    end

    describe "a profile that names tabs" do
      # Sabotage: `Shell.drawer_tabs/1`'s list clause answering `@drawer_tabs`
      # unfiltered. Ran red here and across `StatifierBlocks.ProfilesTest`.
      test "a drawer list naming one tab draws one", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, profile: %{drawer_tabs: [:findings]})

        open_drawer(view)
        html = render(view)

        assert html =~ ~s(id="sb-drawer-tab-findings")
        refute html =~ ~s(id="sb-drawer-tab-tables")
        refute html =~ ~s(id="sb-drawer-tab-source")
      end

      test "an inspector list naming one tab draws one", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, profile: %{inspector_tabs: [:findings]})

        html = render(view)

        assert html =~ ~s(id="sb-inspector-tab-findings")
        refute html =~ ~s(id="sb-inspector-tab-config")
        refute html =~ ~s(id="sb-inspector-tab-condition")
      end

      test "the inspector opens on a tab the profile left, not on Config", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn, profile: %{inspector_tabs: [:findings, :fixtures]})

        assert render(view) =~ ~s(id="sb-inspector-panel-findings")
      end

      test "a toolbar list drops the groups it does not name", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, profile: %{toolbar: [:zoom]})

        html = render(view)

        assert html =~ "sb-toolbar__zoom"
        refute html =~ ~s(phx-click="undo")
        refute html =~ ~s(phx-click="fit")
        refute html =~ "sb-toolbar__metrics"
      end

      test "the Canvas heading and the nested tree chip are not addressable", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, profile: %{toolbar: []})

        html = render(view)

        assert html =~ "sb-toolbar__title"
        assert html =~ "nested tree"
      end

      test "a palette group list draws only the groups it names", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, profile: %{palette_groups: []})

        html = render(view)

        assert html =~ "sb-palette"
        refute html =~ ~s(sb-palette__group")
      end

      # sabotage: drop the `order_palette_groups/2` call from
      # `Editor.palette_groups/2` - the columns draw "Authorization" first,
      # because the view model's own order is alphabetical.
      test "a palette group list is a reading order as well as a set", %{conn: conn} do
        palette =
          StatifierBlocks.Palette.new(
            Map.merge(
              StatifierBlocks.Palette.core_types(),
              StatifierBlocks.BlockTypeFixtures.raw_palette()
            )
          )

        {:ok, view, _html} =
          mount_editor(conn,
            palette: palette,
            profile: %{palette_groups: ["Structure", "Authorization"]}
          )

        drawn =
          view
          |> render()
          |> then(&Regex.scan(~r/data-group="([^"]+)"/, &1))
          |> Enum.map(&List.last/1)

        # "Other" is a group this palette carries and the list does not name:
        # the profile's drop rule still runs, and it runs before the order.
        assert drawn == ["Structure", "Authorization"]
      end
    end

    describe "an id the profile names that the package does not know" do
      test "renders nothing and raises nothing", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn,
            profile: %{
              drawer_tabs: [:findings, :nope],
              inspector_tabs: [:findings, :nope],
              toolbar: [:zoom, :nope],
              palette_groups: ["Structure", "no such group"]
            }
          )

        open_drawer(view)
        html = render(view)

        assert html =~ ~s(id="sb-drawer-tab-findings")
        assert html =~ ~s(id="sb-inspector-tab-findings")
        refute html =~ "sb-drawer-tab-nope"
        refute html =~ "no such group"
      end

      test "a malformed value drops to that key's default", %{conn: conn} do
        {:ok, plain, _html} = mount_editor(conn)
        {:ok, view, _html} = mount_editor(conn, profile: %{drawer_tabs: :nonsense})

        assert editor(view) == editor(plain)
      end

      test "a profile that is not a map at all drops to the default", %{conn: conn} do
        {:ok, plain, _html} = mount_editor(conn)
        {:ok, view, _html} = mount_editor(conn, profile: :operations)

        assert editor(view) == editor(plain)
      end
    end

    describe "read_only?" do
      # Sabotage: `toolbar_items/1`'s `toolbar: :all` clause answering `:all`
      # instead of the three reading groups - the record's own read-only worked
      # mount names no `toolbar`, so it is that clause and not the list one
      # that decides whether a reviewer is offered Undo. Ran red on the Undo
      # and Redo assertions; the list clause is covered by the test below,
      # which alone left this one alive.
      test "renders no palette column, no drag hook and no history", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, profile: %{read_only?: true})

        html = render(view)

        refute html =~ "sb-palette"
        refute html =~ "StatifierBlocksDrag"
        refute html =~ ~s(phx-click="undo")
        refute html =~ ~s(phx-click="redo")
        assert html =~ "StatifierBlocksMeasure"
      end

      # sb-ako9 (RQ-SF038-8). `palette-open` was already on
      # `@read_only_refused`, so the click was inert - but the comment beside
      # that list says a read-only mount draws no control that could have sent
      # one of these, and forty-one "+" buttons were exactly such controls.
      #
      # Sabotage: `:if={not @read_only}` removed from the gap's button in
      # `Slot.gap/1`. Ran red on the refute below and on nothing else in the
      # suite, which is what says this pair is the only cover for the clause.
      test "draws no gap \"+\" on the canvas", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, profile: %{read_only?: true})

        html = render(view)

        refute html =~ "sb-gap__add"
        refute html =~ ~s(phx-click="palette-open")
        assert html =~ "sb-gap"
      end

      test "an editing mount still draws the gap \"+\"", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, profile: %{read_only?: false})

        html = render(view)

        assert html =~ "sb-gap__add"
        assert html =~ ~s(phx-click="palette-open")
      end

      test "hides Undo and Redo whatever the toolbar list says", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn, profile: %{read_only?: true, toolbar: [:history, :zoom]})

        html = render(view)

        refute html =~ ~s(phx-click="undo")
        refute html =~ ~s(phx-click="redo")
        assert html =~ "sb-toolbar__zoom"
      end

      test "draws each config field as a value and no form control", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, profile: %{read_only?: true})

        select(view, "blk_email_step")
        html = render(view)

        assert html =~ "sb-form--readonly"
        assert html =~ "sb-field__value"
        refute html =~ ~s(phx-change="config-change")
        refute html =~ "sb-field__input"
      end

      test "keeps the selection seam and the findings", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, profile: %{read_only?: true})

        select(view, "blk_email_step")

        assert [%{id: "blk_email_step"}] = selections()
        assert render(view) =~ ~s(id="sb-inspector-tab-findings")
      end

      test "refuses no document", %{conn: conn} do
        for {name, document} <- fixtures() do
          assert {:ok, view, _html} =
                   mount_editor(conn, document: document, profile: %{read_only?: true}),
                 "#{name} was refused"

          assert render(view) =~ "sb-editor"
        end
      end

      test "draws the declarations panel as values, with no Add control", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn,
            document: EditorFixtures.credit_card(),
            profile: %{read_only?: true}
          )

        open_drawer(view)
        view |> element("#sb-drawer-tab-declarations") |> render_click()
        html = render(view)

        refute html =~ ~s(phx-click="declaration-add")
        refute html =~ ~s(phx-change="declaration-change")
      end

      test "on_change never fires, whatever the gesture", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, profile: %{read_only?: true})

        select(view, "blk_email_step")
        crafted(view, "remove", %{"block-id" => "blk_email_step"})
        crafted(view, "undo")
        crafted(view, "declaration-add")
        crafted(view, "config-change", %{"block-id" => "blk_email_step", "duration" => "9h"})

        assert latest_document() == nil
      end

      test "a refused gesture leaves the document where it was", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, profile: %{read_only?: true})
        before = editor(view)

        crafted(view, "remove", %{"block-id" => "blk_email_step"})

        assert editor(view) == before
      end
    end
  end
end
