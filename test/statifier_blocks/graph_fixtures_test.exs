defmodule StatifierBlocks.GraphFixturesTest do
  @moduledoc """
  The worked example of ADR-0008's amendment of 2026-09-22, stored as
  documents under `test/fixtures/graph/` so a host can vendor them.

  A patron registration verifies the registering patron's email address
  through a `core.subchart` that routes on the child's `verified` and
  `expired` outcomes, then verifies every member of the household through a
  `core.map` whose `collect_type` marks `verified_address` required. Both
  name the one child document, `email_verification`, which is stored three
  ways: the published revision, a next revision that renames `verified` to
  `confirmed`, and a next revision that keeps `verified` but no longer
  reports `verified_address`.

  The child's root is a host block type, because no `core.*` type declares
  done-data: `library.verify_email` reads its outcomes and the keys it
  reports from its own config, so the three revisions differ only in their
  stored bytes. The resolver is an in-memory map.

  `StatifierBlocks.GraphTest` pins each rule of the check over inline
  documents; this file pins what those rules answer for these stored ones.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiled, Compiler, Document, Finding, Graph, Palette}
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.Emit

  defmodule VerifyEmail do
    @moduledoc """
    The root of the email verification child: its outcomes are the
    newline-separated `outcomes` config field, and its done-data is one
    string key per `reports` member.
    """

    use StatifierBlocks.BlockType

    @impl true
    def outcomes(%{"outcomes" => outcomes}) do
      outcomes
      |> String.split("\n", trim: true)
      |> Enum.map(&{&1, String.capitalize(&1)})
    end

    @impl true
    def donedata_type(%{"reports" => reports}) do
      for %{"name" => name} <- reports,
          do: %{name: name, path: "verification." <> name, type: :string}
    end

    @impl true
    def emit(%Block{config: config}, context) do
      finals =
        Enum.map(outcomes(config), fn {name, _label} ->
          {:ok, id} = Context.outcome_id(context, name)
          id
        end)

      {:ok, Emit.state(context.state_id, hd(finals), Enum.map(finals, &Emit.final/1))}
    end
  end

  @dir Path.join([__DIR__, "..", "fixtures", "graph"])

  @parent "patron_registration-parent.json"
  @child "email_verification-child.json"
  @child_next "email_verification-child_next.json"
  @child_next_no_key "email_verification-child_next_no_key.json"

  describe "the stored documents" do
    # Each one decodes, validates and re-encodes to its stored bytes, so
    # the files are canonical and a vendored copy compares byte for byte.
    #
    # sabotage: swapped the child fixture's `id` and `metadata` keys - it
    # still decodes but no longer re-encodes to its bytes, and this goes red
    # (verified)
    test "each fixture is a valid, canonically encoded document" do
      for name <- [@parent, @child, @child_next, @child_next_no_key] do
        bytes = File.read!(Path.join(@dir, name))
        assert {:ok, %Document{} = document} = Document.from_json(bytes), name
        assert Document.validate(document) == :ok, name
        assert Document.to_json(document) <> "\n" == bytes, name
      end
    end

    # The two next revisions are revisions of the published child: the same
    # document id, a later revision.
    #
    # sabotage: set the renaming revision's stored `revision` to 1 - it is
    # no longer one on from the published child and this goes red (verified)
    test "the next revisions are the same child document, one revision on" do
      child = document!(@child)

      for name <- [@child_next, @child_next_no_key] do
        next = document!(name)
        assert next.id == child.id, name
        assert next.revision == child.revision + 1, name
      end
    end

    # sabotage: recorded the `core.map` reference with `reads: []` in
    # `reference/3` - the parent's interface loses `verified_address` and
    # this goes red (verified)
    test "each fixture compiles, and records the interface the check reads" do
      assert parent().interface == %{
               declared_outcomes: ["done"],
               declared_donedata_keys: [],
               references: [
                 %{
                   block_id: "blk_VERIFY",
                   document_id: "email_verification",
                   routes_on: ["verified", "expired"],
                   reads: []
                 },
                 %{
                   block_id: "blk_HOUSEHOLD",
                   document_id: "email_verification",
                   routes_on: [],
                   reads: ["verified_address"]
                 }
               ]
             }

      assert %{
               declared_outcomes: ["verified", "expired"],
               declared_donedata_keys: ["verified_address"],
               references: []
             } = child(@child).interface

      assert %{declared_outcomes: ["confirmed", "expired"]} = child(@child_next).interface

      assert %{declared_outcomes: ["verified", "expired"], declared_donedata_keys: []} =
               child(@child_next_no_key).interface
    end
  end

  describe "the published child" do
    # sabotage: inverted `pair/3`'s outcome filter to `outcome in
    # child.declared_outcomes` - both routed outcomes are refused and this
    # goes red (verified)
    test "the parent against it is green in both directions" do
      assert Graph.check(parent(), resolver(child(@child))) == []
      assert Graph.consumers_broken(child(@child), [parent()]) == []
    end
  end

  describe "the next revision that renames verified to confirmed" do
    # sabotage: made `pair/3`'s outcome comprehension iterate nothing - the
    # renamed outcome passes and this goes red (verified)
    test "check/2 refuses the parent, on the subchart that routes on verified" do
      assert [
               %Finding{
                 anchor: {:config, "blk_VERIFY", "outcomes"},
                 source: :graph,
                 severity: :error,
                 message: message
               }
             ] = Graph.check(parent(), resolver(child(@child_next)))

      assert message =~ ~s("email_verification")
      assert message =~ ~s("verified")
    end

    # sabotage: made `pair/3`'s outcome comprehension iterate nothing - the
    # parent is not named and this goes red (verified)
    test "consumers_broken/2 names the parent" do
      assert [
               {"patron_registration",
                %Finding{
                  anchor: {:config, "blk_VERIFY", "outcomes"},
                  source: :graph,
                  severity: :error,
                  message: message
                }}
             ] = Graph.consumers_broken(child(@child_next), [parent()])

      assert message =~ ~s("patron_registration")
      assert message =~ ~s("verified")
    end
  end

  describe "the next revision that no longer reports verified_address" do
    # sabotage: made `pair/3`'s key comprehension iterate nothing - the
    # dropped key passes and this goes red (verified)
    test "check/2 refuses the parent, on the map that reads it" do
      assert [
               %Finding{
                 anchor: {:config, "blk_HOUSEHOLD", "collect_type"},
                 source: :graph,
                 severity: :error,
                 message: message
               }
             ] = Graph.check(parent(), resolver(child(@child_next_no_key)))

      assert message =~ ~s("verified_address")
    end

    # sabotage: made `pair/3`'s key comprehension iterate nothing - the
    # parent is not named and this goes red (verified)
    test "consumers_broken/2 names the parent" do
      assert [
               {"patron_registration",
                %Finding{
                  anchor: {:config, "blk_HOUSEHOLD", "collect_type"},
                  message: message
                }}
             ] = Graph.consumers_broken(child(@child_next_no_key), [parent()])

      assert message =~ ~s("patron_registration")
      assert message =~ ~s("verified_address")
    end
  end

  # -- loading -------------------------------------------------------------

  defp parent, do: compile!(document!(@parent), [])
  defp child(name), do: compile!(document!(name), child_use: true)

  defp document!(name) do
    {:ok, document} = @dir |> Path.join(name) |> File.read!() |> Document.from_json()
    document
  end

  defp compile!(%Document{} = document, opts) do
    palette = Palette.new(Map.put(Palette.core_types(), "library.verify_email", VerifyEmail))

    case Compiler.compile(document, palette, opts) do
      {:ok, %Compiled{} = compiled} -> compiled
      {:error, findings} -> flunk("compile refused: #{inspect(findings, pretty: true)}")
    end
  end

  # The host's publish-time resolver over the one child it has published.
  defp resolver(%Compiled{} = published) do
    fn
      "email_verification" -> {:ok, published}
      _other -> {:error, :not_published}
    end
  end
end
