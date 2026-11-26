defmodule FGDataCatalogWeb.DatasetLive.Form do
  @moduledoc """
  The dataset form pages: a new dataset (`/datasets/new`), a new version of
  an existing dataset (`/datasets/:id/versions/new`) and an existing version
  (`/versions/:id/edit`).

  NOTE(Claude-Opus-5.5 2026-11-26): an existing version saves each valid
  change at once. A new dataset or version is created as a Draft of the user
  (which every editor sees, see `Catalog.can?/3`) as soon as its required
  fields are valid; the page then becomes the draft's edit page, without
  reloading. Until then, a new dataset's fields are kept in the user's
  autosave (see `Catalog.save_dataset_draft/2`), a new version's in the page
  only. There is no Submit: a draft is published or deleted.
  """
  # NOTE(Claude 2026-11-04): moved out of `DatasetLive.Index`, where the forms
  # were first table rows and then a modal, to give them a page of their own.
  use FGDataCatalogWeb, :live_view

  import FGDataCatalogWeb.DatasetFormComponents
  import FGDataCatalogWeb.CatalogComponents, only: [status_badge: 1]

  alias FGDataCatalog.Accounts.Scope
  alias FGDataCatalog.Catalog
  alias FGDataCatalog.Changelog
  alias FGDataCatalog.Repo
  alias FGDataCatalog.Catalog.{Dataset, DatasetVersion}
  alias FGDataCatalogWeb.DatasetLive.VersionParams

  # NOTE(Claude 2026-11-17): the dataset's own fields on the edit form (those of
  # `edit_dataset`), editable through any version.
  @dataset_fields ~w(name description)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="form-page">
        <%!-- NOTE(Claude-Opus-5.5 2026-11-26): on the new dataset page, Escape
             closes a suggestion list, then leaves the focused field, then goes
             back to the catalog (`.EscapeBack`, on the key's hint: a hook
             name is resolved only when written as a literal). --%>
        <.link
          id="back-to-catalog"
          navigate={~p"/"}
          class="back-link"
          aria-keyshortcuts={@live_action == :new && "Escape"}
          title={@live_action == :new && "Back to the catalog (Esc)"}
        >
          ← Back to the catalog
          <kbd
            :if={@live_action == :new}
            id="back-shortcut"
            phx-hook=".EscapeBack"
            aria-hidden="true"
          >
            Esc
          </kbd>
        </.link>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".EscapeBack">
          // NOTE(Claude-Opus-5.5 2026-11-26): Escape, in this order: a
          // suggestion list closes (its own handler, which prevents the
          // default: seen here as `defaultPrevented`); else a focused field
          // loses the focus (which also sends its debounced value, so the
          // draft is up to date); else the page goes back to the catalog.
          // With the browser's Back if this page was opened from the catalog
          // (`fgdcFromCatalog` in its history entry, see `stampFromCatalog`),
          // so that the catalog's search, tags and scroll come back; else as
          // the link does. Not on a held key, so that holding Escape does not
          // leave the field and the page at once.
          export default {
            mounted() {
              this.stampFromCatalog()
              this.onKeydown = e => this.keydown(e)
              window.addEventListener("keydown", this.onKeydown)
            },
            destroyed() {
              window.removeEventListener("keydown", this.onKeydown)
              window.removeEventListener("phx:navigate", this.onNavigate)
            },
            keydown(e) {
              if (e.key !== "Escape" || e.defaultPrevented || e.repeat || e.isComposing) return
              if (e.ctrlKey || e.metaKey || e.altKey || e.shiftKey) return
              if (document.querySelector("dialog[open]")) return
              const active = document.activeElement
              if (active && active.matches("input, textarea, select, [contenteditable]")) {
                e.preventDefault()
                return active.blur()
              }
              e.preventDefault()
              if (history.state && history.state.fgdcFromCatalog) history.back()
              else this.el.closest("a").click()
            },
            // The catalog notes, as it is left by "Add missing dataset", when
            // (`fgdc:add-from-catalog`, see `.CatalogTable`). Read once here,
            // and kept in this page's history entry, which outlives a reload
            // or a reconnection. The entry is pushed by LiveView around this
            // mount, hence the wait for it: this page's path, or
            // `phx:navigate`.
            stampFromCatalog() {
              const key = "fgdc:add-from-catalog"
              const at = Number(sessionStorage.getItem(key))
              sessionStorage.removeItem(key)
              // A note older than a few seconds is from a navigation that did
              // not end here.
              if (!at || Date.now() - at > 10000) return
              const path = location.pathname
              const stamp = () => {
                if (location.pathname !== "/datasets/new") return false
                history.replaceState({ ...history.state, fgdcFromCatalog: true }, "")
                return true
              }
              if (path === "/datasets/new" && history.state && history.state.type === "redirect") {
                stamp()
              } else {
                this.onNavigate = () => {
                  if (stamp()) window.removeEventListener("phx:navigate", this.onNavigate)
                }
                window.addEventListener("phx:navigate", this.onNavigate)
              }
            }
          }
        </script>

        <h1 id="form-title">{form_title(@live_action, @edit)}</h1>
        <p :if={@edit.pending == :version && @source} id="prefilled-from" class="form-note">
          Prefilled from {@source.version}. Version, release date, data dictionary,
          years coverage, yearly counts and individuals covered start empty; the fields
          marked Not applicable stay so.
        </p>
        <%!-- NOTE(Claude-Opus-5.5 2026-11-26): the version's state and who may
             act on it (see `Catalog.can?/3`); its actions are in the form's
             footer. --%>
        <div :if={@edit.version} id="edit-state" class="form-note edit-state">
          <.status_badge
            id={"status-#{@edit.version.id}"}
            state={@edit.version.state}
            owner={@edit.version.owning_editor}
            viewer_id={Scope.user_id(@current_scope)}
          />
          <span :if={@edit.version.state == :draft}>
            Every editor sees this draft and may edit, publish or delete it.
          </span>
        </div>
        <%!-- NOTE(Claude 2026-11-06): someone else changed this row while it
             was being edited. --%>
        <div :if={@edit.notice} id="edit-notice" class="form-note edit-notice" role="alert">
          <p :if={@edit.notice.updated != []} id="edit-notice-updated">
            Someone else changed {field_list(@edit.notice.updated)}; the form shows their values.
          </p>
          <p :if={@edit.notice.conflicts != []} id="edit-notice-conflicts">
            Someone else also changed {field_list(@edit.notice.conflicts)}, which you
            are editing: your values are kept in the form, and your next change saves
            them over theirs.
          </p>
        </div>
        <%!-- NOTE(Claude-Opus-5.5 2026-11-26): the same form on the three
             pages, rendered at the same place, so that a new dataset or
             version keeps its fields (and the focus) once its draft exists. --%>
        <.edit_version_form
          dataset_form={@edit.dataset_form}
          version_form={@edit.version_form}
          status={@edit.status}
          saved={MapSet.to_list(@edit.saved)}
          suggestions={@suggestions}
          pending={@edit.pending}
          state={@edit.version && @edit.version.state}
          can={actions(@current_scope, @edit.version)}
          name_holder={@edit.name_holder}
        />
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    # NOTE(Claude-Opus-5.5 2026-11-26): existing values, suggested while typing
    # the Tags, Environments, Modality and Format fields.
    socket =
      socket
      |> assign(:suggestions, %{
        tags: Catalog.list_tags(),
        environments: Catalog.list_environments(),
        modalities: Catalog.list_modalities(),
        formats: Catalog.list_formats()
      })

    # NOTE(Claude 2026-11-06): only signed-in users may add and edit, checked
    # server-side too, not only by hiding the links.
    if Scope.editor?(socket.assigns.current_scope) do
      {:ok, mount_action(socket, socket.assigns.live_action, params)}
    else
      {:ok, leave(socket, "Editing datasets is not available.")}
    end
  end

  # NOTE(Claude-Opus-5.5 2026-11-26): everything is set up by `mount/3`; the
  # only patch is a new draft's, to its edit page, whose assigns `created/5`
  # has already set.
  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  defp mount_action(socket, :new, _params) do
    # NOTE(Claude 2026-11-03): an unsaved new dataset from an earlier visit is
    # shown again, as it was left.
    params = socket |> user_id() |> Catalog.get_dataset_draft_params() |> upgrade_autosave()

    edit =
      %{new_edit(:dataset, %Dataset{}, params) | params: params}
      |> track_all_touched(params)

    socket
    |> assign(:page_title, "Add missing dataset")
    |> assign(:edit, edit)
    |> assign_name_holder()
  end

  # NOTE(Claude 2026-11-06): prefilled from the dataset's latest version.
  # NOTE(Claude-Opus-5.5 2026-11-26): its draft is created once Version and
  # Release date are valid (they start empty), so not on opening the page.
  defp mount_action(socket, :new_version, %{"id" => id}) do
    with {id, ""} <- Integer.parse(id),
         {dataset, source} <-
           Catalog.get_dataset_for_new_version(id, viewer(socket)) do
      params = %{"edit_version" => Catalog.new_version_params(source)}

      socket
      |> assign(:page_title, "Add a version of #{dataset.name}")
      |> assign(:source, source)
      |> assign(:edit, new_edit(:version, dataset, params))
    else
      _ -> leave(socket, "That dataset was not found.")
    end
  end

  # NOTE(Claude 2026-11-16): only a version the viewer may write (see
  # `Catalog.can?/3`): not someone else's My draft.
  defp mount_action(socket, :edit, %{"id" => id}) do
    with {dataset, version, _current} <- find_row(visible_datasets(socket), id),
         true <- Catalog.can?(socket.assigns.current_scope, :write, version) do
      # NOTE(Claude 2026-11-06): to follow other people's changes to the row.
      if connected?(socket), do: Changelog.subscribe()

      socket
      |> assign(:page_title, "Edit #{dataset.name} #{version.version}")
      |> assign(:edit, existing_edit(dataset, version))
    else
      nil -> leave(socket, "That dataset version was not found.")
      false -> leave(socket, "You cannot edit that version.")
    end
  end

  defp existing_edit(dataset, version) do
    %{
      pending: nil,
      name_holder: nil,
      # NOTE(Claude-Opus-5.5 2026-11-26): the params a new dataset or version
      # opened with (autosave or prefill), see `with_prefill/2`.
      prefill: %{},
      dataset: dataset,
      version: version,
      status: :idle,
      dataset_form:
        to_form(Catalog.change_dataset(Catalog.proposed_dataset(dataset, version)),
          as: "edit_dataset"
        ),
      version_form: to_form(Catalog.change_dataset_version(version), as: "edit_version"),
      # NOTE(Claude 2026-11-06): the columns changed in this form since it
      # was opened, the latest form params, and the notice about changes
      # made by someone else (see `handle_info/2`).
      touched: MapSet.new(),
      params: %{},
      notice: nil,
      # NOTE(Claude 2026-11-12): the columns changed in this form whose
      # value is saved, marked with a tick (see `track_saved/2`).
      saved: MapSet.new()
    }
  end

  # NOTE(Claude-Opus-5.5 2026-11-26): a new dataset (`:dataset`, `dataset` is
  # then a blank one) or a new version of `dataset` (`:version`), whose draft
  # does not exist yet: `version` is `nil`. `params` are the form params
  # (`edit_dataset`, `edit_version`).
  defp new_edit(pending, dataset, params) do
    {dataset_changeset, version_changeset} = new_changesets(dataset, params)
    action = if pending == :dataset and params != %{}, do: :validate

    %{
      existing_edit(dataset, %DatasetVersion{})
      | pending: pending,
        prefill: params,
        version: nil,
        dataset_form: to_form(dataset_changeset, as: "edit_dataset", action: action),
        version_form: to_form(version_changeset, as: "edit_version", action: action)
    }
  end

  defp new_changesets(dataset, params) do
    {Catalog.change_dataset(dataset, Map.get(params, "edit_dataset", %{})),
     Catalog.change_dataset_version(
       %DatasetVersion{dataset_id: dataset.id},
       split_version_lists(Map.get(params, "edit_version", %{}))
     )}
  end

  # NOTE(Claude-Opus-5.5 2026-11-26): the autosave of a new dataset, in the
  # params of this form. It is stored with those of the former new dataset
  # form (see `save_draft/2`): the dataset's fields and `versions`, with one
  # version.
  defp upgrade_autosave(nil), do: %{}
  defp upgrade_autosave(%{"edit_version" => _} = params), do: params
  defp upgrade_autosave(%{"edit_dataset" => _} = params), do: params

  defp upgrade_autosave(params) do
    %{
      "edit_dataset" => Map.take(params, ["name", "description"]),
      "edit_version" => get_in(params, ["versions", "0"]) || %{}
    }
  end

  # NOTE(Claude-Opus-5.5 2026-11-26): until the draft exists, the optional
  # fields are disabled (see `version_fields/1`), and a browser does not send
  # disabled fields: their values are those the page opened with (the
  # autosave, or the prefill of a new version), under the fields sent.
  defp with_prefill(params, prefill) do
    Enum.reduce(["edit_dataset", "edit_version"], params, fn key, params ->
      merged = Map.merge(Map.get(prefill, key, %{}), Map.get(params, key, %{}))
      if merged == %{}, do: params, else: Map.put(params, key, merged)
    end)
  end

  # NOTE(Claude-Opus-5.5 2026-11-26): the restored fields count as changed, to
  # be marked as saved once the draft exists.
  defp track_all_touched(edit, params) do
    dataset = params |> Map.get("edit_dataset", %{}) |> Map.keys()
    version = params |> Map.get("edit_version", %{}) |> Map.keys() |> Enum.map(&param_column/1)
    columns = Enum.filter(dataset, &(&1 in @dataset_fields)) ++ version
    %{edit | touched: MapSet.union(edit.touched, MapSet.new(columns))}
  end

  defp leave(socket, message) do
    socket |> put_flash(:error, message) |> push_navigate(to: ~p"/")
  end

  @impl true
  # NOTE(Claude-Opus-5.5 2026-11-26): an existing version, whatever the page
  # was opened as (`pending` is `nil` once a new draft is created).
  def handle_event(
        "validate",
        %{"edit_version" => _} = params,
        %{assigns: %{edit: %{pending: nil}}} = socket
      ) do
    socket =
      socket
      |> update(:edit, &track_touched(&1, params))
      |> save_edit(params)
      |> update(:edit, &track_saved(&1, target_column(params)))

    {:noreply, socket}
  end

  # NOTE(Claude-Opus-5.5 2026-11-26): a new dataset or version: its draft is
  # created as soon as the form is valid, and the page becomes its edit page.
  def handle_event(
        "validate",
        params,
        %{assigns: %{edit: edit}} = socket
      )
      when edit.pending != nil do
    params =
      params
      |> Map.take(["edit_dataset", "edit_version", "_target"])
      |> with_prefill(edit.prefill)

    edit = track_touched(edit, params)
    {dataset_changeset, version_changeset} = new_changesets(edit.dataset, params)

    result =
      if dataset_changeset.valid? and version_changeset.valid?,
        do: create_draft(socket, edit, params),
        else: {:error, dataset_changeset, version_changeset}

    case result do
      {:ok, dataset, version, dataset_error} ->
        {:noreply, created(socket, edit, dataset, version, dataset_error)}

      {:error, dataset_changeset, version_changeset} ->
        if edit.pending == :dataset, do: save_draft(socket, params)

        edit = %{
          edit
          | dataset_form: to_form(dataset_changeset, as: "edit_dataset", action: :validate),
            version_form: to_form(version_changeset, as: "edit_version", action: :validate)
        }

        {:noreply, socket |> assign(:edit, edit) |> assign_name_holder()}
    end
  end

  # NOTE(Claude 2026-11-16): publishes the edited draft, checked by
  # `Catalog.publish_dataset_version/2`.
  def handle_event(
        "publish",
        _params,
        %{assigns: %{edit: %{version: %DatasetVersion{}}}} = socket
      ) do
    %{edit: edit} = socket.assigns
    name = "#{proposed_name(edit)} #{edit.version.version}"

    case Catalog.publish_dataset_version(socket.assigns.current_scope, edit.version) do
      {:ok, _version} ->
        {:noreply, socket |> put_flash(:info, "Published #{name}.") |> push_navigate(to: ~p"/")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, publish_error(name, reason))}
    end
  end

  # NOTE(Claude-Opus-5.5 2026-11-26): a draft is deleted for good (see
  # `Catalog.delete_draft_version/2`); before it exists, what was typed is.
  def handle_event("delete_draft", _params, %{assigns: %{edit: %{version: nil} = edit}} = socket) do
    if edit.pending == :dataset, do: :ok = Catalog.delete_dataset_draft(user_id(socket))
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  def handle_event("delete_draft", _params, %{assigns: %{edit: edit}} = socket) do
    name = "#{proposed_name(edit)} #{edit.version.version}"

    case Catalog.delete_draft_version(socket.assigns.current_scope, edit.version) do
      {:ok, _version} ->
        {:noreply,
         socket |> put_flash(:info, "Deleted the draft #{name}.") |> push_navigate(to: ~p"/")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "You cannot delete #{name}.")}
    end
  end

  # NOTE(Claude 2026-11-04): a form event that does not match this page's form,
  # e.g. one sent from a stale page. Nothing to do.
  def handle_event(event, _params, socket)
      when event in ["validate", "publish", "delete_draft"] do
    {:noreply, socket}
  end

  # NOTE(Claude 2026-11-06): a change set was saved, maybe by someone else, maybe
  # to the row being edited. Fields this form has not changed take the new
  # values; fields it has changed keep the form's values and are reported as
  # conflicts. This form's own saves change nothing (the row then equals the
  # form's last saved version).
  # NOTE(Claude 2026-11-16): a Draft's proposed dataset name and description
  # are edited through the dataset's fields of the form.
  @proposed_columns %{"dataset_name" => "name", "dataset_description" => "description"}

  @impl true
  def handle_info({:catalog_changed, _set_id}, %{assigns: %{live_action: :edit}} = socket) do
    %{edit: edit} = socket.assigns

    case Catalog.get_dataset_version(edit.version.id) do
      nil ->
        {:noreply, leave(socket, "This version no longer exists.")}

      %{dataset: dataset} = version ->
        # NOTE(Claude 2026-11-16): the version may have left the viewer's hands
        # meanwhile (archived, or taken over by another editor).
        if Catalog.can?(socket.assigns.current_scope, :write, version) do
          changed =
            (changed_columns(edit.version, version) ++ changed_columns(edit.dataset, dataset))
            |> Enum.map(&Map.get(@proposed_columns, &1, &1))
            |> Enum.uniq()

          if changed == [] do
            {:noreply, socket}
          else
            {:noreply,
             assign(socket, :edit, apply_remote_change(edit, dataset, version, changed))}
          end
        else
          {:noreply, leave(socket, "You can no longer edit this version.")}
        end
    end
  end

  def handle_info({:catalog_changed, _set_id}, socket), do: {:noreply, socket}

  # NOTE(Claude 2026-11-06): the stored columns that differ, as strings.
  @ignored_columns [:id, :inserted_at, :updated_at, :dataset_id, :owning_editor]
  defp changed_columns(%schema{} = old, new) do
    for field <- schema.__schema__(:fields) -- @ignored_columns,
        Map.get(old, field) != Map.get(new, field),
        do: Atom.to_string(field)
  end

  defp apply_remote_change(edit, dataset, version, changed) do
    {conflicts, updated} = Enum.split_with(changed, &MapSet.member?(edit.touched, &1))
    version_params = touched_params(Map.get(edit.params, "edit_version", %{}), edit.touched)

    # NOTE(Claude 2026-11-09): the touched dataset fields only, like the version's.
    dataset_params =
      edit.params
      |> Map.get("edit_dataset", %{})
      |> Map.take(@dataset_fields)
      |> touched_params(edit.touched)

    dataset_changeset =
      Catalog.change_dataset(Catalog.proposed_dataset(dataset, version), dataset_params)

    version_changeset =
      Catalog.change_dataset_version(version, split_version_lists(version_params))

    previous = edit.notice || %{updated: [], conflicts: []}

    %{
      edit
      | dataset: dataset,
        # NOTE(Claude 2026-11-12): the conflicting columns now hold someone
        # else's values: this form's are no longer saved.
        saved: Enum.reduce(conflicts, edit.saved, &MapSet.delete(&2, &1)),
        version: version,
        dataset_form: to_form(dataset_changeset, as: "edit_dataset", action: :validate),
        version_form: to_form(version_changeset, as: "edit_version", action: :validate),
        notice: %{
          updated: Enum.uniq(previous.updated ++ updated) -- conflicts,
          conflicts: Enum.uniq(previous.conflicts ++ conflicts)
        }
    }
  end

  # NOTE(Claude 2026-11-06): which column a form change is about, from the
  # `_target` LiveView sends: the CSV text and the add/remove buttons of a list
  # are about its embed.
  defp track_touched(edit, params) do
    column = target_column(params)
    touched = if column, do: MapSet.put(edit.touched, column), else: edit.touched
    %{edit | touched: touched, params: params}
  end

  # NOTE(Claude 2026-11-12): moved out of `track_touched/2`, for `track_saved/2`.
  defp target_column(params) do
    case params["_target"] do
      ["edit_dataset", field | _] when field in @dataset_fields -> field
      ["edit_version", field | _] -> param_column(field)
      _ -> nil
    end
  end

  # NOTE(Claude 2026-11-12): the columns marked as saved. A save sends the
  # whole form, so once it succeeds every column changed here is saved (some
  # may have waited for another field's error to be fixed). A failed one saves
  # nothing: the changed column and those with errors lose their tick; the
  # others keep it, their earlier value still being saved.
  defp track_saved(%{status: :saved} = edit, _column) do
    %{edit | saved: MapSet.union(edit.saved, edit.touched)}
  end

  defp track_saved(%{status: :invalid} = edit, column) do
    unsaved = [column | error_columns(edit.dataset_form) ++ error_columns(edit.version_form)]
    %{edit | saved: Enum.reduce(unsaved, edit.saved, &MapSet.delete(&2, &1))}
  end

  defp track_saved(edit, _column), do: edit

  defp error_columns(%{source: %Ecto.Changeset{errors: errors}}) do
    for {field, _error} <- errors, do: param_column(Atom.to_string(field))
  end

  defp param_column("data_dictionary_csv"), do: "data_dictionary"
  defp param_column("yearly_counts_csv"), do: "yearly_counts"
  defp param_column("doc_links_sort"), do: "doc_links"
  defp param_column("doc_links_drop"), do: "doc_links"
  defp param_column("locations_sort"), do: "locations"
  defp param_column("locations_drop"), do: "locations"
  # NOTE(Claude Opus 5.5 2026-11-18): the Not applicable checkboxes set the
  # `not_applicable` column (see `DatasetVersion`).
  defp param_column("years_not_applicable"), do: "not_applicable"
  defp param_column("cohort_size_not_applicable"), do: "not_applicable"
  defp param_column(field), do: field

  # NOTE(Claude 2026-11-06): the form params of the touched columns only.
  defp touched_params(version_params, touched) do
    Map.filter(version_params, fn {key, _value} -> MapSet.member?(touched, param_column(key)) end)
  end

  @field_labels %{
    "name" => "Dataset",
    "description" => "Description",
    "version" => "Version",
    "release_date" => "Release date",
    "tags" => "Tags",
    "environments" => "Environments",
    "access_type" => "Access type",
    "modalities" => "Modality",
    "formats" => "Format",
    "doc_links" => "Documentation",
    "locations" => "Locations",
    "data_dictionary" => "Data dictionary",
    "data_quality" => "Data quality",
    "omop_integration" => "OMOP-mapped",
    "coverage_start" => "Start year",
    "coverage_end" => "End year",
    "yearly_counts" => "Data points per year",
    "cohort_size" => "Individuals covered",
    "not_applicable" => "Not applicable",
    "lead" => "Maintainer",
    "state" => "State",
    "archived_at" => "Archived",
    "owning_editor_id" => "Owning editor"
  }

  defp field_list(columns) do
    columns |> Enum.map(&Map.get(@field_labels, &1, &1)) |> Enum.join(", ")
  end

  # NOTE(Claude 2026-11-03): each valid change to the edited version is saved at
  # once, without approval, as one change set in the changelog. Invalid changes
  # are shown with their errors and not saved.
  defp save_edit(socket, %{"edit_version" => version_params} = params) do
    %{dataset: dataset, version: version} = edit = socket.assigns.edit
    # NOTE(Claude 2026-11-17): through any version, no longer the current one only.
    dataset_params = Map.get(params, "edit_dataset", %{})
    version_params = split_version_lists(version_params)

    dataset_changeset =
      Catalog.change_dataset(Catalog.proposed_dataset(dataset, version), dataset_params)

    version_changeset = Catalog.change_dataset_version(version, version_params)

    result =
      if dataset_changeset.valid? and version_changeset.valid? do
        Catalog.update_dataset_row(dataset, dataset_params, version, version_params,
          scope: socket.assigns.current_scope
        )
      else
        :invalid
      end

    # NOTE(Claude 2026-11-16): refused (`:unauthorized`) when the version left
    # the viewer's hands since the page loaded: the page is left.
    {edit, dataset_changeset, version_changeset} =
      case result do
        {:error, :unauthorized} ->
          {%{edit | status: :invalid}, dataset_changeset, version_changeset}

        {:ok, %{dataset: dataset, version: version}} ->
          {%{edit | dataset: dataset, version: version, status: :saved}, dataset_changeset,
           version_changeset}

        {:error, %Ecto.Changeset{data: %Dataset{}} = changeset} ->
          {%{edit | status: :invalid}, changeset, version_changeset}

        {:error, %Ecto.Changeset{} = changeset} ->
          {%{edit | status: :invalid}, dataset_changeset, changeset}

        :invalid ->
          {%{edit | status: :invalid}, dataset_changeset, version_changeset}
      end

    socket =
      assign(socket, :edit, %{
        edit
        | dataset_form: to_form(dataset_changeset, as: "edit_dataset", action: :validate),
          version_form: to_form(version_changeset, as: "edit_version", action: :validate)
      })

    if result == {:error, :unauthorized},
      do: leave(socket, "You can no longer edit this version."),
      else: socket
  end

  # NOTE(Claude 2026-11-16): the dataset's name as the edited version shows it.
  defp proposed_name(edit), do: Catalog.proposed_dataset(edit.dataset, edit.version).name

  defp publish_error(name, :unauthorized), do: "You cannot publish #{name}."

  defp publish_error(name, %Ecto.Changeset{} = changeset) do
    reasons =
      Enum.map_join(changeset.errors, "; ", fn {field, {message, _opts}} ->
        "#{Map.get(@field_labels, Atom.to_string(field), field)} #{message}"
      end)

    "#{name} was not published: #{reasons}."
  end

  # NOTE(Claude 2026-11-12): who made a change (the signed-in user's email),
  # for the changelog.
  defp actor(socket), do: Scope.actor(socket.assigns.current_scope)

  # NOTE(Claude 2026-11-12): the signed-in user's id, as a draft's submitter
  # and as the owner of the autosaved new dataset.
  defp user_id(socket), do: Scope.user_id(socket.assigns.current_scope)

  # NOTE(Claude 2026-11-16): the viewer, for the `Catalog` functions that show
  # Drafts to editors only.
  defp viewer(socket), do: socket.assigns.current_scope

  # NOTE(Claude 2026-11-06): the dataset already holding the typed name, if
  # any, so the form can say why the name is taken and what to do instead.
  # NOTE(Claude-Opus-5.5 2026-11-26): on the new dataset page only.
  defp assign_name_holder(%{assigns: %{edit: %{pending: :dataset} = edit}} = socket) do
    name = get_in(edit.params, ["edit_dataset", "name"])
    holder = Catalog.dataset_name_holder(name, viewer(socket))
    assign(socket, :edit, %{edit | name_holder: holder})
  end

  defp assign_name_holder(socket), do: socket

  defp form_title(:new, %{pending: :dataset}), do: "Add missing dataset"

  defp form_title(:new_version, %{pending: :version, dataset: dataset}),
    do: "Add a version of #{dataset.name}"

  defp form_title(_action, edit), do: "Edit #{proposed_name(edit)} #{edit.version.version}"

  # NOTE(Claude-Opus-5.5 2026-11-26): the footer's actions the viewer may do
  # with the edited version (none before it exists).
  defp actions(_scope, nil), do: %{}

  defp actions(scope, version),
    do: Map.new([:publish, :delete], &{&1, Catalog.can?(scope, &1, version)})

  # NOTE(Claude-Opus-5.5 2026-11-26): creates the draft of a new dataset or
  # version from valid `params`, as a Draft owned by the viewer. For a new version,
  # the dataset's name and description, if changed, are then saved through it
  # (see `Catalog.update_dataset_row/5`), as on the edit page; if that fails
  # (e.g. the name is taken), the draft exists anyway and the error is shown.
  # Returns `{:ok, dataset, version, dataset_error}` (`dataset_error` a
  # changeset or `nil`) or `{:error, dataset_changeset, version_changeset}`.
  defp create_draft(socket, %{pending: :dataset} = edit, params) do
    attrs =
      params
      |> Map.get("edit_dataset", %{})
      |> Map.put("versions", %{"0" => split_version_lists(params["edit_version"])})

    case Catalog.create_dataset_with_version(attrs,
           actor: actor(socket),
           owning_editor_id: user_id(socket)
         ) do
      {:ok, %Dataset{versions: [version]} = dataset} ->
        :ok = Catalog.delete_dataset_draft(user_id(socket))
        {:ok, dataset, version, nil}

      {:error, changeset} ->
        {_dataset, version_changeset} = new_changesets(edit.dataset, params)
        {:error, changeset, version_changeset}
    end
  end

  defp create_draft(socket, %{pending: :version, dataset: dataset}, params) do
    dataset_params = Map.get(params, "edit_dataset", %{})
    version_params = split_version_lists(params["edit_version"])

    case Catalog.create_dataset_version(dataset, version_params,
           actor: actor(socket),
           owning_editor_id: user_id(socket)
         ) do
      {:ok, version} ->
        if dataset_changed?(dataset, dataset_params) do
          case Catalog.update_dataset_row(dataset, dataset_params, version, %{},
                 scope: socket.assigns.current_scope
               ) do
            {:ok, %{dataset: dataset, version: version}} -> {:ok, dataset, version, nil}
            {:error, %Ecto.Changeset{} = changeset} -> {:ok, dataset, version, changeset}
          end
        else
          {:ok, dataset, version, nil}
        end

      {:error, changeset} ->
        {dataset_changeset, _version} = new_changesets(dataset, params)
        {:error, dataset_changeset, changeset}
    end
  end

  defp dataset_changed?(dataset, params) do
    Catalog.change_dataset(dataset, Map.take(params, @dataset_fields)).changes != %{}
  end

  # NOTE(Claude-Opus-5.5 2026-11-26): the page becomes the new draft's edit
  # page: same LiveView and form, so the fields and the focus stay; the URL
  # changes with a patch.
  defp created(socket, edit, dataset, version, dataset_error) do
    version = Repo.preload(version, :owning_editor, force: true)
    if connected?(socket), do: Changelog.subscribe()

    new = existing_edit(dataset, version)

    dataset_form =
      if dataset_error,
        do: to_form(dataset_error, as: "edit_dataset", action: :validate),
        else: new.dataset_form

    saved =
      if dataset_error,
        do: MapSet.difference(edit.touched, MapSet.new(@dataset_fields)),
        else: edit.touched

    socket
    |> assign(:edit, %{
      new
      | touched: edit.touched,
        params: edit.params,
        saved: saved,
        status: if(dataset_error, do: :invalid, else: :saved),
        dataset_form: dataset_form
    })
    |> assign(:page_title, "Edit #{dataset.name} #{version.version}")
    |> push_patch(to: ~p"/versions/#{version.id}/edit", replace: true)
  end

  # NOTE(Claude 2026-11-16): the versions this viewer may see (see
  # `Catalog.list_datasets/1`): Published ones, and every Draft for editors.
  defp visible_datasets(socket) do
    Catalog.list_datasets(viewer(socket))
  end

  # NOTE(Claude 2026-11-03): looked up among the versions the viewer may see;
  # whether they may edit it is `Catalog.can?/3`.
  defp find_row(datasets, id) do
    with {id, ""} <- Integer.parse(to_string(id)) do
      Enum.find_value(datasets, fn dataset ->
        case Enum.find_index(dataset.versions, &(&1.id == id)) do
          nil -> nil
          index -> {dataset, Enum.at(dataset.versions, index), index == 0}
        end
      end)
    else
      _ -> nil
    end
  end

  # NOTE(Claude-Opus-5.5 2026-11-26): the form params of a new dataset, kept
  # for its user until its draft is created. Stored in the former form's shape
  # (the dataset's fields and `versions`, with one version; see
  # `upgrade_autosave/1`), which the releases before 2026-11-26 read too, so
  # that a rollback keeps them.
  defp save_draft(socket, params) do
    stored =
      params
      |> Map.get("edit_dataset", %{})
      |> Map.take(@dataset_fields)
      |> Map.put("versions", %{"0" => Map.get(params, "edit_version", %{})})

    if user_id = user_id(socket), do: {:ok, _} = Catalog.save_dataset_draft(user_id, stored)
  end

  # NOTE(Claude 2026-11-10): shared with the catalog's quick edit.
  defp split_version_lists(version), do: VersionParams.split_lists(version)
end
