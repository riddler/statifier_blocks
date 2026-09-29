defmodule StatifierBlocks.DescribeTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Describe, Document, DocumentGenerator, Palette}
  alias StatifierBlocks.Core.OnEvent
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
    # says `received` for an await with no timeout. Beyond the listing, and
    # after every edge it shows, the timer edge from the deadline send to
    # the rule its event arms (ADR-0017 decision 3).
    #
    # Sabotage: in `Describe.interrupt_edge/4`'s abandon clause, target
    # `{:body, group}` -> both abandon edges end at the body, red.
    # Sabotage: in `Describe.timer_edge/3`, set `container` to the send
    # itself -> the timer edge's container is `blk_PDLN`, red.
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
               ),
               edge(:timer, "blk_PGRP", {:block, "blk_PDLN"}, {:block, "blk_PEXP"},
                 event: "registration.deadline",
                 delay: "24h"
               )
             ]
    end

    # Sabotage: in `Describe.edge_line/2`'s timer clause, write the stored
    # delay instead of its words -> the line reads `In 24h, ...`, red.
    test "patron registration renders the timer edge's line last" do
      document = decode!(Path.join(@documents, "patron_registration.json"))

      assert document |> outline() |> Describe.render([]) |> List.last() ==
               "In 24 hours, registration.deadline reaches When registration.deadline, abandon"
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
               "Run its steps in order",
               ~s(Decide: When "owes", otherwise \(one of\)),
               "Send loan.fines_notice",
               "Wait for fines.paid",
               "Send loan.checked_out",
               "Resumable group",
               "Wait for loan.returned, giving up after 21d",
               "When loan.renewed, resume",
               "When loan.reported_lost, abandon",
               "Send loan.closed",
               ~s(The steps start with Decide: When "owes", otherwise),
               ~s[After Decide: When "owes", otherwise (done), Send loan.checked_out],
               "After Send loan.checked_out (done), Resumable group",
               "After Resumable group (done), Send loan.closed",
               "Send loan.closed (done) ends the steps",
               "The branch: when patron.fines_owed > 0, Send loan.fines_notice",
               "After Send loan.fines_notice (done), Wait for fines.paid",
               "Wait for fines.paid (received, timed_out) ends the branch",
               "The branch: otherwise, the end of the branch",
               "The group starts with Wait for loan.returned, giving up after 21d",
               "Wait for loan.returned, giving up after 21d (received, timed_out) ends the group",
               "On loan.renewed, When loan.renewed, resume resumes the group at shallow history",
               "On loan.reported_lost, When loan.reported_lost, abandon abandons the group"
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
              Block.new("core.send", id: "send", config: %{"event" => "loan.overdue"})
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
               "The group starts with the end of the group",
               "On again, When again, resume resumes the group"
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

      assert "On its event, When an event, abandon abandons the group" in Describe.render(
               described,
               []
             )
    end

    # A handler that names what it finishes with still abandons its group:
    # the edge is keyed on the `outcome` select, not on the finishing name
    # the view model carries for the card.
    #
    # Sabotage: in `Describe.interrupt_edges/3`, key the edge on the view
    # model node's `outcome` instead of `select/3` -> the handler answers
    # `cancelled`, draws no edge, red.
    test "an abandon handler that names finish_as draws its interrupt edge to the exit" do
      root =
        Block.new("core.group",
          id: "g",
          slots: %{
            "body" => [Block.new("core.send", id: "s", config: %{"event" => "e"})],
            "interrupts" => [
              Block.new("core.on_event",
                id: "h",
                config: %{
                  "event" => "user.cancel",
                  "outcome" => "abandon",
                  "finish_as" => "cancelled"
                }
              )
            ]
          }
        )

      [handler] = root.slots["interrupts"]
      assert OnEvent.validate_config(handler.config) == :ok

      # `finish_as` is refused beside `outcome: "resume"`, so no resume
      # handler names one.
      assert {:error, _findings} =
               OnEvent.validate_config(Map.put(handler.config, "outcome", "resume"))

      described = outline(Document.new(root))

      assert Enum.filter(described.edges, &(&1.kind == :interrupt)) == [
               edge(:interrupt, "g", {:block, "h"}, {:exit, "g"}, event: "user.cancel")
             ]

      assert Describe.render(described, []) |> List.last() =~
               ~r/^On user\.cancel, .* abandons the group$/
    end

    # A handler the palette cannot resolve is read from the document's own
    # config, so its `outcome` select still draws the edge it drew when the
    # view model's node answered it.
    #
    # Sabotage: in `Describe.select/3`, answer `nil` for an unresolvable
    # block -> the handler draws no edge, red.
    test "an unresolvable handler's outcome select still draws its interrupt edge" do
      root =
        Block.new("core.group",
          id: "g",
          slots: %{
            "body" => [],
            "interrupts" => [
              Block.new("host.unknown", id: "h", config: %{"outcome" => "abandon"})
            ]
          }
        )

      assert Enum.filter(outline(Document.new(root)).edges, &(&1.kind == :interrupt)) == [
               edge(:interrupt, "g", {:block, "h"}, {:exit, "g"})
             ]
    end
  end

  describe "a container is recognised by the module its type resolves to" do
    defp loan_steps(type) do
      Block.new(type,
        id: "root",
        slots: %{
          "body" => [Block.new("core.send", id: "send", config: %{"event" => "loan.overdue"})]
        }
      )
      |> Document.new()
    end

    # Sabotage: in `Describe.edges/3`, dispatch on the block's type name
    # (`module(Map.get(Palette.core_types(), block.type))`) instead of
    # `module(ref)` -> the host-named sequence draws no edge, red.
    test "the package's sequence under a host's name draws a sequence's edges" do
      palette =
        Palette.new(%{
          "library.loan_steps" => StatifierBlocks.Core.Sequence,
          "core.send" => StatifierBlocks.Core.Send
        })

      assert %Describe{edges: edges} =
               Describe.outline(loan_steps("library.loan_steps"), palette, [])

      assert edges == [
               edge(:entry, "root", {:entry, "root"}, {:block, "send"}),
               edge(:exit, "root", {:block, "send"}, {:exit, "root"}, outcomes: ["done"])
             ]
    end

    # Sabotage: the mutation above -> `core.sequence` dispatches to the
    # package's sequence whatever the palette holds, edges drawn, red.
    test "a host's own module under core.sequence is described by containment only" do
      palette =
        Palette.new(%{
          "core.sequence" => StatifierBlocks.BlockTypeFixtures.OutcomeParent,
          "core.send" => StatifierBlocks.Core.Send
        })

      assert %Describe{edges: [], nodes: [%Node{id: "root"}, %Node{id: "send", depth: 1}]} =
               Describe.outline(loan_steps("core.sequence"), palette, [])
    end
  end

  describe "a container is named by a noun in the edge lines" do
    # A host's container: one body slot, a `label` field an author names
    # a block by, and a palette label of its own. It draws no edge of its
    # own, so the lines below are rendered over edges written by hand.
    defmodule Route do
      @moduledoc false
      @behaviour StatifierBlocks.BlockType

      @impl true
      def current_version, do: 1

      @impl true
      def slots(_config), do: [{"body", :any, "Stops"}]

      @impl true
      def config_schema(_config),
        do: [%{key: "label", type: :string, label: "Name", required?: false, default: ""}]

      @impl true
      def validate_config(_config), do: :ok

      @impl true
      def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

      @impl true
      def palette_entry, do: %{label: "Delivery route", group: "Parcels"}
    end

    defp route(config) do
      palette = Palette.new(%{"parcel.route" => Route, "core.send" => StatifierBlocks.Core.Send})

      delivered = Block.new("core.send", id: "send", config: %{"event" => "parcel.delivered"})

      described =
        Block.new("parcel.route", id: "route", config: config, slots: %{"body" => [delivered]})
        |> Document.new()
        |> Describe.outline(palette, [])

      %{
        described
        | edges: [
            edge(:entry, "route", {:entry, "route"}, {:block, "send"}),
            edge(:exit, "route", {:block, "send"}, {:exit, "route"}, outcomes: ["done"]),
            edge(:branch, "route", {:entry, "route"}, {:exit, "route"}, condition: :otherwise)
          ]
      }
    end

    # Sabotage: in `Describe`'s noun table, map `Branch` to "the steps" ->
    # the branch's noun reads "the steps", red.
    # Sabotage: in `Describe.node_noun/2`, drop the no-slots clause -> the send
    # carries "the send", red.
    test "an untitled core container is named by its module's noun; a leaf and an unresolvable block by none" do
      root =
        Block.new("core.sequence",
          id: "root",
          slots: %{
            "body" => [
              Block.new("core.group", id: "group"),
              Block.new("core.resumable_group", id: "resumable"),
              Block.new("core.branch", id: "branch"),
              Block.new("core.parallel", id: "parallel", config: %{"lanes" => ["a", "b"]}),
              Block.new("core.foreach", id: "foreach"),
              Block.new("parcel.unknown", id: "unknown", slots: %{"body" => []}),
              Block.new("core.send", id: "send", config: %{"event" => "parcel.delivered"})
            ]
          }
        )

      nouns =
        root |> Document.new() |> outline() |> Map.fetch!(:nodes) |> Map.new(&{&1.id, &1.noun})

      assert nouns == %{
               "root" => "the steps",
               "group" => "the group",
               "resumable" => "the group",
               "branch" => "the branch",
               "parallel" => "the lanes",
               "foreach" => "the loop",
               "unknown" => nil,
               "send" => nil
             }
    end

    # Sabotage: in `Describe.node_noun/2`, read the palette label ahead of the
    # title -> the route is "the delivery route", red.
    test "a titled container is named by its title in every line that names it" do
      described = route(%{"label" => "Morning round"})

      assert %Node{id: "route", noun: "Morning round"} = hd(described.nodes)

      assert described |> Describe.render([]) |> Enum.drop(2) == [
               "Morning round starts with Send parcel.delivered",
               "Send parcel.delivered (done) ends Morning round",
               "Morning round: otherwise, the end of Morning round"
             ]
    end

    # Sabotage: in `Describe.opening/1`, capitalise only a noun from the
    # module table (`"the " <> rest` guarded by `in @plural_nouns`) -> the
    # title "the intake" opens its line lower-case, red.
    # Sabotage: in `Describe.edge_line/2`, answer "starts" for every noun ->
    # the title "the steps" reads "The steps starts", red.
    test "a title beginning with the is capitalised and takes its verb from its text" do
      assert route(%{"label" => "the intake"}) |> Describe.render([]) |> Enum.at(2) ==
               "The intake starts with Send parcel.delivered"

      assert route(%{"label" => "the steps"}) |> Describe.render([]) |> Enum.at(2) ==
               "The steps start with Send parcel.delivered"
    end

    # Sabotage: in `Describe.node_noun/2`, drop `String.downcase/1` -> the route
    # is "the Delivery route", red.
    # Sabotage: in `Describe.opening/1`, answer the noun unchanged -> the
    # entry line opens "the delivery route", red.
    test "an untitled host container is named by the and its palette label in lower case" do
      described = route(%{})

      assert %Node{id: "route", noun: "the delivery route"} = hd(described.nodes)

      assert described |> Describe.render([]) |> Enum.drop(2) == [
               "The delivery route starts with Send parcel.delivered",
               "Send parcel.delivered (done) ends the delivery route",
               "The delivery route: otherwise, the end of the delivery route"
             ]
    end

    # Sabotage: in `Describe.container_name/1`, answer "a block" for a node
    # with no noun -> the entry line reads "a block starts with ...", red.
    test "a node that carries no noun is named by its sentence" do
      described = %Describe{
        id: "bdoc_parcel",
        revision: 0,
        nodes: [
          %Node{
            id: "route",
            type: "parcel.route",
            depth: 0,
            kind: :step,
            sentence: "Deliver the parcels"
          },
          %Node{
            id: "send",
            type: "core.send",
            depth: 1,
            kind: :step,
            sentence: "Send parcel.delivered"
          }
        ],
        edges: [edge(:entry, "route", {:entry, "route"}, {:block, "send"})]
      }

      assert Describe.render(described, []) |> List.last() ==
               "Deliver the parcels starts with Send parcel.delivered"
    end
  end

  describe "an embedded delayed send's sentence is set in double quotation marks" do
    defp overdue(id),
      do: Block.new("core.send", id: id, config: %{"event" => "loan.overdue", "delay" => "7d"})

    defp lines(root), do: root |> Document.new() |> outline() |> Describe.render([])

    # A node written by hand, for the two templates whose embedded step
    # the package's own edges never make a send.
    defp hand_node(id, type, sentence),
      do: %Node{id: id, type: type, depth: 1, kind: :step, sentence: sentence}

    defp by_hand(nodes, edges),
      do: %Describe{id: "bdoc_loan", revision: 0, nodes: nodes, edges: edges}

    # Sabotage: in `Describe.embedded_name/1`, answer `name(node)` for a
    # delayed send -> the entry line reads `The steps start with In 7 days,
    # send loan.overdue`, red.
    test "the :entry line" do
      root =
        Block.new("core.sequence", id: "root", slots: %{"body" => [overdue("overdue")]})

      assert "The steps start with \"In 7 days, send loan.overdue\"" in lines(root)
    end

    # Sabotage: in `Describe.embedded_name/1`, answer `name(node)` for a
    # delayed send -> the sequence lines lose their marks, red.
    test "the :sequence line, from either end" do
      wait = Block.new("core.wait", id: "wait", config: %{"duration" => "14d"})

      root =
        Block.new("core.sequence",
          id: "root",
          slots: %{"body" => [overdue("overdue"), wait, overdue("again")]}
        )

      rendered = lines(root)

      assert "After \"In 7 days, send loan.overdue\" (done), Wait 14d" in rendered
      assert "After Wait 14d (done), \"In 7 days, send loan.overdue\"" in rendered
    end

    # Sabotage: in `Describe.embedded_name/1`, answer `name(node)` for a
    # delayed send -> the exit line reads `In 7 days, send loan.overdue
    # (done) ends the steps`, red.
    test "the :exit line" do
      root =
        Block.new("core.sequence", id: "root", slots: %{"body" => [overdue("overdue")]})

      assert "\"In 7 days, send loan.overdue\" (done) ends the steps" in lines(root)
    end

    # Sabotage: in `Describe.embedded_name/1`, answer `name(node)` for a
    # delayed send -> the branch line reads `The branch: when
    # patron.fines_owed > 0, In 7 days, send loan.overdue`, red.
    test "the :branch line" do
      root =
        Block.new("core.branch",
          id: "fines",
          config: %{"arms" => [%{"slot" => "arm_owes", "cond" => "patron.fines_owed > 0"}]},
          slots: %{"arm_owes" => [overdue("overdue")], "otherwise" => [], "undecided" => []}
        )

      assert "The branch: when patron.fines_owed > 0, \"In 7 days, send loan.overdue\"" in lines(
               root
             )
    end

    # Sabotage: in `Describe.embedded_name/1`, answer `name(node)` for a
    # delayed send -> the interrupt line reads `On loan.reported_lost, In 7
    # days, send loan.overdue abandons the group`, red.
    test "the :interrupt line" do
      described =
        by_hand(
          [
            hand_node("lending", "core.group", "Run its steps as a group")
            |> Map.put(:noun, "the group"),
            hand_node("overdue", "core.send", "In 7 days, send loan.overdue")
          ],
          [
            edge(:interrupt, "lending", {:block, "overdue"}, {:exit, "lending"},
              event: "loan.reported_lost"
            )
          ]
        )

      assert Describe.render(described, []) |> List.last() ==
               "On loan.reported_lost, \"In 7 days, send loan.overdue\" abandons the group"
    end

    # Sabotage: in `Describe.embedded_name/1`, answer `name(node)` for a
    # delayed send -> the timer line reads `In 2 days, loan.due reaches In 7
    # days, send loan.overdue`, red.
    test "the :timer line" do
      described =
        by_hand(
          [
            hand_node("due", "core.send", "In 2 days, send loan.due"),
            hand_node("overdue", "core.send", "In 7 days, send loan.overdue")
          ],
          [
            edge(:timer, "root", {:block, "due"}, {:block, "overdue"},
              event: "loan.due",
              delay: "2d"
            )
          ]
        )

      assert Describe.render(described, []) |> List.last() ==
               "In 2 days, loan.due reaches \"In 7 days, send loan.overdue\""
    end

    # Sabotage: in `Describe.container_name/1`, fall back to `name/1` for a
    # node with no noun -> the line reads `On loan.due, When loan.due,
    # abandon abandons In 7 days, send loan.overdue`, red.
    test "a delayed send named by its sentence where a container carries no noun" do
      described =
        by_hand(
          [
            hand_node("overdue", "core.send", "In 7 days, send loan.overdue"),
            hand_node("rule", "core.on_event", "When loan.due, abandon")
          ],
          [edge(:interrupt, "overdue", {:block, "rule"}, {:exit, "overdue"}, event: "loan.due")]
        )

      assert Describe.render(described, []) |> List.last() ==
               "On loan.due, When loan.due, abandon abandons \"In 7 days, send loan.overdue\""
    end

    # Sabotage: in `Describe.render/2`, quote the node line of a delayed
    # send too (`embedded_name/1` in place of `node_line/1`'s `name/1`) ->
    # the node line carries the marks, red.
    # Sabotage: in `Describe.embedded_name/1`, drop the `core.send` type
    # match -> the host's step carries the marks, red.
    test "a delayed send's node line, an undelayed send and any other step are written as before" do
      reminder =
        hand_node("remind", "loan.remind", "In 7 days, send a reminder")

      described =
        by_hand(
          [
            hand_node("root", "core.sequence", "Run its steps in order")
            |> Map.put(:noun, "the steps"),
            hand_node("overdue", "core.send", "In 7 days, send loan.overdue"),
            hand_node("closed", "core.send", "Send loan.closed"),
            reminder
          ],
          [
            edge(:entry, "root", {:entry, "root"}, {:block, "closed"}),
            edge(:sequence, "root", {:block, "closed"}, {:block, "remind"}, outcomes: ["done"])
          ]
        )

      assert Describe.render(described, []) == [
               "Run its steps in order",
               "In 7 days, send loan.overdue",
               "Send loan.closed",
               "In 7 days, send a reminder",
               "The steps start with Send loan.closed",
               "After Send loan.closed (done), In 7 days, send a reminder"
             ]
    end
  end

  describe "the timer edge" do
    defp delayed(id, event, delay),
      do: Block.new("core.send", id: id, config: %{"event" => event, "delay" => delay})

    defp await(id, event), do: Block.new("core.await", id: id, config: %{"event" => event})

    defp rule(id, event),
      do: Block.new("core.on_event", id: id, config: %{"event" => event, "outcome" => "abandon"})

    # Two delayed sends of one event, each reaching the await and the rule
    # that name it; an undelayed send of the same event and an await of
    # another event take part in none.
    defp timers do
      Block.new("core.sequence",
        id: "root",
        slots: %{
          "body" => [
            delayed("first", "loan.due", "1h30m"),
            await("waits", "loan.due"),
            Block.new("core.group",
              id: "g",
              slots: %{
                "body" => [
                  Block.new("core.send", id: "now", config: %{"event" => "loan.due"}),
                  delayed("second", "loan.due", "2d"),
                  await("other", "loan.returned")
                ],
                "interrupts" => [rule("rule", "loan.due")]
              }
            )
          ]
        }
      )
      |> Document.new()
      |> outline()
    end

    # Sabotage: in `Describe.timer_edges/2`, drop the delay test -> the
    # undelayed send `now` draws two timer edges, red.
    test "a delayed send reaches every rule and await naming its event, in outline order" do
      timer_edges = Enum.filter(timers().edges, &(&1.kind == :timer))

      assert timer_edges == [
               edge(:timer, "root", {:block, "first"}, {:block, "waits"},
                 event: "loan.due",
                 delay: "1h30m"
               ),
               edge(:timer, "root", {:block, "first"}, {:block, "rule"},
                 event: "loan.due",
                 delay: "1h30m"
               ),
               edge(:timer, "g", {:block, "second"}, {:block, "waits"},
                 event: "loan.due",
                 delay: "2d"
               ),
               edge(:timer, "g", {:block, "second"}, {:block, "rule"},
                 event: "loan.due",
                 delay: "2d"
               )
             ]
    end

    # Sabotage: in `Describe.outline/3`, put the timer edges ahead of the
    # container edges -> the first edge is a timer edge, red.
    test "timer edges follow every other edge, and render byte-identically" do
      described = timers()
      {others, timer_edges} = Enum.split_while(described.edges, &(&1.kind != :timer))

      assert length(timer_edges) == 4
      assert Enum.all?(timer_edges, &(&1.kind == :timer))
      refute Enum.any?(others, &(&1.kind == :timer))
      assert Enum.all?(others, &(&1.delay == nil))

      first = Describe.render(described, [])
      second = Describe.render(timers(), [])
      assert :erlang.term_to_binary(first) == :erlang.term_to_binary(second)

      assert Enum.take(first, -4) == [
               "In 1 hour 30 minutes, loan.due reaches Wait for loan.due",
               "In 1 hour 30 minutes, loan.due reaches When loan.due, abandon",
               "In 2 days, loan.due reaches Wait for loan.due",
               "In 2 days, loan.due reaches When loan.due, abandon"
             ]
    end

    # Sabotage: in `Describe.delayed?/1`, accept any binary delay -> the
    # `soon` send draws a timer edge, red.
    test "a document with no delayed send answers no timer edge" do
      refute Enum.any?(outline(decode!(@library_loan)).edges, &(&1.kind == :timer))

      root =
        Block.new("core.sequence",
          id: "root",
          slots: %{
            "body" => [
              delayed("empty", "loan.due", ""),
              delayed("unreadable", "loan.due", "soon"),
              Block.new("core.send", id: "absent", config: %{"event" => "loan.due"}),
              await("waits", "loan.due")
            ]
          }
        )

      refute Enum.any?(outline(Document.new(root)).edges, &(&1.kind == :timer))
    end

    # A send with a delay but no usable event names nothing, so it does not
    # reach a rule or await that names nothing either: a blank event is no
    # event, on either end.
    #
    # Sabotage: in `Describe.timer_edges/2`, bind both ends' `event` with
    # `Map.get(config, "event")` instead of `config_event/1` -> the blank
    # send reaches the blank await, red.
    test "a delayed send with no event reaches nothing" do
      root =
        Block.new("core.sequence",
          id: "root",
          slots: %{
            "body" => [
              Block.new("core.send", id: "blank", config: %{"event" => " ", "delay" => "1d"}),
              Block.new("core.send", id: "absent", config: %{"delay" => "1d"}),
              Block.new("core.await", id: "blank_wait", config: %{"event" => " "}),
              Block.new("core.await", id: "absent_wait", config: %{})
            ]
          }
        )

      refute Enum.any?(outline(Document.new(root)).edges, &(&1.kind == :timer))
    end

    # Sabotage: in `Describe.timer_party/2`, drop the shelf test -> the
    # shelved send and the shelved await draw timer edges, red.
    test "a block inside a drafts shelf takes part in no timer edge" do
      root =
        Block.new("core.sequence",
          id: "root",
          slots: %{
            "body" => [
              delayed("live", "loan.due", "7d"),
              await("waits", "loan.due"),
              Block.new("core.drafts",
                id: "shelf",
                slots: %{
                  "body" => [
                    delayed("shelved_send", "loan.due", "1d"),
                    Block.new("core.sequence",
                      id: "shelved_seq",
                      slots: %{"body" => [await("shelved_await", "loan.due")]}
                    )
                  ]
                }
              )
            ]
          }
        )

      assert Enum.filter(outline(Document.new(root)).edges, &(&1.kind == :timer)) == [
               edge(:timer, "root", {:block, "live"}, {:block, "waits"},
                 event: "loan.due",
                 delay: "7d"
               )
             ]
    end

    # Sabotage: in `Describe.timer_party/2`, let an unresolvable block take
    # part as an await -> the unresolvable block `odd`, whose own
    # config names the event, draws a timer edge, red.
    test "only blocks the palette resolved take part" do
      root =
        Block.new("core.sequence",
          id: "root",
          slots: %{
            "body" => [
              delayed("live", "loan.due", "7d"),
              Block.new("core.await",
                id: "odd",
                type_version: 99,
                config: %{"event" => "loan.due"}
              )
            ]
          }
        )

      refute Enum.any?(outline(Document.new(root)).edges, &(&1.kind == :timer))
    end
  end

  describe "the phrasing seam for a timer edge" do
    defmodule TimerHost do
      @behaviour StatifierBlocks.Describe.Phrasing

      @impl true
      def timer(%Edge{delay: delay, event: event}, _default),
        do: "#{event} is armed #{delay} ahead"
    end

    # Sabotage: in `Describe.render/2`, phrase edges with `:interrupt` for
    # every kind -> `timer/2` is never asked, the default line stays, red.
    test "timer/2 rewords the timer edge's line, and only that line" do
      described =
        outline(decode!(Path.join(@documents, "patron_registration.json")))

      defaults = Describe.render(described, [])
      reworded = Describe.render(described, phrasing: TimerHost)

      assert List.last(reworded) == "registration.deadline is armed 24h ahead"
      assert Enum.drop(reworded, -1) == Enum.drop(defaults, -1)
    end
  end

  describe "the phrasing seam" do
    defmodule Host do
      @behaviour StatifierBlocks.Describe.Phrasing

      @impl true
      def step(%Node{id: "send"}, _default), do: "Tell the patron the loan is overdue"
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
      "Run its steps in order",
      "Wait 14d",
      "Send loan.overdue",
      "The steps start with Wait 14d",
      "After Wait 14d (done), Send loan.overdue",
      "Send loan.overdue (done) ends the steps"
    ]

    defp described do
      Block.new("core.sequence",
        id: "root",
        slots: %{
          "body" => [
            Block.new("core.wait", id: "wait", config: %{"duration" => "14d"}),
            Block.new("core.send", id: "send", config: %{"event" => "loan.overdue"})
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
               "Run its steps in order",
               "Wait 14d",
               "Tell the patron the loan is overdue",
               "It begins with a pause.",
               "After Wait 14d (done), Send loan.overdue",
               "Send loan.overdue (done) ends the steps"
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

  describe "a palette's document validators" do
    # A validator that records each call by messaging the calling process -
    # the side effect the moduledoc says the describe cannot prevent - and
    # answers a finding on the root and one on the document.
    defmodule Recorder do
      @behaviour StatifierBlocks.DocumentValidator

      @impl true
      def validate_document(%Document{root: root} = document) do
        send(self(), {:validated, document.id})
        [{{:block, root.id}, "recorded"}, {:document, "recorded"}]
      end
    end

    # Sabotage: in `Describe.outline/3`, build the view model with
    # `%{palette | validators: []}` -> the recorder is never called, red.
    test "outline/3 runs them, and the outline is the same with or without them" do
      palette =
        Palette.new(Palette.core_types(), recipes: Palette.core_recipes(), validators: [Recorder])

      for document <- [
            decode!(@library_loan)
            | Enum.map(0..19, &DocumentGenerator.generate(20_260_928, &1))
          ] do
        id = document.id
        with_validator = Describe.outline(document, palette, [])

        assert_received {:validated, ^id}
        assert with_validator == outline(document)
        assert Describe.render(with_validator, []) == document |> outline() |> Describe.render([])
      end
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

    # An allowlist, not a denylist: every module the compiled modules call
    # into is named here, so a call into anything else - a bare `:erlang`
    # process primitive included - fails the test until it is added here
    # on purpose. The modules below reach no network, clock, process,
    # random source or model of their own.
    @allowed_modules [
      ArgumentError,
      Enum,
      Exception,
      Keyword,
      List,
      Map,
      String,
      String.Chars,
      StatifierBlocks.BlockType,
      StatifierBlocks.Core.Duration,
      StatifierBlocks.Core.Send,
      StatifierBlocks.Palette,
      StatifierBlocks.Shelf,
      StatifierBlocks.ViewModel,
      :elixir_erl_pass,
      :lists
    ]

    # Modules that hold both pure functions and ones that reach a process,
    # allowed one function at a time. `Code.ensure_loaded?/1` loads a host's
    # phrasing module through the code server when it is not yet loaded,
    # the one call the moduledoc names.
    @allowed_functions %{
      :erlang => ~w(++ =/= =:= error function_exported get_module_info tl)a,
      Code => [:ensure_loaded?],
      Kernel => [:inspect]
    }

    # Sabotage: in `Describe.render/2`, read the option as
    # `Keyword.get(opts, :phrasing, length(:erlang.processes()) && nil)` ->
    # the import table names `{:erlang, :processes, 0}`, off the list, red.
    test "the compiled modules import nothing that reaches one" do
      for module <- @modules do
        # Read from the file on disk: under coverage the loaded module is
        # cover-compiled and `:code.which/1` names no file.
        beam = Application.app_dir(:statifier_blocks, "ebin/#{module}.beam")

        {:ok, {^module, [imports: imports]}} =
          beam |> String.to_charlist() |> :beam_lib.chunks([:imports])

        offending =
          Enum.reject(imports, fn {mod, fun, _arity} ->
            mod in @allowed_modules or fun in Map.get(@allowed_functions, mod, [])
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
