defmodule StatifierBlocks.EditPropertyTest do
  @moduledoc """
  The bead's headline acceptance criterion (ADR-0005 decision 3):
  apply-then-inverse is the identity, over **generated command sequences**
  rather than a handful of hand-picked examples.

  `StatifierBlocks.DocumentGenerator.commands/3` builds a document and a
  sequence of commands against it from one `{@seed, index}` pair, mixing in
  a deliberate minority of refusable commands (see its moduledoc). For each
  generated document this test folds the whole sequence through
  `Edit.apply/2`, and at every successful step immediately applies the
  inverse `apply/2` handed back and asserts that returns the document the
  step started from - by struct equality, not merely equal canonical bytes.
  A refused command leaves the document untouched and contributes no
  inverse. Finally, unwinding every collected inverse - most recent first,
  which is exactly the order they were prepended in - is asserted to
  reproduce the document the whole sequence started from.

  On failure the seed and the generated index print, and re-running
  `DocumentGenerator.commands(@seed, index, @commands_per_document)` with
  that one integer regenerates the exact failing case.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{DocumentGenerator, Edit}

  # Fixed, never seeded from the clock - see the moduledoc.
  @seed 909_090
  @sample_size 60
  @commands_per_document 12

  # Sabotage: in `Edit.apply/2`'s `:insert` clause, changed the inverse from
  # `{:remove, block.id}` to `{:remove, parent_id}` -> red across nearly
  # every generated sequence that contains an insert, because applying the
  # "inverse" then removed the wrong block (usually raising, since the
  # parent it names is often still occupied by other children) instead of
  # restoring the document the insert started from.
  test "apply-then-inverse is the identity over generated command sequences" do
    for index <- 1..@sample_size do
      {document, commands} = DocumentGenerator.commands(@seed, index, @commands_per_document)

      {final_document, inverses} =
        Enum.reduce(commands, {document, []}, fn command, {current, acc} ->
          case Edit.apply(current, command) do
            {:ok, updated, inverse} ->
              assert {:ok, ^current, _rewound_inverse} = Edit.apply(updated, inverse),
                     "seed=#{@seed} index=#{index}: applying the inverse of " <>
                       "#{inspect(command)} did not return the document that step started from"

              {updated, [inverse | acc]}

            {:error, _reason} ->
              # A refused command changes nothing and contributes no inverse:
              # `current` is threaded through unchanged, and `acc` is not
              # extended.
              {current, acc}
          end
        end)

      # `inverses` was built by prepending, so its head is the most recently
      # applied command's inverse - applying the list in this order *is*
      # unwinding the whole sequence in reverse.
      rewound =
        Enum.reduce(inverses, final_document, fn inverse, doc ->
          {:ok, next, _forward_again} = Edit.apply(doc, inverse)
          next
        end)

      assert rewound == document,
             "seed=#{@seed} index=#{index}: unwinding the collected inverses did not " <>
               "reproduce the document the sequence started from"
    end
  end
end
