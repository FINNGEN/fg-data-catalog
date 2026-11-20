defmodule FGDataCatalog.CatalogFixtures do
  @moduledoc """
  Test helpers for creating entities via the `FGDataCatalog.Catalog` context.
  """

  alias FGDataCatalog.Catalog

  def dataset_fixture(attrs \\ %{}, opts \\ []) do
    {:ok, dataset} =
      attrs
      |> Enum.into(%{name: "Dataset #{System.unique_integer([:positive])}"})
      |> Catalog.create_dataset(opts)

    dataset
  end

  def valid_version_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      version: "R#{System.unique_integer([:positive])}",
      release_date: ~D[2026-03-13],
      tags: ["Phenotype", "Longitudinal"],
      environments: ["Sandbox"],
      access_type: :red,
      formats: ["Flat file"],
      modalities: ["Text"],
      doc_links: [%{label: "README", url: "https://example.org/README"}],
      data_dictionary: [
        %{col_name: "FINNGENID", details: "Participant identifier"},
        %{col_name: "EVENT_AGE", details: "Age at event"}
      ],
      coverage_start: 2013,
      coverage_end: 2025,
      yearly_counts: [%{year: 2013, count: 10}, %{year: 2025, count: 100}],
      cohort_size: 500_000,
      lead: "Jane Doe"
    })
  end

  # NOTE(Claude 2026-11-16): Published unless `opts` say otherwise (`state:`,
  # `owning_editor_id:`); the application's own default is a Draft.
  def version_fixture(dataset, attrs \\ %{}, opts \\ []) do
    opts = Keyword.put_new(opts, :state, :published)

    {:ok, version} =
      Catalog.create_dataset_version(dataset, valid_version_attrs(attrs), opts)

    version
  end
end
