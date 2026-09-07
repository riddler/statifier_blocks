defmodule StatifierBlocks.Edit.TargetsRecipesTest do
  @moduledoc """
  `Edit.Targets.accepted_recipes/4` and `recipe_inserts/4`: the recipe half
  of what-may-land-where, asked once rather than once per surface.

  The defect these two readers close is the one ADR-0005's Note of
  2026-09-07 item 1 names: both answers existed and both were private to
  `StatifierBlocks.Editor`, so a host drawing its own picker had to
  re-derive them, and a re-derivation is where clause 3C's bound goes quiet.

  Two documents, one per canonical example domain, because the readers are
  asked about a target in a document rather than about a palette alone: the
  same two questions have to answer the same way in a card-processing
  document and in a signup document.

  A pure test. Nothing here names LiveView, so it compiles and runs headless.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.Edit.Targets

  alias StatifierBlocks.{Block, Document, Palette, Recipe}

  defmodule Reaching do
    @moduledoc """
    A recipe whose command list reaches a block the armed position does not
    enclose - clause 3C's bound broken, which is a recipe module's bug and
    is what `within_reach?/2` exists to catch at the caller.
    """

    @behaviour StatifierBlocks.Recipe

    @impl true
    def palette_entry, do: %{label: "Reaching", group: "Structure", order: 91}

    @impl true
    def insert(_target, _document) do
      {:ok, [{:insert, {"blk_ROOT", "body", 0}, Block.new("core.wait", id: "blk_REACH")}]}
    end
  end

  # Card processing.
  #
  #   blk_ROOT (core.sequence)
  #     body: [blk_CAPTURE_GROUP, blk_TAIL]
  #
  #   blk_CAPTURE_GROUP (core.group) - has an interrupts rail
  #     body: [blk_AUTHORIZE (core.invoke, myapp:authorize)]
  #
  #   blk_TAIL (core.sequence) - no interrupts rail, the refusal case
  defp card_document do
    authorize =
      Block.new("core.invoke",
        id: "blk_AUTHORIZE",
        config: %{"invoke_type" => "myapp:authorize"}
      )

    group = Block.new("core.group", id: "blk_CAPTURE_GROUP", slots: %{"body" => [authorize]})
    tail = Block.new("core.sequence", id: "blk_TAIL")

    Document.new(
      Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [group, tail]}),
      id: "bdoc_CARD"
    )
  end

  # Signup, the same two shapes under different names.
  defp signup_document do
    signup =
      Block.new("core.invoke",
        id: "blk_SIGNUP",
        config: %{"invoke_type" => "myapp:signup"}
      )

    group = Block.new("core.group", id: "blk_WELCOME_GROUP", slots: %{"body" => [signup]})
    tail = Block.new("core.sequence", id: "blk_CLOSING")

    Document.new(
      Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [group, tail]}),
      id: "bdoc_SIGNUP"
    )
  end

  defp landing_target(:card), do: {"blk_CAPTURE_GROUP", "body", 1}
  defp landing_target(:signup), do: {"blk_WELCOME_GROUP", "body", 1}

  defp refusing_target(:card), do: {"blk_TAIL", "body", 0}
  defp refusing_target(:signup), do: {"blk_CLOSING", "body", 0}

  defp document(:card), do: card_document()
  defp document(:signup), do: signup_document()

  describe "accepted_recipes/4" do
    # The palette's other map, answered for a target that suits the
    # arrangement. Both domains, because the reader is asked about a target
    # in a document and the answer must not depend on which document.
    #
    # Sabotage: `accepted_recipes/4` filtering on `match?({:error, _}, ...)`
    # rather than `{:ok, _}` - the set comes back empty and this goes red.
    for domain <- [:card, :signup] do
      test "names the recipes that land at the target (#{domain})" do
        assert Targets.accepted_recipes(
                 document(unquote(domain)),
                 Palette.core(),
                 landing_target(unquote(domain))
               ) == MapSet.new(["deadline"])
      end

      # Clause 3C's ordinary refusal, read through the filter: an enclosing
      # block with no interrupts rail offers no deadline row at all.
      #
      # Sabotage: the filter treating `insert/2`'s `{:error, _}` as a fit -
      # "deadline" appears here and the empty-set assertion goes red.
      test "leaves out a recipe whose insert/2 refuses the target (#{domain})" do
        assert Targets.accepted_recipes(
                 document(unquote(domain)),
                 Palette.core(),
                 refusing_target(unquote(domain))
               ) == MapSet.new()
      end
    end

    # ADR-0005's Note of 2026-09-07 item 1, "What item 1 does not decide":
    # the fourth argument is there for the shape a caller asks both maps in,
    # and `Recipe.insert/2` is handed the target and the document and nothing
    # else. A context therefore cannot change the answer.
    #
    # Sabotage: threading `ctx` into `recipe_inserts/4` and on to a recipe -
    # `insert/2` is arity 2, so the call fails and this goes red.
    test "a context does not change the answer, because it reaches no recipe" do
      target = landing_target(:card)
      document = document(:card)

      permissive = Targets.accepted_recipes(document, Palette.core(), target)

      opinionated =
        Targets.accepted_recipes(document, Palette.core(), target, %{
          entry_type: "myapp:authorize"
        })

      assert permissive == opinionated
      assert permissive == MapSet.new(["deadline"])
    end

    # A palette with no recipes has no recipe rows to offer, which is the
    # case a host that registered none is in.
    #
    # Sabotage: falling back to `core_recipes/0` when the map is empty -
    # "deadline" appears and this goes red.
    test "a palette carrying no recipes answers the empty set" do
      assert Targets.accepted_recipes(
               document(:card),
               Palette.new(Palette.core_types()),
               landing_target(:card)
             ) == MapSet.new()
    end

    # The composition the Note makes the point of the promotion: the filter's
    # test IS `recipe_inserts/4`, spelled once instead of twice, so the paint
    # and the write cannot drift apart on which recipes fit.
    #
    # Sabotage: giving `accepted_recipes/4` its own copy of the two checks
    # and dropping the reach check from the copy - "reaching" joins the set
    # while `recipe_inserts/4` still refuses it, and this goes red.
    test "is exactly the recipes recipe_inserts/4 answers {:ok, _} for" do
      palette =
        Palette.new(Palette.core_types(),
          recipes: Map.put(Palette.core_recipes(), "reaching", Reaching)
        )

      document = document(:signup)
      target = landing_target(:signup)

      accepted = Targets.accepted_recipes(document, palette, target)

      by_hand =
        palette.recipes
        |> Map.keys()
        |> Enum.filter(
          &match?({:ok, _commands}, Targets.recipe_inserts(document, palette, &1, target))
        )
        |> MapSet.new()

      assert accepted == by_hand
      assert accepted == MapSet.new(["deadline"])
    end
  end

  describe "recipe_inserts/4" do
    # The commands, and nothing committed: the reader answers the list the
    # recipe answered with, and assigning, minting a selection and committing
    # the compound stay the editor's.
    #
    # Sabotage: `recipe_inserts/4` returning `{:ok, []}` regardless - the
    # command-shape assertions go red.
    for domain <- [:card, :signup] do
      test "answers the recipe's own command list (#{domain})" do
        document = document(unquote(domain))
        target = landing_target(unquote(domain))
        {parent_id, _slot, _index} = target

        assert {:ok, commands} =
                 Targets.recipe_inserts(document, Palette.core(), "deadline", target)

        assert [
                 {:insert, {^parent_id, "body", 0}, %Block{type: "core.send"}},
                 {:insert, {^parent_id, "interrupts", 0}, %Block{type: "core.on_event"}}
               ] = commands

        # The recipe's own output, passed through rather than rebuilt: the
        # two halves still name the one generated event that couples them,
        # and the reader minted nothing of its own.
        [{:insert, _send_target, send_block}, {:insert, _rail_target, handler}] = commands
        assert send_block.config["event"] == handler.config["event"]
        assert Recipe.within_reach?(target, commands)
      end
    end

    # `Palette.fetch_recipe/2`'s refusal, passed through by name rather than
    # flattened into a boolean - a host calling this reader alone gets the
    # reason.
    #
    # Sabotage: rescuing the fetch to `{:error, :unknown}` - the tuple's
    # name is gone and this goes red.
    test "a name the palette does not carry refuses by name" do
      assert {:error, {:unknown_recipe, "no_such_recipe"}} =
               Targets.recipe_inserts(
                 document(:card),
                 Palette.core(),
                 "no_such_recipe",
                 landing_target(:card)
               )
    end

    # Clause 3C's ordinary case: the arrangement does not fit the position
    # the author armed, and the recipe's own reason is what comes back.
    #
    # Sabotage: mapping every `insert/2` refusal onto
    # `{:recipe_out_of_reach, name}` - the two kinds of refusal stop being
    # distinguishable and this goes red.
    for domain <- [:card, :signup] do
      test "an insert/2 refusal comes back as the recipe stated it (#{domain})" do
        assert {:error, {:no_interrupts_slot, _id}} =
                 Targets.recipe_inserts(
                   document(unquote(domain)),
                   Palette.core(),
                   "deadline",
                   refusing_target(unquote(domain))
                 )
      end
    end

    # Clause 3C's bound, enforced at the caller against the recipe's own
    # output. A list reaching outside the armed position's enclosing block
    # is a recipe module's bug and is refused before it is applied.
    #
    # Sabotage: dropping the `within_reach?/2` clause - the reaching list is
    # answered as `{:ok, _}` and this goes red.
    test "a command list outside clause 3C's bound is refused" do
      palette = Palette.new(Palette.core_types(), recipes: %{"reaching" => Reaching})

      assert {:error, {:recipe_out_of_reach, "reaching"}} =
               Targets.recipe_inserts(
                 document(:card),
                 palette,
                 "reaching",
                 landing_target(:card)
               )
    end
  end
end
