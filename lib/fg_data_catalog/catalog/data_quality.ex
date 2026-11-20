defmodule FGDataCatalog.Catalog.DataQuality do
  @moduledoc """
  The data quality score of a dataset version: how much preparation it needs
  before it can be used, as a list of yes/no criteria, shown as a count of
  the criteria met (e.g. `3/7`).

  The criteria are defined once, here (`criteria/0`): the forms, the catalog's
  modal, the score and the casting all read this list. Add or remove a
  criterion by editing it; nothing else needs to change, and no migration.

  Every version is scored against the current list. Its answers are stored in
  `DatasetVersion.data_quality`, a map from criterion key to `"yes"`, `"no"`
  or `"na"` (Not applicable); an absent key is Unknown. So a new criterion is
  Unknown everywhere, and the stored answers of a removed one are ignored.
  Never reuse the key of a removed criterion for a different question.

  NOTE(Claude Opus 5.5 2026-11-18): Not applicable is for datasets the
  question does not fit (e.g. not keyed by individuals): such a criterion is
  left out of the score, which counts the applicable criteria only (e.g.
  `3/5`). Unknown means nobody has answered yet.
  """

  # NOTE(Claude 2026-11-16): keys are strings, so that params are compared
  # without `String.to_atom/1`. The texts are final (see DONE.md, "Data quality
  # score").
  @criteria [
    %{
      key: "in_one_piece",
      label: "In one piece",
      question:
        "Is all the released data of this kind in one table, with no batches, " <>
          "cohorts or files to stack?",
      if_no: "Find the other pieces and align them before stacking"
    },
    %{
      key: "keyed_by_finngenid",
      label: "Keyed by FINNGENID",
      question: "Does every row carry a FINNGENID?",
      if_no: "Map sample or other IDs first, and lose the rows that don't map"
    },
    %{
      key: "only_useful_columns",
      label: "Only useful columns",
      question:
        "Is every column populated and meant for analysis (no empty, duplicated " <>
          "or debug columns)?",
      if_no: "Work out which columns to drop"
    },
    %{
      key: "consistent_values",
      label: "Consistent values",
      question:
        "Is the same thing always recorded the same way across sources, batches " <>
          "and years: one unit and scale per measurement, one coding system per " <>
          "column, no free text to parse?",
      if_no: "Harmonise units, scales and codes, or extract values from text"
    },
    %{
      key: "quality_checked",
      label: "Quality-checked",
      question:
        "Have known errors, duplicates and contradictions been removed or " <>
          "flagged in the data itself?",
      if_no: "Run their own QC and deduplication"
    },
    %{
      key: "documented",
      label: "Documented",
      question:
        "Is there a description, in English and linked from this entry, of " <>
          "every column, its codes, and what one row represents?",
      if_no: "Reverse-engineer the data or ask the data owner"
    },
    %{
      key: "readable_without_codebook",
      label: "Readable without a codebook",
      question:
        "Can the values be read as they are: plain labels or a standard " <>
          "vocabulary (ICD-10, ATC, OMOP…), with missing values left empty and " <>
          "not given a code?",
      if_no: "Translate values from a codebook before the data can be read or summarised"
    }
  ]

  @answers ~w(yes no na)

  @doc "The current criteria, in order: `%{key, label, question, if_no}`."
  def criteria, do: @criteria

  @doc """
  Keeps the answers of `criteria` only, as `"yes"`, `"no"` or `"na"` under
  their string key; drops everything else (`"unknown"`, `""`, unknown keys). Keys and
  values may be atoms or strings.

      iex> cast(%{"documented" => "yes", "quality_checked" => "", "x" => "yes", in_one_piece: :no})
      %{"documented" => "yes", "in_one_piece" => "no"}

      iex> cast(nil)
      %{}
  """
  def cast(answers, criteria \\ @criteria)

  def cast(answers, criteria) when is_map(answers) do
    keys = MapSet.new(criteria, & &1.key)

    for {key, value} <- answers,
        key = to_string(key),
        value = to_string(value),
        key in keys and value in @answers,
        into: %{},
        do: {key, value}
  end

  def cast(_answers, _criteria), do: %{}

  @doc """
  The answer to criterion `key` in `answers` (stored, or raw form params):
  `:yes`, `:no`, `:na` (Not applicable) or `:unknown`.
  """
  def answer(answers, key) when is_map(answers) do
    case Map.get(answers, key) do
      value when value in ["yes", :yes] -> :yes
      value when value in ["no", :no] -> :no
      value when value in ["na", :na] -> :na
      _ -> :unknown
    end
  end

  def answer(_answers, _key), do: :unknown

  @doc """
  The score of `answers`: `{met, applicable}`, the number of `criteria`
  answered Yes, and the number of `criteria` not answered Not applicable.
  Unknown counts as No; answers to keys not in `criteria` never count.
  """
  # NOTE(Claude Opus 5.5 2026-11-18): Not applicable criteria are left out of
  # the denominator.
  def score(answers, criteria \\ @criteria) do
    {Enum.count(criteria, &(answer(answers, &1.key) == :yes)),
     Enum.count(criteria, &(answer(answers, &1.key) != :na))}
  end

  @doc "Whether every one of `criteria` is answered Not applicable."
  def not_applicable?(answers, criteria \\ @criteria) do
    criteria != [] and Enum.all?(criteria, &(answer(answers, &1.key) == :na))
  end

  @doc """
  The score of `answers` as text, e.g. `"3/7"`, or `"3/5"` with two criteria
  Not applicable; `"?/7"` while one or more criteria are Unknown; `"n/a"` if
  every criterion is Not applicable.
  """
  # NOTE(Claude 2026-11-16): an incomplete score is not shown as a count, so
  # that Unknown is not read as No.
  def score_text(answers, criteria \\ @criteria) do
    {met, total} = score(answers, criteria)

    cond do
      not_applicable?(answers, criteria) -> "n/a"
      unknown_count(answers, criteria) > 0 -> "?/#{total}"
      true -> "#{met}/#{total}"
    end
  end

  @doc """
  The score of `answers` in words, for screen readers: "3 of 7 criteria
  met", "3 of 5 applicable criteria met" (with criteria Not applicable),
  "unknown, 2 of 7 criteria not answered", or "not applicable".
  """
  def score_description(answers, criteria \\ @criteria) do
    {met, total} = score(answers, criteria)
    applicable = if total < length(criteria), do: "applicable criteria", else: "criteria"
    unknown = unknown_count(answers, criteria)

    cond do
      not_applicable?(answers, criteria) ->
        "not applicable"

      unknown > 0 ->
        "unknown, #{unknown} of #{total} #{applicable} not answered"

      true ->
        "#{met} of #{total} #{applicable} met"
    end
  end

  @doc """
  How good the score of `answers` is, for its badge: `:na` if every criterion
  is Not applicable, `:unknown` while one or more criteria are Unknown,
  otherwise `:low`, `:medium` or `:high` by the share of applicable criteria
  met (below 40%, below 70%, the rest; with 7 criteria: 0-2, 3-4, 5-7).
  """
  # NOTE(Claude 2026-11-16): by share, not count, so that it holds when
  # criteria are added or removed.
  def level(answers, criteria \\ @criteria) do
    {met, total} = score(answers, criteria)

    cond do
      # NOTE(Claude Opus 5.5 2026-11-18): first, as `total` is then 0.
      not_applicable?(answers, criteria) -> :na
      unknown_count(answers, criteria) > 0 -> :unknown
      met * 10 < total * 4 -> :low
      met * 10 < total * 7 -> :medium
      true -> :high
    end
  end

  @doc "The number of `criteria` not answered in `answers` (Unknown)."
  def unknown_count(answers, criteria \\ @criteria) do
    Enum.count(criteria, &(answer(answers, &1.key) == :unknown))
  end

  @doc "An answer's label: Yes, No, Not applicable or Unknown."
  def answer_label(:yes), do: "Yes"
  def answer_label(:no), do: "No"
  def answer_label(:na), do: "Not applicable"
  def answer_label(:unknown), do: "Unknown"

  @doc """
  The criteria whose answer differs between `old` and `new`, as
  `{label, old_answer, new_answer}`, in order.
  """
  def diff(old, new, criteria \\ @criteria) do
    for %{key: key, label: label} <- criteria,
        old_answer = answer(old, key),
        new_answer = answer(new, key),
        old_answer != new_answer,
        do: {label, old_answer, new_answer}
  end

  @doc """
  The text shown under a criterion when asked "What if not?": its `if_no`
  text, first letter lowercased.
  """
  def if_no_text(%{if_no: <<first::utf8, rest::binary>>}) do
    "If no, you have to: " <> String.downcase(<<first::utf8>>) <> rest
  end
end
