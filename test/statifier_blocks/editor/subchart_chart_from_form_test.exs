# ADR-0005 decision 1: with `phoenix_live_view` absent the editor does not
# compile, so neither can a test that drives it. The schema and sentence
# halves are pure and live in `StatifierBlocks.Core.SubchartChartFromTest`.
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.SubchartChartFromFormTest do
    @moduledoc """
    The config form of a `core.subchart`, which names its child by `chart`
    or by `chart_from` (ADR-0004's Amendment of 2026-11-19, J1): the form
    offers both keys, a post naming the child either way reaches the
    document, a post naming both is refused with the one finding on
    `chart_from`, and the block's line reads the path.
    """

    use StatifierBlocks.EditorLiveCase

    defp onboarding_document(config) do
      Document.new(
        Block.new("core.sequence",
          id: "blk_onboarding",
          slots: %{"body" => [Block.new("core.subchart", id: "blk_setup", config: config)]}
        ),
        id: "doc_branch_onboarding"
      )
    end

    defp setup_view(conn, config) do
      {:ok, view, _html} = mount_editor(conn, document: onboarding_document(config))

      view
      |> element(~s([data-block-id="blk_setup"] > .sb-node__chrome > .sb-node__label))
      |> render_click()

      view
    end

    defp post_config(view, config) do
      view
      |> form(~s(form[phx-change="config-change"]), %{"config" => config})
      |> render_submit()
    end

    defp setup_block(document),
      do: document |> Document.blocks() |> Enum.find(&(&1.id == "blk_setup"))

    describe "the form offers both keys" do
      # Sabotage: dropped the chart_from declaration from `config_schema/1`
      # -> no chart_from input renders and this goes red.
      test "chart and chart_from render as inputs, chart_from after chart", %{conn: conn} do
        html = conn |> setup_view(%{"chart" => "bdoc_CATALOGUE_SYNC"}) |> render()

        assert html =~ ~s(name="config[chart]")
        assert html =~ ~s(name="config[chart_from]")

        [before_chart_from, _after] = String.split(html, ~s(name="config[chart_from]"), parts: 2)
        assert before_chart_from =~ ~s(name="config[chart]")
        assert html =~ "Or run the chart whose id is at"
      end
    end

    describe "a post naming the child one way reaches the document" do
      test "a path in chart_from, with chart empty, is applied", %{conn: conn} do
        view = setup_view(conn, %{"chart" => "", "chart_from" => ""})

        post_config(view, %{"chart" => "", "chart_from" => "onboarding.setup_document"})

        assert_receive {:document, document}

        assert %Block{config: %{"chart_from" => "onboarding.setup_document"} = config} =
                 setup_block(document)

        assert Map.get(config, "chart", "") == ""
      end

      test "a block that names a chart switches to chart_from in one post", %{conn: conn} do
        view = setup_view(conn, %{"chart" => "bdoc_CATALOGUE_SYNC"})

        post_config(view, %{"chart" => "", "chart_from" => "onboarding.setup_document"})

        assert_receive {:document, document}

        assert %Block{config: %{"chart_from" => "onboarding.setup_document"} = config} =
                 setup_block(document)

        assert Map.get(config, "chart", "") == ""
      end
    end

    describe "a post naming the child both ways is refused" do
      # Sabotage: let `validate_config/1` accept both keys -> the document
      # takes the post and this goes red.
      test "the document is unchanged and the finding renders on the form", %{conn: conn} do
        view = setup_view(conn, %{"chart" => "bdoc_CATALOGUE_SYNC"})

        html =
          post_config(view, %{"chart" => "bdoc_CATALOGUE_SYNC", "chart_from" => "onboarding.next"})

        refute_receive {:document, _document}
        assert html =~ "names the document by chart or by chart_from, never both; clear one"
      end
    end

    describe "the block's line" do
      # Sabotage: had `sentence/1` read chart only -> the description reads
      # "Run a chart and wait" and this goes red.
      test "the selected block is described by its sentence", %{conn: conn} do
        html =
          conn
          |> setup_view(%{"chart_from" => "onboarding.setup_document"})
          |> element(~s([data-editor-description="true"]))
          |> render()

        assert html =~ "Run the chart named at onboarding.setup_document and wait"
      end
    end
  end
end
