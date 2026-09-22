defmodule StatifierBlocks.AcceptsTest do
  @moduledoc """
  A document's `accepts` list (ADR-0014): the envelope key, its four
  refusals, the canonical bytes, the edit command that writes it, the panel
  arithmetic, and the compile carry onto `%Compiled{}` and
  `%CompilationRecord{}`.

  Pure: nothing here names LiveView, so it runs in the headless job too. The
  panel as an author drives it is `StatifierBlocks.Editor.AcceptedEventsTest`.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{
    Block,
    CompilationRecord,
    Compiled,
    Compiler,
    Declarations,
    Document,
    DocumentFixtures,
    Edit,
    Palette,
    Validation
  }

  alias StatifierBlocks.Edit.Session

  @patron_accepts ["email.verified", "registration.abandoned"]

  defp bare(accepts) do
    %{Document.new(Block.new("core.wait", id: "blk_leaf"), id: "bdoc_fixed") | accepts: accepts}
  end

  describe "the envelope key (decision 2)" do
    # Sabotage: `Document`'s `defstruct` defaulting `accepts: nil` - a struct
    # built literally carries `nil`, `validate/1` refuses it as
    # `:not_a_list`, and this goes red.
    test "defaults to [] on the struct" do
      document = %Document{id: "bdoc_fixed", root: Block.new("core.wait", id: "blk_leaf")}

      assert document.accepts == []
      assert Document.validate(document) == :ok
    end

    # Sabotage: `Document.new/2` ignoring the `:accepts` option - the list
    # built here is `[]` and the assertion goes red.
    test "new/2 takes the list as an option" do
      document = Document.new(Block.new("core.wait", id: "blk_leaf"), accepts: ["loan.renew"])

      assert document.accepts == ["loan.renew"]
    end
  end

  describe "Document.validate/1's four refusals (decision 2)" do
    # Sabotage: widening `check_accepts/1`'s guard to `is_list(names) or
    # is_map(names)` - a map reaches `check_accepts_entries/2`, which has no
    # map clause, and the refusal becomes a crash.
    test "refuses a value that is not a list" do
      assert Document.validate(bare(%{"email.verified" => true})) ==
               {:error, {:malformed_envelope, {:accepts, :not_a_list}}}

      assert Document.validate(bare("email.verified")) ==
               {:error, {:malformed_envelope, {:accepts, :not_a_list}}}
    end

    # Sabotage: `check_accepts_entry/2`'s general clause answering `:ok` for
    # any term - an atom and an integer pass, and a document the canonical
    # encoder cannot write as JSON strings validates.
    test "refuses an entry that is not a string, naming its index" do
      assert Document.validate(bare(["email.verified", :loan_due])) ==
               {:error, {:malformed_envelope, {:accepts, {:entry, 1, :not_a_string}}}}

      assert Document.validate(bare([42])) ==
               {:error, {:malformed_envelope, {:accepts, {:entry, 0, :not_a_string}}}}

      assert Document.validate(bare(["copy.returned", <<0xFF>>])) ==
               {:error, {:malformed_envelope, {:accepts, {:entry, 1, :not_a_string}}}}
    end

    # Sabotage: dropping `check_accepts_entry/2`'s `""` clause - an empty
    # string is a valid UTF-8 binary, passes as a name, and this goes red.
    test "refuses an empty name, naming its index" do
      assert Document.validate(bare(["loan.due", ""])) ==
               {:error, {:malformed_envelope, {:accepts, {:entry, 1, :empty}}}}
    end

    # Sabotage: `check_accepts/1` skipping `check_accepts_unique/1` - a list
    # naming one event twice validates and this goes red.
    test "refuses a name already in the list, naming the name" do
      assert Document.validate(bare(["loan.due", "loan.renew", "loan.due"])) ==
               {:error, {:malformed_envelope, {:accepts, {:duplicate_name, "loan.due"}}}}
    end

    # Sabotage: running `check_accepts_unique/1` before the entry pass - the
    # repeated `42` is reported as a duplicate rather than as not a string.
    test "reports the first entry at fault, shape before uniqueness" do
      assert Document.validate(bare([42, 42])) ==
               {:error, {:malformed_envelope, {:accepts, {:entry, 0, :not_a_string}}}}

      assert Document.validate(bare(["loan.due", "", ""])) ==
               {:error, {:malformed_envelope, {:accepts, {:entry, 1, :empty}}}}
    end

    # The record decides no grammar past the four refusals: a pattern-looking
    # or unusual name is not refused here (decision 4 finds a name no
    # descriptor can match, at publish).
    #
    # Sabotage: `check_accepts_entry/2` also requiring
    # `String.match?(name, ~r/\A[a-z.]+\z/)` - `*` and `patron blocked` are
    # refused and this goes red.
    test "asks nothing of a name past those four" do
      assert Document.validate(bare(["*", "patron blocked", "loan.renew"])) == :ok
    end

    # Sabotage: dropping `check_accepts/1` from `validate_envelope/1`'s `with`
    # - a malformed list validates, and `to_json/1` writes bytes that claim
    # to be canonical.
    test "is part of validate/1, so the compiler's document stage reports it" do
      document = %{DocumentFixtures.patron_registration() | accepts: ["loan.due", "loan.due"]}

      assert {:error, [finding]} = Compiler.compile(document, Palette.core())

      assert finding.reason ==
               {:invalid_document,
                {:malformed_envelope, {:accepts, {:duplicate_name, "loan.due"}}}}
    end

    # `Validation.accepts/1` is the one implementation the edit command
    # calls. Sabotage: `accepts/1` returning `:ok` - the edit tests below go
    # red on the refusals, and so does this.
    test "Validation.accepts/1 answers exactly what validate/1 answers" do
      assert Validation.accepts(["loan.due"]) == :ok

      assert Validation.accepts(["loan.due", ""]) ==
               {:error, {:malformed_envelope, {:accepts, {:entry, 1, :empty}}}}
    end
  end

  describe "the canonical bytes (decision 2)" do
    # Sabotage: dropping the `maybe_put_list(pairs, "accepts", ...)` call
    # from `CanonicalJson.encode/1` - the declaration never reaches the
    # bytes, and the fixture's bytes stop matching.
    test "the patron registration fixture encodes to its stored bytes" do
      assert Document.to_json(DocumentFixtures.patron_registration()) ==
               DocumentFixtures.patron_registration_json()
    end

    # The pin the record asks for: every document written before the key
    # existed keeps its bytes and its hash. The two other shipped fixtures'
    # stored bytes are the bytes they were written with, so hashing those
    # bytes directly is the hash they had before `accepts` existed.
    #
    # Sabotage: `maybe_put_list/3`'s `[]` clause removed, so an empty list
    # is written as `"accepts":[]` - both fixtures' bytes and hashes move
    # and this goes red.
    test "an empty or absent accepts leaves every existing document's hash unchanged" do
      for {document, stored} <- [
            {DocumentFixtures.worked_example(), DocumentFixtures.worked_example_json()},
            {DocumentFixtures.signup_wizard(), DocumentFixtures.signup_wizard_json()}
          ] do
        pinned = "sha256:" <> Base.encode16(:crypto.hash(:sha256, stored), case: :lower)

        assert document.accepts == []
        assert Document.to_json(document) == stored
        assert Document.content_hash(document) == pinned
        refute stored =~ "accepts"
      end
    end

    # Sabotage: as above - `[]` written as `"accepts":[]` makes the empty
    # declaration a different spelling from the absent one.
    test "an empty list and an absent key are the same bytes" do
      empty = bare([])

      assert Document.to_json(empty) ==
               ~s({"id":"bdoc_fixed","revision":0,) <>
                 ~s("root":{"id":"blk_leaf","type":"core.wait","type_version":1},) <>
                 ~s("schema_version":1})

      assert {:ok, decoded} = Document.from_json(Document.to_json(empty))
      assert decoded.accepts == []
    end

    # Sabotage: sorting `document.accepts` in `CanonicalJson.encode/1` - the
    # two orders below encode identically and this goes red.
    test "a non-empty list is in the bytes and the hash, in the author's order" do
      forward = bare(["loan.renew", "loan.due"])
      backward = bare(["loan.due", "loan.renew"])

      assert Document.to_json(forward) =~ ~s("accepts":["loan.renew","loan.due"])
      refute Document.content_hash(forward) == Document.content_hash(backward)
      refute Document.content_hash(forward) == Document.content_hash(bare([]))
    end
  end

  describe "the decoder (decision 2)" do
    # Sabotage: dropping `"accepts"` from `Decode`'s `@envelope_keys` - the
    # fixture is refused with `{:unexpected_key, "accepts"}`, the refusal a
    # reader from before the key gives it, and this goes red.
    test "the fixture bytes decode to the hand-built document" do
      assert Document.from_json(DocumentFixtures.patron_registration_json()) ==
               {:ok, DocumentFixtures.patron_registration()}
    end

    # Sabotage: `Decode.decode/1` reading `Map.get(envelope, "accepts")`
    # with no default - an absent key decodes to `nil`, `validate/1` refuses
    # it as `:not_a_list`, and every existing document stops decoding.
    test "an absent key decodes to []" do
      assert {:ok, %Document{accepts: []}} =
               Document.from_json(DocumentFixtures.signup_wizard_json())
    end

    # The decoder passes the value through and `validate/1` answers, so the
    # refusal has one implementation. Sabotage: `Decode.decode/1` filtering
    # the list with `Enum.filter(&is_binary/1)` before building the struct -
    # the non-string entry disappears and the document decodes.
    test "a malformed value reaches validate/1's refusals unchanged" do
      envelope =
        ~s({"id":"bdoc_x","revision":0,"schema_version":1,) <>
          ~s("root":{"id":"blk_root","type":"core.wait","type_version":1},)

      assert Document.from_json(envelope <> ~s("accepts":"loan.due"})) ==
               {:error, {:malformed_envelope, {:accepts, :not_a_list}}}

      assert Document.from_json(envelope <> ~s("accepts":["loan.due",7]})) ==
               {:error, {:malformed_envelope, {:accepts, {:entry, 1, :not_a_string}}}}

      assert Document.from_json(envelope <> ~s("accepts":[""]})) ==
               {:error, {:malformed_envelope, {:accepts, {:entry, 0, :empty}}}}

      assert Document.from_json(envelope <> ~s("accepts":["a","a"]})) ==
               {:error, {:malformed_envelope, {:accepts, {:duplicate_name, "a"}}}}
    end
  end

  describe "{:set_accepts, names} (decision 6)" do
    # Sabotage: returning `{:set_accepts, names}` as the inverse instead of
    # `{:set_accepts, document.accepts}` - undo becomes a second do.
    test "replaces the whole list, and its inverse is the list that was there" do
      document = %{DocumentFixtures.patron_registration() | accepts: ["email.verified"]}

      assert {:ok, updated, inverse} = Edit.apply(document, {:set_accepts, @patron_accepts})

      assert updated.accepts == @patron_accepts
      assert inverse == {:set_accepts, ["email.verified"]}
      assert {:ok, ^document, _forward_again} = Edit.apply(updated, inverse)
    end

    # Sabotage: `apply/2` writing `accepts` without calling
    # `Validation.accepts/1` - a refused list lands, and `to_json/1` raises
    # on a document the editor produced.
    test "refuses every list validate/1 refuses, in the same arms" do
      document = DocumentFixtures.patron_registration()

      assert Edit.apply(document, {:set_accepts, ["a", "a"]}) ==
               {:error, {:malformed_envelope, {:accepts, {:duplicate_name, "a"}}}}

      assert Edit.apply(document, {:set_accepts, [""]}) ==
               {:error, {:malformed_envelope, {:accepts, {:entry, 0, :empty}}}}

      assert Edit.apply(document, {:set_accepts, [:loan_due]}) ==
               {:error, {:malformed_envelope, {:accepts, {:entry, 0, :not_a_string}}}}

      assert Edit.apply(document, {:set_accepts, "loan.due"}) ==
               {:error, {:malformed_envelope, {:accepts, :not_a_list}}}
    end

    # Sabotage: dropping the `maybe_put_list(pairs, "accepts", ...)` call
    # from `CanonicalJson.encode/1` - the edited list never reaches the bytes.
    test "produces a document that validates and encodes" do
      assert {:ok, updated, _inverse} =
               Edit.apply(bare([]), {:set_accepts, ["patron.blocked"]})

      assert Document.validate(updated) == :ok
      assert Document.to_json(updated) =~ ~s("accepts":["patron.blocked"])
    end

    # Sabotage: dropping the `:set_accepts` clause from `check_config/3` -
    # no other clause matches a two-element `{:set_accepts, _}` tuple, so the
    # gate raises FunctionClauseError inside the editor's funnel.
    test "check_config/3 has no block type to ask, so it passes the gate" do
      document = DocumentFixtures.patron_registration()

      assert Edit.check_config(Palette.core(), document, {:set_accepts, ["loan.due"]}) == :ok
    end

    # Sabotage: dropping `Session.refusal/1`'s `:accepts` clause - the
    # sentence falls through to the generic envelope one.
    test "a refusal is phrased once, by the panel's helper" do
      reason = {:malformed_envelope, {:accepts, {:duplicate_name, "loan.due"}}}

      assert Session.refusal(reason) == Declarations.refusal(reason)
      assert Session.refusal(reason) =~ "loan.due"
    end

    # Sabotage: dropping `apply/2`'s `:set_accepts` clause - no clause
    # matches the leaf, and the compound raises FunctionClauseError.
    test "is one leaf of a compound like any other command" do
      document = bare([])

      assert {:ok, updated, inverse} =
               Edit.apply(
                 document,
                 {:compound, [{:set_accepts, ["loan.due"]}, {:set_accepts, ["loan.renew"]}]}
               )

      assert updated.accepts == ["loan.renew"]
      assert {:ok, ^document, _again} = Edit.apply(updated, inverse)
    end
  end

  describe "the panel arithmetic (decision 6)" do
    # Sabotage: `add_accepted/1` appending `"event_1"` unconditionally - the
    # second press mints a name the list already holds, which the command
    # refuses as a duplicate.
    test "add_accepted/1 mints the first free placeholder name" do
      assert Declarations.add_accepted([]) == ["event_1"]
      assert Declarations.add_accepted(["event_1"]) == ["event_1", "event_2"]
      assert Declarations.add_accepted(["event_2"]) == ["event_2", "event_1"]
      assert Validation.accepts(Declarations.add_accepted(["event_1", "loan.due"])) == :ok
    end

    # Sabotage: `put_accepted/3` writing with no range check - an index off
    # the end raises from `List.replace_at/3`'s caller or grows the list.
    test "put_accepted/3 writes the name at an index, and nothing out of range" do
      assert Declarations.put_accepted(["event_1", "loan.due"], 0, "copy.returned") ==
               ["copy.returned", "loan.due"]

      assert Declarations.put_accepted(["event_1"], 5, "copy.returned") == ["event_1"]
      assert Declarations.put_accepted(["event_1"], :none, "copy.returned") == ["event_1"]
      assert Declarations.put_accepted(["event_1"], 0, "") == [""]
    end

    # Sabotage: dropping `refusal/1`'s `{:accepts, reason}` clause - every
    # sentence below falls through to "That change was refused." and the
    # author is not told which name to fix.
    test "refusal/1 phrases each of the four arms" do
      assert Declarations.refusal(
               {:malformed_envelope, {:accepts, {:duplicate_name, "loan.due"}}}
             ) =~ ~s("loan.due")

      assert Declarations.refusal({:malformed_envelope, {:accepts, {:entry, 1, :empty}}}) =~
               "Accepted event 2"

      assert Declarations.refusal({:malformed_envelope, {:accepts, {:entry, 0, :not_a_string}}}) =~
               "Accepted event 1"

      assert Declarations.refusal({:malformed_envelope, {:accepts, :not_a_list}}) ==
               "That change was refused."
    end
  end

  describe "the compile carry (decision 3)" do
    # Sabotage: dropping `accepts: document.accepts` from either struct in
    # `Compiler`'s `chart_stage/5` or `record/3` - that field comes back
    # `[]` and one assertion goes red.
    test "carries the fixture's declared list onto %Compiled{} and %CompilationRecord{}" do
      document = DocumentFixtures.patron_registration()

      assert {:ok, %Compiled{} = compiled} = Compiler.compile(document, Palette.core())

      assert compiled.accepts == ["email.verified", "registration.abandoned"]

      assert %CompilationRecord{accepts: ["email.verified", "registration.abandoned"]} =
               compiled.record
    end

    # Sabotage: `chart_stage/5` carrying `Enum.sort(document.accepts)` - the
    # reversed order comes back sorted and this goes red.
    test "carries the list exactly as written, order included" do
      reversed = Enum.reverse(@patron_accepts)
      document = %{DocumentFixtures.patron_registration() | accepts: reversed}

      assert {:ok, compiled} = Compiler.compile(document, Palette.core())

      assert compiled.accepts == reversed
      assert compiled.record.accepts == reversed
    end

    # Nothing about the declaration reaches the chart, so chart identity does
    # not move when an author edits it; the document hash does.
    #
    # Sabotage: `chart_stage/5` appending `inspect(document.accepts)` to the
    # serialized SCXML - the two charts differ and so do their identities.
    test "never enters the chart: the SCXML and chart identity are unmoved" do
      declared = DocumentFixtures.patron_registration()
      undeclared = %{declared | accepts: []}

      assert {:ok, with_list} = Compiler.compile(declared, Palette.core())
      assert {:ok, without_list} = Compiler.compile(undeclared, Palette.core())

      assert with_list.scxml == without_list.scxml
      assert with_list.record.chart_identity == without_list.record.chart_identity
      refute with_list.record.document_hash == without_list.record.document_hash
      assert without_list.accepts == []
      assert without_list.record.accepts == []
    end

    # The compile reads nothing from the list and judges nothing about it: a
    # name no transition in the chart can take compiles all the same, with no
    # finding (decision 4 leaves that to the host's publish check).
    #
    # Sabotage: `document_stage/1` refusing any document whose `accepts` is
    # not `[]` - this compile fails and the test goes red.
    test "judges nothing: an undeclarable name compiles with no finding" do
      document = %{DocumentFixtures.patron_registration() | accepts: ["patron.blocked"]}

      assert {:ok, compiled} = Compiler.compile(document, Palette.core())

      assert compiled.accepts == ["patron.blocked"]
      assert compiled.warnings == []
    end
  end
end
