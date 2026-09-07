# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes this from a headless *run*; this
# guard is what keeps it out of a headless *compile*.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.HostValidatorRefreshTest do
    @moduledoc """
    The claim `docs/host-validators.md` makes about the lifetime of a host's
    advisory finding: it is not delivered once at mount, it is re-derived on
    every build, so it is still there after the author edits the document.

    That is a property of where validators run rather than of anything the
    editor was taught. `ViewModel.build/3` runs the palette's validators, the
    editor's `rebuild/1` calls `view_model/6` again on every gesture that
    changes anything, and the palette it passes is the assign the host handed
    in. Nothing caches a finding and nothing has to re-register a rule.

    The recipe is only worth writing down if that holds, so it is checked here
    before it is claimed there.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.{Document, Palette}

    defmodule RecordCoverage do
      @moduledoc """
      `docs/host-validators.md`'s rule, as the guide prints it: the `card`
      record was redefined and `risk_band` is no longer a member, so a config
      value still reading it reads a path the datamodel no longer covers.
      """

      @behaviour StatifierBlocks.DocumentValidator

      @dropped ~w(risk_band)

      @impl true
      def validate_document(%Document{} = document) do
        document |> Document.blocks() |> Enum.flat_map(&block_findings/1)
      end

      defp block_findings(block) do
        for {key, value} <- block.config, member <- @dropped, reads?(value, member) do
          {{:config, block.id, key},
           "`card.#{member}` is no longer a member of the `card` record", severity: :warning}
        end
      end

      defp reads?(value, member) when is_binary(value), do: String.contains?(value, member)
      defp reads?(value, member) when is_list(value), do: Enum.any?(value, &reads?(&1, member))

      defp reads?(value, member) when is_map(value),
        do: value |> Map.values() |> Enum.any?(&reads?(&1, member))

      defp reads?(_value, _member), do: false
    end

    @anchor ~s(li[data-anchor="config:blk_cc_decision:arms"][data-source="lint"])

    defp palette_with_rule do
      Palette.new(Palette.core_types(),
        recipes: Palette.core_recipes(),
        validators: [RecordCoverage]
      )
    end

    defp open_findings(view) do
      view |> element(".sb-drawer__strip") |> render_click()
      view |> element(~s(.sb-drawer__tab[phx-value-tab="findings"])) |> render_click()
    end

    # Sabotage: caching `validator_findings/2`'s result on mount instead of
    # re-running it in `derived_findings/3` - the row survives the first
    # assertion and the one after the edit goes red.
    test "a host rule's finding survives the editor's own refresh", %{conn: conn} do
      {:ok, view, _html} =
        mount_editor(conn, document: EditorFixtures.credit_card(), palette: palette_with_rule())

      open_findings(view)

      assert has_element?(view, "#{@anchor} .sb-findings__severity", "warning")

      # An edit, not a re-render: the author changes a pause the rule says
      # nothing about, which is the gesture that rebuilds the view model from
      # a document the mount never saw.
      view
      |> element(~s([phx-click="select"][phx-value-block-id="blk_cc_capture_pause"]))
      |> render_click()

      view
      |> form(~s(form[phx-change="config-change"]), %{"config" => %{"duration" => "9m"}})
      |> render_submit()

      assert_receive {:document, document}

      assert %{"duration" => "9m"} =
               document
               |> Document.blocks()
               |> Enum.find(&(&1.id == "blk_cc_capture_pause"))
               |> Map.fetch!(:config)

      assert has_element?(view, "#{@anchor} .sb-findings__severity", "warning")

      # And it is re-derived rather than remembered: delete the block the rule
      # objected to and the row goes with it, without anything deregistering
      # the rule.
      view
      |> element(~s(.sb-node__remove[phx-value-block-id="blk_cc_decision"]))
      |> render_click()

      refute has_element?(view, @anchor)
    end
  end
end
