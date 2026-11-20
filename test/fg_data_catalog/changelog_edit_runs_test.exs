defmodule FGDataCatalog.ChangelogEditRunsTest do
  # NOTE(Claude Opus 5.5 2026-11-18): runs of live edits, merged for display
  # (`Changelog.edit_runs/1`) and reverted as one (`Changelog.revert/2` with a
  # list). Not async: writes broadcast to every subscriber.
  use FGDataCatalog.DataCase, async: false

  import FGDataCatalog.CatalogFixtures

  alias FGDataCatalog.Catalog
  alias FGDataCatalog.Catalog.{Dataset, DatasetVersion}
  alias FGDataCatalog.Changelog
  alias FGDataCatalog.Changelog.{Change, ChangeSet}

  setup do
    version = version_fixture(dataset_fixture(), %{lead: "A"})
    %{version: version}
  end

  defp edit(version, attrs, who \\ :editor) do
    version = Repo.get!(DatasetVersion, version.id)
    dataset = Repo.get!(Dataset, version.dataset_id)

    {:ok, _} =
      Catalog.update_dataset_row(dataset, %{}, version, attrs, scope: scope_fixture(who))

    Repo.one(from s in ChangeSet, select: max(s.id))
  end

  # The runs, as lists of change set ids, newest run first.
  defp runs(opts \\ []) do
    opts
    |> Changelog.list_recent_changes()
    |> Changelog.edit_runs()
    |> Enum.map(fn run -> Enum.map(run, fn [change | _] -> change.change_set_id end) end)
  end

  defp backdate(set_id, seconds) do
    {1, _} =
      from(s in ChangeSet, where: s.id == ^set_id)
      |> Repo.update_all(set: [inserted_at: DateTime.add(DateTime.utc_now(:second), -seconds)])
  end

  test "consecutive edits of one field of a row by one actor are one run", %{version: version} do
    a = edit(version, %{lead: "B"})
    b = edit(version, %{lead: "BC"})
    c = edit(version, %{lead: "BCD"})

    assert [[^a, ^b, ^c] | _] = runs()
  end

  test "another field, another actor or another action starts a new run", %{version: version} do
    a = edit(version, %{lead: "B"})
    b = edit(version, %{locations: [%{value: "/data/y"}]})
    c = edit(version, %{locations: [%{value: "/data/z"}]}, :other_editor)
    {:ok, d} = Catalog.revert_change_set(scope_fixture(:other_editor), c)

    assert [[^d], [^c], [^b], [^a] | _] = runs()
  end

  test "a change set in between, even of another row, breaks the run", %{version: version} do
    other = version_fixture(dataset_fixture())
    a = edit(version, %{lead: "B"})
    b = edit(other, %{lead: "Other"}, :other_editor)
    c = edit(version, %{lead: "BC"})

    assert [[^c], [^b], [^a] | _] = runs()
    # Also when the change set in between is filtered out.
    assert [[^c], [^a] | _] = runs(actor: "editor@finngen.fi")
  end

  test "more than 60 seconds after the previous edit starts a new run", %{version: version} do
    a = edit(version, %{lead: "B"})
    backdate(a, 70)
    b = edit(version, %{lead: "BC"})
    backdate(b, 1)
    c = edit(version, %{lead: "BCD"})

    assert [[^b, ^c], [^a] | _] = runs()
  end

  test "a page that starts inside a run gets the run's earlier change sets", %{version: version} do
    a = edit(version, %{lead: "B"})
    b = edit(version, %{lead: "BC"})
    c = edit(version, %{lead: "BCD"})
    [last_change] = Repo.all(from ch in Change, where: ch.change_set_id == ^c)

    assert [[^a, ^b, ^c]] = runs(after: last_change.id - 1)
  end

  test "a run is reverted as one change, back to its first old value", %{version: version} do
    ids = for lead <- ["B", "BC", "BCD"], do: edit(version, %{lead: lead})

    assert {:ok, revert_id} = Catalog.revert_change_set(scope_fixture(:editor), ids)

    assert %ChangeSet{action: "revert change sets #" <> _, changes: [change]} =
             ChangeSet |> Repo.get!(revert_id) |> Repo.preload(:changes)

    assert %{"lead" => "BCD"} = change.old_values
    assert %{"lead" => "A"} = change.new_values
    assert Repo.get!(DatasetVersion, version.id).lead == "A"
    assert_replayable()
  end

  test "a run changed since is not reverted", %{version: version} do
    ids = for lead <- ["B", "BC"], do: edit(version, %{lead: lead})
    edit(version, %{lead: "Theirs"}, :other_editor)

    assert {:error, {:conflict, %Change{}}} =
             Catalog.revert_change_set(scope_fixture(:editor), ids)

    assert Repo.get!(DatasetVersion, version.id).lead == "Theirs"
  end

  test "ids that are not a run are refused", %{version: version} do
    a = edit(version, %{lead: "B"})
    b = edit(version, %{locations: [%{value: "/data/y"}]})
    c = edit(version, %{lead: "BC"})

    assert {:error, :not_found} = Catalog.revert_change_set(scope_fixture(:editor), [a, c])
    assert {:error, :not_found} = Catalog.revert_change_set(scope_fixture(:editor), [a, b])
    assert {:error, :not_found} = Catalog.revert_change_set(scope_fixture(:editor), [a, a])
    assert {:error, :unauthorized} = Catalog.revert_change_set(nil, [a, b])
    assert Repo.get!(DatasetVersion, version.id).lead == "BC"
  end
end
