defmodule FGDataCatalog.ChangelogMigrationTest do
  # NOTE(Claude Opus 5.5 2026-11-17): tests of the changelog rewrites for schema
  # migrations (`FGDataCatalog.Changelog.Migration`) and of their check
  # (`FGDataCatalog.Changelog.Verify`). The rewrites run with `repo: Repo`,
  # outside a migration, on a changelog recorded with the current schema.
  use FGDataCatalog.DataCase, async: false

  import FGDataCatalog.CatalogFixtures

  alias FGDataCatalog.Catalog
  alias FGDataCatalog.Changelog.{Change, LocationMigration, Verify}
  alias FGDataCatalog.Changelog.Migration, as: ChangelogMigration

  defp change(op, old, new), do: %{id: 1, record_id: 1, op: op, old_values: old, new_values: new}

  defp version_changes do
    Repo.all(from c in Change, where: c.table_name == "dataset_versions", order_by: c.id)
  end

  describe "converting location history" do
    test "converts inserts and deletes with zero or one location" do
      for {legacy, locations} <- [
            {%{"location" => nil, "location_label" => nil}, "[]"},
            {%{"location" => "/data", "location_label" => nil},
             ~s([{"label":null,"value":"/data"}])}
          ],
          legacy_change <- [change(:insert, nil, legacy), change(:delete, legacy, nil)] do
        upgraded = LocationMigration.upgrade_in(legacy_change, nil)
        assert (upgraded.old_values || upgraded.new_values) == %{"locations" => locations}
        assert LocationMigration.downgrade_in(upgraded, nil) == legacy_change
      end
    end

    test "completes partial location updates using the previous row" do
      value = "/data"
      label = "Sandbox"
      row = %{"location" => value, "location_label" => label}

      for {old, new, encoded} <- [
            {%{"location_label" => label}, %{"location_label" => "Research"},
             ~s([{"label":"Research","value":"/data"}])},
            {%{"location" => value}, %{"location" => "/elsewhere"},
             ~s([{"label":"Sandbox","value":"/elsewhere"}])},
            {row, %{"location" => nil, "location_label" => nil}, "[]"}
          ] do
        legacy = change(:update, Map.put(old, "updated_at", "a"), Map.put(new, "updated_at", "b"))
        upgraded = LocationMigration.upgrade_in(legacy, row)

        assert upgraded.old_values == %{
                 "locations" => ~s([{"label":"Sandbox","value":"/data"}]),
                 "updated_at" => "a"
               }

        assert upgraded.new_values == %{"locations" => encoded, "updated_at" => "b"}
        assert LocationMigration.downgrade_in(upgraded, nil) == legacy
      end

      unrelated = change(:update, %{"lead" => "Ann"}, %{"lead" => "Bob"})
      assert LocationMigration.upgrade_in(unrelated, row) == unrelated
      assert LocationMigration.downgrade_in(unrelated, nil) == unrelated
    end

    test "edits of extra entries project to timestamps on rollback" do
      first = ~s([{"label":null,"value":"/data"}])
      both = ~s([{"label":null,"value":"/data"},{"label":"Cloud","value":"gs://bucket/data"}])

      edit =
        change(:update, %{"locations" => first, "updated_at" => "a"}, %{
          "locations" => both,
          "updated_at" => "b"
        })

      assert LocationMigration.downgrade_in(edit, nil) ==
               change(:update, %{"updated_at" => "a"}, %{"updated_at" => "b"})

      assert LocationMigration.split_locations(both) ==
               {%{"location" => "/data", "location_label" => nil},
                [%{"label" => "Cloud", "value" => "gs://bucket/data"}]}
    end

    test "the upgrade writes the same JSON as a recorded location embed" do
      dataset = dataset_fixture()

      for {value, label} <- [{"/sandbox", nil}, {"gs://bucket/dir", "Cloud"}] do
        version = version_fixture(dataset, %{locations: [%{value: value, label: label}]})
        recorded = Enum.find(version_changes(), &(&1.record_id == version.id))

        assert recorded.new_values["locations"] ==
                 LocationMigration.encode_legacy(%{
                   "location" => value,
                   "location_label" => label
                 })
      end
    end
  end

  # NOTE(Claude Opus 5.5 2026-11-17): a dataset with one version, then that
  # version's lead edited: an insert and an update of `dataset_versions`.
  defp record_changes do
    dataset = dataset_fixture()
    version = version_fixture(dataset, %{lead: "Ann"})

    {:ok, _} =
      Catalog.update_dataset_row(dataset, %{}, version, %{"lead" => "Bob"},
        scope: scope_fixture(:editor)
      )

    :ok
  end

  describe "the rewrite of one change" do
    test "rename_in renames the key in old and new values, mapping the value" do
      assert ChangelogMigration.rename_in(
               change(:update, %{"a" => 1, "x" => 0}, %{"a" => 2}),
               "a",
               "b",
               &(&1 * 10)
             ) == change(:update, %{"b" => 10, "x" => 0}, %{"b" => 20})

      unchanged = change(:insert, nil, %{"x" => 1})
      assert ChangelogMigration.rename_in(unchanged, "a", "b") == unchanged

      assert_raise ArgumentError, ~r/already records "b"/, fn ->
        ChangelogMigration.rename_in(change(:insert, nil, %{"a" => 1, "b" => 2}), "a", "b")
      end
    end

    test "drop_in removes the key everywhere" do
      assert ChangelogMigration.drop_in(change(:update, %{"a" => 1}, %{"a" => 2}), "a") ==
               change(:update, %{}, %{})

      assert ChangelogMigration.drop_in(change(:delete, %{"a" => 1, "x" => 0}, nil), "a") ==
               change(:delete, %{"x" => 0}, nil)
    end

    test "add_in adds the key to full rows only, with a value or a function of the row" do
      assert ChangelogMigration.add_in(change(:insert, nil, %{"x" => 1}), "a", nil) ==
               change(:insert, nil, %{"x" => 1, "a" => nil})

      assert ChangelogMigration.add_in(change(:delete, %{"x" => 1}, nil), "a", &(&1["x"] + 1)) ==
               change(:delete, %{"x" => 1, "a" => 2}, nil)

      update = change(:update, %{"x" => 1}, %{"x" => 2})
      assert ChangelogMigration.add_in(update, "a", 0) == update

      assert_raise ArgumentError, ~r/already records "x"/, fn ->
        ChangelogMigration.add_in(change(:insert, nil, %{"x" => 1}), "x", 0)
      end
    end
  end

  describe "rewriting the recorded changes" do
    setup do: record_changes()

    test "rename_key and back leaves a replayable changelog" do
      assert Verify.run() == :ok

      :ok = ChangelogMigration.rename_key("dataset_versions", "lead", "lead_name", repo: Repo)
      [insert, update] = version_changes()
      assert insert.new_values["lead_name"] == "Ann"
      refute Map.has_key?(insert.new_values, "lead")
      assert {update.old_values["lead_name"], update.new_values["lead_name"]} == {"Ann", "Bob"}
      assert {:error, issues} = Verify.run()
      assert Enum.any?(issues, &(&1 =~ "unknown columns lead_name"))

      :ok = ChangelogMigration.rename_key("dataset_versions", "lead_name", "lead", repo: Repo)
      assert Verify.run() == :ok
    end

    test "add_key and drop_key change full rows, and drop_key updates too" do
      :ok = ChangelogMigration.add_key("dataset_versions", "reviewer", "nobody", repo: Repo)
      [insert, update] = version_changes()
      assert insert.new_values["reviewer"] == "nobody"
      refute Map.has_key?(update.new_values, "reviewer")

      :ok = ChangelogMigration.drop_key("dataset_versions", "reviewer", repo: Repo)
      assert Verify.run() == :ok
    end

    test "rewrite passes the row as it was before each change" do
      test_pid = self()

      :ok =
        ChangelogMigration.rewrite(
          "dataset_versions",
          fn change, row ->
            send(test_pid, {change.op, row && row["lead"]})
            change
          end,
          repo: Repo
        )

      assert_received {:insert, nil}
      assert_received {:update, "Ann"}
    end

    test "rewrite refuses to record a JSON array" do
      assert_raise ArgumentError, ~r/"tags" would be recorded as \["a"\]/, fn ->
        ChangelogMigration.rewrite(
          "dataset_versions",
          fn
            %{op: :insert} = change -> put_in(change.new_values["tags"], ["a"])
            change -> change
          end,
          repo: Repo
        )
      end
    end
  end

  describe "verify" do
    setup do: record_changes()

    test "passes on a changelog recorded with the current schema" do
      assert Verify.run() == :ok
    end

    test "reports stale keys, missing columns, JSON arrays and values that do not load" do
      [insert, _update] = version_changes()
      row = insert.new_values

      bad_row =
        row
        |> Map.delete("lead")
        |> Map.merge(%{"status" => "draft", "tags" => ["a"], "coverage_start" => "2013-01-01"})

      Repo.update_all(from(c in Change, where: c.id == ^insert.id), set: [new_values: bad_row])

      assert {:error, issues} = Verify.run()
      assert Enum.any?(issues, &(&1 =~ "unknown columns status"))
      assert Enum.any?(issues, &(&1 =~ "missing columns lead"))

      assert Enum.any?(
               issues,
               &(&1 =~ "not raw (JSON arrays or objects instead of JSON text): tags")
             )

      assert Enum.any?(issues, &(&1 =~ "replay forward from empty"))
    end

    test "reports a value that does not load with the current schema" do
      [insert, _update] = version_changes()
      bad_row = Map.put(insert.new_values, "coverage_start", "2013-01-01")
      Repo.update_all(from(c in Change, where: c.id == ^insert.id), set: [new_values: bad_row])

      assert {:error, issues} = Verify.run()
      assert Enum.any?(issues, &(&1 =~ ~r/do not load: cannot load `"2013-01-01"`/))
    end

    test "reports a row the changelog does not account for" do
      [insert, _update] = version_changes()

      Repo.update_all(from(c in Change, where: c.id == ^insert.id),
        set: [table_name: "dataset_versions", record_id: insert.record_id + 1000]
      )

      assert {:error, issues} = Verify.run()
      assert Enum.any?(issues, &(&1 =~ "replay forward from empty"))
      assert Enum.any?(issues, &(&1 =~ "replay backward from now"))
    end
  end
end
