defmodule FGDataCatalog.ChangelogTest do
  # NOTE(Claude 2026-11-03): tests of the changelog written by the catalog's
  # write functions, and of replaying it. Not async: the PubSub test would
  # receive the broadcasts of other tests.
  use FGDataCatalog.DataCase, async: false

  import FGDataCatalog.CatalogFixtures

  alias FGDataCatalog.Catalog
  alias FGDataCatalog.Catalog.{Dataset, DatasetVersion}
  alias FGDataCatalog.Changelog
  alias FGDataCatalog.Changelog.{ChangeSet, Replay}

  defp change_sets do
    Repo.all(from s in ChangeSet, order_by: s.id, preload: :changes)
  end

  defp new_dataset_params(name) do
    %{
      "name" => name,
      "versions" => %{
        "0" =>
          valid_version_attrs(%{version: "R1"}) |> Map.new(fn {k, v} -> {to_string(k), v} end)
      }
    }
  end

  # NOTE(Claude 2026-11-05): `list_recent_changes/1` groups by change set, newest
  # set first, and limits to the latest changes.
  test "list_recent_changes lists the latest changes, newest change set first" do
    dataset = dataset_fixture()
    version = version_fixture(dataset)

    {:ok, _} =
      Catalog.update_dataset_row(dataset, %{name: "Renamed"}, version, %{lead: "Someone"},
        scope: scope_fixture(:editor)
      )

    all = Changelog.list_recent_changes()
    assert [first | _] = all

    assert Enum.map(all, & &1.change_set_id) ==
             all |> Enum.map(& &1.change_set_id) |> Enum.sort(:desc)

    assert first.change_set.action == "edit row"
    assert Enum.map(all, & &1.id) |> Enum.sort() == Enum.map(Changelog.list_changes(), & &1.id)

    latest = Changelog.list_recent_changes(limit: 2)
    assert length(latest) == 2
    assert Enum.all?(latest, &(&1.change_set.action == "edit row"))
  end

  test "creating a dataset logs both rows as one change set, parent first" do
    {:ok, dataset} =
      Catalog.create_dataset_with_version(new_dataset_params("Kanta"), actor: "alice")

    [version] = dataset.versions

    assert [%ChangeSet{action: "create dataset", actor: "alice", changes: [d, v]}] =
             change_sets()

    assert %{op: :insert, table_name: "datasets", record_id: dataset_id, old_values: nil} = d
    assert dataset_id == dataset.id
    assert d.new_values == Changelog.raw_row(Dataset, dataset.id)
    assert d.new_values["name"] == "Kanta"

    assert %{op: :insert, table_name: "dataset_versions", old_values: nil} = v
    assert v.record_id == version.id
    assert v.new_values == Changelog.raw_row(DatasetVersion, version.id)
    # Raw SQLite values: JSON text for arrays, ISO text for dates.
    assert v.new_values["tags"] == ~s(["Longitudinal","Phenotype"])
    assert v.new_values["release_date"] == "2026-03-13"

    assert_replayable()
  end

  test "editing a row logs only the changed columns, before and after" do
    dataset = dataset_fixture(%{name: "Old name"})
    version = version_fixture(dataset, %{lead: "Jane", tags: ["A"]})

    {:ok, %{dataset: _, version: _}} =
      Catalog.update_dataset_row(
        dataset,
        %{"name" => "New name"},
        version,
        %{"lead" => "Joe", "tags" => ["A", "B"]},
        scope: scope_fixture("bob@finngen.fi")
      )

    assert %ChangeSet{action: "edit row", actor: "bob@finngen.fi", changes: [d, v]} =
             List.last(change_sets())

    assert %{op: :update, table_name: "datasets", record_id: id} = d
    assert id == dataset.id
    assert Map.delete(d.old_values, "updated_at") == %{"name" => "Old name"}
    assert Map.delete(d.new_values, "updated_at") == %{"name" => "New name"}

    assert %{op: :update, table_name: "dataset_versions"} = v
    assert Map.delete(v.old_values, "updated_at") == %{"lead" => "Jane", "tags" => ~s(["A"])}
    assert Map.delete(v.new_values, "updated_at") == %{"lead" => "Joe", "tags" => ~s(["A","B"])}

    assert_replayable()
  end

  test "an edit that changes nothing is not logged and leaves the row as it was" do
    dataset = dataset_fixture()
    version = version_fixture(dataset)
    row_before = Changelog.raw_row(DatasetVersion, version.id)
    sets_before = change_sets()

    # NOTE(Claude 2026-11-03): embeds re-submitted with the same values, as a
    # form does on every change.
    same = %{
      "lead" => version.lead,
      "doc_links" => %{"0" => %{"label" => "README", "url" => "https://example.org/README"}},
      "data_dictionary" => %{
        "0" => %{"col_name" => "FINNGENID", "details" => "Participant identifier"},
        "1" => %{"col_name" => "EVENT_AGE", "details" => "Age at event"}
      }
    }

    assert {:ok, _} =
             Catalog.update_dataset_row(dataset, %{}, version, same,
               scope: scope_fixture(:editor)
             )

    assert change_sets() == sets_before
    assert Changelog.raw_row(DatasetVersion, version.id) == row_before
  end

  test "re-sending the data dictionary and yearly counts as CSV, unchanged, is not logged" do
    dataset = dataset_fixture()
    version = version_fixture(dataset)
    sets_before = change_sets()

    same = %{
      "data_dictionary_csv" =>
        DatasetVersion.embed_to_csv(:data_dictionary, version.data_dictionary),
      "yearly_counts_csv" => DatasetVersion.embed_to_csv(:yearly_counts, version.yearly_counts)
    }

    assert {:ok, _} =
             Catalog.update_dataset_row(dataset, %{}, version, same,
               scope: scope_fixture(:editor)
             )

    assert change_sets() == sets_before
  end

  test "an edit that changes nothing also keeps the old updated_at" do
    version = version_fixture(dataset_fixture())

    # NOTE(Claude 2026-11-03): backdated, bypassing the log on purpose, so that
    # a write now would change updated_at. Hence no assert_replayable/0 here.
    from(v in "dataset_versions", where: v.id == ^version.id)
    |> Repo.update_all(set: [updated_at: "2020-01-01T00:00:00Z"])

    version = Repo.get!(DatasetVersion, version.id)
    row_before = Changelog.raw_row(DatasetVersion, version.id)
    sets_before = change_sets()

    # A changed embed list that ends up identical forces an actual UPDATE.
    links = %{"0" => %{"label" => "README", "url" => "https://example.org/README"}}
    assert Catalog.change_dataset_version(version, %{"doc_links" => links}).changes != %{}

    assert {:ok, _} =
             Catalog.update_dataset_row(
               version_dataset(version),
               %{},
               version,
               %{
                 "doc_links" => links
               },
               scope: scope_fixture(:editor)
             )

    assert Changelog.raw_row(DatasetVersion, version.id) == row_before
    assert change_sets() == sets_before
  end

  defp version_dataset(version), do: Repo.get!(Dataset, version.dataset_id)

  test "a failed edit leaves no trace" do
    dataset = dataset_fixture()
    other = dataset_fixture(%{name: "Taken"})
    version = version_fixture(dataset)
    sets_before = change_sets()

    # The version is valid, the name is not: nothing is saved.
    assert {:error, %Ecto.Changeset{data: %Dataset{}}} =
             Catalog.update_dataset_row(
               dataset,
               %{"name" => other.name},
               version,
               %{
                 "lead" => "Joe"
               },
               scope: scope_fixture(:editor)
             )

    assert {:error, %Ecto.Changeset{data: %DatasetVersion{}}} =
             Catalog.update_dataset_row(
               dataset,
               %{"name" => "Fine"},
               version,
               %{
                 "cohort_size" => "-1"
               },
               scope: scope_fixture(:editor)
             )

    assert change_sets() == sets_before
    assert Repo.get!(Dataset, dataset.id).name == dataset.name
    assert Repo.get!(DatasetVersion, version.id).lead == version.lead
    assert_replayable()
  end

  test "publishing a draft logs the state change" do
    version =
      version_fixture(dataset_fixture(), %{}, state: :draft, owning_editor_id: user_id(:editor))

    {:ok, published} = Catalog.publish_dataset_version(scope_fixture(:editor), version)
    assert published.state == :published

    assert %ChangeSet{action: "publish version", actor: "editor@finngen.fi", changes: [change]} =
             List.last(change_sets())

    assert %{op: :update, record_id: id} = change
    assert id == version.id
    assert change.old_values["state"] == "draft"
    assert change.new_values["state"] == "published"
    assert_replayable()
  end

  test "replaying backward from now reproduces any earlier state exactly" do
    {:ok, dataset} =
      Catalog.create_dataset_with_version(new_dataset_params("A"), actor: "x", state: :published)

    [v1] = dataset.versions

    {:ok, v2} =
      Catalog.create_dataset_version(dataset, valid_version_attrs(),
        state: :draft,
        owning_editor_id: user_id(:editor)
      )

    midpoint = Changelog.snapshot()
    mid_id = Changelog.last_change_id()

    {:ok, _} =
      Catalog.update_dataset_row(
        dataset,
        %{"name" => "B"},
        v1,
        %{
          "doc_links" => %{"0" => %{"label" => "Docs", "url" => "https://example.org/docs"}},
          "data_quality" => %{"documented" => "yes"}
        },
        scope: scope_fixture(:editor)
      )

    {:ok, _} = Catalog.publish_dataset_version(scope_fixture(:editor), v2)
    {:error, _} = Catalog.create_dataset(%{name: "B"})
    {:ok, _} = Catalog.create_dataset(%{name: "C"})

    later = Changelog.list_changes(mid_id)
    assert length(later) == 4
    assert Replay.backward(Changelog.snapshot(), later) == midpoint
    assert Replay.forward(midpoint, later) == Changelog.snapshot()
    assert_replayable()
  end

  test "replay refuses changes that do not fit the state" do
    {:ok, _} = Catalog.create_dataset(%{name: "A"})
    [insert] = Changelog.list_changes()

    assert_raise Replay.Error, ~r/row already exists/, fn ->
      Replay.forward(Changelog.snapshot(), [insert])
    end

    assert_raise Replay.Error, ~r/row does not match/, fn ->
      Replay.backward(Changelog.empty_snapshot(), [insert])
    end
  end

  test "subscribers are told about committed change sets only" do
    Changelog.subscribe()
    {:ok, _} = Catalog.create_dataset(%{name: "A"})
    assert_receive {:catalog_changed, set_id} when is_integer(set_id)

    {:error, _} = Catalog.create_dataset(%{name: "A"})
    refute_receive {:catalog_changed, _}
  end
end
