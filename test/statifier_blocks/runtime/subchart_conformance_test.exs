defmodule StatifierBlocks.Runtime.SubchartConformanceTest do
  @moduledoc """
  The mechanical pin: `Statifier.Testing.HandlerCase`'s six generated
  checks against `StatifierBlocks.RuntimeFixtures.UnknownResolver`.

  The stock `build_invoke/1` fixture (`src: nil`, `content: nil`) is used
  unmodified - the non-binary-`src` totality rule is exactly what makes
  planning against it deterministic and pure, with no resolver called at
  all. `observed_effects/1` is not overridden: the handler routes nothing
  to `perform/2`, and check 2 (idempotency) asserts precisely that instead
  of flunking for a missing observation point. A later reader should not
  "fix" either absence.
  """

  use ExUnit.Case, async: false

  # Sabotage: had the non-binary-src refusal branch in
  # StatifierBlocks.Runtime.Subchart embed a fresh System.unique_integer/0
  # in its `detail` map -> the generated "start/2 is deterministic" check
  # went red comparing two non-identical refusals (verified).
  use Statifier.Testing.HandlerCase,
    handler: StatifierBlocks.RuntimeFixtures.UnknownResolver,
    type: "statifier_blocks:subchart"
end
