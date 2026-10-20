# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The `:liveview` tag on
# `StatifierBlocks.EditorLiveCase` excludes this from a headless *run*; this
# guard is what keeps it out of a headless *compile*. The pure half - the
# normalizer the host's return value is read through - is
# `StatifierBlocks.ViewModel.AdvisoryFindingsTest`, outside this guard.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.HostAdvisoriesTest do
    @moduledoc """
    The editor's `advisories` assign (ADR-0005's Amendment of 2026-10-19),
    and its first use: ADR-0013 decision 4's agreement check between a
    `core.map`'s `collect_type` and the child chart it names, asked where
    both documents are in hand.

    The parent is a library's overdue round: a `core.map` that runs the
    overdue-notice chart once per overdue loan and collects each answer as a
    `library.notice_result`, a declaration of kind `shape`. The child's root
    is a host type whose `donedata_type/1` declares what the notice chart
    answers. The host holds both documents, so the host builds the function:
    `agreement_advisories/4` below is that host's code, written with nothing
    but the package's public functions.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.BlockType

    defmodule NoticeRoot do
      @moduledoc """
      `library.overdue_notice`: the root of the child chart that sends one
      patron an overdue notice and answers whether it went out, and the fine
      it assessed when the config says it reports one.
      """

      use StatifierBlocks.BlockType

      @impl true
      def emit(_block, _context), do: {:error, :not_compiled_here}

      @impl true
      def donedata_type(config) do
        notified = [%{name: "notified", path: "notice.sent", type: :boolean}]

        if Map.get(config, "reports_fine", false),
          do: notified ++ [%{name: "fine_cents", path: "notice.fine", type: :integer}],
          else: notified
      end
    end

    @chart "bdoc_OVERDUE_NOTICE"
    @anchor ~s(config:blk_notices:collect_type)

    @datamodel %{
      "types" => [
        %{
          "name" => "library.notice_result",
          "kind" => "shape",
          "label" => "Notice result",
          "fields" => [
            %{"name" => "notified", "type" => "boolean", "required?" => true},
            %{"name" => "fine_cents", "type" => "integer", "required?" => true}
          ]
        }
      ]
    }

    defp palette do
      Palette.new(Map.put(Palette.core_types(), "library.overdue_notice", NoticeRoot),
        recipes: Palette.core_recipes()
      )
    end

    defp round_document(collect_type \\ "library.notice_result") do
      Document.new(
        Block.new("core.group",
          id: "blk_round",
          slots: %{
            "body" => [
              Block.new("core.map",
                id: "blk_notices",
                config: %{
                  "items" => "loans.overdue",
                  "chart" => @chart,
                  "item_as" => "loan",
                  "collect" => "notices",
                  "collect_type" => collect_type
                }
              )
            ]
          }
        ),
        id: "doc_overdue_round"
      )
    end

    defp notice_document(config) do
      Document.new(Block.new("library.overdue_notice", id: "blk_notice", config: config),
        id: @chart
      )
    end

    # A child that answers both members the parent's shape requires, and one
    # that answers only whether the notice went out.
    defp agreeing_child, do: %{@chart => notice_document(%{"reports_fine" => true})}
    defp disagreeing_child, do: %{@chart => notice_document(%{})}

    @doc """
    The host's function, as a host writes it: for every `core.map` whose
    child the host holds, ask `BlockType.agrees?/3` and turn a disagreement
    into one advisory on `collect_type`. A `collect_type` naming a declaration
    of kind `record` is declined, as ADR-0013 decision 4 declines it.
    """
    def agreement_advisories(document, palette, datamodel, children) do
      declarations = StatifierDatamodel.Declarations.from_document(datamodel)

      document
      |> Document.blocks()
      |> Enum.filter(&(&1.type == "core.map"))
      |> Enum.flat_map(&pair_advisories(&1, palette, declarations, children))
    end

    defp pair_advisories(%Block{id: id, config: config}, palette, declarations, children) do
      expected = Map.get(config, "collect_type")

      with %Document{root: root} <- Map.get(children, Map.get(config, "chart")),
           true <- shape?(declarations, expected),
           {:ok, module, resolved} <- Palette.resolve(palette, root) do
        fields = BlockType.donedata_type(module, resolved.config)

        case BlockType.agrees?(declarations, fields, expected) do
          {:missing, names} ->
            [
              {{:config, id, "collect_type"},
               "#{config["chart"]} does not answer #{Enum.join(names, ", ")}"}
            ]

          :not_assignable ->
            [{{:config, id, "collect_type"}, "#{config["chart"]}'s answer is not a #{expected}"}]

          _agrees_or_unknown ->
            []
        end
      else
        _no_pair_to_check -> []
      end
    end

    defp shape?(_declarations, members) when is_list(members), do: true

    defp shape?(declarations, name) do
      match?({:ok, %{kind: :shape}}, StatifierDatamodel.Declarations.fetch(declarations, name))
    end

    defp mount_round(conn, opts) do
      document = Keyword.get(opts, :document, round_document())

      advisories =
        case Keyword.fetch(opts, :children) do
          {:ok, children} ->
            [advisories: {__MODULE__, :agreement_advisories, [palette(), @datamodel, children]}]

          :error ->
            []
        end

      {:ok, view, _html} =
        mount_editor(conn, [document: document, palette: palette()] ++ advisories)

      view
    end

    # The two clicks an author makes to reach the list, as
    # `StatifierBlocks.Editor.DocumentValidatorDrawerTest` makes them. The
    # strip is drawn only while the drawer is shut, so a test that reads the
    # list twice opens the drawer once.
    defp open_findings(view) do
      if has_element?(view, ".sb-drawer__strip") do
        view |> element(".sb-drawer__strip") |> render_click()
      end

      view |> element(~s(.sb-drawer__tab[phx-value-tab="findings"])) |> render_click()
    end

    # Every row in the drawer's Findings list anchored on the map's
    # `collect_type`, whatever its source or severity, as `{source, severity}`.
    defp collect_type_rows(view) do
      open_findings(view)

      view
      |> element(".sb-findings__list")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(~s(li[data-anchor="#{@anchor}"]))
      |> Enum.map(fn row ->
        {LazyHTML.attribute(row, "data-source"), LazyHTML.attribute(row, "data-severity")}
      end)
    end

    describe "the acceptance: both documents loaded" do
      # sabotage: dropped `host_advisories` from the editor's `view_model/7`
      # concatenation - the host's function runs and its answer reaches no
      # finding, so the row list is empty and this goes red (verified)
      test "a disagreeing pair raises exactly one :warning advisory on collect_type",
           %{conn: conn} do
        view = mount_round(conn, children: disagreeing_child())

        assert collect_type_rows(view) == [{["lint"], ["warning"]}]

        assert has_element?(
                 view,
                 ~s(li[data-anchor="#{@anchor}"] .sb-findings__message),
                 "#{@chart} does not answer fine_cents"
               )
      end

      # The seam adds nothing the host did not say.
      #
      # sabotage: had `ViewModel.advisory_findings/2` add one advisory on
      # every block's `collect_type` beside the host's own - a row appears
      # for an agreeing pair and this goes red (verified)
      test "an agreeing pair raises none", %{conn: conn} do
        view = mount_round(conn, children: agreeing_child())

        assert collect_type_rows(view) == []
      end
    end

    describe "with no advisories assigned" do
      # The opt-in half: a host that passes nothing sees nothing new. The
      # disagreeing pair is still disagreeing - nothing asks.
      #
      # sabotage: made the catch-all clause of `ViewModel.advisory_findings/2`
      # answer a finding of its own on the root - the drawer's number moves
      # and this goes red (verified)
      test "the editor draws exactly what it drew before the assign existed", %{conn: conn} do
        plain = mount_round(conn, [])
        agreeing = mount_round(conn, children: agreeing_child())

        assert collect_type_rows(plain) == []

        [plain_count] =
          Regex.run(~r/data-findings-count="(\d+)"/, open_findings(plain),
            capture: :all_but_first
          )

        [agreeing_count] =
          Regex.run(~r/data-findings-count="(\d+)"/, open_findings(agreeing),
            capture: :all_but_first
          )

        assert plain_count == agreeing_count
      end
    end

    describe "it is called with the document as it stands" do
      # The function runs on every rebuild, so an author's edit is asked
      # about without the host doing anything: pointing an agreeing map at a
      # child chart that answers less raises the advisory on the next render.
      #
      # sabotage: had `rebuild/1` pass `nil` in place of the `advisories`
      # assign whenever the history is not empty - the mount is asked, the
      # edit is not, no row appears and this goes red (verified)
      test "an author's edit is asked about on the next render", %{conn: conn} do
        children =
          Map.merge(agreeing_child(), %{"bdoc_SHORT_NOTICE" => disagreeing_child()[@chart]})

        view = mount_round(conn, children: children)
        assert collect_type_rows(view) == []

        view
        |> element(~s([data-block-id="blk_notices"] > .sb-node__chrome > .sb-node__label))
        |> render_click()

        view
        |> form(~s(form[phx-change="config-change"]), %{
          "config" => %{"chart" => "bdoc_SHORT_NOTICE"}
        })
        |> render_change()

        assert %Document{} = latest_document()
        assert collect_type_rows(view) == [{["lint"], ["warning"]}]

        assert has_element?(
                 view,
                 ~s(li[data-anchor="#{@anchor}"] .sb-findings__message),
                 "bdoc_SHORT_NOTICE does not answer fine_cents"
               )
      end
    end

    describe "the number a host may show" do
      # sabotage: dropped `:advisories` from `findings_count/3`'s option reads
      # (passing `nil` unconditionally) - the host's number stays one short of
      # the drawer's and this goes red (verified)
      test "findings_count/3 counts the advisory the drawer shows", %{conn: conn} do
        document = round_document()
        host = &agreement_advisories(&1, palette(), @datamodel, disagreeing_child())

        without = StatifierBlocks.Editor.findings_count(document, palette())

        with_advisory =
          StatifierBlocks.Editor.findings_count(document, palette(), advisories: host)

        assert with_advisory == without + 1

        view = mount_round(conn, children: disagreeing_child())

        assert open_findings(view) =~ ~s(data-findings-count="#{with_advisory}")
      end
    end
  end
end
