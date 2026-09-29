defmodule StatifierBlocks.MapHoverTest do
  @moduledoc """
  The description region on hover: the `StatifierBlocksMap` hook's own
  hover (`assets/js/statifier_blocks_map.js`) run over a page carrying the
  descriptions `StatifierBlocks.Map.Info` answers.

  Hover happens in the browser, so the only honest test of it runs the
  same JavaScript. `test/support/js/statifier_blocks_map_hover.mjs` mounts
  the real hook, which draws the graph through the real elkjs, over a page
  holding the region and the store, points at every element the drawing
  carries and at every child of each, and prints what the region held each
  time. Node must be on the path, as for the map's layout tests.

  The tests move from the reference host's hover test at
  `statifier_examples@c620756`, where the hover was a hook of its own. The
  page here is written by the test rather than rendered by a LiveView: a
  store entry is the description's title and explanation as markup, and
  the region's content is the idle description's, or a selected block's.
  The host's test of where its hook's element sat has no counterpart:
  hover is the Map hook's now, on the map's own element.

  Not tagged `:liveview`: nothing here names Phoenix, so it runs in the
  headless tree too.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.Describe
  alias StatifierBlocks.Map, as: BlockMap
  alias StatifierBlocks.Map.Info
  alias StatifierBlocks.MapFixtures
  alias StatifierBlocks.Palette
  alias StatifierBlocks.ViewModel

  @driver Path.expand("../support/js/statifier_blocks_map_hover.mjs", __DIR__)
  @hook Path.expand("../../assets/js/statifier_blocks_map.js", __DIR__)

  @moduletag :tmp_dir

  describe "hover" do
    # Every element the map draws, and every child of each, fills the region
    # with exactly that element's stored description, and moving off puts
    # the idle description back byte for byte - on both teaching documents,
    # so a shape only one document draws is still pointed at.
    #
    # Sabotage: made `show` copy nothing into the region; every hover came
    # back unshown and this went red. Reverted from a copy.
    test "fills the region from the store and restores the idle content", %{tmp_dir: dir} do
      for key <- MapFixtures.keys() do
        result = run(dir, key, page(key))

        assert result["missing"] == [], "#{key}: drawn with no description"
        refute result["hovers"] == []

        for hover <- result["hovers"] do
          where = "#{key}: #{hover["element"]} #{hover["child"]}"
          assert hover["id"] == hover["element"], where
          assert hover["shown"], "#{where}: the region did not show its entry"
          assert hover["restored"], "#{where}: moving off did not restore the region"
        end
      end
    end

    # The rest of the pointer's paths: straight from one element to another,
    # out of the window, onto a gap's "+", and off after a patch has already
    # redrawn the region.
    #
    # Sabotage: made `restore` put the kept content back without asking for
    # the hover mark; the patched region was overwritten and this went red.
    # Reverted from a copy.
    test "chained, out of the window, over a gap, and after a patch", %{tmp_dir: dir} do
      for key <- MapFixtures.keys() do
        paths =
          dir |> run(key, page(key)) |> Map.take(["chained", "outOfWindow", "gaps", "stale"])

        assert paths == %{
                 "chained" => true,
                 "outOfWindow" => true,
                 "gaps" => true,
                 "stale" => true
               },
               key
      end
    end

    # A row selected after the page is up patches the region with that
    # block's description; moving off a hovered element then restores the
    # selected block's description, not the document's the page mounted
    # with.
    #
    # Sabotage: made hover/2 keep the region's content once, when the hook
    # mounted, and restore that; every restore came back with the idle
    # description and this went red. Reverted from a copy.
    test "restores the selected block's description", %{tmp_dir: dir} do
      idle = page("library_loan")
      {_graph, descriptions, _idle} = described("library_loan")
      selected = descriptions |> Enum.find(&(&1.id == "blk_ll_loan_period")) |> entry_html()

      assert selected =~ "Wait"
      refute selected == idle["region"]

      result = run(dir, "selected", Map.put(idle, "patched", selected))
      refute result["hovers"] == []
      assert Enum.all?(result["hovers"], & &1["restored"])
    end

    # A host that stamps no region and no store on the map's element gets a
    # map with no hover: pointing at it changes nothing.
    #
    # Sabotage: made the hook look the region up by a fixed id when its
    # element names none; the bare hook filled the region and this went
    # red. Reverted from a copy.
    test "a map whose element names no region swaps nothing", %{tmp_dir: dir} do
      assert %{"unnamed" => true} = run(dir, "unnamed", page("patron_registration"))
    end

    # A hover never reaches the server: the hook pushes nothing, whatever it
    # is pointed at, leaves no listener behind, and the hover code names no
    # push. The hook's one push, the host list's gesture, is held apart by
    # `StatifierBlocks.AssetsTest`.
    #
    # Sabotage: added `pushEvent("hover", {})` to the hook's mouseover
    # listener, through a local `const push = this.pushEvent.bind(this)`;
    # `pushes` came back non-empty and this went red. Reverted from a copy.
    test "pushes nothing to the server", %{tmp_dir: dir} do
      assert %{"pushes" => [], "listening" => 0} = run(dir, "pushes", page("patron_registration"))

      [_before, hover_code] = String.split(File.read!(@hook), "-- hover\n", parts: 2)
      [hover_code, _hook] = String.split(hover_code, "// The LiveView hook.", parts: 2)
      refute hover_code =~ "pushEvent"
    end
  end

  # ---------------------------------------------------------------- helpers

  defp described(key) do
    document = MapFixtures.document!(key)
    view_model = ViewModel.build(document, Palette.core(), [])
    graph = BlockMap.graph(view_model, phrase: &MapFixtures.phrase/1)
    outline = Describe.outline(document, Palette.core(), [])

    {graph,
     Info.elements(document, graph, view_model, outline, Palette.core(),
       phrase: &MapFixtures.phrase/1
     ), Info.idle(document, graph, view_model, outline)}
  end

  # The page the driver reads: the map's graph, the region's markup with the
  # idle description, and one store entry per description.
  defp page(key) do
    {graph, descriptions, idle} = described(key)

    %{
      "graph" => graph,
      "region" => entry_html(idle),
      "entries" => Enum.map(descriptions, &%{"id" => &1.id, "html" => entry_html(&1)})
    }
  end

  # A description as the region shows it, in the smallest markup that tells
  # one entry from another.
  defp entry_html(%Info{} = description) do
    ~s(<p class="title">#{escape(description.title)}</p><p>#{escape(description.explanation)}</p>)
  end

  defp escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp run(dir, name, page) do
    node = System.find_executable("node") || flunk("the hover tests need Node on the PATH")
    path = Path.join(dir, "#{name}.page.json")
    File.write!(path, JSON.encode!(page))

    {out, status} = System.cmd(node, [@driver, path], stderr_to_stdout: true)
    assert status == 0, "the hover driver exited #{status}: #{out}"
    JSON.decode!(out)
  end
end
