defmodule StatifierBlocks.Runtime.DurableSubchartOverridablesTest do
  @moduledoc """
  Pins the one callback a `use StatifierBlocks.Runtime.DurableSubchart`
  module may override.

  `defoverridable dispatch: 3` leaves no introspectable trace once the
  module is compiled. Drop it from
  `StatifierBlocks.Runtime.DurableSubchart.__using__/1` and a host that
  writes its own `dispatch/3` - to serve a second invoke type beside this
  one, which is exactly the case the moduledoc names - stops replacing the
  injected delegation and quietly becomes a second clause after it, so the
  delegation answers first and the host's arm is never reached. The
  moduledoc saying the injected `dispatch/3` is overridable is prose, and
  prose does not go red.

  So it is pinned the way a caller experiences it, in the shape
  `StatifierBlocks.Composite.OverridablesTest` uses for the composite macro:
  a host writes its own `dispatch/3` answering something the delegation
  could not produce, and the test asks which answer comes back.

  A pure test: nothing is started and no chart is resolved.
  """

  use ExUnit.Case, async: true

  defmodule Overrides do
    @moduledoc "One durable host overriding the injected dispatch/3."

    use StatifierBlocks.Runtime.DurableSubchart

    @impl StatifierBlocks.Runtime.Subchart
    def resolve_chart(_document_id, _ctx), do: :error

    @impl StatifierBlocks.Runtime.Subchart
    def palette, do: StatifierBlocks.Palette.core()

    def dispatch(_type, _params, _context), do: {:error, [reason: :overridden, detail: %{}]}
  end

  # Sabotage, run once: emptied
  # `StatifierBlocks.Runtime.DurableSubchart.__using__/1`'s `defoverridable`
  # list - the test below went red on the `ArgumentError` the injected
  # delegation raises for an invoke type it does not serve, which is exactly
  # the second-invoke-type case the moduledoc says a host overrides
  # `dispatch/3` for, while the behaviour test below stayed green (verified).
  describe "the callback a durable subchart host may override" do
    test "dispatch/3 answers the host's own def, not the delegation to dispatch/4" do
      assert Overrides.dispatch("any:type", %{}, %{}) ==
               {:error, [reason: :overridden, detail: %{}]}
    end
  end

  describe "what the use macro declares" do
    # ADR-0008 decision 2: the behaviour is `Runtime.Subchart`'s own, in
    # full and without additions. `defoverridable` is not what carries that,
    # so it is asserted separately from the override above.
    test "the host carries the Runtime.Subchart behaviour and no second one" do
      behaviours =
        Overrides.module_info(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert behaviours == [StatifierBlocks.Runtime.Subchart]
    end
  end
end
