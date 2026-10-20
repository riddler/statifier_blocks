defmodule StatifierBlocks.GraphTest do
  @moduledoc """
  ADR-0008's amendment of 2026-09-22: the parent/child interface a compile
  records (A1, A5) and the two pairwise checks a host's publish step calls
  over it (A2, A3, A4).

  The worked example is stored, so a host can vendor it: four documents
  under `test/fixtures/graph/`. A patron registration verifies the
  registering patron's email address through a `core.subchart` that routes
  on the child's `verified` and `expired` outcomes, then verifies every
  member of the household through a `core.map` whose `collect_type` marks
  `verified_address` required. Both name the one child document,
  `email_verification`, stored three ways: the published revision, a next
  revision that renames `verified` to `confirmed`, and a next revision that
  keeps `verified` but no longer reports `verified_address`.

  No `core.*` type declares done-data, so the child's root is a host block
  type, `library.verify_email`, which reads its outcomes and the keys it
  reports from its own config: the three revisions differ only in their
  stored bytes.

  The rules the worked example does not reach - an unresolvable child,
  `error` exempt, `done` routing, a declaration-named `collect_type`, the
  resolver asked once, several parents - keep small inline documents,
  including a second child that issues one library card per household
  member. The resolver is an in-memory map, which is all a host's resolver
  has to be for the check to be pure.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiled, Compiler, Document, Finding, Graph, Palette}
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.Emit

  defmodule VerifyEmail do
    @moduledoc """
    The root of the email verification child: its outcomes are the
    newline-separated `outcomes` config field, and its done-data is one
    string key per `reports` member.
    """

    use StatifierBlocks.BlockType

    @impl true
    def outcomes(%{"outcomes" => outcomes}) do
      outcomes
      |> String.split("\n", trim: true)
      |> Enum.map(&{&1, String.capitalize(&1)})
    end

    @impl true
    def donedata_type(%{"reports" => reports}) do
      for %{"name" => name} <- reports,
          do: %{name: name, path: "verification." <> name, type: :string}
    end

    @impl true
    def emit(%Block{config: config}, context),
      do: StatifierBlocks.GraphTest.emit_finals(context, outcomes(config))
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

  defmodule ConfirmBorrower do
    @moduledoc """
    A composite a loan desk drops before a checkout: it runs the email
    verification child named by its one param and routes on the child's
    `verified` and `expired` outcomes. The `core.subchart` is an expansion
    member, so the stored document never holds its id.
    """

    use StatifierBlocks.Composite,
      name: "library.confirm_borrower",
      params: [
        %{
          key: "chart",
          type: :string,
          label: "Verification",
          required?: true,
          default: "email_verification"
        }
      ],
      sentence: "Confirm the borrower through {chart}",
      palette_entry: %{label: "Confirm borrower", group: "Loans"},
      version: 1

    alias StatifierBlocks.Block

    @impl StatifierBlocks.Composite
    def subtree(params) do
      [
        Block.new("core.subchart",
          id: "verify",
          config: %{"chart" => params["chart"], "outcomes" => "verified\nexpired"}
        )
      ]
    end
  end

  defmodule Checkout do
    @moduledoc """
    A composite whose expansion holds another composite: the checkout
    confirms the borrower first, so the subchart is two expansions deep.
    """

    use StatifierBlocks.Composite,
      name: "library.checkout",
      params: [],
      sentence: "Check the item out",
      palette_entry: %{label: "Checkout", group: "Loans"},
      version: 1

    alias StatifierBlocks.Block

    @impl StatifierBlocks.Composite
    def subtree(_params) do
      [
        Block.new("library.confirm_borrower",
          id: "confirm",
          config: %{"chart" => "email_verification"}
        )
      ]
    end
  end

  defmodule LoanDesk do
    @moduledoc """
    A composite with one pass-through slot: whatever the author drops into
    it runs inside the desk's group, with its own id.
    """

    use StatifierBlocks.Composite,
      name: "library.loan_desk",
      params: [],
      slots: [%{name: "body", to: {"desk", "body"}, label: "At the desk"}],
      sentence: "At the loan desk",
      palette_entry: %{label: "Loan desk", group: "Loans"},
      version: 1

    alias StatifierBlocks.Block

    @impl StatifierBlocks.Composite
    def subtree(_params),
      do: [Block.new("core.group", id: "desk", slots: %{"body" => [], "interrupts" => []})]
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
        "library.verify_email" => VerifyEmail,
        "library:issue_card" => IssueCard,
        "library.confirm_borrower" => ConfirmBorrower,
        "library.checkout" => Checkout,
        "library.loan_desk" => LoanDesk
      })
    )
  end

  @dir Path.join([__DIR__, "..", "fixtures", "graph"])

  @parent "patron_registration-parent.json"
  @child "email_verification-child.json"
  @child_next "email_verification-child_next.json"
  @child_next_no_key "email_verification-child_next_no_key.json"

  # The host's datamodel, declaring the receipt a card issue answers with -
  # and a second one whose receipt also requires a key no child declares.
  @card_receipt_datamodel %{
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

  @card_expiry_datamodel %{
    "types" => [
      %{
        "name" => "library.card_receipt",
        "kind" => "shape",
        "fields" => [
          %{"name" => "card_number", "type" => "string", "required?" => true},
          %{"name" => "expires_on", "type" => "string", "required?" => true}
        ]
      }
    ]
  }

  @card_members [
    %{"name" => "card_number", "type" => "string", "required?" => true},
    %{"name" => "branch", "type" => "string"}
  ]

  describe "the stored documents" do
    # Each one decodes, validates and re-encodes to its stored bytes, so
    # the files are canonical and a vendored copy compares byte for byte.
    #
    # sabotage: swapped the child fixture's `id` and `metadata` keys - it
    # still decodes but no longer re-encodes to its bytes, and this goes red
    # (verified)
    test "each fixture is a valid, canonically encoded document" do
      for name <- [@parent, @child, @child_next, @child_next_no_key] do
        bytes = File.read!(Path.join(@dir, name))
        assert {:ok, %Document{} = document} = Document.from_json(bytes), name
        assert Document.validate(document) == :ok, name
        assert Document.to_json(document) <> "\n" == bytes, name
      end
    end

    # The two next revisions are revisions of the published child: the same
    # document id, a later revision.
    #
    # sabotage: set the renaming revision's stored `revision` to 1 - it is
    # no longer one on from the published child and this goes red (verified)
    test "the next revisions are the same child document, one revision on" do
      child = document!(@child)

      for name <- [@child_next, @child_next_no_key] do
        next = document!(name)
        assert next.id == child.id, name
        assert next.revision == child.revision + 1, name
      end
    end
  end

  describe "the interface a compile records (A1, A5)" do
    # sabotage: recorded the `core.map` reference with `reads: []` in
    # `reference/3` - the parent's interface loses `verified_address` and
    # this goes red (verified)
    test "the stored parent records both references, and each child its side" do
      assert stored_parent().interface == %{
               declared_outcomes: ["done"],
               declared_donedata_keys: [],
               references: [
                 %{
                   block_id: "blk_VERIFY",
                   document_id: "email_verification",
                   routes_on: ["verified", "expired"],
                   reads: [],
                   unresolved: nil
                 },
                 %{
                   block_id: "blk_HOUSEHOLD",
                   document_id: "email_verification",
                   routes_on: [],
                   reads: ["verified_address"],
                   unresolved: nil
                 }
               ]
             }

      assert %{declared_outcomes: ["confirmed", "expired"]} = stored_child(@child_next).interface

      assert %{declared_outcomes: ["verified", "expired"], declared_donedata_keys: []} =
               stored_child(@child_next_no_key).interface
    end

    # sabotage: recorded `outcome_names/2` of the subchart block instead of
    # `child_outcomes/1` - `routes_on` gains the appended `error` and the
    # first assertion goes red (verified)
    test "a subchart routes on its author's outcomes and reads nothing" do
      assert %{references: [reference]} = compile!(registration()).interface

      assert reference == %{
               block_id: "blk_VERIFY",
               document_id: "email_verification",
               routes_on: ["verified", "expired"],
               reads: [],
               unresolved: nil
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
               reads: ["card_number"],
               unresolved: nil
             }
    end

    # sabotage: made the name arm of `required_members/2` answer `[]` - a
    # declared name contributes no keys and the first assertion goes red
    # (verified)
    test "a collect_type naming a declaration reads its required fields, and unknown reads none" do
      named = registration(cards: "library.card_receipt")

      assert %{references: [_verify, %{reads: ["card_number", "branch"]}]} =
               compile!(named, datamodel: @card_receipt_datamodel).interface

      assert %{references: [_verify, %{reads: []}]} = compile!(named).interface
    end

    # A name with no `:datamodel` to resolve it is marked, so its keys read
    # as unchecked rather than absent; a supplied datamodel clears the mark,
    # and a `nil` datamodel is no datamodel.
    #
    # sabotage: made `unresolved/2` answer `nil` for every name - the name
    # compiled without `:datamodel` is not marked and this goes red (verified)
    test "a collect_type name compiled without :datamodel is marked unresolved, and with it is not" do
      named = registration(cards: " library.card_receipt ")

      assert %{references: [%{unresolved: nil}, %{reads: [], unresolved: "library.card_receipt"}]} =
               compile!(named).interface

      assert %{references: [_verify, %{unresolved: "library.card_receipt"}]} =
               compile!(named, datamodel: nil).interface

      assert %{references: [_verify, %{reads: ["card_number", "branch"], unresolved: nil}]} =
               compile!(named, datamodel: @card_receipt_datamodel).interface
    end

    # Only a name is marked: the inline arm and a blank name have nothing
    # left to resolve, whatever the options.
    #
    # sabotage: dropped the blank arm of `unresolved/2` - a blank
    # `collect_type` is marked as the name "" and this goes red (verified)
    test "the inline arm and a blank collect_type are never marked unresolved" do
      assert %{references: [_verify, %{unresolved: nil}]} =
               compile!(registration(cards: true)).interface

      assert %{references: [_verify, %{unresolved: nil}]} =
               compile!(registration(cards: "  ")).interface
    end

    # sabotage: read the child side from `donedata_type/1` only under
    # `child_use` - the plain compile records no keys and this goes red
    # (verified)
    test "the child side is the root's outcomes and done-data keys, whatever the chart use" do
      child = document!(@child)

      expected = %{
        declared_outcomes: ["verified", "expired"],
        declared_donedata_keys: ["verified_address"],
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
    # sabotage: inverted `pair/3`'s filter to `outcome in
    # child.declared_outcomes` - both routed outcomes are refused and this
    # goes red (verified)
    test "the stored pair returns no finding" do
      assert Graph.check(stored_parent(), resolver(published())) == []
    end

    # Each reference is judged against the child its own document id
    # resolves to, not against whichever child the parent resolved first.
    #
    # sabotage: replaced `Map.fetch!(children, reference.document_id)` in
    # `check/2` with `children |> Map.values() |> hd()` - one child judges
    # both references and this goes red (verified)
    test "a parent naming two distinct children judges each against its own" do
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

    # sabotage: made `pair/3`'s outcome comprehension iterate nothing - the
    # renamed outcome passes and this goes red (verified)
    test "a routed outcome the child does not declare is refused" do
      resolver = resolver(%{published() | "email_verification" => stored_child(@child_next)})

      assert [
               %Finding{
                 anchor: {:config, "blk_VERIFY", "outcomes"},
                 source: :graph,
                 severity: :error,
                 message: message
               }
             ] = Graph.check(stored_parent(), resolver)

      assert message =~ ~s("email_verification")
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

    # sabotage: made `pair/3`'s key comprehension iterate nothing - the
    # dropped key passes and this goes red (verified)
    test "a read done-data key the child does not declare is refused" do
      resolver =
        resolver(%{published() | "email_verification" => stored_child(@child_next_no_key)})

      assert [
               %Finding{
                 anchor: {:config, "blk_HOUSEHOLD", "collect_type"},
                 source: :graph,
                 severity: :error,
                 message: message
               }
             ] = Graph.check(stored_parent(), resolver)

      assert message =~ ~s("verified_address")
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

    # ADR-0008's second amendment of 2026-09-22, U3: with no `:datamodel`
    # the keys a named `collect_type` reads are unknown, and the pair says
    # so at `:warning` rather than passing it.
    #
    # sabotage: made `pair/3`'s unresolved arm answer `[]` - the unchecked
    # read passes silently and this goes red (verified)
    test "a read left unchecked without :datamodel is a warning on the collect_type field" do
      parent = compile!(registration(cards: "library.card_receipt"))

      assert [
               %Finding{
                 anchor: {:config, "blk_CARDS", "collect_type"},
                 source: :graph,
                 severity: :warning,
                 message: message
               }
             ] = Graph.check(parent, resolver(published()))

      assert message =~ ~s("library_card_issue")
      assert message =~ ~s("library.card_receipt")
      assert message =~ "unchecked"
      assert message =~ ":datamodel"
    end

    # With the datamodel the keys are judged exactly as an inline shape's
    # are: all present passes, one missing is the key rule's `:error`, and
    # no `:warning` rides along either way.
    #
    # sabotage: made `interface/2` read every compile as having no
    # `:datamodel` - the declared keys are reported unchecked instead of
    # judged and this goes red (verified)
    test "with :datamodel a named collect_type's keys are checked as before" do
      named = registration(cards: "library.card_receipt")

      assert Graph.check(
               compile!(named, datamodel: @card_receipt_datamodel),
               resolver(published())
             ) ==
               []

      assert [
               %Finding{
                 anchor: {:config, "blk_CARDS", "collect_type"},
                 severity: :error,
                 message: message
               }
             ] =
               Graph.check(
                 compile!(named, datamodel: @card_expiry_datamodel),
                 resolver(published())
               )

      assert message =~ ~s("expires_on")
    end

    # An unpublished child is A4's `:error` alone: there is no pair to judge.
    #
    # sabotage: judged a reference whose child is unpublished against an
    # empty interface too, in `check/2` - a `:warning` joins the `:error`
    # and this goes red (verified)
    test "an unpublished child of an unresolved reference is the chart error alone" do
      parent = compile!(registration(cards: "library.card_receipt"))
      resolver = resolver(Map.delete(published(), "library_card_issue"))

      assert [%Finding{anchor: {:config, "blk_CARDS", "chart"}, severity: :error}] =
               Graph.check(parent, resolver)
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
    # sabotage: inverted `pair/3`'s filter to `outcome in
    # child.declared_outcomes` - the stored parent is named against its own
    # published child and this goes red (verified)
    test "the published child breaks nobody" do
      assert Graph.consumers_broken(stored_child(@child), [stored_parent()]) == []
    end

    # The amendment's worked example: `verified` renamed to `confirmed`.
    #
    # sabotage: made `pair/3`'s outcome comprehension iterate nothing - the
    # stored parent is not named and this goes red (verified)
    test "the renaming revision names the stored parent" do
      assert [
               {"patron_registration",
                %Finding{
                  anchor: {:config, "blk_VERIFY", "outcomes"},
                  source: :graph,
                  severity: :error,
                  message: message
                }}
             ] = Graph.consumers_broken(stored_child(@child_next), [stored_parent()])

      assert message =~ ~s("patron_registration")
      assert message =~ ~s("verified")
    end

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
               Graph.consumers_broken(stored_child(@child_next), [
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
      assert [
               {"patron_registration",
                %Finding{
                  anchor: {:config, "blk_HOUSEHOLD", "collect_type"},
                  source: :graph,
                  severity: :error,
                  message: message
                }}
             ] = Graph.consumers_broken(stored_child(@child_next_no_key), [stored_parent()])

      assert message =~ ~s("patron_registration")
      assert message =~ ~s("verified_address")
    end

    # sabotage: dropped the `document_id == child_id` filter in
    # `consumers_broken/2` - the parent's reference to the other child is
    # judged against this one and this goes red (verified)
    test "a child revision every parent still agrees with breaks nobody" do
      parent = compile!(registration(cards: true), id: "patron_registration")
      assert Graph.consumers_broken(stored_child(@child), [parent]) == []
      assert Graph.consumers_broken(issue_card(), [parent]) == []
    end

    # ADR-0008's second amendment of 2026-09-22, U3, in the reverse
    # direction: the warning is paired with the parent and names it.
    #
    # sabotage: made `pair/3`'s unresolved arm answer `[]` - the parent's
    # unchecked read passes silently and this goes red (verified)
    test "a read left unchecked without :datamodel is a warning paired with the parent" do
      named = registration(cards: "library.card_receipt")
      parent = compile!(named, id: "patron_registration")

      assert [
               {"patron_registration",
                %Finding{
                  anchor: {:config, "blk_CARDS", "collect_type"},
                  source: :graph,
                  severity: :warning,
                  message: message
                }}
             ] = Graph.consumers_broken(issue_card(), [parent])

      assert message =~ ~s("patron_registration")
      assert message =~ ~s("library.card_receipt")
      assert message =~ "unchecked"

      checked = compile!(named, id: "patron_registration", datamodel: @card_receipt_datamodel)
      assert Graph.consumers_broken(issue_card(), [checked]) == []
    end
  end

  describe "a reference a composite's expansion placed (ADR-0004's Amendment of 2026-10-19)" do
    # The `core.subchart` is the composite's member `blk_CONFIRM_verify`,
    # which the stored loan document does not hold: the reference is
    # recorded under the composite block, the member kept beside it.
    #
    # sabotage: made `reanchor_reference/2` answer the reference unchanged -
    # it is recorded under the member id and this goes red (verified)
    test "is recorded under the composite block, the member kept as expanded_from" do
      document = loan(confirm("blk_CONFIRM"))

      assert %{references: [reference]} = compile!(document).interface

      assert reference == %{
               block_id: "blk_CONFIRM",
               expanded_from: "blk_CONFIRM_verify",
               document_id: "email_verification",
               routes_on: ["verified", "expired"],
               reads: [],
               unresolved: nil
             }

      assert "blk_CONFIRM" in stored_ids(document)
      refute "blk_CONFIRM_verify" in stored_ids(document)
    end

    # The renaming revision drops `verified`, which the member routes on.
    # The finding names a block the stored document holds, on its chrome,
    # with no config key: the member's `outcomes` field is not on the
    # composite's form, and neither is the `chart` param's for an outcome.
    #
    # sabotage: made `Graph`'s `anchor/2` ignore `expanded_from` - the
    # finding is anchored `{:config, "blk_CONFIRM", "outcomes"}` and this
    # goes red (verified)
    test "a forward finding on it is anchored on the composite block, with no config key" do
      document = loan(confirm("blk_CONFIRM"))
      resolver = resolver(%{published() | "email_verification" => stored_child(@child_next)})

      assert [
               %Finding{
                 anchor: {:block, "blk_CONFIRM"},
                 source: :graph,
                 severity: :error,
                 message: message
               }
             ] = Graph.check(compile!(document), resolver)

      assert message =~ ~s("verified")
      assert "blk_CONFIRM" in stored_ids(document)
    end

    # sabotage: made `Graph`'s `anchor/2` ignore `expanded_from` - the
    # chart finding is anchored on a field and this goes red (verified)
    test "an unresolvable child of it is anchored on the composite block too" do
      resolver = resolver(Map.delete(published(), "email_verification"))

      assert [%Finding{anchor: {:block, "blk_CONFIRM"}, source: :graph, severity: :error}] =
               Graph.check(compile!(loan(confirm("blk_CONFIRM"))), resolver)
    end

    # sabotage: made `reanchor_reference/2` answer the reference unchanged -
    # the reverse finding names the member id and this goes red (verified)
    test "a reverse finding on it is anchored on the composite block and names the parent" do
      parent = compile!(loan(confirm("blk_CONFIRM")))

      assert [
               {"book_checkout",
                %Finding{anchor: {:block, "blk_CONFIRM"}, source: :graph, message: message}}
             ] = Graph.consumers_broken(stored_child(@child_next), [parent])

      assert message =~ ~s("book_checkout")
    end

    # Two expansions deep, the reference climbs to the outermost composite,
    # the one the author placed, as E3's walk does for a compile finding.
    #
    # sabotage: made `reanchor_reference/2` take the expansion index entry
    # one level up instead of `anchor/2`'s walk - the reference is recorded
    # under the inner composite `blk_CHECKOUT_confirm` and this goes red
    # (verified)
    test "inside a nested composite it is recorded under the outermost composite" do
      document = loan(Block.new("library.checkout", id: "blk_CHECKOUT"))

      assert %{
               references: [
                 %{block_id: "blk_CHECKOUT", expanded_from: "blk_CHECKOUT_confirm_verify"}
               ]
             } = compile!(document).interface

      resolver = resolver(%{published() | "email_verification" => stored_child(@child_next)})

      assert [%Finding{anchor: {:block, "blk_CHECKOUT"}}] =
               Graph.check(compile!(document), resolver)

      assert "blk_CHECKOUT" in stored_ids(document)
    end

    # A `core.subchart` the author dropped into a pass-through slot keeps
    # its own id (T3), so its reference and its findings are its own.
    #
    # sabotage: made `reanchor_reference/2`'s no-entry arm mark the
    # reference `expanded_from` too - the author's subchart is anchored on
    # its chrome and this goes red (verified)
    test "a subchart the author placed in a pass-through slot keeps its own anchor" do
      verify =
        Block.new("core.subchart",
          id: "blk_VERIFY",
          config: %{"chart" => "email_verification", "outcomes" => "verified\nexpired"}
        )

      document =
        loan(Block.new("library.loan_desk", id: "blk_DESK", slots: %{"body" => [verify]}))

      assert %{references: [reference]} = compile!(document).interface
      refute Map.has_key?(reference, :expanded_from)
      assert reference.block_id == "blk_VERIFY"

      resolver = resolver(%{published() | "email_verification" => stored_child(@child_next)})

      assert [%Finding{anchor: {:config, "blk_VERIFY", "outcomes"}}] =
               Graph.check(compile!(document), resolver)
    end
  end

  # -- documents ---------------------------------------------------------

  defp published do
    %{"email_verification" => stored_child(@child), "library_card_issue" => issue_card()}
  end

  defp resolver(published) do
    fn document_id ->
      case Map.fetch(published, document_id) do
        {:ok, compiled} -> {:ok, compiled}
        :error -> {:error, :not_published}
      end
    end
  end

  defp stored_parent, do: compile!(document!(@parent))
  defp stored_child(name), do: compile!(document!(name), child_use: true)

  defp document!(name) do
    {:ok, document} = @dir |> Path.join(name) |> File.read!() |> Document.from_json()
    document
  end

  defp issue_card do
    compile!(
      Document.new(Block.new("library:issue_card", id: "blk_ROOT"), id: "library_card_issue"),
      child_use: true
    )
  end

  # An inline parent: a sequence that runs the verification child and, when
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

  # A checkout at the loan desk: one block, the composite under test.
  defp loan(block) do
    Document.new(Block.new("core.sequence", id: "blk_LOAN", slots: %{"body" => [block]}),
      id: "book_checkout"
    )
  end

  defp confirm(id),
    do: Block.new("library.confirm_borrower", id: id, config: %{"chart" => "email_verification"})

  # Every block id the stored document holds, before any expansion.
  defp stored_ids(%Document{root: root}), do: block_ids(root)

  defp block_ids(%Block{id: id, slots: slots}),
    do: [id | Enum.flat_map(slots, fn {_name, blocks} -> Enum.flat_map(blocks, &block_ids/1) end)]

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
