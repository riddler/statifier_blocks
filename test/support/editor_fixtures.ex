defmodule StatifierBlocks.EditorFixtures do
  @moduledoc """
  A document for the editor tests: a **signup wizard with A/B testing**.

  Deliberately not the ADR-0001 worked example. That one is the compiler's and
  the algebra's, and the editor needs three things it does not have:

    * two `core.wait` steps in one slot, so a `:move` within a slot has
      somewhere to go and index arithmetic is observable;
    * a `core.branch`, whose `config_schema/1` keys one `:expression` field per
      arm by the arm's own slot name while `validate_config/1` also emits
      findings keyed `"arms"` - the unrouted case ADR-0005 decision 11's
      fourth routing row exists for;
    * an **unresolvable** block with children of its own, which is decision
      12's whole subject and cannot be demonstrated with a palette that
      resolves everything.

  The document is not in the palette's vocabulary by accident:
  `"signup.track_conversion"` is a type this palette does not have, and that is
  the point of it.
  """

  alias StatifierBlocks.{Block, Document, Palette}

  @unknown_type "signup.track_conversion"

  @doc "The type name no palette here resolves. Decision 12's subject."
  @spec unknown_type() :: String.t()
  def unknown_type, do: @unknown_type

  @doc "The core vocabulary, and nothing else - so `#{@unknown_type}` does not resolve."
  @spec palette() :: Palette.t()
  def palette, do: Palette.core()

  @doc """
  The wizard: two steps, a variant branch, and one block whose type this
  palette does not have.

  Ids are fixed rather than minted so tests name positions directly.
  """
  @spec signup_wizard() :: Document.t()
  def signup_wizard do
    Document.new(
      Block.new("core.sequence",
        id: "blk_wizard",
        slots: %{
          "body" => [
            wait("blk_email_step", "PT1H"),
            variant_branch(),
            tracking()
          ]
        }
      ),
      id: "doc_signup_wizard"
    )
  end

  @doc "A `core.wait` with a valid ISO-8601 duration."
  @spec wait(Block.id(), String.t()) :: Block.t()
  def wait(id, duration) do
    Block.new("core.wait", id: id, config: %{"duration" => duration})
  end

  @doc """
  The A/B split: one arm for variant B, and the control in `otherwise`.

  `arm_variant_b` is `:at_least_one`, so it is a slot whose last child cannot
  be dragged out without producing a finding - which decision 5 permits on
  purpose, because a source-side check would make legal rearrangements
  impossible.
  """
  @spec variant_branch() :: Block.t()
  def variant_branch do
    Block.new("core.branch",
      id: "blk_variant",
      config: %{"arms" => [%{"slot" => "arm_variant_b", "cond" => "variant == 'b'"}]},
      slots: %{
        "arm_variant_b" => [wait("blk_variant_b_pause", "PT30M")],
        "otherwise" => [wait("blk_control_pause", "PT2H")]
      }
    )
  end

  @doc """
  The unresolvable block, with a child of its own.

  Its config is preserved byte for byte through any edit elsewhere in the
  tree, and its `after` slot is a raw slot name - there is no `slots/1` to
  give it a label, because there is no module.
  """
  @spec tracking() :: Block.t()
  def tracking do
    Block.new(@unknown_type,
      id: "blk_track_conversion",
      config: %{"event" => "signup.completed", "variant_key" => "ab_variant"},
      slots: %{"after" => [wait("blk_settle_pause", "PT5M")]}
    )
  end
end
