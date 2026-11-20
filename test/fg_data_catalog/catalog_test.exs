defmodule FGDataCatalog.CatalogTest do
  use FGDataCatalog.DataCase, async: true

  import FGDataCatalog.CatalogFixtures

  alias FGDataCatalog.Catalog
  alias FGDataCatalog.Catalog.{Dataset, DatasetVersion, DictionaryEntry, DocLink, YearCount}

  describe "create_dataset/1" do
    test "requires a unique name" do
      assert {:error, changeset} = Catalog.create_dataset(%{name: "  "})
      assert "can't be blank" in errors_on(changeset).name

      assert {:ok, _} = Catalog.create_dataset(%{name: "Kanta lab values"})
      assert {:error, changeset} = Catalog.create_dataset(%{name: "Kanta lab values"})
      assert "has already been taken" in errors_on(changeset).name
    end

    # NOTE(Claude 2026-11-09): optional, trimmed, a few words at most.
    test "takes an optional, trimmed, short description" do
      assert {:ok, %{description: nil}} = Catalog.create_dataset(%{name: "A"})
      assert {:ok, %{description: nil}} = Catalog.create_dataset(%{name: "B", description: "  "})

      assert {:ok, %{description: "Lab test results"}} =
               Catalog.create_dataset(%{name: "C", description: " Lab test results "})

      too_long = String.duplicate("x", Dataset.description_max_length() + 1)
      assert {:error, changeset} = Catalog.create_dataset(%{name: "D", description: too_long})
      assert "should be at most 120 character(s)" in errors_on(changeset).description
    end

    test "a description can be cleared" do
      dataset = dataset_fixture(%{description: "Lab test results"})
      changeset = Catalog.change_dataset(dataset, %{"description" => ""})
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :description, :none) == nil
    end
  end

  describe "create_dataset_version/3" do
    setup do
      %{dataset: dataset_fixture()}
    end

    test "stores every field and reads it back", %{dataset: dataset} do
      version = version_fixture(dataset, %{version: "R14"})
      reloaded = Repo.get!(DatasetVersion, version.id)

      assert %DatasetVersion{
               version: "R14",
               state: :published,
               owning_editor_id: nil,
               tags: ["Longitudinal", "Phenotype"],
               environments: ["Sandbox"],
               access_type: :red,
               formats: ["Flat file"],
               modalities: ["Text"],
               data_quality: %{},
               doc_links: [%DocLink{label: "README", url: "https://example.org/README"}],
               data_dictionary: [
                 %DictionaryEntry{col_name: "FINNGENID"},
                 %DictionaryEntry{col_name: "EVENT_AGE"}
               ],
               coverage_start: 2013,
               coverage_end: 2025,
               yearly_counts: [%YearCount{year: 2013, count: 10}, %YearCount{year: 2025}],
               cohort_size: 500_000,
               lead: "Jane Doe"
             } = reloaded
    end

    test "sets the state, owner and proposals from opts only, never from attrs",
         %{dataset: dataset} do
      someone = user_id("someone@finngen.fi")
      evil = user_id("evil@example.org")

      version =
        version_fixture(
          dataset,
          %{
            state: :published,
            owning_editor_id: evil,
            dataset_name: "Evil",
            dataset_description: "Evil",
            archived_at: DateTime.utc_now(:second)
          },
          state: :draft,
          owning_editor_id: someone
        )

      assert %{state: :draft, owning_editor_id: ^someone} = version
      assert %{dataset_name: nil, dataset_description: nil, archived_at: nil} = version
    end

    test "a new version is a Draft unless told otherwise", %{dataset: dataset} do
      {:ok, version} = Catalog.create_dataset_version(dataset, valid_version_attrs())
      assert version.state == :draft
    end

    # NOTE(Claude Opus 5.5 2026-11-17): only the version and the release date
    # are required; every other field is optional.
    test "requires the version and the release date only", %{dataset: dataset} do
      assert {:error, changeset} = Catalog.create_dataset_version(dataset, %{})
      assert Map.keys(errors_on(changeset)) |> Enum.sort() == [:release_date, :version]

      attrs = %{version: "R1", release_date: ~D[2026-01-01]}
      assert {:ok, version} = Catalog.create_dataset_version(dataset, attrs)
      assert %{access_type: nil, cohort_size: nil, lead: nil} = version
      assert %{coverage_start: nil, coverage_end: nil, omop_integration: nil} = version
      assert %{tags: [], doc_links: [], data_dictionary: [], yearly_counts: []} = version
    end

    # NOTE(Claude 2026-11-09): the lead person / team is optional.
    test "the lead may be left out or blank", %{dataset: dataset} do
      attrs = Map.delete(valid_version_attrs(), :lead)
      assert {:ok, %{lead: nil}} = Catalog.create_dataset_version(dataset, attrs)

      attrs = valid_version_attrs(%{version: "R2", lead: "  "})
      assert {:ok, %{lead: nil}} = Catalog.create_dataset_version(dataset, attrs)
    end

    test "rejects unknown access types", %{dataset: dataset} do
      attrs = valid_version_attrs(%{access_type: "purple"})
      assert {:error, changeset} = Catalog.create_dataset_version(dataset, attrs)
      assert "is invalid" in errors_on(changeset).access_type
    end

    test "cleans up string sets", %{dataset: dataset} do
      version = version_fixture(dataset, %{tags: [" Phenotype ", "", "Phenotype", "Drugs"]})
      assert version.tags == ["Drugs", "Phenotype"]
    end

    test "sorts string sets alphabetically, ignoring case", %{dataset: dataset} do
      version =
        version_fixture(dataset, %{
          tags: ["b", "C", "a", "A", "10", "2"],
          environments: ["Sandbox", "researchers"],
          formats: ["Flat file", "BigQuery DB table"],
          modalities: ["Text", "genes"]
        })

      assert version.tags == ["10", "2", "A", "a", "b", "C"]
      assert version.environments == ["researchers", "Sandbox"]
      assert version.formats == ["BigQuery DB table", "Flat file"]
      assert version.modalities == ["genes", "Text"]
    end

    test "validates cohort size against the FinnGen total", %{dataset: dataset} do
      attrs = valid_version_attrs(%{cohort_size: DatasetVersion.finngen_total() + 1})
      assert {:error, changeset} = Catalog.create_dataset_version(dataset, attrs)
      assert "cannot exceed the whole FinnGen total" in errors_on(changeset).cohort_size

      attrs = valid_version_attrs(%{cohort_size: 0})
      assert {:error, changeset} = Catalog.create_dataset_version(dataset, attrs)
      assert "must be greater than 0" in errors_on(changeset).cohort_size
    end

    test "validates the coverage period", %{dataset: dataset} do
      attrs = valid_version_attrs(%{coverage_start: 2025, coverage_end: 2013})
      assert {:error, changeset} = Catalog.create_dataset_version(dataset, attrs)
      assert "must be on or after the start year" in errors_on(changeset).coverage_end
    end

    # NOTE(Claude Opus 5.5 2026-11-17): years, not dates; one year is a period.
    test "stores the coverage as years", %{dataset: dataset} do
      attrs = valid_version_attrs(%{coverage_start: "2020", coverage_end: "2020"})

      assert {:ok, %{coverage_start: 2020, coverage_end: 2020}} =
               Catalog.create_dataset_version(dataset, attrs)

      for {start, message} <- [
            {"201", "must be a year from 1800 to 2100"},
            {"2101", "must be a year from 1800 to 2100"},
            {"2013-01-01", "is invalid"}
          ] do
        attrs = valid_version_attrs(%{version: "R2", coverage_start: start})
        assert {:error, changeset} = Catalog.create_dataset_version(dataset, attrs)
        assert message in errors_on(changeset).coverage_start
      end
    end

    test "validates embedded documents", %{dataset: dataset} do
      attrs =
        valid_version_attrs(%{
          doc_links: [%{label: "README", url: "javascript:alert(1)"}],
          data_dictionary: [%{details: "no column name"}],
          yearly_counts: [%{year: 2020, count: -1}]
        })

      assert {:error, changeset} = Catalog.create_dataset_version(dataset, attrs)
      errors = errors_on(changeset)
      assert [%{url: ["must be an http(s) URL"]}] = errors.doc_links
      assert [%{col_name: ["can't be blank"]}] = errors.data_dictionary
      assert [%{count: ["must be greater than or equal to 0"]}] = errors.yearly_counts
    end

    test "accepts web links, Unix paths, and GCS paths in location entries", %{dataset: dataset} do
      for {given, stored} <- [
            {" https://example.org/data?release=14 ", "https://example.org/data?release=14"},
            {"http://example.org", "http://example.org"},
            {"/research/shared-data/R14/kanta lab", "/research/shared-data/R14/kanta lab"},
            {"~/data/kanta.parquet", "~/data/kanta.parquet"},
            {"gs://example-bucket", "gs://example-bucket"},
            {"gs://fg_lib.red/R14/kanta lab/", "gs://fg_lib.red/R14/kanta lab/"}
          ] do
        attrs = valid_version_attrs(%{version: "v#{System.unique_integer([:positive])}"})
        attrs = Map.put(attrs, :locations, [%{value: given}])
        assert {:ok, version} = Catalog.create_dataset_version(dataset, attrs)
        assert [%{value: ^stored, label: nil}] = version.locations
      end

      for invalid <- [
            "example.org/data",
            "data/kanta.parquet",
            "ftp://example.org/data",
            "https://",
            "https://example.org/data /research/shared-data",
            "/research/shared-data https://example.org/data",
            "/research/shared-data\nhttps://example.org",
            "gs://",
            "gs:///data",
            "gs://ab/data",
            "gs://Finngen/data",
            "gs://-finngen/data",
            "gs://finngen data/kanta",
            "gs://finngen/data\nkanta",
            "gs://finngen/data https://example.org"
          ] do
        attrs = valid_version_attrs(%{locations: [%{value: invalid}]})
        assert {:error, changeset} = Catalog.create_dataset_version(dataset, attrs)

        assert [%{value: ["must be a web link (https://…), a Unix path (/…) or a gs:// path"]}] =
                 errors_on(changeset).locations,
               invalid
      end
    end

    test "locations are optional and every added entry needs a value", %{dataset: dataset} do
      assert {:ok, %{locations: []}} =
               Catalog.create_dataset_version(dataset, valid_version_attrs())

      for entry <- [%{}, %{value: "  "}] do
        attrs = valid_version_attrs(%{locations: [entry]})
        assert {:error, changeset} = Catalog.create_dataset_version(dataset, attrs)
        assert [%{value: ["can't be blank"]}] = errors_on(changeset).locations
      end

      attrs = valid_version_attrs(%{locations: [%{label: "Web page"}]})
      assert {:error, changeset} = Catalog.create_dataset_version(dataset, attrs)

      assert [%{label: ["needs a location to name"], value: ["can't be blank"]}] =
               errors_on(changeset).locations
    end

    test "locations keep their order and labels", %{dataset: dataset} do
      attrs =
        valid_version_attrs(%{
          locations: [
            %{value: "gs://finngen/kanta", label: " Cloud "},
            %{value: "/sandbox/kanta", label: "Sandbox"},
            %{value: "/sandbox/kanta", label: "Alias"}
          ]
        })

      assert {:ok, version} = Catalog.create_dataset_version(dataset, attrs)
      assert Enum.map(version.locations, & &1.label) == ["Cloud", "Sandbox", "Alias"]

      too_long = String.duplicate("x", FGDataCatalog.Catalog.Location.label_max_length() + 1)
      attrs = valid_version_attrs(%{locations: [%{value: "/sandbox/kanta", label: too_long}]})

      assert {:error, changeset} = Catalog.create_dataset_version(dataset, attrs)
      assert [%{label: ["should be at most 40 character(s)"]}] = errors_on(changeset).locations
    end

    # NOTE(Claude 2026-11-04): documentation entries are links or pasted text.
    test "documentation entries can be pasted text", %{dataset: dataset} do
      attrs =
        valid_version_attrs(%{
          doc_links: [%{kind: "text", label: "README", text: "# Title\n\nBody", url: "ignored"}]
        })

      assert {:ok, version} = Catalog.create_dataset_version(dataset, attrs)
      assert [%DocLink{kind: :text, text: "# Title\n\nBody", url: nil}] = version.doc_links

      attrs = valid_version_attrs(%{doc_links: [%{kind: "text", label: "README"}]})
      assert {:error, changeset} = Catalog.create_dataset_version(dataset, attrs)
      assert [%{text: ["can't be blank"]}] = errors_on(changeset).doc_links
    end

    test "version names are unique within a dataset", %{dataset: dataset} do
      version_fixture(dataset, %{version: "R14"})

      assert {:error, changeset} =
               Catalog.create_dataset_version(dataset, valid_version_attrs(%{version: "R14"}))

      assert "has already been taken" in errors_on(changeset).version

      assert {:ok, _} =
               Catalog.create_dataset_version(
                 dataset_fixture(),
                 valid_version_attrs(%{version: "R14"})
               )
    end
  end

  # NOTE(Claude 2026-11-03): the data dictionary and yearly counts as typed in
  # the form, as CSV text.
  # NOTE(Claude Opus 5.5 2026-11-18): the fields that do not apply to a version
  # (see `DatasetVersion.not_applicable_fields/0`) and OMOP-mapped's Not
  # applicable.
  describe "Not applicable fields" do
    setup do
      %{version: version_fixture(dataset_fixture())}
    end

    defp na_change(version, attrs), do: DatasetVersion.changeset(version, attrs)

    test "a new version has none", %{version: version} do
      assert Repo.get!(DatasetVersion, version.id).not_applicable == []
    end

    test "each checkbox marks its field and clears its values", %{version: version} do
      changeset = na_change(version, %{"years_not_applicable" => "true"})
      assert changeset.valid?
      assert {:ok, version} = Repo.update(changeset)

      assert %{
               not_applicable: ["years_coverage"],
               coverage_start: nil,
               coverage_end: nil,
               yearly_counts: [],
               cohort_size: 500_000
             } = Repo.get!(DatasetVersion, version.id)

      {:ok, version} =
        version |> na_change(%{"cohort_size_not_applicable" => "true"}) |> Repo.update()

      assert version.not_applicable == ["years_coverage", "cohort_size"]
      assert version.cohort_size == nil
    end

    test "a checkbox not sent leaves its field as it is", %{version: version} do
      {:ok, version} =
        version
        |> na_change(%{"years_not_applicable" => "true", "cohort_size_not_applicable" => "true"})
        |> Repo.update()

      {:ok, version} =
        version |> na_change(%{"years_not_applicable" => "false"}) |> Repo.update()

      assert version.not_applicable == ["cohort_size"]
    end

    test "a value sent with Not applicable is dropped", %{version: version} do
      changeset =
        na_change(version, %{
          "cohort_size_not_applicable" => "true",
          "cohort_size" => "100",
          "years_not_applicable" => "true",
          "coverage_start" => "2001",
          "yearly_counts_csv" => "2001,x"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :cohort_size) == nil
      assert Ecto.Changeset.get_field(changeset, :coverage_start) == nil
      assert Ecto.Changeset.get_field(changeset, :yearly_counts) == []
    end

    test "the list keeps known names only, in a fixed order", %{version: version} do
      changeset =
        na_change(version, %{
          not_applicable: ["cohort_size", "nope", "years_coverage", "cohort_size"]
        })

      assert Ecto.Changeset.get_change(changeset, :not_applicable) ==
               ["years_coverage", "cohort_size"]

      version = %{version | not_applicable: ["years_coverage"]}

      refute Map.has_key?(
               na_change(version, %{"years_not_applicable" => "true"}).changes,
               :not_applicable
             )
    end

    test "OMOP-mapped may be Not applicable", %{version: version} do
      {:ok, version} =
        version |> na_change(%{"omop_integration" => "not_applicable"}) |> Repo.update()

      assert Repo.get!(DatasetVersion, version.id).omop_integration == :not_applicable
    end

    test "a new version is prefilled with them", %{version: version} do
      {:ok, version} =
        version
        |> na_change(%{
          "cohort_size_not_applicable" => "true",
          "data_quality" => %{"documented" => "na"}
        })
        |> Repo.update()

      params = Catalog.new_version_params(version)
      assert params["not_applicable"] == ["cohort_size"]
      assert params["data_quality"] == %{"documented" => "na"}
    end
  end

  describe "CSV entry of the data dictionary and yearly counts" do
    setup do
      %{version: version_fixture(dataset_fixture())}
    end

    defp csv_changeset(version, attrs), do: Catalog.change_dataset_version(version, attrs)

    test "replaces the entries, skipping a header row and blank lines", %{version: version} do
      years = Enum.map_join(1953..2022, "\n", &"#{&1},#{&1 - 1900}")

      changeset =
        csv_changeset(version, %{
          "data_dictionary_csv" => ~s(Column,Details\nFINNGENID,Id\n\nAGE,"Age, in years"\nSEX),
          "yearly_counts_csv" => "year,count\n" <> years
        })

      assert changeset.valid?
      version = Ecto.Changeset.apply_changes(changeset)

      assert version.data_dictionary == [
               %DictionaryEntry{col_name: "FINNGENID", details: "Id"},
               %DictionaryEntry{col_name: "AGE", details: "Age, in years"},
               %DictionaryEntry{col_name: "SEX", details: nil}
             ]

      assert length(version.yearly_counts) == 70
      assert hd(version.yearly_counts) == %YearCount{year: 1953, count: 53}
    end

    # NOTE(Claude 2026-11-06): as pasted from a spreadsheet.
    test "accepts tab-separated text", %{version: version} do
      changeset =
        csv_changeset(version, %{
          "data_dictionary_csv" => "column\tdetails\nAGE\tAge, in years",
          "yearly_counts_csv" => "2013\t10\n2014\t12\n"
        })

      assert changeset.valid?
      version = Ecto.Changeset.apply_changes(changeset)

      assert version.data_dictionary == [
               %DictionaryEntry{col_name: "AGE", details: "Age, in years"}
             ]

      assert version.yearly_counts == [
               %YearCount{year: 2013, count: 10},
               %YearCount{year: 2014, count: 12}
             ]
    end

    # NOTE(Claude 2026-11-09): a quoted value may span lines, and is quoted
    # again when written back for editing.
    test "keeps line breaks in quoted details", %{version: version} do
      changeset =
        csv_changeset(version, %{
          "data_dictionary_csv" => ~s(AGE,"Age in years\nat baseline"\nSEX,Sex)
        })

      assert changeset.valid?
      version = Ecto.Changeset.apply_changes(changeset)

      assert version.data_dictionary == [
               %DictionaryEntry{col_name: "AGE", details: "Age in years\nat baseline"},
               %DictionaryEntry{col_name: "SEX", details: "Sex"}
             ]

      assert DatasetVersion.embed_to_csv(:data_dictionary, version.data_dictionary) ==
               ~s(AGE,"Age in years\nat baseline"\nSEX,Sex)
    end

    test "empty text clears the entries", %{version: version} do
      changeset = csv_changeset(version, %{"yearly_counts_csv" => " \n"})
      assert Ecto.Changeset.apply_changes(changeset).yearly_counts == []
    end

    test "without CSV text the entries are left alone", %{version: version} do
      changeset = csv_changeset(version, %{"lead" => "Someone"})
      assert Ecto.Changeset.apply_changes(changeset).yearly_counts == version.yearly_counts
    end

    test "reports entry errors by line on the CSV field", %{version: version} do
      changeset =
        csv_changeset(version, %{
          "data_dictionary_csv" => "A,ok\n,no column",
          "yearly_counts_csv" => "2013,10\n\n2014,-1\n2015,many\n2013,5\n2016"
        })

      errors = errors_on(changeset)
      assert errors.data_dictionary_csv == ["line 2: column can't be blank"]

      assert Enum.sort(errors.yearly_counts_csv) == [
               "line 3: count must be greater than or equal to 0",
               "line 4: count is invalid",
               "line 6: count can't be blank",
               "year 2013 is on more than one line (lines 1, 5)"
             ]
    end

    test "reports malformed CSV and too many values", %{version: version} do
      errors =
        errors_on(
          csv_changeset(version, %{
            "data_dictionary_csv" => "A,b,c",
            "yearly_counts_csv" => ~s(2013,10\n"2014,1)
          })
        )

      assert [too_many] = errors.data_dictionary_csv
      assert too_many =~ "line 1: expected at most 2 values (column, details), got 3"
      assert errors.yearly_counts_csv == ["line 2: a quoted value is not closed"]
    end

    test "the CSV shown for editing reads back as the same entries", %{version: version} do
      version = %{
        version
        | data_dictionary: [%DictionaryEntry{col_name: "X", details: ~s(say "hi", then go)}]
      }

      csv = DatasetVersion.embed_to_csv(:data_dictionary, version.data_dictionary)
      assert csv == ~s(X,"say ""hi"", then go")
      changeset = csv_changeset(version, %{"data_dictionary_csv" => csv})
      assert Ecto.Changeset.apply_changes(changeset).data_dictionary == version.data_dictionary
    end
  end

  describe "create_dataset_with_version/2" do
    test "creates the dataset and its first version" do
      attrs = %{name: "New dataset", versions: [valid_version_attrs(%{version: "R14"})]}

      assert {:ok, dataset} = Catalog.create_dataset_with_version(attrs)
      # NOTE(Claude 2026-11-16): a Draft unless told otherwise.
      assert [%DatasetVersion{version: "R14", state: :draft}] = dataset.versions
      assert Catalog.list_published_datasets() == []

      assert [%{name: "New dataset", versions: [%{version: "R14"}]}] =
               Catalog.list_datasets(scope_fixture(:editor))
    end

    test "state and owning_editor_id come from opts, not attrs" do
      someone = user_id("someone@finngen.fi")
      evil = user_id("evil@x.org")

      attrs = %{
        name: "Draft dataset",
        versions: [valid_version_attrs(%{state: :published, owning_editor_id: evil})]
      }

      assert {:ok, dataset} =
               Catalog.create_dataset_with_version(attrs,
                 state: :draft,
                 owning_editor_id: someone
               )

      assert [%{state: :draft, owning_editor_id: ^someone}] = dataset.versions
    end

    test "requires exactly one valid version and saves nothing otherwise" do
      assert {:error, changeset} = Catalog.create_dataset_with_version(%{name: "No version"})
      assert "can't be blank" in errors_on(changeset).versions

      attrs = %{name: "Two", versions: [valid_version_attrs(), valid_version_attrs()]}
      assert {:error, changeset} = Catalog.create_dataset_with_version(attrs)
      assert "should have 1 item(s)" in errors_on(changeset).versions

      attrs = %{name: "Bad version", versions: [valid_version_attrs(%{release_date: nil})]}
      assert {:error, changeset} = Catalog.create_dataset_with_version(attrs)
      assert [%{release_date: ["can't be blank"]}] = errors_on(changeset).versions

      assert Repo.aggregate(FGDataCatalog.Catalog.Dataset, :count) == 0
    end

    test "rejects a name that already exists" do
      dataset_fixture(%{name: "Taken"})
      attrs = %{name: "Taken", versions: [valid_version_attrs()]}
      assert {:error, changeset} = Catalog.create_dataset_with_version(attrs)
      assert "has already been taken" in errors_on(changeset).name
    end
  end

  # NOTE(Claude 2026-11-04): the source of the tag autocomplete.
  describe "list_tags/0" do
    test "lists the distinct tags of all versions, sorted case-insensitively" do
      dataset = dataset_fixture()
      version_fixture(dataset, %{version: "R13", tags: ["Phenotype", "drugs"]})
      version_fixture(dataset, %{version: "R14", tags: ["Phenotype", "Biobank"]})

      assert Catalog.list_tags() == ["Biobank", "drugs", "Phenotype"]
    end

    # NOTE(Claude 2026-11-06): archived versions no longer feed the autocompletes.
    test "leaves out the values of archived versions" do
      dataset = dataset_fixture()
      version_fixture(dataset, %{version: "R13", tags: ["kept"], modalities: ["Text"]})

      archived =
        version_fixture(dataset, %{version: "R14", tags: ["gone"], modalities: ["Images"]})

      {:ok, _} = Catalog.archive_version(scope_fixture(:editor), archived)

      assert Catalog.list_tags() == ["kept"]
      assert Catalog.list_modalities() == ["Text"]
    end
  end

  describe "list_modalities/0 and list_formats/0" do
    test "list the distinct values of all versions, sorted case-insensitively" do
      dataset = dataset_fixture()

      version_fixture(dataset, %{
        version: "R13",
        modalities: ["Text", "genes"],
        formats: ["Parquet"]
      })

      version_fixture(dataset, %{
        version: "R14",
        modalities: ["Text"],
        formats: ["CSV.gz", "Parquet"]
      })

      assert Catalog.list_modalities() == ["genes", "Text"]
      assert Catalog.list_formats() == ["CSV.gz", "Parquet"]
    end
  end

  describe "list_published_datasets/0" do
    test "orders datasets by name and versions newest first by release date" do
      b = dataset_fixture(%{name: "B dataset"})
      a = dataset_fixture(%{name: "A dataset"})

      # NOTE(Claude 2026-11-02): "R9" sorts after "R14" as a string; release date must win.
      version_fixture(a, %{version: "R9", release_date: ~D[2022-01-01]})
      version_fixture(a, %{version: "R14", release_date: ~D[2026-03-13]})
      version_fixture(a, %{version: "R12", release_date: ~D[2024-06-01]})
      version_fixture(b, %{version: "R1", release_date: ~D[2020-01-01]})

      assert [%{name: "A dataset", versions: versions}, %{name: "B dataset"}] =
               Catalog.list_published_datasets()

      assert Enum.map(versions, & &1.version) == ["R14", "R12", "R9"]
    end

    test "hides drafts and datasets with no published version" do
      published = dataset_fixture(%{name: "Published"})
      version_fixture(published, %{version: "R13", release_date: ~D[2025-01-01]})
      version_fixture(published, %{version: "R14", release_date: ~D[2026-01-01]}, state: :draft)

      draft_only = dataset_fixture(%{name: "Draft only"})
      version_fixture(draft_only, %{}, state: :draft)

      _no_versions = dataset_fixture(%{name: "No versions"})

      assert [%{name: "Published", versions: [%{version: "R13"}]}] =
               Catalog.list_published_datasets()
    end
  end

  # NOTE(Claude 2026-11-06): the catalog as seen by a viewer.
  describe "list_datasets/1" do
    setup do
      dataset = dataset_fixture(%{name: "A"})
      version_fixture(dataset, %{version: "R1", release_date: ~D[2025-01-01]})

      version_fixture(dataset, %{version: "R2", release_date: ~D[2026-01-01]},
        state: :draft,
        owning_editor_id: user_id("me@finngen.fi")
      )

      theirs = dataset_fixture(%{name: "B"})

      version_fixture(theirs, %{version: "T1"},
        state: :draft,
        owning_editor_id: user_id("them@finngen.fi")
      )

      archived = dataset_fixture(%{name: "Z"})
      version_fixture(archived, %{version: "Z1"}, state: :archived)

      :ok
    end

    defp names_and_versions(scope) do
      for d <- Catalog.list_datasets(scope), do: {d.name, Enum.map(d.versions, & &1.version)}
    end

    test "shows Published versions only to a visitor" do
      assert names_and_versions(nil) == [{"A", ["R1"]}]
      assert names_and_versions(nil) == names_and_versions_published()
    end

    # NOTE(Claude 2026-11-16): every editor sees every Draft, whoever owns it.
    test "adds every Draft for any editor, sorted by release date" do
      # NOTE(Claude 2026-11-09): B's draft (2026-03-13) is released after A's.
      expected = [{"B", ["T1"]}, {"A", ["R2", "R1"]}]
      assert names_and_versions(scope_fixture("me@finngen.fi")) == expected
      assert names_and_versions(scope_fixture("them@finngen.fi")) == expected
      assert names_and_versions(scope_fixture(:editor)) == expected
    end

    # NOTE(Claude 2026-11-09): datasets by latest release date, then name.
    test "orders datasets by their latest release date, newest first" do
      for {name, date} <- [{"D", ~D[2024-01-01]}, {"C", ~D[2025-06-01]}, {"E", ~D[2025-06-01]}] do
        version_fixture(dataset_fixture(%{name: name}), %{version: "1", release_date: date})
      end

      assert Enum.map(Catalog.list_datasets(nil), & &1.name) == ["C", "E", "A", "D"]
    end

    defp names_and_versions_published do
      for d <- Catalog.list_published_datasets(),
          do: {d.name, Enum.map(d.versions, & &1.version)}
    end
  end

  describe "can?/3" do
    # NOTE(Claude 2026-11-16): the rule table of DONE.md ("Version states and
    # editors"), transcribed cell by cell: state => actor => allowed actions.
    @table %{
      published: %{
        visitor: [:read],
        other_editor: [:read, :write, :unpublish, :archive],
        owner: [:read, :write, :unpublish, :archive]
      },
      draft: %{
        visitor: [],
        other_editor: [:read, :archive],
        owner: [:read, :write, :publish, :archive]
      },
      archived: %{
        visitor: [],
        other_editor: [:read, :unarchive],
        owner: [:read, :unarchive]
      }
    }

    @actions [:read, :write, :publish, :unpublish, :archive, :unarchive]

    for {state, actors} <- @table, {actor, allowed} <- actors, action <- @actions do
      @state state
      @actor actor
      @action action
      @allowed action in allowed

      test "#{state} × #{actor} × #{action}: #{if @allowed, do: "allowed", else: "refused"}" do
        owner = user_fixture("owner@finngen.fi")
        version = %DatasetVersion{state: @state, owning_editor_id: owner.id}

        scope =
          case @actor do
            :visitor -> nil
            :other_editor -> scope_fixture(:other_editor)
            :owner -> FGDataCatalog.Accounts.Scope.for_user(owner)
          end

        assert Catalog.can?(scope, @action, version) == @allowed
      end
    end

    test "a version without an owning editor has no owner" do
      version = %DatasetVersion{state: :draft, owning_editor_id: nil}
      scope = scope_fixture(:editor)

      refute Catalog.can?(scope, :write, version)
      refute Catalog.can?(scope, :publish, version)
      assert Catalog.can?(scope, :archive, version)
    end
  end

  describe "state transitions" do
    setup do
      dataset = dataset_fixture(%{name: "Transitions"})
      %{dataset: dataset, me: scope_fixture(:editor), other: scope_fixture(:other_editor)}
    end

    test "unpublish makes a Published version a Draft owned by whoever does it",
         %{dataset: dataset, other: other} do
      version = version_fixture(dataset, %{}, owning_editor_id: user_id(:editor))

      assert {:ok, %{state: :draft}} = Catalog.unpublish_dataset_version(other, version)
      assert %{state: :draft, owning_editor_id: id} = Repo.get!(DatasetVersion, version.id)
      assert id == user_id(:other_editor)
    end

    test "unarchive makes an Archived version a Draft owned by whoever does it",
         %{dataset: dataset, me: me, other: other} do
      version = version_fixture(dataset, %{}, owning_editor_id: user_id(:editor))

      assert {:ok, %{state: :archived, archived_at: %DateTime{}}} =
               Catalog.archive_version(me, version)

      assert {:ok, _} = Catalog.unarchive_version(other, version)
      reloaded = Repo.get!(DatasetVersion, version.id)
      assert %{state: :draft, archived_at: nil} = reloaded
      assert reloaded.owning_editor_id == user_id(:other_editor)
    end

    test "publish and archive leave the owner as it is", %{dataset: dataset, me: me, other: other} do
      draft = version_fixture(dataset, %{}, state: :draft, owning_editor_id: user_id(:editor))

      assert {:ok, %{state: :published}} = Catalog.publish_dataset_version(me, draft)
      assert {:ok, %{state: :archived}} = Catalog.archive_version(other, draft)
      assert Repo.get!(DatasetVersion, draft.id).owning_editor_id == user_id(:editor)
    end

    test "taking over someone else's Draft: archive it, then unarchive it",
         %{dataset: dataset, other: other} do
      draft = version_fixture(dataset, %{}, state: :draft, owning_editor_id: user_id(:editor))

      assert {:error, :unauthorized} = Catalog.publish_dataset_version(other, draft)
      assert {:ok, _} = Catalog.archive_version(other, draft)
      assert {:ok, _} = Catalog.unarchive_version(other, draft)
      assert {:ok, %{state: :published}} = Catalog.publish_dataset_version(other, draft)
    end

    test "visitors may do nothing", %{dataset: dataset} do
      version = version_fixture(dataset)

      assert {:error, :unauthorized} = Catalog.unpublish_dataset_version(nil, version)
      assert {:error, :unauthorized} = Catalog.archive_version(nil, version)

      assert {:error, :unauthorized} =
               Catalog.update_dataset_row(dataset, %{}, version, %{lead: "X"}, scope: nil)

      assert Repo.get!(DatasetVersion, version.id).state == :published
    end

    # NOTE(Claude 2026-11-16): the check is made on the version as it is in the
    # database when the change is saved, not on the struct the page holds.
    test "the check reads the version from the database, not the given struct",
         %{dataset: dataset, me: me, other: other} do
      draft = version_fixture(dataset, %{}, state: :draft, owning_editor_id: user_id(:editor))
      # The other editor takes it over; `draft` still shows me as its owner.
      {:ok, _} = Catalog.archive_version(other, draft)
      {:ok, _} = Catalog.unarchive_version(other, draft)

      assert {:error, :unauthorized} =
               Catalog.update_dataset_row(dataset, %{}, draft, %{lead: "Mine"}, scope: me)

      assert {:error, :unauthorized} = Catalog.publish_dataset_version(me, draft)
      assert %{lead: "Jane Doe", state: :draft} = Repo.get!(DatasetVersion, draft.id)

      # And the other way: a stale Published struct of a version now archived.
      published = version_fixture(dataset, %{version: "P"})
      {:ok, _} = Catalog.archive_version(other, published)

      assert {:error, :unauthorized} =
               Catalog.update_dataset_row(dataset, %{}, published, %{lead: "X"}, scope: me)

      assert {:error, :unauthorized} = Catalog.unpublish_dataset_version(me, published)
      assert {:error, :unauthorized} = Catalog.archive_version(me, published)
    end

    test "a refused change records nothing in the changelog", %{dataset: dataset, other: other} do
      draft = version_fixture(dataset, %{}, state: :draft, owning_editor_id: user_id(:editor))
      last = FGDataCatalog.Changelog.last_change_id()

      assert {:error, :unauthorized} =
               Catalog.update_dataset_row(dataset, %{}, draft, %{lead: "X"}, scope: other)

      assert FGDataCatalog.Changelog.last_change_id() == last
    end

    test "list_archived_versions/0 lists the Archived versions only",
         %{dataset: dataset, me: me} do
      kept = version_fixture(dataset, %{version: "Kept"})
      gone = version_fixture(dataset, %{version: "Gone"})
      {:ok, _} = Catalog.archive_version(me, gone)

      assert [%{id: id}] = Catalog.list_archived_versions()
      assert id == gone.id
      refute id == kept.id
    end
  end

  # NOTE(Claude 2026-11-16): a Draft's edits of the dataset's name and
  # description stay off the Published versions until it is published.
  describe "dataset name and description through a Draft" do
    setup do
      dataset = dataset_fixture(%{name: "Original", description: "Old words"})
      published = version_fixture(dataset, %{version: "R1", release_date: ~D[2025-01-01]})

      draft =
        version_fixture(dataset, %{version: "R2", release_date: ~D[2026-01-01]},
          state: :draft,
          owning_editor_id: user_id(:editor)
        )

      %{dataset: dataset, published: published, draft: draft, me: scope_fixture(:editor)}
    end

    test "are stored on the Draft, not on the dataset, while a Published version exists",
         %{dataset: dataset, draft: draft, me: me} do
      assert {:ok, %{dataset: stored, version: version}} =
               Catalog.update_dataset_row(
                 dataset,
                 %{name: "Renamed", description: ""},
                 draft,
                 %{},
                 scope: me
               )

      assert %{name: "Original", description: "Old words"} = stored
      assert %{name: "Original"} = Repo.get!(Dataset, dataset.id)
      assert %{dataset_name: "Renamed", dataset_description: ""} = version

      assert %{name: "Renamed", description: nil} =
               Catalog.proposed_dataset(Repo.get!(Dataset, dataset.id), version)

      # Visitors see the dataset's own values.
      assert [%{name: "Original", versions: [%{version: "R1"}]}] =
               Catalog.list_published_datasets()
    end

    test "are applied to the dataset on publish, and cleared from the version",
         %{dataset: dataset, draft: draft, me: me} do
      {:ok, _} = Catalog.update_dataset_row(dataset, %{name: "Renamed"}, draft, %{}, scope: me)
      assert {:ok, published} = Catalog.publish_dataset_version(me, draft)

      assert %{dataset_name: nil, dataset_description: nil} = published
      assert %{name: "Renamed", description: "Old words"} = Repo.get!(Dataset, dataset.id)
    end

    test "publish is refused if another dataset took the name meanwhile",
         %{dataset: dataset, draft: draft, me: me} do
      {:ok, _} = Catalog.update_dataset_row(dataset, %{name: "Wanted"}, draft, %{}, scope: me)
      dataset_fixture(%{name: "Wanted"})

      assert {:error, %Ecto.Changeset{data: %Dataset{}} = changeset} =
               Catalog.publish_dataset_version(me, draft)

      assert %{name: ["has already been taken"]} = errors_on(changeset)
      assert %{state: :draft, dataset_name: "Wanted"} = Repo.get!(DatasetVersion, draft.id)
      assert %{name: "Original"} = Repo.get!(Dataset, dataset.id)
    end

    test "are validated like the dataset's own", %{dataset: dataset, draft: draft, me: me} do
      dataset_fixture(%{name: "Taken"})

      for {attrs, field} <- [
            {%{name: ""}, :name},
            {%{name: "Taken"}, :name},
            {%{description: String.duplicate("x", 200)}, :description}
          ] do
        assert {:error, %Ecto.Changeset{data: %Dataset{}} = changeset} =
                 Catalog.update_dataset_row(dataset, attrs, draft, %{}, scope: me)

        assert Map.has_key?(errors_on(changeset), field)
      end

      assert %{dataset_name: nil, dataset_description: nil} = Repo.get!(DatasetVersion, draft.id)
    end

    test "an edit back to the dataset's values clears the proposal",
         %{dataset: dataset, draft: draft, me: me} do
      {:ok, %{version: draft}} =
        Catalog.update_dataset_row(dataset, %{name: "Renamed"}, draft, %{}, scope: me)

      {:ok, %{version: draft}} =
        Catalog.update_dataset_row(dataset, %{name: "Original"}, draft, %{}, scope: me)

      assert draft.dataset_name == nil
    end

    test "change the dataset directly when it has no Published version",
         %{dataset: dataset, published: published, draft: draft, me: me} do
      {:ok, _} = Catalog.archive_version(me, published)
      {:ok, _} = Catalog.update_dataset_row(dataset, %{name: "Direct"}, draft, %{}, scope: me)

      assert %{name: "Direct"} = Repo.get!(Dataset, dataset.id)
      assert %{dataset_name: nil} = Repo.get!(DatasetVersion, draft.id)
    end

    test "change the dataset directly when edited through a Published version",
         %{dataset: dataset, published: published, me: me} do
      {:ok, _} = Catalog.update_dataset_row(dataset, %{name: "Direct"}, published, %{}, scope: me)
      assert %{name: "Direct"} = Repo.get!(Dataset, dataset.id)
    end
  end

  describe "dataset_name_holder/2 and get_dataset_for_new_version/2" do
    test "any editor may add a version to a dataset whose versions are all archived" do
      dataset = dataset_fixture(%{name: "Gone"})
      version = version_fixture(dataset, %{version: "G1"})
      {:ok, _} = Catalog.archive_version(scope_fixture(:other_editor), version)

      assert {:archived, %{id: id}} = Catalog.dataset_name_holder("Gone", scope_fixture(:editor))
      assert id == dataset.id

      assert {%{id: ^id}, %{version: "G1"}} =
               Catalog.get_dataset_for_new_version(dataset.id, scope_fixture(:editor))

      assert Catalog.get_dataset_for_new_version(dataset.id, nil) == nil
    end

    test "prefill from the newest version that is not archived, a Draft included" do
      dataset = dataset_fixture()
      version_fixture(dataset, %{version: "Old", release_date: ~D[2024-01-01]})
      draft = version_fixture(dataset, %{version: "Draft", release_date: ~D[2025-01-01]})
      newest = version_fixture(dataset, %{version: "New", release_date: ~D[2026-01-01]})
      {:ok, _} = Catalog.archive_version(scope_fixture(:editor), newest)
      {:ok, _} = Catalog.unpublish_dataset_version(scope_fixture(:editor), draft)

      assert {_dataset, %{version: "Draft"}} =
               Catalog.get_dataset_for_new_version(dataset.id, scope_fixture(:other_editor))
    end

    test "a dataset with only Drafts is listed for editors, unpublished for visitors" do
      dataset = dataset_fixture(%{name: "Drafty"})
      version_fixture(dataset, %{}, state: :draft)

      assert {:listed, _} = Catalog.dataset_name_holder("Drafty", scope_fixture(:editor))
      assert {:unpublished, _} = Catalog.dataset_name_holder("Drafty", nil)
    end
  end
end
