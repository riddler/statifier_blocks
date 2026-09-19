defmodule StatifierBlocks.Compiler.MintedIdCollisionTest do
  @moduledoc """
  A block an author placed in a composite's pass-through slot, carrying the
  id that composite's expansion mints for one of its own members
  (`ADR-0002`'s Amendment of 2026-09-18, `C10`).

  Author ids are checked for uniqueness in the Document stage, over the
  authored document; members are minted later, at Resolve, so nothing
  compared the two. The author's block then passed the minted-member filter
  `C2` item 2's raisable set is taken through, and the document was refused
  only at the Chart stage, as a duplicate state id - a finding that names the
  symptom. Resolve now reports the cause, against the composite block, and
  the Chart stage's duplicate id stays the backstop for every collision this
  does not reach.

  The fixtures are the signup wizard's confirmation step with a pass-through
  slot, the shape `StatifierBlocks.Composite.DeclaredOutcomesTest` uses. Its
  subtree mints one member, `<composite id>_body`.

  A pure test. Nothing here names LiveView, so it compiles and runs headless.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.Compiler.Finding

  alias StatifierBlocks.{
    Block,
    Compiler,
    Document,
    Palette
  }

  defmodule OpenStep do
    @moduledoc """
    Exposes a pass-through slot spliced into its one minted member, and
    declares a name only the author's filling could raise - so the colliding
    child below is exactly the one that used to hide `C2` item 3's finding.
    """

    use StatifierBlocks.Composite,
      name: "signup.open_step",
      params: [
        %{key: "event", type: :string, label: "Confirmed by", required?: true, default: ""}
      ],
      slots: [%{name: "body", to: {"body", "body"}, label: "Then"}],
      outcomes: ["received"],
      palette_entry: %{label: "Confirm the contact"},
      version: 1

    alias StatifierBlocks.Block

    @impl StatifierBlocks.Composite
    def subtree(_params), do: [Block.new("core.sequence", id: "body", slots: %{"body" => []})]
  end

  defmodule PlainOpenStep do
    @moduledoc "The same subtree and slot, declaring no outcomes: replaced by its expansion."

    use StatifierBlocks.Composite,
      name: "signup.plain_open_step",
      params: [
        %{key: "event", type: :string, label: "Confirmed by", required?: true, default: ""}
      ],
      slots: [%{name: "body", to: {"body", "body"}, label: "Then"}],
      palette_entry: %{label: "Confirm the contact"},
      version: 1

    alias StatifierBlocks.Block

    @impl StatifierBlocks.Composite
    def subtree(_params), do: [Block.new("core.sequence", id: "body", slots: %{"body" => []})]
  end

  describe "an author's block carrying an id the expansion mints" do
    # Sabotage: seeded the member reduction in `expand_node/3` with
    # `outcome_findings/5` alone, dropping the collision findings - red: the
    # compile gets past Resolve and the Chart stage answers `:duplicate_id`,
    # which is the behaviour this test replaces.
    test "is a Resolve finding against the composite block, naming the author's block" do
      assert {:error, findings} =
               Compiler.compile(
                 document(open("signup.open_step", [await("blk_OPEN_body")])),
                 palette()
               )

      assert Enum.all?(findings, &(&1.stage == :resolve))
      refute Enum.any?(findings, &(&1.code == :duplicate_id))

      assert [%Finding{} = finding] = Enum.filter(findings, &(&1.code == :minted_id_collision))

      assert finding.block_id == "blk_OPEN"
      assert finding.reason == {:minted_id_collision, "blk_OPEN", "blk_OPEN_body"}
      assert finding.message =~ ~s("blk_OPEN_body")
    end

    # Sabotage: passed no `:fault` to `Finding.new/4` - red, because the
    # Resolve stage's default is `:package`, and renaming the block is a
    # document edit that fixes it.
    test "is the author's fault" do
      assert {:error, findings} =
               Compiler.compile(
                 document(open("signup.open_step", [await("blk_OPEN_body")])),
                 palette()
               )

      assert [%Finding{fault: :author}] =
               Enum.filter(findings, &(&1.code == :minted_id_collision))
    end

    # Sabotage: walked the members and their direct slot children only, not
    # the whole spliced expansion - red: the colliding id below sits one
    # level further down, inside the author's group.
    test "is found at any depth below the composite block" do
      nested =
        Block.new("core.group",
          id: "blk_GROUP",
          slots: %{"body" => [await("blk_OPEN_body")]}
        )

      assert {:error, findings} =
               Compiler.compile(document(open("signup.open_step", [nested])), palette())

      assert [%Finding{reason: {:minted_id_collision, "blk_OPEN", "blk_OPEN_body"}}] =
               Enum.filter(findings, &(&1.code == :minted_id_collision))
    end

    # Sabotage: seeded the collision findings only for a composite whose
    # declared outcome names are non-empty - red: a composite replaced
    # outright by its expansion collides all the same.
    test "is reported on a composite that declares no outcomes" do
      assert {:error, findings} =
               Compiler.compile(
                 document(open("signup.plain_open_step", [await("blk_OPEN_body")])),
                 palette()
               )

      assert [%Finding{stage: :resolve, block_id: "blk_OPEN"}] =
               Enum.filter(findings, &(&1.code == :minted_id_collision))
    end
  end

  describe "a document without the collision is untouched" do
    # The negative half. Sabotage: reported a minted id occurring once as well
    # as one occurring twice - red, because this document compiles.
    test "an author's block of any other id compiles as it did" do
      assert {:ok, _compiled} =
               Compiler.compile(
                 document(open("signup.plain_open_step", [await("blk_FILL")])),
                 palette()
               )
    end

    # The finding `C2` item 3 draws is unchanged when nothing collides, and
    # the new one is absent. Sabotage: the same one as above - red on the
    # `refute`.
    test "C2 item 3's finding is still the one a non-colliding filling draws" do
      assert {:error, findings} =
               Compiler.compile(
                 document(open("signup.open_step", [await("blk_FILL")])),
                 palette()
               )

      assert [%Finding{reason: {:outcome_not_raisable, "blk_OPEN", "received"}}] =
               Enum.filter(findings, &(&1.code == :outcome_not_raisable))

      refute Enum.any?(findings, &(&1.code == :minted_id_collision))
    end
  end

  describe "the scope: blocks the expansion does not carry are not asked" do
    # A child the composite drops keeps the finding it drew before. Sabotage:
    # walked every slot of the composite block as the author wrote it rather
    # than the spliced expansion - red: the dropped child below was reported
    # as a collision, and its `:undeclared_slot` finding was lost with it.
    test "a colliding child in a slot the type does not declare keeps :undeclared_slot" do
      block = %{
        open("signup.plain_open_step", [await("blk_FILL")])
        | slots: %{"body" => [await("blk_FILL")], "later" => [await("blk_OPEN_body")]}
      }

      assert {:error, findings} = Compiler.compile(document(block), palette())

      assert [%Finding{stage: :resolve, reason: {:undeclared_slot, "blk_OPEN", "later", 1}}] =
               Enum.filter(findings, &(&1.code == :undeclared_slot))

      refute Enum.any?(findings, &(&1.code == :minted_id_collision))
    end

    # A block outside the composite carrying a minted id is not in that
    # composite's expansion, so Resolve does not report it and the emitted
    # chart's duplicate state id refuses the document, as before. Sabotage:
    # reported a minted id occurring once as well as one occurring twice -
    # red: the composite then drew the finding for its own member.
    test "a minted id written outside the composite is refused at the Chart stage" do
      root =
        Block.new("core.sequence",
          id: "blk_ROOT",
          slots: %{
            "body" => [
              open("signup.plain_open_step", [await("blk_FILL")]),
              await("blk_OPEN_body")
            ]
          }
        )

      assert {:error, findings} =
               Compiler.compile(Document.new(root, id: "bdoc_mintedidcollision"), palette())

      refute Enum.any?(findings, &(&1.code == :minted_id_collision))
      assert Enum.any?(findings, &(&1.stage == :chart and &1.code == :duplicate_id))
    end
  end

  # -- fixtures ------------------------------------------------------------

  defp palette do
    Palette.new(
      Map.merge(Palette.core_types(), %{
        "signup.open_step" => OpenStep,
        "signup.plain_open_step" => PlainOpenStep
      })
    )
  end

  defp open(type, children) do
    Block.new(type,
      id: "blk_OPEN",
      config: %{"event" => "signup.confirmed"},
      slots: %{"body" => children}
    )
  end

  defp await(id) do
    Block.new("core.await",
      id: id,
      config: %{"event" => "signup.confirmed", "timeout" => "10m"}
    )
  end

  defp document(block),
    do:
      Document.new(
        Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [block]}),
        id: "bdoc_mintedidcollision"
      )
end
