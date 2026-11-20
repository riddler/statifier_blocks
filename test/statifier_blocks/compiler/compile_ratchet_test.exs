defmodule StatifierBlocks.Compiler.CompileRatchetTest do
  @moduledoc """
  Upgrading moves no chart hash (ADR-0004's Amendment of 2026-11-20, `L8`):
  every document `StatifierBlocks.CompileRatchet` enumerates has no
  returnable step, and compiles, under every mode, to the SHA-256 of the
  bytes and the chart identity it compiled to at `v0.45.0`, pinned in
  `test/fixtures/compile_ratchet/v0.45.0.json`.

  The moving case is pinned beside it: the same signup wizard with its
  host step type declaring `returnable?/1` compiles to other bytes and
  another chart identity, the same ones every time.

  `StatifierBlocks.CompileRatchet`'s moduledoc says what the enumeration
  covers, what it leaves out and how the pins are re-derived.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, BlockType, Compiler, CompileRatchet, CoreFixtures}
  alias StatifierBlocks.{Document, Palette}

  # A host's signup step that declares every instance a returnable step,
  # otherwise the stub `StatifierBlocks.CoreFixtures.SignupStep` is.
  defmodule ReturnableSignupStep do
    @moduledoc false
    @behaviour StatifierBlocks.BlockType

    alias StatifierBlocks.CoreFixtures.SignupStep

    @impl true
    defdelegate current_version, to: SignupStep
    @impl true
    defdelegate slots(config), to: SignupStep
    @impl true
    defdelegate config_schema(config), to: SignupStep
    @impl true
    defdelegate validate_config(config), to: SignupStep
    @impl true
    defdelegate io(config), to: SignupStep
    @impl true
    defdelegate emit(block, context), to: SignupStep
    @impl true
    def returnable?(_config), do: true
  end

  @pins CompileRatchet.golden_path() |> File.read!() |> JSON.decode!()

  # sabotage: had `Trail`'s survey count every block a returnable step, so
  # a trail root, pushes and Back went into documents with none -> every
  # entry that compiles goes red here (verified)
  for {name, _document, _palette} <- CompileRatchet.entries(),
      {mode, _opts} <- CompileRatchet.modes() do
    test "#{name} compiles to its #{CompileRatchet.base()} bytes and chart identity under #{mode}" do
      {_name, document, palette} = entry(unquote(name))
      {_mode, opts} = Enum.find(CompileRatchet.modes(), &(elem(&1, 0) == unquote(mode)))

      assert CompileRatchet.pin(document, palette, opts) ==
               Map.fetch!(@pins, unquote(name <> "-" <> mode))
    end
  end

  # A pin nobody reaches proves nothing: the pinned names are exactly the
  # ones the enumeration compiles, in both directions.
  test "the pins and the enumeration name the same documents" do
    expected =
      for {name, _document, _palette} <- CompileRatchet.entries(),
          {mode, _opts} <- CompileRatchet.modes(),
          do: name <> "-" <> mode

    assert Enum.sort(Map.keys(@pins)) == Enum.sort(expected)
  end

  # The claim is about documents with no returnable step; this is what makes
  # every entry one.
  test "no enumerated document has a returnable step" do
    for {name, document, palette} <- CompileRatchet.entries(),
        %Block{type: type, config: config} <- Document.blocks(document) do
      {:ok, ref} = Palette.fetch(palette, type)
      refute BlockType.returnable?(ref, config), "#{name}: #{type} is a returnable step"
    end
  end

  describe "a host that declares its step type returnable" do
    # sabotage: had `BlockType.returnable?/2` answer `false` for every
    # type -> the wizard keeps its pinned bytes and the first refute goes
    # red (verified)
    test "moves the bytes and chart identity of a document using it, once" do
      {_name, document, palette} = entry("byte_corpus/signup_wizard")
      returnable = returnable_palette()

      for {mode, opts} <- CompileRatchet.modes() do
        pinned = Map.fetch!(@pins, "byte_corpus/signup_wizard-" <> mode)

        # The same palette without the declaration keeps the pin.
        assert CompileRatchet.pin(document, palette, opts) == pinned

        assert {:ok, moved} = Compiler.compile(document, returnable, opts)
        refute CompileRatchet.digest(moved.scxml) == pinned["sha256"]
        refute moved.record.chart_identity.content_hash == pinned["chart_identity"]
        assert moved.scxml =~ ~s(<data expr="[]" id="s_blk_WROOT__trail"/>)

        # Once: the moved bytes are the same on every compile.
        assert {:ok, again} = Compiler.compile(document, returnable, opts)
        assert again.scxml == moved.scxml
        assert again.record.chart_identity == moved.record.chart_identity
      end
    end
  end

  defp entry(name), do: Enum.find(CompileRatchet.entries(), &(elem(&1, 0) == name))

  defp returnable_palette do
    Palette.core_types()
    |> Map.merge(CoreFixtures.host_types())
    |> Map.put("myapp.signup_step", ReturnableSignupStep)
    |> Palette.new()
  end
end
