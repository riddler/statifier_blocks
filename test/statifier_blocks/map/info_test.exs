defmodule StatifierBlocks.Map.InfoTest do
  @moduledoc """
  The description region's data, for every element the Map draws and for
  the document when nothing is selected.

  The tests move from the reference host's description test at
  `statifier_examples@c620756`, assertion for assertion, with the values it
  expected: the documents are the two teaching documents that host carried
  (`StatifierBlocks.MapFixtures`), read with the library world's words for
  event names, the `:phrase` the Map takes. The host ran its "every
  fixture" tests over a longer fixture list, and here they run over the two
  documents this package carries; its one host-typed document is replaced
  by a host type written here. The note tests are this package's own.

  Not tagged `:liveview`: nothing here names Phoenix, so it runs in the
  headless tree too.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.Block
  alias StatifierBlocks.BlockType
  alias StatifierBlocks.Core.Await
  alias StatifierBlocks.Core.Group
  alias StatifierBlocks.Core.Wait
  alias StatifierBlocks.Describe
  alias StatifierBlocks.Document
  alias StatifierBlocks.Map, as: BlockMap
  alias StatifierBlocks.Map.Info
  alias StatifierBlocks.MapFixtures
  alias StatifierBlocks.Palette
  alias StatifierBlocks.ViewModel

  # A host type the core palette does not carry: it explains itself only
  # through its palette entry's description, as a host's own type may.
  defmodule CardIntake do
    @moduledoc false
    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config), do: []

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

    @impl true
    def palette_entry,
      do: %{
        label: "Card intake",
        group: "Library",
        description: "Takes a patron's library card application at the desk."
      }
  end

  # A host type whose own sentence is a whole sentence, full stop included,
  # as a host's line may be.
  defmodule CardStamp do
    @moduledoc false
    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config), do: []

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

    @impl true
    def sentence(_config), do: "Stamp the patron's card."

    @impl true
    def palette_entry, do: %{label: "Card stamp", group: "Library"}
  end

  # The library fixtures are the two teaching documents the region is read
  # against; between them every kind the map draws is drawn at least once.
  @library ["library_loan", "patron_registration"]

  describe "elements/6" do
    # Every element the map draws has exactly one description, keyed by the
    # id the map draws it under - asked of every fixture, because a document
    # whose shape no other fixture has (a parallel, a composite, a drafts
    # shelf, a host type) is the one a single-fixture test misses.
    #
    # Sabotage: made walk/2 skip a graph node's "edges"; this went red on
    # the first fixture with a connector. Reverted from a copy.
    test "describes every element the map draws, once, under the map's id" do
      for key <- MapFixtures.keys() do
        {graph, descriptions, _idle} = described(key)

        assert Enum.map(descriptions, & &1.id) |> Enum.sort() == graph_ids(graph),
               "#{key}: the descriptions are not the map's elements"

        for description <- descriptions do
          assert is_binary(description.title) and description.title != ""
          assert is_binary(description.explanation) and description.explanation != ""
        end
      end
    end

    # Sabotage: made block/2 answer :block for a rail block; the :rule
    # kind went missing from both fixtures and this went red. Reverted from
    # a copy.
    test "the two library fixtures draw every kind between them" do
      kinds =
        @library
        |> Enum.flat_map(fn key -> key |> described() |> elem(1) |> Enum.map(& &1.kind) end)
        |> MapSet.new()

      for kind <- [
            :block,
            :rule,
            :arm,
            :undecided_arm,
            :rules,
            :body,
            :marker,
            :end,
            :start,
            :edge,
            :interrupt
          ] do
        assert kind in kinds, "no #{kind} described"
      end
    end

    # The settings are the type's `config_schema/1` fields, labelled as the
    # type labels them, with the block's values.
    #
    # Sabotage: made settings/1 read `&1.key` for the label; this went red
    # on "Wait for". Reverted from a copy.
    test "a block's settings are its config_schema fields and their values" do
      loan = by_id("library_loan")

      assert loan["blk_ll_loan_period"].settings == [
               {label(Wait, "duration"), "21d"}
             ]

      assert loan["blk_ll_late_return"].settings == [
               {label(Await, "event"), "copy.returned"},
               {label(Await, "timeout"), "14d"}
             ]

      # An optional field the author left empty says so rather than
      # drawing nothing.
      assert {label(Await, "timeout"), "Not set"} in by_id("patron_registration")["blk_pr_email"].settings
    end

    # Sabotage: dropped the `index + 1` in place/2 (counted from zero); this
    # went red. Reverted from a copy.
    test "a block's place counts from one and names its container" do
      loan = by_id("library_loan")

      assert fact(loan["blk_ll_root"], "Place") == "The root: every other step sits inside it"

      assert fact(loan["blk_ll_loan_period"], "Place") ==
               "Step 1 of 1 in Steps of Group (Run interruptible steps)"

      assert fact(loan["blk_ll_late_return"], "Place") =~
               ~r/^Step 2 of 2 in Otherwise, arm 3 of 4 of Branch \(/

      assert fact(loan["blk_ll_reported_lost"], "Place") ==
               "Rule 2 of 2 in Interrupt rules of Group (Run interruptible steps)"
    end

    # Every outcome name the type declares, and where each one goes, off the
    # outline's own edges.
    #
    # Sabotage: made onward/2 answer the edge's source instead of its
    # target; this went red. Reverted from a copy.
    test "a block's outcomes say where each one goes" do
      loan = by_id("library_loan")

      assert fact(loan["blk_ll_overdue_notice"], "Outcomes") == [
               "done: goes on to Wait until the copy is returned, giving up after 14d"
             ]

      assert [received, timed_out] = fact(loan["blk_ll_late_return"], "Outcomes")
      assert received =~ ~r/^received: finishes Branch/
      assert timed_out =~ ~r/^timed_out: finishes Branch/

      assert fact(loan["blk_ll_root"], "Outcomes") == ["done: the document finishes"]
    end

    # A step inside a group can be left by the group's rules; a step outside
    # it cannot, and a rule is not left by its own group's rules.
    #
    # Sabotage: left the block itself out of the groups leaving/2 asks, so
    # a group lost its own rules; this went red. Reverted from a copy.
    test "the interrupt rules that can leave a block" do
      loan = by_id("library_loan")

      assert fact(loan["blk_ll_loan_period"], "Interrupt rules") == [
               "When the copy is returned, abandons Group (Run interruptible steps)",
               "When the copy is reported lost, abandons Group (Run interruptible steps)"
             ]

      assert fact(loan["blk_ll_on_loan"], "Interrupt rules") ==
               fact(loan["blk_ll_loan_period"], "Interrupt rules")

      assert fact(loan["blk_ll_close"], "Interrupt rules") == nil
      assert fact(loan["blk_ll_returned_early"], "Interrupt rules") == nil
    end

    # Sabotage: made does/1 answer "resumes" for every edge; this went red.
    # Reverted from a copy.
    test "a rule says what it listens for and what it does to its group" do
      rule = by_id("patron_registration")["blk_pr_expired"]

      assert rule.kind == :rule
      assert fact(rule, "Listens for") == "registration.deadline"
      assert fact(rule, "Then") == "abandons Group (Run interruptible steps)"
      assert fact(rule, "Outcomes") == nil

      rules = by_id("patron_registration")["blk_pr_verify/interrupts"]
      assert rules.kind == :rules

      assert fact(rules, "Rules") == [
               "When the registration is abandoned, abandon",
               "When the registration week is up, abandon"
             ]
    end

    # A rule's "Then", beside its "Listens for", names the history a
    # resumable group re-enters at when the rule resumes it; the same words
    # close the rule's line in a step's interrupt rules and on its dashed
    # edge. A rule that abandons names none, and neither does one that
    # resumes a plain group. A rule with no event yet says so. Neither
    # teaching document has a resumable group, so one is written here.
    #
    # Sabotage: made the rule's "Then" leave out history/1; this went red.
    # Made history/1 answer "" for every edge; this went red. Made the
    # rule's "Listens for" answer nil for an unnamed event; this went red.
    # Made interrupt_line/2 leave out history/1; this went red. Each
    # reverted from a copy.
    test "a rule's Then names the history a resumable group re-enters at" do
      for mode <- ["shallow", "deep"] do
        held = describe_root(resumable_root(mode))
        at = "resumes Resumable group at #{mode} history"

        assert [{"Place", _place}, {"Listens for", "loan.renewed"}, {"Then", ^at}] =
                 held["renew"].facts

        assert [{"Place", _place}, {"Listens for", "An event not named yet"}, {"Then", then}] =
                 held["lost"].facts

        assert then == "abandons Resumable group"

        assert fact(held["back"], "Interrupt rules") == [
                 "When the loan is renewed, #{at}",
                 "On its event, abandons Resumable group"
               ]

        assert held["renew->held/body"].sentence == "When the loan is renewed, #{at}"
        assert held["lost->held/exit"].sentence == "On its event, abandons Resumable group"
      end

      plain = describe_root(resume_root())
      assert fact(plain["renew"], "Then") == "resumes Group (Run interruptible steps)"
      refute plain["renew->held/body"].sentence =~ "history"
    end

    # A group's body is a pane of its own on the map, and says which group
    # it is the body of and which steps it holds, in order.
    #
    # Sabotage: made slot/5 describe a "body" slot as an arm; the :body
    # kind went missing and this went red. Reverted from a copy.
    test "a group's body pane says whose body it is and what it holds" do
      body = by_id("patron_registration")["blk_pr_verify/body"]

      assert body.kind == :body
      assert body.title == "Steps"
      assert fact(body, "Group") == "Group (Run interruptible steps)"

      assert fact(body, "Steps") == [
               "In 7 days, send word that the registration week is up",
               "Wait until the email address is verified",
               ~s(Decide: When "child", otherwise),
               "Send word that the patron is welcomed"
             ]
    end

    # Sabotage: paired the branch edges with the wired slots in reverse
    # order; the loan's arms went to the wrong steps and this went red.
    # Reverted from a copy.
    test "an arm states its condition and where taking it goes" do
      loan = by_id("library_loan")

      renew = loan["blk_ll_due/arm_renew"]
      assert renew.kind == :arm
      assert fact(renew, "Condition") == "copy.holds == 0 AND loan.renewals < 2"
      assert fact(renew, "Goes to") == "Send word that the loan is renewed"
      assert fact(renew, "Place") =~ ~r/^Arm 2 of 4 of Branch/

      otherwise = loan["blk_ll_due/otherwise"]
      assert fact(otherwise, "Condition") == "None of the arms before it holds"
      assert fact(otherwise, "Goes to") == "Send word that the loan is overdue"
      assert fact(otherwise, "Steps") == "2"
    end

    # The undecided arm is described as itself on both fixtures: wired on the
    # patron registration, empty on the loan.
    #
    # Sabotage: dropped the "undecided" clause of slot/5; both went to :arm
    # and this went red. Reverted from a copy.
    test "the undecided arm, wired and unwired" do
      wired = by_id("patron_registration")["blk_pr_age/undecided"]
      assert wired.kind == :undecided_arm
      assert fact(wired, "Goes to") == "Send word that the patron is asked to visit"

      unwired = by_id("library_loan")["blk_ll_due/undecided"]
      assert unwired.kind == :undecided_arm

      assert fact(unwired, "Goes to") ==
               "Nowhere yet: an undecided condition counts as not holding"

      assert fact(unwired, "Steps") == "0"
    end

    # Sabotage: made endpoint/2 answer the sentence of an `{:exit, id}`
    # container rather than "the end of" it; this went red. Reverted from a
    # copy.
    test "an empty slot's marker names its slot and where it leads" do
      marker = by_id("patron_registration")["blk_pr_age/otherwise/empty"]

      assert marker.kind == :marker
      assert marker.title == BlockMap.empty_text()
      assert fact(marker, "Slot") =~ ~r/^Otherwise of Branch/
      assert fact(marker, "Goes to") =~ ~r/^the end of Branch/
    end

    # Each dashed interrupt edge the map draws is described under its own
    # map id, off the outline's interrupt edge from the same rule. Neither
    # teaching document has a resume rule, so a group written here carries
    # that case, beside any the documents draw.
    #
    # Sabotage: made lands/3 answer the exit for a resume edge too; this
    # went red. Reverted from a copy.
    test "an interrupt edge says its rule, its event and where it lands" do
      loan = by_id("library_loan")
      edge = loan["blk_ll_returned_early->blk_ll_on_loan/exit"]

      assert edge.kind == :interrupt

      assert edge.sentence ==
               "When the copy is returned, abandons Group (Run interruptible steps)"

      assert fact(edge, "Rule") =~ "the copy is returned"
      assert fact(edge, "Listens for") == "copy.returned"
      assert fact(edge, "Goes to") == "the end of Group (Run interruptible steps)"

      written = describe_root(resume_root())

      resumes =
        for described <- [written | Enum.map(MapFixtures.keys(), &by_id/1)],
            {_id, %Info{kind: :interrupt} = edge} <- described,
            String.ends_with?(edge.id, "/body"),
            do: edge

      refute resumes == []

      for edge <- resumes do
        assert fact(edge, "Goes to") =~ ~r/^the head of the body of /
        assert edge.sentence =~ "resumes"
      end
    end

    # Sabotage: made edge/2 look for an `:exit` edge instead of the
    # `:sequence` one; the connector carried nothing and this went red.
    # Reverted from a copy.
    test "a connector names both ends and what it carries" do
      edge = by_id("library_loan")["blk_ll_overdue_notice->blk_ll_late_return"]

      assert edge.kind == :edge
      assert fact(edge, "From") == "Send word that the loan is overdue"
      assert fact(edge, "To") == "Wait until the copy is returned, giving up after 14d"
      assert fact(edge, "Carries") == "done"
      assert fact(edge, "Inside") =~ ~r/^Branch \(/
    end

    # The map's Branch marks have their words here: a branch names its arms
    # in the order it tries them, a rejoin says where the arms come back
    # together, and the end mark says the document finishes there.
    #
    # Sabotage: made arms/1 answer [] for a branch; this went red. Made the
    # rejoin clause of edge/2 title itself "Connector"; this went red. Made
    # the end mark :marker; this went red. Each reverted from a copy.
    test "a branch's arms, its rejoin and the end mark are described" do
      loan = by_id("library_loan")

      assert fact(loan["blk_ll_due"], "Arms, in order") == [
               ~s(1. When "returned": loan.returned),
               ~s(2. When "renew": copy.holds == 0 AND loan.renewals < 2),
               "3. Otherwise",
               "4. Cannot be decided"
             ]

      assert fact(loan["blk_ll_close"], "Arms, in order") == nil

      rejoin = loan["blk_ll_due->blk_ll_root/end/done"]
      assert %Info{kind: :edge, title: "Rejoin"} = rejoin
      assert fact(rejoin, "To") == "the document finishes"
      assert fact(rejoin, "Outcome") == "done"
      assert fact(rejoin, "Inside") =~ ~r/^Sequence/

      assert %Info{kind: :end, title: "End"} = loan["blk_ll_root/end/done"]

      patron = by_id("patron_registration")["blk_pr_age->blk_pr_welcome"]
      assert %Info{kind: :edge, title: "Rejoin"} = patron
      assert fact(patron, "To") == "Send word that the patron is welcomed"
    end

    # Each end mark says the document finishes there and with which
    # outcome, the solid ring and the dashed one told apart in words; the
    # edge into an abandon end names the rules that abandon the group.
    # No other edge carries an outcome.
    #
    # Sabotage: made end_explanation/1 answer the done text for every
    # outcome; this went red. Made the end clause of edge/2 leave out the
    # interrupt rules; this went red. Made outcome/1 answer an Outcome fact
    # for a rejoin into a step; this went red. Made the abandon end's text say
    # "its last step" in place of "a group at the end of its flow"; this went
    # red. Made the Finish edge's text say "the last step" in place of "or a
    # group at the end of its flow"; this went red. Each reverted from a copy.
    test "every end mark and the edge into it name the outcome" do
      patron = by_id("patron_registration")

      done = patron["blk_pr_root/end/done"]

      assert %Info{kind: :end, title: "End", sentence: "The document finishes: done"} =
               done

      assert fact(done, "Outcome") == "done"
      assert done.explanation =~ "solid ring"

      abandon = patron["blk_pr_root/end/abandon"]
      assert %Info{kind: :end, sentence: "The document finishes: abandon"} = abandon
      assert fact(abandon, "Outcome") == "abandon"
      assert abandon.explanation =~ "dashed ring"

      assert abandon.explanation ==
               "Where the document finishes when an interrupt rule abandons a group at the end " <>
                 "of its flow, drawn as a dashed ring: the rule leaves the group, and nothing " <>
                 "comes after the group."

      into_done = patron["blk_pr_verify->blk_pr_root/end/done"]
      assert %Info{kind: :edge, title: "Finish"} = into_done

      assert into_done.sentence ==
               "When Run interruptible steps finishes, the document finishes: done"

      finish_explanation =
        "The arrow into a final mark: the document's last step, or a group at the end " <>
          "of its flow, is behind it, so when control leaves it this way, the document " <>
          "finishes with the outcome it names."

      assert into_done.explanation == finish_explanation

      assert fact(into_done, "Outcome") == "done"
      assert fact(into_done, "Interrupt rules") == nil

      into_abandon = patron["blk_pr_verify->blk_pr_root/end/abandon"]
      assert %Info{kind: :edge, title: "Finish"} = into_abandon
      assert into_abandon.sentence =~ ~r/^When an interrupt rule abandons Group/
      assert fact(into_abandon, "Outcome") == "abandon"
      assert [_one, _two] = fact(into_abandon, "Interrupt rules")
      assert into_abandon.explanation == finish_explanation

      for key <- @library,
          {id, %Info{kind: :edge} = edge} <- by_id(key),
          not String.contains?(id, "/end/") do
        assert fact(edge, "Outcome") == nil, "#{key}: #{id}"
      end
    end

    # A group deeper in tail position that a rule abandons has its own edge
    # into the one abandon end, and elements/6 describes each such edge as
    # it describes the root's last step's: the finish edge's explanation,
    # the outcome, and the rules of THAT group - the loan group's renewal
    # and return, the overdue group's loss report - so the description names
    # which group abandons. The abandon end's own text is the ruled words,
    # and the done edge stays with the root's last step, naming no rules.
    # The fourth loan puts a sequence in tail position under the loan
    # group, so the overdue group is reached through it.
    #
    # Sabotage: made tail_slots/1 skip a sequence; the closing-sequence loan
    # lost its overdue edge and this went red. Made finishing/3 answer the
    # finishes text for an abandon; this went red. Made the abandon end's
    # text say "its last step" in place of "a group at the end of its flow";
    # this went red. Each reverted from a copy.
    test "a deep abandon's edges name the group that abandons and its rules" do
      group = "Group (Run interruptible steps)"

      rules = %{
        "blk_ll_on_loan" => [
          "When the loan is renewed, resumes #{group}",
          "When the copy is returned, abandons #{group}"
        ],
        "blk_ll_overdue" => ["When the copy is reported lost, abandons #{group}"]
      }

      finish_explanation =
        "The arrow into a final mark: the document's last step, or a group at the end " <>
          "of its flow, is behind it, so when control leaves it this way, the document " <>
          "finishes with the outcome it names."

      for {key, document, last, abandoning} <- MapFixtures.deep_abandons() do
        {_graph, descriptions, _idle} = described_document(document, Palette.core())
        by_id = Map.new(descriptions, &{&1.id, &1})

        done = by_id["#{last}->blk_ll_root/end/done"]
        assert %Info{kind: :edge} = done, key
        assert fact(done, "Outcome") == "done", key
        assert fact(done, "Interrupt rules") == nil, key

        abandon_end = by_id["blk_ll_root/end/abandon"]
        assert %Info{kind: :end, sentence: "The document finishes: abandon"} = abandon_end, key

        assert abandon_end.explanation ==
                 "Where the document finishes when an interrupt rule abandons a group at the end " <>
                   "of its flow, drawn as a dashed ring: the rule leaves the group, and nothing " <>
                   "comes after the group.",
               key

        abandon_edges =
          for {id, %Info{kind: :edge}} <- by_id,
              String.ends_with?(id, "->blk_ll_root/end/abandon"),
              do: id

        assert Enum.sort(abandon_edges) ==
                 Enum.sort(for(g <- abandoning, do: "#{g}->blk_ll_root/end/abandon")),
               key

        for g <- abandoning do
          edge = by_id["#{g}->blk_ll_root/end/abandon"]
          assert %Info{kind: :edge, title: "Finish"} = edge, "#{key}: #{g}"

          assert edge.sentence ==
                   "When an interrupt rule abandons #{group}, the document finishes: abandon",
                 "#{key}: #{g}"

          assert fact(edge, "Outcome") == "abandon", "#{key}: #{g}"
          assert fact(edge, "Interrupt rules") == Map.fetch!(rules, g), "#{key}: #{g}"
          assert edge.explanation == finish_explanation, "#{key}: #{g}"
        end
      end
    end

    # The start dot and its edge: where the document starts, in the map's
    # own sentence, and the step that runs first. The loan's events are not
    # the edge's: the idle description lists them as what it listens for.
    #
    # Sabotage: made describe/2 answer :end for the start dot; this went
    # red. Reverted from a copy. Sabotage: joined the edge's two sentences
    # with a comma again; this went red. Reverted from a copy.
    test "the start dot and its edge are described" do
      loan = by_id("library_loan")

      assert %Info{kind: :start, title: "Start", sentence: "Starts when the system is told to"} =
               loan["blk_ll_root/start"]

      edge = loan["blk_ll_root/start->blk_ll_on_loan"]
      assert %Info{kind: :start, title: "Start"} = edge
      assert fact(edge, "What starts it") == "Starts when the system is told to"
      assert fact(edge, "First step") == "Run interruptible steps"
      assert edge.sentence == "Starts when the system is told to. First: Run interruptible steps."
      refute edge.sentence =~ "copy.returned"
    end

    # The start edge reads as two sentences, what starts the document and
    # then the step that runs first, closed with one full stop whether or
    # not the first step's own line ends in one.
    #
    # Sabotage: made the edge add its full stop to every first step; the
    # card stamp's line ended in two and this went red. Reverted from a
    # copy.
    test "the start edge reads as two sentences, with one full stop" do
      wait = Block.new("core.wait", id: "loan_period", config: %{"duration" => "21 days"})
      root = Block.new("core.sequence", id: "root", slots: %{"body" => [wait]})

      assert %{"root/start->loan_period" => edge} = describe_root(root)
      assert edge.sentence == "Starts when the system is told to. First: Wait 21 days."

      stamp = Block.new("library.card_stamp", id: "stamp")
      root = Block.new("core.sequence", id: "root", slots: %{"body" => [stamp]})
      palette = Palette.new(Map.put(Palette.core_types(), "library.card_stamp", CardStamp))

      assert %{"root/start->stamp" => edge} = describe_root(root, palette)
      assert edge.sentence == "Starts when the system is told to. First: Stamp the patron's card."
    end

    # The two shapes no fixture has: a document with no step yet, whose
    # edge goes into the empty marker, and a root drawn with its flow in a
    # pane of its own, whose edge the graph itself carries.
    #
    # Sabotage: made the start edge read its first step with target/2,
    # which calls a marker "the document finishes"; this went red. Made
    # elements/6 drop the graph's own edges; this went red. Joined the
    # empty document's two sentences with a comma again; this went red.
    # Each reverted from a copy.
    test "a start into an empty slot, and one the graph carries, are described" do
      empty = Block.new("core.sequence", id: "root", slots: %{"body" => []})

      assert %{"root/start->root/body/empty" => edge} = describe_root(empty)
      assert fact(edge, "First step") == "no step yet (#{BlockMap.empty_text()})"

      assert edge.sentence ==
               "Starts when the system is told to. First: no step yet (#{BlockMap.empty_text()})."

      group =
        Block.new("core.group",
          id: "held",
          slots: %{
            "body" => [
              Block.new("core.await", id: "wait", config: %{"event" => "hold.collected"})
            ],
            "interrupts" => []
          }
        )

      assert %{"held/start->held" => edge, "held/start" => %{kind: :start}} = describe_root(group)
      assert fact(edge, "First step") == "Run interruptible steps"
    end
  end

  describe "idle/4" do
    # Sabotage: counted the root among the steps; this went red. Reverted
    # from a copy.
    test "the document: its name, description, what starts it, and its counts" do
      {_graph, _descriptions, loan} = described("library_loan")

      assert loan.kind == :idle
      assert loan.id == nil
      assert loan.title == "Riverbend Public Library loan"
      assert loan.sentence =~ "A patron borrows a copy"
      assert loan.explanation =~ BlockMap.empty_text()
      assert loan.explanation =~ "The key beside the drawing"
      assert loan.explanation =~ "or point at the map"
      assert fact(loan, "What starts it") == "Starts when the system is told to"
      assert fact(loan, "Listens for") == ["copy.returned", "copy.reported_lost"]
      assert fact(loan, "Steps") == "9"
      assert fact(loan, "Open slots") == "1"

      {_graph, _descriptions, patron} = described("patron_registration")
      assert patron.title == "Riverbend Public Library patron registration"
      assert fact(patron, "Steps") == "10"
      assert fact(patron, "Open slots") == "1"
    end

    # The map is hidden from assistive technology, so the key it draws
    # reaches the region as text: the "Legend" fact, last, holding the line
    # of every entry the graph's key carries, in the key's order, and only
    # those.
    #
    # Sabotage: made key/1 label the fact "Key"; this went red.
    # Reverted from a copy.
    # Sabotage: made key/1 answer no fact; this went red. Reverted from a
    # copy. Sabotage: made key/1 list the lines in reverse; this went red.
    # Reverted from a copy.
    test "the key's lines, as the last fact, for the marks the map draws" do
      for key <- @library do
        {graph, _descriptions, idle} = described(key)
        lines = for %{"line" => line} <- graph["legend"], do: line

        assert lines != [], key
        assert List.last(idle.facts) == {"Legend", lines}, key
      end

      {loan_graph, _descriptions, loan} = described("library_loan")
      {_graph, _descriptions, patron} = described("patron_registration")
      refute Enum.any?(loan_graph["legend"], &(&1["mark"] == "timer"))
      assert length(fact(patron, "Legend")) > length(fact(loan, "Legend"))
    end

    # A graph that carries no key - one built before the graph carried
    # it, say - has no "Legend" fact rather than an empty one.
    #
    # Sabotage: made key/1 answer the fact with an empty list; this went
    # red. Reverted from a copy.
    test "a graph with no key gives no key fact" do
      document = MapFixtures.document!("library_loan")
      view_model = ViewModel.build(document, Palette.core(), [])
      outline = Describe.outline(document, Palette.core(), [])
      graph = view_model |> BlockMap.graph() |> Map.delete("legend")

      idle = Info.idle(document, graph, view_model, outline)
      refute Enum.any?(idle.facts, &match?({"Legend", _}, &1))
    end

    # How the document finishes, beside what starts it: the words its end
    # marks and the arrows into them carry, in the outline's exit order -
    # each outcome, and "abandons" for an abandon end. The loan finishes
    # when its branch does; the registration's group can also be
    # abandoned, and so can the loans written here deeper in their tails.
    #
    # Sabotage: made finish_word/1 answer "abandon" for an abandon end;
    # this went red. Reverted from a copy.
    # Sabotage: put the fact after "Listens for"; this went red. Reverted
    # from a copy.
    test "what the document finishes with, beside what starts it" do
      {_graph, _descriptions, loan} = described("library_loan")
      {_graph, _descriptions, patron} = described("patron_registration")

      assert [{"What starts it", _}, {"Finishes with", ["done"]}, {"Listens for", _} | _] =
               loan.facts

      assert [{"What starts it", _}, {"Finishes with", ["done", "abandons"]} | _] = patron.facts

      for {key, document, _last, _abandoning} <- MapFixtures.deep_abandons() do
        {_graph, _descriptions, idle} = described_document(document, Palette.core())
        assert fact(idle, "Finishes with") == ["done", "abandons"], key
      end
    end

    # A document the map draws no end for - a root with no step yet - has
    # no fact to say how it finishes, rather than an empty one.
    #
    # Sabotage: made finishes_with/1 answer the fact with an empty list;
    # this went red. Reverted from a copy.
    test "a document with no step yet says nothing of how it finishes" do
      document = Document.new(Block.new("core.sequence", id: "blk_ll_root"))
      {_graph, _descriptions, idle} = described_document(document, Palette.core())

      refute Enum.any?(idle.facts, &match?({"Finishes with", _}, &1))
      assert [{"What starts it", _}, {"Listens for", "No events"} | _] = idle.facts
    end

    # Sabotage: made starts/1 answer an empty list for a document that
    # accepts nothing; this went red. Reverted from a copy.
    test "a document with no name, description or accepted events" do
      document = %{MapFixtures.document!("library_loan") | metadata: %{}, accepts: []}
      view_model = ViewModel.build(document, Palette.core(), [])
      outline = Describe.outline(document, Palette.core(), [])

      idle = Info.idle(document, BlockMap.graph(view_model), view_model, outline)

      assert idle.title == document.id
      assert idle.sentence == nil
      assert fact(idle, "Listens for") == "No events"
    end
  end

  describe "the paragraph on how to read the map, and the key" do
    # Every class the Map hook draws under, with the words that name that
    # thing: in the paragraph, for the boxes and what is drawn on them, or
    # in the key's line for one mark, for every mark the key names. The
    # classes are read out of the hook itself, so a mark the hook starts
    # drawing fails the first test here until the paragraph or the key
    # names it.
    @hook "assets/js/statifier_blocks_map.js"

    # Named in the paragraph: the boxes, what is drawn on them, and the key
    # itself, which the paragraph points at.
    @in_paragraph %{
      "block" => "A plain box is a step",
      "block--container" => "drawn inside the step that holds it",
      "title" => "its type's name on top",
      "sentence" => "what it does under it",
      "slot" => "A shaded box inside a step is a place it holds steps",
      "slot-label" => "a branch's arms or a parallel's lanes",
      "empty" => "A dashed box saying",
      "empty-text" => "is a place no step fills yet",
      "caption" => "A caption on a branch's band",
      "block--selected" => "The selected step's box is outlined",
      "gap" => "a \"+\" at a box's lower right corner",
      "key" => "The key beside the drawing",
      "key-title" => "The key beside the drawing",
      "key-entry" => "says what each of its other marks means",
      "key-line" => "says what each of its other marks means"
    }

    # Named in the key: each class with the mark whose line names it and
    # the words in that line.
    @in_key %{
      "start" => {"start", "The filled dot marked Start"},
      "start-word" => {"start", "marked Start"},
      "start-caption" => {"start", "its arrow captioned with what starts it"},
      "end" => {"end", "A dot inside a solid ring marked End"},
      "end-word" => {"end", "marked End"},
      "end-ring" => {"end", "solid ring"},
      "end-dot" => {"end", "A dot inside"},
      "edge--end" => {"end", "the outcome named on the arrow into it"},
      "end-caption" => {"end", "the outcome named on the arrow into it"},
      "edge" => {"arrow", "An arrow runs from a step to the one after it"},
      "band" => {"fork", "A band"},
      "band-group" => {"fork", "stands over a branch's arms"},
      "fork" => {"fork", "a fork mark"},
      "join" => {"join", "the arms come back together at a dot"},
      "edge--rejoin" => {"join", "a heavier arrow leads on"},
      "edge--interrupt" => {"interrupt", "A dashed arrow runs from an interrupt rule"},
      "mark" => {"wait", "An hourglass marks a step that waits for an event"},
      "edge--timer" => {"timer", "A dotted arrow"},
      "timer-caption" => {"timer", "labelled with the delay"},
      "drafts" => {"drafts", "Drafts:"},
      "drafts-row" => {"drafts", "not wired in"}
    }

    # The canvas itself, and the pane drawn in place of a map that could
    # not be laid out: neither is a mark on a map.
    @not_marks ["svg", "error", "error-title", "error-reason", "error-hint"]

    # The classes the hook builds by interpolation, each with every class it
    # can build. A class is read whole, with each `${...}` in it read as
    # `${}` wherever in the name it stands. An interpolated class the hook
    # adds and neither this table nor the next lists fails the test, so
    # none escapes the scan.
    @interpolated %{"${}-caption" => ["start-caption", "end-caption"]}

    # The classes the hook builds by putting a value from the graph after a
    # stem it also draws plain, each with the graph key the value is read
    # from. Every value the graph gives under that key is a word in the
    # variants table below, so the paragraph or the key names each class
    # these build.
    @modifiers %{"end--${}" => "outcome", "mark--${}" => "mark", "slot--${}" => "style"}

    # Each value the graph gives a mark, a slot or an end, and where the
    # words that name that one are: the paragraph, or a mark's key line.
    @variants %{
      "wait" => {"wait", "An hourglass"},
      "clock" => {"clock", "A clock marks a timed wait or a message sent after a delay"},
      "arm" => {:paragraph, "a branch's arms"},
      "body" => {:paragraph, "A shaded box inside a step is a place it holds steps"},
      "rail" => {:paragraph, "A column beside a group holds the rules that watch it"},
      "tray" => {:paragraph, "a shelf of drafts"},
      "done" => {"end", "solid ring"},
      "abandon" => {"end-abandon", "A dashed ring"}
    }

    # Sabotage: cut "its arrow captioned with what starts it" from the
    # start's key line; this went red on "start-caption". Reverted from a
    # copy. Sabotage: added a class neither the paragraph nor the key names
    # to a template in the hook; this went red. Reverted from a copy.
    # Sabotage: cut the pointer at the key from the paragraph; this went
    # red on "key". Reverted from a copy.
    test "names every mark the hook draws, in the paragraph or the key" do
      {_graph, _descriptions, idle} = described("library_loan")
      {plain, built} = @hook |> File.read!() |> hook_classes()

      assert Enum.sort(built) == Enum.sort(Map.keys(@interpolated) ++ Map.keys(@modifiers))

      interpolated = Enum.flat_map(built, &Map.get(@interpolated, &1, []))
      drawn = Enum.uniq(plain ++ interpolated)

      assert Enum.sort(drawn -- @not_marks) ==
               Enum.sort(Map.keys(@in_paragraph) ++ Map.keys(@in_key))

      for {class, words} <- @in_paragraph do
        assert idle.explanation =~ words, "the paragraph does not name #{class}"
      end

      lines = key_lines()

      for {class, {mark, words}} <- @in_key do
        assert Map.fetch!(lines, mark) =~ words, "the key's #{mark} line does not name #{class}"
      end
    end

    # Between them the two teaching documents draw every mark the key
    # has a line for but the drafts shelf's, which a loan with a shelf
    # draws, so every line above is read off a real key.
    #
    # Sabotage: made drawn_marks/1 leave out the graph's timer edges; this
    # went red on "timer". Reverted from a copy. Sabotage: made
    # put_legend/1 leave the shelf's entry out; this went red. Reverted
    # from a copy.
    test "the two library fixtures' keys and a shelf's name every mark between them" do
      marks = key_lines() |> Map.keys() |> Enum.sort()

      assert marks ==
               Enum.sort(
                 ~w(start end end-abandon arrow fork join interrupt wait clock timer drafts)
               )

      for {_class, {mark, _words}} <- @in_key, do: assert(mark in marks)
    end

    # Sabotage: made mark/1 answer "hourglass" for an await; this went red
    # on "mark--${}". Reverted from a copy. Sabotage: renamed the tray
    # style to "drawer" in the Map's style/2 and slot_options/5 and in
    # Info's slot/5; this went red on "slot--${}". Reverted from a copy.
    test "names every value the hook puts after a stem" do
      for {class, key} <- @modifiers do
        values =
          drawn_graphs()
          |> Enum.flat_map(&values(&1, key))
          |> Enum.uniq()

        assert values != [], "the graph gives no #{key} for #{class}"
        assert values -- Map.keys(@variants) == [], "#{class} builds a class nothing names"
      end
    end

    # A comment in the hook draws nothing, so a class it names is not read.
    #
    # Sabotage: made hook_classes/1 read the hook with its comments left
    # in; this went red. Reverted from a copy.
    test "reads no class out of a comment" do
      hook = """
      // sb-map__commented
      /* sb-map__blocked
         sb-map__${blocked} */
      const SVG_NS = "http://www.w3.org/2000/svg"
      `<g class="sb-map__fork sb-map__mark--${node.mark}">` // sb-map__trailing
      """

      assert hook_classes(hook) == {["fork"], ["mark--${}"]}
    end

    # Sabotage: made the clock's key line name only a message sent after a
    # delay; this went red on "clock". Reverted from a copy. Sabotage:
    # renamed the tray style to "drawer" in the Map's style/2 and
    # slot_options/5 and in Info's slot/5; this went red. Reverted from a
    # copy.
    test "names every kind of mark, slot and end the graph gives" do
      {_graph, _descriptions, idle} = described("library_loan")
      lines = key_lines()

      given = drawn_graphs() |> Enum.flat_map(&graph_values/1) |> Enum.uniq()

      assert Enum.sort(given) == Enum.sort(Map.keys(@variants))

      for {value, {where, words}} <- @variants do
        text = if where == :paragraph, do: idle.explanation, else: Map.fetch!(lines, where)
        assert text =~ words, "nothing names #{value}"
      end
    end

    # Each mark is named once, in the key and not again in the paragraph,
    # and no sentence of the paragraph is said twice.
    #
    # Sabotage: put the fork mark back into the paragraph's sentence on a
    # branch's box; this went red. Reverted from a copy.
    test "names each mark once and says no sentence twice" do
      {_graph, _descriptions, idle} = described("library_loan")
      text = idle.explanation
      key = key_lines() |> Map.values() |> Enum.join("\n")

      for words <- Map.values(@in_paragraph) do
        assert length(String.split(text, words)) == 2, "named more than once: #{words}"
      end

      for {_mark, words} <- Map.values(@in_key) do
        assert length(String.split(key, words)) == 2, "named more than once in the key: #{words}"
        refute text =~ words, "named in the paragraph and in the key: #{words}"
      end

      sentences = String.split(text, ~r/(?<=[.;])\s+/, trim: true)
      assert sentences == Enum.uniq(sentences)
    end

    # Which boxes are steps, and what the column beside a group holds: its
    # interrupt rules, or the step that runs when it fails. Each is a whole
    # sentence of the paragraph, in these words, and the sentence on shaded
    # boxes leaves the column to it.
    #
    # Sabotage: made the opening read "Every box on the map is a step";
    # this went red. Sabotage: cut ", or the step that runs when it fails"
    # from the column's sentence; this went red. Sabotage: put the group's
    # interrupt rules back into the sentence on shaded boxes; this went
    # red. Each reverted from a copy.
    test "says which boxes are steps and what a group's column holds" do
      {_graph, _descriptions, idle} = described("library_loan")
      sentences = String.split(idle.explanation, ~r/(?<=[.;])\s+/, trim: true)

      assert ("A plain box is a step, drawn inside the step that holds it, with its " <>
                "type's name on top and what it does under it.") in sentences

      assert ("A column beside a group holds the rules that watch it, or the step that " <>
                "runs when it fails.") in sentences

      refute idle.explanation =~ "its interrupt rules in a column beside it"
    end

    # The rejoin in plain words, and the arm's condition said once: in the
    # paragraph's sentence on a branch's box, not again in the key's line
    # for where the arms come back together.
    #
    # Sabotage: made the join's key line read "after whichever arm's
    # condition holds"; this went red. Reverted from a copy.
    test "says the rejoin in plain words and the condition once" do
      {_graph, _descriptions, idle} = described("library_loan")
      join = Map.fetch!(key_lines(), "join")

      assert join =~ "come back together"
      refute join =~ "condition"
      assert length(String.split(idle.explanation, "condition")) == 2
    end

    # A timer edge runs to an interrupt rule or an await; the key names
    # what hears it so it cannot be read as the timed wait the clock marks.
    #
    # Sabotage: put back "to the rule or the wait that hears it"; this went
    # red. Reverted from a copy.
    test "names what hears a timer as a rule or an hourglass step" do
      timer = Map.fetch!(key_lines(), "timer")

      assert timer =~ "to the interrupt rule or the hourglass step that hears it"
      refute timer =~ "the wait that hears it"
    end
  end

  describe "a block's explanation" do
    # What a block's type does is the type's own paragraph, asked of
    # `BlockType.explain/1` through the page's palette, for every block of
    # every fixture: a core type's `explain/0`, a host type's palette
    # description. No text of the host's own stands in for either.
    #
    # Sabotage: made explain/2 answer the undescribed line for every
    # resolved block; this went red. Reverted from a copy.
    test "is the type's own explanation, through the palette, for every block" do
      for key <- MapFixtures.keys() do
        view_model = MapFixtures.view_model!(key)
        {_graph, descriptions, _idle} = described(key)

        for %Info{kind: kind, id: id, explanation: explanation} <- descriptions,
            kind in [:block, :rule] do
          node = ViewModel.find_node(view_model, id)
          {:ok, ref} = Palette.fetch(Palette.core(), node.type)

          assert explanation == BlockType.explain(ref), "#{key}: #{id}"
        end
      end
    end

    # The registration's group reads the paragraph `core.group` declares,
    # and a host type that declares none reads its palette description.
    #
    # Sabotage: made explain/2 look the type up in `Palette.core()` rather
    # than the palette it is handed; the host type's line went missing and
    # this went red. Reverted from a copy.
    test "a core type reads its callback, a host type its palette description" do
      assert by_id("patron_registration")["blk_pr_verify"].explanation == Group.explain()

      palette = Palette.new(Map.put(Palette.core_types(), "library.card_intake", CardIntake))

      root =
        Block.new("core.sequence",
          id: "root",
          slots: %{"body" => [Block.new("library.card_intake", id: "intake")]}
        )

      document = Document.new(root)
      view_model = ViewModel.build(document, palette, [])
      node = ViewModel.find_node(view_model, "intake")
      {:ok, ref} = Palette.fetch(palette, node.type)

      refute Palette.declares?(ref, :explain, 0)
      assert is_binary(node.entry.description) and node.entry.description != ""
      assert describe_root(root, palette)["intake"].explanation == node.entry.description
    end

    # A block the palette cannot resolve says so: the package has nothing
    # to explain it with.
    #
    # Sabotage: dropped the unresolvable clause of explain/2; this went
    # red. Reverted from a copy.
    test "a block of a type the palette does not know says so" do
      root =
        Block.new("core.sequence",
          id: "root",
          slots: %{"body" => [Block.new("nowhere.unknown", id: "lost")]}
        )

      assert describe_root(root)["lost"].explanation =~ "does not know"
    end
  end

  describe "timer edges" do
    # The registration's deadline send arms the rule that abandons the
    # registration: its dotted edge is described in the package's own line
    # for it, the event read as words only where it stands in event position
    # (the rule's When, not the edge's own naming of it), and names both
    # ends, the event and the delay.
    #
    # Sabotage: made elements/6 leave the graph's timers out; this went
    # red. Reverted from a copy.
    test "the registration's deadline edge says which rule hears it, and when" do
      id = "blk_pr_deadline->blk_pr_expired/timer"
      assert %Info{kind: :timer} = timer = by_id("patron_registration")[id]
      assert timer.title == "Timer"

      assert timer.sentence ==
               "In 7 days, registration.deadline reaches " <>
                 "When the registration week is up, abandon"

      assert timer.explanation =~ "dotted arrow"
      assert fact(timer, "Sent by") == "In 7 days, send word that the registration week is up"
      assert fact(timer, "Heard by") == "When the registration week is up, abandon"
      assert fact(timer, "Event") == "registration.deadline"
      assert fact(timer, "Delay") == "7d"
    end

    # Each timer edge is described in its own line, found by the edge it
    # draws rather than by where that line falls among the outline's: a
    # loan that sends itself two reminders, each heard by its own wait,
    # says of each dotted edge which reminder reaches which wait, and when.
    #
    # Sabotage: made edge_line/2 render the outline's every edge and take
    # the first timer line; the second edge said the first's sentence and
    # this went red. Reverted from a copy.
    test "each timer edge says its own line, found by its edge" do
      send = fn id, event, delay ->
        Block.new("core.send", id: id, config: %{"event" => event, "delay" => delay})
      end

      root =
        Block.new("core.sequence",
          id: "root",
          slots: %{
            "body" => [
              send.("remind", "loan.due_soon", "14d"),
              send.("chase", "loan.overdue", "21d"),
              Block.new("core.await", id: "soon", config: %{"event" => "loan.due_soon"}),
              Block.new("core.await", id: "late", config: %{"event" => "loan.overdue"})
            ]
          }
        )

      described = describe_root(root)

      assert described["remind->soon/timer"].sentence ==
               "In 14 days, loan.due_soon reaches Wait for loan.due_soon"

      assert described["chase->late/timer"].sentence ==
               "In 21 days, loan.overdue reaches Wait until the loan is overdue"
    end

    # The timer's explanation names what hears it in the key's words, so the
    # thing at the arrow's end cannot be read as the timed wait the clock
    # marks.
    #
    # Sabotage: put back "and the rule or the wait it points at hears it";
    # this went red. Reverted from a copy.
    test "the timer's explanation names the interrupt rule or the hourglass step" do
      id = "blk_pr_deadline->blk_pr_expired/timer"
      timer = by_id("patron_registration")[id]

      assert timer.explanation =~ "the interrupt rule or the hourglass step that hears it"
      refute timer.explanation =~ "the wait it points at"
    end

    # The dotted edge's twin in words, for a reader who selects a row
    # rather than points at the map: the send says what hears it, the rule
    # which send arms it, and a block at neither end of a timer edge says
    # neither.
    #
    # Sabotage: made timed/2 answer nothing; this went red. Reverted from
    # a copy.
    test "the send names what hears it, and the rule what arms it" do
      described = by_id("patron_registration")

      assert fact(described["blk_pr_deadline"], "Heard by") == [
               "When the registration week is up, abandon"
             ]

      assert fact(described["blk_pr_expired"], "Armed by") == [
               "In 7 days, send word that the registration week is up"
             ]

      assert fact(described["blk_pr_email"], "Heard by") == nil
      assert fact(described["blk_pr_email"], "Armed by") == nil
    end
  end

  describe "the author's note" do
    # A block's note is its description's `note`, which the region shows
    # above the built-in text; a rule is a block and carries one too. The
    # note adds itself and changes nothing else the description says, and a
    # block the author wrote no note for has none.
    #
    # Sabotage: made block/2 answer `note: nil` for every block; this went
    # red. Reverted from a copy.
    test "a block's note leads its description and changes nothing else" do
      plain = by_id("library_loan")

      noted =
        "library_loan"
        |> MapFixtures.document!()
        |> put_note("blk_ll_loan_period", "Three weeks is the branch's standard loan.")
        |> put_note("blk_ll_reported_lost", "A lost copy is billed at the desk.")
        |> described_document(Palette.core())
        |> elem(1)
        |> Map.new(&{&1.id, &1})

      assert noted["blk_ll_loan_period"].note == "Three weeks is the branch's standard loan."
      assert noted["blk_ll_reported_lost"].note == "A lost copy is billed at the desk."
      assert noted["blk_ll_reported_lost"].kind == :rule

      for id <- ["blk_ll_loan_period", "blk_ll_reported_lost"] do
        assert %{noted[id] | note: nil} == plain[id], id
      end

      for {id, description} <- noted, id not in ["blk_ll_loan_period", "blk_ll_reported_lost"] do
        assert description.note == nil, id
        assert description == plain[id], id
      end
    end

    # The empty string is the absent note, and a note that is only
    # whitespace says nothing either: the region reads as it did.
    #
    # Sabotage: made notes/1 keep a block's note as written, blank or not;
    # this went red. Reverted from a copy.
    test "an empty or whitespace note is no note" do
      for note <- ["", "  \n\t "] do
        described =
          "library_loan"
          |> MapFixtures.document!()
          |> put_note("blk_ll_loan_period", note)
          |> described_document(Palette.core())
          |> elem(1)
          |> Map.new(&{&1.id, &1})

        assert described["blk_ll_loan_period"].note == nil, inspect(note)
      end
    end

    # Only a block carries a note: no slot, marker, edge or mark reads one,
    # nor the idle description, even where the root carries a note.
    #
    # Sabotage: made describe/2's slot clause carry the note of the slot's
    # block; this went red. Reverted from a copy.
    test "no element but a block, and no idle description, carries a note" do
      document =
        "patron_registration"
        |> MapFixtures.document!()
        |> then(fn document ->
          Enum.reduce(Document.blocks(document), document, &put_note(&2, &1.id, "Why #{&1.id}"))
        end)

      {_graph, descriptions, idle} = described_document(document, Palette.core())

      for %Info{kind: kind, id: id, note: note} <- descriptions do
        if kind in [:block, :rule],
          do: assert(note == "Why #{id}", id),
          else: assert(note == nil, id)
      end

      assert idle.note == nil
    end
  end

  describe "the host's words" do
    # A host that passes no `:phrase` reads every event name as authored,
    # exactly as the Map draws it: the words are the host's, never the
    # package's.
    #
    # Sabotage: made elements/6 read every name as words whatever phrase
    # it was given; this went red. Reverted from a copy.
    test "without a phrase, every event name stays as authored" do
      described =
        "library_loan"
        |> MapFixtures.document!()
        |> described_document(Palette.core(), [])
        |> elem(1)
        |> Map.new(&{&1.id, &1})

      assert fact(described["blk_ll_loan_period"], "Interrupt rules") == [
               "On copy.returned, abandons Group (Run interruptible steps)",
               "On copy.reported_lost, abandons Group (Run interruptible steps)"
             ]

      assert described["blk_ll_overdue_notice->blk_ll_late_return"].sentence ==
               "After Send loan.overdue, Wait for copy.returned, giving up after 14d"
    end
  end

  # ---------------------------------------------------------------- helpers

  # The Map's graph, every description and the idle one for the teaching
  # document `key`, under the library world's words for event names.
  defp described(key), do: key |> MapFixtures.document!() |> described_document(Palette.core())

  defp described_document(document, palette, opts \\ [phrase: &MapFixtures.phrase/1]) do
    view_model = ViewModel.build(document, palette, [])
    graph = BlockMap.graph(view_model, opts)
    outline = Describe.outline(document, palette, [])

    {graph, Info.elements(document, graph, view_model, outline, palette, opts),
     Info.idle(document, graph, view_model, outline)}
  end

  defp describe_root(root, palette \\ Palette.core()) do
    {_graph, descriptions, _idle} = described_document(Document.new(root), palette)
    Map.new(descriptions, &{&1.id, &1})
  end

  # A loan that renews: the renewal rule resumes the group's body.
  defp resume_root do
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
  end

  # A loan held at the history `mode`: the renewal rule resumes the group's
  # body there, and a rule whose event is not named yet abandons it.
  defp resumable_root(mode) do
    group =
      Block.new("core.resumable_group",
        id: "held",
        config: %{"history" => mode},
        slots: %{
          "body" => [
            Block.new("core.send", id: "notice", config: %{"event" => "loan.overdue"}),
            Block.new("core.await", id: "back", config: %{"event" => "copy.returned"})
          ],
          "interrupts" => [
            Block.new("core.on_event",
              id: "renew",
              config: %{"event" => "loan.renewed", "outcome" => "resume"}
            ),
            Block.new("core.on_event",
              id: "lost",
              config: %{"event" => " ", "outcome" => "abandon"}
            )
          ]
        }
      )

    Block.new("core.sequence", id: "root", slots: %{"body" => [group]})
  end

  # `document` with `note` on the block `id`.
  defp put_note(%Document{root: root} = document, id, note),
    do: %{document | root: note_block(root, id, note)}

  defp note_block(%Block{id: id} = block, id, note), do: %{block | note: note}

  defp note_block(%Block{slots: slots} = block, id, note),
    do: %{
      block
      | slots:
          Map.new(slots, fn {name, kids} -> {name, Enum.map(kids, &note_block(&1, id, note))} end)
    }

  defp by_id(key) do
    {_graph, descriptions, _idle} = described(key)
    Map.new(descriptions, &{&1.id, &1})
  end

  defp fact(%Info{facts: facts}, label) do
    Enum.find_value(facts, fn {name, value} -> if name == label, do: value end)
  end

  defp label(module, key) do
    %{} |> module.config_schema() |> Enum.find(&(&1.key == key)) |> Map.fetch!(:label)
  end

  # Every mark, slot style and end outcome a graph gives, at any depth.
  # Every line the two teaching documents' keys carry, by mark, and the
  # line a loan with a drafts shelf adds for it.
  defp key_lines do
    for graph <- drawn_graphs(),
        %{"mark" => mark, "line" => line} <- graph["legend"],
        into: %{},
        do: {mark, line}
  end

  # The graphs the variants are read off: the two teaching documents and a
  # loan with a drafts shelf, the one place a tray slot is drawn.
  defp drawn_graphs do
    shelf = described_document(Document.new(shelf_root()), Palette.core())

    for {graph, _descriptions, _idle} <- Enum.map(@library, &described/1) ++ [shelf],
        do: graph
  end

  # A loan's overdue notice, with a second notice parked on the drafts
  # shelf.
  defp shelf_root do
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
  end

  defp graph_values(node) do
    own = [node["mark"], node["style"], node["kind"] == "end" && node["outcome"]]
    inside = node |> Map.get("children", []) |> Enum.flat_map(&graph_values/1)
    Enum.filter(own, &is_binary/1) ++ inside
  end

  # Every string value the graph's nodes give under `key`, root included.
  defp values(node, key) do
    inside = node |> Map.get("children", []) |> Enum.flat_map(&values(&1, key))
    Enum.filter([node[key]], &is_binary/1) ++ inside
  end

  # The classes a hook's source names, with its comments cut: the plain
  # ones, and the interpolated ones with each `${...}` read as `${}`,
  # wherever in the name it stands. An interpolation whose every string is
  # empty or opens with a space adds classes rather than extending the
  # name before it, so it ends that name and the classes inside it are
  # read on their own.
  defp hook_classes(text) do
    code =
      text
      |> String.replace(~r{/\*.*?\*/}s, "")
      |> String.replace(~r{(?<!:)//.*$}m, "")
      |> String.replace(~r/\$\{([^}]*)\}/, fn interpolation ->
        [_all, inside] = Regex.run(~r/\$\{([^}]*)\}/, interpolation)
        if appends?(inside), do: " " <> inside, else: interpolation
      end)

    names =
      ~r/sb-map__((?:[a-z-]|\$\{[^}]*\})+)/
      |> Regex.scan(code, capture: :all_but_first)
      |> List.flatten()
      |> Enum.map(&String.replace(&1, ~r/\$\{[^}]*\}/, "${}"))

    {plain, built} = Enum.split_with(names, &(not String.contains?(&1, "${}")))
    {plain, Enum.uniq(built)}
  end

  defp appends?(inside) do
    strings = ~r/"([^"]*)"|'([^']*)'/ |> Regex.scan(inside) |> Enum.map(&List.last/1)
    strings != [] and Enum.all?(strings, &(&1 == "" or String.starts_with?(&1, " ")))
  end

  # Every id the graph draws below its root: nodes, connectors, interrupt
  # edges and timer edges alike, and an edge the root itself carries.
  defp graph_ids(%{"children" => children} = graph) do
    edges = graph |> Map.get("edges", []) |> Enum.map(& &1["id"])
    timers = graph |> Map.get("timers", []) |> Enum.map(& &1["id"])
    (Enum.flat_map(children, &ids/1) ++ edges ++ timers) |> Enum.sort()
  end

  defp ids(node) do
    own = [node["id"]]
    inside = node |> Map.get("children", []) |> Enum.flat_map(&ids/1)
    edges = node |> Map.get("edges", []) |> Enum.map(& &1["id"])
    interrupts = node |> Map.get("interrupts", []) |> Enum.map(& &1["id"])
    own ++ inside ++ edges ++ interrupts
  end
end
