defmodule StatifierBlocks.DocumentFixtures do
  @moduledoc """
  Shared test fixtures: the family's two worked examples, each built two
  ways so the encoder and the decoder can be checked against the same
  canonical bytes independently.

  The two domains are the family's canonical pair (the umbrella's
  `docs/terminology-firewall.md`, "Example domains"), and between them they
  exercise the whole `core.*` vocabulary:

  | Fixture | Domain | Core types it reaches |
  |---|---|---|
  | `worked_example/0` | credit-card authorization and capture | `core.sequence`, `core.resumable_group`, `core.branch`, `core.parallel`, `core.wait` |
  | `signup_wizard/0` | a signup wizard with A/B testing | `core.sequence`, `core.group`, `core.branch`, `core.on_event` |

  `worked_example/0` is the one ADR-0001 spells out; `signup_wizard/0` is
  the second full example, and it carries the two core types the first one
  does not reach - the plain `core.group` and the shipped `core.on_event`,
  where the first example's interrupt handler is a host type.

  Both build in memory with explicit ids and deliberately reverse/mixed
  insertion order in every `slots`/`config` map, so a test asserting byte
  equality against the stored JSON would fail if the encoder ever leaned on
  map iteration order instead of sorting.
  """

  alias StatifierBlocks.{Block, Document}

  @fixture_path Path.join([__DIR__, "..", "fixtures", "documents", "worked_example.json"])
  @wizard_path Path.join([__DIR__, "..", "fixtures", "documents", "signup_wizard.json"])

  @doc "The ADR-0001 worked example, built with `Block.new/2`/`Document.new/2`."
  @spec worked_example() :: Document.t()
  def worked_example do
    capture =
      Block.new("myapp.capture",
        id: "blk_CAP",
        config: %{"invoke_type" => "myapp:capture"}
      )

    wait =
      Block.new("core.wait",
        id: "blk_WAI",
        config: %{"duration" => "PT48H"}
      )

    notify_receipt =
      Block.new("myapp.notify",
        id: "blk_NOT",
        config: %{"invoke_type" => "myapp:notify"}
      )

    notify_otherwise =
      Block.new("myapp.notify",
        id: "blk_NO2",
        config: %{"invoke_type" => "myapp:notify"}
      )

    parallel =
      Block.new("core.parallel",
        id: "blk_PAR",
        # Reverse-sorted insertion order vs. the canonical
        # `lane_capture, lane_receipt` output.
        config: %{"lanes" => ["capture", "receipt"]},
        slots: %{
          "lane_receipt" => [wait, notify_receipt],
          "lane_capture" => [capture]
        }
      )

    branch =
      Block.new("core.branch",
        id: "blk_BR",
        config: %{
          "arms" => [%{"slot" => "arm_approved", "cond" => "budget_remaining > amount"}]
        },
        # Reverse-sorted vs. the canonical `arm_approved, otherwise` output.
        slots: %{
          "otherwise" => [notify_otherwise],
          "arm_approved" => [parallel]
        }
      )

    interrupt =
      Block.new("myapp.on_event",
        id: "blk_INT",
        config: %{"event" => "myapp.cancelled", "outcome" => "abandon"}
      )

    group =
      Block.new("core.resumable_group",
        id: "blk_GRP",
        config: %{"history" => "deep"},
        # Reverse-sorted vs. the canonical `body, interrupts` output.
        slots: %{
          "interrupts" => [interrupt],
          "body" => [branch]
        }
      )

    authorize =
      Block.new("myapp.authorize",
        id: "blk_AUTH",
        type_version: 2,
        # Reverse-sorted vs. the canonical `invoke_type, timeout` output.
        config: %{"timeout" => "PT30S", "invoke_type" => "myapp:authorize"}
      )

    root =
      Block.new("core.sequence",
        id: "blk_ROOT",
        slots: %{"body" => [authorize, group]}
      )

    Document.new(root,
      id: "bdoc_01JDOC",
      revision: 17,
      metadata: %{"name" => "Card authorization"}
    )
  end

  @doc "The worked example's canonical bytes, read from the fixture file."
  @spec worked_example_json() :: binary()
  def worked_example_json do
    @fixture_path
    |> File.read!()
    |> String.trim_trailing()
  end

  @doc """
  The second worked example: a signup wizard with A/B testing.

  A variant is assigned, the wizard's steps run inside a plain `core.group`
  that an abandonment event can interrupt, the branch picks the screen for
  the assigned bucket, and the conversion event is recorded on the way out.

  Deliberately reaches what `worked_example/0` does not: `core.group`
  rather than `core.resumable_group` (a wizard has nothing to resume - an
  abandoned signup starts over), and the shipped `core.on_event` rather
  than a host handler, so both sides of ADR-0003 decision 3's kind gate
  have a full example.
  """
  @spec signup_wizard() :: Document.t()
  def signup_wizard do
    variant_b =
      Block.new("myapp.signup_step",
        id: "blk_VB",
        # Reverse-sorted vs. the canonical `invoke_type, step` output.
        config: %{"step" => "checkout_b", "invoke_type" => "myapp:signup"}
      )

    control =
      Block.new("myapp.signup_step",
        id: "blk_VA",
        config: %{"step" => "checkout_a", "invoke_type" => "myapp:signup"}
      )

    branch =
      Block.new("core.branch",
        id: "blk_WBR",
        config: %{
          "arms" => [%{"slot" => "arm_variant_b", "cond" => "variant == 'b'"}]
        },
        # Reverse-sorted vs. the canonical `arm_variant_b, otherwise` output.
        slots: %{
          "otherwise" => [control],
          "arm_variant_b" => [variant_b]
        }
      )

    conversion =
      Block.new("myapp.conversion",
        id: "blk_CNV",
        config: %{"event" => "signup.completed", "invoke_type" => "myapp:conversion"}
      )

    abandoned =
      Block.new("core.on_event",
        id: "blk_WINT",
        config: %{"outcome" => "abandon", "event" => "signup.abandoned"}
      )

    group =
      Block.new("core.group",
        id: "blk_WGRP",
        # Reverse-sorted vs. the canonical `body, interrupts` output.
        slots: %{
          "interrupts" => [abandoned],
          "body" => [branch, conversion]
        }
      )

    assign =
      Block.new("myapp.assign_variant",
        id: "blk_VAR",
        config: %{"invoke_type" => "myapp:assign_variant"}
      )

    root =
      Block.new("core.sequence",
        id: "blk_WROOT",
        slots: %{"body" => [assign, group]}
      )

    Document.new(root,
      id: "bdoc_01JWIZ",
      revision: 4,
      metadata: %{"name" => "Signup wizard"}
    )
  end

  @doc "The signup wizard's canonical bytes, read from the fixture file."
  @spec signup_wizard_json() :: binary()
  def signup_wizard_json do
    @wizard_path
    |> File.read!()
    |> String.trim_trailing()
  end
end
