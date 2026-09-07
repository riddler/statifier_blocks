defmodule StatifierBlocks.Compiler.CompositeExpansionTest do
  @moduledoc """
  The compiler's half of composites: a composite is replaced by its expansion
  at Resolve, and a finding raised inside that expansion is reported one level
  up against the composite and the param that produced it (ADR-0004's
  amendment of 2026-09-07, E1-E4).

  The obligation E4 states as prose is stated here as an assertion: the SCXML
  a document holding a composite compiles to is **byte-identical** to the
  SCXML the same document compiles to after that composite has been expanded
  in place. The expanded document is built from `Composite.expand/2` itself,
  which is what the editor's Expand operation will put in the document.

  A pure test. Nothing here names LiveView, so it compiles and runs headless.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, Composite, Document, Palette, Provenance}
  alias StatifierBlocks.Compiler.Finding

  # -- the card-processing composite, the amendment's own worked example ---

  defmodule GuardedStep do
    @moduledoc """
    Call out, and record the failure if the call comes back on the error
    path. Two params; the author fills both and reaches neither member.
    """

    use StatifierBlocks.Composite,
      name: "myapp.guarded_step",
      params: [
        %{key: "invoke_type", type: :string, label: "Call", required?: true, default: ""},
        %{
          key: "failure_path",
          type: :string,
          label: "Record the failure at",
          required?: true,
          default: "",
          datamodel_path?: true
        }
      ],
      sentence: "Call {invoke_type}, recording failure at {failure_path}",
      palette_entry: %{label: "Guarded step", group: "Structure"},
      version: 1

    alias StatifierBlocks.Block

    @impl StatifierBlocks.Composite
    def subtree(params) do
      [
        Block.new("core.invoke",
          id: "call",
          config: %{"invoke_type" => params["invoke_type"], "assign_to" => "", "params" => ""},
          slots: %{
            "on_error" => [
              Block.new("core.assign",
                id: "guard",
                config: %{"path" => params["failure_path"], "value" => "failed"}
              )
            ]
          }
        )
      ]
    end
  end

  # -- a composite whose declaration is wrong where no param can be blamed -

  defmodule Crowded do
    @moduledoc """
    The same shape with two blocks on a `zero_or_one` error path, which is a
    structural refusal against the call - a member whose config carries no
    param's value, so there is nothing on the author's form to point at.
    """

    use StatifierBlocks.Composite,
      name: "myapp.crowded",
      params: [
        %{
          key: "failure_path",
          type: :string,
          label: "Record the failure at",
          required?: true,
          default: "",
          datamodel_path?: true
        }
      ],
      version: 1

    alias StatifierBlocks.Block

    @impl StatifierBlocks.Composite
    def subtree(params) do
      [
        Block.new("core.invoke",
          id: "call",
          config: %{"invoke_type" => "myapp:authorize", "assign_to" => "", "params" => ""},
          slots: %{
            "on_error" => [
              Block.new("core.assign",
                id: "first",
                config: %{"path" => params["failure_path"], "value" => "failed"}
              ),
              Block.new("core.assign",
                id: "second",
                config: %{"path" => params["failure_path"], "value" => "again"}
              )
            ]
          }
        )
      ]
    end
  end

  # -- a signup composite whose expansion is more than one block ----------

  defmodule ConfirmContact do
    @moduledoc """
    Two top-level members rather than one, which is the case that exercises
    the splice: a composite in a slot is replaced by *all* of its members, in
    document order, head first.
    """

    use StatifierBlocks.Composite,
      name: "signup.confirm_contact",
      params: [
        %{key: "invoke_type", type: :string, label: "Send", required?: true, default: ""},
        %{
          key: "confirmed_path",
          type: :string,
          label: "Record confirmation at",
          required?: true,
          default: "",
          datamodel_path?: true
        }
      ],
      version: 1

    alias StatifierBlocks.Block

    @impl StatifierBlocks.Composite
    def subtree(params) do
      [
        Block.new("core.invoke",
          id: "send",
          config: %{"invoke_type" => params["invoke_type"], "assign_to" => "", "params" => ""}
        ),
        Block.new("core.assign",
          id: "record",
          config: %{"path" => params["confirmed_path"], "value" => "confirmed"}
        )
      ]
    end
  end

  describe "E1/E4: a composite compiles to the bytes its expansion compiles to" do
    # Sabotage: made `Compiler.resolve/2` fall through to `resolve_children/3`
    # for a composite - red at the first assertion, because the composite's
    # generated `emit/2` then raises rather than emitting the members.
    test "a document holding a composite compiles to the same bytes as the expanded one" do
      block = guarded_step("blk_GS")
      {members, _param_map} = Composite.expand(block, GuardedStep)

      assert {:ok, composed} = Compiler.compile(document([block]), palette())
      assert {:ok, expanded} = Compiler.compile(document(members), palette())

      assert composed.scxml == expanded.scxml
      assert composed.provenance == expanded.provenance
      assert composed.invoke_types == expanded.invoke_types
    end

    # Sabotage: minted the expanded ids from a counter rather than from the
    # composite block's id - red, because the state ids then name the counter
    # and the two compiles disagree on every one of them.
    test "E2: the state ids are the expanded blocks' ids, by decision 3" do
      assert {:ok, compiled} = Compiler.compile(document([guarded_step("blk_GS")]), palette())

      assert compiled.scxml =~ "s_blk_GS_call"
      assert compiled.scxml =~ "s_blk_GS_guard"
      refute compiled.scxml =~ "s_blk_GS\""
    end

    # Sabotage: kept only the expansion root at the splice - red, because a
    # composite standing for two blocks then compiles to one of them and the
    # signup wizard silently loses the step that records the confirmation.
    test "a composite standing for two blocks splices both, in document order" do
      block = confirm_contact("blk_CC")
      {members, _param_map} = Composite.expand(block, ConfirmContact)

      assert Enum.map(members, & &1.id) == ["blk_CC_send", "blk_CC_record"]

      assert {:ok, composed} = Compiler.compile(document([block]), palette())
      assert {:ok, expanded} = Compiler.compile(document(members), palette())

      assert composed.scxml == expanded.scxml
      assert composed.provenance == expanded.provenance
    end

    # Sabotage: made the expansion read the composite block's id from the
    # document root instead of the block - red, because the two composites
    # then mint the same member ids and the compile refuses on the duplicate.
    test "two composites in one document expand to distinct members" do
      document = document([guarded_step("blk_ONE"), guarded_step("blk_TWO")])

      assert {:ok, compiled} = Compiler.compile(document, palette())

      for id <- ~w(s_blk_ONE_call s_blk_ONE_guard s_blk_TWO_call s_blk_TWO_guard) do
        assert compiled.scxml =~ id
      end
    end
  end

  describe "E3: a finding inside an expansion is reported one level up" do
    # Sabotage: dropped the `config_key` from `reanchor_finding/2` and kept
    # only the block id - red on the key, which is the whole point: the
    # editor draws this beneath the one field the author typed into.
    test "a finding with a param to blame names the composite and the param's key" do
      document = document([guarded_step("blk_GS", "myapp:capture")])

      assert {:ok, compiled} =
               Compiler.compile(document, palette(),
                 known_invoke_types: MapSet.new(["myapp:authorize"])
               )

      assert [%Finding{} = warning] = compiled.warnings
      assert warning.code == :no_registered_invoke_handler
      assert warning.block_id == "blk_GS"
      assert warning.config_key == "invoke_type"
      assert warning.message == ~s(no handler registered for invoke type "myapp:capture")
    end

    # Sabotage: re-anchored to the composite but carried the param key of the
    # member's *sibling* - red, because a structural refusal then points at a
    # field the author can change and cannot fix it by changing.
    test "a structural finding no param produced names the composite with a nil key" do
      document = document([crowded("blk_CR")])

      assert {:error, findings} = Compiler.compile(document, palette())

      assert [%Finding{} = finding] =
               Enum.filter(findings, &(&1.code == :slot_arity_violated))

      assert finding.stage == :structure
      assert finding.block_id == "blk_CR"
      assert finding.config_key == nil
    end

    # Sabotage: ran the re-anchoring after `in_document_order/2` - red here,
    # because a finding anchored on a block the stored document does not hold
    # sorts to the front and carries no path.
    test "a re-anchored finding is placed in the stored document, not the expansion" do
      document = document([guarded_step("blk_GS", "myapp:capture")])

      assert {:ok, compiled} =
               Compiler.compile(document, palette(), known_invoke_types: MapSet.new([]))

      assert [%Finding{path: path}] = compiled.warnings
      assert {:ok, ^path} = Document.fetch_path(document, "blk_GS")
    end

    # Sabotage: reported the raise as a crash instead of a finding - red,
    # because decision 1 forbids `compile/3` to raise at all.
    test "a broken declaration is a resolve finding against the composite" do
      defmodule Empty do
        @moduledoc false
        use StatifierBlocks.Composite, name: "myapp.empty", params: [], version: 1

        @impl StatifierBlocks.Composite
        def subtree(_params), do: []
      end

      palette = Palette.new(Map.merge(Palette.core_types(), %{"myapp.empty" => Empty}))
      document = document([Block.new("myapp.empty", id: "blk_EM")])

      assert {:error, [%Finding{} = finding]} = Compiler.compile(document, palette)
      assert finding.stage == :resolve
      assert finding.code == :composite_expansion_failed
      assert finding.block_id == "blk_EM"
    end
  end

  describe "the expanded anchors survive, at the engineer's altitude" do
    # Sabotage: rewrote the provenance map's owners to the composite when the
    # findings were re-anchored - red, because the Source tab then has no
    # span to highlight inside the expansion and a fixture run names a block
    # that emitted nothing.
    test "every span inside the expansion is owned by the expanded block" do
      assert {:ok, compiled} = Compiler.compile(document([guarded_step("blk_GS")]), palette())

      owners = owning_ids(compiled)

      assert "blk_GS_call" in owners
      assert "blk_GS_guard" in owners
      refute "blk_GS" in owners
    end

    # Sabotage: keyed `by_state_id` off the composite - red, because runtime
    # highlighting then resolves an active state to a block the chart never
    # emitted.
    test "the state-id key names the expanded blocks too" do
      assert {:ok, compiled} = Compiler.compile(document([guarded_step("blk_GS")]), palette())

      assert %{block_id: "blk_GS_call"} = compiled.provenance.by_state_id["s_blk_GS_call"]
      assert %{block_id: "blk_GS_guard"} = compiled.provenance.by_state_id["s_blk_GS_guard"]
    end
  end

  # -- helpers -----------------------------------------------------------

  defp palette do
    Palette.new(
      Map.merge(Palette.core_types(), %{
        "myapp.guarded_step" => GuardedStep,
        "myapp.crowded" => Crowded,
        "signup.confirm_contact" => ConfirmContact
      })
    )
  end

  defp document(children) do
    Document.new(
      Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => children}),
      id: "bdoc_CANONICAL"
    )
  end

  defp guarded_step(id, invoke_type \\ "myapp:authorize") do
    Block.new("myapp.guarded_step",
      id: id,
      config: %{
        "invoke_type" => invoke_type,
        "failure_path" => "cards.authorization.failure"
      }
    )
  end

  defp confirm_contact(id) do
    Block.new("signup.confirm_contact",
      id: id,
      config: %{
        "invoke_type" => "myapp:signup",
        "confirmed_path" => "signup.contact.confirmed"
      }
    )
  end

  defp crowded(id) do
    Block.new("myapp.crowded",
      id: id,
      config: %{"failure_path" => "cards.authorization.failure"}
    )
  end

  defp owning_ids(%{provenance: %Provenance{spans: spans}}) do
    spans |> Enum.map(fn {_span, owner} -> owner.block_id end) |> Enum.uniq()
  end
end
