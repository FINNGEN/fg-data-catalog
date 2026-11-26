defmodule FGDataCatalogWeb.DatasetFormComponents do
  @moduledoc """
  The dataset forms, each shown on a page of its own (see
  `FGDataCatalogWeb.DatasetLive.Form`): the "new dataset" form and the form of
  an existing version being edited. Fields are laid out vertically, in the
  order of the catalog columns.
  """
  use FGDataCatalogWeb, :html

  alias FGDataCatalog.Catalog.{DataQuality, Dataset, DatasetVersion, Location}

  # NOTE(Claude 2026-11-03): typing pauses this long (ms) before a change is
  # sent, and so autosaved. Leaving a field sends it at once.
  @debounce "300"

  @doc """
  Renders the form for a new dataset and its first version.
  """
  attr :form, Phoenix.HTML.Form, required: true
  attr :suggestions, :map, default: %{}

  attr :name_holder, :any,
    default: nil,
    doc: "the dataset holding the typed name, see `Catalog.dataset_name_holder/2`"

  def new_dataset_form(assigns) do
    assigns = assign(assigns, :debounce, @debounce)

    ~H"""
    <.form
      for={@form}
      id="dataset-form"
      class="dataset-form"
      phx-change="validate"
      phx-submit="save"
    >
      <div class="form-fields">
        <.required_note id="dataset-form-required-note" />
        <.input
          field={@form[:name]}
          type="text"
          label="Dataset"
          phx-debounce={@debounce}
          mark_required
          autofocus
        />
        <.name_holder_note :if={@name_holder} holder={@name_holder} />
        <.description_input field={@form[:description]} debounce={@debounce} />
        <.inputs_for :let={v} field={@form[:versions]}>
          <.version_fields form={v} debounce={@debounce} suggestions={@suggestions} />
        </.inputs_for>
      </div>
      <%!-- NOTE(Claude 2026-11-12): the status and buttons stay in view (see
           `.form-footer`), next to the fields on a wide screen. --%>
      <div id="dataset-form-footer" class="form-footer">
        <p class="draft-status">Changes are saved as a draft as you type.</p>
        <div class="form-actions">
          <.button id="submit-dataset" variant="primary" phx-disable-with="Submitting…">
            Submit
          </.button>
          <button
            id="discard-dataset"
            type="button"
            phx-click="discard"
            data-confirm="Discard this new dataset?"
          >
            Discard
          </button>
        </div>
      </div>
    </.form>
    """
  end

  # NOTE(Claude 2026-11-06): why the typed name is taken, and what to do
  # instead: add a version to the dataset that holds it, or unarchive it.
  # NOTE(Claude 2026-11-16): every editor may unarchive a version or add one to
  # any dataset (the page is for editors only).
  attr :holder, :any, required: true

  defp name_holder_note(%{holder: {kind, dataset}} = assigns) do
    assigns = assign(assigns, kind: kind, dataset: dataset)

    ~H"""
    <div id="name-holder" class="form-note" role="status">
      <%= case @kind do %>
        <% :listed -> %>
          <p>
            {@dataset.name} is already in the catalog.
            <.link id="name-holder-add-version" navigate={~p"/datasets/#{@dataset.id}/versions/new"}>
              Add a version of it
            </.link>
            instead.
          </p>
        <% :archived -> %>
          <p>
            This name belongs to an archived dataset, which is no longer in the catalog.
            <.link id="name-holder-archive" navigate={~p"/archive"}>Unarchive it</.link>
            or
            <.link
              id="name-holder-add-version"
              navigate={~p"/datasets/#{@dataset.id}/versions/new"}
            >
              add a new version of it
            </.link>
            instead.
          </p>
        <% :unpublished -> %>
          <p>
            This name belongs to a dataset that is not published yet. Choose
            another name.
          </p>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders the form of a new version of `dataset`, created on Submit.
  """
  # NOTE(Claude 2026-11-06): no autosaved draft, unlike the new dataset form.
  attr :form, Phoenix.HTML.Form, required: true
  attr :dataset, :map, required: true
  attr :suggestions, :map, default: %{}

  def new_version_form(assigns) do
    assigns = assign(assigns, :debounce, @debounce)

    ~H"""
    <.form
      for={@form}
      id="version-form"
      class="dataset-form"
      phx-change="validate"
      phx-submit="save"
    >
      <div class="form-fields">
        <.required_note id="version-form-required-note" />
        <.version_fields
          form={@form}
          debounce={@debounce}
          suggestions={@suggestions}
          autofocus_version
        />
      </div>
      <%!-- NOTE(Claude 2026-11-12): the status and buttons stay in view (see
           `.form-footer`), next to the fields on a wide screen. --%>
      <div id="version-form-footer" class="form-footer">
        <div class="form-actions">
          <.button id="submit-version" variant="primary" phx-disable-with="Submitting…">
            Submit
          </.button>
          <.link id="cancel-version" navigate={~p"/"}>Cancel</.link>
        </div>
      </div>
    </.form>
    """
  end

  @doc """
  Renders the form of an existing version. Each valid change is saved at once
  (see `FGDataCatalogWeb.DatasetLive.Form`).

  NOTE(Claude 2026-11-17): the dataset's name and description are editable
  through any version, not only the current one (see
  `FGDataCatalog.Catalog.update_dataset_row/5` for where they are saved).
  """
  attr :dataset_form, Phoenix.HTML.Form, required: true
  attr :version_form, Phoenix.HTML.Form, required: true
  attr :status, :atom, values: [:idle, :saved, :invalid], required: true

  attr :saved, :list,
    default: [],
    doc: "the columns (as strings) changed in this form and saved, marked with a tick"

  attr :suggestions, :map, default: %{}

  def edit_version_form(assigns) do
    assigns = assign(assigns, :debounce, @debounce)

    ~H"""
    <%!-- NOTE(Claude 2026-11-04): Enter submits the form, which just saves it
         like any other change. --%>
    <.form
      for={@version_form}
      id="edit-form"
      class="dataset-form"
      phx-change="validate"
      phx-submit="validate"
    >
      <div class="form-fields">
        <.required_note id="edit-form-required-note" />
        <.input
          field={@dataset_form[:name]}
          type="text"
          label="Dataset"
          phx-debounce={@debounce}
          saved={"name" in @saved}
          mark_required
          autofocus
        />
        <.description_input
          field={@dataset_form[:description]}
          debounce={@debounce}
          saved={"description" in @saved}
        />
        <.version_fields
          form={@version_form}
          debounce={@debounce}
          suggestions={@suggestions}
          saved={@saved}
        />
      </div>
      <%!-- NOTE(Claude 2026-11-12): the status and buttons stay in view (see
           `.form-footer`), next to the fields on a wide screen. --%>
      <div id="edit-form-footer" class="form-footer">
        <p id="edit-status" class="draft-status" role="status">
          {edit_status(@status)}
        </p>
        <div class="form-actions">
          <.button id="done-editing" variant="primary" navigate={~p"/"}>Done</.button>
        </div>
      </div>
    </.form>
    """
  end

  # NOTE(Claude Opus 5.5 2026-11-17): the dataset's description (optional, as
  # every unmarked field), right under its name, as in the catalog. `maxlength` stops typing at the changeset's limit.
  attr :field, Phoenix.HTML.FormField, required: true
  attr :debounce, :string, required: true
  attr :saved, :boolean, default: false

  defp description_input(assigns) do
    ~H"""
    <.input
      field={@field}
      type="text"
      label="Description (a few words)"
      placeholder="Laboratory test results from Kanta"
      maxlength={Dataset.description_max_length()}
      phx-debounce={@debounce}
      saved={@saved}
    />
    """
  end

  defp edit_status(:idle), do: "Changes are saved as you type."
  defp edit_status(:saved), do: "Saved."
  defp edit_status(:invalid), do: "Not saved: fix the errors in this form."

  @doc false
  attr :form, Phoenix.HTML.Form, required: true
  attr :debounce, :string, required: true
  attr :suggestions, :map, default: %{}
  attr :autofocus_version, :boolean, default: false

  attr :only, :list,
    default: nil,
    doc: "the fields to show (see `show_field?/2`), or `nil` for all; the quick edit shows one"

  attr :saved, :list,
    default: [],
    doc: "the columns (as strings) marked as saved, see `edit_version_form/1`"

  # NOTE(Claude 2026-11-04): the version's fields, one under the other, shared
  # by the new dataset form and the edit form. Related fields are grouped.
  # NOTE(Claude 2026-11-10): and by the catalog's quick edit, which shows one
  # field (or group) with `only`.
  def version_fields(assigns) do
    ~H"""
    <.input
      :if={show_field?(@only, :version)}
      field={@form[:version]}
      type="text"
      label="Version"
      placeholder="R14"
      phx-debounce={@debounce}
      saved={"version" in @saved}
      mark_required
      autofocus={@autofocus_version}
    />
    <.input
      :if={show_field?(@only, :release_date)}
      field={@form[:release_date]}
      type="date"
      label="Release date"
      min={first_release_date()}
      max={last_release_date()}
      saved={"release_date" in @saved}
      mark_required
    />
    <.suggest_input
      :if={show_field?(@only, :tags)}
      field={@form[:tags]}
      label="Tags (comma-separated)"
      suggestions={Map.get(@suggestions, :tags, [])}
      debounce={@debounce}
      saved={"tags" in @saved}
    />
    <script :type={Phoenix.LiveView.ColocatedHook} name=".TokenSuggest">
      export default {
        mounted() {
          const input = this.el
          const list = document.getElementById(input.dataset.list)
          let matches = []
          let active = -1

          // The comma-separated token the caret is in: its bounds and text.
          const token = () => {
            const caret = input.selectionStart ?? input.value.length
            const start = input.value.lastIndexOf(",", caret - 1) + 1
            let end = input.value.indexOf(",", caret)
            if (end === -1) end = input.value.length
            return { start, end, text: input.value.slice(start, end).trim() }
          }

          // NOTE(Claude 2026-11-16): the list is `position: fixed`, placed from
          // the field's box in the window, so that a scrolling ancestor (the
          // catalog table's `.table-scroll`) does not clip it. It opens below
          // the field, or above when there is more room there (a field near
          // the window's or the table's bottom), and as tall as fits.
          const field = input.closest(".suggest") || input
          const GAP = 2
          const MARGIN = 8
          const place = () => {
            if (list.hidden) return
            const box = field.getBoundingClientRect()
            list.style.left = `${box.left}px`
            list.style.width = `${box.width}px`
            list.style.maxHeight = ""
            const below = window.innerHeight - box.bottom - GAP - MARGIN
            const above = box.top - GAP - MARGIN
            const height = list.scrollHeight
            if (height <= below || below >= above) {
              list.style.top = `${box.bottom + GAP}px`
              list.style.bottom = ""
              list.style.maxHeight = `${Math.max(below, 0)}px`
            } else {
              list.style.top = ""
              list.style.bottom = `${window.innerHeight - box.top + GAP}px`
              list.style.maxHeight = `${Math.max(above, 0)}px`
            }
          }

          // NOTE(Claude 2026-11-16): kept in place while open when the page or
          // the table scrolls (captured: scroll events do not bubble), or the
          // window is resized.
          const onMove = () => place()
          const listen = (on) => {
            const method = on ? "addEventListener" : "removeEventListener"
            window[method]("scroll", onMove, true)
            window[method]("resize", onMove)
          }
          this.unlisten = () => listen(false)

          const close = () => { list.hidden = true; active = -1; listen(false) }

          const highlight = (i) => {
            active = i
            Array.from(list.children).forEach((li, j) =>
              li.setAttribute("aria-selected", String(j === i)))
          }

          const choose = (tag) => {
            const { start, end } = token()
            const before = input.value.slice(0, start).replace(/\s+$/, "")
            const after = input.value.slice(end).replace(/^,?\s*/, "")
            const head = before === "" ? "" : before + " "
            const inserted = head + tag + ", "
            input.value = inserted + after
            input.setSelectionRange(inserted.length, inserted.length)
            close()
            input.dispatchEvent(new Event("input", { bubbles: true }))
            input.focus()
          }

          const MAX_SUGGESTIONS = 8

          const render = () => {
            const all = JSON.parse(input.dataset.suggestions || "[]")
            const { text } = token()
            const used = new Set(
              input.value.split(",").map((t) => t.trim().toLowerCase()))
            const q = text.toLowerCase()
            const prefix = (t) => t.toLowerCase().startsWith(q)
            // NOTE(Claude 2026-11-04): with nothing typed yet, the first
            // MAX_SUGGESTIONS unused values are listed (all of them match "").
            matches = all
              .filter((t) => t.toLowerCase().includes(q) && !used.has(t.toLowerCase()))
              .sort((a, b) => Number(prefix(b)) - Number(prefix(a)))
              .slice(0, MAX_SUGGESTIONS)
            list.replaceChildren(...matches.map((tag) => {
              const li = document.createElement("li")
              li.setAttribute("role", "option")
              li.textContent = tag
              // mousedown, not click: it fires before the input loses focus.
              li.addEventListener("mousedown", (e) => { e.preventDefault(); choose(tag) })
              return li
            }))
            list.hidden = matches.length === 0
            active = -1
            listen(false)
            if (!list.hidden) { place(); listen(true) }
          }

          input.addEventListener("input", render)
          // NOTE(Claude 2026-11-04): focus lists the suggestions before anything is
          // typed; click re-opens the list after Escape or choosing one.
          input.addEventListener("focus", render)
          input.addEventListener("click", render)
          input.addEventListener("blur", close)
          input.addEventListener("keydown", (e) => {
            if (list.hidden) return
            if (e.key === "ArrowDown") {
              e.preventDefault(); highlight((active + 1) % matches.length)
            } else if (e.key === "ArrowUp") {
              e.preventDefault(); highlight((active - 1 + matches.length) % matches.length)
            } else if ((e.key === "Enter" || e.key === "Tab") && active >= 0) {
              e.preventDefault(); choose(matches[active])
            } else if (e.key === "Escape") {
              e.preventDefault(); close()
            }
          })
        },
        destroyed() {
          this.unlisten && this.unlisten()
        }
      }
    </script>
    <.input
      :if={show_field?(@only, :environments)}
      field={@form[:environments]}
      type="text"
      label="Environments (comma-separated)"
      value={join_list(@form[:environments].value)}
      phx-debounce={@debounce}
      saved={"environments" in @saved}
    />
    <.input
      :if={show_field?(@only, :access_type)}
      field={@form[:access_type]}
      type="select"
      label="Access type"
      prompt="Choose…"
      options={access_type_options()}
      saved={"access_type" in @saved}
    />
    <%!-- NOTE(Claude 2026-11-04): modality is what the data is, format is how it is
         stored or delivered; the two vary independently. --%>
    <.suggest_input
      :if={show_field?(@only, :modalities)}
      field={@form[:modalities]}
      label="Modality (comma-separated)"
      placeholder="Free text, Genes, Lab measurements"
      suggestions={Map.get(@suggestions, :modalities, [])}
      debounce={@debounce}
      saved={"modalities" in @saved}
    />
    <.suggest_input
      :if={show_field?(@only, :formats)}
      field={@form[:formats]}
      label="Format (comma-separated)"
      placeholder="CSV.gz, Parquet, BigQuery table"
      suggestions={Map.get(@suggestions, :formats, [])}
      debounce={@debounce}
      saved={"formats" in @saved}
    />
    <.embed_list
      :if={show_field?(@only, :doc_links)}
      form={@form}
      field={:doc_links}
      legend="Documentation"
      add_label="Add entry"
      saved={"doc_links" in @saved}
    >
      <:row :let={link}>
        <.input
          field={link[:kind]}
          type="select"
          label="Type"
          options={[{"Link", "link"}, {"Text (e.g. README contents)", "text"}]}
        />
        <.input
          field={link[:label]}
          type="text"
          label="Label"
          placeholder="README"
          phx-debounce={@debounce}
        />
        <%!-- NOTE(Claude 2026-11-04): the kind decides which content input is shown. --%>
        <.input
          :if={to_string(link[:kind].value) != "text"}
          field={link[:url]}
          type="url"
          label="URL"
          phx-debounce={@debounce}
        />
        <.input
          :if={to_string(link[:kind].value) == "text"}
          field={link[:text]}
          type="textarea"
          label="Text"
          rows="8"
          phx-debounce={@debounce}
        />
      </:row>
    </.embed_list>
    <.embed_list
      :if={show_field?(@only, :locations)}
      form={@form}
      field={:locations}
      legend="Locations"
      add_label="Add location"
      saved={"locations" in @saved}
    >
      <:row :let={location}>
        <.input
          field={location[:label]}
          type="text"
          label="Label (optional)"
          maxlength={Location.label_max_length()}
          phx-debounce={@debounce}
        />
        <.input
          field={location[:value]}
          type="text"
          label="Web link, Unix path or gs:// path"
          placeholder="https://…, /research/shared-data/… or gs://bucket/…"
          phx-debounce={@debounce}
        />
      </:row>
    </.embed_list>
    <.csv_input
      :if={show_field?(@only, :data_dictionary)}
      form={@form}
      embed={:data_dictionary}
      label="Data dictionary (CSV: column,details ; or cells pasted from a spreadsheet)"
      placeholder={"FINNGENID,Participant identifier\nEVENT_AGE,\"Age at event, in years\""}
      debounce={@debounce}
      saved={"data_dictionary" in @saved}
    />
    <%!-- NOTE(Claude 2026-11-16): the data quality answers, one radio group per criterion. --%>
    <.quality_fields
      :if={show_field?(@only, :data_quality)}
      field={@form[:data_quality]}
      saved={"data_quality" in @saved}
    />
    <.omop_radios
      :if={show_field?(@only, :omop_integration)}
      field={@form[:omop_integration]}
      saved={"omop_integration" in @saved}
    />
    <fieldset :if={show_field?(@only, :years)} class="field-group">
      <legend>Years coverage</legend>
      <%!-- NOTE(Claude Opus 5.5 2026-11-18): Not applicable clears the years
           and the counts, and disables their inputs (see
           `DatasetVersion.not_applicable_fields/0`). --%>
      <.not_applicable_checkbox
        form={@form}
        name="years_coverage"
        saved={"not_applicable" in @saved}
      />
      <%!-- NOTE(Claude Opus 5.5 2026-11-17): years, no longer dates. A number
           input can be emptied by hand, so it needs no Clear button. --%>
      <.input
        field={@form[:coverage_start]}
        type="number"
        label="Start year"
        placeholder="2013"
        min={first_coverage_year()}
        max={last_coverage_year()}
        step="1"
        phx-debounce={@debounce}
        saved={"coverage_start" in @saved}
        disabled={not_applicable?(@form, "years_coverage")}
        value={unless(not_applicable?(@form, "years_coverage"), do: @form[:coverage_start].value)}
      />
      <.input
        field={@form[:coverage_end]}
        type="number"
        label="End year"
        placeholder="2025"
        min={first_coverage_year()}
        max={last_coverage_year()}
        step="1"
        phx-debounce={@debounce}
        saved={"coverage_end" in @saved}
        disabled={not_applicable?(@form, "years_coverage")}
        value={unless(not_applicable?(@form, "years_coverage"), do: @form[:coverage_end].value)}
      />
      <.csv_input
        form={@form}
        embed={:yearly_counts}
        label="Data points per year (CSV: year,count, or cells pasted from a spreadsheet)"
        placeholder="2013,1200\n2014,1350"
        debounce={@debounce}
        saved={"yearly_counts" in @saved}
        disabled={not_applicable?(@form, "years_coverage")}
      />
    </fieldset>
    <fieldset :if={show_field?(@only, :cohort_size)} class="field-group">
      <legend>Cohort coverage</legend>
      <.not_applicable_checkbox form={@form} name="cohort_size" saved={"not_applicable" in @saved} />
      <.input
        field={@form[:cohort_size]}
        type="number"
        label="Individuals covered"
        min="1"
        phx-debounce={@debounce}
        saved={"cohort_size" in @saved}
        disabled={not_applicable?(@form, "cohort_size")}
        value={unless(not_applicable?(@form, "cohort_size"), do: @form[:cohort_size].value)}
      />
    </fieldset>
    <.input
      :if={show_field?(@only, :lead)}
      field={@form[:lead]}
      type="text"
      label="Maintainer"
      phx-debounce={@debounce}
      saved={"lead" in @saved}
    />
    """
  end

  # NOTE(Claude Opus 5.5 2026-11-18): the checkbox of a field that may be Not
  # applicable (`name`, see `DatasetVersion.not_applicable_fields/0`). It sets
  # the field's own virtual boolean, so that a form showing one field only (a
  # quick edit) leaves the other as it is; checked from `not_applicable`.
  attr :form, Phoenix.HTML.Form, required: true
  attr :name, :string, required: true
  attr :saved, :boolean, default: false

  defp not_applicable_checkbox(assigns) do
    {_name, virtual} = List.keyfind(DatasetVersion.not_applicable_fields(), assigns.name, 0)
    assigns = assign(assigns, :virtual, virtual)

    ~H"""
    <.input
      field={@form[@virtual]}
      type="checkbox"
      label="Not applicable to this dataset"
      checked={not_applicable?(@form, @name)}
      saved={@saved}
    />
    """
  end

  # NOTE(Claude Opus 5.5 2026-11-18): from the changeset (the form sends the
  # virtual booleans, never `not_applicable` itself).
  defp not_applicable?(form, name), do: name in List.wrap(form[:not_applicable].value)

  defp first_coverage_year, do: DatasetVersion.coverage_years().first
  defp last_coverage_year, do: DatasetVersion.coverage_years().last
  defp first_release_date, do: elem(DatasetVersion.release_date_bounds(), 0)
  defp last_release_date, do: elem(DatasetVersion.release_date_bounds(), 1)

  # NOTE(Claude 2026-11-10): whether `version_fields/1` shows `field` (`:years`
  # is the coverage period and the yearly counts).
  defp show_field?(nil, _field), do: true
  defp show_field?(only, field), do: field in only

  @doc false
  attr :form, Phoenix.HTML.Form, required: true
  attr :field, :atom, required: true
  attr :legend, :string, required: true
  attr :add_label, :string, required: true
  attr :saved, :boolean, default: false
  slot :row, required: true

  # NOTE(Claude 2026-11-02): add/remove rows of an embeds_many field using
  # Ecto's sort_param/drop_param (see `DatasetVersion.changeset/2`).
  def embed_list(assigns) do
    ~H"""
    <fieldset class="embed-list field-group" id={"#{@form.id}_#{@field}"}>
      <legend>{@legend}</legend>
      <%!-- NOTE(Claude 2026-11-12): next to the first entry's inputs. --%>
      <.saved_tick :if={@saved} id={"#{@form.id}_#{@field}"} />
      <.inputs_for :let={row} field={@form[@field]}>
        <div class="embed-row">
          <input type="hidden" name={"#{@form.name}[#{@field}_sort][]"} value={row.index} />
          {render_slot(@row, row)}
          <button
            type="button"
            name={"#{@form.name}[#{@field}_drop][]"}
            value={row.index}
            phx-click={JS.dispatch("change")}
          >
            Remove
          </button>
        </div>
      </.inputs_for>
      <input type="hidden" name={"#{@form.name}[#{@field}_drop][]"} />
      <button
        type="button"
        name={"#{@form.name}[#{@field}_sort][]"}
        value="new"
        phx-click={JS.dispatch("change")}
      >
        {@add_label}
      </button>
    </fieldset>
    """
  end

  @doc false
  attr :form, Phoenix.HTML.Form, required: true
  attr :embed, :atom, required: true
  attr :label, :string, required: true
  attr :placeholder, :string, required: true
  attr :debounce, :string, required: true
  attr :saved, :boolean, default: false
  attr :disabled, :boolean, default: false

  # NOTE(Claude 2026-11-03): a list entered as CSV text, one entry per line, so
  # that it can be pasted in one go (e.g. 70 years of counts). Shows the text as
  # typed if there is any, otherwise the saved entries; the changeset parses it
  # (see `DatasetVersion.csv_embeds/0`).
  def csv_input(assigns) do
    csv_field = :"#{assigns.embed}_csv"
    field = assigns.form[csv_field]

    assigns =
      assigns
      |> assign(:field, field)
      |> assign(
        :value,
        # NOTE(Claude Opus 5.5 2026-11-18): empty when disabled (Not
        # applicable), not the text sent before.
        if(assigns.disabled,
          do: "",
          else:
            field.value ||
              DatasetVersion.embed_to_csv(assigns.embed, assigns.form[assigns.embed].value)
        )
      )

    ~H"""
    <.input
      field={@field}
      type="textarea"
      label={@label}
      value={@value}
      placeholder={@placeholder}
      rows="6"
      spellcheck="false"
      phx-debounce={@debounce}
      saved={@saved}
      disabled={@disabled}
    />
    """
  end

  # NOTE(Claude 2026-11-02): joined with a bare "," so that re-rendering gives
  # back exactly what was typed (the changeset trims the values).
  defp join_list(list) when is_list(list), do: Enum.join(list, ",")
  defp join_list(value), do: value

  defp access_type_options do
    Enum.map(DatasetVersion.access_types(), fn type ->
      {FGDataCatalogWeb.CatalogComponents.access_type_label(type), type}
    end)
  end

  @doc false
  attr :field, Phoenix.HTML.FormField, required: true
  attr :saved, :boolean, default: false

  # NOTE(Claude 2026-11-10): "OMOP-mapped" as radio buttons, one above the
  # other: Unknown (an empty value, which the changeset casts to nil), Yes, No
  # (and Not applicable since 2026-11-18, `DatasetVersion.omop_integrations/0`). The value is an atom
  # from the version, or a string from the params.
  def omop_radios(assigns) do
    errors =
      if used_input?(assigns.field),
        do: Enum.map(assigns.field.errors, &translate_error/1),
        else: []

    options = [
      {"Unknown", ""}
      | Enum.map(DatasetVersion.omop_integrations(), fn value ->
          {FGDataCatalogWeb.CatalogComponents.omop_label(value), Atom.to_string(value)}
        end)
    ]

    assigns =
      assign(assigns,
        errors: errors,
        options: options,
        current: to_string(assigns.field.value)
      )

    ~H"""
    <fieldset
      id={@field.id}
      class={["field", "radio-group", @errors != [] && "has-error"]}
      aria-describedby={@errors != [] && "#{@field.id}-errors"}
    >
      <legend class="field-label">OMOP-mapped</legend>
      <div class="radio-options">
        <label :for={{label, value} <- @options} class="checkbox-label">
          <%!-- NOTE(Claude 2026-11-12): next to the chosen value. --%>
          <.saved_tick :if={@saved and @current == value} id={@field.id} />
          <input
            type="radio"
            id={"#{@field.id}_#{if value == "", do: "unknown", else: value}"}
            name={@field.name}
            value={value}
            checked={@current == value}
          />{label}
        </label>
      </div>
      <div :if={@errors != []} id={"#{@field.id}-errors"} class="field-errors">
        <p :for={msg <- @errors} class="field-error">
          <.icon name="hero-exclamation-circle" />
          {msg}
        </p>
      </div>
    </fieldset>
    """
  end

  @doc false
  attr :field, Phoenix.HTML.FormField, required: true
  attr :saved, :boolean, default: false

  # NOTE(Claude 2026-11-16): the data quality section: one radio group per
  # current criterion (Yes, No, Unknown, and Not applicable since 2026-11-18),
  # its short label and the question for
  # the editor, under a legend with the score. Unknown sends an empty value,
  # which the changeset drops (see `DataQuality.cast/1`). The value is the
  # version's answers, or the raw params (with empty values) once typed.
  def quality_fields(assigns) do
    answers = DataQuality.cast(assigns.field.value)

    assigns =
      assign(assigns,
        answers: answers,
        score: DataQuality.score_text(answers),
        options: [{"Yes", "yes"}, {"No", "no"}, {"Unknown", ""}, {"Not applicable", "na"}]
      )

    ~H"""
    <fieldset id={@field.id} class="field-group quality-fields">
      <legend>
        Data quality <span id={"#{@field.id}-score"} class="quality-score">{@score}</span>
      </legend>
      <.saved_tick :if={@saved} id={@field.id} />
      <fieldset
        :for={criterion <- DataQuality.criteria()}
        id={"#{@field.id}_#{criterion.key}"}
        class="radio-group quality-question"
        aria-describedby={"#{@field.id}_#{criterion.key}-question"}
      >
        <legend class="field-label">{criterion.label}</legend>
        <p id={"#{@field.id}_#{criterion.key}-question"} class="quality-question-text">
          {criterion.question}
        </p>
        <div class="radio-options">
          <label :for={{label, value} <- @options} class="checkbox-label">
            <input
              type="radio"
              id={"#{@field.id}_#{criterion.key}_#{if value == "", do: "unknown", else: value}"}
              name={"#{@field.name}[#{criterion.key}]"}
              value={value}
              checked={Map.get(@answers, criterion.key, "") == value}
            />{label}
          </label>
        </div>
      </fieldset>
    </fieldset>
    """
  end

  # NOTE(Claude 2026-11-04): a comma-separated text input that suggests existing
  # values for the token being typed. The list is a client-side `<ul>` that
  # LiveView never patches (phx-update="ignore"); the `.TokenSuggest` hook
  # (defined once, in `version_fields/1`) fills it.
  # NOTE(Claude 2026-11-10): public, for the catalog's in-place quick edit,
  # which gives no visible label (`label` nil) but an `aria-label` (`rest`).
  @doc false
  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, default: nil
  attr :placeholder, :string, default: nil
  attr :suggestions, :list, default: []
  attr :debounce, :string, required: true
  attr :saved, :boolean, default: false
  attr :rest, :global

  def suggest_input(assigns) do
    ~H"""
    <div class="suggest">
      <.input
        field={@field}
        type="text"
        label={@label}
        placeholder={@placeholder}
        value={join_list(@field.value)}
        phx-debounce={@debounce}
        phx-hook=".TokenSuggest"
        data-suggestions={Jason.encode!(@suggestions)}
        data-list={"#{@field.id}-suggestions"}
        autocomplete="off"
        saved={@saved}
        {@rest}
      />
      <ul
        id={"#{@field.id}-suggestions"}
        class="suggestions"
        role="listbox"
        phx-update="ignore"
        hidden
      >
      </ul>
    </div>
    """
  end
end
