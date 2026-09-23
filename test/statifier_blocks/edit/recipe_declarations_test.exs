defmodule StatifierBlocks.Edit.RecipeDeclarationsTest do
  @moduledoc """
  A recipe may write the document's two declarations - the datamodel roots
  and the accepts list - beside the blocks it inserts, and clause 3C's bound
  does not refuse either (ADR-0005's Amendment of 2026-09-22 on 3C).

  A declaration names no position, so there is no reach for it to exceed.
  The bound still holds for every command that does name one: a declaration
  in the list does not carry an out-of-reach insert past the check.

  One document, in the patron registration domain: a visitor becoming a
  library patron proves they own an email address, and a recipe that arms
  the wait for that proof also declares the event the host sends in.

  A pure test. Nothing here names LiveView, so it compiles and runs headless.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Document, Edit, Palette, Recipe}
  alias StatifierBlocks.Document.DatamodelEntry
  alias StatifierBlocks.Edit.Targets

  defmodule AwaitVerification do
    @moduledoc """
    Inserts a wait on `email.verified` at the armed position and adds that
    name to the document's accepts list, so the declaration and the handler
    arrive in one undo entry.
    """

    @behaviour StatifierBlocks.Recipe

    @impl true
    def palette_entry, do: %{label: "Await verification", group: "Patrons", order: 1}

    @impl true
    def insert(target, document) do
      wait =
        Block.new("core.await",
          id: "blk_AWAIT_VERIFIED",
          config: %{"event" => "email.verified", "timeout" => "P1D"}
        )

      {:ok,
       [
         {:insert, target, wait},
         {:set_accepts, Enum.uniq(document.accepts ++ ["email.verified"])}
       ]}
    end
  end

  defmodule RecordEmail do
    @moduledoc """
    Declares the `patron_email` datamodel root first, then inserts the wait
    that the address is verified - the declaration leads the list.
    """

    @behaviour StatifierBlocks.Recipe

    @impl true
    def palette_entry, do: %{label: "Record the email", group: "Patrons", order: 2}

    @impl true
    def insert(target, document) do
      root = %DatamodelEntry{id: "patron_email", expr: "''"}

      wait =
        Block.new("core.await", id: "blk_AWAIT_EMAIL", config: %{"event" => "email.verified"})

      {:ok, [{:set_datamodel, document.datamodel ++ [root]}, {:insert, target, wait}]}
    end
  end

  defmodule DeclaringAndReaching do
    @moduledoc """
    Writes a declaration and an insert above the enclosing block - clause
    3C's bound broken by the insert, whatever the declaration beside it.
    """

    @behaviour StatifierBlocks.Recipe

    @impl true
    def palette_entry, do: %{label: "Declaring and reaching", group: "Patrons", order: 3}

    @impl true
    def insert(_target, _document) do
      {:ok,
       [
         {:set_accepts, ["email.verified"]},
         {:insert, {"blk_ROOT", "body", 0}, Block.new("core.wait", id: "blk_REACH")}
       ]}
    end
  end

  #   blk_ROOT (core.sequence)
  #     body: [blk_REGISTRATION_GROUP]
  #
  #   blk_REGISTRATION_GROUP (core.group)
  #     body: [blk_SEND_VERIFICATION (core.invoke, myapp:send_verification)]
  defp document(accepts) do
    send_verification =
      Block.new("core.invoke",
        id: "blk_SEND_VERIFICATION",
        config: %{"invoke_type" => "myapp:send_verification"}
      )

    group =
      Block.new("core.group",
        id: "blk_REGISTRATION_GROUP",
        slots: %{"body" => [send_verification]}
      )

    Document.new(
      Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => [group]}),
      id: "bdoc_PATRONREG",
      accepts: accepts
    )
  end

  @target {"blk_REGISTRATION_GROUP", "body", 1}

  defp palette do
    Palette.new(Palette.core_types(),
      recipes: %{
        "await_verification" => AwaitVerification,
        "record_email" => RecordEmail,
        "declaring_and_reaching" => DeclaringAndReaching
      }
    )
  end

  describe "Recipe.within_reach?/2" do
    # Sabotage: deleting the `{:set_accepts, _names}` clause of the private
    # `reach/3` - the command falls to the last clause, halts as out of
    # reach, and both assertions go red.
    test "a list holding {:set_accepts, _} is within reach" do
      assert Recipe.within_reach?(@target, [{:set_accepts, ["email.verified"]}])

      assert Recipe.within_reach?(@target, [
               {:insert, @target, Block.new("core.await", id: "blk_A")},
               {:set_accepts, ["email.verified", "registration.abandoned"]}
             ])
    end

    # Sabotage: deleting the `{:set_datamodel, _entries}` clause of the
    # private `reach/3` - the command falls to the last clause, halts as out
    # of reach, and both assertions go red.
    test "a list holding {:set_datamodel, _} is still within reach" do
      root = %DatamodelEntry{id: "patron_email", expr: "''"}

      assert Recipe.within_reach?(@target, [{:set_datamodel, [root]}])

      assert Recipe.within_reach?(@target, [
               {:set_datamodel, [root]},
               {:insert, @target, Block.new("core.await", id: "blk_A")}
             ])
    end

    # A declaration admits itself and nothing else: the insert that reaches
    # above the enclosing block is refused wherever the declaration sits.
    #
    # Sabotage: making the `{:set_accepts, _names}` clause answer
    # `{:halt, minted}` - `reduce_while/3` stops on the declaration with a
    # set rather than `:out_of_reach`, the insert after it is never read,
    # and the first assertion goes red.
    test "a declaration does not carry an out-of-reach insert past the bound" do
      reaching = {:insert, {"blk_ROOT", "body", 0}, Block.new("core.wait", id: "blk_REACH")}

      refute Recipe.within_reach?(@target, [{:set_accepts, ["email.verified"]}, reaching])
      refute Recipe.within_reach?(@target, [{:set_datamodel, []}, reaching])
    end
  end

  describe "Edit.Targets.recipe_inserts/4" do
    # The whole gesture below the editor: the recipe's list passes the
    # bound, and committed as one compound it writes the handler and the
    # declaration together.
    #
    # Sabotage: deleting the `{:set_accepts, _names}` clause of the private
    # `reach/3` - `recipe_inserts/4` answers
    # `{:error, {:recipe_out_of_reach, "await_verification"}}` and this goes
    # red.
    test "a recipe writing {:set_accepts, _} is admitted and its compound applies" do
      document = document(["registration.abandoned"])

      assert {:ok, commands} =
               Targets.recipe_inserts(document, palette(), "await_verification", @target)

      assert {:ok, updated, _inverse} = Edit.apply(document, {:compound, commands})
      assert updated.accepts == ["registration.abandoned", "email.verified"]
    end

    # Sabotage: deleting the `{:set_datamodel, _entries}` clause of the
    # private `reach/3` - `recipe_inserts/4` answers
    # `{:error, {:recipe_out_of_reach, "record_email"}}` and this goes red.
    test "a recipe writing {:set_datamodel, _} is still admitted" do
      document = document([])

      assert {:ok, [{:set_datamodel, [%DatamodelEntry{id: "patron_email"}]}, {:insert, _, _}]} =
               Targets.recipe_inserts(document, palette(), "record_email", @target)
    end

    # Sabotage: the same `{:halt, minted}` answer for `{:set_accepts, _}` -
    # the reduce stops before the reaching insert, `within_reach?/2` answers
    # true, and this comes back `{:ok, _}`.
    test "a recipe declaring and reaching is still refused" do
      assert {:error, {:recipe_out_of_reach, "declaring_and_reaching"}} =
               Targets.recipe_inserts(document([]), palette(), "declaring_and_reaching", @target)
    end
  end
end
