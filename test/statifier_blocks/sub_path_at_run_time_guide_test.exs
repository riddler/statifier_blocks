defmodule StatifierBlocks.SubPathAtRunTimeGuideTest do
  @moduledoc """
  The document and the resolver `docs/guides/choose-a-sub-path-at-run-time.md`
  walks through, compiled and run on the current release.

  The page quotes its document byte for byte from a fixture and its
  resolver's clauses verbatim, and every compiled line and handler answer
  it states is asserted here, so the guide and the package cannot drift
  apart silently.

  A pure test. Nothing here names LiveView, so it compiles and runs headless.
  `async: false` because the live run below starts a `Statifier.Session`
  under the shared supervisor the other session tests use.
  """

  use ExUnit.Case, async: false

  alias Statifier.Session
  alias Statifier.Testing.HandlerCase
  alias StatifierBlocks.{Compiled, Compiler, Document, Palette, ViewModel}
  alias StatifierBlocks.Core.Subchart, as: SubchartBlock
  alias StatifierBlocks.Runtime.Subchart

  @page "docs/guides/choose-a-sub-path-at-run-time.md"
  @fixture "test/fixtures/documents/sub_path_at_run_time/branch_onboarding.json"

  @type_string SubchartBlock.invoke_type()

  # The page's resolver, its two resolve_chart/2 clauses as the page prints
  # them; the store it calls is this test's.
  @allow_list """
    @setups ["doc_catalogue_sync", "doc_reading_list_import", "doc_card_reader_setup"]

    @impl true
    def resolve_chart(document_id, _ctx) when document_id in @setups,
      do: Library.Documents.published(document_id)

    def resolve_chart(_document_id, _ctx), do: :error
  """

  defmodule OnboardingSetups do
    @moduledoc "The page's allow-list resolver over a test store."

    use StatifierBlocks.Runtime.Subchart

    alias StatifierBlocks.Palette

    @setups ["doc_catalogue_sync", "doc_reading_list_import", "doc_card_reader_setup"]

    @impl true
    def resolve_chart(document_id, _ctx) when document_id in @setups,
      do: {:ok, StatifierBlocks.RuntimeFixtures.trivial_child(document_id)}

    def resolve_chart(_document_id, _ctx), do: :error

    @impl true
    def palette, do: Palette.core()

    @doc "The ids this resolver offers."
    def setups, do: @setups
  end

  defp page, do: File.read!(@page)

  defp document do
    {:ok, document} = @fixture |> File.read!() |> Document.from_json()
    document
  end

  defp compiled do
    {:ok, compiled} = Compiler.compile(document(), Palette.core())
    compiled
  end

  defp start(src) do
    invoke = HandlerCase.build_invoke(@type_string, src: src, invoke_id: "blk_SETUP")
    ctx = HandlerCase.build_ctx(@type_string, OnboardingSetups)
    Subchart.start(invoke, ctx, OnboardingSetups)
  end

  describe "the page and its fixture" do
    # Sabotage: changed the fixture's `needs_site_visit` outcome to
    # `site_visit` -> red: the page no longer quotes the fixture.
    test "the page quotes the fixture document byte for byte" do
      assert page() =~ "```json\n" <> File.read!(@fixture) <> "```\n"
    end

    # Sabotage: added an id to `OnboardingSetups`' `@setups` -> red: the
    # resolver the tests run no longer offers what the page prints.
    test "the page prints the resolver's allow-list clauses, which the tests run" do
      assert page() =~ @allow_list

      [_all, ids] = Regex.run(~r/@setups (\[.*?\])/, @allow_list)
      assert Code.eval_string(ids) |> elem(0) == OnboardingSetups.setups()
    end
  end

  describe "the compiled chart" do
    # Sabotage: emitted the path as a literal `src` in `Subchart.emit/2` ->
    # red: the invoke line the page quotes is not in the chart.
    test "compiles under the core palette with no finding, as the page quotes it" do
      %Compiled{scxml: scxml, warnings: warnings} = compiled()

      assert warnings == []

      invoke =
        ~s(<invoke id="blk_SETUP" srcexpr="onboarding.setup_document" type="statifier_blocks:subchart">)

      param =
        ~s(<param expr="'done skipped needs_site_visit error'" name="statifier_blocks:outcomes"/>)

      assert scxml =~ invoke
      assert scxml =~ param
      assert page() =~ invoke <> "\n  " <> param
    end

    test "the block's line reads the path, as the page says" do
      line = "Run the chart named at onboarding.setup_document and wait"

      assert document()
             |> ViewModel.build(Palette.core(), [])
             |> ViewModel.find_node("blk_SETUP")
             |> ViewModel.sentence() == line

      assert page() =~ "**Run\nthe chart named at onboarding.setup_document and wait**"
    end

    test "the compile records no child reference for the block" do
      assert compiled().interface.references == []
    end
  end

  describe "the resolver is the allow-list" do
    test "an offered id starts the setup as the child" do
      for id <- ["doc_catalogue_sync", "doc_reading_list_import", "doc_card_reader_setup"] do
        assert {:ok, [{:start_child, started, _origin}]} = start(id)
        assert {:ok, _machine} = Statifier.compile(started.content)
      end
    end

    # Sabotage: widened `OnboardingSetups.resolve_chart/2` to answer every
    # id -> red: the
    # unoffered id starts a child.
    test "an id the host does not offer is refused unknown_document" do
      assert {:ok, [{:raise, :platform, "error.communication.invoke.blk_SETUP", _origin, opts}]} =
               start("doc_branch_closure")

      assert opts[:data] == %{
               "reason" => "unknown_document",
               "detail" => %{"chart" => "doc_branch_closure"}
             }
    end

    test "a value that is not a string is refused unknown_document" do
      for value <- [42, :undefined] do
        assert {:ok, [{:raise, :platform, _event, _origin, opts}]} = start(value)
        assert opts[:data]["reason"] == "unknown_document"
      end
    end
  end

  describe "a live run" do
    test "an offered setup runs as the child and the onboarding finishes" do
      assert settles_in(%{"onboarding" => %{"setup_document" => "doc_catalogue_sync"}}) ==
               "s_blk_ROOT__o_done"
    end

    # Sabotage: answered every id in `OnboardingSetups.resolve_chart/2` ->
    # red: the
    # unoffered id runs a child and the onboarding finishes instead.
    test "an unoffered id, or nothing written yet, is caught by on_error" do
      for datamodel <- [%{"onboarding" => %{"setup_document" => "doc_branch_closure"}}, %{}] do
        assert settles_in(datamodel) == "s_blk_REFUSED"
      end
    end
  end

  # Which of the two places the page names the run settles in: the
  # onboarding's own final, or the on_error slot's wait.
  defp settles_in(datamodel) do
    {:ok, machine} = Statifier.compile(compiled().scxml)

    {:ok, session} =
      Session.start_link(machine,
        invoke_handlers: Subchart.handlers(OnboardingSetups),
        datamodel: datamodel
      )

    try do
      await_settled(session, 200)
    after
      Session.stop(session)
    end
  end

  defp await_settled(session, attempts) do
    configuration = Session.status(session).configuration

    cond do
      "s_blk_ROOT__o_done" in configuration ->
        "s_blk_ROOT__o_done"

      "s_blk_REFUSED" in configuration ->
        "s_blk_REFUSED"

      attempts == 0 ->
        flunk("the run settled at #{inspect(Enum.sort(configuration))}")

      true ->
        Process.sleep(5)
        await_settled(session, attempts - 1)
    end
  end
end
