defmodule FGDataCatalog.ChangelogRevertTest do
  # NOTE(Claude 2026-11-06): reverting a change set, as a new logged change set.
  # Not async: writes broadcast to every subscriber.
  use FGDataCatalog.DataCase, async: false

  import FGDataCatalog.CatalogFixtures

  alias FGDataCatalog.Catalog
  alias FGDataCatalog.Catalog.{Dataset, DatasetVersion}
  alias FGDataCatalog.Changelog
  alias FGDataCatalog.Changelog.ChangeSet

  defp last_set_id, do: Repo.one(from s in ChangeSet, select: max(s.id))

  defp edit(version, attrs) do
    version = Repo.get!(DatasetVersion, version.id)
    dataset = Repo.get!(Dataset, version.dataset_id)

    {:ok, %{version: version}} =
      Catalog.update_dataset_row(dataset, %{}, version, attrs, scope: scope_fixture(:editor))

    version
  end

  test "reverting an update restores the old values, embeds and lists included" do
    version = version_fixture(dataset_fixture(), %{tags: ["A"], release_date: ~D[2026-01-01]})
    before = Changelog.raw_row(DatasetVersion, version.id)

    edit(version, %{
      tags: ["B", "C"],
      release_date: ~D[2026-02-02],
      doc_links: [],
      omop_integration: :yes
    })

    set_id = last_set_id()

    assert {:ok, revert_id} = Catalog.revert_change_set(scope_fixture(:editor), set_id)

    assert %ChangeSet{action: "revert change set #" <> _, actor: "editor@finngen.fi"} =
             Repo.get!(ChangeSet, revert_id)

    restored = Repo.get!(DatasetVersion, version.id)
    assert restored.tags == ["A"]
    assert restored.release_date == ~D[2026-01-01]
    assert [%{label: "README"}] = restored.doc_links
    assert restored.omop_integration == nil

    after_revert = Changelog.raw_row(DatasetVersion, version.id)
    assert Map.delete(after_revert, "updated_at") == Map.delete(before, "updated_at")
    assert_replayable()
  end

  test "a later change to other columns of the row does not prevent it" do
    version = version_fixture(dataset_fixture(), %{lead: "A", tags: ["x"]})
    edit(version, %{lead: "B"})
    set_id = last_set_id()
    edit(version, %{tags: ["y"]})

    assert {:ok, _} = Catalog.revert_change_set(scope_fixture(:editor), set_id)
    assert %{lead: "A", tags: ["y"]} = Repo.get!(DatasetVersion, version.id)
    assert_replayable()
  end

  test "a later change to the same columns is a conflict, and nothing is reverted" do
    dataset = dataset_fixture(%{name: "Old name"})
    version = version_fixture(dataset, %{lead: "A"})

    {:ok, _} =
      Catalog.update_dataset_row(dataset, %{name: "New name"}, version, %{lead: "B"},
        scope: scope_fixture(:editor)
      )

    set_id = last_set_id()
    dataset = Repo.get!(Dataset, dataset.id)
    version = Repo.get!(DatasetVersion, version.id)

    {:ok, _} =
      Catalog.update_dataset_row(dataset, %{name: "Newer name"}, version, %{},
        scope: scope_fixture(:editor)
      )

    # The version's change is undone first (newest first), then the dataset's
    # conflicts: the version's revert is rolled back too.
    assert {:error, {:conflict, %{table_name: "datasets"}}} =
             Catalog.revert_change_set(scope_fixture(:editor), set_id)

    assert Repo.get!(Dataset, dataset.id).name == "Newer name"
    assert Repo.get!(DatasetVersion, version.id).lead == "B"
    assert_replayable()
  end

  test "reverting a creation deletes the dataset and its version; reverting that restores them" do
    {:ok, dataset} =
      Catalog.create_dataset_with_version(%{
        "name" => "Created",
        "versions" => [valid_version_attrs(%{version: "R1"})]
      })

    set_id = last_set_id()
    snapshot = Changelog.snapshot()

    assert {:ok, revert_id} = Catalog.revert_change_set(scope_fixture(:editor), set_id)
    refute Repo.get(Dataset, dataset.id)

    assert Repo.aggregate(from(v in DatasetVersion, where: v.dataset_id == ^dataset.id), :count) ==
             0

    # Reverting the revert re-inserts the rows exactly as they were.
    assert {:ok, _} = Catalog.revert_change_set(scope_fixture(:editor), revert_id)
    assert Changelog.snapshot() == snapshot
    assert_replayable()
  end

  test "a creation is not reverted once the dataset got another version" do
    {:ok, dataset} = Catalog.create_dataset(%{name: "Parent"})
    set_id = last_set_id()
    version_fixture(dataset)

    assert {:error, {:conflict, %{table_name: "datasets"}}} =
             Catalog.revert_change_set(scope_fixture(:editor), set_id)

    assert Repo.get(Dataset, dataset.id)
    assert_replayable()
  end

  # NOTE(Claude 2026-11-16): any editor, no longer admins only.
  test "any editor may revert, visitors may not" do
    version = version_fixture(dataset_fixture(), %{lead: "A"})
    edit(version, %{lead: "B"})

    assert {:error, :unauthorized} = Catalog.revert_change_set(nil, last_set_id())
    assert Repo.get!(DatasetVersion, version.id).lead == "B"

    assert {:ok, _} = Catalog.revert_change_set(scope_fixture(:other_editor), last_set_id())
    assert Repo.get!(DatasetVersion, version.id).lead == "A"
  end

  test "an unknown change set is not found" do
    assert {:error, :not_found} = Catalog.revert_change_set(scope_fixture(:editor), -1)
  end

  # NOTE(Claude 2026-11-16): accepted consequence of "every editor may revert":
  # a revert writes the state and the owner back, undoing a transition.
  test "reverting an unpublish restores the state and the owning editor" do
    version = version_fixture(dataset_fixture(), %{}, owning_editor_id: user_id(:editor))
    {:ok, _} = Catalog.unpublish_dataset_version(scope_fixture(:other_editor), version)
    assert %{state: :draft} = Repo.get!(DatasetVersion, version.id)

    assert {:ok, _} = Catalog.revert_change_set(scope_fixture(:other_editor), last_set_id())

    assert %{state: :published, owning_editor_id: owner} = Repo.get!(DatasetVersion, version.id)
    assert owner == user_id(:editor)
    assert_replayable()
  end
end
