defmodule StatifierBlocks.Composite.DeclaringSlotsRaiseTest do
  @moduledoc """
  What a declaring composite's `slots/1` may raise.

  `ADR-0002`'s `C7` item 1 derives one slot per declared outcome, labelled
  from `outcomes/1`'s own answer, which is what makes the two agree by
  construction rather than by test. The cost is a reach: `slots/1` on a
  composite that DECLARES outcomes now runs the same expansion `outcomes/1`
  runs, so it inherits that callback's raise class where it used to have
  none. `C3`'s "gains no new way to fail" is scoped to the composite that
  declares none - it answers from the declaration alone and never expands.

  That is the boundary these tests pin: for one declaration, `slots/1` raises
  only where `outcomes/1` already raises, and for a composite that declares
  no outcomes `slots/1` does not raise at all even when `outcomes/1` does.

  The fixtures are the signup wizard's, with a param that makes `subtree/1`
  answer an empty list - the smallest broken declaration `expand!/2` refuses.

  A pure test. Nothing here names LiveView, so it compiles and runs headless.
  """

  use ExUnit.Case, async: true

  defmodule ConfirmSubtree do
    @moduledoc """
    One subtree for both declarations below, sound or broken by the same
    param, so the only difference between the two modules is the `outcomes`
    key.
    """

    alias StatifierBlocks.Block

    @doc "A sequence over an await, or nothing at all when `broken` is set."
    @spec build(map()) :: [Block.t()]
    def build(%{"broken" => true}), do: []

    def build(params) do
      [
        Block.new("core.sequence",
          id: "body",
          slots: %{
            "body" => [
              Block.new("core.await",
                id: "wait",
                config: %{"event" => params["event"], "timeout" => "10m"}
              )
            ]
          }
        )
      ]
    end
  end

  defmodule ConfirmStepDeclaring do
    @moduledoc "Declares outcomes, so its `slots/1` reaches the expansion."

    use StatifierBlocks.Composite,
      name: "signup.confirm_step_declaring",
      params: [
        %{key: "event", type: :string, label: "Confirmed by", required?: true, default: ""},
        %{key: "broken", type: :boolean, label: "Broken", required?: false, default: false}
      ],
      outcomes: ["received"],
      palette_entry: %{label: "Confirm the contact"},
      version: 1

    alias StatifierBlocks.Composite.DeclaringSlotsRaiseTest.ConfirmSubtree

    @impl StatifierBlocks.Composite
    def subtree(params), do: ConfirmSubtree.build(params)
  end

  defmodule ConfirmStepPlain do
    @moduledoc """
    Byte for byte the declaration above without the `outcomes` key: `C3`'s
    composite, whose `slots/1` answers the declaration and expands nothing.
    """

    use StatifierBlocks.Composite,
      name: "signup.confirm_step",
      params: [
        %{key: "event", type: :string, label: "Confirmed by", required?: true, default: ""},
        %{key: "broken", type: :boolean, label: "Broken", required?: false, default: false}
      ],
      palette_entry: %{label: "Confirm the contact"},
      version: 1

    alias StatifierBlocks.Composite.DeclaringSlotsRaiseTest.ConfirmSubtree

    @impl StatifierBlocks.Composite
    def subtree(params), do: ConfirmSubtree.build(params)
  end

  describe "a declaring composite's slots/1 raises where outcomes/1 raises" do
    # Sabotage: made `outcome_slots/3` answer `[]` for a declaration whose
    # expansion is broken, by rescuing around `derived_outcomes/2` - green
    # here, and then `slots/1` and `outcomes/1` disagree about the same
    # declaration, which is the one thing `C7` item 1 derives them together
    # to prevent.
    test "the same declaration, the same raise, word for word" do
      config = broken()

      outcomes_error =
        assert_raise ArgumentError, fn -> ConfirmStepDeclaring.outcomes(config) end

      slots_error =
        assert_raise ArgumentError, fn -> ConfirmStepDeclaring.slots(config) end

      assert slots_error.message == outcomes_error.message
      assert slots_error.message =~ "subtree/1 must answer a non-empty list"
    end

    # Sabotage: dropped `outcome_slots/3` from `derived_slots/2` - red,
    # because the derived slot disappears and there is nothing for an author
    # to hang the outcome's continuation off.
    test "neither raises for a sound declaration, and the derived slot is there" do
      config = sound()

      assert ConfirmStepDeclaring.outcomes(config) == [{"received", "Received"}]
      assert {"on_received", :zero_or_one, "Received"} in ConfirmStepDeclaring.slots(config)
    end
  end

  describe "C3: a composite that declares no outcomes gains no new way to fail" do
    # The boundary. Sabotage: made `outcome_slots/3` expand unconditionally
    # rather than only for a declaration carrying `outcomes` - red, because
    # this module's `slots/1` would then raise on a declaration it has always
    # answered from the declaration alone.
    test "its outcomes/1 raises on the broken declaration and its slots/1 does not" do
      config = broken()

      assert_raise ArgumentError, fn -> ConfirmStepPlain.outcomes(config) end
      assert ConfirmStepPlain.slots(config) == []
    end
  end

  # -- fixtures ------------------------------------------------------------

  defp sound, do: %{"event" => "contact.confirmed"}

  defp broken, do: %{"event" => "contact.confirmed", "broken" => true}
end
