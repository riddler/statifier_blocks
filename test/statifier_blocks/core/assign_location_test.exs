defmodule StatifierBlocks.Core.AssignLocationTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.Core.{AssignLocation, Config, Invoke, Map, Subchart}
  alias StatifierBlocks.InvokeStep

  @message "must be a datamodel path, like cards.authorization"

  describe "the shared shape" do
    # sabotage: dropped the blank arm so `""` reached the rule -> every
    # optional location field becomes required and this goes red (verified)
    test "a blank location passes and produces nothing" do
      assert AssignLocation.location(nil, "assign_to", &Config.datamodel_path?/1, @message) ==
               {:ok, nil}

      assert AssignLocation.location("", "assign_to", &Config.datamodel_path?/1, @message) ==
               {:ok, nil}

      assert AssignLocation.check(
               [],
               %{"assign_to" => ""},
               "assign_to",
               &Config.datamodel_path?/1,
               @message
             ) == []
    end

    # sabotage: anchored the finding on a fixed `"assign_to"` instead of the
    # key it was given -> `core.map`'s refusal lands on a key its form has
    # no control for and this goes red (verified)
    test "a refusal is one finding anchored on the field's own key" do
      assert AssignLocation.location("a b", "collect", &Config.identifier?/1, "nope") ==
               {:error, [{"collect", "nope"}]}

      assert AssignLocation.check(
               [{"chart", "earlier"}],
               %{"collect" => "a b"},
               "collect",
               &Config.identifier?/1,
               "nope"
             ) == [{"collect", "nope"}, {"chart", "earlier"}]
    end

    # sabotage: made `check/5` add the finding whatever the rule answered ->
    # every accepted location grows the list and this goes red (verified)
    test "an accepted location leaves the accumulator untouched" do
      assert AssignLocation.check(
               [{"chart", "earlier"}],
               %{"assign_to" => "cards.authorization"},
               "assign_to",
               &Config.datamodel_path?/1,
               @message
             ) == [{"chart", "earlier"}]
    end
  end

  describe "the four sites it is shared across" do
    # sabotage: pointed `core.invoke` at `Config.identifier?/1` -> the three
    # datamodel-path sites stop agreeing and this goes red (verified)
    test "three of the four take a dotted path, and core.map's collect does not" do
      assert Invoke.validate_config(%{
               "invoke_type" => "myapp:authorize",
               "assign_to" => "cards.authorization"
             }) == :ok

      assert Subchart.validate_config(%{"chart" => "bdoc_C", "assign_to" => "cards.outcome"}) ==
               :ok

      assert InvokeStep.check_assign_to([], %{"assign_to" => "cards.authorization"}) == []

      # ADR-0009 decision 4 gives `collect` a bare-identifier grammar in as
      # many words, so widening it is that record's amendment to make.
      assert {:error, [{"collect", message}]} =
               Map.validate_config(%{
                 "items" => "signup.invitees",
                 "chart" => "bdoc_C",
                 "collect" => "signup.answers"
               })

      assert message =~ "bare lowercase identifier"
    end

    # sabotage: widened the rule to `non_empty_string?/1` at any one site ->
    # whitespace stops being refused there and this goes red (verified)
    test "none of the four accepts whitespace in a location" do
      assert {:error, [{"assign_to", _m1}]} =
               Invoke.validate_config(%{"invoke_type" => "myapp:authorize", "assign_to" => "a b"})

      assert {:error, [{"assign_to", _m2}]} =
               Subchart.validate_config(%{"chart" => "bdoc_C", "assign_to" => "a b"})

      assert [{"assign_to", _m3}] = InvokeStep.check_assign_to([], %{"assign_to" => "a b"})

      assert {:error, [{"collect", _m4}]} =
               Map.validate_config(%{
                 "items" => "signup.invitees",
                 "chart" => "bdoc_C",
                 "collect" => "a b"
               })
    end
  end
end
