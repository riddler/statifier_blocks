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

  defp palette, do: Palette.core()

  defp assign(id, path, value \\ "false") do
    Block.new("core.assign", id: id, config: %{"path" => path, "value" => value})
  end

  defp document(children) do
    Document.new(
      Block.new("core.sequence", id: "blk_wizard", slots: %{"body" => children}),
      id: "doc_signup_wizard"
    )
  end

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
end
