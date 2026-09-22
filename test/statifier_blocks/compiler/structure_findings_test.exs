defmodule StatifierBlocks.Compiler.StructureFindingsTest do
  @moduledoc """
  `Compiler.structure_findings/3`: the compile's stages before Emit as one
  public function, and the compile's own prefix rather than a second copy
  of it (ADR-0004's Amendment of 2026-09-22, G1 to G3).

  G2's two halves are the assertions here. When `compile/3` refuses at
  stages 1 to 4, `structure_findings/3` returns exactly its findings, struct
  for struct and in order; otherwise it returns `[]`. Both are checked over
  the stored fixture documents, over those documents with one value blanked
  so a stage refuses, and over a document holding a composite, which is the
  case where a check over the stored document and the compile's own check
  disagree.

  The totality half is here too: a document whose `root` is not a block, or
  whose `slots` value is not a map of block lists, is refused by both
  functions rather than raising.

  A pure test. Nothing here names LiveView.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{
    Assignability,
    Block,
    Compiler,
    CoreFixtures,
    Document,
    DocumentFixtures,
    Palette,
    SlotValidation
  }

  alias StatifierBlocks.Compiler.Finding

  # -- a library composite whose expansion breaks a slot's arity ----------

  defmodule CrowdedHold do
    @moduledoc """
    Place a hold on a copy, and record two notes on the error path, which
    admits at most one. The refusal is against a member no param filled, so
    the compile reports it against the composite with no key to blame.
    """

    use StatifierBlocks.Composite,
      name: "library.crowded_hold",
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
          id: "place",
          config: %{"invoke_type" => "library:place_hold", "assign_to" => "", "params" => ""},
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

  # -- the same call with one note, which compiles -------------------------

  defmodule PlaceHold do
    @moduledoc "Place a hold on a copy, recording the failure if the call errors."

    use StatifierBlocks.Composite,
      name: "library.place_hold",
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
          id: "place",
          config: %{"invoke_type" => "library:place_hold", "assign_to" => "", "params" => ""},
          slots: %{
            "on_error" => [
              Block.new("core.assign",
                id: "note",
                config: %{"path" => params["failure_path"], "value" => "failed"}
              )
            ]
          }
        )
      ]
    end
  end

  describe "G2: the stored fixtures" do
    # Sabotage: made `document_stage/1` refuse every document - the shared
    # prefix refuses the first fixture and both assertions go red (verified).
    test "a document every stage accepts has no structure findings" do
      for document <- stored_fixtures() do
        assert {:ok, _compiled} = Compiler.compile(document, CoreFixtures.palette())
        assert Compiler.structure_findings(document, CoreFixtures.palette()) == []
      end
    end

    # A value blanked, so the Config stage refuses: the compile's refusal and
    # this function's answer are one list. No new value is written into the
    # fixtures; one they already hold is emptied.
    #
    # Sabotage: made `structure_findings/3` return the prefix's findings
    # without `in_document_order/2` - the `path` each finding carries is then
    # `nil` where the compile's names the block, and the equality goes red
    # (verified).
    test "a Config refusal is the compile's refusal, struct for struct" do
      for {document, block_id, key} <- blanked_fixtures() do
        broken = blank(document, block_id, key)

        assert {:error, refusal} = Compiler.compile(broken, CoreFixtures.palette())
        assert Enum.any?(refusal, &(&1.stage == :config and &1.block_id == block_id))
        assert Compiler.structure_findings(broken, CoreFixtures.palette()) == refusal
      end
    end

    # Sabotage: made `structure_findings/3` drop the Resolve stage's findings
    # from what it returns - the list comes back empty and the equality goes
    # red (verified).
    test "a Resolve refusal stops there, as the compile's does" do
      document = retype(signup_wizard(), "blk_VAR", "library.unknown")

      assert {:error, [%Finding{stage: :resolve}] = refusal} =
               Compiler.compile(document, CoreFixtures.palette())

      assert Compiler.structure_findings(document, CoreFixtures.palette()) == refusal
    end
  end

  describe "G3: a composite, over the spliced document" do
    # The composite's member breaks a slot's arity. The compile reports it
    # against the composite the author placed, and so does this function;
    # the public validators over the stored document see the composite alone
    # and pass it.
    #
    # Sabotage: handed `structure_stage/6` the stored document rather than
    # `structure_document/3`'s spliced one - the arity refusal disappears and
    # the first assertion goes red (verified).
    test "a finding inside an expansion names the composite, as the compile does" do
      document = library_document([crowded_hold("blk_HOLD")])

      assert {:error, refusal} = Compiler.compile(document, library_palette())
      assert [%Finding{} = arity] = Enum.filter(refusal, &(&1.code == :slot_arity_violated))
      assert arity.stage == :structure
      assert arity.block_id == "blk_HOLD"
      assert arity.config_key == nil

      assert Compiler.structure_findings(document, library_palette()) == refusal

      assert SlotValidation.validate(library_palette(), document) == :ok
      assert Assignability.validate(library_palette(), document, %{}) == :ok

      # The same call with one note on the error path expands cleanly, and
      # both functions agree there is nothing to say.
      clean = library_document([place_hold("blk_HOLD")])

      assert {:ok, _compiled} = Compiler.compile(clean, library_palette())
      assert Compiler.structure_findings(clean, library_palette()) == []
    end
  end

  describe "G1: stages 1 to 4 and nothing after them" do
    # `:terminate` and `:child_use` together are an Emit-stage refusal: the
    # compile refuses, and a function that stops before Emit has nothing to
    # say about it.
    #
    # Sabotage: made `structure_findings/3` call `stages/3` and unwrap the
    # error - the Emit finding comes back and this goes red (verified).
    test "a refusal after Structure is not one of its findings" do
      document = patron_registration()
      opts = [terminate: true, child_use: true]

      assert {:error, [%Finding{stage: :emit} | _rest]} =
               Compiler.compile(document, CoreFixtures.palette(), opts)

      assert Compiler.structure_findings(document, CoreFixtures.palette(), opts) == []
    end

    # Sabotage: made `structure_findings/3` validate its options against the
    # two it reads (`Keyword.validate!/2`) - the host's one keyword list then
    # raises here (verified).
    test "takes compile/3's own options and ignores the ones it does not read" do
      broken = blank(patron_registration(), "blk_PVER", "event")
      opts = [known_invoke_types: MapSet.new(), declare: [{"patron", nil}]]

      assert {:error, refusal} = Compiler.compile(broken, CoreFixtures.palette(), opts)
      assert Compiler.structure_findings(broken, CoreFixtures.palette(), opts) == refusal
    end
  end

  describe "totality: the Document stage's refusal is returned without walking the tree" do
    # Sabotage: removed `in_document_order/2`'s Document-stage clause - both
    # calls raise in `Document.blocks/1` and this goes red (verified).
    test "a root that is not a block is refused by both functions" do
      document = %{patron_registration() | root: "not a block"}

      assert {:error, [%Finding{stage: :document, block_id: nil}] = refusal} =
               Compiler.compile(document, CoreFixtures.palette())

      assert Compiler.structure_findings(document, CoreFixtures.palette()) == refusal
    end

    # Sabotage: the same removal - `Document.blocks/1` raises on the string
    # where a list of blocks belongs, and this goes red (verified).
    test "a slots value that is not a map of block lists is refused by both functions" do
      document = patron_registration()
      document = %{document | root: %{document.root | slots: %{"body" => "not a list"}}}

      assert {:error, [%Finding{stage: :document, block_id: nil}] = refusal} =
               Compiler.compile(document, CoreFixtures.palette())

      assert Compiler.structure_findings(document, CoreFixtures.palette()) == refusal
    end

    # The tree is intact and the envelope is not: the case that did not raise
    # before, and whose answer is unchanged.
    #
    # Sabotage: made `in_document_order/2`'s Document-stage clause answer
    # `{:error, []}` - the refusal loses its one finding and the match goes
    # red (verified).
    test "an envelope refusal over an intact tree is the one Document-stage finding" do
      document = %{patron_registration() | revision: -1}

      assert {:error, [%Finding{stage: :document, block_id: nil}] = refusal} =
               Compiler.compile(document, CoreFixtures.palette())

      assert Compiler.structure_findings(document, CoreFixtures.palette()) == refusal
    end
  end

  # -- helpers -------------------------------------------------------------

  defp stored_fixtures do
    [worked_example(), signup_wizard(), patron_registration()]
  end

  # One value per fixture that the block's own `validate_config/1` requires.
  defp blanked_fixtures do
    [
      {worked_example(), "blk_WAI", "duration"},
      {signup_wizard(), "blk_WINT", "event"},
      {patron_registration(), "blk_PVER", "event"}
    ]
  end

  defp worked_example, do: decode(DocumentFixtures.worked_example_json())
  defp signup_wizard, do: decode(DocumentFixtures.signup_wizard_json())
  defp patron_registration, do: decode(DocumentFixtures.patron_registration_json())

  defp decode(json) do
    {:ok, document} = Document.from_json(json)
    document
  end

  defp blank(%Document{root: root} = document, block_id, key) do
    %{document | root: update_block(root, block_id, &%{&1 | config: Map.put(&1.config, key, "")})}
  end

  defp retype(%Document{root: root} = document, block_id, type) do
    %{document | root: update_block(root, block_id, &%{&1 | type: type})}
  end

  defp update_block(%Block{id: id} = block, id, fun), do: fun.(block)

  defp update_block(%Block{slots: slots} = block, id, fun) do
    %{
      block
      | slots:
          Map.new(slots, fn {name, children} ->
            {name, Enum.map(children, &update_block(&1, id, fun))}
          end)
    }
  end

  defp library_palette do
    Palette.new(
      Map.merge(Palette.core_types(), %{
        "library.crowded_hold" => CrowdedHold,
        "library.place_hold" => PlaceHold
      })
    )
  end

  defp library_document(children) do
    Document.new(
      Block.new("core.sequence", id: "blk_LROOT", slots: %{"body" => children}),
      id: "bdoc_LIBRARY_HOLD"
    )
  end

  defp crowded_hold(id) do
    Block.new("library.crowded_hold", id: id, config: %{"failure_path" => "loan.hold_failure"})
  end

  defp place_hold(id) do
    Block.new("library.place_hold", id: id, config: %{"failure_path" => "loan.hold_failure"})
  end
end
