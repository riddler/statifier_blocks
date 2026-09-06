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
    # `statifier_datamodel`'s own suite; what this one holds is that the
    # arm exists, that it reaches that package, and that an empty document
    # is a claim rather than an absence (ADR-0006 decision 6).
    test "reads an ADR-0006 document through StatifierDatamodel" do
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

    # Folded here when `StatifierBlocks.Predicates.Datamodel` moved to the
    # `statifier_datamodel` package: the arm that reads a document delegates
    # now, and these are the shapes that delegation has to leave alone.
    #
    # sabotage: had the document clause answer `MapSet.new()` for a map the
    # package's admission step declines - a malformed shape became an empty
    # claim, every annotated path would have been flagged, and the
    # `%{"scopes" => "global"}` assertion went red (verified).
    test "a map the admission step declines is unrecognized, not an empty claim" do
      assert Datamodel.declared_paths(%{"scopes" => "global"}) == nil
      assert Datamodel.declared_paths(%{}) == nil
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

  describe "a {:path, opts} field is annotated by construction" do
    defp subchart(id, assign_to) do
      Block.new("core.subchart",
        id: id,
        config: %{
          "chart" => "bdoc_eligibility",
          "outcomes" => "approved",
          "assign_to" => assign_to
        }
      )
    end

    # sabotage: dropped `datamodel_path?(%{type: {:path, _opts}})`'s clause
    # from `BlockType` - the filter in `block_findings/5` stops reaching a
    # field that carries no key and this goes red (verified).
    test "an undeclared value on a typed field gets 11e's advisory" do
      document = document([subchart("blk_eligibility", "eligibility")])

      assert [%Finding{} = finding] = Datamodel.findings(document, palette(), ["signup.step"])
      assert finding.anchor == {:config, "blk_eligibility", "assign_to"}
      assert finding.severity == :info
      assert finding.source == :lint
      assert finding.message =~ "eligibility"
    end

    # sabotage: the same dropped clause - this test stays green while the
    # one above goes red, which is the split that makes the pair worth
    # having: an advisory that never fires looks exactly like a value that
    # was declared (verified).
    test "a declared value on a typed field produces nothing" do
      document = document([subchart("blk_eligibility", "eligibility")])

      assert Datamodel.findings(document, palette(), ["eligibility"]) == []
    end

    # sabotage: dropped `block_findings/5`'s `Enum.filter` - the subchart's
    # `chart` and `outcomes` are plain `:string` fields with values, and
    # each gains an advisory, so the single-finding match goes red
    # (verified).
    test "the block's other string fields are not annotated by association" do
      document = document([subchart("blk_eligibility", "eligibility")])

      assert [%Finding{anchor: {:config, _id, "assign_to"}}] =
               Datamodel.findings(document, palette(), [])
    end
  end

  describe "a capture's targets reach the advisory (ADR-0011 decision 10)" do
    defp handler(id, capture) do
      Block.new("core.on_event",
        id: id,
        config: %{"event" => "order.cancelled", "outcome" => "abandon", "capture" => capture}
      )
    end

    # The third gap the capture Note named: a capture's keys are datamodel
    # paths that reach the advisory through no field declaration, so the one
    # pass that covers every other datamodel path could not see them.
    #
    # sabotage: dropped the `capture_findings/4` call from
    # `block_findings/5` -> no finding is produced and this goes red
    # (verified).
    test "an undeclared target is the same :info every other path gets" do
      document = document([handler("blk_cancel", %{"order.cancel_reason" => "reason"})])

      assert [%Finding{} = finding] =
               Datamodel.findings(document, palette(), ["order.state"])

      assert finding.anchor == {:config, "blk_cancel", "capture"}
      assert finding.severity == :info
      assert finding.source == :lint
      assert finding.message =~ "order.cancel_reason"
    end

    # sabotage: read the pairs the other way round (the value as the path)
    # -> the declared target is flagged and the source is not, so both
    # assertions invert (verified). The key is the destination.
    test "a declared target produces nothing, and the source side is not a path here" do
      document = document([handler("blk_cancel", %{"order.cancel_reason" => "reason"})])

      assert Datamodel.findings(document, palette(), ["order.cancel_reason"]) == []
    end

    # sabotage: dropped the `is_map(pairs)` guard -> a handler with no
    # capture raises rather than producing nothing (verified).
    test "no capture, or a malformed one, produces nothing" do
      assert Datamodel.findings(
               document([Block.new("core.on_event", id: "blk_bare", config: %{})]),
               palette(),
               []
             ) == []

      assert Datamodel.findings(document([handler("blk_odd", "not a map")]), palette(), []) == []
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

  describe "candidates/3 (sb-0vt)" do
    # sabotage: the `|| MapSet.new()` after `declared_paths/1` dropped, so a
    # `nil` datamodel reached `MapSet.union/2` and raised instead of
    # collapsing to `[]` - this goes red with a FunctionClauseError rather
    # than a diff (verified).
    test "no declaring surface offers nothing" do
      assert Datamodel.candidates(document([]), nil) == []
      assert Datamodel.candidates(document([]), nil, []) == []
    end

    # sabotage: `MapSet.union(declared_roots(declare))` dropped from
    # `candidates/3` - `ambient` leaves the list and this goes red (verified).
    # Deduplication is the other half: `card` is named by both the datamodel
    # and the declare roots and appears once.
    test "unions the three surfaces and deduplicates" do
      document = document([], [entry("signup")])

      assert Datamodel.candidates(document, ["card.brand", "card"], ["ambient", "card"]) ==
               ["ambient", "card", "card.brand", "signup"]
    end

    # sabotage: `Enum.sort/1` -> `Enum.to_list/1` in `candidates/3` - this
    # goes red while the 4-path assertion above stays GREEN (both verified).
    #
    # Sorted output is what keeps a rendered list stable across renders rather
    # than reshuffling under the author mid-read.
    #
    # This needs MORE THAN 32 paths to assert anything, which is why it is its
    # own test and carries this note. Erlang stores a small map with its keys
    # in term order, so for a handful of strings `Enum.to_list/1` on the
    # MapSet is already sorted and the mutation below survives; above 32 the
    # set becomes a hashmap and the order is the hash's. The sabotage was run
    # both ways: `Enum.sort/1` -> `Enum.to_list/1` leaves a 4-path assertion
    # GREEN and turns this one red (verified), which is the whole reason the
    # small case is not trusted to carry this property.
    test "sorts, on a set large enough for MapSet order to be hash order" do
      paths = for i <- 1..40, do: "scope.field_#{i}"

      assert Datamodel.candidates(document([]), Enum.shuffle(paths)) == Enum.sort(paths)
    end

    # sabotage: `document_roots/1` dropped from the union - the document is
    # the surface a caller cannot pass and cannot forget, and this goes red
    # while the other two tests stay green (verified).
    test "reads the document's own datamodel key with no argument" do
      assert Datamodel.candidates(document([], [entry("signup"), entry("ambient")]), nil) ==
               ["ambient", "signup"]
    end

    # A root is offered whole and contributes nothing beneath itself (11l):
    # a root says storage exists at a name, and the datamodel document is
    # what enumerates paths under it.
    #
    # sabotage: `declared_roots/1` swapped for `declared_paths/1` on the
    # `declare` argument - a plain list of roots normalizes identically, so
    # this stays green. Recorded so the next reader does not take this test
    # for a stronger one than it is; the union test above is the guard.
    test "a declared root is offered as itself, not expanded" do
      assert Datamodel.candidates(document([]), nil, ["signup"]) == ["signup"]
    end

    # sabotage: the ADR-0006 document arm removed from `declared_paths/1` -
    # the document normalizes to `nil` and this returns `[]` (verified).
    test "projects an ADR-0006 datamodel document to its declared paths" do
      datamodel = %{
        "version" => 1,
        "scopes" => [
          %{
            "scope" => "local",
            "entries" => [
              %{
                "path" => "card",
                "type" => "object",
                "fields" => [%{"path" => "card.brand"}, %{"path" => "card.last4"}]
              }
            ]
          }
        ]
      }

      assert Datamodel.candidates(document([]), datamodel) ==
               ["card", "card.brand", "card.last4"]
    end

    # The set an author is OFFERED and the set that decides whether they get
    # an advisory are one set. This is the property the module claims, and it
    # is why `candidates/3` lives beside `findings/4` rather than in a module
    # of its own: two readers of three surfaces would drift, and the editor
    # would offer a path it then flagged.
    #
    # sabotage: `candidates/3` reading only `declared_paths/1` and skipping
    # both root surfaces - `signup` is then offered by nothing while still
    # drawing no advisory, and the first assertion goes red (verified).
    test "every offered candidate is one findings/4 would not flag" do
      candidates =
        Datamodel.candidates(document([], [entry("signup")]), ["card.brand"], ["ambient"])

      assert candidates == ["ambient", "card.brand", "signup"]

      for candidate <- candidates do
        assert Datamodel.findings(
                 document([assign("blk_probe", candidate)], [entry("signup")]),
                 palette(),
                 ["card.brand"],
                 ["ambient"]
               ) == []
      end
    end
  end

  describe "candidates_under/2 (sb-0vt)" do
    @datamodel_document %{
      "version" => 1,
      "scopes" => [
        %{
          "scope" => "local",
          "entries" => [
            %{
              "path" => "card",
              "type" => "object",
              "fields" => [%{"path" => "card.brand"}, %{"path" => "card.last4"}]
            },
            %{"path" => "cardholder", "type" => "string"}
          ]
        }
      ]
    }

    # sabotage: `under/2` swapped for a `String.starts_with?(&1.path, prefix)`
    # filter without the dot - `cardholder` joins the result and this goes
    # red (verified). That dot is the whole difference between a path
    # segment and a string prefix.
    test "narrows to entries strictly under the prefix, in document order" do
      assert Datamodel.candidates_under(@datamodel_document, "card") ==
               ["card.brand", "card.last4"]
    end

    # sabotage: `candidates_under/2` rewritten to index the datamodel here and
    # call `StatifierDatamodel.Index.under/2` on the result, without the
    # package's own `nil` arm - a flat list has no order to query and this
    # raises rather than returning empty (verified).
    test "a datamodel that is not an ADR-0006 document has no order to query" do
      assert Datamodel.candidates_under(["card.brand"], "card") == []
      assert Datamodel.candidates_under(nil, "card") == []
      assert Datamodel.candidates_under(@datamodel_document, "") == []
    end
  end

  # The read-only declared-path view's rows. The arithmetic lives here, with
  # `phoenix_live_view` absent, for the reason the rest of this module does:
  # the projection is pure, and the drawer tab over it asserts only that the
  # rows reach the markup.
  describe "declared_view/3" do
    @view_document %{
      "version" => 1,
      "scopes" => [
        %{
          "scope" => "local",
          "entries" => [
            %{
              "path" => "card",
              "type" => "object",
              "label" => "Card",
              "fields" => [
                %{"path" => "card.brand", "type" => "string", "label" => "Brand"},
                %{"path" => "card.number", "type" => "string", "sensitive?" => true}
              ]
            },
            %{"path" => "risk_reasons", "type" => "list", "item_type" => "string"}
          ]
        }
      ]
    }

    # sabotage: dropped `document_roots(document)` from the union - the
    # `signup` row vanished and this went red. That surface is the one a
    # caller cannot pass, so nothing else would have caught it.
    test "carries every path all three surfaces declare, sorted" do
      rows = Datamodel.declared_view(document([], [entry("signup")]), @view_document, ["host"])

      assert Enum.map(rows, & &1.path) == [
               "card",
               "card.brand",
               "card.number",
               "host",
               "risk_reasons",
               "signup"
             ]
    end

    # sabotage: `sources` built as the FIRST matching surface rather than
    # every matching one - the row for a path both the document and the
    # compile call declare read `[:declare]` and this went red.
    test "names every surface that declared a path, not just the first" do
      rows = Datamodel.declared_view(document([], [entry("signup")]), ["signup"], ["signup"])

      assert [%{path: "signup", sources: [:datamodel, :declare, :document]}] = rows
    end

    # sabotage: `entry_at/2` reading the index by `Map.get(index.entries, path)`
    # with no `{:ok, entry}` unwrapping - every shape came back `nil` and this
    # went red on the first assertion.
    test "carries the shape the ADR-0006 projection holds, and nothing for a root" do
      rows = Datamodel.declared_view(document([]), @view_document, ["host"])
      by_path = Map.new(rows, &{&1.path, &1})

      assert %{type: :object, scope: :local, label: "Card", sensitive?: false} = by_path["card"]
      assert %{type: :string, label: "Brand"} = by_path["card.brand"]
      assert %{type: :string, sensitive?: true} = by_path["card.number"]
      assert %{type: :list, item_type: :string} = by_path["risk_reasons"]

      assert %{type: nil, item_type: nil, scope: nil, label: nil, sensitive?: false} =
               by_path["host"]
    end

    # 11m's precondition, read forwards: with nothing declared anywhere there
    # is no advisory, and the view says the same thing by being empty.
    # sabotage: `declared_paths(datamodel) || MapSet.new()` replaced by a
    # `MapSet.new([nil])` fallback - an empty document grew a phantom row.
    test "is empty when nothing declares anything" do
      assert Datamodel.declared_view(document([]), nil, []) == []
    end

    # sabotage: the union built from `candidates/3` (a plain list) rather than
    # from the three sets - `MapSet.member?/2` raised and this went red. The
    # two must agree, which is why the agreement is asserted rather than
    # assumed.
    test "is candidates/3's set, path for path" do
      document = document([], [entry("signup")])

      assert document
             |> Datamodel.declared_view(@view_document, ["host"])
             |> Enum.map(& &1.path) == Datamodel.candidates(document, @view_document, ["host"])
    end
  end

  describe "value_candidates/2" do
    defp value_datamodel(entries) do
      %{"version" => 1, "scopes" => [%{"scope" => "local", "entries" => entries}]}
    end

    defp step_and_brand do
      value_datamodel([
        %{
          "path" => "signup.step",
          "type" => "string",
          "one_of" => ["details", "payment", "review"]
        },
        %{"path" => "card.brand", "type" => "string", "one_of" => ["visa", "amex"]},
        %{"path" => "signup.email", "type" => "string"}
      ])
    end

    # Sabotage: `declared_values/1` answering `%{}` for an index it has ->
    # every assertion here goes red. The derivation is the whole of the
    # "with no host map supplied" criterion.
    test "a path with declared values offers them, in declaration order" do
      assert Datamodel.value_candidates(step_and_brand()) == %{
               "signup.step" => ["details", "payment", "review"],
               "card.brand" => ["visa", "amex"]
             }
    end

    # Sabotage: mapping an empty option list to `[]` instead of leaving the
    # entry out -> this goes red. An absent key is a free-text control and an
    # empty list is an empty picker, which is the difference the "behaves
    # exactly as it does today" criterion turns on.
    test "a path with no declared values is absent, not present and empty" do
      refute Map.has_key?(Datamodel.value_candidates(step_and_brand()), "signup.email")
    end

    # Sabotage: dropping the number and boolean clauses of `option/1` -> both
    # paths vanish from the map and this goes red.
    test "numbers and booleans are offered as their printed form" do
      candidates =
        Datamodel.value_candidates(
          value_datamodel([
            %{"path" => "signup.attempts", "type" => "integer", "one_of" => [1, 2, 3]},
            %{"path" => "signup.consented", "type" => "boolean", "one_of" => [true, false]}
          ])
        )

      assert candidates == %{
               "signup.attempts" => ["1", "2", "3"],
               "signup.consented" => ["true", "false"]
             }
    end

    # Sabotage: `option/1` falling through to `inspect/1` instead of dropping
    # -> `["a"]` and `%{"b" => 1}` reach the picker as their inspect forms and
    # this goes red. A value that cannot be drawn as an option is not one.
    test "values with no drawable form are dropped, and a path left with none is absent" do
      candidates =
        Datamodel.value_candidates(
          value_datamodel([
            %{"path" => "signup.mixed", "one_of" => ["ok", ["a"], %{"b" => 1}, nil]},
            %{"path" => "signup.undrawable", "one_of" => [%{"b" => 1}, nil]}
          ])
        )

      assert candidates == %{"signup.mixed" => ["ok"]}
    end

    # Sabotage: `declared_values/1` raising rather than answering `%{}` on a
    # shape `index/1` declines -> these go red. Same total-normalizer
    # discipline `declared_paths/1` is written under.
    test "a datamodel that is not an ADR-0006 document declares no enumerations" do
      assert Datamodel.value_candidates(nil) == %{}
      assert Datamodel.value_candidates(["signup.step", "card.brand"]) == %{}
      assert Datamodel.value_candidates(MapSet.new(["signup.step"])) == %{}
      assert Datamodel.value_candidates(%{"scopes" => "not a list"}) == %{}
    end
  end

  # The precedence the 2026-09-05 note rules on, pinned in both directions:
  # replacement at a path the host names, and the datamodel's own list
  # everywhere else. A union would show a set nobody declared.
  describe "value_candidates/2, where the host's map and the datamodel meet" do
    # Sabotage: `Map.merge(host, derived)` instead of
    # `Map.merge(derived, host)` -> the host's entry loses to the datamodel's
    # and this goes red.
    test "a host entry replaces the derived list for its path" do
      candidates = Datamodel.value_candidates(step_and_brand(), %{"signup.step" => ["payment"]})

      assert candidates["signup.step"] == ["payment"]
    end

    # Sabotage: deriving nothing when a host map is supplied at all - the
    # "host wins outright" reading of the merge -> this goes red while the
    # test above stays green, which is the direction that reading breaks.
    test "and leaves every other path's default intact" do
      candidates = Datamodel.value_candidates(step_and_brand(), %{"signup.step" => ["payment"]})

      assert candidates["card.brand"] == ["visa", "amex"]
    end

    # Sabotage: unioning the two lists per path -> the values the host left
    # out come back and this goes red. This is the union the record refuses.
    test "the values the host left out are not offered" do
      candidates = Datamodel.value_candidates(step_and_brand(), %{"signup.step" => ["payment"]})

      refute "review" in candidates["signup.step"]
      refute "details" in candidates["signup.step"]
    end

    # Sabotage: treating an empty host list as "no entry" and falling back to
    # the derived list -> this goes red. Suppressing a path is something a
    # host can say, and replacement is what lets it say it.
    test "an empty host list is a suppression, and is carried through as one" do
      assert Datamodel.value_candidates(step_and_brand(), %{"signup.step" => []})["signup.step"] ==
               []
    end

    # Sabotage: intersecting the host's map with the declared paths -> the
    # undeclared path's entry disappears and this goes red. The host's map
    # was never bounded by the datamodel and still is not.
    test "a host entry for an undeclared path is offered as written" do
      candidates = Datamodel.value_candidates(step_and_brand(), %{"signup.variant" => ["a", "b"]})

      assert candidates["signup.variant"] == ["a", "b"]
      assert candidates["signup.step"] == ["details", "payment", "review"]
    end

    # Sabotage: normalizing the host's entries through `option/1` too -> the
    # `%{label:, value:}` candidates the seam documents are dropped and this
    # goes red. Nothing in this package interprets what a host wrote.
    test "the host's own candidate shapes pass through untouched" do
      host = %{"signup.step" => [%{label: "Pay now", value: "payment"}]}

      assert Datamodel.value_candidates(step_and_brand(), host)["signup.step"] ==
               [%{label: "Pay now", value: "payment"}]
    end

    # Sabotage: dropping the `datamodel` argument's `nil` arm -> this goes
    # red. It is the behaviour every host that supplies no datamodel had
    # before this function existed.
    test "with no datamodel the host's map is the whole answer, as it was before" do
      assert Datamodel.value_candidates(nil, %{"signup.step" => ["payment"]}) == %{
               "signup.step" => ["payment"]
             }
    end

    # Sabotage: `host_values/1` guarding on `is_map/1` alone -> a `MapSet`
    # merges its own internal shape over the derived map and this goes red.
    test "a host map that is not a plain map supplies no entries" do
      assert Datamodel.value_candidates(step_and_brand(), nil)["signup.step"] ==
               ["details", "payment", "review"]

      assert Datamodel.value_candidates(step_and_brand(), MapSet.new(["signup.step"]))[
               "signup.step"
             ] == ["details", "payment", "review"]
    end
  end

  describe "declared_types/1" do
    # ADR-0011 decision 9: a field whose type names another declaration reads
    # as that declaration's label, which is the same rendering a finding
    # applies to a type it names. One renderer, two surfaces.
    #
    # Sabotage: `field_type_text/2` answering `Types.to_string/1` directly -
    # the nested declaration reads as its nominal name and this goes red.
    test "renders a field whose type names a declaration as that declaration's label" do
      datamodel = %{
        "types" => [
          %{
            "name" => "cards.card",
            "kind" => "record",
            "label" => "Card",
            "fields" => [%{"name" => "last4", "type" => "string", "required?" => true}]
          },
          %{
            "name" => "cards.credit_txn",
            "kind" => "record",
            "label" => "Credit card transaction",
            "fields" => [
              %{"name" => "card", "type" => "cards.card", "required?" => true},
              %{"name" => "tags", "type" => "list", "item_type" => "string"},
              %{"name" => "provenance", "type" => "whatever the host means"}
            ]
          }
        ]
      }

      assert [card, txn] = Datamodel.declared_types(datamodel)
      assert card.name == "cards.card"

      assert txn.fields == [
               %{name: "card", type: "Card", required?: true, label: nil},
               %{name: "tags", type: "list of string", required?: false, label: nil},
               %{name: "provenance", type: "unspecified", required?: false, label: nil}
             ]
    end

    # Sabotage: sorting by `label` rather than by `name` - two declarations
    # whose labels order the other way round come back swapped.
    test "is by declared name, and a document with no types declares none" do
      datamodel = %{
        "types" => [
          %{"name" => "b.two", "kind" => "shape", "label" => "A label", "fields" => []},
          %{"name" => "a.one", "kind" => "record", "label" => "Z label", "fields" => []}
        ]
      }

      assert Enum.map(Datamodel.declared_types(datamodel), & &1.name) == ["a.one", "b.two"]
      assert Datamodel.declared_types(%{"scopes" => []}) == []
      assert Datamodel.declared_types(["a.one"]) == []
    end
  end
end
