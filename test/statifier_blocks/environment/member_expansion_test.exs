defmodule StatifierBlocks.Environment.MemberExpansionTest do
  @moduledoc """
  ADR-0011's Amendment of 2026-09-07: a write signature whose type is a
  record, a shape, or an inline shape puts an entry at the path it names
  **and** one at every member beneath it.

  The record's worked shape is the signup domain's - a step that writes a
  contact record at `signup.contact` and a later step that reads
  `signup.contact.email` - so the fixtures here are that domain's, in this
  file, because no other surface asserts against them.

  The datamodel declares `types` and no `scopes` entries at all, so the seed
  is empty and every entry an assertion names came from a write. The seed's
  own expansion is `StatifierDatamodel.Index.entries/1`'s and is asserted
  elsewhere; this file is about the write side.

  A pure test. Nothing here names LiveView, so it compiles and runs headless.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Assignability, Block, Document, Environment, Palette}

  @datamodel %{
    "version" => 1,
    "scopes" => [],
    "types" => [
      %{
        "name" => "signup.plan",
        "kind" => "record",
        "label" => "Plan",
        "fields" => [
          %{"name" => "tier", "type" => "string", "required?" => true},
          %{"name" => "seats", "type" => "integer"}
        ]
      },
      %{
        "name" => "signup.contact",
        "kind" => "record",
        "label" => "Contact",
        "fields" => [
          %{"name" => "email", "type" => "string", "required?" => true},
          %{"name" => "phone", "type" => "string"},
          %{"name" => "address", "type" => "signup.postal_address"}
        ]
      },
      %{
        "name" => "signup.postal_address",
        "kind" => "record",
        "label" => "Postal address",
        "fields" => [
          %{"name" => "line1", "type" => "string", "required?" => true},
          %{"name" => "postcode", "type" => "string", "required?" => true}
        ]
      },
      %{
        "name" => "Contactable",
        "kind" => "shape",
        "label" => "Contactable",
        "fields" => [
          %{"name" => "email", "type" => "string", "required?" => true},
          %{"name" => "phone", "type" => "string"}
        ]
      },
      %{
        "name" => "signup.invite_batch",
        "kind" => "record",
        "label" => "Invite batch",
        "fields" => [
          %{"name" => "sent_at", "type" => "datetime"},
          %{"name" => "invitees", "type" => "list", "item_type" => "signup.contact"}
        ]
      },
      %{
        "name" => "signup.referrer",
        "kind" => "record",
        "label" => "Referrer",
        "fields" => [
          %{"name" => "name", "type" => "string", "required?" => true},
          %{"name" => "referred_by", "type" => "signup.referrer"}
        ]
      }
    ]
  }

  defmodule Assign do
    @moduledoc """
    One write signature, at the path and the type the config names. The type
    is a term rather than a spelling read out of JSON, so one block type
    stands in for every row of the amendment's table.
    """

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(config),
      do: [
        %{
          key: "assign_to",
          type: {:path, %{writes: Map.get(config, "writes", :unknown)}},
          label: "Write to",
          required?: true,
          default: ""
        }
      ]

    @impl true
    def validate_config(_config), do: :ok
    @impl true
    def io(_config), do: %{kinds: [:step]}
    @impl true
    def palette_entry, do: %{label: "Assign"}
    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule AssignPair do
    @moduledoc "A record write at a root and an explicit write beneath it, in one block."

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
          type: {:path, %{writes: "signup.contact"}},
          label: "Write the contact to",
          required?: true,
          default: ""
        },
        %{
          key: "member_at",
          type: {:path, %{writes: "integer"}},
          label: "Write a count to",
          required?: true,
          default: ""
        }
      ]

    @impl true
    def validate_config(_config), do: :ok
    @impl true
    def io(_config), do: %{kinds: [:step]}
    @impl true
    def palette_entry, do: %{label: "Assign a pair"}
    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule AssignPairReversed do
    @moduledoc """
    `AssignPair`'s two fields in the other declaration order, which is the
    order that actually exercises the rule: with the member's own signature
    declared first, only the precedence rule keeps the record's derived
    member from landing on top of it.
    """

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(_config),
      do: [
        %{
          key: "member_at",
          type: {:path, %{writes: "integer"}},
          label: "Write a count to",
          required?: true,
          default: ""
        },
        %{
          key: "assign_to",
          type: {:path, %{writes: "signup.contact"}},
          label: "Write the contact to",
          required?: true,
          default: ""
        }
      ]

    @impl true
    def validate_config(_config), do: :ok
    @impl true
    def io(_config), do: %{kinds: [:step]}
    @impl true
    def palette_entry, do: %{label: "Assign a pair, member first"}
    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defmodule Reads do
    @moduledoc "One read signature, at the path and the type the config names."

    @behaviour StatifierBlocks.BlockType

    @impl true
    def current_version, do: 1
    @impl true
    def slots(_config), do: []

    @impl true
    def config_schema(config),
      do: [
        %{
          key: "subject",
          type: {:path, %{expects: Map.get(config, "expects", "string")}},
          label: "Read",
          required?: true,
          default: ""
        }
      ]

    @impl true
    def validate_config(_config), do: :ok
    @impl true
    def io(_config), do: %{kinds: [:step]}
    @impl true
    def palette_entry, do: %{label: "Read"}
    @impl true
    def emit(%Block{id: id}, _context), do: {:error, {:not_implemented, id}}
  end

  defp palette do
    Palette.new(
      Map.merge(Palette.core_types(), %{
        "myapp.assign" => Assign,
        "myapp.assign_pair" => AssignPair,
        "myapp.assign_pair_reversed" => AssignPairReversed,
        "myapp.reads" => Reads
      })
    )
  end

  defp ctx, do: %{datamodel: @datamodel}

  defp assign(id, path, writes) do
    Block.new("myapp.assign", id: id, config: %{"assign_to" => path, "writes" => writes})
  end

  defp document(children) do
    Document.new(
      Block.new("core.sequence", id: "blk_ROOT", slots: %{"body" => children}),
      id: "bdoc_signup"
    )
  end

  # The environment after every child of the root's body.
  defp after_all(children) do
    document = document(children)
    Environment.at(palette(), document, {"blk_ROOT", "body", length(children)}, ctx())
  end

  defp annotated_after_all(children) do
    document = document(children)
    Environment.annotated(palette(), document, {"blk_ROOT", "body", length(children)}, ctx())
  end

  describe "section 2's table, one test per row" do
    # sabotage: make `expansion/3`'s binary clause answer `:none` -> a named
    # record stops expanding and this row goes red
    test "row 1: a named record yields the path and one entry per field" do
      assert after_all([assign("blk_A", "signup.plan", "signup.plan")]) == %{
               "signup.plan" => "signup.plan",
               "signup.plan.tier" => "string",
               "signup.plan.seats" => "integer"
             }
    end

    # sabotage: filter `expansion/3`'s declaration clause on `kind == :record`
    # -> a shape stops expanding and this row goes red
    test "row 2: a named shape yields its fields exactly as a record does" do
      assert after_all([assign("blk_A", "signup.applicant", "Contactable")]) == %{
               "signup.applicant" => "Contactable",
               "signup.applicant.email" => "string",
               "signup.applicant.phone" => "string"
             }
    end

    # sabotage: drop `expansion/3`'s `{:shape, members}` clause -> an inline
    # shape falls through to the catch-all and this row goes red
    test "row 3: an inline shape yields one entry per member, in member order" do
      inline =
        {:shape,
         [
           %{name: "token", type: "string", required?: true},
           %{name: "attempts", type: "integer", required?: false}
         ]}

      assert after_all([assign("blk_A", "signup.verification", inline)]) == %{
               "signup.verification" => inline,
               "signup.verification.token" => "string",
               "signup.verification.attempts" => "integer"
             }
    end

    # sabotage: have `expansion/3`'s `{:list, _}` clause expand the item type
    # -> a list starts contributing paths and this row goes red
    test "row 4: a list yields the path and nothing else" do
      assert after_all([assign("blk_A", "signup.plans", {:list, "signup.plan"})]) == %{
               "signup.plans" => {:list, "signup.plan"}
             }
    end

    # sabotage: make `expansion/3`'s catch-all expand rather than answer
    # `:none` -> one of these three grows entries and this row goes red
    test "row 5: a scalar, an opaque name and :unknown yield the path and nothing else" do
      assert after_all([assign("blk_A", "signup.email", "string")]) == %{
               "signup.email" => "string"
             }

      assert after_all([assign("blk_A", "signup.payload", "myapp.opaque")]) == %{
               "signup.payload" => "myapp.opaque"
             }

      assert after_all([assign("blk_A", "signup.note", :unknown)]) == %{
               "signup.note" => :unknown
             }
    end

    # sabotage: stop `derived_writes/4` from recursing (return only the
    # member pairs) -> the two `address` members disappear and this goes red
    test "row 6: a record inside a record expands beneath its own path" do
      assert after_all([assign("blk_A", "signup.contact", "signup.contact")]) == %{
               "signup.contact" => "signup.contact",
               "signup.contact.email" => "string",
               "signup.contact.phone" => "string",
               "signup.contact.address" => "signup.postal_address",
               "signup.contact.address.line1" => "string",
               "signup.contact.address.postcode" => "string"
             }
    end

    # sabotage: as row 4's, reached through a member rather than through the
    # root
    test "row 7: a list-typed member yields its own entry and nothing beneath it" do
      assert after_all([assign("blk_A", "signup.batch", "signup.invite_batch")]) == %{
               "signup.batch" => "signup.invite_batch",
               "signup.batch.sent_at" => "datetime",
               "signup.batch.invitees" => {:list, "signup.contact"}
             }
    end
  end

  describe "section 4's precedence" do
    # sabotage: drop the `put_derived/6` step from `apply_writes/5` -> the
    # `phone` member disappears and this goes red. The `declared` guard is not
    # what this test exercises: these two fields are declared in the order
    # that hides it, which is why the next test exists
    test "an explicit signature in the same block wins over the derived member" do
      pair =
        Block.new("myapp.assign_pair",
          id: "blk_A",
          config: %{"assign_to" => "signup.contact", "member_at" => "signup.contact.email"}
        )

      env = after_all([pair])

      assert Map.fetch!(env, "signup.contact.email") == "integer"
      assert Map.fetch!(env, "signup.contact.phone") == "string"
    end

    # sabotage: drop the `declared` MapSet test from `put_derived/6` -> the
    # record's derived `string` lands on top of the block's own `integer`,
    # which the previous test cannot see because its two fields happen to be
    # declared in the order that hides it, and this one goes red (verified)
    test "the explicit signature wins whichever order the two fields are declared in" do
      pair =
        Block.new("myapp.assign_pair_reversed",
          id: "blk_A",
          config: %{"assign_to" => "signup.contact", "member_at" => "signup.contact.email"}
        )

      env = after_all([pair])

      assert Map.fetch!(env, "signup.contact.email") == "integer"
      assert Map.fetch!(env, "signup.contact.phone") == "string"
    end

    # sabotage: apply the derived members before the signature's own entry ->
    # the later block's write is overwritten and this goes red
    test "a later block writing the member replaces the derived entry" do
      env =
        after_all([
          assign("blk_A", "signup.contact", "signup.contact"),
          assign("blk_B", "signup.contact.email", "integer")
        ])

      assert Map.fetch!(env, "signup.contact.email") == "integer"
      assert Map.fetch!(env, "signup.contact.phone") == "string"
    end

    # sabotage: make `clear_derived/3` a no-op -> the six member entries
    # survive a rewrite to a scalar and this goes red
    test "a rewrite at the root clears the members its previous write derived" do
      env =
        after_all([
          assign("blk_A", "signup.contact", "signup.contact"),
          assign("blk_B", "signup.contact", "string")
        ])

      assert env == %{"signup.contact" => "string"}
    end

    # sabotage: drop the equality test in `clear_derived/3`'s reduce and
    # delete every derived path unconditionally -> the explicit entry the
    # earlier block wrote is cleared too and this goes red
    test "a rewrite does not clear a member an explicit signature wrote" do
      env =
        after_all([
          assign("blk_A", "signup.contact", "signup.contact"),
          assign("blk_B", "signup.contact.email", "integer"),
          assign("blk_C", "signup.contact", "string")
        ])

      assert env == %{"signup.contact" => "string", "signup.contact.email" => "integer"}
    end

    # sabotage: as the rewrite test's - the new type's members have to be
    # derived as well as the old type's cleared
    test "a rewrite derives the new type's members" do
      env =
        after_all([
          assign("blk_A", "signup.thing", "signup.contact"),
          assign("blk_B", "signup.thing", "signup.plan")
        ])

      assert env == %{
               "signup.thing" => "signup.plan",
               "signup.thing.tier" => "string",
               "signup.thing.seats" => "integer"
             }
    end
  end

  describe "section 3's depth" do
    # sabotage: start `derived_writes/3` with a `seen` that is never added to
    # -> `signup.referrer` re-enters itself and the walk does not terminate
    test "a self-referencing declaration expands once per chain of paths" do
      env = after_all([assign("blk_A", "signup.referrer", "signup.referrer")])

      assert env == %{
               "signup.referrer" => "signup.referrer",
               "signup.referrer.name" => "string",
               "signup.referrer.referred_by" => "signup.referrer"
             }
    end

    # sabotage: as above, reached two levels down rather than one
    test "the guard is per chain, so a second unrelated root expands again" do
      env =
        after_all([
          assign("blk_A", "signup.contact", "signup.contact"),
          assign("blk_B", "signup.other", "signup.postal_address")
        ])

      assert Map.fetch!(env, "signup.contact.address.line1") == "string"
      assert Map.fetch!(env, "signup.other.line1") == "string"
    end
  end

  describe "section 5's upstream reference" do
    # sabotage: annotate a derived entry with `:slot_entry` rather than the
    # block id -> the member entry stops naming the block that wrote the root
    test "a member entry names the block that wrote the root" do
      env = annotated_after_all([assign("blk_A", "signup.contact", "signup.contact")])

      assert Map.fetch!(env, "signup.contact") == {"signup.contact", "blk_A"}
      assert Map.fetch!(env, "signup.contact.email") == {"string", "blk_A"}
      assert Map.fetch!(env, "signup.contact.address.line1") == {"string", "blk_A"}
    end

    # sabotage: as above - the refusal's `source` is the annotation, so a
    # member entry that named `:slot_entry` would change this finding
    test "a refused member read is a type mismatch against the root's writer" do
      document =
        document([
          assign("blk_A", "signup.contact", "signup.contact"),
          Block.new("myapp.reads",
            id: "blk_B",
            config: %{"subject" => "signup.contact.email", "expects" => "integer"}
          )
        ])

      assert {:error, findings} = Assignability.validate(palette(), document, ctx())

      assert findings == [
               {:type_mismatch, "blk_B", "blk_A", "string", "integer", "signup.contact.email"}
             ]
    end

    # sabotage: as row 1's - with no expansion the read finds nothing at the
    # member path, which decision 5 makes an advisory rather than an error
    test "the same read is satisfied when the member type meets it" do
      document =
        document([
          assign("blk_A", "signup.contact", "signup.contact"),
          Block.new("myapp.reads",
            id: "blk_B",
            config: %{"subject" => "signup.contact.email", "expects" => "string"}
          )
        ])

      assert Assignability.validate(palette(), document, ctx()) == :ok
    end
  end

  describe "what expansion does not reach" do
    # sabotage: expand `declared_seed/1`'s entries -> the seed grows member
    # entries of its own and this goes red
    test "a caller with no datamodel expands nothing, because nothing resolves" do
      children = [assign("blk_A", "signup.contact", "signup.contact")]
      document = document(children)

      assert Environment.at(palette(), document, {"blk_ROOT", "body", 1}, %{}) == %{
               "signup.contact" => "signup.contact"
             }
    end

    # sabotage: expand read signatures too -> a read stops being a question
    # about one path and this goes red
    test "a read signature is a question about one path and expands nothing" do
      block =
        Block.new("myapp.reads",
          id: "blk_B",
          config: %{"subject" => "signup.contact", "expects" => "signup.contact"}
        )

      document = document([block])

      assert Environment.read_signatures(palette(), document, block) == [
               {"subject", "signup.contact", "signup.contact"}
             ]
    end

    # sabotage: expand inside `write_signatures/3` -> the public list of what
    # a block declares grows entries no field declared and this goes red
    test "write_signatures/3 answers what the block declares, not what it derives" do
      block = assign("blk_A", "signup.contact", "signup.contact")
      document = document([block])

      assert Environment.write_signatures(palette(), document, block) == [
               {"assign_to", "signup.contact", "signup.contact"}
             ]
    end
  end

  describe "section 4: the drop-check preview and the walk are one codepath" do
    # sabotage: give `apply_writes/5` a reduce of its own again rather than
    # delegating -> the walk and the preview stop being one codepath and this
    # equality goes red
    test "with_writes/5 answers exactly what the walk holds after the same block" do
      candidate = assign("blk_A", "signup.contact", "signup.contact")
      document = document([candidate])
      declarations = Environment.declarations(ctx())

      before = Environment.annotated(palette(), document, {"blk_ROOT", "body", 0}, ctx())

      assert Environment.with_writes(palette(), document, candidate, before, declarations) ==
               annotated_after_all([candidate])
    end

    # sabotage: give `with_writes/5` a plain `Map.put` per signature (its body
    # before the amendment) -> without the expansion the preview holds no member
    # entry, so the read at `signup.contact.email` is decision 5's advisory
    test "the preview refuses a member mismatch the drop would introduce" do
      downstream =
        Block.new("myapp.reads",
          id: "blk_B",
          config: %{"subject" => "signup.contact.email", "expects" => "integer"}
        )

      candidate = assign("blk_A", "signup.contact", "signup.contact")

      assert {:error, findings} =
               Assignability.check(
                 palette(),
                 document([downstream]),
                 {"blk_ROOT", "body", 0},
                 candidate,
                 ctx()
               )

      assert findings == [
               {:type_mismatch, "blk_B", "blk_A", "string", "integer", "signup.contact.email"}
             ]

      # and `validate/3` on the document the drop produces says the same
      assert {:error, ^findings} =
               Assignability.validate(palette(), document([candidate, downstream]), ctx())
    end

    # sabotage: default `declarations` to `Environment.declarations(%{})`'s
    # result computed from a document -> this stops being the empty index
    test "the declarations argument defaults to the empty index" do
      candidate = assign("blk_A", "signup.contact", "signup.contact")
      document = document([candidate])

      assert Environment.with_writes(palette(), document, candidate, %{}) == %{
               "signup.contact" => {"signup.contact", "blk_A"}
             }
    end
  end
end
