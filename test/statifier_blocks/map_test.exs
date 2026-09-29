defmodule StatifierBlocks.MapTest do
  @moduledoc """
  The Map's graph, read without laying it out: it is the document, every
  empty slot is marked, the options that keep the model order are where
  the moduledoc says they are, and for the two teaching documents it is
  what the reference host's map answered before it moved here.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.Block
  alias StatifierBlocks.Core.Branch
  alias StatifierBlocks.Core.Duration
  alias StatifierBlocks.Core.Group
  alias StatifierBlocks.Core.ResumableGroup
  alias StatifierBlocks.Describe
  alias StatifierBlocks.Describe.Edge
  alias StatifierBlocks.Document
  alias StatifierBlocks.Map, as: BlockMap
  alias StatifierBlocks.MapFixtures
  alias StatifierBlocks.Palette
  alias StatifierBlocks.ViewModel
  alias StatifierBlocks.ViewModel.Node

  @force "org.eclipse.elk.layered.crossingMinimization.forceNodeModelOrder"
  @consider "org.eclipse.elk.layered.considerModelOrder.strategy"

  describe "the reference host's graph" do
    # The move changes nothing the graph answers: for each teaching
    # document, the package's graph under the library world's words is the
    # JSON value the reference host's map module answered at the commit the
    # fixtures were copied from, less what the package has changed since:
    # the clock mark on the library loan's timed wait (see MapFixtures).
    #
    # Sabotage: made @body_lead 47; this went red. Reverted from a copy.
    test "each teaching document's graph is the reference host's" do
      for key <- MapFixtures.keys() do
        assert graph(key) == MapFixtures.host_graph!(key), key
      end
    end
  end

  describe "the graph is the document" do
    # A drafts shelf is drawn at the foot of its slot, where the outline
    # visits it; the document written here carries one.
    #
    # Sabotage: made slot_children/2 draw only the flow, dropping the shelf;
    # this went red. Reverted from a copy.
    test "every fixture's graph holds the outline's blocks, once each, in reading order" do
      for {key, view_model} <- [{"shelf", shelf_view_model()} | view_models()] do
        outline_ids =
          for {%Node{block_id: id}, _depth, _kind} <- ViewModel.outline(view_model), do: id

        assert BlockMap.nodes(BlockMap.graph(view_model)) == outline_ids, key
      end
    end

    # The library world's two branches, arm by arm: every arm a slot node of
    # its own, in the order the branch evaluates them, the empty one
    # included.
    #
    # Sabotage: made drawn_slots/1 drop a body slot with no children; this
    # went red. Reverted from a copy.
    test "a branch draws every arm it declares, in slot order" do
      assert slot_ids(graph("library_loan"), "blk_ll_due") == [
               "blk_ll_due/arm_returned",
               "blk_ll_due/arm_renew",
               "blk_ll_due/otherwise",
               "blk_ll_due/undecided"
             ]

      assert slot_ids(graph("patron_registration"), "blk_pr_age") == [
               "blk_pr_age/arm_child",
               "blk_pr_age/arm_adult",
               "blk_pr_age/otherwise",
               "blk_pr_age/undecided"
             ]
    end
  end

  describe "the input" do
    # The host's selection marks the one block it names and changes nothing
    # else: every block of every fixture, selected in turn, answers the
    # unselected graph with `"selected" => true` on that block's node alone.
    #
    # Sabotage: made put_selected/2 mark every block; this went red.
    # Reverted from a copy.
    test "a selection changes nothing but the marked node" do
      for {key, view_model} <- view_models() do
        plain = BlockMap.graph(view_model)

        for id <- BlockMap.nodes(plain) do
          selected = BlockMap.graph(view_model, selected: id)

          assert for(%{"selected" => true, "id" => marked} <- walk(selected), do: marked) == [id],
                 "#{key}: #{id}"

          assert unmark(selected) == plain, "#{key}: #{id}"
        end
      end
    end

    # Sabotage: made put_selected/2 mark any node the id names, not only a
    # block; this went red. Reverted from a copy.
    test "a selection naming no block marks nothing" do
      view_model = MapFixtures.view_model!("library_loan")
      plain = BlockMap.graph(view_model)

      for id <- ["blk_ll_due/undecided", "blk_ll_due/undecided/empty", "blk_ll_root/start", nil] do
        assert BlockMap.graph(view_model, selected: id) == plain, inspect(id)
      end
    end

    # A host that passes no words draws every sentence exactly as the
    # package writes it.
    #
    # Sabotage: made Phrasing.none/1 answer words for every name; this went
    # red. Reverted from a copy.
    test "with no phrase, a box's line is the package's sentence" do
      for {key, view_model} <- view_models() do
        for %{"kind" => "block", "id" => id, "lines" => [_ | _] = lines} = node <-
              walk(BlockMap.graph(view_model)),
            not Map.has_key?(node, "children") do
          sentence = view_model |> ViewModel.find_node(id) |> ViewModel.sentence()
          assert Enum.join(lines, " ") == sentence, "#{key}: #{id}"
        end
      end
    end

    # The graph is built from the view model alone: it takes no document,
    # and no box carries a position. The one coordinate in it is a port's
    # fixed attachment point on its group's side, which the layout reads
    # and never moves.
    #
    # Sabotage: gave end_mark/2 an "x"; this went red. Reverted from a copy.
    test "the graph takes a view model, and no box carries a position" do
      assert_raise FunctionClauseError, fn ->
        BlockMap.graph(MapFixtures.document!("library_loan"))
      end

      for {key, view_model} <- view_models(),
          node <- walk(BlockMap.graph(view_model)),
          ports = Map.get(node, "ports", []) do
        refute Map.has_key?(node, "x") or Map.has_key?(node, "y"), "#{key}: #{node["id"]}"
        for port <- ports, do: assert(%{"y" => 0, "width" => 0, "height" => 0} = port)
      end
    end
  end

  describe "empty slots are marked, not hidden" do
    # Derived rather than listed: every slot in the view model with nothing
    # in it is one marker in the graph, and nothing else is.
    #
    # Sabotage: made slot/3 draw no marker for an empty slot; this went red.
    # Reverted from a copy.
    test "every empty slot of every fixture is exactly one marker" do
      for {key, view_model} <- view_models() do
        expected =
          for {%Node{block_id: id, slots: slots}, _depth, _kind} <- ViewModel.outline(view_model),
              %{name: name, children: []} <- slots,
              do: "#{id}/#{name}/empty"

        assert Enum.sort(markers(BlockMap.graph(view_model))) == Enum.sort(expected), key
      end
    end

    test "each library fixture marks the one arm its author left empty" do
      assert markers(graph("library_loan")) == ["blk_ll_due/undecided/empty"]
      assert markers(graph("patron_registration")) == ["blk_pr_age/otherwise/empty"]

      assert %{"title" => title} = find(graph("library_loan"), "blk_ll_due/undecided/empty")
      assert title == BlockMap.empty_text()
      assert BlockMap.empty_text() == "Nothing here yet"
    end
  end

  describe "what is and is not an edge" do
    # A group's interrupt rules each watch the whole body; joining them
    # would draw them as steps that run one after another.
    #
    # Sabotage: made flow_edges/1 answer sequence_edges/1 for every slot;
    # this went red. Reverted from a copy.
    test "a rail's blocks are not joined" do
      for {key, rail} <- [
            {"library_loan", "blk_ll_on_loan/interrupts"},
            {"patron_registration", "blk_pr_verify/interrupts"}
          ] do
        assert %{"edges" => [], "children" => [_first, _second]} = find(graph(key), rail)
      end
    end

    # The words said once are an Invoke's, whose type declares no sentence
    # and falls back to its label.
    #
    # Sabotage: made under/2 always wrap; this went red. Reverted from a
    # copy.
    test "a sentence that only repeats the title is not drawn twice" do
      graph = graph("library_loan")

      assert %{"title" => "Sequence", "lines" => ["Run its steps in order"]} =
               find(graph, "blk_ll_root")

      assert %{"title" => "Wait", "lines" => ["Wait 21d"]} = find(graph, "blk_ll_loan_period")

      assert %{"title" => "Invoke", "lines" => []} =
               find(BlockMap.graph(invoke_view_model()), "hold")
    end
  end

  describe "captions" do
    # A group's rules column and a branch carry the caption for their type,
    # and nothing else on the map carries one: not the Invoke's failure
    # rail either.
    #
    # Sabotage: made put_band/2 leave the caption off; this went red.
    # Reverted from a copy.
    test "only a group's rules column and a branch carry a caption" do
      for {key, view_model} <- [{"invoke", invoke_view_model()} | view_models()] do
        graph = BlockMap.graph(view_model)

        expected =
          for node <- walk(graph),
              node["kind"] == "block",
              type = ViewModel.find_node(view_model, node["id"]).type,
              BlockMap.caption(type) != nil,
              into: %{} do
            if node["band"],
              do: {node["id"], BlockMap.caption(type)},
              else: {"#{node["id"]}/interrupts", BlockMap.caption(type)}
          end

        captioned =
          for node <- walk(graph), node["caption"], into: %{}, do: {node["id"], node["caption"]}

        assert captioned == expected, key
      end
    end

    # A caption is the type's own explanation - the first sentence of
    # `BlockType.explain/1` - on one line: whole where it fits, cut at a
    # word and ended with "..." where it does not. Only a branch and the
    # two groups have one; a leaf never does.
    #
    # Sabotage: made caption/1 answer the whole paragraph; this went red.
    # Reverted from a copy.
    test "a caption is the first sentence of the type's explanation, on one line" do
      per_line = div(260 - 24, 7)

      assert BlockMap.caption("core.branch") == "A branch picks one path."
      assert String.starts_with?(Branch.explain(), "A branch picks one path. ")

      for {type, module} <- [
            {"core.group", Group},
            {"core.resumable_group", ResumableGroup}
          ] do
        caption = BlockMap.caption(type)
        [sentence | _rest] = String.split(module.explain(), ". ", parts: 2)
        cut = String.trim_trailing(caption, "...")

        assert String.length(caption) <= per_line, type
        assert String.ends_with?(caption, "..."), type
        assert String.starts_with?(sentence <> " ", cut <> " "), type
      end

      for type <- ["core.send", "core.await", "core.on_event", "core.sequence", "myapp.intake"],
          do: assert(BlockMap.caption(type) == nil, type)
    end

    # A branch's `caption_width` is the fork mark's 26px room plus its
    # caption at the map's estimate, and the branch is held that wide plus
    # its padding. A branch with no condition arm draws only its two
    # standing arms, so its header is narrower than its caption, and the
    # caption is what sets its least width.
    #
    # Sabotage: made band_width/1 leave out @fork_room; this went red. Made
    # the branch's `least:` 0; this went red. Each reverted from a copy.
    test "a branch's caption sets its least width when it is wider than its header" do
      branch = Block.new("core.branch", id: "shelve", config: %{"arms" => []})

      graph =
        Block.new("core.sequence", id: "root", slots: %{"body" => [branch]})
        |> Document.new()
        |> build()
        |> BlockMap.graph()

      node = find(graph, "shelve")
      caption = BlockMap.caption("core.branch")
      caption_room = 26 + String.length(caption) * 7 + 24

      header_room =
        ([node["title"] | node["lines"]] |> Enum.map(&String.length/1) |> Enum.max()) * 7 + 24

      assert node["caption"] == caption
      assert node["caption_width"] == caption_room
      assert header_room < caption_room

      [_height, width] =
        Regex.run(
          ~r/^\((\d+),(\d+)\)$/,
          node["layoutOptions"]["org.eclipse.elk.nodeSize.minimum"],
          capture: :all_but_first
        )

      assert String.to_integer(width) == caption_room + 2 * 12
    end
  end

  describe "event names in words" do
    # The two teaching documents, under the library world's words, draw
    # their event names as words.
    #
    # Sabotage: made block/2 draw ViewModel.sentence/1 unphrased; this went
    # red. Reverted from a copy.
    test "a box's line reads the host's event names as words" do
      loan = graph("library_loan")
      assert find(loan, "blk_ll_close")["lines"] == ["Send word that the loan is closed"]

      assert find(loan, "blk_ll_late_return")["lines"] |> Enum.join(" ") =~
               "Wait until the copy is returned"

      for key <- MapFixtures.keys(),
          node <- walk(graph(key)),
          line <- Map.get(node, "lines", []),
          event <- ~w(copy.returned loan.closed registration.deadline email.verified) do
        refute line =~ event, "#{key}: #{node["id"]} draws #{event} as a name"
      end
    end
  end

  describe "sizes" do
    # A word longer than a line keeps its own line, whole, and widens its
    # box to fit rather than running out of it.
    #
    # Sabotage: capped leaf_width/1 at 260; this went red. Reverted from a
    # copy.
    test "a leaf is as wide as its longest word needs" do
      event = "patron.registration.second_reminder_after_the_first_week"

      root =
        Block.new("core.sequence",
          id: "root",
          slots: %{"body" => [Block.new("core.send", id: "long", config: %{"event" => event})]}
        )

      graph = root |> Document.new() |> ViewModel.build(Palette.core(), []) |> BlockMap.graph()
      leaf = find(graph, "long")

      assert event in leaf["lines"]
      assert leaf["width"] >= String.length(event) * 7 + 24
    end

    # The title is sized too, not only the sentence under it.
    #
    # No core type's own label outgrows a leaf's least width, so the case
    # that needs it is a view model whose send carries a long title of its
    # own over a short sentence.
    #
    # Sabotage: made the leaf clause size by leaf_width(lines) without the
    # title; this went red. Reverted from a copy.
    test "a leaf is at least as wide as its title" do
      for {_key, view_model} <- [{"titled", titled_view_model()} | view_models()],
          node <- walk(BlockMap.graph(view_model)),
          Map.has_key?(node, "width"),
          # The start dot and the end marks carry no text to be wide enough for.
          node["kind"] not in ["start", "end"] do
        assert node["width"] >= String.length(node["title"]) * 7 + 24, node["id"]
      end
    end
  end

  describe "interrupt edges and timer marks" do
    # The map reads its interrupt edges off the view model; Describe reads
    # them off the document. The two are held equal, rule for rule, so the
    # map cannot draw an interrupt the description does not say.
    #
    # Sabotage: made leads_to/1 answer "body" for an abandon rule; this went
    # red. Reverted from a copy.
    test "every fixture's interrupt edges are Describe's" do
      for {key, document} <- documents() do
        described =
          for %Edge{kind: :interrupt, from: {:block, rule}, to: {to, group}} <-
                Describe.outline(document, Palette.core(), []).edges do
            %{"from" => rule, "group" => group, "to" => Atom.to_string(to)}
          end

        assert BlockMap.interrupts(BlockMap.graph(build(document))) == described, key
      end
    end

    # The map's timer edges are the outline's `:timer` edges, for every
    # fixture: each delayed send to each rule or await naming its event,
    # in the outline's order, with the event and the delay.
    test "every fixture's timer edges are Describe's" do
      for {key, document} <- documents() do
        described =
          for %Edge{kind: :timer, from: {:block, from}, to: {:block, to}} = edge <-
                Describe.outline(document, Palette.core(), []).edges do
            %{"from" => from, "to" => to, "event" => edge.event, "delay" => edge.delay}
          end

        assert BlockMap.timers(BlockMap.graph(build(document))) == described, key
      end
    end

    # The registration's deadline send reaches the one rule that abandons
    # the registration on its event, seven days on.
    #
    # Sabotage: made timer/3 give the edge kind "sequence"; this went red.
    # Reverted from a copy.
    test "the registration's deadline send reaches its deadline rule" do
      assert BlockMap.timers(graph("patron_registration")) == [
               %{
                 "from" => "blk_pr_deadline",
                 "to" => "blk_pr_expired",
                 "event" => "registration.deadline",
                 "delay" => "7d"
               }
             ]

      assert [%{"kind" => "timer", "id" => "blk_pr_deadline->blk_pr_expired/timer"}] =
               graph("patron_registration")["timers"]

      assert BlockMap.timers(graph("library_loan")) == []
      refute Map.has_key?(graph("library_loan"), "timers")
    end

    # A send with no delay arms nothing for later, so it draws no timer
    # edge to the wait that names its event, while a delayed one does; the
    # outline agrees.
    #
    # Sabotage: made put_timers/2 pair every send, delayed or not; this went
    # red. Reverted from a copy.
    test "only a delayed send draws a timer edge" do
      heard = Block.new("core.await", id: "heard", config: %{"event" => "x.due"})

      root =
        Block.new("core.sequence",
          id: "root",
          slots: %{
            "body" => [
              Block.new("core.send", id: "now", config: %{"event" => "x.due"}),
              Block.new("core.send", id: "later", config: %{"event" => "x.due", "delay" => "1h"}),
              heard
            ]
          }
        )

      document = Document.new(root)
      graph = document |> build() |> BlockMap.graph()

      described =
        for %Edge{kind: :timer, from: {:block, from}, to: {:block, to}} <-
              Describe.outline(document, Palette.core(), []).edges,
            do: {from, to}

      assert described == [{"later", "heard"}]
      assert Enum.map(BlockMap.timers(graph), &{&1["from"], &1["to"]}) == described
    end

    # A delay of whitespace alone is not a duration: `delayed?/1` hands the
    # field to `Duration.duration?/1` as the form holds it, untrimmed, so
    # such a send carries no clock mark and draws no timer edge to the await
    # that names its event, and Describe's outline agrees.
    #
    # Sabotage: made delayed?/1 answer true for a delay of whitespace alone;
    # this went red. Reverted from a copy.
    test "a send whose delay is whitespace alone carries no clock and draws no timer edge" do
      root =
        Block.new("core.sequence",
          id: "root",
          slots: %{
            "body" => [
              Block.new("core.send",
                id: "reminder",
                config: %{"event" => "loan.overdue", "delay" => "   "}
              ),
              Block.new("core.await", id: "overdue", config: %{"event" => "loan.overdue"})
            ]
          }
        )

      document = Document.new(root)
      graph = document |> build() |> BlockMap.graph()

      assert marks(graph) == %{"overdue" => "wait"}
      assert BlockMap.timers(graph) == []
      refute Map.has_key?(graph, "timers")

      assert for(
               %Edge{kind: :timer} = edge <- Describe.outline(document, Palette.core(), []).edges,
               do: edge
             ) == []
    end

    # A send on the drafts shelf arms nothing, and neither is a rule there
    # heard: a shelved block takes part in no timer edge, as in Describe.
    #
    # Sabotage: made timer_parties/1 ignore the shelf; this went red.
    # Reverted from a copy.
    test "a delayed send or a rule on the drafts shelf draws no timer edge" do
      send = fn id ->
        Block.new("core.send", id: id, config: %{"event" => "x.due", "delay" => "1h"})
      end

      heard = Block.new("core.await", id: "heard", config: %{"event" => "x.due"})

      root =
        Block.new("core.sequence",
          id: "root",
          slots: %{
            "body" => [
              send.("live"),
              heard,
              Block.new("core.drafts", id: "shelf", slots: %{"body" => [send.("parked")]})
            ]
          }
        )

      document = Document.new(root)
      graph = document |> build() |> BlockMap.graph()

      described =
        for %Edge{kind: :timer, from: {:block, from}, to: {:block, to}} <-
              Describe.outline(document, Palette.core(), []).edges,
            do: {from, to}

      assert described == [{"live", "heard"}]
      assert Enum.map(BlockMap.timers(graph), &{&1["from"], &1["to"]}) == described
    end

    # Sabotage: made put_interrupts/2 take the group's last drawn child as
    # the head; this went red. Reverted from a copy.
    test "each library group's two rules leave it by its exit" do
      assert BlockMap.interrupts(graph("library_loan")) == [
               %{"from" => "blk_ll_returned_early", "group" => "blk_ll_on_loan", "to" => "exit"},
               %{"from" => "blk_ll_reported_lost", "group" => "blk_ll_on_loan", "to" => "exit"}
             ]

      assert BlockMap.interrupts(graph("patron_registration")) == [
               %{"from" => "blk_pr_abandoned", "group" => "blk_pr_verify", "to" => "exit"},
               %{"from" => "blk_pr_expired", "group" => "blk_pr_verify", "to" => "exit"}
             ]

      assert [%{"kind" => "interrupt", "head" => "blk_pr_deadline"} | _rest] =
               find(graph("patron_registration"), "blk_pr_verify")["interrupts"]
    end

    # A resume rule goes back to the head of the group's body. Neither
    # library fixture has one, so a group written here carries the case.
    #
    # Sabotage: made put_interrupts/2 take the pane itself, not its first,
    # as the head; this went red. Reverted from a copy.
    test "a resume rule leads to the head of its group's body" do
      graph = BlockMap.graph(resume_view_model())

      assert [%{"from" => "renew", "group" => "held", "to" => "body"}] =
               BlockMap.interrupts(graph)

      node = find(graph, "held")
      # The body is the group's first child, a pane; its head is the pane's first.
      assert [%{"style" => "body", "children" => [%{"id" => "notice"} | _steps]} | _rest] =
               node["children"]

      assert [%{"kind" => "interrupt", "to" => "body", "head" => "notice"}] = node["interrupts"]
    end

    # Sabotage: made mark/1 answer nil for core.await; this went red.
    # Reverted from a copy.
    test "the library fixtures mark every await, the wait and the one delayed send, and no other" do
      assert marks(graph("library_loan")) == %{
               "blk_ll_late_return" => "wait",
               "blk_ll_loan_period" => "clock"
             }

      assert marks(graph("patron_registration")) == %{
               "blk_pr_deadline" => "clock",
               "blk_pr_email" => "wait",
               "blk_pr_guardian" => "wait"
             }
    end

    # Derived rather than listed: every await in every fixture carries the
    # wait mark, every wait the clock mark, every send the clock mark
    # exactly when its delay is set, and no other block carries a mark.
    test "every fixture marks its awaits, its waits and its delayed sends, and nothing else" do
      for {key, view_model} <- view_models() do
        expected =
          for {%Node{} = node, _depth, _kind} <- ViewModel.outline(view_model),
              mark = expected_mark(node),
              into: %{},
              do: {node.block_id, mark}

        assert marks(BlockMap.graph(view_model)) == expected, key
      end
    end

    # The mark sits level with the title, so the title leaves it room. No
    # core type's own label is long enough to need it, so the case is a
    # view model whose await carries a long title of its own.
    #
    # Sabotage: dropped the title-plus-mark term from put_mark/4's width;
    # this went red. Reverted from a copy.
    test "a marked leaf is wide enough for its title and its mark" do
      title = "Wait for the patron to collect the copy from the hold shelf"

      root =
        Block.new("core.sequence",
          id: "root",
          slots: %{
            "body" => [
              Block.new("core.await", id: "held", config: %{"event" => "hold.collected"})
            ]
          }
        )

      view_model = root |> Document.new() |> build()
      [%{children: [await]} = body] = view_model.root.slots
      titled = %{body | children: [%{await | title: title}]}
      view_model = %{view_model | root: %{view_model.root | slots: [titled]}}

      assert %{"mark" => "wait", "title" => ^title, "width" => width} =
               find(BlockMap.graph(view_model), "held")

      assert width >= String.length(title) * 7 + 24 + 22
    end

    # A timed wait carries the clock, as a delayed send does, and not the
    # hourglass an await carries. The clock is a mark only: the send's
    # timer edge still runs to the await that hears its event, and nothing
    # runs to the wait.
    #
    # Sabotage: made mark/1 answer "wait" for core.wait; this went red.
    # Reverted from a copy.
    test "a wait carries the clock mark and hears no timer edge" do
      root =
        Block.new("core.sequence",
          id: "root",
          slots: %{
            "body" => [
              Block.new("core.send",
                id: "reminder",
                config: %{"event" => "loan.overdue", "delay" => "21d"}
              ),
              Block.new("core.wait", id: "loan_period", config: %{"duration" => "21d"}),
              Block.new("core.await", id: "overdue", config: %{"event" => "loan.overdue"})
            ]
          }
        )

      graph = root |> Document.new() |> build() |> BlockMap.graph()

      assert marks(graph) == %{
               "reminder" => "clock",
               "loan_period" => "clock",
               "overdue" => "wait"
             }

      assert Enum.map(BlockMap.timers(graph), &{&1["from"], &1["to"]}) == [
               {"reminder", "overdue"}
             ]
    end
  end

  describe "the options that keep the model order" do
    # Sabotage: dropped @force_model_order from container_options/4; this
    # went red. Reverted from a copy.
    test "forceNodeModelOrder is on every container" do
      for {key, view_model} <- view_models() do
        for container <- containers(BlockMap.graph(view_model)) do
          assert container["layoutOptions"][@force] == "true",
                 "#{key}: #{container["id"]} does not force the model order"
        end
      end
    end

    # Sabotage: added @consider_model_order to container_options/4; this
    # went red. Reverted from a copy.
    test "considerModelOrder is on the root and on nothing else" do
      for {key, view_model} <- view_models() do
        graph = BlockMap.graph(view_model)

        assert graph["layoutOptions"][@consider] == "NODES_AND_EDGES"

        for container <- containers(graph), container["id"] != "plan-map" do
          refute Map.has_key?(container["layoutOptions"], @consider),
                 "#{key}: #{container["id"]} carries considerModelOrder"
        end
      end
    end

    # Sabotage: reversed ViewModel.flow_children/1 in slot_children/2; this
    # went red. Reverted from a copy.
    test "a container lists its children in model order, and sequence edges follow it" do
      body = find(graph("patron_registration"), "blk_pr_verify/body")

      assert Enum.map(body["children"], & &1["id"]) == [
               "blk_pr_deadline",
               "blk_pr_email",
               "blk_pr_age",
               "blk_pr_welcome"
             ]

      assert Enum.map(body["edges"], &{&1["sources"], &1["targets"], &1["kind"]}) == [
               {["blk_pr_deadline"], ["blk_pr_email"], "sequence"},
               {["blk_pr_email"], ["blk_pr_age"], "sequence"},
               {["blk_pr_age"], ["blk_pr_welcome"], "rejoin"}
             ]
    end
  end

  describe "the happy path" do
    # A group whose body is all leaves attaches its edges at a fixed point
    # on its top and bottom sides: its and its pane's padding (12 each)
    # plus half its widest step. A group whose body holds a container has
    # no width to read and carries no ports: the registration's group
    # holds its age branch in its body.
    #
    # Sabotage: made put_ports/2 count one padding, not two; this went red.
    # Reverted from a copy.
    test "a group of leaves carries its two ports where its steps stand, and no other does" do
      on_loan = find(graph("library_loan"), "blk_ll_on_loan")
      x = 12 + 12 + 150 / 2

      assert on_loan["layoutOptions"]["org.eclipse.elk.portConstraints"] == "FIXED_POS"

      assert [
               %{"id" => "blk_ll_on_loan#in", "x" => ^x, "layoutOptions" => north},
               %{"id" => "blk_ll_on_loan#out", "x" => ^x, "layoutOptions" => south}
             ] = on_loan["ports"]

      assert north == %{"org.eclipse.elk.port.side" => "NORTH"}
      assert south == %{"org.eclipse.elk.port.side" => "SOUTH"}

      group = find(graph("patron_registration"), "blk_pr_verify")
      refute Map.has_key?(group, "ports")
      refute Map.has_key?(group["layoutOptions"], "org.eclipse.elk.portConstraints")

      for {key, view_model} <- view_models(),
          node <- walk(BlockMap.graph(view_model)),
          Map.has_key?(node, "ports") do
        assert [%{"style" => "body"} | _rest] = node["children"], key
      end
    end
  end

  describe "the Branch" do
    # The header is the map's own; the branch type's sentence, which the
    # list draws, is what it was.
    #
    # Sabotage: made arm_lines/1 reverse the arms; this went red. Reverted
    # from a copy.
    test "a branch's header names every arm, and its sentence is unchanged" do
      for {key, id, sentence, arms} <- [
            {"library_loan", "blk_ll_due", ~s(Decide: When "returned", otherwise),
             [~s(When "returned"), ~s(When "renew"), "Otherwise", "Cannot be decided"]},
            {"patron_registration", "blk_pr_age", ~s(Decide: When "child", otherwise),
             [~s(When "child"), ~s(When "adult"), "Otherwise", "Cannot be decided"]}
          ] do
        node = ViewModel.find_node(MapFixtures.view_model!(key), id)
        assert ViewModel.sentence(node) == sentence

        assert %{"band" => true, "lines" => lines} = find(graph(key), id)
        header = Enum.join(lines, " ")

        positions =
          for {label, n} <- Enum.with_index(arms, 1) do
            assert {at, _len} = :binary.match(header, "#{n}. #{label}")
            at
          end

        assert positions == Enum.sort(positions), key
      end
    end

    # Only a branch carries a band, and only the edge out of a branch is a
    # rejoin.
    #
    # Sabotage: made put_band/2 band every container; this went red.
    # Reverted from a copy.
    test "every fixture bands only its branches and rejoins only out of them" do
      for {key, view_model} <- view_models() do
        graph = BlockMap.graph(view_model)

        branches =
          for {%Node{type: "core.branch", block_id: id}, _depth, _kind} <-
                ViewModel.outline(view_model),
              do: id

        assert Enum.sort(for(%{"band" => true, "id" => id} <- walk(graph), do: id)) ==
                 Enum.sort(branches),
               key

        for %{"edges" => edges} <- walk(graph),
            %{"kind" => kind, "sources" => [from], "targets" => [to]} <- edges do
          expected =
            cond do
              String.ends_with?(from, "/start") -> "start"
              from in branches -> "rejoin"
              String.contains?(to, "/end/") -> "end"
              true -> "sequence"
            end

          assert kind == expected, "#{key}: #{from}"
        end
      end
    end
  end

  describe "the end" do
    # Every end of every fixture's own flow is one of the outline's: a
    # `done` end for the `:exit` edge from the root's last step into the
    # root's exit, and an `abandon` end where that step is a group one of
    # whose rules abandons it. `done` is the outline's own outcome for the
    # root, which is why the map may write it rather than read it. No end
    # mark is a block.
    #
    # Sabotage: made put_ends/2 draw no end; this went red. Reverted from a
    # copy.
    test "every fixture's ends are Describe's, one per way it finishes" do
      for {key, document} <- documents() do
        view_model = build(document)
        graph = BlockMap.graph(view_model)
        outline = Describe.outline(document, Palette.core(), [])
        root = view_model.root.block_id

        done =
          for %Edge{kind: :exit, container: ^root, from: {:block, last}} <- outline.edges,
              do: {last, "done"}

        abandon =
          for {last, "done"} <- done,
              %Edge{kind: :interrupt, container: ^last, to: {:exit, ^last}} <- outline.edges,
              uniq: true,
              do: {last, "abandon"}

        drawn =
          for node <- walk(graph),
              %{"sources" => [from], "targets" => [to], "outcome" => outcome} <-
                Map.get(node, "edges", []),
              do: {from, outcome, to}

        assert Enum.map(drawn, fn {from, outcome, _to} -> {from, outcome} end) ==
                 done ++ abandon,
               key

        refute done == [], key
        assert %Describe.Node{outcomes: ["done"]} = Enum.find(outline.nodes, &(&1.id == root))

        for {_from, outcome, to} <- drawn do
          assert to == "#{root}/end/#{outcome}"
          assert %{"kind" => "end", "outcome" => ^outcome} = find(graph, to)
          refute to in BlockMap.nodes(graph)
        end
      end
    end

    # The loan finishes when its branch does: the branch rejoins into one
    # solid end. The registration's group is its last step and its rules
    # abandon it, so it finishes done or abandoned: two ends, the edge into
    # each captioned with its outcome.
    #
    # Sabotage: made end_edge/4 caption every edge "done"; this went red.
    # Reverted from a copy.
    test "the loan ends done after its branch, the registration done or abandoned" do
      root = find(graph("library_loan"), "blk_ll_root")

      assert Enum.map(root["children"], & &1["id"]) ==
               ["blk_ll_root/start", "blk_ll_on_loan", "blk_ll_due", "blk_ll_root/end/done"]

      assert %{"kind" => "end", "outcome" => "done"} = done = List.last(root["children"])
      refute Map.has_key?(done, "title")

      assert List.last(root["edges"]) == %{
               "id" => "blk_ll_due->blk_ll_root/end/done",
               "sources" => ["blk_ll_due"],
               "targets" => ["blk_ll_root/end/done"],
               "kind" => "rejoin",
               "outcome" => "done",
               "labels" => [
                 %{
                   "id" => "blk_ll_due->blk_ll_root/end/done/caption",
                   "text" => "done",
                   "width" => 52,
                   "height" => 16
                 }
               ]
             }

      root = find(graph("patron_registration"), "blk_pr_root")

      assert Enum.map(root["children"], & &1["id"]) ==
               [
                 "blk_pr_root/start",
                 "blk_pr_verify",
                 "blk_pr_root/end/done",
                 "blk_pr_root/end/abandon"
               ]

      assert [
               %{"kind" => "end", "outcome" => "done", "labels" => [%{"text" => "done"}]},
               %{"kind" => "end", "outcome" => "abandon", "labels" => [%{"text" => "abandon"}]}
             ] = Enum.filter(root["edges"], &Map.has_key?(&1, "outcome"))

      assert Enum.map(Enum.filter(root["edges"], &Map.has_key?(&1, "outcome")), & &1["sources"]) ==
               [["blk_pr_verify"], ["blk_pr_verify"]]
    end

    # A group whose rules only resume it is never left by them, so it ends
    # the document done and nothing else; a group of abandon rules adds the
    # one abandon end however many rules there are.
    #
    # Sabotage: made abandons/1 read every rule as an abandon; this went
    # red. Reverted from a copy.
    test "only an abandon rule adds an abandon end, once" do
      for {outcomes, ends} <- [
            {["resume"], ["done"]},
            {["abandon", "abandon"], ["done", "abandon"]},
            {["resume", "abandon"], ["done", "abandon"]}
          ] do
        rules =
          for {outcome, n} <- Enum.with_index(outcomes),
              do:
                Block.new("core.on_event",
                  id: "rule#{n}",
                  config: %{"event" => "e#{n}", "outcome" => outcome}
                )

        group =
          Block.new("core.group",
            id: "held",
            slots: %{
              "body" => [Block.new("core.send", id: "s", config: %{"event" => "x"})],
              "interrupts" => rules
            }
          )

        root = Block.new("core.sequence", id: "root", slots: %{"body" => [group]})
        graph = root |> Document.new() |> build() |> BlockMap.graph()

        assert for(%{"kind" => "end", "outcome" => outcome} <- walk(graph), do: outcome) == ends,
               inspect(outcomes)
      end
    end

    # A step that is last in a nested flow hands back to the block around
    # it, which goes on: no end follows it. Every Send in the two library
    # fixtures is such a step - at the foot of an arm or of the
    # registration's body - and none is joined to an end; every end is
    # joined to the root's last step alone.
    #
    # Sabotage: made put_ends/2 join the ends to the first step of the
    # root's flow; this went red. Reverted from a copy.
    test "a send that continues is followed by no end" do
      for {key, view_model} <- view_models() do
        graph = BlockMap.graph(view_model)

        sends =
          for {%Node{type: "core.send", block_id: id}, _depth, _kind} <-
                ViewModel.outline(view_model),
              do: id

        refute sends == [], key

        [last | _rest] =
          view_model.root
          |> ViewModel.body_slots()
          |> hd()
          |> ViewModel.flow_children()
          |> Enum.reverse()

        into_ends =
          for node <- walk(graph),
              %{"sources" => [from], "targets" => [to]} <- Map.get(node, "edges", []),
              String.contains?(to, "/end/"),
              do: from

        refute into_ends == [], key
        assert Enum.uniq(into_ends) == [last.block_id], key
        for send <- sends, do: refute(send in into_ends, "#{key}: #{send}")
      end
    end
  end

  describe "the start" do
    # One start dot per document, first among the root's children, and one
    # start edge from it into the first step of the root's own flow,
    # captioned with the one sentence - whether the document declares the
    # events it accepts (the library fixtures) or declares none (the
    # document written here). The dot is no block: it is in no outline.
    #
    # Sabotage: made put_start/2 aim the edge at the root instead of the
    # first step; this went red. Reverted from a copy.
    test "every fixture starts once, with one captioned edge into its first step" do
      assert BlockMap.start_text() == "Starts when told to"

      documents = [{"no accepts", no_accepts_document()} | documents()]
      accepts = for {_key, document} <- documents, do: document.accepts != []
      assert true in accepts and false in accepts

      for {key, document} <- documents do
        view_model = build(document)
        graph = BlockMap.graph(view_model)
        root_id = view_model.root.block_id
        start = "#{root_id}/start"

        [%{block_id: first} | _rest] =
          view_model.root |> ViewModel.body_slots() |> hd() |> ViewModel.flow_children()

        assert [%{"id" => ^start, "kind" => "start"} = dot] =
                 Enum.filter(walk(graph), &(&1["kind"] == "start")),
               key

        refute Map.has_key?(dot, "title")
        assert [^dot | _rest] = find(graph, root_id)["children"]

        edges = for node <- walk(graph), edge <- Map.get(node, "edges", []), do: edge

        assert [
                 %{
                   "sources" => [^start],
                   "targets" => [^first],
                   "labels" => [%{"text" => "Starts when told to"}]
                 }
               ] = Enum.filter(edges, &(&1["kind"] == "start"))

        refute start in BlockMap.nodes(graph)
      end
    end

    # A document with no step yet starts into its root's empty marker.
    #
    # Sabotage: made put_start/2 fall back to the root, not the first drawn
    # child; this went red. Reverted from a copy.
    test "a document with no step starts into its empty slot" do
      graph =
        Block.new("core.sequence", id: "root", slots: %{"body" => []})
        |> Document.new()
        |> build()
        |> BlockMap.graph()

      root = find(graph, "root")

      assert [%{"id" => "root/start"}, %{"id" => "root/body/empty"}] = root["children"]

      assert [%{"sources" => ["root/start"], "targets" => ["root/body/empty"]}] =
               root["edges"]
    end

    # A root whose flow is not drawn inside it - a group, whose body is a
    # pane of its own - has its dot above its box and its edge into the box.
    #
    # Sabotage: dropped the inline? check from put_start/2; this went red.
    # Reverted from a copy.
    test "a root whose flow is not drawn inside it starts above its box" do
      graph =
        Block.new("core.group",
          id: "held",
          slots: %{
            "body" => [
              Block.new("core.await", id: "wait", config: %{"event" => "hold.collected"})
            ],
            "interrupts" => []
          }
        )
        |> Document.new()
        |> build()
        |> BlockMap.graph()

      assert [%{"id" => "held/start", "kind" => "start"}, %{"id" => "held"}] = graph["children"]

      assert [%{"sources" => ["held/start"], "targets" => ["held"], "kind" => "start"}] =
               graph["edges"]

      refute Enum.any?(find(graph, "held")["children"], &(&1["kind"] == "start"))
    end
  end

  # Sabotage: made sequence_edges/1 carry its source as a tuple; the encoder
  # refused it and this went red. Reverted from a copy.
  test "the graph encodes to JSON for the hook" do
    for {_key, view_model} <- view_models() do
      assert {:ok, _json} = encode(BlockMap.graph(view_model, selected: "blk_ll_due"))
    end
  end

  # ------------------------------------------------------------------ helpers

  # The graph's JSON, or the error the encoder raised on a term JSON has no
  # form for.
  defp encode(term) do
    {:ok, JSON.encode!(term)}
  rescue
    error -> {:error, error}
  end

  defp build(%Document{} = document), do: ViewModel.build(document, Palette.core(), [])

  defp documents, do: for(key <- MapFixtures.keys(), do: {key, MapFixtures.document!(key)})

  defp view_models, do: for({key, document} <- documents(), do: {key, build(document)})

  defp graph(key),
    do: BlockMap.graph(MapFixtures.view_model!(key), phrase: &MapFixtures.phrase/1)

  # A notice whose block carries a title longer than its sentence.
  defp titled_view_model do
    view_model =
      Block.new("core.sequence",
        id: "root",
        slots: %{
          "body" => [Block.new("core.send", id: "notice", config: %{"event" => "loan.due"})]
        }
      )
      |> Document.new()
      |> build()

    [%{children: [send]} = body] = view_model.root.slots
    title = "Tell the patron the loan falls due at the end of the week"
    titled = %{body | children: [%{send | title: title}]}
    %{view_model | root: %{view_model.root | slots: [titled]}}
  end

  # A loan whose second notice is parked on the drafts shelf.
  defp shelf_view_model do
    Block.new("core.sequence",
      id: "root",
      slots: %{
        "body" => [
          Block.new("core.send", id: "notice", config: %{"event" => "loan.overdue"}),
          Block.new("core.drafts",
            id: "shelf",
            slots: %{
              "body" => [
                Block.new("core.send", id: "second", config: %{"event" => "loan.overdue"})
              ]
            }
          )
        ]
      }
    )
    |> Document.new()
    |> build()
  end

  # A hold placed with the host: an Invoke, whose failure path is a rail
  # that is not a group's rules column.
  defp invoke_view_model do
    hold =
      Block.new("core.invoke",
        id: "hold",
        config: %{"invoke_type" => "library:place_hold"},
        slots: %{
          "on_error" => [
            Block.new("core.send", id: "no_hold", config: %{"event" => "hold.refused"})
          ]
        }
      )

    Block.new("core.sequence", id: "root", slots: %{"body" => [hold]})
    |> Document.new()
    |> build()
  end

  # A loan that renews: the renewal rule resumes the group's body.
  defp resume_view_model do
    group =
      Block.new("core.group",
        id: "held",
        slots: %{
          "body" => [
            Block.new("core.send", id: "notice", config: %{"event" => "loan.overdue"}),
            Block.new("core.await", id: "back", config: %{"event" => "copy.returned"})
          ],
          "interrupts" => [
            Block.new("core.on_event",
              id: "renew",
              config: %{"event" => "loan.renewed", "outcome" => "resume"}
            )
          ]
        }
      )

    Block.new("core.sequence", id: "root", slots: %{"body" => [group]})
    |> Document.new()
    |> build()
  end

  defp no_accepts_document do
    Block.new("core.sequence",
      id: "root",
      slots: %{
        "body" => [Block.new("core.send", id: "notice", config: %{"event" => "loan.overdue"})]
      }
    )
    |> Document.new()
  end

  defp walk(%{} = node), do: [node | Enum.flat_map(Map.get(node, "children", []), &walk/1)]

  defp find(graph, id), do: Enum.find(walk(graph), &(&1["id"] == id))

  defp containers(graph), do: Enum.filter(walk(graph), &Map.has_key?(&1, "children"))

  defp markers(graph), do: for(%{"kind" => "empty", "id" => id} <- walk(graph), do: id)

  defp marks(graph),
    do: for(%{"mark" => mark, "id" => id} <- walk(graph), into: %{}, do: {id, mark})

  defp unmark(%{} = node) do
    node = Map.delete(node, "selected")

    case node do
      %{"children" => children} -> Map.put(node, "children", Enum.map(children, &unmark/1))
      %{} -> node
    end
  end

  # The mark a block should carry, read off the fixture's own form values
  # rather than the map's code.
  defp expected_mark(%Node{type: "core.await"}), do: "wait"
  defp expected_mark(%Node{type: "core.wait"}), do: "clock"

  defp expected_mark(%Node{type: "core.send", form: %{fields: fields}}) do
    case Enum.find(fields, &(&1.key == "delay")) do
      %{value: delay} -> if Duration.duration?(delay), do: "clock"
      nil -> nil
    end
  end

  defp expected_mark(%Node{}), do: nil

  defp slot_ids(graph, block_id) do
    for %{"kind" => "slot", "id" => id} <- find(graph, block_id)["children"], do: id
  end
end
