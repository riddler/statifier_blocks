defmodule StatifierBlocks.Core.OnEventTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, BlockType, Compiler, Document, Palette}
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.OnEvent

  # One record with a field of each shape the walk has to answer for: a
  # scalar, a declared record, a list, and a spelling the document declares
  # nothing for.
  @datamodel %{
    "types" => [
      %{
        "name" => "cards.declined",
        "kind" => "record",
        "label" => "Declined authorization",
        "fields" => [
          %{"name" => "reason", "type" => "string"},
          %{"name" => "txn", "type" => "cards.credit_txn"},
          %{"name" => "attempts", "type" => "list", "item_type" => "cards.credit_txn"},
          %{"name" => "vendor", "type" => "vendors.opaque"}
        ]
      },
      %{
        "name" => "cards.credit_txn",
        "kind" => "record",
        "label" => "Credit card transaction",
        "fields" => [%{"name" => "amount_minor", "type" => "integer"}]
      }
    ]
  }

  # The inline arm of `payload`, written where the payload is declared: a
  # member typed by a scalar, one typed by a declared record, and one
  # typed by a nested inline shape, so the walk's three descents are all
  # reachable without the datamodel document.
  @inline_payload [
    %{"name" => "reason", "type" => "string"},
    %{"name" => "txn", "type" => "cards.credit_txn"},
    %{
      "name" => "route",
      "type" => [%{"name" => "acquirer", "type" => "string", "required?" => true}]
    }
  ]

  # What `handler(%{"order.cancel_reason" => "reason", "order.at" =>
  # "meta.at"})` compiled to on `main` at `da10e05` - the commit this
  # branch is built on, and the last one before `capture` grew its literal
  # source arm. Captured by compiling that document in that checkout, not
  # by copying this branch's own output, which is what makes the byte
  # comparison below a claim about the arm's additivity rather than a
  # restatement of it.
  @path_only_golden ~s(<scxml initial="s_blk_OE" name="bdoc_T" version="1.0" ) <>
                      ~s(xmlns="http://www.w3.org/2005/07/scxml">) <>
                      ~s(<state id="s_blk_OE" initial="s_blk_OE__armed">) <>
                      ~s(<state id="s_blk_OE__armed">) <>
                      ~s(<transition event="order.cancelled" target="s_blk_OE__o_done">) <>
                      ~s(<assign expr="_event.data.meta.at" location="order.at"/>) <>
                      ~s(<assign expr="_event.data.reason" location="order.cancel_reason"/>) <>
                      ~s(<raise event="statifier_blocks.interrupt.abandon"/>) <>
                      ~s(</transition></state><final id="s_blk_OE__o_done"><onentry>) <>
                      ~s(<raise event="done.outcome.s_blk_OE.done"/>) <>
                      ~s(</onentry></final></state></scxml>)

  describe "validate_config/1 and the capture map" do
    # sabotage: dropped `check_capture/2` from `validate_config/1`'s pipeline
    # -> every rejected map below went green, taking this red (verified)
    test "accepts a map of datamodel path to _event.data path" do
      assert OnEvent.validate_config(capture(%{"order.cancel_reason" => "reason"})) == :ok

      assert OnEvent.validate_config(
               capture(%{"order.cancel_reason" => "reason", "order.at" => "at"})
             ) == :ok
    end

    # An absent key and an empty map are the same thing, and both are what a
    # document that never carried pairs - or carried them and no longer does -
    # looks like.
    #
    # sabotage: made `check_capture/2`'s `nil` clause report a finding -> the
    # absent case went red (verified); a second mutation dropping the
    # `is_map` clause's `Enum.all?` short-circuit took the empty case red
    # too, since `Enum.all?` over `%{}` is the arm that lets an empty map
    # through
    test "treats an absent capture and an empty one alike" do
      assert OnEvent.validate_config(Map.delete(capture(%{}), "capture")) == :ok
      assert OnEvent.validate_config(capture(%{})) == :ok
    end

    # sabotage: had `pair?/1` check only the destination -> the bad-source
    # cases went green, taking this red (verified). A second, narrower
    # mutation replacing `@whitespace` with a `[" ", "\t", "\n"]` membership
    # test left the carriage-return case green, taking it red on its own
    test "rejects a pair whose either half is not a path" do
      for bad <- [
            %{"" => "reason"},
            %{"order.cancel_reason" => ""},
            %{"order cancel_reason" => "reason"},
            %{"order.cancel_reason" => "the reason"},
            %{"order.cancel_reason" => "reason\r"},
            %{"order.cancel_reason" => "reason\t"},
            %{"order.cancel_reason" => 1},
            %{1 => "reason"}
          ] do
        assert {:error, [{"capture", _message}]} = OnEvent.validate_config(capture(bad)),
               inspect(bad)
      end
    end

    # sabotage: let the `_other` clause fall through to `findings` -> a
    # capture that is not a map at all went green, taking this red (verified)
    test "rejects a capture that is not a map" do
      for bad <- ["order.cancel_reason", ["order.cancel_reason"], 1] do
        assert {:error, [{"capture", _message}]} = OnEvent.validate_config(capture(bad)),
               inspect(bad)
      end
    end

    # ADR-0002's Note of 2026-09-12, N1: the value position takes a string
    # OR a two-element form tagged `"const"`, and every JSON type this
    # package admits in a document is admitted inside it. The float that
    # would round out that list is not tested here because it is not a
    # value a block document may carry at all - `Validation`'s `{:float,
    # path}` problem refuses it before this key is ever read.
    #
    # sabotage: dropped `source?/1`'s `["const", value]` clause so every
    # tagged source fell through to `_other` -> every case here went red
    # (verified)
    test "accepts a literal source in each JSON type a document may carry" do
      for value <- [
            "pressed_yes",
            "",
            ~s(he said "hi"),
            "back\\slash",
            "line\nbreak",
            0,
            42,
            -42,
            true,
            false,
            nil,
            [],
            [1, "two", nil],
            %{},
            %{"a" => 1, "b" => [true, "x"]}
          ] do
        assert OnEvent.validate_config(capture(%{"order.mark" => ["const", value]})) == :ok,
               inspect(value)
      end
    end

    # Shape, never content. A source that happens to spell the tag, or to
    # look like anything else, is still read as the path it is.
    #
    # sabotage: made `source?/1` test a binary for the tag's own spelling
    # before `path?/1` -> the first case went red (verified)
    test "reads a string source as a path whatever it spells" do
      for source <- ["const", "true", "null", "42", "_event"] do
        assert OnEvent.validate_config(capture(%{"order.mark" => source})) == :ok, source
      end
    end

    # The malformed tagged forms, which are the whole of what the shape
    # rule has to refuse: a wrong length, a wrong tag, a map rather than an
    # array, a nested tag in the tag's own position, and the two value
    # cases `literal/1` cannot spell so that the engine reads back what the
    # document carried - a string outside printable ASCII, and a float,
    # which reaches this key only on a document that never validated.
    #
    # sabotage: widened `source?/1`'s clause to `[_tag, value]` -> the
    # wrong-tag cases went green, taking this red; a second mutation
    # dropping `spellable?/1`'s string clause took the ASCII cases red on
    # their own (verified)
    test "rejects a tagged source that is not the two-element const form" do
      for bad <- [
            ["const"],
            ["const", "a", "b"],
            ["konst", "a"],
            ["CONST", "a"],
            [1, "a"],
            %{"const" => "a"},
            {"const", "a"},
            ["const", "café"],
            ["const", "✓"],
            ["const", <<"ctrl", 1, "char">>],
            ["const", 1.5],
            ["const", :undefined],
            ["const", ["ok", "café"]],
            ["const", %{"café" => 1}],
            ["const", %{"ok" => 1.5}],
            ["const", %{1 => "a"}]
          ] do
        assert {:error, [{"capture", _message}]} =
                 OnEvent.validate_config(capture(%{"order.mark" => bad})),
               inspect(bad)
      end
    end

    # The message is the only thing an author is shown for either form -
    # `capture` has no field to anchor a per-pair finding on - so it has to
    # name both.
    #
    # sabotage: reverted `capture_message/0` to its path-only wording ->
    # this went red (verified)
    test "names both source forms in the one message it has" do
      {:error, [{"capture", message}]} = OnEvent.validate_config(capture(%{"d" => ["const"]}))

      assert message =~ "_event.data"
      assert message =~ ~s(["const", value])
    end

    # The finding order is the order the editor renders, and `capture` is
    # checked last, so it reports last.
    #
    # sabotage: moved `check_capture/2` ahead of `check_event/2` in the
    # pipeline -> `Config.verdict/1` reversed them into a different order and
    # the ordered pattern went red (verified)
    test "reports capture after the fields declared before it" do
      assert {:error, [{"event", _}, {"outcome", _}, {"capture", _}]} =
               OnEvent.validate_config(%{"capture" => "not a map"})
    end
  end

  describe "the event field, with candidates offered for it (sb-82mu)" do
    # The editor offers the enclosing body's generated
    # `done.outcome.<state id>.<outcome>` names on this field. The field is
    # still a `:string` and this type still validates a name it has never
    # heard of - the event-name shape rule is the only gate, exactly as it
    # was - which is the half of that claim that has to hold with LiveView
    # off the load path.
    #
    # sabotage: narrowed `check_event/2` to accept only names matching the
    # generated shape -> the free-typed rows below went red and the
    # generated one stayed green (verified)
    test "accepts a free-typed event name and a generated one alike" do
      for event <- [
            "order.cancelled",
            "done.outcome.s_blk_CREDIT.approved",
            "vendor.webhook.received"
          ] do
        assert OnEvent.validate_config(%{"event" => event, "outcome" => "abandon"}) == :ok
      end
    end

    # The candidates are advisory, so the one thing this field refuses is
    # what it refused before them: nothing written at all.
    #
    # sabotage: dropped `check_event/2` from the pipeline -> this went red
    # and nothing else moved (verified)
    test "still refuses an empty event" do
      assert {:error, [{"event", _} | _rest]} =
               OnEvent.validate_config(%{"event" => "", "outcome" => "abandon"})
    end

    # `config_schema/1` is where a candidate key would have gone if the
    # field declaration had grown one. It did not: the derivation is the
    # editor's, keyed on this type, and the declaration is untouched.
    #
    # sabotage: added a `candidates:` key to the `event` declaration -> this
    # went red, which is the guard on that surface (verified)
    test "declares event as a plain required string, with no candidate key" do
      assert Enum.find(OnEvent.config_schema(%{}), &(&1.key == "event")) == %{
               key: "event",
               type: :string,
               label: "When this event arrives",
               required?: true,
               default: ""
             }
    end
  end

  describe "emit/2 and the compiled assigns" do
    # sabotage: emitted the assigns after the raise rather than before ->
    # the index comparison went red (verified)
    test "writes one assign per pair, ahead of the outcome raise" do
      scxml =
        compile!(handler(%{"order.cancel_reason" => "reason", "order.cancelled_at" => "at"}))

      assert scxml =~ ~s(<assign expr="_event.data.reason" location="order.cancel_reason"/>)
      assert scxml =~ ~s(<assign expr="_event.data.at" location="order.cancelled_at"/>)

      assert index(scxml, ~s(location="order.cancel_reason")) <
               index(scxml, "<raise ")

      assert index(scxml, ~s(location="order.cancelled_at")) <
               index(scxml, "<raise ")
    end

    # A map has no order of its own, and above 32 pairs its iteration order
    # is a hash order rather than the sorted one a small map happens to
    # give - which is exactly why the record fixes an order rather than
    # leaving the bytes to iteration. Forty pairs is what makes this
    # assertion able to fail.
    #
    # sabotage: dropped the `Enum.sort_by/2` from `captures/1` -> the emitted
    # order followed the map's iteration and this went red (verified; it
    # stays green with the sort under either map representation)
    test "orders the pairs by their datamodel paths, not by the map's iteration" do
      pairs = for n <- 0..39, into: %{}, do: {"d.k#{String.pad_leading("#{n}", 2, "0")}", "s#{n}"}

      emitted =
        pairs
        |> handler()
        |> compile!()
        |> then(&Regex.scan(~r/<assign expr="[^"]*" location="([^"]*)"\/>/, &1))
        |> Enum.map(fn [_whole, location] -> location end)

      assert emitted == Enum.sort(Map.keys(pairs))
      assert length(emitted) == 40
    end

    # The additivity claim, asserted as bytes rather than as prose: a handler
    # that carries no capture compiles to exactly what it compiled to before
    # the key existed, and an emptied one is the same handler.
    #
    # sabotage: made `captures/1`'s `nil` clause emit a single assign from a
    # hard-coded pair -> both comparisons went red (verified)
    test "compiles byte-identically to today for a handler with no capture" do
      without = compile!(Map.delete(handler(%{}).config, "capture") |> block())
      absent = compile!(handler(nil))
      empty = compile!(handler(%{}))

      assert absent == without
      assert empty == without
      refute without =~ "<assign"
    end

    # `emit/2` is checked directly rather than through a compile, for the
    # reason `emit_test.exs` gives about the guard: the Config stage rejects
    # this config first, so a compile would go red whether or not `emit/2`
    # answered for it, and the answer is the thing under test. A capture
    # silently dropped is the failure the key exists to prevent.
    #
    # sabotage: had `captures/1`'s malformed arm return `{:ok, []}` ->
    # `emit/2` answered `{:ok, ...}` with the pair dropped and no assign
    # emitted, taking this red (verified)
    test "refuses a malformed capture rather than dropping the pair" do
      assert {:error, [{"capture", _message}]} =
               OnEvent.emit(
                 block(%{
                   "event" => "order.cancelled",
                   "outcome" => "abandon",
                   "capture" => %{"order.cancel_reason" => ""}
                 }),
                 Context.new("blk_OE", "bdoc_T")
               )
    end
  end

  describe "what the interpreter does with a captured path" do
    # The record's run-time claim, pinned against the engine rather than
    # against the record: a source path the payload does not carry is
    # written as the engine's explicit unbound marker, and that marker is
    # not `nil`. A consumer of a captured path tests for it; the
    # `error.execution` the record's bullet describes is upstream work and
    # is deliberately NOT asserted here, because it does not happen today.
    #
    # sabotage: none available in this package - the behaviour under test is
    # the engine's, and this test is here to go red if a version bump
    # changes it. Its own construction was verified instead by asserting
    # `nil` in place of the marker, which went red on the real engine.
    test "writes the unbound marker, not nil, for a payload key that is not there" do
      {machine_state, _effects} =
        run(%{"order.cancel_reason" => "reason"}, %{"order" => %{}})

      captured = machine_state.datamodel |> Map.fetch!("order") |> Map.fetch!("cancel_reason")

      assert captured == :undefined
      refute captured == nil
    end

    # The other half of the pair, so the test above is read as "the payload
    # was missing" rather than "capture never writes anything".
    #
    # sabotage: dropped the assigns from the transition's children -> the
    # path was never written and this went red (verified)
    test "writes the payload value when the source path is there" do
      {machine_state, _effects} =
        run(%{"order.cancel_reason" => "reason"}, %{"order" => %{}},
          data: %{"reason" => "customer_request"}
        )

      assert machine_state.datamodel["order"]["cancel_reason"] == "customer_request"
    end
  end

  describe "the payload declaration" do
    # sabotage: dropped the `payload` declaration from `config_schema/1` ->
    # this went red, and so did the field-order assertion in
    # `core_types_test.exs`, which is the editor's only route to the field
    # (verified)
    test "declares payload as an optional type-expression field admitting both arms" do
      assert Enum.find(OnEvent.config_schema(%{}), &(&1.key == "payload")) == %{
               key: "payload",
               type: {:type_expr, %{arms: [:name, :inline]}},
               label: "Its payload is",
               required?: false,
               default: ""
             }
    end

    # The name resolving is not this callback's question: an unresolvable
    # name is the amendment's P4 case, unchanged behaviour. Nor is what an
    # arm may be - that is the shared check's, asserted below - so this
    # callback reports nothing about the field at all.
    #
    # sabotage: put a `check_payload/2` back into the pipeline refusing a
    # value that is not a string -> the inline arm stops validating here
    # and this goes red (verified)
    test "accepts an absent, a blank, a named and an inline payload" do
      assert OnEvent.validate_config(%{"event" => "cards.declined", "outcome" => "abandon"}) ==
               :ok

      assert OnEvent.validate_config(payload_config("")) == :ok
      assert OnEvent.validate_config(payload_config("cards.declined")) == :ok
      assert OnEvent.validate_config(payload_config("kaboom.not.declared")) == :ok
      assert OnEvent.validate_config(payload_config(@inline_payload)) == :ok
      assert OnEvent.validate_config(payload_config(%{})) == :ok
    end

    # The half `validate_config/1` no longer answers for: bytes that are
    # neither arm are refused, once, by the one check every
    # `{:type_expr, opts}` field shares - at compile, on the field's key.
    #
    # sabotage: declared `payload` as `:string` again -> the shared check
    # skips the field, the map compiles clean, and this goes red (verified)
    test "a payload that is neither arm is refused by the shared check, on its own key" do
      assert [finding] =
               BlockType.type_expr_findings(OnEvent, payload_config(%{}))
               |> Enum.map(&elem(&1, 0))

      assert finding == "payload"

      assert BlockType.type_expr_findings(OnEvent, payload_config("cards.declined")) == []
      assert BlockType.type_expr_findings(OnEvent, payload_config(@inline_payload)) == []
      assert BlockType.type_expr_findings(OnEvent, payload_config("")) == []
    end
  end

  describe "the declared payload's refusal at compile" do
    # sabotage: made `payload_capture_findings/2` return `[]` for every
    # input -> this went red, with the two other tests that assert a
    # refusal, and every test that asserts a compile stayed green
    # (verified)
    test "refuses a pair reading a member the declared payload does not carry" do
      assert {:error, [finding]} = typed_compile(%{"card.why" => "code"}, "cards.declined")

      assert %Compiler.Finding{
               stage: :config,
               block_id: "blk_OE",
               config_key: "capture",
               severity: :error,
               fault: :author
             } = finding

      assert finding.message =~ "card.why"
      assert finding.message =~ "code"
      assert finding.message =~ "cards.declined"
    end

    # sabotage: made `carries?/3` return `false` for every path -> this went
    # red, which is the guard against a refusal that refuses every read
    # (verified)
    test "compiles a pair reading a declared member" do
      assert {:ok, _compiled} = typed_compile(%{"card.why" => "reason"}, "cards.declined")
    end

    # One finding for the whole key, naming every pair that reads past the
    # payload, in the destinations' sorted order - the order the assigns
    # themselves are emitted in.
    #
    # sabotage: reported one finding per offending pair -> the single-element
    # match went red (verified)
    test "reports one finding for the key, naming each offending pair" do
      assert {:error, [finding]} =
               typed_compile(%{"card.why" => "code", "card.at" => "when"}, "cards.declined")

      assert finding.config_key == "capture"
      assert index(finding.message, "card.at") < index(finding.message, "card.why")
    end

    # sabotage: had `descend/3`'s `{:declared, name}` clause return `true`
    # rather than walking -> the second assertion went red (verified)
    test "walks a deeper segment through a field whose type is itself declared" do
      assert {:ok, _compiled} =
               typed_compile(%{"card.amount" => "txn.amount_minor"}, "cards.declined")

      assert {:error, [_finding]} =
               typed_compile(%{"card.amount" => "txn.no_such_field"}, "cards.declined")
    end

    # P5's depth rule: a field this package cannot see into stops the walk
    # and refuses nothing beyond it. A scalar, a list and an opaque
    # spelling are the three ways that happens.
    #
    # sabotage: made `descend/3`'s catch-all return `false` -> all three
    # went red (verified)
    test "stops the walk at a scalar, a list and an opaque field type" do
      assert {:ok, _scalar} = typed_compile(%{"card.why" => "reason.deeper"}, "cards.declined")
      assert {:ok, _list} = typed_compile(%{"card.why" => "attempts.deeper"}, "cards.declined")
      assert {:ok, _opaque} = typed_compile(%{"card.why" => "vendor.deeper"}, "cards.declined")
    end

    # The amendment's P4, by both its routes: a payload naming a type the
    # document does not declare, and a compile with no datamodel at all.
    # Neither refuses anything, and neither is a finding of its own.
    #
    # sabotage: refused a payload whose name resolves to nothing -> the
    # first assertion went red (verified)
    test "refuses nothing when the payload resolves to nothing" do
      assert {:ok, _unresolvable} =
               typed_compile(%{"card.why" => "code"}, "cards.not_declared")

      assert {:ok, _no_datamodel} =
               Compiler.compile(
                 Document.new(payload_handler(%{"card.why" => "code"}, "cards.declined"),
                   id: "bdoc_T"
                 ),
                 Palette.core()
               )
    end

    # The same refusal from the other arm. An inline payload needs no
    # datamodel document to be read: the members are written where the
    # payload is.
    #
    # sabotage: dropped `declared_payload/2`'s list clause -> an inline
    # payload resolves to nothing, the refusal stops firing, and the first
    # assertion goes red (verified)
    test "refuses a pair reading a member an inline payload does not carry" do
      assert {:error, [finding]} = inline_compile(%{"card.why" => "code"})

      assert %Compiler.Finding{
               stage: :config,
               block_id: "blk_OE",
               config_key: "capture",
               severity: :error,
               fault: :author
             } = finding

      assert finding.message =~ "card.why"
      assert finding.message =~ "code"
      assert finding.message =~ "inline payload"

      assert {:ok, _read} = inline_compile(%{"card.why" => "reason"})
    end

    # P5's depth rule reaching an inline member, both ways it can descend:
    # a member typed by a declared name resolves through the datamodel
    # document, and a member typed by a nested inline shape walks its own
    # members.
    #
    # sabotage: dropped `descend/3`'s `{:shape, members}` clause -> the
    # nested shape stops the walk instead of descending, and the fourth
    # assertion goes red (verified)
    test "walks below an inline member, through a declared name and a nested shape" do
      assert {:ok, _named} = inline_compile(%{"card.amount" => "txn.amount_minor"})
      assert {:error, [_named]} = inline_compile(%{"card.amount" => "txn.no_such_field"})

      assert {:ok, _nested} = inline_compile(%{"card.route" => "route.acquirer"})
      assert {:error, [_nested]} = inline_compile(%{"card.route" => "route.no_such_member"})

      # And a member typed by a scalar stops the walk, as a declared
      # field typed by one does.
      assert {:ok, _scalar} = inline_compile(%{"card.why" => "reason.deeper"})
    end

    # An inline payload writing no well-formed member carries no member,
    # so every read is a read past it - which is what a payload naming a
    # declaration with no fields already does.
    #
    # sabotage: made `declared_payload/2` answer `:error` for an empty
    # member list -> the refusal stops firing and this goes red (verified)
    test "an inline payload with no members carries none" do
      assert {:error, [finding]} =
               typed_compile(%{"card.why" => "reason"}, [%{"no" => "name"}])

      assert finding.config_key == "capture"
    end

    # The untyped document, unchanged: no payload, no finding, and the same
    # bytes the handler compiled to before the key existed.
    #
    # sabotage: made an absent payload resolve to a declaration with no
    # fields, so an untyped handler refuses every pair -> this went red,
    # with every other test that captures without declaring (verified)
    test "leaves a handler with no payload exactly as it was" do
      typed =
        Compiler.compile(
          Document.new(handler(%{"order.cancel_reason" => "nowhere_in_any_payload"}),
            id: "bdoc_T"
          ),
          Palette.core(),
          datamodel: @datamodel
        )

      assert {:ok, compiled} = typed

      assert compiled.scxml ==
               compile!(handler(%{"order.cancel_reason" => "nowhere_in_any_payload"}))
    end

    # `payload` is a declaration and not an emission: the compiled bytes are
    # the ones the same handler compiles to without it.
    #
    # sabotage: emitted the payload name as an attribute on the transition
    # -> this went red (verified)
    test "emits nothing of its own" do
      {:ok, declared} =
        Compiler.compile(
          Document.new(payload_handler(%{"card.why" => "reason"}, "cards.declined"), id: "bdoc_T"),
          Palette.core(),
          datamodel: @datamodel
        )

      assert declared.scxml == compile!(payload_handler(%{"card.why" => "reason"}, nil))
    end
  end

  describe "a literal capture source (ADR-0002's Note of 2026-09-12, N1)" do
    # The measurement that asked for the arm (campaign SF040's capture k2),
    # asserted the way it was found missing: two handlers on one screen,
    # each recording which of them fired, with nothing in either payload.
    # The host contributes no data at all here, which is the point - before
    # this arm the two buttons could only be told apart by what the host
    # chose to put in the payload.
    #
    # sabotage: had `source_expr/1`'s const clause emit `"_event.data." <>
    # tag` -> both reads came back as the unbound marker and this went red
    # (verified)
    test "records a distinct literal per handler on a two-button screen" do
      machine_state =
        run_two(
          {"screen.yes", %{"answer.choice" => ["const", "yes"]}},
          {"screen.no", %{"answer.choice" => ["const", "no"]}},
          "screen.no"
        )

      assert machine_state.datamodel |> Map.fetch!("answer") |> Map.fetch!("choice") == "no"

      machine_state =
        run_two(
          {"screen.yes", %{"answer.choice" => ["const", "yes"]}},
          {"screen.no", %{"answer.choice" => ["const", "no"]}},
          "screen.yes"
        )

      assert machine_state.datamodel |> Map.fetch!("answer") |> Map.fetch!("choice") == "yes"
    end

    # The spelling decision this request takes, pinned end to end rather
    # than as bytes: whatever `literal/1` writes, the engine has to read
    # back the value the document carried. Run against the real engine, so
    # it goes red if predicator's literal grammar moves under a version
    # bump - which is the risk a spelling decision carries.
    #
    # sabotage: dropped `escape/1`'s backslash replacement -> the two
    # backslash cases came back short a character, taking this red; a
    # second mutation emitting a raw newline rather than `\n` took the
    # newline case red on its own, because XML attribute-value
    # normalisation turns the raw byte into a space (verified)
    test "reads back the document's own value, for each type it admits" do
      for value <- [
            "pressed_yes",
            "",
            ~s(he said "hi"),
            "back\\slash",
            "a\\\"b",
            "line\nbreak",
            "tab\there",
            0,
            42,
            -42,
            true,
            false,
            nil,
            [],
            [1, 2],
            ["a", nil, true],
            %{},
            %{"b" => 2, "a" => 1},
            %{"nested" => %{"x" => [1, "two", false]}}
          ] do
        {machine_state, _effects} =
          run(%{"order.mark" => ["const", value]}, %{"order" => %{}})

        read = machine_state.datamodel |> Map.fetch!("order") |> Map.fetch!("mark")

        assert read == value, "#{inspect(value)} read back as #{inspect(read)}"
      end
    end

    # An object's keys are sorted for the reason the pairs themselves are:
    # a map has no order of its own and a compile has to be deterministic.
    # Forty keys for the reason the pair-ordering test gives: below 32 a
    # map iterates in a sorted order of its own accord, so a smaller object
    # could not fail this.
    #
    # sabotage: dropped `literal/1`'s `Enum.sort_by/2` over the object's
    # pairs -> the emitted bytes followed the map's iteration and this went
    # red (verified; at ten keys the same mutation stayed green, which is
    # what forty is here for)
    test "spells an object's keys in sorted order" do
      value = for n <- 0..39, into: %{}, do: {"k#{String.pad_leading("#{n}", 2, "0")}", n}

      expected =
        value
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.map_join(",", fn {key, member} -> "&quot;#{key}&quot;:#{member}" end)

      scxml = compile!(handler(%{"order.mark" => ["const", value]}))

      assert scxml =~ ~s(expr="{#{expected}}")
    end

    # Consent clause 8's additivity proof, as bytes: a document whose every
    # capture uses the path form compiles to exactly what it compiled to
    # before this request existed. The expected bytes were captured by
    # compiling this same document on `main` at `da10e05`, which is the
    # commit this branch is built on and the last one before the const arm.
    #
    # sabotage: made `source_expr/1`'s path clause prefix `_event.` rather
    # than `_event.data.` -> this went red (verified)
    test "compiles a path-only document to the bytes it compiled to before the const arm" do
      pairs = %{"order.cancel_reason" => "reason", "order.at" => "meta.at"}

      assert compile!(handler(pairs)) == @path_only_golden
    end

    # Advisory (a) on this bead, built rather than written down: P5 is a
    # rule about a source PATH, so a literal pair is never reached by it.
    # A handler may declare a payload and capture a literal beside a path
    # read out of it, and the literal is not a member the payload is asked
    # for.
    #
    # sabotage: dropped `unread_pairs/3`'s `path?(source)` filter -> the
    # literal pair was walked as a path, `carries?/3` answered false for
    # the list, and the first assertion went red (verified)
    test "does not read a literal pair against the declared payload" do
      assert {:ok, _compiled} =
               typed_compile(
                 %{"card.why" => "reason", "card.mark" => ["const", "declined"]},
                 "cards.declined"
               )

      assert {:error, [finding]} =
               typed_compile(
                 %{"card.why" => "nope", "card.mark" => ["const", "declined"]},
                 "cards.declined"
               )

      assert finding.config_key == "capture"
      assert finding.message =~ "nope"
      refute finding.message =~ "card.mark"
    end
  end

  # -- helpers ---------------------------------------------------------------

  defp payload_config(value) do
    %{"event" => "cards.declined", "outcome" => "abandon", "payload" => value}
  end

  defp payload_handler(pairs, payload) do
    config = %{"event" => "cards.declined", "outcome" => "abandon", "capture" => pairs}

    Block.new("core.on_event",
      id: "blk_OE",
      config: if(payload == nil, do: config, else: Map.put(config, "payload", payload))
    )
  end

  defp inline_compile(pairs), do: typed_compile(pairs, @inline_payload)

  defp typed_compile(pairs, payload) do
    Compiler.compile(
      Document.new(payload_handler(pairs, payload), id: "bdoc_T"),
      Palette.core(),
      datamodel: @datamodel
    )
  end

  defp capture(value), do: %{"event" => "order.cancelled", "outcome" => "abandon"} |> put(value)

  defp put(config, value), do: Map.put(config, "capture", value)

  defp handler(pairs) do
    block(%{"event" => "order.cancelled", "outcome" => "abandon", "capture" => pairs})
  end

  defp block(config), do: Block.new("core.on_event", id: "blk_OE", config: config)

  defp compile!(%Block{} = root) do
    {:ok, compiled} = Compiler.compile(Document.new(root, id: "bdoc_T"), Palette.core())
    compiled.scxml
  end

  defp index(haystack, needle) do
    [{start, _length}] = Regex.run(~r/#{Regex.escape(needle)}/, haystack, return: :index)
    start
  end

  # A capturing handler in a group whose body waits, so the interrupt has
  # something live to interrupt, run to the point just after the event has
  # fired the handler.
  defp run(pairs, datamodel, opts \\ []) do
    root =
      Block.new("core.group",
        id: "blk_GRP",
        slots: %{
          "body" => [Block.new("core.wait", id: "blk_STEP", config: %{"duration" => "48h"})],
          "interrupts" => [
            Block.new("core.on_event",
              id: "blk_INT",
              config: %{
                "event" => "order.cancelled",
                "outcome" => "abandon",
                "capture" => pairs
              }
            )
          ]
        }
      )

    {:ok, machine} = Statifier.compile(compile!(root))
    {machine_state, _effects} = Statifier.initialize(machine, datamodel: datamodel)

    {:ok, machine_state, effects} =
      Statifier.send_event(
        machine_state,
        Statifier.Event.external("order.cancelled", Keyword.take(opts, [:data]))
      )

    {machine_state, effects}
  end

  # Two handlers in one group's interrupts, each with its own event and its
  # own capture map - the two-button screen `k2` measured - run to the
  # point just after `fired` has fired one of them. No payload is sent, so
  # everything either handler writes came out of the document.
  defp run_two({left_event, left_pairs}, {right_event, right_pairs}, fired) do
    handler = fn id, event, pairs ->
      Block.new("core.on_event",
        id: id,
        config: %{"event" => event, "outcome" => "abandon", "capture" => pairs}
      )
    end

    root =
      Block.new("core.group",
        id: "blk_GRP",
        slots: %{
          "body" => [Block.new("core.wait", id: "blk_STEP", config: %{"duration" => "48h"})],
          "interrupts" => [
            handler.("blk_LEFT", left_event, left_pairs),
            handler.("blk_RIGHT", right_event, right_pairs)
          ]
        }
      )

    {:ok, machine} = Statifier.compile(compile!(root))
    {machine_state, _effects} = Statifier.initialize(machine, datamodel: %{"answer" => %{}})

    {:ok, machine_state, _effects} =
      Statifier.send_event(machine_state, Statifier.Event.external(fired, []))

    machine_state
  end
end
