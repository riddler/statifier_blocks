if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule StatifierBlocks.Editor.CompositeExpandTest do
    @moduledoc """
    The editor's half of composites (ADR-0005's 2026-09-07 amendment, parts
    (i) and (ii)): the gesture that replaces a composite with the blocks it
    stands for, and the card it sits on.

    The obligations under test are the record's own clauses. Expand commits
    ONE `{:compound, ...}` whose first member removes the composite (1E), the
    inserts land where the composite stood in the order the expansion gives
    them (1E, 2E), the whole thing is one undo entry so one undo puts the
    composite back byte for byte (3E), a slot that will not admit the
    expansion refuses the gesture and writes nothing (5E), and the composite
    draws as an ordinary leaf card with chips, a sentence and no interior
    (7E, 8E).

    The obligation the campaign's consent states as prose is stated here as
    an assertion, from the editor's side rather than the compiler's: the SCXML
    the document compiles to before Expand is byte-identical to the SCXML the
    document compiles to after it. `StatifierBlocks.Compiler.CompositeExpansionTest`
    proves the same equality against a hand-built expanded document; what can
    only be proved here is that the document the EDITOR writes is that
    document.
    """

    use StatifierBlocks.EditorLiveCase

    alias StatifierBlocks.{Compiler, Composite}

    # -- the record's own worked example, in the card-processing domain -----

    defmodule GuardedStep do
      @moduledoc """
      Call out, and record the failure if the call comes back on the error
      path. One top-level member carrying a nested one.
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

      # A composite declares its chips the way every other block type does:
      # `summary/1` over the config, which for a composite IS its params
      # (clause 7E). Nothing generates it - a type that wants no chips
      # declares none, and the card never learns which kind of type it drew.
      @impl StatifierBlocks.BlockType
      def summary(config) do
        [config["invoke_type"], config["failure_path"] |> String.split(".") |> List.last()]
      end

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

    # -- two top-level members, which is the case that fixes the ORDER -----

    defmodule ConfirmContact do
      @moduledoc """
      A signup composite standing for two blocks rather than one: the case in
      which "at the composite's own target" and "in the order the expansion
      gives them" are two different commands.
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
        sentence: "Send {invoke_type}, recording at {confirmed_path}",
        palette_entry: %{label: "Confirm contact", group: "Structure"},
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

    describe "1E-3E: one compound, one undo entry" do
      # Sabotage: dropped the `{:remove, id}` from the head of the compound -
      # red at the first assertion, because the composite is then still in the
      # document beside its own expansion.
      test "Expand replaces the composite with the blocks it stands for", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: document(), palette: palette())

        expand(view, "blk_GS")

        assert_receive {:document, document}
        assert ids(document) == ["blk_ROOT", "blk_GS_call", "blk_GS_guard", "blk_TAIL"]
      end

      # Sabotage: committed the members as separate `commit/2` calls rather
      # than one compound - red here, because the first undo then puts back
      # only the last member and the composite stays gone.
      test "one undo puts the composite back, byte for byte", %{conn: conn} do
        before = document()
        {:ok, view, _html} = mount_editor(conn, document: before, palette: palette())

        expand(view, "blk_GS")
        assert_receive {:document, _expanded}

        view |> element(~s(button[phx-click="undo"])) |> render_click()

        assert_receive {:document, restored}
        assert restored == before
      end

      # Sabotage: left `selected_id` on the composite's own id - red, because
      # the card that class names is then gone from the document and no card
      # carries it.
      test "the selection lands on the first expanded block", %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: document(), palette: palette())

        html = expand(view, "blk_GS")

        assert html =~ ~r/class="[^"]*sb-node--selected[^"]*"[^>]*id="sb-block-blk_GS_call"/
        refute html =~ ~s(id="sb-block-blk_GS")
      end

      # Sabotage: inserted every member at the composite's own index rather
      # than at index + n - red, because the two members then arrive reversed
      # and the wizard records the confirmation before it sends anything.
      test "a two-member expansion lands in the order the expansion gives",
           %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn, document: confirm_document(), palette: palette())

        expand(view, "blk_CC")

        assert_receive {:document, document}
        assert ids(document) == ["blk_ROOT", "blk_CC_send", "blk_CC_record", "blk_TAIL"]
      end
    end

    describe "consent clause 6: the document Expand writes compiles to the same bytes" do
      # Sabotage: built the inserts from a fresh `Block.new/2` per member
      # rather than from `Composite.expand/2` - red, because the minted ids
      # then differ from the ones the compiler's own splice produces and every
      # state id in the two charts disagrees.
      test "the chart before Expand is byte-identical to the chart after it",
           %{conn: conn} do
        before = document()
        {:ok, view, _html} = mount_editor(conn, document: before, palette: palette())

        expand(view, "blk_GS")
        assert_receive {:document, expanded}

        assert {:ok, composed} = Compiler.compile(before, palette())
        assert {:ok, after_expand} = Compiler.compile(expanded, palette())

        assert composed.scxml == after_expand.scxml
        assert composed.provenance == after_expand.provenance
        assert composed.invoke_types == after_expand.invoke_types
      end

      # Sabotage: minted the editor's ids from the composite's TYPE rather
      # than its id - red, because the document then holds blocks whose ids
      # `Composite.expand/2` never produced.
      test "the blocks in the document are the ones `Composite.expand/2` answers",
           %{conn: conn} do
        {:ok, view, _html} = mount_editor(conn, document: document(), palette: palette())

        expand(view, "blk_GS")
        assert_receive {:document, expanded}

        {members, _param_map} = Composite.expand(guarded_step("blk_GS"), GuardedStep)

        assert body(expanded) == members ++ [tail()]
      end
    end

    describe "5E: a slot that will not admit the expansion refuses the gesture" do
      # Sabotage: dropped the admission check and let `Edit.apply/2` decide -
      # red, because that function is purely structural and writes the
      # expansion into a rail that declares it will not hold one.
      test "nothing is written and the composite stays", %{conn: conn} do
        before = interrupts_document()
        {:ok, view, _html} = mount_editor(conn, document: before, palette: palette())

        expand(view, "blk_GS")

        refute_receive {:document, _document}
        assert render(view) =~ ~s(id="sb-block-blk_GS")
      end

      # Sabotage: made the refusal commit an empty compound - red, because
      # undo then becomes available over a gesture that wrote nothing.
      test "the refused gesture is not on the undo stack", %{conn: conn} do
        {:ok, view, _html} =
          mount_editor(conn, document: interrupts_document(), palette: palette())

        expand(view, "blk_GS")

        assert has_element?(view, ~s(button[phx-click="undo"][disabled]))
      end
    end

    describe "7E-8E: the card draws as an ordinary leaf" do
      # Sabotage: gave the composite a slot in the generated `slots/1` - red,
      # because the card then reports itself as a container and draws an
      # interior an author could drop a block into.
      test "chips, a sentence and no interior", %{conn: conn} do
        {:ok, _view, html} = mount_editor(conn, document: document(), palette: palette())

        card = card(html, "blk_GS")

        assert card =~ ~s(data-container="false")
        assert card =~ "Guarded step"
        assert card =~ ~s(class="sb-node__chip")
        assert chips(card) == ["myapp:authorize", "failure"]
        refute card =~ "sb-slot"
      end

      # The sentence is the composite's own, resolved through the same
      # three-step `Node.sentence` every other type's resolves through
      # (clause 7E). It is asserted on the node rather than on the markup
      # because no card in this package draws a sentence - ADR-0005's
      # sentence amendment says so in as many words ("a card draws what it
      # drew yesterday"), and 7E's claim is that a composite draws like the
      # types beside it, not that it draws more.
      #
      # Sabotage: dropped the `sentence/1` the composite macro generates -
      # red, because the node then falls back to the palette label and the
      # params the author filled in say nothing.
      test "the composite's sentence resolves the ordinary way", %{conn: _conn} do
        view_model = StatifierBlocks.ViewModel.build(document(), palette(), [])

        [%{name: "body", children: [composite | _rest]} | _slots] = view_model.root.slots

        assert composite.block_id == "blk_GS"

        assert composite.sentence ==
                 "Call myapp:authorize, recording failure at cards.authorization.failure"
      end

      # Sabotage: drew the Expand control on every card rather than on the
      # composites - red, because a `core.assign` then offers a gesture that
      # refuses itself the moment it is clicked.
      test "the Expand control is on the composite and nowhere else", %{conn: conn} do
        {:ok, _view, html} = mount_editor(conn, document: document(), palette: palette())

        assert card(html, "blk_GS") =~ ~s(phx-click="expand")
        refute card(html, "blk_TAIL") =~ ~s(phx-click="expand")
      end

      # Sabotage: labelled the control "Expand" - red, because clause 6E
      # forbids exactly the word the fold toggle already answers with.
      test "6E: the control's label is not the fold toggle's word", %{conn: conn} do
        {:ok, _view, html} = mount_editor(conn, document: document(), palette: palette())

        card = card(html, "blk_GS")

        assert card =~ ~s(title="Replace with its steps")
        refute card =~ ~s(title="Expand")
      end
    end

    # -- fixtures ----------------------------------------------------------

    defp expand(view, id) do
      view
      |> element(~s([phx-click="expand"][phx-value-block-id="#{id}"]))
      |> render_click()
    end

    defp palette do
      Palette.new(
        Map.merge(Palette.core_types(), %{
          "myapp.guarded_step" => GuardedStep,
          "signup.confirm_contact" => ConfirmContact
        })
      )
    end

    defp document do
      Document.new(
        Block.new("core.sequence",
          id: "blk_ROOT",
          slots: %{"body" => [guarded_step("blk_GS"), tail()]}
        ),
        id: "bdoc_EXPAND"
      )
    end

    defp confirm_document do
      Document.new(
        Block.new("core.sequence",
          id: "blk_ROOT",
          slots: %{"body" => [confirm_contact("blk_CC"), tail()]}
        ),
        id: "bdoc_EXPAND"
      )
    end

    # The composite parked on a rail that declares `[:interrupt_handler]`.
    # Its expansion's root is a `core.invoke`, which is a `:step`, so the two
    # kind sets do not intersect and 5E refuses.
    defp interrupts_document do
      Document.new(
        Block.new("core.group",
          id: "blk_ROOT",
          slots: %{"body" => [tail()], "interrupts" => [guarded_step("blk_GS")]}
        ),
        id: "bdoc_REFUSED"
      )
    end

    defp guarded_step(id) do
      Block.new("myapp.guarded_step",
        id: id,
        config: %{
          "invoke_type" => "myapp:authorize",
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

    defp tail do
      Block.new("core.assign", id: "blk_TAIL", config: %{"path" => "done", "value" => "true"})
    end

    defp chips(card) do
      ~r/<span class="sb-node__chip"[^>]*>\s*([^<]*?)\s*<\/span>/
      |> Regex.scan(card)
      |> Enum.map(fn [_all, chip] -> chip end)
    end

    defp ids(%Document{} = document) do
      document |> Document.blocks() |> Enum.map(& &1.id)
    end

    defp body(%Document{root: %Block{slots: slots}}), do: Map.fetch!(slots, "body")

    # One card's markup: from its own `id` attribute to the next card's, so a
    # leaf card's slice holds its chrome and nothing below it.
    defp card(html, id) do
      [_before, rest] = String.split(html, ~s(id="sb-block-#{id}"), parts: 2)

      case String.split(rest, ~s(id="sb-block-), parts: 2) do
        [only] -> only
        [slice, _next] -> slice
      end
    end
  end
end
