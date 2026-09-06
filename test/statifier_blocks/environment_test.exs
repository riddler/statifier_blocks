defmodule StatifierBlocks.EnvironmentTest do
  @moduledoc """
  ADR-0011's walk, driven by the record's own worked shape: the card
  processing document whose datamodel declares two records and one shape,
  whose entry block names the subject path, and whose two branches - one
  agreeing, one disagreeing - are the record's whole argument for a per-path
  merge.

  A pure test. Nothing here names LiveView, so it compiles and runs in the
  headless job, which is where the walk's independence from the editor is
  actually proven.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Assignability, Block, Document, Environment, Palette}

  # ADR-0011's worked shape, verbatim in structure: two declared paths under
  # `scopes`, two records and one shape under `types`. `scopes` is carried
  # because a datamodel document without it is not a document.
  @datamodel %{
    "version" => 1,
    "scopes" => [
      %{"scope" => "global", "label" => "Global", "entries" => []},
      %{
        "scope" => "local",
        "label" => "This run",
        "entries" => [
          %{
            "name" => "current_txn",
            "path" => "cards.current_txn",
            "type" => "object",
            "label" => "Current transaction"
          },
          %{
            "name" => "settlement",
            "path" => "cards.settlement",
            "type" => "object",
            "label" => "Settlement"
          }
        ]
      },
      %{"scope" => "event", "label" => "Event", "entries" => []}
    ],
    "types" => [
      %{
        "name" => "cards.credit_txn",
        "kind" => "record",
        "label" => "Credit card transaction",
        "fields" => [
          %{"name" => "amount_minor", "type" => "integer", "required?" => true},
          %{"name" => "currency", "type" => "string", "required?" => true},
          %{"name" => "authorized_at", "type" => "datetime"},
          %{"name" => "expires_on", "type" => "date"}
        ]
      },
      %{
        "name" => "cards.settlement",
        "kind" => "record",
        "label" => "Settlement",
        "fields" => [
          %{"name" => "amount_minor", "type" => "integer", "required?" => true},
          %{"name" => "currency", "type" => "string", "required?" => true},
          %{"name" => "settled_on", "type" => "date", "required?" => true}
        ]
      },
      %{
        "name" => "Settleable",
        "kind" => "shape",
        "label" => "Settleable",
        "fields" => [
          %{"name" => "amount_minor", "type" => "integer", "required?" => true},
          %{"name" => "currency", "type" => "string", "required?" => true}
        ]
      },
      %{
        "name" => "Settled",
        "kind" => "shape",
        "label" => "Settled",
        "fields" => [
          %{"name" => "amount_minor", "type" => "integer", "required?" => true},
          %{"name" => "settled_on", "type" => "date", "required?" => true}
        ]
      }
    ]
  }

  @subject "cards.current_txn"

  defmodule Open do
    @moduledoc "The entry block: names the subject path and puts a record there."

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
    def io(_config), do: %{kinds: [:step], produces: "cards.credit_txn"}
    @impl true
    def palette_entry, do: %{label: "Open", subject: "cards.current_txn"}
    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule Settle do
    @moduledoc """
    The record's settle step: a `subject` field expecting a shape, and an
    `assign_to` field writing a record.
    """

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(config) do
      [
        %{
          key: "subject",
          type: {:path, %{expects: Map.get(config, "expects", "Settleable")}},
          label: "Settle what",
          required?: true,
          default: ""
        },
        %{
          key: "assign_to",
          type: {:path, %{writes: "cards.settlement"}},
          label: "Write the settlement to",
          required?: false,
          default: ""
        }
      ]
    end

    @impl true
    def validate_config(_config), do: :ok
    @impl true
    def io(_config), do: %{kinds: [:step]}
    @impl true
    def palette_entry, do: %{label: "Settle", subject: "cards.current_txn"}
    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule WriteString do
    @moduledoc "Writes one of the nine scalars at the path its field names."

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
          label: "Write a string to",
          required?: true,
          default: ""
        }
      ]

    @impl true
    def validate_config(_config), do: :ok
    @impl true
    def io(_config), do: %{kinds: [:step]}
    @impl true
    def palette_entry, do: %{label: "Write a string"}
    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule Widens do
    @moduledoc "Widens `cards.credit_txn` into `Settled`, and nothing else."

    @behaviour StatifierBlocks.Assignability.Relation

    @impl true
    def assignable?("cards.credit_txn", "Settled"), do: true
    def assignable?(_held, _expected), do: false
  end

  defmodule Deny do
    @moduledoc "Widens nothing - the floor a host relation can never fall below."

    @behaviour StatifierBlocks.Assignability.Relation

    @impl true
    def assignable?(_held, _expected), do: false
  end

  defp palette(assignability \\ nil) do
    Palette.new(
      Map.merge(Palette.core_types(), %{"cards.open" => Open, "cards.settle" => Settle}),
      assignability: assignability
    )
  end

  defp string_palette do
    Palette.new(
      Map.merge(Palette.core_types(), %{
        "cards.open" => Open,
        "cards.settle" => Settle,
        "cards.write_string" => WriteString
      })
    )
  end

  defp ctx, do: %{datamodel: @datamodel}

  defp open(id \\ "blk_OPEN"), do: Block.new("cards.open", id: id)

  defp settle(id, opts \\ []) do
    config =
      %{"subject" => @subject, "assign_to" => "cards.settlement"}
      |> Map.merge(Map.new(opts))

    Block.new("cards.settle", id: id, config: config)
  end

  defp assign(id, path) do
    Block.new("core.assign", id: id, config: %{"path" => path, "value" => "1"})
  end

  defp document(children, id \\ "bdoc_cards") do
    Document.new(Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => children}), id: id)
  end

  # `core.branch` reads its arms from `config["arms"]`, one slot per arm.
  defp branch(id, arms) do
    Block.new("core.branch",
      id: id,
      config: %{"arms" => Enum.map(arms, fn {slot, _} -> %{"slot" => slot, "cond" => "true"} end)},
      slots: Map.new(arms)
    )
  end

  describe "the seed and the walk" do
    # sabotage: drop the `:produces` arm from `sugar/5` (make it answer `[]`
    # for `:produces`) -> the environment holds nothing at the subject and
    # this assertion goes red
    test "the entry block's produces seeds the subject path" do
      document = document([open(), settle("blk_STL")])

      assert Environment.at(palette(), document, {"blk_ROOT", "body", 1}, ctx()) == %{
               @subject => "cards.credit_txn"
             }
    end

    # sabotage: change `seed_annotated/3`'s entry-type clause to answer `%{}`
    # -> the seed disappears and this goes red
    test "the entry block sees the seed, not what it is about to write" do
      document = document([open(), settle("blk_STL")])
      seeded = Map.put(ctx(), :entry_type, "cards.applicant")

      # The seed, and only the seed: the entry block's own `produces` lands
      # on the way out of it, so it is not in front of its own reads.
      assert Environment.at(palette(), document, {"blk_ROOT", "body", 0}, seeded) == %{
               @subject => "cards.applicant"
             }

      # And with nothing seeded, the document opens holding nothing at all.
      assert Environment.at(palette(), document, {"blk_ROOT", "body", 0}, ctx()) == %{}
    end

    # sabotage: drop `datamodel_path?/1` from `field_writes/2`'s filter, so a
    # `:string` field carrying `datamodel_path?: true` writes nothing -> the
    # assigned path is absent and this goes red
    test "a path field with no declared type makes the path known, not typed" do
      document =
        document([
          open(),
          assign("blk_ASG", "cards.current_txn.authorized_at"),
          settle("blk_STL")
        ])

      assert Environment.at(palette(), document, {"blk_ROOT", "body", 2}, ctx()) == %{
               @subject => "cards.credit_txn",
               "cards.current_txn.authorized_at" => :unknown
             }
    end

    # sabotage: change `written_type/1`'s `{:path, %{writes: T}}` clause to
    # answer `:unknown` -> the settlement path loses its type and this goes
    # red
    test "a writes: field types the path it names" do
      document = document([open(), settle("blk_STL"), settle("blk_STL2")])

      assert Environment.at(palette(), document, {"blk_ROOT", "body", 2}, ctx()) == %{
               @subject => "cards.credit_txn",
               "cards.settlement" => "cards.settlement"
             }
    end
  end

  describe "the read check" do
    # sabotage: change `Environment.satisfies/3` to hand the two spellings to
    # `Types.satisfies/3` in the other order -> coverage stops applying and
    # this document starts refusing
    test "a record covering a shape's required set satisfies the read" do
      document = document([open(), settle("blk_STL")])

      assert Assignability.validate(palette(), document, ctx()) == :ok
    end

    # sabotage: delete the `{:missing, names}` clause of `refused/2` so every
    # refusal answers `:not_assignable` -> the reason arm goes red
    test "a record that does not cover the shape is refused, naming the path and the fields" do
      document = document([open(), settle("blk_STL", %{"expects" => "Settled"})])

      assert {:error, [finding]} = Assignability.validate(palette(), document, ctx())

      assert finding ==
               {:type_mismatch, "blk_STL", "blk_OPEN", "cards.credit_txn", "Settled", @subject}

      assert Assignability.finding_reason(
               palette(),
               finding,
               StatifierDatamodel.Declarations.from_document(@datamodel)
             ) == {:shape_not_satisfied, ["settled_on"]}
    end

    # sabotage: move the `host_widens?/3` call in `assignable?/4` ahead of the
    # `Environment.satisfies/3` case -> the floor stops being reached last and
    # this goes red for the palette that carries no relation
    test "a palette with no host relation gets the new steps and the old floor" do
      document = document([open(), settle("blk_STL", %{"expects" => "Settleable"})])

      # The new step: coverage, before the host is asked at all.
      assert Assignability.validate(palette(), document, ctx()) == :ok

      # The old floor: nothing widens `cards.credit_txn` into an unrelated
      # declared name, and with no relation on the palette nothing can.
      refused = document([open(), settle("blk_REF", %{"expects" => "cards.settlement"})])

      assert {:error, [{:type_mismatch, "blk_REF", "blk_OPEN", _held, _expected, @subject}]} =
               Assignability.validate(palette(), refused, ctx())
    end

    # sabotage: swap the two arms of `assignable?/4` so the host is asked
    # first -> `Deny` starts narrowing what coverage already admitted, and
    # this goes red
    test "the host relation runs last, so a relation that widens nothing cannot narrow coverage" do
      document = document([open(), settle("blk_STL")])

      assert Assignability.validate(palette(Deny), document, ctx()) == :ok
    end

    # sabotage: make `assignable?/4` ignore its `declarations` argument ->
    # coverage has nothing to read and the host is asked about a pair it
    # widens, so this goes red the moment the relation is taken off
    test "the host is reached only after coverage has failed" do
      # `Settled` is not covered by `cards.credit_txn`, so the check falls
      # through to the relation, which widens exactly this pair.
      document = document([open(), settle("blk_STL", %{"expects" => "Settled"})])

      assert Assignability.validate(palette(Widens), document, ctx()) == :ok
      assert {:error, [_finding]} = Assignability.validate(palette(), document, ctx())
    end

    # sabotage: make `read_findings/5` treat an absent path as a refusal
    # instead of `:unknown` -> this goes red, because an undeclared path
    # stops being the advisory it is and becomes an error
    test "a path the environment does not hold is satisfied, not refused" do
      document = document([open(), settle("blk_STL", %{"subject" => "cards.nowhere"})])

      assert Assignability.validate(palette(), document, ctx()) == :ok
    end

    # The record's first contrast case, and the one an author meets most: a
    # step expecting a shape at a path a scalar was written to. It refuses,
    # it names the path, and the reason is not the coverage arm - nothing
    # was covered, the two are simply different - but `{:fixable_by, id}`,
    # naming the block whose write signature put the scalar there.
    #
    # sabotage: made `written_type/1` answer `:unknown` for a
    # `{:path, %{writes: T}}` field -> the scalar never reaches the path,
    # the read is satisfied by permissiveness, and this goes red (verified).
    test "a shape read at a path holding a scalar is refused, naming the path" do
      scalar = Block.new("cards.settle", id: "blk_SCALAR", config: %{"assign_to" => @subject})
      document = document([open(), scalar, settle("blk_STL")])

      # The write is a `cards.settlement`, not a string, until the type is
      # replaced - `config_schema/1` declares what the field writes, so a
      # scalar reaches the path through a block that declares one.
      assert Map.get(
               Environment.at(palette(), document, {"blk_ROOT", "body", 2}, ctx()),
               @subject
             ) ==
               "cards.settlement"

      string = Block.new("cards.write_string", id: "blk_STR", config: %{"at" => @subject})
      stringed = document([open(), string, settle("blk_STL")])

      assert Map.get(
               Environment.at(string_palette(), stringed, {"blk_ROOT", "body", 2}, ctx()),
               @subject
             ) == "string"

      assert {:error, [finding]} = Assignability.validate(string_palette(), stringed, ctx())

      assert finding ==
               {:type_mismatch, "blk_STL", "blk_STR", "string", "Settleable", @subject}

      assert Assignability.finding_reason(
               string_palette(),
               finding,
               StatifierDatamodel.Declarations.from_document(@datamodel)
             ) == {:fixable_by, "blk_STR"}
    end
  end

  describe "arms merge per path by agreement" do
    # sabotage: change `merged_entry/3`'s all-agree clause to answer
    # `{:unknown, :slot_entry}` -> the branch blanks the subject and the
    # settle step after it loses its check
    test "a branch whose arms agree types the block after it" do
      arms = [
        {"arm_receipt", [assign("blk_RCP", "cards.receipt")]},
        {"arm_notify", [assign("blk_NTF", "cards.notice")]}
      ]

      document = document([open(), branch("blk_BR", arms), settle("blk_STL")])
      env = Environment.at(palette(), document, {"blk_ROOT", "body", 2}, ctx())

      assert Map.get(env, @subject) == "cards.credit_txn"
      assert Assignability.validate(palette(), document, ctx()) == :ok
    end

    # sabotage: change `merged_entry/3`'s disagreeing clause to keep the
    # first arm's entry -> the subject stays typed through a branch that
    # rewrote it and the last assertion goes red
    test "a branch where one arm rewrites the subject drops that path and refuses nothing" do
      arms = [
        {"arm_retry", [Block.new("cards.open", id: "blk_RETRY")]},
        {"arm_fallback", [settle("blk_FALL", %{"assign_to" => @subject})]}
      ]

      document = document([open(), branch("blk_BR", arms), settle("blk_STL")])
      env = Environment.at(palette(), document, {"blk_ROOT", "body", 2}, ctx())

      assert Map.get(env, @subject) == :unknown

      # Decision 3's permissiveness doing its job: the walk lost information
      # and says so by being quiet, rather than by guessing.
      assert Assignability.validate(palette(), document, ctx()) == :ok
    end

    # sabotage: change `merged_entry/3`'s held-by-some clause to keep the one
    # entry it found -> a path only one arm holds leaves the container typed
    # and this goes red
    test "a path only one arm holds leaves the container at :unknown" do
      arms = [
        {"arm_a", [assign("blk_A", "cards.only_here")]},
        {"arm_b", [assign("blk_B", "cards.elsewhere")]}
      ]

      document = document([open(), branch("blk_BR", arms), settle("blk_STL")])
      env = Environment.at(palette(), document, {"blk_ROOT", "body", 2}, ctx())

      assert Map.get(env, "cards.only_here") == :unknown
      assert Map.get(env, "cards.elsewhere") == :unknown
    end
  end

  describe "a fan-out binds its item inside the body" do
    # sabotage: drop the `Map.drop(scoped)` from `slot_env/7` -> `item`
    # leaks out of the body and the second assertion goes red
    test "item and index are bound in the body and do not leave it" do
      body = [assign("blk_IN", "cards.tally")]

      foreach =
        Block.new("core.foreach",
          id: "blk_EACH",
          config: %{"items" => "cards.lines", "item_as" => "line"},
          slots: %{"body" => body}
        )

      document = document([open(), foreach, settle("blk_STL")])

      inside = Environment.at(palette(), document, {"blk_EACH", "body", 0}, ctx())
      assert Map.has_key?(inside, "line")
      assert Map.get(inside, "index") == "integer"

      after_it = Environment.at(palette(), document, {"blk_ROOT", "body", 2}, ctx())
      refute Map.has_key?(after_it, "line")
      refute Map.has_key?(after_it, "index")
    end
  end

  describe "the core vocabulary's signatures" do
    # sabotage: made `sugar_write/4` answer `[]` -> the entry block stops
    # seeding the subject path, every read below becomes a read of a path the
    # environment does not hold, and the refusal stops happening (verified)
    test "entry -> assign -> settle checks the settle step's read against the seed" do
      steps = fn expects ->
        document([
          open(),
          assign("blk_ASG", "cards.current_txn.authorized_at"),
          settle("blk_STL", %{"expects" => expects})
        ])
      end

      # The assign wrote a path beside the subject, so the settle step's read
      # is still checked against what the entry block seeded.
      assert Assignability.validate(palette(), steps.("Settleable"), ctx()) == :ok

      assert {:error,
              [{:type_mismatch, "blk_STL", "blk_OPEN", "cards.credit_txn", "Settled", @subject}]} =
               Assignability.validate(palette(), steps.("Settled"), ctx())
    end

    # sabotage: made `field_writes/2` test the field type
    # (`match?({:path, _}, ...)`) instead of `BlockType.datamodel_path?/1`, so
    # a `:string` field carrying the key stops writing -> red (verified)
    test "core.assign writes its path, known without becoming typed" do
      block = assign("blk_ASG", "cards.current_txn.authorized_at")
      document = document([open(), block, settle("blk_STL")])

      assert Environment.write_signatures(palette(), document, block) ==
               [{"path", "cards.current_txn.authorized_at", :unknown}]

      assert Environment.read_signatures(palette(), document, block) == []
    end

    # sabotage: dropped the `BlockType.datamodel_path?/1` filter from
    # `field_writes/2` -> `core.wait`'s `duration` becomes a write and the
    # untouched-environment assertion goes red (verified)
    test "core.wait, core.send, core.raise and core.await write nothing and read nothing" do
      leaves = [
        Block.new("core.wait", id: "blk_WAIT", config: %{"duration" => "PT5S"}),
        Block.new("core.send",
          id: "blk_SEND",
          config: %{"event" => "cards.receipt_requested", "delay" => "PT1S"}
        ),
        Block.new("core.raise", id: "blk_RAISE", config: %{"event" => "cards.retry"}),
        Block.new("core.await",
          id: "blk_AWAIT",
          config: %{"event" => "cards.receipt_arrived", "timeout" => "PT1M"}
        )
      ]

      document = document([open()] ++ leaves ++ [settle("blk_STL")])

      for block <- leaves do
        assert Environment.write_signatures(palette(), document, block) == []
        assert Environment.read_signatures(palette(), document, block) == []
      end

      # Four blocks later the environment is the seed, untouched.
      assert Environment.at(palette(), document, {"blk_ROOT", "body", 5}, ctx()) == %{
               @subject => "cards.credit_txn"
             }
    end

    # sabotage: reverted `core.subchart`'s `assign_to` to a plain `:string`
    # -> the outcome path stops being written and both assertions go red
    # (verified)
    test "core.subchart writes assign_to" do
      block =
        Block.new("core.subchart",
          id: "blk_SUB",
          config: %{"chart" => "bdoc_settle", "outcomes" => "done", "assign_to" => "settlement"}
        )

      document = document([open(), block, settle("blk_STL")])

      assert Environment.write_signatures(palette(), document, block) ==
               [{"assign_to", "settlement", :unknown}]

      env = Environment.at(palette(), document, {"blk_ROOT", "body", 2}, ctx())
      assert Map.get(env, "settlement") == :unknown
    end

    # sabotage: dropped the `writes` key off `core.map`'s `collect`
    # (`{:path, %{}}`) -> the block after the fan-out sees `:unknown` instead
    # of a list and this goes red (verified)
    test "the block after a core.map sees collect as a list" do
      block =
        Block.new("core.map",
          id: "blk_MAP",
          config: %{"items" => "cards.lines", "chart" => "bdoc_child", "collect" => "results"}
        )

      document = document([open(), block, settle("blk_STL")])

      # `items` says where without saying what; `collect` says both.
      assert Environment.write_signatures(palette(), document, block) == [
               {"items", "cards.lines", :unknown},
               {"collect", "results", {:list, :unknown}}
             ]

      env = Environment.at(palette(), document, {"blk_ROOT", "body", 2}, ctx())

      assert Map.get(env, "results") == {:list, :unknown}
      assert Environment.type_of(%{}, Map.get(env, "results")) == :list
    end

    # sabotage: made `capture_writes/1` fall through its `is_map` clause and
    # answer `[]` -> the captured path is invisible to everything after the
    # handler and this goes red (verified)
    test "a captured path is known after the handler" do
      handler =
        Block.new("core.on_event",
          id: "blk_ON",
          config: %{
            "event" => "cards.receipt_arrived",
            "outcome" => "resume",
            "capture" => %{"cards.receipt" => "receipt"}
          }
        )

      group =
        Block.new("core.group",
          id: "blk_GRP",
          slots: %{
            "body" => [assign("blk_STEP", "cards.tally")],
            "interrupts" => [handler]
          }
        )

      document = document([open(), group, settle("blk_STL")])

      assert Environment.write_signatures(palette(), document, handler) ==
               [{"capture", "cards.receipt", :unknown}]

      # On the interrupt path, immediately after the handler.
      after_handler = Environment.at(palette(), document, {"blk_GRP", "interrupts", 1}, ctx())
      assert Map.has_key?(after_handler, "cards.receipt")

      # And after the group: the handler fired or it did not, so decision 4
      # leaves the path known and untyped rather than absent.
      after_group = Environment.at(palette(), document, {"blk_ROOT", "body", 2}, ctx())
      assert Map.get(after_group, "cards.receipt") == :unknown
    end

    # sabotage: dropped the `arms/5` step from `through/5` -> a container
    # stops handing its children's writes out and the settlement assertion
    # goes red (verified)
    test "a one-slot container hands its children's writes out through the merge" do
      for container <- [
            Block.new("core.sequence", id: "blk_C", slots: %{"body" => [settle("blk_IN")]}),
            Block.new("core.group", id: "blk_C", slots: %{"body" => [settle("blk_IN")]}),
            Block.new("core.resumable_group",
              id: "blk_C",
              config: %{"history" => "shallow"},
              slots: %{"body" => [settle("blk_IN")]}
            ),
            Block.new("core.foreach",
              id: "blk_C",
              config: %{"items" => "cards.lines"},
              slots: %{"body" => [settle("blk_IN")]}
            )
          ] do
        document = document([open(), container, settle("blk_STL")])
        env = Environment.at(palette(), document, {"blk_ROOT", "body", 2}, ctx())

        assert Map.get(env, "cards.settlement") == "cards.settlement"
        assert Map.get(env, @subject) == "cards.credit_txn"
      end
    end

    # sabotage: made `merged_disagreement/1` answer `{:unknown, :slot_entry}`
    # for a single agreed type -> two lanes writing the same type at the same
    # path stop agreeing and this goes red (verified)
    test "core.parallel's lanes merge per path, and lanes that agree keep the type" do
      parallel =
        Block.new("core.parallel",
          id: "blk_PAR",
          config: %{"lanes" => ["a", "b"]},
          slots: %{"lane_a" => [settle("blk_A")], "lane_b" => [settle("blk_B")]}
        )

      document = document([open(), parallel, settle("blk_STL")])
      env = Environment.at(palette(), document, {"blk_ROOT", "body", 2}, ctx())

      assert Map.get(env, "cards.settlement") == "cards.settlement"
      assert Map.get(env, @subject) == "cards.credit_txn"
    end

    # sabotage: gave `core.wait` a `{:path, %{}}` field -> the census below
    # names a fifth writer and this goes red (verified)
    test "the vocabulary's path-field writers are exactly the four the record names" do
      writers =
        for {name, module} <- Palette.core_types(),
            Code.ensure_loaded?(module),
            function_exported?(module, :config_schema, 1),
            Enum.any?(module.config_schema(%{}), &StatifierBlocks.BlockType.datamodel_path?/1),
            do: name

      assert Enum.sort(writers) == ["core.assign", "core.foreach", "core.map", "core.subchart"]
    end
  end

  describe "totality and termination" do
    # sabotage: n/a for a wrong answer - this test exists to catch a *hang*.
    # Confirmed by making `entering/4` recurse on the block's own position
    # instead of the position it occupies, which makes this run past its
    # timeout instead of asserting red.
    test "a document built only of empty sequences terminates" do
      depth = 2_000

      innermost = Block.new("core.sequence", id: "blk_seq0", slots: %{"body" => []})

      chain =
        Enum.reduce(1..depth, innermost, fn i, acc ->
          Block.new("core.sequence", id: "blk_seq#{i}", slots: %{"body" => [acc]})
        end)

      document = document([chain])

      task =
        Task.async(fn -> Environment.at(palette(), document, {"blk_seq0", "body", 0}, ctx()) end)

      assert Task.await(task, 5_000) == %{}
    end

    # sabotage: remove the `index > length(children)` guard from
    # `annotated/4` -> a position past the end of a slot starts answering for
    # the end of the slot and this goes red
    test "a position past the end of a slot holds nothing" do
      document = document([open(), settle("blk_STL")])

      assert Environment.at(palette(), document, {"blk_ROOT", "body", 9}, ctx()) == %{}
    end

    # sabotage: change `annotated/4`'s `nil` clause to answer the seed ->
    # this goes red, because a parent no block carries starts answering with
    # a typed environment
    test "a parent no block carries holds nothing" do
      document = document([open(), settle("blk_STL")])
      seeded = Map.put(ctx(), :entry_type, "cards.applicant")

      assert Environment.at(palette(), document, {"blk_MISSING", "body", 0}, seeded) == %{}
    end

    # sabotage: change `declarations/1` to read a key other than `:datamodel`
    # -> the declarations go empty, coverage stops applying, and the
    # satisfied document above starts refusing
    test "a datamodel that is not a document declares nothing rather than raising" do
      document = document([open(), settle("blk_STL")])

      assert Environment.declarations(%{datamodel: "not a document"}) == %{}
      assert Environment.declarations(%{}) == %{}

      # And the walk over it is still total: with no declarations the two
      # opaque spellings simply fail to match, which is a refusal and not an
      # exception.
      assert {:error, [_finding]} = Assignability.validate(palette(), document, %{})
    end
  end

  describe "the type grammar" do
    # sabotage: delete `type_of/2`'s `"unknown"` clause -> the string reads
    # as an opaque expression again and this goes red
    test "the string unknown reads as :unknown" do
      assert Environment.type_of(%{}, "unknown") == :unknown
      assert Environment.type_of(%{}, :unknown) == :unknown
    end

    # sabotage: delete `type_of/2`'s `{:list, _}` clause -> a list falls
    # through to `parse/2`, which does not know it, and this goes red
    test "a list is the document's own list, whatever its item type" do
      assert Environment.type_of(%{}, {:list, "cards.credit_txn"}) == :list
      assert Environment.satisfies(%{}, {:list, "a"}, {:list, "b"}) == :identical
    end
  end

  describe "what this package does not define" do
    # sabotage: add a `StatifierBlocks.Compatibility` module -> this goes
    # red. ADR-0011 decision 3: the eight-row table is asserted once, in the
    # package that owns the document.
    test "no Compatibility or Coverage module of this package's own" do
      refute Code.ensure_loaded?(StatifierBlocks.Compatibility)
      refute Code.ensure_loaded?(StatifierBlocks.Coverage)

      # The read check that is used instead, named so a reader finds it.
      assert function_exported?(StatifierDatamodel.Types, :satisfies, 3)
      assert function_exported?(StatifierDatamodel.Types, :satisfies?, 3)
    end
  end
end
