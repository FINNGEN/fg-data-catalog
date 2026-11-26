defmodule FGDataCatalogWeb.DatasetLive.Form do
  @moduledoc """
  The dataset form pages: a new dataset (`/datasets/new`), a new version of
  an existing dataset (`/datasets/:id/versions/new`) and an existing version
  (`/versions/:id/edit`).

  A new dataset is saved as a draft as it is typed, and created on Submit.
  A new version is created on Submit. An existing version saves each valid
  change at once.
  """
  # NOTE(Claude 2026-11-04): moved out of `DatasetLive.Index`, where the forms
  # were first table rows and then a modal, to give them a page of their own.
  use FGDataCatalogWeb, :live_view

  import FGDataCatalogWeb.DatasetFormComponents
  import FGDataCatalogWeb.CatalogComponents, only: [status_badge: 1]

  alias FGDataCatalog.Accounts.Scope
  alias FGDataCatalog.Catalog
  alias FGDataCatalog.Changelog
  alias FGDataCatalog.Catalog.{Dataset, DatasetVersion}
  alias FGDataCatalogWeb.DatasetLive.VersionParams

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

        <%= cond do %>
          <% @live_action == :new -> %>
            <h1 id="form-title">Add missing dataset</h1>
            <.new_dataset_form
              form={@form}
              suggestions={@suggestions}
              name_holder={@name_holder}
            />
          <% @live_action == :new_version -> %>
            <h1 id="form-title">Add a version of {@dataset.name}</h1>
            <p :if={@source} id="prefilled-from" class="form-note">
              Prefilled from {@source.version}. Version, release date, data dictionary,
              years coverage, yearly counts and individuals covered start empty; the fields
              marked Not applicable stay so.
            </p>
            <.new_version_form form={@form} dataset={@dataset} suggestions={@suggestions} />
          <% true -> %>
            <h1 id="form-title">Edit {proposed_name(@edit)} {@edit.version.version}</h1>
            <%!-- NOTE(Claude 2026-11-16): the version's state, and Publish for its
                 owning editor while it is a Draft (see `Catalog.can?/3`). --%>
            <div id="edit-state" class="form-note edit-state">
              <.status_badge
                id={"status-#{@edit.version.id}"}
                state={@edit.version.state}
                owner={@edit.version.owning_editor}
              />
              <span :if={@edit.version.state == :draft}>
                Only its owning editor may edit and publish a Draft; other editors see it.
              </span>
              <button
                :if={Catalog.can?(@current_scope, :publish, @edit.version)}
                type="button"
                id="edit-publish"
                class="link-button"
                phx-click="publish"
              >
                Publish
              </button>
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
            <.edit_version_form
              dataset_form={@edit.dataset_form}
              version_form={@edit.version_form}
              status={@edit.status}
              saved={MapSet.to_list(@edit.saved)}
              suggestions={@suggestions}
            />
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    # NOTE(Claude 2026-11-04): existing values, suggested while typing the Tags,
    # Modality and Format fields.
    socket =
      socket
      |> assign(:suggestions, %{
        tags: Catalog.list_tags(),
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

  defp mount_action(socket, :new, _params) do
    # NOTE(Claude 2026-11-03): an unsaved new dataset from an earlier visit is
    # shown again, as it was left.
    draft = Catalog.get_dataset_draft_params(user_id(socket))

    socket
    |> assign(:page_title, "Add missing dataset")
    |> assign(:form, build_new_form(draft || %{}))
    |> assign_name_holder(draft || %{})
  end

  # NOTE(Claude 2026-11-06): prefilled from the dataset's latest version; nothing
  # is saved until Submit.
  defp mount_action(socket, :new_version, %{"id" => id}) do
    with {id, ""} <- Integer.parse(id),
         {dataset, source} <-
           Catalog.get_dataset_for_new_version(id, viewer(socket)) do
      params = Catalog.new_version_params(source)

      socket
      |> assign(:page_title, "Add a version of #{dataset.name}")
      |> assign(:dataset, dataset)
      |> assign(:source, source)
      |> assign(:form, to_form(new_version_changeset(dataset, params), as: "version"))
    else
      _ -> leave(socket, "That dataset was not found.")
    end
  end

  # NOTE(Claude 2026-11-16): only a version the viewer may write (see
  # `Catalog.can?/3`): not a Draft owned by someone else.
  defp mount_action(socket, :edit, %{"id" => id}) do
    with {dataset, version, _current} <- find_row(visible_datasets(socket), id),
         true <- Catalog.can?(socket.assigns.current_scope, :write, version) do
      edit = %{
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

      # NOTE(Claude 2026-11-06): to follow other people's changes to the row.
      if connected?(socket), do: Changelog.subscribe()

      socket
      |> assign(:page_title, "Edit #{dataset.name} #{version.version}")
      |> assign(:edit, edit)
    else
      nil -> leave(socket, "That dataset version was not found.")
      false -> leave(socket, "You cannot edit that version.")
    end
  end

  defp leave(socket, message) do
    socket |> put_flash(:error, message) |> push_navigate(to: ~p"/")
  end

  @impl true
  def handle_event(
        "validate",
        %{"edit_version" => _} = params,
        %{assigns: %{live_action: :edit}} = socket
      ) do
    socket =
      socket
      |> update(:edit, &track_touched(&1, params))
      |> save_edit(params)
      |> update(:edit, &track_saved(&1, target_column(params)))

    {:noreply, socket}
  end

  def handle_event("validate", %{"dataset" => params}, %{assigns: %{live_action: :new}} = socket) do
    save_draft(socket, params)

    {:noreply,
     socket
     |> assign(:form, to_form(new_dataset_changeset(params), action: :validate))
     |> assign_name_holder(params)}
  end

  def handle_event("save", %{"dataset" => params}, %{assigns: %{live_action: :new}} = socket) do
    # NOTE(Claude 2026-11-16): every new dataset is a Draft owned by its creator.
    case Catalog.create_dataset_with_version(with_version(params) |> split_lists(),
           actor: actor(socket),
           state: :draft,
           owning_editor_id: user_id(socket)
         ) do
      {:ok, dataset} ->
        :ok = Catalog.delete_dataset_draft(user_id(socket))

        {:noreply,
         socket
         |> put_flash(:info, added_message(dataset.name))
         |> push_navigate(to: ~p"/")}

      {:error, changeset} ->
        save_draft(socket, params)
        {:noreply, socket |> assign(:form, to_form(changeset)) |> assign_name_holder(params)}
    end
  end

  def handle_event(
        "validate",
        %{"version" => params},
        %{assigns: %{live_action: :new_version}} = socket
      ) do
    changeset = new_version_changeset(socket.assigns.dataset, split_version_lists(params))
    {:noreply, assign(socket, :form, to_form(changeset, as: "version", action: :validate))}
  end

  def handle_event(
        "save",
        %{"version" => params},
        %{assigns: %{live_action: :new_version}} = socket
      ) do
    %{dataset: dataset} = socket.assigns

    # NOTE(Claude 2026-11-16): every new version is a Draft owned by its creator.
    case Catalog.create_dataset_version(dataset, split_version_lists(params),
           actor: actor(socket),
           state: :draft,
           owning_editor_id: user_id(socket)
         ) do
      {:ok, version} ->
        {:noreply,
         socket
         |> put_flash(:info, added_message("#{dataset.name} #{version.version}"))
         |> push_navigate(to: ~p"/")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "version"))}
    end
  end

  # NOTE(Claude 2026-11-16): publishes the edited Draft, checked by
  # `Catalog.publish_dataset_version/2`.
  def handle_event("publish", _params, %{assigns: %{live_action: :edit}} = socket) do
    %{edit: edit} = socket.assigns
    name = "#{proposed_name(edit)} #{edit.version.version}"

    case Catalog.publish_dataset_version(socket.assigns.current_scope, edit.version) do
      {:ok, _version} ->
        {:noreply, socket |> put_flash(:info, "Published #{name}.") |> push_navigate(to: ~p"/")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, publish_error(name, reason))}
    end
  end

  def handle_event("discard", _params, %{assigns: %{live_action: :new}} = socket) do
    :ok = Catalog.delete_dataset_draft(user_id(socket))
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  # NOTE(Claude 2026-11-04): a form event that does not match this page's form,
  # e.g. one sent from a stale page. Nothing to do.
  def handle_event(event, _params, socket)
      when event in ["validate", "save", "discard", "publish"] do
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

  # NOTE(Claude 2026-11-17): the dataset's own fields on the edit form (those of
  # `edit_dataset`), editable through any version.
  @dataset_fields ~w(name description)

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
  defp assign_name_holder(socket, params) do
    holder =
      Catalog.dataset_name_holder(params["name"], viewer(socket))

    assign(socket, :name_holder, holder)
  end

  # NOTE(Claude 2026-11-16): every new dataset or version is a Draft.
  defp added_message(name),
    do: "Added #{name} as a Draft: publish it from the catalog when it is ready."

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

  defp save_draft(socket, params) do
    if user_id = user_id(socket), do: {:ok, _} = Catalog.save_dataset_draft(user_id, params)
  end

  # NOTE(Claude 2026-11-03): without an action, a restored draft shows no errors
  # until the user edits it again.
  defp build_new_form(params), do: params |> new_dataset_changeset() |> to_form()

  defp new_version_changeset(dataset, params) do
    Catalog.change_dataset_version(%DatasetVersion{dataset_id: dataset.id}, params)
  end

  defp new_dataset_changeset(params) do
    Catalog.change_new_dataset(%Dataset{}, params |> with_version() |> split_lists())
  end

  # NOTE(Claude 2026-11-04): always one version, otherwise its fields (rendered
  # by `inputs_for` over the versions) would vanish.
  defp with_version(params), do: Map.put_new(params, "versions", %{"0" => %{}})

  defp split_lists(%{"versions" => versions} = params) when is_map(versions) do
    %{params | "versions" => Map.new(versions, fn {key, v} -> {key, split_version_lists(v)} end)}
  end

  defp split_lists(params), do: params

  # NOTE(Claude 2026-11-10): shared with the catalog's quick edit.
  defp split_version_lists(version), do: VersionParams.split_lists(version)
end
