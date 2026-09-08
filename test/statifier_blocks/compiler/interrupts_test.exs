defmodule StatifierBlocks.Compiler.InterruptsTest do
  @moduledoc """
  ADR-0010 decision 8, "the rail scopes the pair": at emit, every `<raise>`
  of the interrupt pair inside a group's rail subtree becomes that group's
  salted event, the group's two transitions match only the salted names,
  and a raise outside any rail is untouched.

  The nesting test below is the record's worked example, driven through a
  real `Statifier` machine rather than asserted against bytes: the defect
  is about which of two same-named transitions an engine selects, and only
  the engine can answer that. Measured on `origin/main` at `6fb88fe`, the
  outer resume left the run at `s_blk_G1__waiting` - the inner group had
  taken it and restarted its own body, and the outer group's history
  re-entry never fired. Here it leaves the run at `s_blk_G2__waiting`,
  which is what the outer group's deep history remembers.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, ByteCorpus, Compiler, CoreFixtures, Document, Emission, Palette}
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.Emit

  @outer "s_blk_AUTH"
  @inner "s_blk_GUARD"

  defmodule BodyStep do
    @moduledoc """
    A host `:step` that raises the interrupt pair from a group's **body**.

    Nothing shipped can do this - `core.on_event` is tagged
    `:interrupt_handler` and only an `interrupts` slot admits that kind - so
    a host type is the only way to put a bare raise somewhere that is not a
    rail while a rail is right there above it. That is the position 8c is
    about, and this type is what lets a test stand in it.
    """

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config), do: []

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def io(_config), do: %{kinds: [:step]}

    @impl true
    def emit(_block, context) do
      done = Context.done_id(context)

      {:ok,
       Emit.state(context.state_id, done, [
         Emission.element("onentry", [], [
           Emission.element("raise", [{"event", Emit.interrupt_events().abandon}])
         ]),
         Emit.final(done)
       ])}
    end
  end

  # The record's worked example. "Authorize with a deadline" is a
  # resumable group whose rail resumes it; a guarded step with a rail of
  # its own sits inside its body and is active when the deadline fires.
  # The outer history is `deep` so that resuming the outer group is
  # observably different from restarting the inner one.
  defp nested_document do
    Document.new(
      Block.new("core.resumable_group",
        id: "blk_AUTH",
        config: %{"history" => "deep"},
        slots: %{
          "body" => [
            Block.new("core.await", id: "blk_STEP1", config: %{"event" => "card.authorized"}),
            Block.new("core.group",
              id: "blk_GUARD",
              slots: %{
                "body" => [
                  Block.new("core.await", id: "blk_G1", config: %{"event" => "signup.answered"}),
                  Block.new("core.await", id: "blk_G2", config: %{"event" => "signup.confirmed"})
                ],
                "interrupts" => [
                  Block.new("core.on_event",
                    id: "blk_GH",
                    config: %{"event" => "signup.paused", "outcome" => "resume"}
                  )
                ]
              }
            )
          ],
          "interrupts" => [
            Block.new("core.on_event",
              id: "blk_AH",
              config: %{"event" => "card.deadline", "outcome" => "resume"}
            )
          ]
        }
      ),
      id: "bdoc_NEST"
    )
  end

  defp scxml(document, palette \\ Palette.core(), opts \\ []) do
    assert {:ok, compiled} = Compiler.compile(document, palette, opts)
    compiled.scxml
  end

  # The run, up to the point the record describes: the first step is past,
  # the inner guarded step is on its *second* step, and both rails are
  # armed.
  defp armed_run do
    {:ok, machine} = Statifier.compile(scxml(nested_document()))
    {machine_state, _effects} = Statifier.initialize(machine)

    {:ok, machine_state, _} = Statifier.send_event(machine_state, "card.authorized")
    {:ok, machine_state, _} = Statifier.send_event(machine_state, "signup.answered")

    machine_state
  end

  defp leaves(machine_state), do: Statifier.active_leaf_states(machine_state)

  describe "the salted pair (8b)" do
    # sabotage: wire the group's two transitions on the bare pair again
    # -> this goes red, and so does the outer-resume run below (verified)
    test "a group's two transitions match only its own salted names" do
      chart = scxml(nested_document())

      for state <- [@outer, @inner], half <- [:abandon, :resume] do
        salted = Map.fetch!(Emit.interrupt_events(state), half)
        assert chart =~ ~s(<transition event="#{salted}"), "#{state}/#{half}"
      end
    end

    # Consent clause 13, and 8f: a rail matching both names would re-open
    # the capture the decision closes.
    #
    # sabotage: wire the group's two transitions on the bare pair again
    # -> the bare names are back on a rail and this goes red (verified)
    test "no rail keeps an alias of the bare pair" do
      chart = scxml(nested_document())
      %{abandon: abandon, resume: resume} = Emit.interrupt_events()

      for bare <- [abandon, resume] do
        refute chart =~ ~s(<transition event="#{bare}"), bare
      end
    end

    # sabotage: never run the salt pass, so the transitions are salted
    # and the raises are left bare -> this goes red (verified)
    test "each handler's raise carries its own group's salt" do
      chart = scxml(nested_document())

      assert chart =~ ~s(<raise event="#{Emit.interrupt_events(@outer).resume}"/>)
      assert chart =~ ~s(<raise event="#{Emit.interrupt_events(@inner).resume}"/>)
      refute chart =~ ~s(<raise event="#{Emit.interrupt_events().resume}"/>)
    end
  end

  describe "the record's worked example, run for real" do
    # sabotage: wire the group's two transitions on the bare pair again
    # -> both rails match the outer handler's raise, the inner one wins on
    # depth, and this goes red at `s_blk_G1__waiting` - which is exactly
    # what `origin/main` at 6fb88fe does (verified)
    test "the outer group's resume resumes the outer group" do
      {:ok, machine_state, _} = Statifier.send_event(armed_run(), "card.deadline")

      assert "s_blk_G2__waiting" in leaves(machine_state),
             "the outer group's deep history did not re-enter where the body left off"

      refute "s_blk_G1__waiting" in leaves(machine_state),
             "the inner group restarted, which is the capture decision 8 closes"
    end

    # The other half of "each resumes its own group": the inner rail still
    # works exactly as it did, and takes only its own resume.
    #
    # sabotage: salt every group with one constant rather than with its
    # own state id -> the inner resume is taken by the outer rail too and
    # this goes red (verified)
    test "the inner group's resume restarts the inner group only" do
      {:ok, machine_state, _} = Statifier.send_event(armed_run(), "signup.paused")

      assert "s_blk_G1__waiting" in leaves(machine_state)
      assert "s_blk_AH__armed" in leaves(machine_state), "the outer rail was disarmed"
    end
  end

  describe "a host block type on a rail (8d)" do
    # `myapp.on_event` raises the bare pair `interrupt_events/0` names,
    # exactly as a host type is documented to. The rewrite is a property
    # of where it sits, not of which type emitted it.
    #
    # sabotage: salt every group with one constant rather than with its
    # own state id -> this goes red (verified)
    test "is scoped exactly as core.on_event is" do
      document =
        Document.new(
          Block.new("core.group",
            id: "blk_GUARD",
            slots: %{
              "body" => [
                Block.new("core.await", id: "blk_G1", config: %{"event" => "signup.answered"})
              ],
              "interrupts" => [
                Block.new("myapp.on_event",
                  id: "blk_HOST",
                  config: %{"event" => "signup.paused", "outcome" => "resume"}
                )
              ]
            }
          ),
          id: "bdoc_HOST"
        )

      chart = scxml(document, CoreFixtures.palette())

      assert chart =~ ~s(<raise event="#{Emit.interrupt_events(@inner).resume}"/>)
      refute chart =~ ~s(<raise event="#{Emit.interrupt_events().resume}"/>)
    end
  end

  describe "a raise outside any rail (8c)" do
    # sabotage: none - there is no rail in this document to salt from,
    # so this test is the control for the three above rather than a claim
    # of its own
    test "is emitted unchanged" do
      # A handler as the document's own root: a `core.on_event` is the
      # only shipped type that raises the pair, and `interrupts` is the
      # only slot that admits its kind, so a bare raise reaches the
      # compiled chart exactly one way - with no group above it at all.
      document =
        Document.new(
          Block.new("core.on_event",
            id: "blk_OE",
            config: %{"event" => "order.cancelled", "outcome" => "abandon"}
          ),
          id: "bdoc_BARE"
        )

      assert scxml(document) =~ ~s(<raise event="#{Emit.interrupt_events().abandon}"/>)
    end

    # The position the decision is actually about: a bare raise in the
    # *body* of a group whose rail is right there above it. Salting it
    # would make the body able to interrupt its own group, which is not
    # what it does today and not what decision 8 asks for.
    #
    # sabotage: count every child placeholder under a rail-bearing state
    # as a rail child rather than only the ones in its `<parallel>` -> the
    # body's raise is salted and this goes red (verified)
    test "is emitted unchanged from a group's body" do
      document =
        Document.new(
          Block.new("core.group",
            id: "blk_GUARD",
            slots: %{
              "body" => [Block.new("myapp.body_step", id: "blk_BODY")],
              "interrupts" => [
                Block.new("core.on_event",
                  id: "blk_GH",
                  config: %{"event" => "signup.paused", "outcome" => "resume"}
                )
              ]
            }
          ),
          id: "bdoc_BODY"
        )

      palette = Palette.new(Map.put(Palette.core_types(), "myapp.body_step", BodyStep))
      chart = scxml(document, palette)

      assert chart =~ ~s(<raise event="#{Emit.interrupt_events().abandon}"/>)
      refute chart =~ ~s(<raise event="#{Emit.interrupt_events(@inner).abandon}"/>)
    end

    # A group with an empty `interrupts` slot emits no rail at all
    # (`Emit.interruptible/2` degenerates to `ordered/2`), so there is
    # nothing to salt and nothing to match.
    #
    # sabotage: never run the salt pass -> unchanged here, which is the
    # point: a group with no handlers has nothing to salt either way
    test "a group with no handlers emits no interrupt event" do
      document =
        Document.new(
          Block.new("core.group",
            id: "blk_GROUP",
            slots: %{
              "body" => [
                Block.new("core.await", id: "blk_G1", config: %{"event" => "signup.answered"})
              ]
            }
          ),
          id: "bdoc_PLAIN"
        )

      refute scxml(document) =~ "statifier_blocks.interrupt"
    end
  end

  describe "a document with no interruptible group (8e)" do
    # The corpus goldens were captured at 0.21.0, long before this pass
    # existed (`StatifierBlocks.Compiler.ByteCorpusTest`), so asserting
    # them here is a real before-and-after rather than a restatement of
    # today's output. Three of the five entries hold no group, in three
    # compile modes each; the other two are re-baselined by this change
    # and are deliberately not in this list.
    #
    # sabotage: stop descending into a rail child's subtree when
    # rewriting -> these stay green (they hold no group) while the two
    # entries that do hold one go red, which is the asymmetry 8e claims
    # (verified)
    for name <- ["invoke_handled", "map_handled", "subchart_handled"],
        {mode, _opts} <- ByteCorpus.modes() do
      test "#{name} compiles byte-identically under #{mode}" do
        {_name, document, palette} =
          Enum.find(ByteCorpus.entries(), &(elem(&1, 0) == unquote(name)))

        {mode, opts} = Enum.find(ByteCorpus.modes(), &(elem(&1, 0) == unquote(mode)))

        assert Compiler.compile(document, palette, opts) |> elem(1) |> Map.fetch!(:scxml) ==
                 File.read!(ByteCorpus.golden_path(unquote(name), mode))
      end
    end
  end
end
