defmodule StatifierBlocks.PlanTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Document, Palette, Plan}
  alias StatifierBlocks.Edit.Targets

  doctest StatifierBlocks.Plan

  @corpus "test/fixtures/documents"

  # A loan's renewal notice, which has to carry at least one reminder, and
  # which only a block of kind `:reminder` may fill. No palette in this
  # file registers a `:reminder` type, so the slot is one no palette here
  # can fill.
  defmodule RenewalNotice do
    @moduledoc false
    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: [{"reminders", :at_least_one, "Reminders"}]
    @impl true
    def config_schema(_config), do: []
    @impl true
    def validate_config(_config), do: :ok
    @impl true
    def io(_config), do: %{kinds: [:step], slot_accepts: %{"reminders" => [:reminder]}}
    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}
  end

  # A copy held for a patron: exactly one step says what happens at pickup.
  defmodule Hold do
    @moduledoc false
    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: [{"pickup", :exactly_one, "At pickup"}]
    @impl true
    def config_schema(_config), do: []
    @impl true
    def validate_config(_config), do: :ok
    @impl true
    def io(_config), do: %{kinds: [:step], slot_accepts: %{"pickup" => [:step]}}
    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}
  end

  # Three typed steps of a loan, each reading what the one before it wrote
  # at the loan's subject path: a request, then the copy lent against it,
  # then the copy coming back.
  defmodule Request do
    @moduledoc false
    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []
    @impl true
    def config_schema(_config), do: []
    @impl true
    def validate_config(_config), do: :ok
    @impl true
    def io(_config), do: %{kinds: [:step], produces: "library.request"}
    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}
    @impl true
    def palette_entry, do: %{subject: "loan.current"}
  end

  defmodule Lend do
    @moduledoc false
    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []
    @impl true
    def config_schema(_config), do: []
    @impl true
    def validate_config(_config), do: :ok
    @impl true
    def io(_config), do: %{kinds: [:step], consumes: "library.request", produces: "library.loan"}
    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}
    @impl true
    def palette_entry, do: %{subject: "loan.current"}
  end

  defmodule Return do
    @moduledoc false
    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []
    @impl true
    def config_schema(_config), do: []
    @impl true
    def validate_config(_config), do: :ok
    @impl true
    def io(_config), do: %{kinds: [:step], consumes: "library.loan"}
    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}
    @impl true
    def palette_entry, do: %{subject: "loan.current"}
  end

  defp decode!(name) do
    {:ok, document} = Document.from_json(File.read!(Path.join(@corpus, name)))
    document
  end

  defp library_palette do
    Palette.new(
      Map.merge(Palette.core_types(), %{
        "library.renewal_notice" => RenewalNotice,
        "library.hold" => Hold,
        "library.request" => Request,
        "library.lend" => Lend,
        "library.return" => Return
      })
    )
  end

  defp document(children, root_type \\ "core.sequence") do
    Document.new(Block.new(root_type, id: "blk_ROOT", slots: %{"body" => children}), id: "doc_1")
  end

  describe "the corpus" do
    # Mutation: make `expressible/3` answer `{:no, []}` instead of `:ok`
    # for an empty reason list - red.
    test "patron registration is expressible through the core palette" do
      assert Plan.expressible(decode!("patron_registration.json"), Palette.core()) == :ok
    end

    # Mutation: drop the `Assignability.validate/3` kind findings from the
    # reason list - red, the document reads as expressible.
    test "a handler dropped into a group's body is refused, naming the handler and the rule" do
      document = decode!("expressible/handler_in_body.json")

      assert {:no,
              [
                {:not_admitted, "blk_PABN",
                 {:kind_not_admitted, "blk_PABN", "blk_PGRP", "body", [:interrupt_handler],
                  [:step]}}
              ]} = Plan.expressible(document, Palette.core())
    end

    # Mutation: drop `unfillable_reasons/4` from the reason list - red, the
    # slot is no longer reported.
    test "a required slot the palette cannot fill names the block and the slot" do
      document = decode!("expressible/empty_required_slot.json")

      assert Plan.expressible(document, library_palette()) ==
               {:no, [{:unfillable_slot, "blk_RNOT", "reminders"}]}
    end
  end

  describe "rule 2 at the block's own position" do
    # Mutation: make `expressible/3` answer `{:no, []}` instead of `:ok` for
    # an empty reason list - red.
    test "a typed chain whose every read is satisfied is expressible" do
      document =
        document([
          Block.new("library.request", id: "blk_REQ"),
          Block.new("library.lend", id: "blk_LEND"),
          Block.new("library.return", id: "blk_RET")
        ])

      assert Plan.expressible(document, library_palette()) == :ok
    end

    # Mutation: drop the `:kind_not_admitted` filter in
    # `admission_findings/3` - red: the return's mismatched read comes back as
    # `{:not_admitted, "blk_RET", {:type_mismatch, ...}}`, a refusal the
    # editor does not make.
    test "a read the environment contradicts is not a reason, since the editor offers that drop" do
      {:ok, probe} = Targets.probe(library_palette(), "library.return")
      before = document([Block.new("library.request", id: "blk_REQ")])

      assert {"blk_ROOT", "body"} in Targets.droppable_slots_for(
               before,
               library_palette(),
               probe,
               %{}
             )

      document =
        document([
          Block.new("library.request", id: "blk_REQ"),
          Block.new("library.return", id: "blk_RET")
        ])

      assert {:error, [{:type_mismatch, "blk_RET", "blk_REQ", _, _, _}]} =
               StatifierBlocks.Assignability.validate(library_palette(), document, %{})

      assert Plan.expressible(document, library_palette()) == :ok
    end
  end

  describe "rules 1 and 3, and resolution" do
    # Mutation: make `resolution_reasons/2` answer `[]` for every block - red.
    test "a block whose type the palette does not carry is unresolved" do
      document = document([Block.new("library.lend", id: "blk_LEND")])

      assert Plan.expressible(document, Palette.core()) ==
               {:no, [{:unresolved, "blk_LEND", {:unknown_block_type, "library.lend"}}]}
    end

    # Mutation: answer `[]` where `declared_arity/3` finds no declaration - red.
    test "a block in a slot its parent does not declare is refused" do
      stray = Block.new("core.raise", id: "blk_RSE", config: %{"event" => "loan.lost"})
      root = Block.new("core.sequence", id: "blk_ROOT", slots: %{"stray" => [stray]})

      assert Plan.expressible(Document.new(root, id: "doc_1"), Palette.core()) ==
               {:no, [{:slot_not_declared, "blk_RSE", {"blk_ROOT", "stray"}}]}
    end

    # Mutation: change `room_reasons/4`'s guard to `index >= 2` - red.
    test "a second child in a single-child slot has no room, the first does" do
      first = Block.new("core.raise", id: "blk_R1", config: %{"event" => "loan.lost"})
      second = Block.new("core.raise", id: "blk_R2", config: %{"event" => "loan.lost"})

      invoke =
        Block.new("core.invoke",
          id: "blk_INV",
          config: %{"invoke_type" => "library:hold"},
          slots: %{"on_error" => [first, second]}
        )

      assert Plan.expressible(document([invoke]), Palette.core()) ==
               {:no, [{:no_room, "blk_R2", {"blk_INV", "on_error", 1}}]}
    end
  end

  describe "a required slot" do
    # Mutation: drop the `Enum.empty?/1` filter from `unfillable_reasons/4`'s
    # comprehension - red, the arm is reported although a step fills it.
    test "that is empty, and the palette can fill, is not a reason" do
      branch =
        Block.new("core.branch",
          id: "blk_BR",
          config: %{"arms" => [%{"slot" => "arm_overdue", "cond" => "overdue"}]}
        )

      assert Plan.expressible(document([branch]), Palette.core()) == :ok
    end

    # Mutation: drop the `== []` filter from `unfillable_reasons/4`'s
    # comprehension - red: a full `:exactly_one` slot admits nothing at its
    # append gap, so it would be reported as unfillable.
    test "that is already filled is not a reason" do
      lost = Block.new("core.raise", id: "blk_RSE", config: %{"event" => "loan.lost"})
      hold = Block.new("library.hold", id: "blk_HOLD", slots: %{"pickup" => [lost]})

      assert Plan.expressible(document([hold]), library_palette()) == :ok
    end
  end

  describe "the context" do
    # Mutation: call `Assignability.validate/3` with `%{}` instead of `ctx` -
    # red: the skipped handler's kind finding comes back.
    test "is the one the assignability check is asked with" do
      handler =
        Block.new("core.on_event",
          id: "blk_LOST",
          config: %{"event" => "loan.lost", "outcome" => "lost"}
        )

      assert {:no, [{:not_admitted, "blk_LOST", {:kind_not_admitted, _, _, _, _, _}}]} =
               Plan.expressible(document([handler]), Palette.core())

      assert Plan.expressible(document([handler]), Palette.core(), %{
               skip_blocks: MapSet.new(["blk_LOST"])
             }) == :ok
    end
  end

  describe "the boolean" do
    # Mutation: make `expressible?/3` return `expressible/3`'s answer as is,
    # without the `== :ok` - red: `:ok` is truthy but not `true`.
    test "is true for a document the tagged answer calls expressible" do
      document = decode!("patron_registration.json")

      assert Plan.expressible(document, Palette.core()) == :ok
      assert Plan.expressible?(document, Palette.core()) == true
    end

    # Mutation: make `expressible?/3` answer `true` for every document - red.
    # Returning the tagged answer as is is red too: `{:no, reasons}` is
    # truthy, which is the reading this function exists to rule out.
    test "is false for a document the tagged answer refuses" do
      document = decode!("expressible/handler_in_body.json")

      assert {:no, [_ | _]} = Plan.expressible(document, Palette.core())
      assert Plan.expressible?(document, Palette.core()) == false
    end

    # Mutation: call `expressible/3` with `%{}` instead of `ctx` inside
    # `expressible?/3` - red: the skipped handler is refused again.
    test "is asked with the same context as the tagged answer" do
      handler =
        Block.new("core.on_event",
          id: "blk_LOST",
          config: %{"event" => "loan.lost", "outcome" => "lost"}
        )

      ctx = %{skip_blocks: MapSet.new(["blk_LOST"])}

      assert Plan.expressible?(document([handler]), Palette.core()) == false
      assert Plan.expressible(document([handler]), Palette.core(), ctx) == :ok
      assert Plan.expressible?(document([handler]), Palette.core(), ctx) == true
    end
  end
end
