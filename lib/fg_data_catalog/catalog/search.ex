defmodule FGDataCatalog.Catalog.Search do
  @moduledoc """
  Free-text search over loaded datasets (as returned by
  `FGDataCatalog.Catalog.list_datasets/1`), done in memory.

  A query is split into words; a dataset matches if every word occurs, ignoring
  case, in its name, its description, or in one of its versions' version string, tags,
  environments, access type, modalities, formats, OMOP mapping,
  documentation labels or maintainer (`lead`). A matching dataset keeps all
  its versions.

  NOTE(Claude Opus 5.5 2026-11-17): the maintainer is searched only with the
  `maintainer: true` option (for signed-in users), as visitors do not see it.
  """

  # NOTE(Claude 2026-11-06): the catalog is small and already loaded, so
  # searching it in memory avoids a query per keystroke.

  alias FGDataCatalog.Catalog.DatasetVersion

  @doc """
  Keeps the datasets matching `query`. A blank query keeps them all.

  Options: `maintainer: true` also searches the versions' maintainer (`lead`),
  which visitors do not see; off by default.
  """
  def filter(datasets, query, opts \\ []) do
    maintainer? = Keyword.get(opts, :maintainer, false)

    case words(query) do
      [] -> datasets
      words -> Enum.filter(datasets, &matches?(&1, words, maintainer?))
    end
  end

  @doc """
  Keeps the datasets that have a version carrying every tag in `tags`
  (exactly, case included). No tags keeps them all.
  """
  # NOTE(Claude 2026-11-12): the tag filter (tags clicked in the table). One
  # version must have all the tags, so that the row of a clicked chip always
  # stays, whichever version it belongs to.
  def filter_tags(datasets, []), do: datasets

  def filter_tags(datasets, tags) do
    Enum.filter(datasets, fn dataset ->
      Enum.any?(dataset.versions, fn version -> Enum.all?(tags, &(&1 in version.tags)) end)
    end)
  end

  @doc "The words of `query`, downcased. `nil` has none."
  def words(nil), do: []
  def words(query) when is_binary(query), do: query |> String.downcase() |> String.split()

  defp matches?(dataset, words, maintainer?) do
    text = haystack(dataset, maintainer?)
    Enum.all?(words, &String.contains?(text, &1))
  end

  # NOTE(Claude 2026-11-06): one text per dataset, its values separated by a
  # newline so that a word cannot match across two values.
  defp haystack(dataset, maintainer?) do
    [
      dataset.name,
      dataset.description
      | Enum.flat_map(dataset.versions, &version_values(&1, maintainer?))
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join("\n", &(&1 |> to_string() |> String.downcase()))
  end

  defp version_values(%DatasetVersion{} = v, maintainer?) do
    # NOTE(Claude 2026-11-16): with the dataset name and description a Draft
    # proposes (seen by editors only, as the Draft is).
    [v.version, access_type_text(v.access_type), omop_text(v.omop_integration)] ++
      if(maintainer?, do: [v.lead], else: []) ++
      [v.dataset_name, v.dataset_description] ++
      v.tags ++
      v.environments ++
      v.modalities ++
      v.formats ++
      Enum.map(v.doc_links, & &1.label) ++
      Enum.flat_map(v.locations, &[&1.label, &1.value])
  end

  defp access_type_text(nil), do: nil
  defp access_type_text(:public), do: "public"
  defp access_type_text(type), do: "#{type} account"

  # NOTE(Claude 2026-11-10): "omop" finds the OMOP-mapped versions.
  defp omop_text(:yes), do: "omop-mapped"
  defp omop_text(_), do: nil
end
