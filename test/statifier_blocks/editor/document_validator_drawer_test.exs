# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes this from a headless *run*; this
# guard is what keeps it out of a headless *compile*.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.DocumentValidatorDrawerTest do
    @moduledoc """
    ADR-0005 clauses `11p` to `11t`, the half that only exists once there is
    markup: a host's whole-document rule reaches the drawer's Findings tab
    through the routes decision 11 already has, and the row says which rule
    is speaking.

    Nothing in the drawer was taught about validators. That is the assertion
    rather than an aside - a fourth producer on an existing source, through
    existing anchors, onto existing routes, is what the amendment claims the
    findings layer can take, and a rendering test is the only place that
    claim is actually checked.

    The contract itself - the source stamp, the default severity, the
    normalizer - is `StatifierBlocks.ViewModel.DocumentValidatorTest`'s, and
    it runs with LiveView off the path.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.{Document, Palette}

    defmodule TrackingNeedsAnEmail do
      @moduledoc "A rule about the whole document, in the host's vocabulary."

      @behaviour StatifierBlocks.DocumentValidator

      @impl true
      def validate_document(%Document{} = document) do
        [
          {{:block, document.root.id}, "a tracking step needs an email step before it",
           severity: :info}
        ]
      end
    end

    defp palette_with_rule do
      Palette.new(Palette.core_types(),
        recipes: Palette.core_recipes(),
        validators: [TrackingNeedsAnEmail]
      )
    end

    # The two clicks an author makes to reach the list, as
    # `StatifierBlocks.Editor.FindingsTest` makes them.
    defp open_findings(view) do
      view |> element(".sb-drawer__strip") |> render_click()
      view |> element(~s(.sb-drawer__tab[phx-value-tab="findings"])) |> render_click()
    end

    # Sabotage: `ViewModel.validator_findings/2` returning `[]` - the row is
    # never built and every assertion here goes red.
    test "a host rule's finding is a row in the drawer, saying which rule speaks",
         %{conn: conn} do
      {:ok, view, _html} = mount_editor(conn, palette: palette_with_rule())
      open_findings(view)

      row = ~s(li[data-anchor="block:blk_wizard"][data-source="lint"])

      assert has_element?(view, "#{row} .sb-findings__source", "lint")
      assert has_element?(view, "#{row} .sb-findings__severity", "info")

      assert has_element?(
               view,
               "#{row} .sb-findings__message",
               "a tracking step needs an email step before it"
             )
    end

    # `Shell.findings_count/1` is the one number this package means by "the
    # document's findings", so a host rule has to move it.
    #
    # Sabotage: `derived_findings/3` dropping `document_rule_findings/2` - the
    # count stays at the resolution finding alone and this goes red.
    test "and it is counted with everything else the document has", %{conn: conn} do
      {:ok, plain, _html} = mount_editor(conn)
      {:ok, ruled, _html} = mount_editor(conn, palette: palette_with_rule())

      assert open_findings(plain) =~ ~s(data-findings-count="1")
      assert open_findings(ruled) =~ ~s(data-findings-count="2")
    end
  end
end
