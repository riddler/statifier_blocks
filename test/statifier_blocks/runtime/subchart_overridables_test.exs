defmodule StatifierBlocks.Runtime.SubchartOverridablesTest do
  @moduledoc """
  Pins the set of handler callbacks a `use StatifierBlocks.Runtime.Subchart`
  module may override.

  `defoverridable` leaves no introspectable trace once the module is
  compiled, so a name dropped from the list in
  `StatifierBlocks.Runtime.Subchart.__using__/1` changes nothing a reader of
  the compiled module can see: the host's `def` stops replacing the injected
  delegation and quietly becomes a second clause after it, and the
  delegation keeps winning. The moduledoc beside the list is prose, and
  prose does not go red.

  So the set is pinned the way a caller experiences it, which is the shape
  `StatifierBlocks.Composite.OverridablesTest` uses for the composite macro:
  one host writes its own `def` for every name on the list, each answering
  something the delegation could not produce, and the test asks which answer
  comes back. This matters more here than elsewhere, because the whole
  reason a host `use`s this module is to take over one leg of the handler
  protocol - `forward/3` for a host that filters events, say - while leaving
  the other two delegated.

  A pure test: nothing is started, and the overriding clauses answer without
  reaching the runtime.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.Palette

  defmodule Overrides do
    @moduledoc "One host overriding all three delegated callbacks."

    use StatifierBlocks.Runtime.Subchart

    @impl StatifierBlocks.Runtime.Subchart
    def resolve_chart(_document_id, _ctx), do: :error

    @impl StatifierBlocks.Runtime.Subchart
    def palette, do: StatifierBlocks.Palette.core()

    @impl Statifier.Invoke.Handler
    def start(_invoke, _ctx), do: {:ok, [:overridden_start]}

    @impl Statifier.Invoke.Handler
    def cancel(_invoke_id, _ctx), do: {:ok, [:overridden_cancel]}

    @impl Statifier.Invoke.Handler
    def forward(_invoke_id, _event, _ctx), do: {:ok, [:overridden_forward]}
  end

  # Sabotage for this whole describe block, run once: emptied
  # `StatifierBlocks.Runtime.Subchart.__using__/1`'s `defoverridable` list -
  # all three tests below went red, `start/2` and `cancel/2` on the
  # delegation's answer and `forward/3` on the `FunctionClauseError` the
  # delegation raises for an argument that is not a `Statifier.Event`, while
  # the two tests in the second describe block stayed green (verified).
  #
  # The arguments are plain terms rather than a `Statifier.Effect.Invoke`
  # and a `Statifier.Event`: the overriding clauses match on none of them,
  # and the question here is only which definition answers. A real
  # invocation reaching the delegation is `subchart_lifecycle_test.exs`'s
  # subject, not this file's.
  describe "the handler callbacks a subchart host may override" do
    test "start/2 answers the host's own def, not the delegation" do
      assert Overrides.start(:an_invoke, %{}) == {:ok, [:overridden_start]}
    end

    test "cancel/2 answers the host's own def, not the delegation" do
      assert Overrides.cancel("inv", %{}) == {:ok, [:overridden_cancel]}
    end

    test "forward/3 answers the host's own def, not the delegation" do
      assert Overrides.forward("inv", :an_event, %{}) == {:ok, [:overridden_forward]}
    end
  end

  describe "what the use macro declares" do
    # The behaviour is what makes a missing `resolve_chart/2` or `palette/0`
    # a compile warning rather than a runtime surprise, and it is not
    # `defoverridable`'s business - so it is asserted separately from the
    # three above.
    test "the host carries both behaviours" do
      behaviours =
        Overrides.module_info(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert StatifierBlocks.Runtime.Subchart in behaviours
      assert Statifier.Invoke.Handler in behaviours
    end

    test "palette/0 is the host's, reaching the compile through the module" do
      assert %Palette{} = Overrides.palette()
    end
  end
end
