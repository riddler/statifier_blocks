defmodule StatifierBlocks.Compiler.DeclaredRootsTest do
  @moduledoc """
  The declaration mechanism ADR-0004's foreach amendment needs (F2, F3)
  and the refusal it carries (F6), tested on its own rather than only
  through `core.foreach`: it is a compiler seam any block type may use,
  and the properties that matter - determinism, provenance totality, and
  "no roots, no element" - are the compiler's rather than the loop's.

  What `core.foreach` in particular declares is
  `StatifierBlocks.Core.ForeachTest`'s.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, Document, Emission, Palette, Provenance}
  alias StatifierBlocks.Compiler.DeclaredRoots
  alias StatifierBlocks.Core.Emit

  defmodule Declaring do
    @moduledoc """
    `myapp.declaring`: a leaf step that declares the roots its config
    names, one per comma-separated name, so a test can build any nesting
    without going through `core.foreach`.
    """

    @behaviour StatifierBlocks.BlockType

    alias StatifierBlocks.Compiler.{Context, DeclaredRoots}
    alias StatifierBlocks.Core.Emit
    alias StatifierBlocks.Emission

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: [{"body", :any, "Steps"}]

    @impl true
    def config_schema(_config),
      do: [%{key: "roots", type: :string, label: "Declares", required?: false, default: ""}]

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def io(_config), do: %{kinds: [:step], slot_accepts: %{"body" => [:step]}}

    @impl true
    def emit(%StatifierBlocks.Block{config: config}, context) do
      done = Context.done_id(context)

      roots =
        config
        |> Map.get("roots", "")
        |> String.split(",", trim: true)
        |> Enum.map(&Emission.from_config(DeclaredRoots.declare(&1), "roots"))

      {initial, transitions, refs} =
        context |> Context.children("body") |> Emit.chain(done)

      {:ok,
       Emit.state(context.state_id, initial, roots ++ transitions ++ refs ++ [Emit.final(done)])}
    end
  end

  describe "declare/2 and hoist/1" do
    # sabotage: made `declare/2` always write an `expr` attribute -> a
    # root meant to read as undefined starts life as the empty string and
    # this goes red (verified)
    test "a root with no expr is written as a bare <data id>" do
      assert %Emission{name: "data", attributes: [{"id", "invitee"}]} =
               DeclaredRoots.declare("invitee")

      assert %Emission{attributes: [{"expr", "0"}, {"id", "i"}]} =
               DeclaredRoots.declare("i", "0")
    end

    # sabotage: sorted the roots by id before returning them -> the order
    # stops being the document's and decision 6's determinism argument
    # stops holding, which this catches (verified)
    test "lifts every <data> out of the tree, outermost first, in document order" do
      tree =
        Emit.state("s_a", nil, [
          DeclaredRoots.declare("outer_two"),
          DeclaredRoots.declare("outer_one"),
          Emit.state("s_b", nil, [DeclaredRoots.declare("inner")])
        ])

      assert {:ok, {stripped, roots}} = DeclaredRoots.hoist(tree)
      assert Enum.map(roots, &id/1) == ["outer_two", "outer_one", "inner"]

      # The stripped tree keeps everything else, in place.
      assert [%Emission{name: "state", children: []}] = stripped.children
    end

    # sabotage: emitted an empty `<datamodel/>` for a document declaring
    # nothing -> every chart this package ever compiled changes bytes, and
    # its chart identity with them, which this catches (verified)
    test "a tree declaring nothing produces no <datamodel> element at all" do
      tree = Emit.state("s_a", nil, [Emit.final("s_a__o_done")])

      assert {:ok, {^tree, []}} = DeclaredRoots.hoist(tree)
      assert DeclaredRoots.datamodel([]) == []

      assert [%Emission{name: "datamodel"}] =
               DeclaredRoots.datamodel([DeclaredRoots.declare("x")])
    end
  end

  describe "through the compiler" do
    # sabotage: dropped the roots from the `<scxml>` element's children ->
    # they are lifted out of the tree and land nowhere, the chart fails
    # upstream on an undefined variable, and this goes red (verified)
    test "the roots reach the chart's one top-level <datamodel>, in document order" do
      compiled = compile!(document("alpha,beta", "gamma"))

      assert compiled.scxml =~
               ~s(<datamodel><data id="alpha"/><data id="beta"/><data id="gamma"/></datamodel>)

      refute compiled.scxml =~ ~s(<state id="s_blk_OUT" initial="s_blk_IN"><data)
    end

    # sabotage: rebuilt the `<datamodel>`'s children rather than moving
    # them -> a byte in the top-level declarations belongs to no block and
    # decision 5's totality is gone, which this catches (verified)
    test "the wrapper belongs to the root block and each root keeps its own owner" do
      compiled = compile!(document("alpha", "gamma"))

      assert {:ok, wrapper} = owner_at(compiled, "<datamodel>")
      assert wrapper.block_id == "blk_OUT"

      assert {:ok, inner} = owner_at(compiled, ~s(<data id="gamma"/>))
      assert inner.block_id == "blk_IN"
      assert inner.config_key == "roots"
    end

    # sabotage: accepted a nested re-declaration instead of reporting it
    # -> the inner block silently overwrites the outer binding and this
    # goes red (verified)
    test "a nested re-declaration is refused as :duplicate_binding" do
      assert {:error, [finding]} = compile(document("alpha", "alpha"))

      assert finding.stage == :emit
      assert finding.code == :duplicate_binding
      assert finding.fault == :author
      assert finding.block_id == "blk_IN"
      assert finding.config_key == "roots"
    end
  end

  defp document(outer_roots, inner_roots) do
    inner = Block.new("myapp.declaring", id: "blk_IN", config: %{"roots" => inner_roots})

    Block.new("myapp.declaring",
      id: "blk_OUT",
      config: %{"roots" => outer_roots},
      slots: %{"body" => [inner]}
    )
  end

  defp palette,
    do: Palette.new(Map.merge(Palette.core_types(), %{"myapp.declaring" => Declaring}))

  defp compile(root), do: Compiler.compile(Document.new(root, id: "bdoc_ROOTS"), palette())

  defp compile!(root) do
    {:ok, compiled} = compile(root)
    compiled
  end

  defp id(%Emission{attributes: attributes}) do
    {"id", id} = List.keyfind(attributes, "id", 0)
    id
  end

  defp owner_at(compiled, needle) do
    {offset, _length} = :binary.match(compiled.scxml, needle)
    Provenance.owner_at(compiled.provenance, offset + 1)
  end
end
