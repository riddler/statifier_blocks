defmodule StatifierBlocks.Compiler.MintedWriterSentenceTest do
  @moduledoc """
  ADR-0011's Note of 2026-09-08 (`RQ-SF038-24`, option 1), which `sb-bjt7`
  builds: a `:type_mismatch` whose disagreeing WRITER is a minted expansion
  member keeps the minted id in the tuple, and renders as the sentence of the
  composite block the author placed.

  The worked example is the signup domain's **"Guarded section"** - a step
  that records the applicant, and a `core.group` whose `body` the composite
  exposes as its own pass-through slot. Two cases, and the record's section 4
  is the reason they are two: a writer the author cannot see is resolved one
  level up, and a pass-through child - which has no entry in the expansion
  index at all - is named by its own id, because that is an id the author
  typed.

  The types here are never compiled: the walk is what reads them, the
  structure stage refuses before `emit`, and `emit/2` refuses if it is ever
  reached.

  A pure test. Nothing here names LiveView, so it compiles and runs headless.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, Document, Palette}
  alias StatifierBlocks.Compiler.Finding

  # -- the leaves --------------------------------------------------------

  defmodule SignupStep do
    @moduledoc "One write signature, at the record type its config names."

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config),
      do: [
        %{
          key: "assign_to",
          type: {:path, %{writes: "signup.applicant"}},
          label: "Record the applicant at",
          required?: true,
          default: ""
        }
      ]

    @impl true
    def validate_config(_config), do: :ok
    @impl true
    def io(_config), do: %{kinds: [:step]}
    @impl true
    def palette_entry, do: %{label: "Signup step"}
    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule Notify do
    @moduledoc "A leaf whose one field READS a path at `string`."

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config),
      do: [
        %{
          key: "to",
          type: {:path, %{expects: "string"}},
          label: "Notify",
          required?: true,
          default: ""
        }
      ]

    @impl true
    def validate_config(_config), do: :ok
    @impl true
    def io(_config), do: %{kinds: [:step]}
    @impl true
    def palette_entry, do: %{label: "Notify"}
    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule Marker do
    @moduledoc "A leaf that WRITES a `string` at the path its config names."

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config),
      do: [
        %{
          key: "at",
          type: {:path, %{writes: "string"}},
          label: "Mark",
          required?: true,
          default: ""
        }
      ]

    @impl true
    def validate_config(_config), do: :ok
    @impl true
    def io(_config), do: %{kinds: [:step]}
    @impl true
    def palette_entry, do: %{label: "Marker"}
    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule Deadline do
    @moduledoc "A leaf whose one field READS a path at `datetime`."

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config),
      do: [
        %{
          key: "when",
          type: {:path, %{expects: "datetime"}},
          label: "Due",
          required?: true,
          default: ""
        }
      ]

    @impl true
    def validate_config(_config), do: :ok
    @impl true
    def io(_config), do: %{kinds: [:step]}
    @impl true
    def palette_entry, do: %{label: "Deadline"}
    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  # -- the composites ----------------------------------------------------

  defmodule GuardedSection do
    @moduledoc """
    "Guarded section": the step the composite mints writes the applicant
    record, and the declared `body` slot maps into the group that follows it.
    It declares a `sentence/1`, which is the line the writer half renders.
    """

    use StatifierBlocks.Composite,
      name: "myapp.guarded_section",
      params: [
        %{
          key: "applicant_path",
          type: :string,
          label: "Record the applicant at",
          required?: true,
          default: "",
          datamodel_path?: true
        }
      ],
      slots: [%{name: "body", to: {"then", "body"}, label: "Then"}],
      sentence: "Guard the applicant at {applicant_path}",
      palette_entry: %{label: "Guarded section", group: "Structure"},
      version: 1

    alias StatifierBlocks.Block

    @impl StatifierBlocks.Composite
    def subtree(params) do
      [
        Block.new("myapp.signup_step",
          id: "call",
          config: %{"assign_to" => params["applicant_path"]}
        ),
        Block.new("core.group", id: "then", slots: %{"body" => []})
      ]
    end
  end

  defmodule PlainSection do
    @moduledoc """
    The same arrangement, declaring no `sentence/1`. It is here for the other
    rung of the chain the Note adopts: a composite with no line of its own is
    named by its type's label, so the answer is never blank.
    """

    use StatifierBlocks.Composite,
      name: "myapp.plain_section",
      params: [
        %{
          key: "applicant_path",
          type: :string,
          label: "Record the applicant at",
          required?: true,
          default: "",
          datamodel_path?: true
        }
      ],
      slots: [%{name: "body", to: {"then", "body"}, label: "Then"}],
      palette_entry: %{label: "Plain section", group: "Structure"},
      version: 1

    alias StatifierBlocks.Block

    @impl StatifierBlocks.Composite
    def subtree(params) do
      [
        Block.new("myapp.signup_step",
          id: "call",
          config: %{"assign_to" => params["applicant_path"]}
        ),
        Block.new("core.group", id: "then", slots: %{"body" => []})
      ]
    end
  end

  @datamodel %{
    "version" => 1,
    "scopes" => [],
    "types" => [
      %{
        "name" => "signup.applicant",
        "kind" => "record",
        "label" => "Applicant",
        "fields" => [
          %{"name" => "email", "type" => "string", "required?" => true},
          %{"name" => "invited_at", "type" => "datetime"}
        ]
      }
    ]
  }

  # -- helpers -----------------------------------------------------------

  defp palette do
    Palette.from_modules(
      [
        {"myapp.guarded_section", GuardedSection},
        {"myapp.plain_section", PlainSection},
        {"myapp.signup_step", SignupStep},
        {"myapp.notify", Notify},
        {"myapp.marker", Marker},
        {"myapp.deadline", Deadline}
      ],
      core: true
    )
  end

  defp section(type, id, children) do
    Block.new(type,
      id: id,
      config: %{"applicant_path" => "signup.applicant"},
      slots: %{"body" => children}
    )
  end

  defp document(children) do
    Document.new(
      Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => children}),
      id: "bdoc_CANONICAL"
    )
  end

  defp compile(children) do
    Compiler.compile(document(children), palette(), datamodel: @datamodel)
  end

  defp finding_for(children, reason_tag) do
    assert {:error, findings} = compile(children)
    assert %Finding{} = finding = Enum.find(findings, &(elem(&1.reason, 0) == reason_tag))
    finding
  end

  # -- the writer half ---------------------------------------------------

  describe "a minted expansion member as the disagreeing writer" do
    # Sabotage: put `source_phrase/2`'s catch-all back to `inspect(source)`
    # unconditionally - red, because the sentence then names `"blk_GX_call"`,
    # a block the author cannot see, cannot select and cannot edit.
    test "renders the owning composite's sentence" do
      finding =
        finding_for(
          [
            section("myapp.guarded_section", "blk_GX", [
              Block.new("myapp.notify",
                id: "blk_notify",
                config: %{"to" => "signup.applicant.invited_at"}
              )
            ])
          ],
          :type_mismatch
        )

      assert finding.message =~ ~s("Guard the applicant at signup.applicant" left)
      refute finding.message =~ "blk_GX_call"
    end

    # Sabotage: had `structure_finding/4`'s `:type_mismatch` clause rewrite
    # the tuple's `upstream_ref` to the composite id as well as the sentence -
    # red here, which is section 1 of the Note: the minted id is the only
    # thing that says WHICH member wrote the entry, and a fixture run and the
    # Source tab both still name it.
    test "leaves the minted id in the tuple" do
      finding =
        finding_for(
          [
            section("myapp.guarded_section", "blk_GX", [
              Block.new("myapp.notify",
                id: "blk_notify",
                config: %{"to" => "signup.applicant.invited_at"}
              )
            ])
          ],
          :type_mismatch
        )

      assert {:type_mismatch, "blk_notify", "blk_GX_call", "datetime", "string",
              "signup.applicant.invited_at"} = finding.reason
    end

    # Sabotage: the same one as the first test's - red here too, on
    # `"blk_PS_call"`. The rung is what this case adds: `BlockType.sentence/2`
    # lands on the type's label for a composite that composed no line of its
    # own, which is what ADR-0005's chain gives it and is why the answer is
    # never blank.
    test "a composite declaring no sentence renders its type's label" do
      finding =
        finding_for(
          [
            section("myapp.plain_section", "blk_PS", [
              Block.new("myapp.notify",
                id: "blk_notify",
                config: %{"to" => "signup.applicant.invited_at"}
              )
            ])
          ],
          :type_mismatch
        )

      assert finding.message =~ ~s("Plain section" left)
      refute finding.message =~ "blk_PS_call"
    end
  end

  # -- section 4: the pass-through child is not resolved ------------------

  describe "a pass-through child as the disagreeing writer" do
    # Sabotage: had `writer_sentences/3` key the composite's sentence by every
    # block in the composite's own subtree rather than by the ids the expansion
    # index holds - red, because a block the author placed inside the composite
    # is then renamed after it. Section 4: a pass-through child has no entry in
    # the index, `anchor/2` answers `nil` for it, and it keeps being named by an
    # id the author typed.
    test "is named by its own id, not the composite's sentence" do
      finding =
        finding_for(
          [
            section("myapp.guarded_section", "blk_GX", [
              Block.new("myapp.marker", id: "blk_marker", config: %{"at" => "signup.marker"}),
              Block.new("myapp.deadline", id: "blk_due", config: %{"when" => "signup.marker"})
            ])
          ],
          :type_mismatch
        )

      assert finding.message =~ ~s("blk_marker" left)
      refute finding.message =~ "Guard the applicant at"
    end
  end

  # -- the document that holds no composite -------------------------------

  describe "a document with no expansion" do
    # The regression guard for everything this Note does not touch, and its
    # sabotage is the first one in this file: putting `source_phrase/2`'s
    # catch-all back to an unconditional `inspect(source)` leaves this test
    # green, which is the point. A document holding no composite takes
    # `writer_sentences/3`'s empty-index clause, never reaches the map, and
    # reads word for word as it always did.
    test "renders the writer's own id exactly as before" do
      finding =
        finding_for(
          [
            Block.new("myapp.marker", id: "blk_marker", config: %{"at" => "signup.marker"}),
            Block.new("myapp.deadline", id: "blk_due", config: %{"when" => "signup.marker"})
          ],
          :type_mismatch
        )

      assert finding.message =~ ~s("blk_marker" left)
    end
  end
end
