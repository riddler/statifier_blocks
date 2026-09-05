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
  alias StatifierBlocks.Predicates.TruthTable

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
            wait("blk_email_step", "1h"),
            variant_branch(),
            tracking()
          ]
        }
      ),
      id: "doc_signup_wizard"
    )
  end

  @doc """
  A one-step document whose only child is a `core.invoke`.

  Separate from the wizard rather than a fourth child of it: an invoke block
  in the shared document would shift every position the move and drag tests
  name, and what this one is for - the `invoke_type` field's control - needs
  no surroundings at all.
  """
  @spec invoke_step() :: Document.t()
  def invoke_step do
    Document.new(
      Block.new("core.sequence",
        id: "blk_flow",
        slots: %{
          "body" => [
            Block.new("core.invoke",
              id: "blk_authorize",
              config: %{"invoke_type" => "myapp:authorize"}
            )
          ]
        }
      ),
      id: "doc_invoke_step"
    )
  end

  @doc "A `core.wait` with a valid duration."
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
        "arm_variant_b" => [wait("blk_variant_b_pause", "30m")],
        "otherwise" => [wait("blk_control_pause", "2h")]
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
      slots: %{"after" => [wait("blk_settle_pause", "5m")]}
    )
  end

  @doc """
  A **credit-card processing** document: one branch, three ways out.

  The shell's fixture (`sb-832`), and a second domain on purpose. The signup
  wizard above is what the edit algebra is exercised against; what the drawer
  needs is a branch whose arms are worth tabulating - an amount threshold, a
  risk band, and the ordinary path in `otherwise` - because a truth table over
  it is one row per case and one column per arm, which is the shape the
  amendment moved into a full-width drawer.

  Ids are fixed, so a test and a screenshot name the same blocks.
  """
  @spec credit_card() :: Document.t()
  def credit_card do
    Document.new(
      Block.new("core.sequence",
        id: "blk_cc_flow",
        slots: %{
          "body" => [
            Block.new("core.branch",
              id: "blk_cc_decision",
              config: %{
                "arms" => [
                  %{"slot" => "arm_review", "cond" => "amount > 500"},
                  %{"slot" => "arm_declined", "cond" => "risk_band == 'high'"}
                ]
              },
              slots: %{
                "arm_review" => [wait("blk_cc_manual_hold", "24h")],
                "arm_declined" => [wait("blk_cc_decline_notice", "1m")],
                "otherwise" => [wait("blk_cc_settle_pause", "15m")]
              }
            ),
            wait("blk_cc_capture_pause", "5m")
          ]
        }
      ),
      id: "doc_credit_card"
    )
  end

  @doc """
  The truth tables a host would hand the drawer for `credit_card/0`.

  Keyed by block id, which is the whole of the `fixtures` seam: this package
  does not invent a fixture-bundle format (ADR-0002 decision 9 puts that
  convention in statifier-ui), so what crosses is tables already built.

  The rows are chosen so the drawer shows more than one status: a case that
  matches, a case whose declared expectation is contradicted, and a case whose
  bindings do not name everything the arms read.
  """
  @spec credit_card_tables() :: %{String.t() => [TruthTable.t()]}
  def credit_card_tables do
    {:ok, table} =
      TruthTable.build(
        %{
          name: "Authorization routing",
          description: "Which arm takes an authorization, by amount and risk band.",
          paths: ["amount", "risk_band"],
          columns: [
            %{key: "arm_review", label: "Review", source: "amount > 500"},
            %{key: "arm_declined", label: "Declined", source: "risk_band == 'high'"},
            %{key: "otherwise", label: "Capture", source: nil}
          ]
        },
        [
          %{
            name: "small, low risk",
            bindings: %{"amount" => "120", "risk_band" => "'low'"},
            expected: %{"arm_review" => false, "arm_declined" => false}
          },
          %{
            name: "large, low risk",
            bindings: %{"amount" => "900", "risk_band" => "'low'"},
            expected: %{"arm_review" => true}
          },
          %{
            name: "large, high risk",
            bindings: %{"amount" => "900", "risk_band" => "'high'"},
            note: "The first arm wins; the decline arm is never reached.",
            expected: %{"arm_declined" => true}
          },
          %{
            name: "band unbound",
            bindings: %{"amount" => "120"},
            expected: %{"arm_declined" => false}
          }
        ]
      )

    %{"blk_cc_decision" => [table]}
  end
end
