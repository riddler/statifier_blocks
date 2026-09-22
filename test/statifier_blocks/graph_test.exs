defmodule StatifierBlocks.GraphTest do
  @moduledoc """
  ADR-0008's amendment of 2026-09-22: the parent/child interface a compile
  records (A1, A5) and the two pairwise checks a host's publish step calls
  over it (A2, A3, A4).

  The documents are inline and minimal: a patron registration parent that
  runs an email verification child and issues one library card per member
  of a household. The resolver is an in-memory map, which is all a host's
  resolver has to be for the check to be pure.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiled, Compiler, Document, Finding, Graph, Palette}
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.Emit

  defmodule VerifyEmail do
    @moduledoc "The root of a child that verifies a patron's email address."

    use StatifierBlocks.BlockType

    @impl true
    def outcomes(_config), do: [{"verified", "Verified"}, {"expired", "Expired"}]

    @impl true
    def donedata_type(_config),
      do: [%{name: "verified_at", path: "verification.at", type: :string}]

    @impl true
    def emit(%Block{}, context), do: StatifierBlocks.GraphTest.emit_finals(context, outcomes(%{}))
  end

  defmodule VerifyEmailRenamed do
    @moduledoc "The next revision of that root: `verified` renamed to `confirmed`."

    use StatifierBlocks.BlockType

    @impl true
    def outcomes(_config), do: [{"confirmed", "Confirmed"}, {"expired", "Expired"}]

    @impl true
    def emit(%Block{}, context), do: StatifierBlocks.GraphTest.emit_finals(context, outcomes(%{}))
  end

  defmodule IssueCard do
    @moduledoc "The root of a child that issues one library card at a branch."

    use StatifierBlocks.BlockType

    @impl true
    def donedata_type(_config) do
      [
        %{name: "card_number", path: "card.number", type: :string},
        %{name: "branch", path: "card.branch", type: :string}
      ]
    end

    @impl true
    def emit(%Block{}, context),
      do: StatifierBlocks.GraphTest.emit_finals(context, [{"done", ""}])
  end

  defmodule IssueCardThin do
    @moduledoc "The next revision of that root, which no longer reports the card number."

    use StatifierBlocks.BlockType

    @impl true
    def donedata_type(_config), do: [%{name: "branch", path: "card.branch", type: :string}]

    @impl true
    def emit(%Block{}, context),
      do: StatifierBlocks.GraphTest.emit_finals(context, [{"done", ""}])
  end

  @doc false
  def emit_finals(context, outcomes) do
    finals =
      Enum.map(outcomes, fn {name, _label} ->
        {:ok, id} = Context.outcome_id(context, name)
        id
      end)

    {:ok, Emit.state(context.state_id, hd(finals), Enum.map(finals, &Emit.final/1))}
  end

  defp palette do
    Palette.new(
      Map.merge(Palette.core_types(), %{
        "library:verify_email" => VerifyEmail,
        "library:verify_email_renamed" => VerifyEmailRenamed,
        "library:issue_card" => IssueCard,
        "library:issue_card_thin" => IssueCardThin
      })
    )
  end

  @card_members [
    %{"name" => "card_number", "type" => "string", "required?" => true},
    %{"name" => "branch", "type" => "string"}
  ]

  describe "the interface a compile records (A1, A5)" do
    # sabotage: recorded `outcome_names/2` of the subchart block instead of
    # `child_outcomes/1` - `routes_on` gains the appended `error` and the
    # first assertion goes red (verified)
    test "a subchart routes on its author's outcomes and reads nothing" do
      assert %{references: [reference]} = compile!(registration()).interface

      assert reference == %{
               block_id: "blk_VERIFY",
               document_id: "email_verification",
               routes_on: ["verified", "expired"],
               reads: []
             }
    end

    # sabotage: recorded an empty `outcomes` field as `[]` rather than
    # through `child_outcomes/1` - `routes_on` is empty and this goes red
    # (verified)
    test "a subchart with no outcomes listed routes on done" do
      assert %{references: [%{routes_on: ["done"]}]} =
               compile!(registration(outcomes: "")).interface
    end

    # sabotage: dropped the `required?: true` filter in `required_members/2`
    # - `branch`, which the shape does not promise, joins `reads` and this
    # goes red (verified)
    test "a map reads the members its inline collect_type marks required" do
      assert %{references: [_verify, cards]} = compile!(registration(cards: true)).interface

      assert cards == %{
               block_id: "blk_CARDS",
               document_id: "library_card_issue",
               routes_on: [],
               reads: ["card_number"]
             }
    end

    # sabotage: made the name arm of `required_members/2` answer `[]` - a
    # declared name contributes no keys and the first assertion goes red
    # (verified)
    test "a collect_type naming a declaration reads its required fields, and unknown reads none" do
      datamodel = %{
        "types" => [
          %{
            "name" => "library.card_receipt",
            "kind" => "shape",
            "fields" => [
              %{"name" => "card_number", "type" => "string", "required?" => true},
              %{"name" => "branch", "type" => "string", "required?" => true}
            ]
          }
        ]
      }

      named = registration(cards: "library.card_receipt")

      assert %{references: [_verify, %{reads: ["card_number", "branch"]}]} =
               compile!(named, datamodel: datamodel).interface

      assert %{references: [_verify, %{reads: []}]} = compile!(named).interface
    end

    # sabotage: read the child side from `donedata_type/1` only under
    # `child_use` - the plain compile records no keys and this goes red
    # (verified)
    test "the child side is the root's outcomes and done-data keys, whatever the chart use" do
      child =
        Document.new(Block.new("library:verify_email", id: "blk_ROOT"), id: "email_verification")

      expected = %{
        declared_outcomes: ["verified", "expired"],
        declared_donedata_keys: ["verified_at"],
        references: []
      }

      assert compile!(child).interface == expected
      assert compile!(child, child_use: true).interface == expected
    end

    # The interface is a function of the compile's inputs and adds nothing
    # to the bytes, so recording it cannot move chart identity.
    #
    # sabotage: added a fresh `System.unique_integer/0` to the recorded
    # interface - two compiles of one document differ and this goes red
    # (verified)
    test "recompiling an unchanged document records the same interface" do
      document = registration(cards: true)
      assert compile!(document).interface == compile!(document).interface
    end
  end

  describe "check/2, the forward direction (A2, A4)" do
    # sabotage: inverted `pair/3`'s filter to `outcome in child.outcomes` -
    # every declared outcome the parent routes on is refused and this goes
    # red (verified)
    test "a green pair returns no finding" do
      assert Graph.check(compile!(registration(cards: true)), resolver(published())) == []
    end

    # sabotage: matched `{:error, :not_published}` to `[]` in `check/2` -
    # the unresolvable child passes silently and this goes red (verified)
    test "an unresolvable child is a finding on the referencing block's chart field" do
      resolver = resolver(Map.delete(published(), "email_verification"))

      assert [
               %Finding{
                 anchor: {:config, "blk_VERIFY", "chart"},
                 source: :graph,
                 severity: :error,
                 message: message
               }
             ] = Graph.check(compile!(registration()), resolver)

      assert message =~ ~s("email_verification")
    end

    # sabotage: inverted `pair/3`'s filter to `outcome in child.outcomes` -
    # the declared `expired` is refused in place of `verified` and this
    # goes red (verified)
    test "a routed outcome the child does not declare is refused" do
      resolver = resolver(%{published() | "email_verification" => verify_email_renamed()})

      assert [
               %Finding{
                 anchor: {:config, "blk_VERIFY", "outcomes"},
                 source: :graph,
                 severity: :error,
                 message: message
               }
             ] = Graph.check(compile!(registration()), resolver)

      assert message =~ ~s("verified")
    end

    # sabotage: removed the `@exempt_outcome` filter in `pair/3` - an author
    # listing `error` explicitly is refused against a child that never
    # declares it, and this goes red (verified)
    test "error is exempt: a child need not declare it" do
      assert Graph.check(
               compile!(registration(outcomes: "verified\nerror")),
               resolver(published())
             ) ==
               []
    end

    # A1: an empty `outcomes` routes on `done`, so a child that does not
    # declare `done` leaves that arm dead exactly as a listed name would.
    #
    # sabotage: recorded an empty `outcomes` field as `[]` rather than
    # through `child_outcomes/1` - nothing is routed on, nothing is refused
    # and this goes red (verified)
    test "a parent listing no outcomes is refused against a child without done" do
      assert [%Finding{anchor: {:config, "blk_VERIFY", "outcomes"}, message: message}] =
               Graph.check(compile!(registration(outcomes: "")), resolver(published()))

      assert message =~ ~s("done")
    end

    # sabotage: made `pair/3`'s key comprehension iterate nothing - the thin
    # child is judged only on outcomes, which a map routes on none of, and
    # this goes red (verified)
    test "a read done-data key the child does not declare is refused" do
      resolver = resolver(%{published() | "library_card_issue" => issue_card_thin()})

      assert [
               %Finding{
                 anchor: {:config, "blk_CARDS", "collect_type"},
                 source: :graph,
                 severity: :error,
                 message: message
               }
             ] = Graph.check(compile!(registration(cards: true)), resolver)

      assert message =~ ~s("card_number")
    end

    # A2: the other direction - a child outcome the parent has no arm for -
    # misroutes rather than dead-arms, and is not refused here.
    #
    # sabotage: appended a refusal for every child outcome the reference
    # does not route on to `pair/3` - the unrouted `expired` is refused and
    # this goes red (verified)
    test "a child declaring an outcome the parent does not route on is not refused" do
      parent = compile!(registration(outcomes: "verified"))
      assert Graph.check(parent, resolver(published())) == []
    end

    # sabotage: resolved per reference rather than per distinct document id
    # - the resolver is asked twice for the one child and this goes red
    # (verified)
    test "the resolver is asked once per distinct document id" do
      test_pid = self()

      counting = fn document_id ->
        send(test_pid, {:resolved, document_id})
        resolver(published()).(document_id)
      end

      assert Graph.check(compile!(registration(twice: true)), counting) == []
      assert_received {:resolved, "email_verification"}
      refute_received {:resolved, "email_verification"}
    end
  end

  describe "consumers_broken/2, the reverse direction (A2, A3)" do
    # The amendment's worked example: `verified` renamed to `confirmed`.
    #
    # sabotage: dropped the `document_id == child_id` filter in
    # `consumers_broken/2` - the parent naming only the card child is judged
    # against the verification child too, and this goes red (verified)
    test "names every parent the next child revision breaks, and none other" do
      broken = compile!(registration(), id: "patron_registration")
      renewal = compile!(registration(outcomes: "verified"), id: "patron_renewal")
      untouched = compile!(registration(outcomes: "expired"), id: "patron_reinstatement")
      elsewhere = compile!(registration(chart: "library_card_issue"), id: "branch_transfer")

      assert [
               {"patron_registration", %Finding{} = first},
               {"patron_renewal", %Finding{} = second}
             ] =
               Graph.consumers_broken(verify_email_renamed(), [
                 broken,
                 untouched,
                 renewal,
                 elsewhere
               ])

      for {finding, parent} <- [{first, "patron_registration"}, {second, "patron_renewal"}] do
        assert finding.anchor == {:config, "blk_VERIFY", "outcomes"}
        assert finding.source == :graph
        assert finding.severity == :error
        assert finding.message =~ ~s("#{parent}")
        assert finding.message =~ ~s("verified")
      end
    end

    # sabotage: made `pair/3`'s key comprehension iterate nothing - a key
    # the next revision drops breaks nobody and this goes red (verified)
    test "a dropped done-data key names the parent that reads it" do
      parent = compile!(registration(cards: true), id: "patron_registration")

      assert [{"patron_registration", %Finding{anchor: {:config, "blk_CARDS", "collect_type"}}}] =
               Graph.consumers_broken(issue_card_thin(), [parent])
    end

    # sabotage: dropped the `document_id == child_id` filter in
    # `consumers_broken/2` - the parent's reference to the other child is
    # judged against this one and this goes red (verified)
    test "a child revision every parent still agrees with breaks nobody" do
      parent = compile!(registration(cards: true), id: "patron_registration")
      assert Graph.consumers_broken(verify_email(), [parent]) == []
      assert Graph.consumers_broken(issue_card(), [parent]) == []
    end
  end

  # -- documents ---------------------------------------------------------

  defp published do
    %{"email_verification" => verify_email(), "library_card_issue" => issue_card()}
  end

  defp resolver(published) do
    fn document_id ->
      case Map.fetch(published, document_id) do
        {:ok, compiled} -> {:ok, compiled}
        :error -> {:error, :not_published}
      end
    end
  end

  defp verify_email, do: child("library:verify_email", "email_verification")
  defp verify_email_renamed, do: child("library:verify_email_renamed", "email_verification")
  defp issue_card, do: child("library:issue_card", "library_card_issue")
  defp issue_card_thin, do: child("library:issue_card_thin", "library_card_issue")

  defp child(type, id) do
    compile!(Document.new(Block.new(type, id: "blk_ROOT"), id: id), child_use: true)
  end

  # The parent: a sequence that runs the verification child and, when
  # asked, issues a card for every member of the household.
  defp registration(opts \\ []) do
    verify =
      Block.new("core.subchart",
        id: "blk_VERIFY",
        config: %{
          "chart" => Keyword.get(opts, :chart, "email_verification"),
          "outcomes" => Keyword.get(opts, :outcomes, "verified\nexpired")
        }
      )

    again =
      Block.new("core.subchart",
        id: "blk_REVERIFY",
        config: %{"chart" => "email_verification", "outcomes" => "verified\nexpired"}
      )

    cards =
      case Keyword.get(opts, :cards, false) do
        false -> []
        true -> [card_map(@card_members)]
        name -> [card_map(name)]
      end

    body = [verify] ++ if(Keyword.get(opts, :twice, false), do: [again], else: []) ++ cards

    Document.new(Block.new("core.sequence", id: "blk_SEQ", slots: %{"body" => body}),
      id: Keyword.get(opts, :id, "patron_registration")
    )
  end

  defp card_map(collect_type) do
    Block.new("core.map",
      id: "blk_CARDS",
      config: %{
        "items" => "patron.household",
        "chart" => "library_card_issue",
        "item_as" => "member",
        "collect" => "cards",
        "collect_type" => collect_type,
        "on" => "all"
      }
    )
  end

  defp compile!(document, opts \\ [])

  defp compile!(%Document{} = document, opts) do
    {id, opts} = Keyword.pop(opts, :id)
    document = if id, do: %{document | id: id}, else: document

    case Compiler.compile(document, palette(), opts) do
      {:ok, %Compiled{} = compiled} -> compiled
      {:error, findings} -> flunk("compile refused: #{inspect(findings, pretty: true)}")
    end
  end
end
