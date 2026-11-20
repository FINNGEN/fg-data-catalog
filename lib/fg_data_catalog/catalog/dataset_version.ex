defmodule FGDataCatalog.Catalog.DatasetVersion do
  @moduledoc """
  One release of a dataset. A catalog row shows the latest published version
  of each dataset; older versions are shown when the row is expanded.

  NOTE(Claude 2026-11-16): `state`, `owning_editor_id`, `dataset_name`,
  `dataset_description` and `archived_at` are set by the application, never
  cast from user input. Who may see and do what in each state is
  `FGDataCatalog.Catalog.can?/3`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias FGDataCatalog.Accounts.User

  alias FGDataCatalog.Catalog.{
    CSV,
    DataQuality,
    Dataset,
    DictionaryEntry,
    DocLink,
    Location,
    YearCount
  }

  @access_types [:red, :green, :public]
  # NOTE(Claude 2026-11-10): no more "partial" OMOP mapping.
  # NOTE(Claude Opus 5.5 2026-11-18): Not applicable, for data that cannot be
  # mapped to OMOP (e.g. not about individuals); `nil` stays Unknown.
  @omop_integrations [:yes, :no, :not_applicable]
  # NOTE(Claude 2026-11-16): see `state` below.
  @states [:draft, :published, :archived]

  # NOTE(Claude 2026-11-04): the number of individuals in FinnGen, the common
  # denominator of every version's cohort coverage (versions only store the
  # individuals they cover). Update it here when FinnGen grows.
  @finngen_total 520_210

  # NOTE(Claude Opus 5.5 2026-11-17): the years a coverage period may start or
  # end in. Also stops the edit form, which saves each valid change, from
  # saving the partial years typed on the way ("2", "20", "201").
  @coverage_years 1800..2100

  # NOTE(Claude Opus 5.5 2026-11-18): the fields that may be marked Not
  # applicable in `not_applicable`, in the order they are stored, each with the
  # virtual boolean the forms set it with. `"years_coverage"` is the coverage
  # period and the yearly counts.
  @not_applicable_fields [
    {"years_coverage", :years_not_applicable},
    {"cohort_size", :cohort_size_not_applicable}
  ]

  @doc "The years a coverage period may start or end in."
  def coverage_years, do: @coverage_years

  @doc "The total number of individuals in FinnGen, shared by all datasets."
  def finngen_total, do: @finngen_total

  schema "dataset_versions" do
    field :version, :string
    field :release_date, :date
    # NOTE(Claude 2026-11-16): one state per version (it replaces `status` and
    # `archived_at`): a Draft is seen by editors only, an Archived version is out
    # of the catalog but kept (see `Catalog.can?/3`). New versions are Drafts.
    field :state, Ecto.Enum, values: @states, default: :draft
    # NOTE(Claude 2026-11-16): the editor who moved the version into Draft
    # (created, unpublished or unarchived it), who alone may edit and publish it
    # while it is a Draft. `nil` for the seeds and older data, until an editor
    # moves the version into Draft. Was `submitted_by`.
    belongs_to :owning_editor, User
    # NOTE(Claude 2026-11-16): when the version was archived, for the archive
    # page only: set by `Catalog.archive_version/2`, cleared on unarchive. Never
    # used to decide visibility (that is `state`).
    field :archived_at, :utc_datetime
    # NOTE(Claude 2026-11-16): the dataset name and description proposed by a
    # Draft of a dataset that has a Published version, applied to the dataset
    # when the Draft is published (see `Catalog.update_dataset_row/5`). `nil`:
    # unchanged; a `""` description: cleared.
    field :dataset_name, :string
    field :dataset_description, :string
    field :tags, {:array, :string}, default: []
    field :environments, {:array, :string}, default: []
    field :access_type, Ecto.Enum, values: @access_types
    field :formats, {:array, :string}, default: []
    field :modalities, {:array, :string}, default: []
    # NOTE(Claude 2026-11-16): the answers to the data quality criteria, keyed by
    # criterion key, "yes" or "no"; an absent key is Unknown (see
    # `FGDataCatalog.Catalog.DataQuality`).
    field :data_quality, :map, default: %{}
    # NOTE(Claude 2026-11-10): whether the data is mapped to OMOP ("OMOP-mapped"):
    # yes, no, or unknown (nil).
    field :omop_integration, Ecto.Enum, values: @omop_integrations
    # NOTE(Claude Opus 5.5 2026-11-17): the years coverage, as years (not
    # dates): the version covers its start year to its end year, both
    # included. Either may be unknown (`nil`).
    field :coverage_start, :integer
    field :coverage_end, :integer
    field :cohort_size, :integer
    # NOTE(Claude Opus 5.5 2026-11-18): the fields that do not apply to this
    # version (see `not_applicable_fields/0`), e.g. no cohort coverage for data
    # that is not about FinnGen individuals. Such a field has no value, and is
    # shown as Not applicable, not as Unknown. The forms set it through the
    # virtual booleans below, one per field, so that a form showing only one
    # of the fields leaves the other one as it is.
    field :not_applicable, {:array, :string}, default: []
    field :years_not_applicable, :boolean, virtual: true
    field :cohort_size_not_applicable, :boolean, virtual: true
    field :lead, :string

    embeds_many :locations, Location, on_replace: :delete
    embeds_many :doc_links, DocLink, on_replace: :delete
    embeds_many :data_dictionary, DictionaryEntry, on_replace: :delete
    embeds_many :yearly_counts, YearCount, on_replace: :delete

    # NOTE(Claude 2026-11-03): the data dictionary and the yearly counts are
    # entered as CSV text (see `csv_embeds/0`). Never stored: parsed into the
    # embeds above by `changeset/2`, which also reports their errors here.
    field :data_dictionary_csv, :string, virtual: true
    field :yearly_counts_csv, :string, virtual: true

    belongs_to :dataset, Dataset

    timestamps(type: :utc_datetime)
  end

  @doc """
  The fields that may be marked Not applicable, as `{name, virtual_field}`:
  their name in `not_applicable`, and the virtual boolean the forms set.
  """
  def not_applicable_fields, do: @not_applicable_fields

  @doc "Whether `field` (a name in `not_applicable_fields/0`) is Not applicable to `version`."
  def not_applicable?(%{not_applicable: names}, field) when is_list(names), do: field in names
  def not_applicable?(_version, _field), do: false

  def access_types, do: @access_types
  def omop_integrations, do: @omop_integrations
  def states, do: @states

  # NOTE(Claude 2026-11-03): for each list entered as CSV: its embed, the
  # virtual field holding the text, the columns in order, and the header row
  # that may come first (skipped).
  @csv_embeds [
    {:data_dictionary, :data_dictionary_csv, [:col_name, :details], ~w(column details)},
    {:yearly_counts, :yearly_counts_csv, [:year, :count], ~w(year count)}
  ]

  @doc false
  def csv_embeds, do: @csv_embeds

  @doc """
  Writes the entries of `embed` (structs or changesets) as the CSV text shown
  for editing, without a header row.
  """
  def embed_to_csv(embed, entries) when is_list(entries) do
    {_, _, columns, _} = List.keyfind(@csv_embeds, embed, 0)

    entries
    |> Enum.map(fn
      %Ecto.Changeset{} = changeset -> apply_changes(changeset)
      entry -> entry
    end)
    |> Enum.map(fn entry -> Enum.map(columns, &Map.get(entry, &1)) end)
    |> CSV.dump()
  end

  def embed_to_csv(_embed, _entries), do: ""

  def changeset(version, attrs) do
    {attrs, csv_lines} = attrs |> cast_data_quality() |> parse_csv_params()

    # NOTE(Claude Opus 5.5 2026-11-18): the fields Not applicable first, so
    # that the values sent for them are dropped before they are cast (and
    # validated): see `drop_not_applicable/2`.
    # Only their own params: `cast/3` keeps the params it is given, which
    # `cast_embed/3` reads later.
    na_keys = ~w(not_applicable years_not_applicable cohort_size_not_applicable)

    changeset =
      version
      |> cast(Map.filter(attrs, fn {key, _value} -> to_string(key) in na_keys end), [
        :not_applicable,
        :years_not_applicable,
        :cohort_size_not_applicable
      ])
      |> put_not_applicable()

    attrs = drop_not_applicable(attrs, get_field(changeset, :not_applicable))

    changeset
    |> cast(attrs, [
      :version,
      :release_date,
      :tags,
      :environments,
      :access_type,
      :formats,
      :modalities,
      :data_quality,
      :omop_integration,
      :coverage_start,
      :coverage_end,
      :cohort_size,
      :lead
    ])
    |> cast_embed(:doc_links, sort_param: :doc_links_sort, drop_param: :doc_links_drop)
    |> cast_embed(:locations, sort_param: :locations_sort, drop_param: :locations_drop)
    |> cast_embed(:data_dictionary)
    |> cast_embed(:yearly_counts)
    |> clear_not_applicable()
    # NOTE(Claude Opus 5.5 2026-11-17): only the version and the release date
    # are required (and the dataset's name, see `Dataset`); every other field
    # is optional. The forms mark the required fields (see `DatasetFormComponents`).
    |> validate_required([:version, :release_date])
    |> update_change(:tags, &clean_strings/1)
    |> update_change(:environments, &clean_strings/1)
    |> update_change(:formats, &clean_strings/1)
    |> update_change(:modalities, &clean_strings/1)
    |> validate_number(:cohort_size, greater_than: 0)
    |> validate_cohort_within_total()
    |> validate_coverage_years()
    |> validate_coverage_period()
    |> validate_csv_embeds(csv_lines)
    # NOTE(Claude 2026-11-03): reported on :version, which has an input (the
    # default, :dataset_id, has none).
    |> unique_constraint([:dataset_id, :version], error_key: :version)
  end

  # NOTE(Claude 2026-11-16): keeps only the answers to the current criteria,
  # "yes" or "no" (see `DataQuality.cast/1`), before `cast/3`, so that the same
  # answers sent again are no change.
  defp cast_data_quality(attrs) do
    Enum.reduce([:data_quality, "data_quality"], attrs, fn key, attrs ->
      case attrs do
        %{^key => answers} -> %{attrs | key => DataQuality.cast(answers)}
        _ -> attrs
      end
    end)
  end

  # NOTE(Claude Opus 5.5 2026-11-18): `not_applicable` keeps only the known
  # names, once each, in the order of `@not_applicable_fields` (so that the same
  # names in another order are no change). Then each virtual boolean that was
  # sent adds its field's name, or removes it; a name whose boolean was not
  # sent is left as it is.
  defp put_not_applicable(changeset) do
    names = get_field(changeset, :not_applicable) || []

    names =
      Enum.reduce(@not_applicable_fields, names, fn {name, virtual}, names ->
        case fetch_change(changeset, virtual) do
          {:ok, true} -> [name | names]
          {:ok, _false_or_nil} -> List.delete(names, name)
          :error -> names
        end
      end)

    known = for {name, _virtual} <- @not_applicable_fields, name in names, do: name

    if known == changeset.data.not_applicable,
      do: delete_change(changeset, :not_applicable),
      else: put_change(changeset, :not_applicable, known)
  end

  # NOTE(Claude Opus 5.5 2026-11-18): the params of the fields Not applicable
  # (`names`), dropped: a value sent with Not applicable is ignored, not an
  # error. Its inputs are disabled in the forms, so it is not sent there.
  @not_applicable_params %{
    "years_coverage" => ~w(coverage_start coverage_end yearly_counts yearly_counts_csv),
    "cohort_size" => ~w(cohort_size)
  }

  defp drop_not_applicable(attrs, names) do
    keys = Enum.flat_map(names, &Map.fetch!(@not_applicable_params, &1))
    Map.reject(attrs, fn {key, _value} -> to_string(key) in keys end)
  end

  # NOTE(Claude Opus 5.5 2026-11-18): a field marked Not applicable has no
  # value: marking it clears its value (the changelog keeps the old one).
  defp clear_not_applicable(changeset) do
    names = get_field(changeset, :not_applicable)

    changeset =
      if "years_coverage" in names do
        changeset
        |> put_change(:coverage_start, nil)
        |> put_change(:coverage_end, nil)
        |> put_embed(:yearly_counts, [])
      else
        changeset
      end

    if "cohort_size" in names, do: put_change(changeset, :cohort_size, nil), else: changeset
  end

  # NOTE(Claude 2026-11-03): replaces each CSV text param by the list of entries
  # it holds, for `cast_embed/3`. Returns the params and, per virtual field,
  # either the line of each entry or `{:error, message}`. Only string-keyed
  # (form) params can hold CSV text.
  defp parse_csv_params(attrs) do
    Enum.reduce(@csv_embeds, {attrs, %{}}, fn {embed, csv_field, columns, header},
                                              {attrs, lines} ->
      with text when is_binary(text) <- Map.get(attrs, Atom.to_string(csv_field)),
           {:ok, entries, entry_lines} <- csv_entries(text, columns, header) do
        {Map.put(attrs, Atom.to_string(embed), entries), Map.put(lines, csv_field, entry_lines)}
      else
        {:error, message} -> {attrs, Map.put(lines, csv_field, {:error, message})}
        _no_csv -> {attrs, lines}
      end
    end)
  end

  defp csv_entries(text, columns, header) do
    with {:ok, rows} <- CSV.parse(text) do
      rows
      |> Enum.map(fn {line, fields} -> {line, Enum.map(fields, &String.trim/1)} end)
      |> drop_header(header)
      |> Enum.reduce_while({[], []}, fn {line, fields}, {entries, lines} ->
        if length(fields) > length(columns) do
          {:halt,
           {:error,
            "line #{line}: expected at most #{length(columns)} values " <>
              "(#{Enum.join(header, ", ")}), got #{length(fields)}; " <>
              "put quotes around a value that contains a comma"}}
        else
          entry =
            columns
            |> Enum.map(&Atom.to_string/1)
            |> Enum.zip(fields)
            |> Map.new()

          {:cont, {[entry | entries], [line | lines]}}
        end
      end)
      |> case do
        {:error, message} -> {:error, message}
        {entries, lines} -> {:ok, Enum.reverse(entries), Enum.reverse(lines)}
      end
    else
      {:error, line, message} -> {:error, "line #{line}: #{message}"}
    end
  end

  defp drop_header([{_line, fields} | rest] = rows, header) do
    if Enum.map(fields, &String.downcase/1) == header, do: rest, else: rows
  end

  defp drop_header([], _header), do: []

  # NOTE(Claude 2026-11-03): the entries have no inputs of their own, so their
  # errors are shown on the CSV text, by line.
  defp validate_csv_embeds(changeset, csv_lines) do
    # NOTE(Claude Opus 5.5 2026-11-18): the yearly counts of a version whose
    # years coverage is Not applicable were cleared (see
    # `clear_not_applicable/1`): any text typed for them is ignored.
    csv_lines =
      if not_applicable?(
           %{not_applicable: get_field(changeset, :not_applicable)},
           "years_coverage"
         ),
         do: Map.delete(csv_lines, :yearly_counts_csv),
         else: csv_lines

    Enum.reduce(@csv_embeds, changeset, fn {embed, csv_field, _columns, _header}, changeset ->
      case Map.get(csv_lines, csv_field) do
        nil ->
          changeset

        {:error, message} ->
          add_error(changeset, csv_field, message)

        lines ->
          # NOTE(Claude 2026-11-03): the change also lists the old entries, to
          # be deleted (`:replace`); the parsed ones follow, in order.
          entries =
            changeset |> get_change(embed, []) |> Enum.reject(&(&1.action == :replace))

          entries
          |> Enum.zip(lines)
          |> Enum.flat_map(fn {entry, line} ->
            entry
            |> traverse_errors(&error_message/1)
            |> Enum.flat_map(fn {field, messages} ->
              Enum.map(messages, &"line #{line}: #{column_name(field)} #{&1}")
            end)
          end)
          |> Kernel.++(duplicate_year_errors(embed, entries, lines))
          |> Enum.reduce(changeset, &add_error(&2, csv_field, &1))
      end
    end)
  end

  defp duplicate_year_errors(:yearly_counts, entries, lines) do
    entries
    |> Enum.map(&get_field(&1, :year))
    |> Enum.zip(lines)
    |> Enum.reject(fn {year, _line} -> is_nil(year) end)
    |> Enum.group_by(fn {year, _line} -> year end, fn {_year, line} -> line end)
    |> Enum.filter(fn {_year, lines} -> length(lines) > 1 end)
    |> Enum.sort()
    |> Enum.map(fn {year, lines} ->
      "year #{year} is on more than one line (lines #{Enum.join(lines, ", ")})"
    end)
  end

  defp duplicate_year_errors(_embed, _entries, _lines), do: []

  defp error_message({message, opts}) do
    Enum.reduce(opts, message, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end

  defp column_name(:col_name), do: "column"
  defp column_name(field), do: Atom.to_string(field)

  # NOTE(Claude 2026-11-05): also sorted, so that the stored order does not
  # depend on the order in which the values were typed.
  defp clean_strings(list) do
    list
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> sort_values()
  end

  @doc """
  Sorts the values of a list field (tags, environments, formats, modalities)
  alphabetically, ignoring case; values differing only in case keep a fixed
  order.
  """
  def sort_values(values), do: Enum.sort_by(values, &{String.downcase(&1), &1})

  defp validate_cohort_within_total(changeset) do
    cohort = get_field(changeset, :cohort_size)

    if is_integer(cohort) and cohort > @finngen_total do
      add_error(changeset, :cohort_size, "cannot exceed the whole FinnGen total")
    else
      changeset
    end
  end

  defp validate_coverage_years(changeset) do
    first..last//_ = @coverage_years

    Enum.reduce([:coverage_start, :coverage_end], changeset, fn field, changeset ->
      validate_number(changeset, field,
        greater_than_or_equal_to: first,
        less_than_or_equal_to: last,
        message: "must be a year from #{first} to #{last}"
      )
    end)
  end

  # NOTE(Claude Opus 5.5 2026-11-17): years now; the same year twice is a
  # period of one year.
  defp validate_coverage_period(changeset) do
    from = get_field(changeset, :coverage_start)
    to = get_field(changeset, :coverage_end)

    if is_integer(from) and is_integer(to) and from > to do
      add_error(changeset, :coverage_end, "must be on or after the start year")
    else
      changeset
    end
  end
end
