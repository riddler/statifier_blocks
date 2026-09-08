defmodule StatifierBlocks.Assignability.PaletteKindsTest do
  @moduledoc """
  ADR-0002's Note of 2026-09-08, item 1: admission resolves a composite's
  member kinds through the palette.

  `kinds/3`, `slot_accepts/4` and `admits?/4` take the palette first and
  resolve a composite exactly as `produces/4` already does, so the editor
  refuses at drop what the compiler refuses at compile. The core-only
  spellings - `kinds/2`, `slot_accepts/3`, `admits?/3` - stay, and answer
  what the `io/1` callback answers.

  Every composite here is rooted at a **host** type, which is the whole of
  the difference the item names: a composite rooted at a core type resolves
  the same way through either palette, because the callback's fallback
  palette is `StatifierBlocks.Palette.core/0` and a core member is in it. A
  host-rooted composite is where the callback falls back to `[:step]` kinds
  and no `slot_accepts`, and a reader holding the palette does not.

  The card-processing domain, and `myapp.on_chargeback` -
  `StatifierBlocks.AssignabilityFixtures`'s host interrupt handler - is the
  handler the first composite's expansion is rooted at.

  A pure test. Nothing here names LiveView, so it compiles and runs headless.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Assignability, AssignabilityFixtures, Block, Compiler, Document, Palette}
  alias StatifierBlocks.Compiler.Finding

  # -- a composite whose expansion root is an interrupt handler -------------

  defmodule WatchForChargeback do
    @moduledoc """
    Watch for a chargeback on the transaction in flight. Its expansion is one
    `myapp.on_chargeback`, so the composite is an interrupt handler and not a
    step - which is exactly what the core-only derivation cannot see, because
    `myapp.on_chargeback` is not in `StatifierBlocks.Palette.core_types/0`.
    """

    use StatifierBlocks.Composite,
      name: "myapp.watch_for_chargeback",
      params: [
        %{key: "reason_code", type: :string, label: "Reason code", required?: false, default: ""}
      ],
      sentence: "Watch for a chargeback ({reason_code})",
      palette_entry: %{label: "Watch for a chargeback", group: "Structure"},
      version: 1

    alias StatifierBlocks.Block

    @impl StatifierBlocks.Composite
    def subtree(params) do
      [
        Block.new("myapp.on_chargeback",
          id: "watch",
          config: %{"reason" => params["reason_code"]}
        )
      ]
    end
  end

  # -- a composite whose expansion root is a step ---------------------------

  defmodule AuthorizeThenSettle do
    @moduledoc """
    Authorize the transaction and settle it. Its expansion is two host steps,
    so the composite is a step - the same verdict either palette reaches, and
    the control the handler-rooted case is read against.
    """

    use StatifierBlocks.Composite,
      name: "myapp.authorize_then_settle",
      params: [
        %{key: "note", type: :string, label: "Note", required?: false, default: ""}
      ],
      sentence: "Authorize and settle ({note})",
      palette_entry: %{label: "Authorize and settle", group: "Structure"},
      version: 1

    alias StatifierBlocks.Block

    @impl StatifierBlocks.Composite
    def subtree(_params) do
      [Block.new("myapp.authorize", id: "auth"), Block.new("myapp.settle", id: "settle")]
    end
  end

  # -- a host container, so a pass-through slot has a host slot to map to ---

  defmodule Escalation do
    @moduledoc """
    `myapp.escalation`: a host container whose `"handlers"` slot admits
    interrupt handlers and nothing else.
    """

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: [{"handlers", :any, "Handlers"}]
    @impl true
    def config_schema(_config), do: []
    @impl true
    def validate_config(_config), do: :ok
    @impl true
    def io(_config), do: %{kinds: [:step], slot_accepts: %{"handlers" => [:interrupt_handler]}}
    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule EscalationFrame do
    @moduledoc """
    A composite exposing the host container's `"handlers"` slot as its own
    `"watchers"`. The mapped inner slot is a host type's, so the core-only
    derivation answers `:any` for it and a reader holding the palette answers
    what the host declared.
    """

    use StatifierBlocks.Composite,
      name: "myapp.escalation_frame",
      params: [
        %{key: "note", type: :string, label: "Note", required?: false, default: ""}
      ],
      slots: [%{name: "watchers", to: {"frame", "handlers"}, label: "Watchers"}],
      sentence: "Escalation frame ({note})",
      palette_entry: %{label: "Escalation frame", group: "Structure"},
      version: 1

    alias StatifierBlocks.Block

    @impl StatifierBlocks.Composite
    def subtree(_params) do
      [Block.new("myapp.escalation", id: "frame", slots: %{"handlers" => []})]
    end
  end

  defp palette do
    Palette.new(
      Map.merge(Map.merge(Palette.core_types(), AssignabilityFixtures.host_types()), %{
        "myapp.watch_for_chargeback" => WatchForChargeback,
        "myapp.authorize_then_settle" => AuthorizeThenSettle,
        "myapp.escalation" => Escalation,
        "myapp.escalation_frame" => EscalationFrame
      }),
      assignability: AssignabilityFixtures.Widens
    )
  end

  defp ctx, do: %{entry_type: "myapp.transaction"}

  # A root sequence with an empty `body`, and a group beside nothing, so a
  # position can be named directly.
  defp sequence_document do
    root = Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => []})
    Document.new(root, id: "bdoc_pk_seq")
  end

  defp group_document do
    group =
      Block.new("core.group", id: "blk_GRP", slots: %{"body" => [], "interrupts" => []})

    root = Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [group]})
    Document.new(root, id: "bdoc_pk_grp")
  end

  describe "kinds/3 and slot_accepts/4 against their core-only spellings" do
    # sabotage: give `kinds/3` `io(ref, block.config)` in place of
    # `io_of(palette, ref, block)` -> the first assertion goes red
    test "a host-rooted handler composite is :step to the callback and :interrupt_handler to a palette" do
      block = Block.new("myapp.watch_for_chargeback", id: "blk_wc")

      assert Assignability.kinds(palette(), WatchForChargeback, block) == [:interrupt_handler]
      assert Assignability.kinds(WatchForChargeback, block.config) == [:step]
    end

    # sabotage: give `slot_accepts/4` `io(ref, block.config)` in place of
    # `io_of(palette, ref, block)` -> the first assertion goes red
    test "a pass-through slot mapped to a host slot is :any to the callback and the host's to a palette" do
      block = Block.new("myapp.escalation_frame", id: "blk_ef")

      assert Assignability.slot_accepts(palette(), EscalationFrame, block, "watchers") ==
               [:interrupt_handler]

      assert Assignability.slot_accepts(EscalationFrame, block.config, "watchers") == :any
    end
  end

  describe "admission refuses on the palette's kinds" do
    # sabotage: revert `kind_admission_finding/5` to `admits?/3` over the
    # core-only spellings -> this test goes red (the composite is admitted)
    test "a handler-rooted composite is refused at a sequence body" do
      candidate = Block.new("myapp.watch_for_chargeback", id: "blk_cand")

      assert {:error, findings} =
               Assignability.check(
                 palette(),
                 sequence_document(),
                 {"blk_ROOT", "body", 0},
                 candidate,
                 ctx()
               )

      assert {:kind_not_admitted, "blk_cand", "blk_ROOT", "body", [:interrupt_handler], [:step]} in findings
    end

    # sabotage: the same revert -> this test goes red (the composite is
    # refused, because the callback calls it a step)
    test "a handler-rooted composite is admitted on a group's interrupts slot" do
      candidate = Block.new("myapp.watch_for_chargeback", id: "blk_cand")

      assert :ok =
               Assignability.check(
                 palette(),
                 group_document(),
                 {"blk_GRP", "interrupts", 0},
                 candidate,
                 ctx()
               )
    end

    test "a step-rooted composite is refused on a group's interrupts slot" do
      candidate = Block.new("myapp.authorize_then_settle", id: "blk_cand")

      assert {:error, findings} =
               Assignability.check(
                 palette(),
                 group_document(),
                 {"blk_GRP", "interrupts", 0},
                 candidate,
                 ctx()
               )

      assert {:kind_not_admitted, "blk_cand", "blk_GRP", "interrupts", [:step],
              [:interrupt_handler]} in findings
    end
  end

  describe "admission and the compiler agree on the same document" do
    test "the handler-rooted composite at a sequence body is refused by both" do
      candidate = Block.new("myapp.watch_for_chargeback", id: "blk_cand")

      {:error, admission_findings} =
        Assignability.check(
          palette(),
          sequence_document(),
          {"blk_ROOT", "body", 0},
          candidate,
          ctx()
        )

      admitted =
        for {:kind_not_admitted, _id, _parent, slot, kinds, accepts} <- admission_findings,
            do: {slot, kinds, accepts}

      root = Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [candidate]})
      document = Document.new(root, id: "bdoc_pk_compile")

      assert {:error, compiler_findings} =
               Compiler.compile(document, palette(), entry_type: "myapp.transaction")

      compiled =
        for %Finding{reason: {:kind_not_admitted, _id, _parent, slot, kinds, accepts}} <-
              compiler_findings,
            do: {slot, kinds, accepts}

      assert admitted == [{"body", [:interrupt_handler], [:step]}]
      assert compiled == admitted
    end
  end
end
