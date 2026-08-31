defmodule StatifierBlocks.DatamodelTest do
  @moduledoc """
  ADR-0005 amendment 11e-11g, asserted where the rule lives.

  Deliberately not a LiveView test and deliberately not tagged `:liveview`:
  the undeclared-path check is pure, so it is asserted with
  `phoenix_live_view` absent from the dependency tree, and the editor test
  beside it asserts only that the finding reaches the markup.

  The two properties that carry the record are the first two describes: a
  path the datamodel does not declare produces exactly one `:info` finding
  anchored on the field's `key`, and no datamodel at all produces nothing.
  """

  use ExUnit.Case, async: true

  doctest StatifierBlocks.Datamodel

  alias StatifierBlocks.{Block, Datamodel, Document, Finding, Palette}
  alias StatifierBlocks.Document.DatamodelEntry

  defp palette, do: Palette.core()

  defp assign(id, path, value \\ "false") do
    Block.new("core.assign", id: id, config: %{"path" => path, "value" => value})
  end

  defp document(children, datamodel \\ []) do
    Document.new(
      Block.new("core.sequence", id: "blk_wizard", slots: %{"body" => children}),
      id: "doc_signup_wizard",
      datamodel: datamodel
    )
  end

  defp entry(id), do: %DatamodelEntry{id: id}

  describe "declared_paths/1" do
    # sabotage: `declared_paths(_unrecognized)` returning `MapSet.new([])`
    # instead of `nil` - a host passing a shape this package does not know
    # would get every annotated path flagged, and the string and integer
    # assertions here go red (verified).
    test "normalizes the shapes the record names, and nothing else" do
      assert Datamodel.declared_paths(nil) == nil
      assert Datamodel.declared_paths(["a.b", "c.d"]) == MapSet.new(["a.b", "c.d"])
      assert Datamodel.declared_paths(MapSet.new(["a.b"])) == MapSet.new(["a.b"])
      assert Datamodel.declared_paths([]) == MapSet.new([])

      assert Datamodel.declared_paths("signup.step") == nil
      assert Datamodel.declared_paths(42) == nil
    end

    # sabotage: dropped the ADR-0006 document clause, so a typed document
    # fell through to `_unrecognized` and returned `nil` - both assertions
    # here go red (verified). The projection itself is asserted in
    # `StatifierBlocks.Predicates.DatamodelTest`; what this one holds is
    # that the arm exists and that an empty document is a claim rather
    # than an absence (ADR-0006 decision 6).
    test "reads an ADR-0006 document through Predicates.Datamodel" do
      assert Datamodel.declared_paths(%{"version" => 1, "scopes" => []}) == MapSet.new([])

      assert Datamodel.declared_paths(%{
               "version" => 1,
               "scopes" => [
                 %{"scope" => "local", "entries" => [%{"path" => "signup.step"}]}
               ]
             }) == MapSet.new(["signup.step"])
    end

    # sabotage: dropping the `Enum.filter(&declared_path?/1)` - `""` and the
    # integer land in the set, and the equality here goes red (verified).
    test "drops blanks and non-strings from a supplied list" do
      assert Datamodel.declared_paths(["signup.step", "", 42, nil]) ==
               MapSet.new(["signup.step"])
    end
  end

  describe "an undeclared path (11e)" do
    # sabotage: anchoring on `value_path` rather than on the field's `key` -
    # the anchor becomes `{:config, id, ["path"]}` and this goes red, which
    # is the distinction 11e states in so many words (verified).
    test "produces one :info finding anchored on the field's key, source :lint" do
      document = document([assign("blk_variant_write", "signup.variant")])
      declared = ["signup.variant_id", "signup.step"]

      assert [%Finding{} = finding] = Datamodel.findings(document, palette(), declared)
      assert finding.anchor == {:config, "blk_variant_write", "path"}
      assert finding.severity == :info
      assert finding.source == :lint
      assert finding.message =~ "signup.variant"
    end

    # sabotage: `not MapSet.member?/2` losing its `not` - the declared path
    # is flagged and the undeclared one is not, so both assertions invert
    # (verified).
    test "a declared path produces nothing" do
      document = document([assign("blk_step_write", "signup.step")])

      assert Datamodel.findings(document, palette(), ["signup.step"]) == []
    end

    # sabotage: `Enum.filter(&BlockType.datamodel_path?/1)` removed - the
    # `value` field is checked too and a second finding appears (verified).
    test "only the annotated field is checked, not every string field" do
      document = document([assign("blk_write", "signup.variant", "\"b\"")])

      assert [%Finding{anchor: {:config, "blk_write", "path"}}] =
               Datamodel.findings(document, palette(), [])
    end

    # sabotage: `advisory/4` dropping its `declared_path?(path)` guard - an
    # empty `path` produces an advisory beside the `:error` validate_config
    # already gives it, saying the same thing twice (verified).
    test "a missing or empty path produces nothing - that is validate_config's :error" do
      document =
        document([
          Block.new("core.assign", id: "blk_empty", config: %{"path" => "", "value" => "false"}),
          Block.new("core.assign", id: "blk_absent", config: %{"value" => "false"})
        ])

      assert Datamodel.findings(document, palette(), ["signup.step"]) == []
    end

    # sabotage: returning `[]` for the empty-set case as if it were `nil` -
    # a host that declares nothing stops being believed, and this goes red
    # (verified).
    test "an empty declared set is a claim, and every annotated path is undeclared" do
      document = document([assign("blk_write", "signup.variant")])

      assert [%Finding{severity: :info}] = Datamodel.findings(document, palette(), [])
    end

    # sabotage: `{:error, _reason}` in `undeclared_findings/3` calling
    # `block_findings/4` anyway - resolving no module, the call raises and
    # this goes red rather than returning the resolution finding's `[]`
    # (verified).
    test "an unresolvable block contributes nothing" do
      document =
        document([
          Block.new("host.tracking", id: "blk_tracking", config: %{"path" => "signup.variant"})
        ])

      assert Datamodel.findings(document, palette(), []) == []
    end
  end

  describe "no datamodel (11f): absence is not unknown-ness" do
    # sabotage: `findings/3`'s `nil` arm falling through to
    # `undeclared_findings/3` with an empty set - every annotated path in a
    # document the host said nothing about is flagged, which is exactly the
    # unfounded claim 11d objected to (verified).
    test "nil produces nothing at all, not a quieter severity" do
      document =
        document([
          assign("blk_a", "signup.variant"),
          assign("blk_b", "merchant.risk_tier")
        ])

      assert Datamodel.findings(document, palette(), nil) == []
    end
  end

  describe "declared_roots/1 (11k source 2)" do
    # sabotage: `declared_roots(_unrecognized)` returning `nil` instead of
    # the empty set - `MapSet.union/2` in `findings/4` raises on `nil` and
    # every assertion below goes red rather than one (verified).
    test "normalizes the compile call's shape, and is total" do
      assert Datamodel.declared_roots([{"signup", nil}, {"card", "0"}]) ==
               MapSet.new(["signup", "card"])

      assert Datamodel.declared_roots(["signup"]) == MapSet.new(["signup"])
      assert Datamodel.declared_roots(MapSet.new(["signup"])) == MapSet.new(["signup"])
      assert Datamodel.declared_roots([]) == MapSet.new([])
      assert Datamodel.declared_roots(nil) == MapSet.new([])
      assert Datamodel.declared_roots("signup") == MapSet.new([])
      assert Datamodel.declared_roots([{"", nil}, 42, nil]) == MapSet.new([])
    end
  end

  describe "a declared root (11k, 11l)" do
    # The empty datamodel is what makes this test bite rather than decoration:
    # it is a host claiming its documents address nothing (11f), so the check
    # runs whatever the root set holds, and only the root can be what silences
    # the advisory.
    #
    # sabotage: `document_roots/1` returning `MapSet.new()` unconditionally -
    # the document's own declaration stops counting and `signup.variant` is
    # flagged, so this goes red (verified). This is the ADR-0001 11g open
    # question, answered.
    test "a root the document declares covers every path beneath it" do
      document = document([assign("blk_write", "signup.variant")], [entry("signup")])

      assert Datamodel.findings(document, palette(), []) == []
    end

    # sabotage: `declared_roots/1` dropped from the union in `findings/4` -
    # the host's roots stop counting and the assign is flagged (verified).
    # The empty datamodel is here for the same reason as above.
    test "a root the compile call declares covers every path beneath it" do
      document = document([assign("blk_write", "signup.variant")])

      assert Datamodel.findings(document, palette(), [], [{"signup", nil}]) == []
    end

    # sabotage: `root_segment/1` returning the whole path instead of the
    # first segment - a declared root stops covering anything beneath it and
    # the deep path is flagged, which is exactly what 11l forbids (verified).
    test "matching is by root segment, however deep the path" do
      document =
        document(
          [assign("blk_deep", "signup.address.line_1"), assign("blk_bare", "signup")],
          [entry("signup")]
        )

      assert Datamodel.findings(document, palette(), []) == []
    end

    # sabotage: `declared?/3` matching the datamodel by root segment too -
    # `signup.variant` is covered by the declared `signup.step`'s root and
    # this goes red, which is 11l's "still matched whole" (verified).
    test "the datamodel's own paths are still matched whole, not by root" do
      document = document([assign("blk_write", "signup.variant")])

      assert [%Finding{severity: :info}] =
               Datamodel.findings(document, palette(), ["signup.step"])
    end

    # sabotage: the `MapSet.union/2` in `findings/4` replaced by the document
    # set alone - the host root stops covering `card.brand` and a second
    # finding appears (verified).
    test "the two surfaces are a union, and an undeclared root is still flagged" do
      document =
        document(
          [
            assign("blk_signup", "signup.variant"),
            assign("blk_card", "card.brand"),
            assign("blk_typo", "sigunp.variant")
          ],
          [entry("signup")]
        )

      assert [%Finding{anchor: {:config, "blk_typo", "path"}, severity: :info}] =
               Datamodel.findings(document, palette(), nil, [{"card", nil}])
    end

    # sabotage: `document_roots/1` losing its `declared_path?` filter - the
    # blank id lands in the root set, `root_segment/1` never produces `""`
    # for a real path so nothing is covered by it, but the set stops being
    # empty and 11m's precondition fires on a document that declared nothing
    # usable. Written against `""` rather than `nil` because that is the arm
    # that goes red (verified).
    test "a blank declared root declares nothing" do
      document = document([assign("blk_write", "signup.variant")], [entry("")])

      assert Datamodel.findings(document, palette(), nil) == []
      assert [%Finding{severity: :info}] = Datamodel.findings(document, palette(), [])
    end
  end

  describe "nothing declared anywhere (11m)" do
    # sabotage: the `is_nil(declared) and MapSet.size(roots) == 0` guard
    # reduced to `MapSet.size(roots) == 0` - a host supplying an empty
    # datamodel stops being believed and the last assertion goes red
    # (verified).
    test "no datamodel and no roots produces nothing (11f, unchanged)" do
      document = document([assign("blk_a", "signup.variant")])

      assert Datamodel.findings(document, palette(), nil) == []
      assert Datamodel.findings(document, palette(), nil, []) == []
      assert [%Finding{severity: :info}] = Datamodel.findings(document, palette(), [])
    end

    # sabotage: the same guard widened to `is_nil(declared)` alone - the
    # check never runs without a host datamodel and this goes red. This is
    # the case the amendment adds: a document that declares its own roots
    # lints its own paths with no host involved at all.
    test "a document that declares roots lints its own paths with no host" do
      document =
        document(
          [assign("blk_ok", "signup.step"), assign("blk_typo", "sigunp.step")],
          [entry("signup")]
        )

      assert [%Finding{anchor: {:config, "blk_typo", "path"}, severity: :info}] =
               Datamodel.findings(document, palette(), nil)
    end
  end
end
