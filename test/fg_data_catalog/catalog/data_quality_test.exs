defmodule FGDataCatalog.Catalog.DataQualityTest do
  # NOTE(Claude 2026-11-16): the score and the casting, mostly against an
  # explicit criteria list, so that adding or removing a criterion does not
  # break them.
  use FGDataCatalog.DataCase, async: true

  alias FGDataCatalog.Catalog.{DataQuality, DatasetVersion}

  doctest DataQuality, import: true

  @criteria [
    %{key: "a", label: "A", question: "A?", if_no: "Do A"},
    %{key: "b", label: "B", question: "B?", if_no: "Do B"},
    %{key: "c", label: "C", question: "C?", if_no: "Do C"}
  ]

  describe "score/2" do
    test "counts the criteria answered yes, over the number of criteria" do
      assert DataQuality.score(%{"a" => "yes", "b" => "yes", "c" => "no"}, @criteria) == {2, 3}
    end

    test "counts Unknown (an absent key) as No" do
      assert DataQuality.score(%{"a" => "yes"}, @criteria) == {1, 3}
      assert DataQuality.score(%{"a" => "yes", "b" => "no"}, @criteria) == {1, 3}
    end

    test "nothing answered scores zero" do
      assert DataQuality.score(%{}, @criteria) == {0, 3}
    end
  end

  # NOTE(Claude Opus 5.5 2026-11-18): Not applicable criteria are left out of
  # the score.
  describe "Not applicable" do
    test "is left out of the denominator" do
      answers = %{"a" => "yes", "b" => "na", "c" => "no"}
      assert DataQuality.score(answers, @criteria) == {1, 2}
      assert DataQuality.score_text(answers, @criteria) == "1/2"

      assert DataQuality.score_description(answers, @criteria) ==
               "1 of 2 applicable criteria met"
    end

    test "Unknown still makes the score incomplete" do
      answers = %{"a" => "yes", "b" => "na"}
      assert DataQuality.score_text(answers, @criteria) == "?/2"
      assert DataQuality.level(answers, @criteria) == :unknown

      assert DataQuality.score_description(answers, @criteria) ==
               "unknown, 1 of 2 applicable criteria not answered"
    end

    test "the level is by the share of applicable criteria met" do
      assert DataQuality.level(%{"a" => "yes", "b" => "na", "c" => "na"}, @criteria) == :high
      assert DataQuality.level(%{"a" => "no", "b" => "na", "c" => "na"}, @criteria) == :low
    end

    test "every criterion Not applicable is n/a, not a score" do
      answers = %{"a" => "na", "b" => "na", "c" => "na"}
      assert DataQuality.not_applicable?(answers, @criteria)
      assert DataQuality.score(answers, @criteria) == {0, 0}
      assert DataQuality.score_text(answers, @criteria) == "n/a"
      assert DataQuality.score_description(answers, @criteria) == "not applicable"
      assert DataQuality.level(answers, @criteria) == :na
    end

    test "is an answer of its own" do
      assert DataQuality.answer(%{"a" => "na"}, "a") == :na
      assert DataQuality.answer(%{"a" => :na}, "a") == :na
      assert DataQuality.answer_label(:na) == "Not applicable"
      refute DataQuality.not_applicable?(%{"a" => "na"}, @criteria)
    end

    test "cast/2 keeps it, and diff/3 shows it" do
      assert DataQuality.cast(%{"a" => "na", "b" => "n/a"}, @criteria) == %{"a" => "na"}

      assert DataQuality.diff(%{"a" => "no"}, %{"a" => "na"}, @criteria) ==
               [{"A", :no, :na}]
    end
  end

  describe "level/2" do
    test "unknown while one or more criteria are Unknown" do
      assert DataQuality.level(%{}, @criteria) == :unknown
      assert DataQuality.level(%{"a" => "yes", "b" => "yes"}, @criteria) == :unknown
    end

    test "low, medium or high by the share of criteria met, for 7 criteria" do
      criteria = for i <- 1..7, do: %{key: "k#{i}", label: "", question: "", if_no: ""}

      levels =
        for met <- 0..7 do
          answers =
            Map.new(Enum.with_index(criteria, 1), fn {c, i} ->
              {c.key, if(i <= met, do: "yes", else: "no")}
            end)

          DataQuality.level(answers, criteria)
        end

      assert levels == [:low, :low, :low, :medium, :medium, :high, :high, :high]
    end
  end

  describe "score_text/2 and score_description/2" do
    test "a count when every criterion is answered" do
      answers = %{"a" => "yes", "b" => "no", "c" => "yes"}
      assert DataQuality.score_text(answers, @criteria) == "2/3"
      assert DataQuality.score_description(answers, @criteria) == "2 of 3 criteria met"
    end

    test "a question mark when one or more are Unknown" do
      assert DataQuality.score_text(%{}, @criteria) == "?/3"
      assert DataQuality.score_text(%{"a" => "yes", "b" => "yes"}, @criteria) == "?/3"

      assert DataQuality.score_description(%{"a" => "no"}, @criteria) ==
               "unknown, 2 of 3 criteria not answered"
    end

    test "answers to keys not in the list do not complete it" do
      answers = %{"a" => "yes", "b" => "yes", "removed" => "yes"}
      assert DataQuality.score_text(answers, @criteria) == "?/3"
    end

    test "ignores stored keys that are not in the list" do
      answers = %{"a" => "yes", "removed" => "yes", "other" => "yes"}
      assert DataQuality.score(answers, @criteria) == {1, 3}
    end

    test "the denominator is the length of the list" do
      assert {_, 1} = DataQuality.score(%{"a" => "yes"}, Enum.take(@criteria, 1))
      assert {_, total} = DataQuality.score(%{})
      assert total == length(DataQuality.criteria())
    end
  end

  describe "cast/2" do
    test "keeps the yes and no answers to keys of the list" do
      assert DataQuality.cast(%{"a" => "yes", "b" => "no"}, @criteria) ==
               %{"a" => "yes", "b" => "no"}
    end

    test "drops unknown keys and values other than yes or no" do
      answers = %{
        "a" => "unknown",
        "b" => "",
        "c" => "maybe",
        "removed" => "yes",
        "a_b" => "no"
      }

      assert DataQuality.cast(answers, @criteria) == %{}
    end

    test "accepts atom keys and values, and nothing at all" do
      assert DataQuality.cast(%{a: :yes, c: "no"}, @criteria) == %{"a" => "yes", "c" => "no"}
      assert DataQuality.cast(nil, @criteria) == %{}
      assert DataQuality.cast("yes", @criteria) == %{}
    end
  end

  test "the changeset stores the cast answers only" do
    changeset =
      DatasetVersion.changeset(%DatasetVersion{}, %{
        "data_quality" => %{"documented" => "yes", "in_one_piece" => "", "nope" => "yes"}
      })

    assert Ecto.Changeset.get_change(changeset, :data_quality) == %{"documented" => "yes"}
    refute Map.has_key?(errors_on(changeset), :data_quality)
  end

  test "the same answers sent again are no change" do
    version = %DatasetVersion{data_quality: %{"documented" => "yes"}}

    changeset =
      DatasetVersion.changeset(version, %{
        "data_quality" => %{"documented" => "yes", "in_one_piece" => ""}
      })

    refute Map.has_key?(changeset.changes, :data_quality)
  end

  test "diff/3 lists the changed criteria in order" do
    assert DataQuality.diff(%{"c" => "no"}, %{"a" => "yes", "c" => "no"}, @criteria) ==
             [{"A", :unknown, :yes}]

    assert DataQuality.diff(%{"a" => "yes", "b" => "no"}, %{"b" => "yes"}, @criteria) ==
             [{"A", :yes, :unknown}, {"B", :no, :yes}]
  end

  test "if_no_text/1 lowercases the first letter" do
    assert DataQuality.if_no_text(hd(@criteria)) == "If no, you have to: do A"
  end

  test "the criteria have unique keys and every text" do
    keys = Enum.map(DataQuality.criteria(), & &1.key)
    assert keys == Enum.uniq(keys)

    for criterion <- DataQuality.criteria(),
        field <- [:key, :label, :question, :if_no] do
      assert is_binary(Map.fetch!(criterion, field)) and Map.fetch!(criterion, field) != ""
    end
  end
end
