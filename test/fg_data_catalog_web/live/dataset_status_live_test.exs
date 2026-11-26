defmodule FGDataCatalogWeb.DatasetStatusLiveTest do
  # NOTE(Claude 2026-11-16): the rule table of version states and editors (see
  # `FGDataCatalog.Catalog.can?/3` and DONE.md), checked through the UI, one
  # test per cell (state × actor): whether the actor sees the version, and has
  # exactly the allowed actions (buttons and quick-edit cells). Each forbidden
  # action is also sent directly as an event, and must change nothing in the
  # database: the server check is what protects the data.
  use FGDataCatalogWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import FGDataCatalog.CatalogFixtures
  import FGDataCatalog.DataCase, only: [assert_replayable: 0]

  alias FGDataCatalog.Catalog
  alias FGDataCatalog.Catalog.DatasetVersion
  alias FGDataCatalog.Repo

  # NOTE(Claude 2026-11-16): the owning editor of the versions is `:editor`;
  # the "other editor" is `:other_editor` (see `FGDataCatalogWeb.ConnCase`).
  setup do
    dataset = dataset_fixture(%{name: "Kanta lab values"})
    owner = user_id(:editor)

    versions = %{
      published:
        version_fixture(dataset, %{version: "R14", release_date: ~D[2026-03-13]},
          owning_editor_id: owner
        ),
      draft:
        version_fixture(dataset, %{version: "R15", release_date: ~D[2026-09-01]},
          state: :draft,
          owning_editor_id: owner
        ),
      archived:
        version_fixture(dataset, %{version: "R13", release_date: ~D[2025-03-01]},
          state: :archived,
          owning_editor_id: owner
        )
    }

    %{dataset: dataset, versions: versions}
  end

  # NOTE(Claude 2026-11-16): the rule table, cell by cell: what the actor may
  # do with a version in that state, besides reading it ("hidden" if not).
  @cells [
    {:published, :visitor, :read, []},
    {:published, :other_editor, :read, [:write, :unpublish, :archive]},
    {:published, :owner, :read, [:write, :unpublish, :archive]},
    {:draft, :visitor, :hidden, []},
    {:draft, :other_editor, :read, [:write, :publish, :delete]},
    {:draft, :owner, :read, [:write, :publish, :delete]},
    {:archived, :visitor, :hidden, []},
    {:archived, :other_editor, :read, [:unarchive]},
    {:archived, :owner, :read, [:unarchive]}
  ]

  @actions [:write, :publish, :delete, :unpublish, :archive, :unarchive]

  defp conn_for(:visitor), do: build_conn()
  defp conn_for(:other_editor), do: log_in(build_conn(), :other_editor)
  defp conn_for(:owner), do: log_in(build_conn(), :editor)

  for {state, actor, read, allowed} <- @cells do
    @state state
    @actor actor
    @read read
    @allowed allowed

    describe "#{state} version, #{actor}" do
      test "sees it or not, with exactly the allowed actions", %{versions: versions} do
        version = versions[@state]
        conn = conn_for(@actor)
        {:ok, view, _html} = live(conn, ~p"/")

        # NOTE(Claude 2026-11-16): Archived versions are never in the catalog;
        # editors read them on the archive page.
        in_catalog? = @read == :read and @state != :archived
        assert has_element?(view, "#version-#{version.id}") == in_catalog?

        if @actor != :visitor, do: render_hook(view, "toggle_editor_mode", %{})

        assert has_element?(view, "#edit-version-#{version.id}") == :write in @allowed
        assert has_element?(view, "#publish-version-#{version.id}") == :publish in @allowed
        assert has_element?(view, "#unpublish-version-#{version.id}") == :unpublish in @allowed
        assert has_element?(view, "#archive-version-#{version.id}") == :archive in @allowed
        assert has_element?(view, "#delete-version-#{version.id}") == :delete in @allowed

        assert has_element?(view, "#version-#{version.id} [data-quick-edit]") ==
                 :write in @allowed

        if @actor == :visitor do
          refute has_element?(view, "#archive-link")
          assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/archive")
        else
          {:ok, archive, _html} = live(conn, ~p"/archive")

          assert has_element?(archive, "#archived-version-#{version.id}") ==
                   (@state == :archived)

          assert has_element?(archive, "#unarchive-version-#{version.id}") ==
                   :unarchive in @allowed
        end
      end

      for action <- @actions -- allowed do
        @action action

        test "a forbidden #{action} sent directly changes nothing", %{versions: versions} do
          version = versions[@state]
          before = Repo.get!(DatasetVersion, version.id)

          refused!(conn_for(@actor), @action, version)

          assert Repo.get!(DatasetVersion, version.id) == before
        end
      end
    end
  end

  # NOTE(Claude 2026-11-16): sends the event of `action` for `version`, as a
  # page that showed its button would.
  defp refused!(conn, :write, version) do
    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/versions/#{version.id}/edit")

    {:ok, view, _html} = live(conn, ~p"/")
    render_hook(view, "toggle_editor_mode", %{})
    id = to_string(version.id)
    render_hook(view, "quick_edit", %{"id" => id, "field" => "lead"})
    refute has_element?(view, "#quick-edit-form")
    # OMOP-mapped saves at once, without an editor.
    render_hook(view, "quick_edit", %{"id" => id, "field" => "omop_integration"})
  end

  defp refused!(conn, :unarchive, version) do
    case live(conn, ~p"/archive") do
      {:ok, view, _html} ->
        render_hook(view, "unarchive", %{"id" => to_string(version.id)})

      {:error, {:live_redirect, %{to: "/"}}} ->
        :ok
    end
  end

  defp refused!(conn, action, version) do
    {:ok, view, _html} = live(conn, ~p"/")
    render_hook(view, to_string(action), %{"id" => to_string(version.id)})
  end

  describe "allowed transitions through the UI" do
    test "the owning editor publishes their Draft", %{conn: conn, versions: versions} do
      {:ok, view, _html} = live(conn, ~p"/")
      view |> element("#publish-version-#{versions.draft.id}") |> render_click()

      assert Repo.get!(DatasetVersion, versions.draft.id).state == :published
      assert has_element?(view, "#status-#{versions.draft.id}.status-published")
      refute has_element?(view, "#publish-version-#{versions.draft.id}")
      assert_replayable()
    end

    @tag role: :other_editor
    test "unpublish makes the acting editor the owner", %{conn: conn, versions: versions} do
      {:ok, view, _html} = live(conn, ~p"/")
      view |> element("#unpublish-version-#{versions.published.id}") |> render_click()

      assert %{state: :draft, owning_editor_id: owner} =
               Repo.get!(DatasetVersion, versions.published.id)

      assert owner == user_id(:other_editor)
      # Now theirs: they may edit and publish it.
      assert has_element?(view, "#publish-version-#{versions.published.id}")
      assert has_element?(view, "#edit-version-#{versions.published.id}")
    end

    @tag role: :other_editor
    test "unarchive makes the acting editor the owner", %{conn: conn, versions: versions} do
      {:ok, view, _html} = live(conn, ~p"/archive")
      view |> element("#unarchive-version-#{versions.archived.id}") |> render_click()

      assert %{state: :draft, owning_editor_id: owner, archived_at: nil} =
               Repo.get!(DatasetVersion, versions.archived.id)

      assert owner == user_id(:other_editor)
      refute has_element?(view, "#archived-version-#{versions.archived.id}")
    end

    # NOTE(Claude-Opus-5.5 2026-11-26): "My draft" for its owner, "Draft" for
    # the others, with its owner in an instant tooltip (`data-tip`).
    test "the badge reads My draft for its owner, Draft by its owner for the others",
         %{conn: conn, versions: versions} do
      id = versions.draft.id
      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "#status-#{id}.status-draft.is-mine", "My draft")
      assert has_element?(view, "#status-#{id}[data-tip^='Your draft']")
      refute has_element?(view, "#status-#{id}[title]")

      {:ok, other, _html} = live(conn_for(:other_editor), ~p"/")
      assert has_element?(other, "#status-#{id}.status-draft:not(.is-mine)", "Draft")
      refute has_element?(other, "#status-#{id}", "My draft")
      assert has_element?(other, "#status-#{id}[data-tip='Draft by editor@finngen.fi']")
    end

    @tag role: :other_editor
    test "another editor deletes someone's Draft", %{conn: conn, versions: versions} do
      id = versions.draft.id
      {:ok, view, _html} = live(conn, ~p"/")
      view |> element("#delete-version-#{id}") |> render_click()

      assert Repo.get(DatasetVersion, id) == nil
      refute has_element?(view, "#version-#{id}")
      assert_replayable()
    end
  end

  # NOTE(Claude 2026-11-16): a Draft sorts among the dataset's versions by
  # release date, so a newer Draft by anyone is the top row for every editor.
  describe "a newer Draft by another editor" do
    setup %{dataset: dataset} do
      newest =
        version_fixture(dataset, %{version: "R16", release_date: ~D[2026-10-01]},
          state: :draft,
          owning_editor_id: user_id("someone-else@finngen.fi")
        )

      %{newest: newest}
    end

    for actor <- [:owner, :other_editor] do
      @actor actor
      test "is the dataset's top row for #{actor}", %{newest: newest} do
        {:ok, view, _html} = live(conn_for(@actor), ~p"/")
        assert has_element?(view, "#version-#{newest.id}.current-version")
        assert has_element?(view, "#status-#{newest.id}.status-draft[data-tip*='someone-else']")
      end
    end

    test "is absent for a visitor, who sees the Published version on top",
         %{newest: newest, versions: versions} do
      {:ok, view, _html} = live(conn_for(:visitor), ~p"/")
      refute has_element?(view, "#version-#{newest.id}")
      assert has_element?(view, "#version-#{versions.published.id}.current-version")
      refute has_element?(view, ".status-badge")
    end
  end

  test "a new dataset is a Draft owned by its creator", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/datasets/new")

    view
    |> form("#edit-form")
    |> render_change(%{
      "edit_dataset" => %{"name" => "New one"},
      "edit_version" => %{
        "version" => "R1",
        "release_date" => "2026-01-01",
        "lead" => "Jane",
        "access_type" => "red",
        "cohort_size" => "10"
      }
    })

    version = Repo.get_by!(DatasetVersion, version: "R1", owning_editor_id: user_id(:editor))
    assert version.state == :draft

    {:ok, index, _html} = live(conn, ~p"/")
    assert has_element?(index, "#status-#{version.id}.status-draft", "My draft")
    assert has_element?(index, "#publish-version-#{version.id}")
    assert Catalog.list_published_datasets() |> Enum.all?(&(&1.name != "New one"))
  end
end
