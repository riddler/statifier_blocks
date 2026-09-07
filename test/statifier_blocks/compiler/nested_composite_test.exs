defmodule StatifierBlocks.Compiler.NestedCompositeTest do
  @moduledoc """
  The two arms of the Resolve stage's composite handling that the flat cases
  in `StatifierBlocks.Compiler.CompositeExpansionTest` leave unproven.

  The first is the recursion: `resolve/2` is re-entered for every member of an
  expansion, so a composite whose member is *itself* a composite expands twice
  in one pass. Two obligations follow from that, and both are asserted here.
  E4's byte-identity holds at every depth - the document holding the outer
  composite, the document after one Expand (which still holds the inner
  composite) and the document after two compile to the same bytes. And the
  climb in `anchor/2` does not stop at the inner composite: a finding raised
  inside the inner expansion is reported against the **outermost** composite
  and the param key on *its* form, because the inner composite is a block the
  author can neither see nor select.

  The second is the refusal: a composite standing at the document root whose
  subtree answers more than one top-level block has nowhere to splice the
  rest, and `root_expansion_finding/2` refuses it naming the count.

  A pure test. Nothing here names LiveView, so it compiles and runs headless.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, Composite, Document, Palette}
  alias StatifierBlocks.Compiler.Finding

  # -- the inner composite: the signup domain's confirmation step ---------

  defmodule ConfirmContact do
    @moduledoc """
    Send the confirmation and record that it went out. Two members, so the
    inner expansion is a splice as well as a recursion.
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
      sentence: "Send {invoke_type}, recording confirmation at {confirmed_path}",
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

  # -- the outer composite, whose one member is the inner composite -------

  defmodule ConfirmedSignup do
    @moduledoc """
    A composite whose member is itself a composite. One param, so the param
    map blames the member on it without ambiguity and the anchor the author
    is shown has a key to carry; the confirmation path is the outer
    declaration's own constant, which no field on the author's form can
    reach.
    """

    use StatifierBlocks.Composite,
      name: "signup.confirmed_signup",
      params: [
        %{key: "invoke_type", type: :string, label: "Send", required?: true, default: ""}
      ],
      sentence: "Confirm the contact by sending {invoke_type}",
      version: 1

    alias StatifierBlocks.Block

    @impl StatifierBlocks.Composite
    def subtree(params) do
      [
        Block.new("signup.confirm_contact",
          id: "confirm",
          config: %{
            "invoke_type" => params["invoke_type"],
            "confirmed_path" => "signup.contact.confirmed"
          }
        )
      ]
    end
  end

  # -- a composite standing for exactly one top-level block --------------

  defmodule RecordConsent do
    @moduledoc """
    One top-level member, so it has an expansion root to splice and the
    refusal below does not reach it. It is the arm's other side: the refusal
    is about the *count*, not about a composite standing at the root.
    """

    use StatifierBlocks.Composite,
      name: "signup.record_consent",
      params: [
        %{
          key: "consent_path",
          type: :string,
          label: "Record consent at",
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
        Block.new("core.sequence",
          id: "body",
          slots: %{
            "body" => [
              Block.new("core.assign",
                id: "consent",
                config: %{"path" => params["consent_path"], "value" => "granted"}
              )
            ]
          }
        )
      ]
    end
  end

  describe "the Resolve stage's recursion: a member that is itself a composite" do
    # Sabotage: kept only the head of `resolve_member/3`'s `member_nodes` -
    # red here alone, because the inner composite stands for two blocks and
    # the outer then compiles to one of them, silently dropping the step
    # that records the confirmation.
    test "the composite, its one Expand and its two compile to the same bytes" do
      block = confirmed_signup("blk_CS")

      {once, _param_map} = Composite.expand(block, ConfirmedSignup)
      assert [%Block{type: "signup.confirm_contact", id: "blk_CS_confirm"} = inner] = once

      {twice, _param_map} = Composite.expand(inner, ConfirmContact)
      assert Enum.map(twice, & &1.id) == ["blk_CS_confirm_send", "blk_CS_confirm_record"]

      assert {:ok, composed} = Compiler.compile(document([block]), palette())
      assert {:ok, expanded_once} = Compiler.compile(document(once), palette())
      assert {:ok, expanded_twice} = Compiler.compile(document(twice), palette())

      assert composed.scxml == expanded_once.scxml
      assert composed.scxml == expanded_twice.scxml
      assert composed.provenance == expanded_twice.provenance
      assert composed.invoke_types == expanded_twice.invoke_types
    end

    # Sabotage: stopped `anchor/2`'s climb at the first hop (dropped the
    # recursive `anchor(expansion, composite_id) ||`) - red here alone,
    # anchoring on `blk_CS_confirm`: a block that is not in the document the
    # author is editing, carrying a key that names no field on their form.
    test "a finding inside the inner expansion names the outermost composite and its key" do
      document = document([confirmed_signup("blk_CS", "myapp:signup")])

      assert {:ok, compiled} =
               Compiler.compile(document, palette(),
                 known_invoke_types: MapSet.new(["myapp:authorize"])
               )

      assert [%Finding{} = warning] = compiled.warnings
      assert warning.code == :no_registered_invoke_handler
      assert warning.block_id == "blk_CS"
      assert warning.config_key == "invoke_type"
      assert {:ok, path} = Document.fetch_path(document, "blk_CS")
      assert warning.path == path
    end
  end

  describe "the refusal: a composite at the document root standing for two blocks" do
    # Sabotage: made `resolve_stage/2`'s multi-node clause answer the head
    # node instead of refusing - red here alone, because the document then
    # compiles and silently drops every top-level block after the first,
    # which is the one outcome decision 1 forbids.
    test "is refused with the count of top-level blocks it answers" do
      root =
        Block.new("signup.confirm_contact",
          id: "blk_ROOT_CC",
          config: %{
            "invoke_type" => "myapp:signup",
            "confirmed_path" => "signup.contact.confirmed"
          }
        )

      document = Document.new(root, id: "bdoc_CANONICAL")

      assert {:error, findings} = Compiler.compile(document, palette())

      assert [%Finding{} = finding] =
               Enum.filter(findings, &(&1.code == :composite_expansion_failed))

      assert finding.stage == :resolve
      assert finding.block_id == "blk_ROOT_CC"

      assert finding.reason ==
               {:composite_expansion_failed, "blk_ROOT_CC", {:root_expansion_not_single, 2}}

      assert finding.message =~ "answers 2 top-level blocks"
    end

    # Sabotage: made `resolve_stage/2`'s single-node clause refuse whenever
    # the root resolves to a composite - red here alone (with a count of 1),
    # because a composite standing for a single block has a root to splice
    # and is the ordinary case the editor's Expand produces.
    test "but a composite root standing for one block compiles" do
      root =
        Block.new("signup.record_consent",
          id: "blk_ROOT_RC",
          config: %{"consent_path" => "signup.consent.granted"}
        )

      assert {:ok, compiled} =
               Compiler.compile(Document.new(root, id: "bdoc_CANONICAL"), palette())

      assert compiled.scxml =~ "s_blk_ROOT_RC_body"
    end
  end

  # -- helpers -----------------------------------------------------------

  defp palette do
    Palette.new(
      Map.merge(Palette.core_types(), %{
        "signup.confirm_contact" => ConfirmContact,
        "signup.confirmed_signup" => ConfirmedSignup,
        "signup.record_consent" => RecordConsent
      })
    )
  end

  defp document(children) do
    Document.new(
      Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => children}),
      id: "bdoc_CANONICAL"
    )
  end

  defp confirmed_signup(id, invoke_type \\ "myapp:signup") do
    Block.new("signup.confirmed_signup", id: id, config: %{"invoke_type" => invoke_type})
  end
end
