defmodule StatifierBlocks.DescribeTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Describe, Document, DocumentGenerator, Palette}
  alias StatifierBlocks.Describe.{Edge, Node}

  doctest StatifierBlocks.Describe

  @documents Path.expand("../fixtures/documents", __DIR__)

  # The flow-graph note's library-loan example, lifted verbatim from
  # `docs/block-level-flow-graph.md`, "Worked example: a library loan".
  @library_loan Path.expand("../fixtures/flow_graph_note/library_loan.json", __DIR__)

  # The two JSON files under the documents corpus that are composite
  # declarations rather than block documents.
  @not_documents ~w(migrating_0_27_to_0_34/screen_after.json migrating_0_27_to_0_34/screen_before.json)

  defp decode!(path) do
    {:ok, document} = Document.from_json(File.read!(path))
    document
  end

  defp outline(document), do: Describe.outline(document, Palette.core(), [])

  defp block_ids(%Block{id: id, slots: slots}) do
    [id | slots |> Map.values() |> List.flatten() |> Enum.flat_map(&block_ids/1)]
  end

  defp edge(kind, container, from, to, fields \\ []) do
    struct!(Edge, [kind: kind, container: container, from: from, to: to] ++ fields)
  end

  describe "agreement with the flow-graph note's worked examples" do
    # The note's lifted listing, edge for edge, with the one difference
    # ADR-0016 decision 1 names: an await's edge carries the outcomes its
    # type declares, `received` and `timed_out`, where the compiled listing
    # says `received` for an await with no timeout.
    #
    # Sabotage: in `Describe.interrupt_edge/4`'s abandon clause, target
    # `{:body, group}` -> both abandon edges end at the body, red.
    test "patron registration produces the note's edges" do
      document = decode!(Path.join(@documents, "patron_registration.json"))

      assert outline(document).edges == [
               edge(:entry, "blk_PROOT", {:entry, "blk_PROOT"}, {:block, "blk_PGRP"}),
               edge(:exit, "blk_PROOT", {:block, "blk_PGRP"}, {:exit, "blk_PROOT"},
                 outcomes: ["done"]
               ),
               edge(:entry, "blk_PGRP", {:entry, "blk_PGRP"}, {:block, "blk_PDLN"}),
               edge(:sequence, "blk_PGRP", {:block, "blk_PDLN"}, {:block, "blk_PVER"},
                 outcomes: ["done"]
               ),
               edge(:exit, "blk_PGRP", {:block, "blk_PVER"}, {:exit, "blk_PGRP"},
                 outcomes: ["received", "timed_out"]
               ),
               edge(:interrupt, "blk_PGRP", {:block, "blk_PABN"}, {:exit, "blk_PGRP"},
                 event: "registration.abandoned"
               ),
               edge(:interrupt, "blk_PGRP", {:block, "blk_PEXP"}, {:exit, "blk_PGRP"},
                 event: "registration.deadline"
               )
             ]
    end

    # Sabotage: in `Describe.branch_edges/2`, drop the `pick` from each
    # arm -> the two `:branch` edges out of blk_LCHK's entry disappear, red.
    test "the library loan produces the note's edges" do
      assert outline(decode!(@library_loan)).edges == [
               edge(:entry, "blk_LROOT", {:entry, "blk_LROOT"}, {:block, "blk_LCHK"}),
               edge(:sequence, "blk_LROOT", {:block, "blk_LCHK"}, {:block, "blk_LOUT"},
                 outcomes: ["done"]
               ),
               edge(:sequence, "blk_LROOT", {:block, "blk_LOUT"}, {:block, "blk_LLEN"},
                 outcomes: ["done"]
               ),
               edge(:sequence, "blk_LROOT", {:block, "blk_LLEN"}, {:block, "blk_LEND"},
                 outcomes: ["done"]
               ),
               edge(:exit, "blk_LROOT", {:block, "blk_LEND"}, {:exit, "blk_LROOT"},
                 outcomes: ["done"]
               ),
               edge(:branch, "blk_LCHK", {:entry, "blk_LCHK"}, {:block, "blk_LFIN"},
                 condition: "patron.fines_owed > 0"
               ),
               edge(:sequence, "blk_LCHK", {:block, "blk_LFIN"}, {:block, "blk_LPAY"},
                 outcomes: ["done"]
               ),
               edge(:exit, "blk_LCHK", {:block, "blk_LPAY"}, {:exit, "blk_LCHK"},
                 outcomes: ["received", "timed_out"]
               ),
               edge(:branch, "blk_LCHK", {:entry, "blk_LCHK"}, {:exit, "blk_LCHK"},
                 condition: :otherwise
               ),
               edge(:entry, "blk_LLEN", {:entry, "blk_LLEN"}, {:block, "blk_LRET"}),
               edge(:exit, "blk_LLEN", {:block, "blk_LRET"}, {:exit, "blk_LLEN"},
                 outcomes: ["received", "timed_out"]
               ),
               edge(:interrupt, "blk_LLEN", {:block, "blk_LREN"}, {:body, "blk_LLEN"},
                 event: "loan.renewed",
                 history: :shallow
               ),
               edge(:interrupt, "blk_LLEN", {:block, "blk_LLOS"}, {:exit, "blk_LLEN"},
                 event: "loan.reported_lost"
               )
             ]
    end

    # Sabotage: in `Describe.edge_line/2`'s interrupt clause, drop the
    # ` at <history> history` suffix -> the resume line loses it, red.
    test "the library loan renders the default lines" do
      assert Describe.render(outline(decode!(@library_loan)), []) == [
               "Sequence",
               ~s(Decide: When "owes", otherwise \(one of\)),
               "Send loan.fines_notice",
               "Wait for event",
               "Send loan.checked_out",
               "Resumable group",
               "Wait for event",
               "When loan.renewed, resume",
               "When loan.reported_lost, abandon",
               "Send loan.closed",
               ~s(Sequence starts with Decide: When "owes", otherwise),
               ~s[After Decide: When "owes", otherwise (done), Send loan.checked_out],
               "After Send loan.checked_out (done), Resumable group",
               "After Resumable group (done), Send loan.closed",
               "Send loan.closed (done) ends Sequence",
               ~s(Decide: When "owes", otherwise: when patron.fines_owed > 0, Send loan.fines_notice),
               "After Send loan.fines_notice (done), Wait for event",
               ~s[Wait for event (received, timed_out) ends Decide: When "owes", otherwise],
               ~s(Decide: When "owes", otherwise: otherwise, the end of Decide: When "owes", otherwise),
               "Resumable group starts with Wait for event",
               "Wait for event (received, timed_out) ends Resumable group",
               "On loan.renewed, When loan.renewed, resume resumes Resumable group at shallow history",
               "On loan.reported_lost, When loan.reported_lost, abandon abandons Resumable group"
             ]
    end

    # Sabotage: in `Describe.node/4`, answer `parent: nil` -> every child's
    # parent is lost, red.
    test "nodes carry their parent, depth, kind, outcomes and arrangement" do
      %Describe{id: "bdoc_01JLIBRARYLOAN", revision: 1, nodes: nodes} =
        outline(decode!(@library_loan))

      assert Enum.map(nodes, &{&1.id, &1.parent, &1.depth, &1.kind, &1.outcomes, &1.fan_label}) ==
               [
                 {"blk_LROOT", nil, 0, :step, ["done"], nil},
                 {"blk_LCHK", "blk_LROOT", 1, :step, ["done"], "one of"},
                 {"blk_LFIN", "blk_LCHK", 2, :arm, ["done"], nil},
                 {"blk_LPAY", "blk_LCHK", 2, :arm, ["received", "timed_out"], nil},
                 {"blk_LOUT", "blk_LROOT", 1, :step, ["done"], nil},
                 {"blk_LLEN", "blk_LROOT", 1, :step, ["done"], nil},
                 {"blk_LRET", "blk_LLEN", 2, :step, ["received", "timed_out"], nil},
                 {"blk_LREN", "blk_LLEN", 2, :rail, ["done"], nil},
                 {"blk_LLOS", "blk_LLEN", 2, :rail, ["done"], nil},
                 {"blk_LEND", "blk_LROOT", 1, :step, ["done"], nil}
               ]

      assert %Node{summary: ["loan.fines_notice"]} = Enum.find(nodes, &(&1.id == "blk_LFIN"))
    end
  end

  describe "every fixture document" do
    # Sabotage: in `Describe.outline/3`, keep `tl(nodes)` -> every fixture's
    # root is missing from the nodes, red.
    test "outlines without raising, every block once, edges only between its blocks" do
      paths = [@library_loan | Path.wildcard(Path.join(@documents, "**/*.json"))]

      skipped =
        for path <- paths, match?({:error, _}, Document.from_json(File.read!(path))) do
          Path.relative_to(path, @documents)
        end

      assert Enum.sort(skipped) == @not_documents

      for path <- paths, Path.relative_to(path, @documents) not in skipped do
        document = decode!(path)
        %Describe{nodes: nodes, edges: edges} = outline(document)
        ids = block_ids(document.root)

        assert Enum.sort(Enum.map(nodes, & &1.id)) == Enum.sort(ids), path
        assert length(Enum.uniq(ids)) == length(ids), path

        for %Edge{container: container, from: {_from, from}, to: {_to, to}} <- edges do
          assert container in ids and from in ids and to in ids, "#{path}: #{from} -> #{to}"
        end
      end
    end
  end

  describe "an unresolvable block type" do
    # Sabotage: in `Describe.outcomes/1`, answer `[]` for an unresolvable
    # block -> the placeholder's outcomes and its edge's outcomes are
    # empty, red.
    test "outlines as its placeholder and takes part in its parent's edges" do
      root =
        Block.new("core.sequence",
          id: "root",
          slots: %{
            "body" => [
              Block.new("nobody.knows.this", id: "odd", config: %{"x" => 1}),
              Block.new("core.send", id: "send", config: %{"event" => "order.paid"})
            ]
          }
        )

      %Describe{nodes: nodes, edges: edges} = outline(Document.new(root))

      assert %Node{
               type: "nobody.knows.this",
               sentence: "nobody.knows.this",
               parent: "root",
               outcomes: ["done"],
               summary: [],
               kind: :step,
               depth: 1
             } = Enum.find(nodes, &(&1.id == "odd"))

      assert edge(:sequence, "root", {:block, "odd"}, {:block, "send"}, outcomes: ["done"]) in edges
    end

    # Sabotage: in `Describe.edges/3`, route an unresolvable block to
    # `body_edges/2` -> its `body` slot's child gets an `:entry` edge, red.
    test "draws no edge inside itself" do
      root =
        Block.new("nobody.knows.this",
          id: "odd",
          slots: %{"body" => [Block.new("core.send", id: "send", config: %{"event" => "e"})]}
        )

      assert %Describe{edges: [], nodes: [%Node{id: "odd"}, %Node{id: "send", depth: 1}]} =
               outline(Document.new(root))
    end
  end

  describe "edges the worked examples do not show" do
    # Sabotage: in `Describe.unwired_undecided?/1`, answer `false` for an
    # empty `undecided` -> a branch edge to the exit appears for it, red.
    test "a branch: an empty guarded arm, a wired otherwise, a wired and an unwired undecided" do
      branch = fn id, undecided ->
        Block.new("core.branch",
          id: id,
          config: %{
            "arms" => [
              %{"slot" => "arm_a", "cond" => "a > 1"},
              %{"slot" => "arm_b", "cond" => "b > 1"}
            ]
          },
          slots: %{
            "arm_a" => [],
            "arm_b" => [Block.new("core.send", id: id <> "b", config: %{"event" => "b"})],
            "otherwise" => [Block.new("core.send", id: id <> "o", config: %{"event" => "o"})],
            "undecided" => undecided
          }
        )
      end

      wired = branch.("w", [Block.new("core.send", id: "wu", config: %{"event" => "u"})])

      assert outline(Document.new(wired)).edges == [
               edge(:branch, "w", {:entry, "w"}, {:exit, "w"}, condition: "a > 1"),
               edge(:branch, "w", {:entry, "w"}, {:block, "wb"}, condition: "b > 1"),
               edge(:exit, "w", {:block, "wb"}, {:exit, "w"}, outcomes: ["done"]),
               edge(:branch, "w", {:entry, "w"}, {:block, "wo"}, condition: :otherwise),
               edge(:exit, "w", {:block, "wo"}, {:exit, "w"}, outcomes: ["done"]),
               edge(:branch, "w", {:entry, "w"}, {:block, "wu"}, condition: :undecided),
               edge(:exit, "w", {:block, "wu"}, {:exit, "w"}, outcomes: ["done"])
             ]

      assert outline(Document.new(branch.("n", []))).edges |> Enum.map(& &1.condition) ==
               ["a > 1", "b > 1", nil, :otherwise, nil]
    end

    # Sabotage: in `Describe.container_edges/4`'s `Group` clause, pass
    # `:shallow` as the history -> the plain group's resume carries a
    # history, red.
    test "a plain group's resume re-enters its body from the first step; an empty body" do
      root =
        Block.new("core.group",
          id: "g",
          slots: %{
            "body" => [],
            "interrupts" => [
              Block.new("core.on_event",
                id: "h",
                config: %{"event" => "again", "outcome" => "resume"}
              )
            ]
          }
        )

      described = outline(Document.new(root))

      assert described.edges == [
               edge(:entry, "g", {:entry, "g"}, {:exit, "g"}),
               edge(:interrupt, "g", {:block, "h"}, {:body, "g"}, event: "again")
             ]

      assert Describe.render(described, []) |> Enum.drop(2) == [
               "Group starts with the end of Group",
               "On again, When again, resume resumes Group"
             ]
    end

    # Sabotage: in `Describe.container_edges/4`, route every other type to
    # `branch_edges/2` -> the parallel's lanes draw `:branch` edges, red.
    test "a parallel is described by containment and its arrangement only" do
      root =
        Block.new("core.parallel",
          id: "p",
          config: %{"lanes" => ["a", "b"]},
          slots: %{
            "lane_a" => [Block.new("core.send", id: "sa", config: %{"event" => "a"})],
            "lane_b" => [
              Block.new("core.sequence",
                id: "q",
                slots: %{"body" => [Block.new("core.send", id: "sq", config: %{"event" => "q"})]}
              )
            ]
          }
        )

      %Describe{nodes: [parallel | _rest], edges: edges} = described = outline(Document.new(root))

      assert %Node{id: "p", fan_label: "all of"} = parallel

      assert edges == [
               edge(:entry, "q", {:entry, "q"}, {:block, "sq"}),
               edge(:exit, "q", {:block, "sq"}, {:exit, "q"}, outcomes: ["done"])
             ]

      assert hd(Describe.render(described, [])) =~ ~r/ \(all of\)$/
    end

    # Sabotage: in `Describe.event/2`, drop the blank check -> the edge
    # carries `"  "` as its event, red.
    test "a handler with a blank event, and one with no usable outcome" do
      root =
        Block.new("core.group",
          id: "g",
          slots: %{
            "body" => [Block.new("core.send", id: "s", config: %{"event" => "e"})],
            "interrupts" => [
              Block.new("core.on_event",
                id: "h1",
                config: %{"event" => "  ", "outcome" => "abandon"}
              ),
              Block.new("core.on_event",
                id: "h2",
                config: %{"event" => "x", "outcome" => "shrug"}
              )
            ]
          }
        )

      described = outline(Document.new(root))

      assert edge(:interrupt, "g", {:block, "h1"}, {:exit, "g"}) in described.edges
      refute Enum.any?(described.edges, &(&1.from == {:block, "h2"}))

      assert "On its event, When an event, abandon abandons Group" in Describe.render(
               described,
               []
             )
    end
  end

  describe "the phrasing seam" do
    defmodule Host do
      @behaviour StatifierBlocks.Describe.Phrasing

      @impl true
      def step(%Node{id: "send"}, _default), do: "Tell the shop the order is paid"
      def step(%Node{id: "wait"}, _default), do: "   "
      def step(%Node{id: "root"}, default), do: default <> "\nsecond line"

      @impl true
      def entry(%Edge{}, _default), do: "It begins with a pause."

      @impl true
      def sequence(%Edge{}, _default), do: raise("host bug")

      @impl true
      def exit(%Edge{}, _default), do: {:not, "a string"}
    end

    defmodule Thrower do
      @behaviour StatifierBlocks.Describe.Phrasing

      @impl true
      def step(%Node{}, _default), do: throw(:nope)

      @impl true
      def entry(%Edge{}, _default), do: exit(:nope)

      @impl true
      def sequence(%Edge{}, _default), do: :default

      @impl true
      def exit(%Edge{}, default), do: default <> "\t"
    end

    defmodule ExitOnly do
      @behaviour StatifierBlocks.Describe.Phrasing

      @impl true
      def exit(%Edge{}, _default), do: "and that is all"
    end

    @defaults [
      "Sequence",
      "Wait 30s",
      "Send order.paid",
      "Sequence starts with Wait 30s",
      "After Wait 30s (done), Send order.paid",
      "Send order.paid (done) ends Sequence"
    ]

    defp described do
      Block.new("core.sequence",
        id: "root",
        slots: %{
          "body" => [
            Block.new("core.wait", id: "wait", config: %{"duration" => "30s"}),
            Block.new("core.send", id: "send", config: %{"event" => "order.paid"})
          ]
        }
      )
      |> Document.new()
      |> outline()
    end

    # Sabotage: in `Describe.usable/1`, accept any binary -> the blank and
    # the multiline answers replace their lines, red.
    test "a host overrides one node and one edge; blank, newline, non-string and raise fall back" do
      assert Describe.render(described(), phrasing: Host) == [
               "Sequence",
               "Wait 30s",
               "Tell the shop the order is paid",
               "It begins with a pause.",
               "After Wait 30s (done), Send order.paid",
               "Send order.paid (done) ends Sequence"
             ]
    end

    # Sabotage: in `Describe.ask/4`, drop the `catch` clauses -> the throw
    # escapes render/2, red.
    test "a throw, an exit, :default and a tab fall back to the default" do
      assert Describe.render(described(), phrasing: Thrower) == @defaults
    end

    # Sabotage: in `Describe.render/2`, phrase the edges with `nil` -> the
    # exit line keeps the default, red.
    test "a callback is chosen by kind; an undeclared one keeps the default" do
      assert Describe.render(described(), phrasing: ExitOnly) ==
               List.replace_at(@defaults, 5, "and that is all")
    end

    # Sabotage: in `Describe.phrase/4`'s `nil` clause, answer `""` -> every
    # line is blank, red.
    test "no phrasing module answers the default lines" do
      assert Describe.render(described(), phrasing: nil) == @defaults
    end
  end

  describe "determinism" do
    # Sabotage: in `Describe.node_line/1`'s first clause, append
    # `:erlang.unique_integer()` -> two renders differ, red.
    test "rendering is byte-identical across two runs and across the document generator" do
      for index <- 0..199 do
        document = DocumentGenerator.generate(20_260_926, index)

        first = document |> outline() |> Describe.render([])
        second = document |> outline() |> Describe.render([])

        assert :erlang.term_to_binary(first) == :erlang.term_to_binary(second),
               "document #{index}"

        ids = block_ids(document.root)
        %Describe{nodes: nodes, edges: edges} = outline(document)

        assert Enum.sort(Enum.map(nodes, & &1.id)) == Enum.sort(ids), "document #{index}"

        assert Enum.all?(edges, fn %Edge{from: {_, from}, to: {_, to}} ->
                 from in ids and to in ids
               end),
               "document #{index}"

        for line <- first do
          assert String.trim(line) != "", "document #{index}"
          refute String.contains?(line, ["\n", "\r", "\t"]), "document #{index}: #{inspect(line)}"
        end
      end
    end

    # Sabotage: in `Describe.flat/1`, answer `text` unchanged -> the
    # condition's newline breaks its line, red.
    test "an author's condition carrying a newline is written on one line" do
      root =
        Block.new("core.branch",
          id: "b",
          config: %{"arms" => [%{"slot" => "arm_a", "cond" => "a >\n1"}]},
          slots: %{
            "arm_a" => [Block.new("core.send", id: "s", config: %{"event" => "e"})],
            "otherwise" => [],
            "undecided" => []
          }
        )

      lines = root |> Document.new() |> outline() |> Describe.render([])

      assert Enum.any?(lines, &String.contains?(&1, "when a > 1, Send e"))
      refute Enum.any?(lines, &String.contains?(&1, "\n"))
    end
  end

  describe "no network, clock, process, random source or model" do
    @modules [Describe, Edge, Node, StatifierBlocks.Describe.Phrasing]

    @forbidden_modules [
      :gen_tcp,
      :gen_udp,
      :httpc,
      :inet,
      :socket,
      :ssl,
      :os,
      :calendar,
      :timer,
      :rand,
      :random,
      :crypto,
      :global,
      :ets,
      :persistent_term,
      System,
      DateTime,
      NaiveDateTime,
      Date,
      Time,
      Process,
      Task,
      GenServer,
      Agent,
      Port,
      Registry,
      Supervisor,
      StatifierBlocks.Compiler,
      :"Elixir.Node"
    ]

    @forbidden_erlang ~w(spawn spawn_link spawn_monitor spawn_opt send now monotonic_time
                         system_time time date localtime universaltime timestamp
                         unique_integer make_ref open_port whereis register self)a

    # Sabotage: add `System.os_time()` to `Describe.render/2` -> the import
    # table names `System`, red.
    test "the compiled modules import nothing that reaches one" do
      for module <- @modules do
        # Read from the file on disk: under coverage the loaded module is
        # cover-compiled and `:code.which/1` names no file.
        beam = Application.app_dir(:statifier_blocks, "ebin/#{module}.beam")

        {:ok, {^module, [imports: imports]}} =
          beam |> String.to_charlist() |> :beam_lib.chunks([:imports])

        offending =
          Enum.filter(imports, fn {mod, fun, _arity} ->
            mod in @forbidden_modules or (mod == :erlang and fun in @forbidden_erlang)
          end)

        assert offending == [], "#{inspect(module)} imports #{inspect(offending)}"
      end
    end

    # Sabotage: add a `receive ... after 0` to `Describe.render/2` -> the
    # source scan finds `receive`, red.
    test "the source holds no receive" do
      lib = Path.expand("../../lib/statifier_blocks", __DIR__)
      sources = [Path.join(lib, "describe.ex") | Path.wildcard(Path.join(lib, "describe/*.ex"))]

      assert length(sources) == 4

      for source <- sources do
        refute File.read!(source) =~ ~r/\breceive\b/, source
      end
    end
  end
end
