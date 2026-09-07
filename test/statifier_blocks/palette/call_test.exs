defmodule StatifierBlocks.Palette.CallTest do
  @moduledoc """
  `StatifierBlocks.Palette.call/4` and `declares?/3`: the one call seam, and
  the `{module, state}` entry it exists to hide (ADR-0002's 2026-09-07
  amendment, filed with `sb-5b7j`).

  Three things belong to the seam and to nothing else, and each has a test
  here: the **arity arithmetic** (a stateful module exports a callback at one
  higher arity), the **absent-callback default** (which is why it takes four
  arguments and not three), and the **state prepending** (the whole of what a
  caller must not know).

  The fourth is the `ordered_entry/1` hazard, which is the one site where
  forgetting the seam would fail *silently* rather than loudly.

  A pure test. Nothing here names LiveView, so it compiles and runs headless.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Palette}

  defmodule Bare do
    @moduledoc "An ordinary block type: callbacks at the declared arities."

    use StatifierBlocks.BlockType

    @impl true
    def current_version, do: 3
    @impl true
    def config_schema(_config), do: [%{key: "k", type: :string, label: "K", default: ""}]
    @impl true
    def palette_entry, do: %{label: "Bare", group: "Structure", order: 7}
    @impl true
    def sentence(config), do: "bare #{Map.get(config, "k", "")}"
    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule Stateful do
    @moduledoc """
    A host's own stateful type: the same callbacks, each at one higher arity,
    with the state first. It does not `@behaviour StatifierBlocks.BlockType` -
    the behaviour's arities are the declared ones and this module's are not.
    """

    def current_version(state), do: state.version
    def config_schema(state, _config), do: state.schema
    def palette_entry(state), do: state.entry
    def sentence(state, config), do: "#{state.prefix} #{Map.get(config, "k", "")}"
    def emit(_state, %Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule Raises do
    @moduledoc "A stateful entry whose callback raises when it is reached."

    def sentence(_state, _config), do: raise("reached")
  end

  @state %{
    version: 5,
    prefix: "stateful",
    schema: [%{key: "k", type: :string, label: "K", default: ""}],
    entry: %{label: "Stateful", group: "Structure", order: 9}
  }

  defp ref, do: {Stateful, @state}

  describe "call/4 prepends the state and does the arity arithmetic" do
    # Sabotage: called `apply(module, callback, args)` for a pair too - red
    # with an UndefinedFunctionError, because the stateful module exports
    # nothing at the declared arity.
    test "a stateful entry is called at one higher arity, state first" do
      assert Palette.call(ref(), :current_version, [], :absent) == 5
      assert Palette.call(ref(), :sentence, [%{"k" => "x"}], :absent) == "stateful x"
    end

    # Sabotage: prepended the state for a bare module as well - red. A bare
    # entry is called exactly as it was before the seam existed, which is
    # what makes a plain-module palette byte-identical in behaviour.
    test "a bare entry is called at the declared arity, unchanged" do
      assert Palette.call(Bare, :current_version, [], :absent) == 3
      assert Palette.call(Bare, :sentence, [%{"k" => "x"}], :absent) == "bare x"
    end

    # Sabotage: asked `function_exported?/3` at the declared arity for a pair
    # - red. Asking about the wrong arity answers "not declared" SILENTLY and
    # degrades a stateful type into the absent-callback path, which looks
    # exactly like a type that declared nothing.
    test "the absent-callback default, on both kinds of entry" do
      assert Palette.call(Bare, :summary, [%{}], :absent) == :absent
      assert Palette.call(ref(), :summary, [%{}], :absent) == :absent
      assert Palette.call(ref(), :slots, [%{}], []) == []
    end

    # Sabotage: dropped the `Code.ensure_loaded?/1` half - red under a module
    # that was never compiled, which is exactly the case decision 3 says a
    # palette may name.
    test "a module that is not loadable takes the default" do
      assert Palette.call(NoSuchModuleAtAll, :current_version, [], :absent) == :absent
      assert Palette.call({NoSuchModuleAtAll, %{}}, :current_version, [], :absent) == :absent
      assert Palette.call(nil, :current_version, [], :absent) == :absent
    end
  end

  describe "declares?/3 answers declaredness without calling" do
    # Sabotage: made `declares?/3` take the exported arity rather than the
    # declared one - red on the pair. A caller never writes `arity + 1`; that
    # arithmetic is the seam's, in both functions.
    test "the arity it takes is the declared one, on both kinds of entry" do
      assert Palette.declares?(Bare, :sentence, 1)
      assert Palette.declares?(ref(), :sentence, 1)

      refute Palette.declares?(Bare, :summary, 1)
      refute Palette.declares?(ref(), :summary, 1)

      refute Palette.declares?(ref(), :sentence, 2)
    end

    # Sabotage: implemented `declares?/3` by calling and comparing to the
    # default - red, because the call would raise here rather than answering
    # the question, and a callback that legitimately answers the default
    # would read as absent and a presentation branch take the wrong arm.
    test "it does not call the callback" do
      assert Palette.declares?({Raises, %{}}, :sentence, 1)

      assert_raise RuntimeError, fn -> Palette.call({Raises, %{}}, :sentence, [%{}], :absent) end
    end
  end

  describe "fetch/2 answers the entry as stored" do
    # Sabotage: normalized a bare module into `{module, nil}` - red. That is
    # what would break every host matching `{:ok, module}` today, for the
    # benefit of a case most palettes do not have.
    test "neither normalizing a module nor unwrapping a pair" do
      palette = Palette.from_modules([{"a.bare", Bare}, {"a.stateful", ref()}])

      assert Palette.fetch(palette, "a.bare") == {:ok, Bare}
      assert Palette.fetch(palette, "a.stateful") == {:ok, ref()}
      assert Palette.fetch(palette, "a.missing") == {:error, {:unknown_block_type, "a.missing"}}
    end

    # Sabotage: read `module.current_version()` directly in `new_block/2` and
    # `resolve/2` - red with an UndefinedFunctionError on the pair.
    test "new_block/2 and resolve/2 read a stateful entry through the seam" do
      palette = Palette.from_modules([{"a.stateful", ref()}])

      assert {:ok, block} = Palette.new_block(palette, "a.stateful")
      assert block.type_version == 5
      assert block.config == %{"k" => ""}

      assert {:ok, entry, ^block} = Palette.resolve(palette, block)
      assert entry == ref()
    end
  end

  describe "the ordered_entry/1 hazard" do
    # Sabotage: restored `is_atom(module)` as `ordered_entry/1`'s opening
    # guard - red, and SILENTLY so without this test: a `{module, state}`
    # entry fails `is_atom/1`, takes the `_no_declared_order -> []` arm, and
    # drops out of the duplicate-order check and out of every ordering
    # question downstream of it. No raise, no warning.
    test "a stateful entry colliding with a bare one at the same order is refused" do
      colliding = %{@state | entry: %{label: "Stateful", group: "Structure", order: 7}}

      assert_raise ArgumentError, ~r/both declare order 7/, fn ->
        Palette.from_modules([{"a.bare", Bare}, {"a.stateful", {Stateful, colliding}}])
      end
    end

    # Sabotage: as above - red. The message names BOTH entries, because the
    # one a host would have to look for is the one it did not write.
    test "the refusal names both entries" do
      colliding = %{@state | entry: %{label: "Stateful", group: "Structure", order: 7}}

      raised =
        assert_raise ArgumentError, fn ->
          Palette.from_modules([{"a.bare", Bare}, {"a.stateful", {Stateful, colliding}}])
        end

      message = raised.message

      assert message =~ ~s("a.bare")
      assert message =~ ~s("a.stateful")
    end

    # Sabotage: dropped the second `register/2` clause - red with the
    # malformed-registration raise, which is how a host would meet the
    # widening if `from_modules/2` had not taken it.
    test "a stateful entry with no collision registers, and orders" do
      palette = Palette.from_modules([{"a.bare", Bare}, {"a.stateful", ref()}])

      assert map_size(palette.types) == 2
    end

    # Sabotage: accepted any two-tuple as a registration - red. A pair whose
    # first element is not a module is still a mount-time programmer error
    # with no sensible degraded reading.
    test "a registration that is neither shape is still refused" do
      assert_raise ArgumentError, ~r/registration/, fn ->
        Palette.from_modules([{"a.bad", {"not a module", %{}}}])
      end
    end
  end
end
