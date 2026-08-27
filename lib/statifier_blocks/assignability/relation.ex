defmodule StatifierBlocks.Assignability.Relation do
  @moduledoc """
  A host's widening relation. Consulted only after identity has failed, so
  an implementation can only widen, never narrow (ADR-0003 decision 6).

  Pure, under ADR-0002 decision 4: no process dictionary, no application
  configuration, no IO, no clock, no randomness. `assignable?/2` is called
  during validation on every edit, so anything impure here breaks the
  determinism the compiler promises.
  """

  alias StatifierBlocks.Assignability

  @doc """
  Does `produced` widen to satisfy `consumed`? Called only when
  `produced == consumed` has already failed (ADR-0003 decision 6), so a
  module answering `true` here can only grow the accepted set, never
  shrink it.
  """
  @callback assignable?(
              produced :: Assignability.type_expr(),
              consumed :: Assignability.type_expr()
            ) ::
              boolean()
end
