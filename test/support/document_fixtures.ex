defmodule StatifierBlocks.DocumentFixtures do
  @moduledoc """
  Shared test fixtures: the ADR-0001 worked example, built two ways so the
  encoder and (later) the decoder can each be checked against the same
  canonical bytes independently.

  `worked_example/0` builds the document in memory with explicit ids and
  deliberately reverse/mixed insertion order in every `slots`/`config` map,
  so a test asserting byte equality against `worked_example_json/0` would
  fail if the encoder ever leaned on map iteration order instead of sorting.
  """

  alias StatifierBlocks.{Block, Document}

  @fixture_path Path.join([__DIR__, "..", "fixtures", "documents", "worked_example.json"])

  @doc "The ADR-0001 worked example, built with `Block.new/2`/`Document.new/2`."
  @spec worked_example() :: Document.t()
  def worked_example do
    crm =
      Block.new("myapp.crm_push",
        id: "blk_CRM",
        config: %{"invoke_type" => "myapp:crm_push"}
      )

    wait =
      Block.new("core.wait",
        id: "blk_WAI",
        config: %{"duration" => "PT48H"}
      )

    notify_nurture =
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
        # `lane_crm, lane_nurture` output.
        config: %{"lanes" => ["crm", "nurture"]},
        slots: %{
          "lane_nurture" => [wait, notify_nurture],
          "lane_crm" => [crm]
        }
      )

    branch =
      Block.new("core.branch",
        id: "blk_BR",
        config: %{
          "arms" => [%{"slot" => "arm_qualified", "cond" => "score > 80"}]
        },
        # Reverse-sorted vs. the canonical `arm_qualified, otherwise` output.
        slots: %{
          "otherwise" => [notify_otherwise],
          "arm_qualified" => [parallel]
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

    enrich =
      Block.new("myapp.enrich",
        id: "blk_ENR",
        type_version: 2,
        # Reverse-sorted vs. the canonical `invoke_type, timeout` output.
        config: %{"timeout" => "PT30S", "invoke_type" => "myapp:enrich"}
      )

    root =
      Block.new("core.sequence",
        id: "blk_ROOT",
        slots: %{"body" => [enrich, group]}
      )

    Document.new(root,
      id: "bdoc_01JDOC",
      revision: 17,
      metadata: %{"name" => "Inbound qualification"}
    )
  end

  @doc "The worked example's canonical bytes, read from the fixture file."
  @spec worked_example_json() :: binary()
  def worked_example_json do
    @fixture_path
    |> File.read!()
    |> String.trim_trailing()
  end
end
