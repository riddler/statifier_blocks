defmodule StatifierBlocks.ViewModel.DocumentValidatorTest do
  @moduledoc """
  ADR-0005 clauses `11p` to `11u`: a host's own whole-document rule rides the
  palette, is handed the document and only the document, says where and what,
  and the package stamps the source.

  Every case here is a pure view-model assertion - no LiveView module is
  named, so the file carries no `Code.ensure_loaded?/1` wrapper and compiles
  in the headless tree unchanged. What only exists once there is markup - the
  row in the drawer - is
  `StatifierBlocks.Editor.DocumentValidatorDrawerTest`'s.

  The palettes are built per test rather than shared, for the reason
  `StatifierBlocks.ViewModel.SingletonTest` builds one per test: what a
  validator says is a property of the palette it is in, and one suite-wide
  palette would make every assertion here about somebody else's rule.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Document, Finding, Palette, ViewModel}

  defmodule Root do
    @moduledoc "A one-slot root, so a document is a tree rather than a block."

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1

    @impl true
    def slots(_config), do: [{"steps", :many, "Steps"}]

    @impl true
    def config_schema(_config), do: []

    @impl true
    def validate_config(_config), do: :ok

    @impl true
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

    @impl true
    def palette_entry, do: %{label: "Flow"}
  end

  defmodule Step do
    @moduledoc "An ordinary step, and the type the rules below count."

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
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

    @impl true
    def palette_entry, do: %{label: "Step"}
  end

  defmodule OneStepOnly do
    @moduledoc "A rule about the whole tree: at most one step."

    @behaviour StatifierBlocks.DocumentValidator

    @impl true
    def validate_document(%Document{} = document) do
      steps = document |> Document.blocks() |> Enum.filter(&(&1.type == "test.step"))

      if length(steps) > 1 do
        [{{:block, document.root.id}, "this document holds more than one step"}]
      else
        []
      end
    end
  end

  defmodule NamesItsSeverity do
    @moduledoc "A rule that asks for a severity of its own."

    @behaviour StatifierBlocks.DocumentValidator

    @impl true
    def validate_document(%Document{} = document) do
      [{{:block, document.root.id}, "my gate refuses this document", severity: :error}]
    end
  end

  defmodule SaysSecond do
    @moduledoc "A second rule, for the order the palette fixes."

    @behaviour StatifierBlocks.DocumentValidator

    @impl true
    def validate_document(%Document{} = document),
      do: [{{:block, document.root.id}, "second"}]
  end

  defmodule SaysFirst do
    @moduledoc "The other one."

    @behaviour StatifierBlocks.DocumentValidator

    @impl true
    def validate_document(%Document{} = document),
      do: [{{:block, document.root.id}, "first"}]
  end

  defmodule ReturnsRubbish do
    @moduledoc "A rule whose return value is not a list of findings."

    @behaviour StatifierBlocks.DocumentValidator

    @impl true
    def validate_document(_document), do: :ok
  end

  defmodule ReturnsBadMembers do
    @moduledoc "A rule whose list holds members of shapes nothing declares."

    @behaviour StatifierBlocks.DocumentValidator

    @impl true
    def validate_document(%Document{} = document) do
      [
        "a bare string",
        {{:block, document.root.id}},
        {{:block, document.root.id}, :not_a_message},
        {{:nowhere, "blk"}, "an anchor with no such row"},
        {{:block, document.root.id}, "third element is not a keyword list", ["loud"]},
        {{:block, document.root.id}, "a severity nothing recognises", severity: :fatal},
        {{:block, document.root.id}, "the one good member"}
      ]
    end
  end

  defmodule Raises do
    @moduledoc "A rule with a bug in it."

    @behaviour StatifierBlocks.DocumentValidator

    @impl true
    def validate_document(_document), do: raise(ArgumentError, "the host's own bug")
  end

  defmodule Anchored do
    @moduledoc "A rule anchoring on a field and on a slot rather than a block."

    @behaviour StatifierBlocks.DocumentValidator

    @impl true
    def validate_document(%Document{} = document) do
      [
        {{:config, "blk_a", "duration"}, "about a field"},
        {{:slot, document.root.id, "steps"}, "about a slot"},
        {{:block, "blk_long_gone"}, "about a block this document does not hold"}
      ]
    end
  end

  defp types, do: %{"test.root" => Root, "test.step" => Step}

  defp document(step_ids) do
    Document.new(
      Block.new("test.root",
        id: "blk_root",
        slots: %{"steps" => Enum.map(step_ids, &Block.new("test.step", id: &1))}
      ),
      id: "doc_rules"
    )
  end

  defp messages(view_model, source) do
    view_model.findings
    |> Enum.filter(&(&1.source == source))
    |> Enum.map(& &1.message)
  end

  describe "a host's rule" do
    # Sabotage: `ViewModel.validator_findings/2` returning `[]` instead of
    # walking `palette.validators` - the finding never appears and this goes
    # red.
    test "its finding joins the view model's, stamped `:lint`" do
      palette = Palette.new(types(), validators: [OneStepOnly])
      view_model = ViewModel.build(document(["blk_a", "blk_b"]), palette, [])

      assert [%Finding{} = finding] = Enum.filter(view_model.findings, &(&1.source == :lint))
      assert finding.message == "this document holds more than one step"
      assert finding.anchor == {:block, "blk_root"}
    end

    # The default is `:warning`, not `Finding.new/4`'s `:error`: a host rule
    # cannot make a document not compile (`11r`).
    #
    # Sabotage: `document_rule_findings/2` passing `:error` as the validators'
    # default severity - the severity assertion goes red.
    test "defaults to :warning, and may name its own severity" do
      defaulted =
        ViewModel.build(
          document(["blk_a", "blk_b"]),
          Palette.new(types(), validators: [OneStepOnly]),
          []
        )

      named =
        ViewModel.build(
          document(["blk_a"]),
          Palette.new(types(), validators: [NamesItsSeverity]),
          []
        )

      assert [%Finding{severity: :warning}] =
               Enum.filter(defaulted.findings, &(&1.source == :lint))

      assert [%Finding{severity: :error}] = Enum.filter(named.findings, &(&1.source == :lint))
    end

    # Sabotage: `validator_findings/2` reducing over `MapSet.new(validators)` -
    # the order stops being the palette's and this goes red.
    test "runs every validator, in the palette's list order" do
      palette = Palette.new(types(), validators: [SaysFirst, SaysSecond])
      view_model = ViewModel.build(document(["blk_a"]), palette, [])

      assert messages(view_model, :lint) == ["first", "second"]
    end

    # Sabotage: `spec_finding/4` dropping its `anchor?/1` guard - the
    # `{:nowhere, ...}` member becomes a finding and the count goes to two.
    test "a return that is not a list, and a member that is not a spec, are no finding" do
      rubbish =
        ViewModel.build(
          document(["blk_a"]),
          Palette.new(types(), validators: [ReturnsRubbish]),
          []
        )

      bad =
        ViewModel.build(
          document(["blk_a"]),
          Palette.new(types(), validators: [ReturnsBadMembers]),
          []
        )

      assert messages(rubbish, :lint) == []

      assert messages(bad, :lint) == [
               "a severity nothing recognises",
               "the one good member"
             ]
    end

    # `11r`: a host's code raising is that host's bug, and swallowing it would
    # hide it at the only moment it is visible.
    #
    # Sabotage: wrapping `module.validate_document/1` in a `try/rescue` that
    # returns `[]` - nothing raises and this goes red.
    test "an exception inside it is not caught" do
      palette = Palette.new(types(), validators: [Raises])

      assert_raise ArgumentError, "the host's own bug", fn ->
        ViewModel.build(document(["blk_a"]), palette, [])
      end
    end

    # `11s`: the anchor enum keeps its three members, and an anchor naming an
    # id the document does not hold lands in `orphan_findings` through the
    # existing split rather than through a refusal of its own.
    #
    # Sabotage: `anchor?/1` answering `true` only for `{:block, id}` - the
    # config and slot rows vanish and this goes red.
    test "may anchor on any of decision 11's three rows, orphans included" do
      palette = Palette.new(types(), validators: [Anchored])
      view_model = ViewModel.build(document(["blk_a"]), palette, [])

      assert messages(view_model, :lint) == [
               "about a field",
               "about a slot",
               "about a block this document does not hold"
             ]

      assert [%Finding{message: "about a block this document does not hold"}] =
               view_model.orphan_findings
    end
  end

  describe "a document with no host callback" do
    # The property clause `11p` names: a palette that declares nothing pays
    # nothing.
    #
    # Sabotage: `Palette.new/2` defaulting `:validators` to `[Anchored]` - the
    # two view models stop matching and this goes red.
    test "validates exactly as it did before validators existed" do
      document = document(["blk_a", "blk_b"])

      assert ViewModel.build(document, Palette.new(types()), []) ==
               ViewModel.build(document, Palette.new(types(), validators: []), [])

      assert ViewModel.build(document, Palette.new(types()), []).findings == []
    end
  end

  describe "the package's own singleton rule" do
    # `11t`: the declared rule and the written one are one mechanism, and the
    # source stamp is the difference - `:config` says a declared shape is not
    # satisfied, `:lint` says the editor applied a rule. Both are emitted,
    # unreconciled, even where they contradict each other.
    #
    # Sabotage: `document_rule_findings/2` stamping the singleton specs
    # `:lint` too - the two lists stop being separable and this goes red.
    test "runs on the same path, keeps `:config`, and does not suppress a host's rule" do
      types = %{"test.root" => Root, "test.step" => singleton_step()}
      palette = Palette.new(types, validators: [OneStepOnly])
      view_model = ViewModel.build(document(["blk_a", "blk_b"]), palette, [])

      assert messages(view_model, :config) == [
               "this document holds 2 Step blocks, and may hold exactly one"
             ]

      assert messages(view_model, :lint) == ["this document holds more than one step"]
    end

    # `11t` fixes the order: the derived per-block sources, then the document
    # rules with the declared one first, then the `findings` argument.
    #
    # Sabotage: `derived_findings/3` appending `document_rule_findings/2`
    # before `per_block` - the order assertion goes red.
    test "runs first among the document rules, and both run before caller findings" do
      types = %{"test.root" => Root, "test.step" => singleton_step()}
      palette = Palette.new(types, validators: [OneStepOnly])
      supplied = Finding.new({:block, "blk_root"}, :compile, "the caller's own")

      view_model = ViewModel.build(document(["blk_a", "blk_b"]), palette, [supplied])

      assert Enum.map(view_model.findings, & &1.source) == [:config, :lint, :compile]
    end
  end

  defmodule SingletonStep do
    @moduledoc "A step a palette says a document may hold exactly one of."

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
    def emit(%Block{id: id}, _context), do: {:ok, {:emitted, id}}

    @impl true
    def palette_entry, do: %{label: "Step", singleton: :anywhere}
  end

  defp singleton_step, do: SingletonStep
end
