defmodule StatifierBlocks.DeclarationsTest do
  @moduledoc """
  The declarations panel's arithmetic (ADR-0005's 2026-09-01 amendment,
  2g-2m), held with no editor present.

  Deliberately **not** tagged `:liveview`, and that is the point rather than
  a convenience: decision 1 puts every decision with a return value outside
  `StatifierBlocks.Editor.*` so it can be asserted with
  `phoenix_live_view` absent from the dependency tree, and which entry moved
  and what the new list is are exactly such decisions.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.Declarations
  alias StatifierBlocks.Document.DatamodelEntry

  doctest Declarations

  defp entry(id, opts \\ []) do
    %DatamodelEntry{
      id: id,
      expr: Keyword.get(opts, :expr),
      description: Keyword.get(opts, :description)
    }
  end

  defp ids(entries), do: Enum.map(entries, & &1.id)

  describe "add/1" do
    # Sabotage: `add/1` appending `%DatamodelEntry{id: ""}` instead of a
    # minted name - the list it produces is one ADR-0001 11b refuses, so
    # pressing Add would answer with a refusal rather than a row, and the
    # round trip through `Validation.datamodel/1` below goes red.
    test "mints a name the grammar accepts, so the press always produces a row" do
      [minted] = Declarations.add([])

      assert minted.id == "root_1"
      assert minted.expr == nil
      assert minted.description == nil
      assert StatifierBlocks.Validation.datamodel([minted]) == :ok
    end

    # Sabotage: minting from `length(entries) + 1` instead of scanning the
    # ids - a list holding only `root_2` mints `root_2` again and 11c's
    # uniqueness refuses the press.
    test "skips every name already taken, and re-uses one that was freed" do
      assert [_kept, minted] = Declarations.add([entry("root_1")])
      assert minted.id == "root_2"

      assert [_kept_two, second] = Declarations.add([entry("root_2")])
      assert second.id == "root_1"
    end

    test "appends rather than prepends, because order is emission order" do
      assert [entry("signup")] |> Declarations.add() |> ids() == ["signup", "root_1"]
    end
  end

  describe "remove/2" do
    # Sabotage: dropping the `in_range?/2` guard - `List.delete_at/2` treats a
    # negative index as counting from the end, so a crafted `-1` removes the
    # LAST declaration instead of none.
    test "drops the named row, and answers an out-of-range index with the list unchanged" do
      entries = [entry("a"), entry("b")]

      assert entries |> Declarations.remove(0) |> ids() == ["b"]
      assert Declarations.remove(entries, 2) == entries
      assert Declarations.remove(entries, -1) == entries
      assert Declarations.remove(entries, :none) == entries
      assert Declarations.remove(entries, "0") == entries
    end
  end

  describe "move/3" do
    # Sabotage: `neighbour/2` answering `{:ok, index + 1}` for `:up` - the
    # first two assertions swap answers, which is the defect an author reads
    # as the buttons being wired backwards.
    test "swaps with the neighbour in the named direction" do
      entries = [entry("a"), entry("b"), entry("c")]

      assert entries |> Declarations.move(1, :up) |> ids() == ["b", "a", "c"]
      assert entries |> Declarations.move(1, :down) |> ids() == ["a", "c", "b"]
    end

    test "takes the direction as it arrives off the wire" do
      entries = [entry("a"), entry("b")]

      assert entries |> Declarations.move(1, "up") |> ids() == ["b", "a"]
      assert entries |> Declarations.move(0, "down") |> ids() == ["b", "a"]
    end

    # Sabotage: dropping the second `in_range?/2` in `move/3` - moving the
    # last row down swaps it with `nil`, and the list stops being a list of
    # entries at all.
    test "is inert off either end, and never wraps" do
      entries = [entry("a"), entry("b")]

      assert Declarations.move(entries, 0, :up) == entries
      assert Declarations.move(entries, 1, :down) == entries
      assert Declarations.move(entries, 0, "sideways") == entries
      assert Declarations.move(entries, :none, :up) == entries
    end
  end

  describe "put/4" do
    # Sabotage: `cast/2` returning the value for every field - clearing the
    # initial-value box writes `""`, which 11b refuses and 11d would never
    # encode, so the ordinary act of emptying a box produces a refusal.
    test "reads a cleared optional box as absent, and never as an empty string" do
      entries = [entry("a", expr: "1", description: "prose")]

      assert entries |> Declarations.put(0, :expr, "") |> hd() |> Map.get(:expr) == nil

      assert entries |> Declarations.put(0, :description, "") |> hd() |> Map.get(:description) ==
               nil
    end

    # Sabotage: casting `:id` through the same clause as the optional fields -
    # a cleared name becomes `nil`, which crashes 11b's regex check rather
    # than producing the refusal the panel is supposed to show.
    test "writes a blank id through verbatim, so the command is the one that refuses it" do
      assert [entry("a")] |> Declarations.put(0, :id, "") |> hd() |> Map.get(:id) == ""

      assert {:error, {:malformed_envelope, {:datamodel, {:entry, 0, {:id, :not_an_identifier}}}}} =
               [entry("a")]
               |> Declarations.put(0, :id, "")
               |> StatifierBlocks.Validation.datamodel()
    end

    test "leaves every other entry alone" do
      entries = [entry("a"), entry("b")]

      assert entries |> Declarations.put(1, :id, "renamed") |> ids() == ["a", "renamed"]
    end

    test "answers an out-of-range index with the list unchanged" do
      entries = [entry("a")]

      assert Declarations.put(entries, 3, :id, "x") == entries
      assert Declarations.put(entries, :none, :id, "x") == entries
    end
  end

  describe "change/3" do
    # Sabotage: mapping `:id` to the key `"id"` - the panel's name box sends
    # `name`, so every rename would be silently dropped while the other two
    # fields kept working.
    test "reads the id off the wire name the form is allowed to use" do
      [changed] = Declarations.change([entry("a")], 0, %{"name" => "signup"})

      assert changed.id == "signup"
    end

    # Sabotage: `Map.get/2` with a `nil` default instead of `Map.fetch/2` -
    # a payload carrying only one field blanks the two beside it.
    test "leaves a field the payload did not carry alone" do
      entries = [entry("a", expr: "1", description: "prose")]

      [changed] = Declarations.change(entries, 0, %{"name" => "b"})

      assert {changed.id, changed.expr, changed.description} == {"b", "1", "prose"}
    end

    test "ignores a key outside the three ADR-0001 11b gives an entry" do
      entries = [entry("a")]

      assert Declarations.change(entries, 0, %{"sensitive?" => "true", "type" => "string"}) ==
               entries
    end
  end

  describe "count/1" do
    test "counts a list and answers zero for anything else" do
      assert Declarations.count([entry("a"), entry("b")]) == 2
      assert Declarations.count([]) == 0
      assert Declarations.count(nil) == 0
    end
  end

  describe "refusal/1" do
    # Sabotage: `refusal/1` falling through to `inspect(reason)` - the panel
    # shows an author `{:malformed_envelope, {:datamodel, {:entry, 0, ...}}}`,
    # which is a term they cannot act on.
    test "phrases every refusal the datamodel grammar produces" do
      assert Declarations.refusal(
               {:malformed_envelope, {:datamodel, {:entry, 0, {:id, :not_an_identifier}}}}
             ) =~ "Declaration 1 needs a name"

      assert Declarations.refusal(
               {:malformed_envelope, {:datamodel, {:entry, 1, {:expr, :not_an_expression}}}}
             ) =~ "Declaration 2's initial value"

      assert Declarations.refusal(
               {:malformed_envelope,
                {:datamodel, {:entry, 2, {:description, :not_a_non_empty_string}}}}
             ) =~ "Declaration 3's description"

      assert Declarations.refusal({:malformed_envelope, {:datamodel, {:duplicate_id, "signup"}}}) =~
               ~s("signup")
    end

    test "answers a term it cannot phrase with a sentence rather than a tuple" do
      assert Declarations.refusal({:no_such_block, "blk_X"}) == "That change was refused."
      assert Declarations.refusal({:malformed_envelope, {:datamodel, :not_a_list}}) =~ "refused"
    end
  end
end
