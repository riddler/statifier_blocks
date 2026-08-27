defmodule StatifierBlocks.BlockTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.Block

  # sabotage: change the type_version default from 1 to 0 -> red
  test "new/2 defaults type_version to 1, config to %{}, slots to %{}" do
    block = Block.new("core.wait")

    assert block.type == "core.wait"
    assert block.type_version == 1
    assert block.config == %{}
    assert block.slots == %{}
    assert "blk_" <> _rest = block.id
  end

  # sabotage: replace `Keyword.get_lazy(opts, :id, &StatifierBlocks.Id.block/0)`
  # with `StatifierBlocks.Id.block()` (ignores the :id option) -> red
  test "new/2 accepts an explicit :id and overrides every default" do
    block =
      Block.new("myapp.enrich",
        id: "blk_explicit",
        type_version: 2,
        config: %{"a" => 1},
        slots: %{"body" => []}
      )

    assert block.id == "blk_explicit"
    assert block.type_version == 2
    assert block.config == %{"a" => 1}
    assert block.slots == %{"body" => []}
  end

  # sabotage: default :id to the fixed literal "blk_fixed" instead of
  # `&StatifierBlocks.Id.block/0` -> red
  test "new/2 mints a fresh id per call when :id is not given" do
    refute Block.new("core.wait").id == Block.new("core.wait").id
  end
end
