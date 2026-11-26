defmodule FGDataCatalogWeb.CatalogComponents do
  @moduledoc """
  Components for rendering the dataset catalog table.
  """
  use FGDataCatalogWeb, :html

  alias FGDataCatalog.Accounts.Scope
  alias FGDataCatalog.Catalog
  alias FGDataCatalog.Catalog.{DataQuality, DatasetVersion, Location}
  alias FGDataCatalogWeb.DatasetFormComponents

  @doc """
  Renders one table row for a dataset version.

  The current version row carries the dataset name and the "+N" toggle; previous
  version rows start `hidden` and are revealed by that toggle, client-side.
  """
  attr :dataset, :map, required: true
  attr :version, DatasetVersion, required: true
  attr :current, :boolean, required: true
  attr :previous_count, :integer, default: 0

  attr :scope, :any,
    default: nil,
    doc: "who views the row: editors see its state and the actions `Catalog.can?/3` allows"

  attr :year_domain, :any, default: nil, doc: "the sparklines' shared years, see `year_domain/1`"

  attr :words, :list,
    default: [],
    doc: "the search's words (see `FGDataCatalog.Catalog.Search.words/1`), highlighted"

  attr :list_params, :map,
    default: %{},
    doc: "the catalog's URL parameters (the search), kept by the dictionary link"

  attr :tag_links, :boolean,
    default: false,
    doc: "make the tags links that add (or remove) them to the tag filter of `list_params`"

  attr :quick_editable, :boolean,
    default: false,
    doc: "mark the quick editable values (`data-quick-edit`), in Editor mode, if writable"

  attr :quick_edit, :map,
    default: nil,
    doc: "the field being quick edited, `%{version_id: id, field: field, form: form}`, if any"

  def version_row(assigns) do
    # NOTE(Claude 2026-11-10): the versions of a dataset share their sparklines'
    # height scale, as all the rows share the time axis.
    assigns = assign(assigns, :y_max, counts_max(assigns.dataset))

    # NOTE(Claude 2026-11-16): what the viewer may do with the version (see
    # `Catalog.can?/3`), and the dataset as the version shows it (a Draft's
    # proposed name and description, see `Catalog.proposed_dataset/2`).
    %{scope: scope, version: version} = assigns
    can = Map.new(~w(write publish unpublish archive)a, &{&1, Catalog.can?(scope, &1, version)})

    assigns =
      assign(assigns,
        editor: Scope.editor?(scope),
        can: can,
        quick_editable: assigns.quick_editable and can.write,
        shown: Catalog.proposed_dataset(assigns.dataset, version)
      )

    ~H"""
    <tr
      id={"version-#{@version.id}"}
      class={if @current, do: "current-version", else: "previous-version"}
      hidden={!@current}
      data-version-id={@version.id}
    >
      <%!-- NOTE(Claude 2026-11-09): the row header holds the dataset's name,
           with, on the same line and right-aligned, the version's status and
           icon actions (for editors only) and, under it in small
           type, its description if it has one (screen readers repeat the
           header with each cell, so keep it short). Previous versions have the
           name visually hidden but keep their status and actions. --%>
      <th scope="row">
        <div class="dataset-heading">
          <%!-- NOTE(Claude 2026-11-10): `data-quick-edit` marks what an editor may
               quick edit, in Editor mode: hovered, it is outlined, and the E key
               opens its editor (the `.QuickEdit` hook of `DatasetLive.Index`); the editor replaces
               the value in place (`quick_inline/1`), or opens in a modal. Here the
               name and the description, edited together. --%>
          <%= cond do %>
            <% editing?(@quick_edit, @version, "dataset") -> %>
              <.quick_inline quick_edit={@quick_edit} field="dataset" />
            <% @current -> %>
              <span
                class="dataset-name"
                data-quick-edit={@quick_editable && "dataset"}
                tabindex={@quick_editable && "-1"}
              >
                {highlight(@shown.name, @words)}
              </span>
              <%!-- NOTE(Claude 2026-11-17): in Editor mode, a writable previous
                 version shows the name it gives the dataset (a Draft's proposed
                 one), muted, to quick edit it through that version. --%>
            <% @quick_editable -> %>
              <span class="dataset-name previous-name" data-quick-edit="dataset" tabindex="-1">
                {highlight(@shown.name, @words)}
              </span>
            <% true -> %>
              <span class="visually-hidden">{@shown.name}</span>
          <% end %>
          <%!-- NOTE(Claude Opus 5.5 2026-11-19): editors only: the version's state,
               Edit if they may write it (see `Catalog.can?/3`), and a "…" button
               that opens the other actions in a popover (`.CatalogTable` in
               `DatasetLive.Index` closes it and moves the focus after an action). --%>
          <div :if={@editor} class="row-actions">
            <%!-- NOTE(Claude 2026-11-06): the version's state leads its actions
                 (Publish and Unpublish act on it). In a slot of one width, as
                 Live and Draft differ. --%>
            <span class="status-slot">
              <.status_badge
                id={"status-#{@version.id}"}
                state={@version.state}
                owner={@version.owning_editor}
              />
            </span>
            <%!-- NOTE(Claude 2026-11-04): opens the version's edit form page. --%>
            <.link
              :if={@can.write}
              id={"edit-version-#{@version.id}"}
              class="edit-version icon-action"
              navigate={~p"/versions/#{@version.id}/edit"}
              title="Edit"
              aria-label={"Edit #{@shown.name} #{@version.version}"}
            >
              <.icon name="hero-pencil-square" />
            </.link>
            <%!-- NOTE(Claude Opus 5.5 2026-11-19): a native `popover="auto"`, in the
                 top layer, so that neither the table's scroll box nor its sticky
                 cells clip or cover it, and the column keeps its width. Anchored to
                 its button with CSS (a name of its own per row, see `app.css`),
                 or by `.CatalogTable` where anchor positioning is missing. Right
                 after its button, so that Tab goes from one into the other. --%>
            <button
              type="button"
              id={"actions-#{@version.id}"}
              class="row-actions-trigger icon-action"
              popovertarget={"actions-menu-#{@version.id}"}
              title={"More actions for #{@shown.name} #{@version.version}"}
              aria-label={"More actions for #{@shown.name} #{@version.version}"}
              style={"anchor-name: --actions-#{@version.id}"}
            >
              <.icon name="hero-ellipsis-horizontal" />
            </button>
            <%!-- NOTE(Claude Opus 5.5 2026-11-19): a plain list of links and
                 buttons, with text labels (not an ARIA menu). --%>
            <div
              popover="auto"
              id={"actions-menu-#{@version.id}"}
              class="table-popover row-actions-menu"
              data-table-popover
              data-trigger={"actions-#{@version.id}"}
              style={"position-anchor: --actions-#{@version.id}"}
            >
              <ul>
                <%!-- NOTE(Claude 2026-11-09): a new version of the dataset,
                     prefilled from this one. On the dataset's first row only. --%>
                <li :if={@current}>
                  <.link
                    id={"add-version-#{@dataset.id}"}
                    class="add-version menu-action"
                    navigate={~p"/datasets/#{@dataset.id}/versions/new"}
                  >
                    <.icon name="app-document-duplicate-plus" /> Add version
                  </.link>
                </li>
                <%!-- NOTE(Claude Opus 5.5 2026-11-19): the changes of everything this
                     row shows, on the changelog page: the version's and its
                     dataset's (name, description), not those of its other versions. --%>
                <li>
                  <.link
                    id={"history-version-#{@version.id}"}
                    class="version-history menu-action"
                    navigate={~p"/changelog?#{[version: @version.id]}"}
                  >
                    <.icon name="hero-clock" /> History
                  </.link>
                </li>
                <%!-- NOTE(Claude 2026-11-16): Publish (a Draft, for its owning
                     editor) makes it visible to everyone; Unpublish (a Published
                     version, for any editor) turns it back into a Draft owned by
                     the viewer. Buttons: they act, they do not navigate. --%>
                <li :if={@can.publish}>
                  <button
                    type="button"
                    id={"publish-version-#{@version.id}"}
                    class="publish-version menu-action"
                    phx-click="publish"
                    phx-value-id={@version.id}
                  >
                    <.icon name="app-forward-overlap" /> Publish
                  </button>
                </li>
                <li :if={@can.unpublish}>
                  <button
                    type="button"
                    id={"unpublish-version-#{@version.id}"}
                    class="unpublish-version menu-action"
                    phx-click="unpublish"
                    phx-value-id={@version.id}
                  >
                    <.icon name="hero-eye-slash" /> Unpublish
                  </button>
                </li>
                <li :if={@can.archive}>
                  <button
                    type="button"
                    id={"archive-version-#{@version.id}"}
                    class="archive-version menu-action"
                    phx-click="archive"
                    phx-value-id={@version.id}
                  >
                    <.icon name="hero-archive-box" /> Archive
                  </button>
                </li>
              </ul>
            </div>
          </div>
        </div>
        <span
          :if={@current && @shown.description && !editing?(@quick_edit, @version, "dataset")}
          class="dataset-description"
          data-quick-edit={@quick_editable && "dataset"}
          tabindex={@quick_editable && "-1"}
        >
          {highlight(@shown.description, @words)}
        </span>
      </th>
      <%!-- NOTE(Claude 2026-11-06): an empty field shows a shaded em dash
           (`no_value/1`), in every cell below. --%>
      <td data-quick-edit={@quick_editable && "tags"} tabindex={@quick_editable && "-1"}>
        <.quick_inline
          :if={editing?(@quick_edit, @version, "tags")}
          quick_edit={@quick_edit}
          field="tags"
        />
        <%!-- NOTE(Claude 2026-11-05): list fields are sorted on display too, for
             versions saved before they were sorted on save. --%>
        <ul :if={@version.tags != [] && !editing?(@quick_edit, @version, "tags")} class="tags">
          <%!-- NOTE(Claude 2026-11-10): `data-tag` lets the table's `.CatalogTable`
               hook highlight every chip of the same tag; `phx-no-format` keeps the
               chip's text free of the whitespace the formatter would add. --%>
          <%!-- NOTE(Claude 2026-11-12): a click on a tag filters the rows by it
               (another click on it removes it), but in Editor mode, where a
               click on the cell edits the tags. --%>
          <%!-- NOTE(Claude Opus 5.5 2026-11-17): the tags fill the two lines of the
               row's height (see `tag_lines/1`), in order; an empty, hidden
               `li.tags-break` ends the first line. --%>
          <%= for {line, index} <- Enum.with_index(tag_lines(@version.tags)) do %>
            <li :if={index > 0} class="tags-break" aria-hidden="true"></li>
            <li
              :for={tag <- line}
              data-tag={tag}
              class={[tag in Map.get(@list_params, "tags", []) && "is-tag-selected"]}
              phx-no-format
            ><%= if @tag_links && !@quick_editable do %><.link
                patch={tag_filter_path(@list_params, tag)}
                title={tag_link_title(@list_params, tag)}
              >{highlight(tag, @words)}</.link><% else %>{highlight(tag, @words)}<% end %></li>
          <% end %>
        </ul>
        <.no_value :if={@version.tags == [] && !editing?(@quick_edit, @version, "tags")} />
      </td>
      <%!-- NOTE(Claude 2026-11-09): the rows are two lines high (the dataset's
           description sits under its name), so pairs of short values share a
           column, one above the other, to keep the table narrow: environment
           and access type, version and release date, modality and format. --%>
      <td class="stacked">
        <.quick_inline
          :if={editing?(@quick_edit, @version, "environments")}
          quick_edit={@quick_edit}
          field="environments"
        />
        <span
          :if={!editing?(@quick_edit, @version, "environments")}
          class="stacked-value"
          data-quick-edit={@quick_editable && "environments"}
          tabindex={@quick_editable && "-1"}
        >
          <.text_or_dash text={join_values(@version.environments)} words={@words} />
        </span>
        <.quick_inline
          :if={editing?(@quick_edit, @version, "access_type")}
          quick_edit={@quick_edit}
          field="access_type"
        />
        <span
          :if={!editing?(@quick_edit, @version, "access_type")}
          class="stacked-value"
          data-quick-edit={@quick_editable && "access_type"}
          tabindex={@quick_editable && "-1"}
        >
          <.text_or_dash text={access_type_label(@version.access_type)} words={@words} />
        </span>
      </td>
      <td class="stacked">
        <.quick_inline
          :if={editing?(@quick_edit, @version, "version")}
          quick_edit={@quick_edit}
          field="version"
        />
        <div
          :if={!editing?(@quick_edit, @version, "version")}
          class="version stacked-value"
          data-quick-edit={@quick_editable && "version"}
          tabindex={@quick_editable && "-1"}
        >
          <span><.text_or_dash text={@version.version} words={@words} /></span>
          <button
            :if={@current and @previous_count > 0}
            type="button"
            class="versions-toggle"
            aria-expanded="false"
            aria-label={"Show #{@previous_count} previous versions"}
            phx-click={toggle_previous_versions(@dataset.id)}
          >
            +{@previous_count}
          </button>
        </div>
        <.quick_inline
          :if={editing?(@quick_edit, @version, "release_date")}
          quick_edit={@quick_edit}
          field="release_date"
        />
        <span
          :if={!editing?(@quick_edit, @version, "release_date")}
          class="stacked-value"
          data-quick-edit={@quick_editable && "release_date"}
          tabindex={@quick_editable && "-1"}
        >
          <time
            :if={@version.release_date}
            data-local-date
            datetime={Date.to_iso8601(@version.release_date)}
          >
            {@version.release_date}
          </time>
          <.no_value :if={!@version.release_date} />
        </span>
      </td>
      <td class="stacked">
        <.quick_inline
          :if={editing?(@quick_edit, @version, "modalities")}
          quick_edit={@quick_edit}
          field="modalities"
        />
        <span
          :if={!editing?(@quick_edit, @version, "modalities")}
          class="stacked-value"
          data-quick-edit={@quick_editable && "modalities"}
          tabindex={@quick_editable && "-1"}
        >
          <.text_or_dash text={join_values(@version.modalities)} words={@words} />
        </span>
        <.quick_inline
          :if={editing?(@quick_edit, @version, "formats")}
          quick_edit={@quick_edit}
          field="formats"
        />
        <span
          :if={!editing?(@quick_edit, @version, "formats")}
          class="stacked-value"
          data-quick-edit={@quick_editable && "formats"}
          tabindex={@quick_editable && "-1"}
        >
          <.text_or_dash text={join_values(@version.formats)} words={@words} />
        </span>
      </td>
      <td data-quick-edit={@quick_editable && "doc_links"} tabindex={@quick_editable && "-1"}>
        <.no_value :if={@version.doc_links == []} />
        <ul :if={@version.doc_links != []} class="doc-links">
          <li :for={link <- @version.doc_links}>
            <%!-- NOTE(Claude 2026-11-04): pasted text entries expand in place. --%>
            <details :if={link.kind == :text} class="doc-text">
              <summary>{highlight(link.label, @words)}</summary>
              <pre>{link.text}</pre>
            </details>
            <a :if={link.kind != :text} href={link.url} target="_blank" rel="noopener noreferrer">
              {highlight(link.label, @words)}
            </a>
          </li>
        </ul>
      </td>
      <%!-- NOTE(Claude Opus 5.5 2026-11-17): where to find the data, under its
           name if it has one (see `location/1`). --%>
      <td
        class="location"
        data-quick-edit={@quick_editable && "locations"}
        tabindex={@quick_editable && "-1"}
      >
        <.location
          id={"locations-#{@version.id}"}
          entries={@version.locations}
          words={@words}
        />
      </td>
      <td data-quick-edit={@quick_editable && "data_dictionary"} tabindex={@quick_editable && "-1"}>
        <.link
          :if={@version.data_dictionary != []}
          class="dictionary-link"
          patch={catalog_path(Map.put(@list_params, "dictionary", @version.id))}
        >
          {pluralize(length(@version.data_dictionary), "variable")}
        </.link>
        <.no_value :if={@version.data_dictionary == []} />
      </td>
      <%!-- NOTE(Claude 2026-11-16): the data quality score, a link that opens
           its modal (`?quality=ID`), for everyone. In Editor mode, plain text:
           the cell is quick edited, in a modal (the form's Data quality section). --%>
      <td
        class="data-quality"
        data-quick-edit={@quick_editable && "data_quality"}
        tabindex={@quick_editable && "-1"}
      >
        <.quality_score
          dataset={@dataset}
          version={@version}
          list_params={@list_params}
          link={!@quick_editable}
        />
      </td>
      <%!-- NOTE(Claude 2026-11-10): its quick edit cycles Unknown, Yes, No,
           saved at once (see `DatasetLive.Index`).
           NOTE(Claude Opus 5.5 2026-11-18): then Not applicable. --%>
      <td
        class="omop"
        data-quick-edit={@quick_editable && "omop_integration"}
        tabindex={@quick_editable && "-1"}
      >
        <.omop_mapped value={@version.omop_integration} />
      </td>
      <%!-- NOTE(Claude Opus 5.5 2026-11-19): Not applicable is a single line,
           not stacked: centered in the row's height like the OMOP-mapped
           n/a next to it, at the right end of the column. --%>
      <td
        :if={DatasetVersion.not_applicable?(@version, "years_coverage")}
        class="not-applicable-cell"
        data-quick-edit={@quick_editable && "years"}
        tabindex={@quick_editable && "-1"}
      >
        <.not_applicable />
      </td>
      <td
        :if={!DatasetVersion.not_applicable?(@version, "years_coverage")}
        class="stacked"
        data-quick-edit={@quick_editable && "years"}
        tabindex={@quick_editable && "-1"}
      >
        <%!-- NOTE(Claude Opus 5.5 2026-11-17): the years stacked above the
             sparkline (see `.year-coverage`), in a stacked cell, so that the
             years line up with the row's first line. A dash without coverage
             dates nor yearly counts, where the years would be (above an empty
             slot as large as a sparkline), so that it lines up with the years
             above and below; with counts only, the sparkline alone, under an
             empty line. --%>
        <div
          :if={
            is_nil(@version.coverage_start) and is_nil(@version.coverage_end) and
              @version.yearly_counts == []
          }
          class="year-coverage"
        >
          <span><.no_value title="Unknown" /></span>
          <div class="sparkline" aria-hidden="true"></div>
        </div>
        <div
          :if={@version.coverage_start || @version.coverage_end || @version.yearly_counts != []}
          class="year-coverage"
        >
          <span>{year_range(@version.coverage_start, @version.coverage_end)}</span>
          <.sparkline
            counts={@version.yearly_counts}
            coverage_start={@version.coverage_start}
            coverage_end={@version.coverage_end}
            domain={@year_domain}
            y_max={@y_max}
          />
        </div>
      </td>
      <td
        :if={DatasetVersion.not_applicable?(@version, "cohort_size")}
        class="not-applicable-cell"
        data-quick-edit={@quick_editable && "cohort_size"}
        tabindex={@quick_editable && "-1"}
      >
        <.not_applicable />
      </td>
      <td
        :if={!DatasetVersion.not_applicable?(@version, "cohort_size")}
        class="stacked"
        data-quick-edit={@quick_editable && "cohort_size"}
        tabindex={@quick_editable && "-1"}
      >
        <%!-- NOTE(Claude Opus 5.5 2026-11-17): like the years, the size stacked
             above the meter, and a dash without a cohort size, where the size
             would be (above an empty slot as wide as a meter), so that it lines
             up with the sizes above and below. --%>
        <%!-- NOTE(Claude Opus 5.5 2026-11-18): quick edited in a modal (with
             its Not applicable checkbox), no longer in place. --%>
        <div :if={is_nil(@version.cohort_size)} class="cohort-coverage">
          <span><.no_value title="Unknown" /></span>
          <div class="meter-slot" aria-hidden="true"></div>
        </div>
        <div :if={@version.cohort_size} class="cohort-coverage">
          <span>{format_integer(@version.cohort_size)}</span>
          <%!-- NOTE(Claude Opus 5.5 2026-11-17): the meter with, over it, a
               faint gridline at each tick of the heading's scale but its
               ends, as on the sparklines (see `cohort_gridlines/0`). --%>
          <div class="meter-plot">
            <meter
              min="0"
              max={DatasetVersion.finngen_total()}
              value={@version.cohort_size}
              title={"#{format_integer(@version.cohort_size)} of #{format_integer(DatasetVersion.finngen_total())} in FinnGen"}
              aria-label={"#{format_integer(@version.cohort_size)} of #{format_integer(DatasetVersion.finngen_total())} individuals in FinnGen"}
            />
            <svg
              class="meter-gridlines"
              viewBox="0 0 100 8"
              preserveAspectRatio="none"
              aria-hidden="true"
            >
              <line :for={x <- cohort_gridlines()} x1={x} y1="0" x2={x} y2="8" />
            </svg>
          </div>
        </div>
      </td>
      <%!-- NOTE(Claude Opus 5.5 2026-11-17): the maintainer, for signed-in users only. --%>
      <td
        :if={@editor}
        class="maintainer"
        data-quick-edit={@quick_editable && "lead"}
        tabindex={@quick_editable && "-1"}
      >
        <.quick_inline
          :if={editing?(@quick_edit, @version, "lead")}
          quick_edit={@quick_edit}
          field="lead"
        />
        <.text_or_dash
          :if={!editing?(@quick_edit, @version, "lead")}
          text={@version.lead}
          words={@words}
        />
      </td>
    </tr>
    """
  end

  # NOTE(Claude 2026-11-10): whether `field` of `version` is being quick edited.
  defp editing?(%{version_id: id, field: field}, %{id: id}, field), do: true
  defp editing?(_quick_edit, _version, _field), do: false

  @doc """
  The quick edit's fields edited in place (`quick_inline/1`). `"dataset"` is
  the dataset's name and description. Of the others, OMOP-mapped is cycled
  in place, the rest open in a modal.
  """
  # NOTE(Claude 2026-11-10): the list fields (tags, environments, modalities,
  # formats) too, as comma-separated inputs with suggestions.
  # NOTE(Claude Opus 5.5 2026-11-18): no longer `cohort_size`, now in a modal
  # with its Not applicable checkbox.
  def quick_inline_fields,
    do: ~w(dataset tags environments access_type version release_date modalities formats
         lead)

  @doc """
  Renders the in-place editor of a catalog cell's `field` (one of
  `quick_inline_fields/0`): its input, focused, with Save and Cancel buttons.
  Enter saves (a select saves on change); Escape or a click elsewhere cancels.
  """
  attr :quick_edit, :map, required: true, doc: "the quick edit, with its `form` and `suggestions`"
  attr :field, :string, required: true

  def quick_inline(assigns) do
    assigns =
      assign(assigns, form: assigns.quick_edit.form, suggestions: assigns.quick_edit.suggestions)

    ~H"""
    <%!-- NOTE(Claude 2026-11-10): a click elsewhere cancels it, as Escape does;
         handled by the table's `.CatalogTable` hook (not `phx-click-away`), so
         that a click on another cell opens that cell's editor instead. --%>
    <.form
      for={@form}
      id="quick-edit-form"
      class="quick-edit-inline"
      phx-change="quick_validate"
      phx-submit="quick_save"
      phx-window-keydown="quick_cancel"
      phx-key="Escape"
    >
      <.quick_input form={@form} field={@field} suggestions={@suggestions} />
      <span class="quick-edit-actions">
        <button
          type="submit"
          id="quick-edit-save"
          class="icon-action"
          title="Save (Enter)"
          aria-label="Save"
        >
          <.icon name="hero-check" />
        </button>
        <button
          type="button"
          id="quick-edit-cancel"
          class="icon-action"
          phx-click="quick_cancel"
          title="Cancel (Escape)"
          aria-label="Cancel"
        >
          <.icon name="hero-x-mark" />
        </button>
      </span>
    </.form>
    """
  end

  # NOTE(Claude 2026-11-10): the inputs of `quick_inline/1`, without visible
  # labels (the column heading says what they are), focused when they appear.
  attr :form, Phoenix.HTML.Form, required: true
  attr :field, :string, required: true
  attr :suggestions, :map, default: %{}

  defp quick_input(%{field: "dataset"} = assigns) do
    ~H"""
    <span class="quick-edit-fields">
      <.input
        field={@form[:name]}
        type="text"
        aria-label="Dataset"
        phx-mounted={JS.focus()}
        autocomplete="off"
      />
      <.input
        field={@form[:description]}
        type="text"
        aria-label="Description"
        placeholder="Description"
        maxlength={FGDataCatalog.Catalog.Dataset.description_max_length()}
        autocomplete="off"
      />
    </span>
    """
  end

  defp quick_input(%{field: "access_type"} = assigns) do
    ~H"""
    <.input
      field={@form[:access_type]}
      type="select"
      aria-label="Access type"
      prompt="Choose…"
      options={Enum.map(DatasetVersion.access_types(), &{access_type_label(&1), &1})}
      phx-mounted={JS.focus()}
    />
    """
  end

  # NOTE(Claude 2026-11-10): a list field, comma-separated, suggesting the
  # values in use, as on the edit page (`DatasetFormComponents.suggest_input/1`).
  defp quick_input(%{field: field} = assigns)
       when field in ~w(tags environments modalities formats) do
    {name, label} = quick_list_field(field)
    assigns = assign(assigns, name: name, label: label)

    ~H"""
    <DatasetFormComponents.suggest_input
      field={@form[@name]}
      suggestions={Map.get(@suggestions, @name, [])}
      debounce="300"
      aria-label={@label}
      phx-mounted={JS.focus()}
    />
    """
  end

  defp quick_input(assigns) do
    assigns =
      assign(assigns, quick_input_attrs(assigns.field))

    ~H"""
    <.input
      field={@form[@name]}
      type={@type}
      aria-label={@label}
      min={@min}
      max={@max}
      phx-mounted={JS.focus()}
      autocomplete="off"
    />
    """
  end

  defp quick_list_field("tags"), do: {:tags, "Tags (comma-separated)"}
  defp quick_list_field("environments"), do: {:environments, "Environments (comma-separated)"}
  defp quick_list_field("modalities"), do: {:modalities, "Modality (comma-separated)"}
  defp quick_list_field("formats"), do: {:formats, "Format (comma-separated)"}

  defp quick_input_attrs("version"),
    do: [name: :version, type: "text", label: "Version", min: nil, max: nil]

  defp quick_input_attrs("release_date") do
    {min, max} = DatasetVersion.release_date_bounds()
    [name: :release_date, type: "date", label: "Release date", min: min, max: max]
  end

  defp quick_input_attrs("lead"),
    do: [name: :lead, type: "text", label: "Maintainer", min: nil, max: nil]

  @doc """
  Renders a modal dialog that closes by patching to `close_to`.

  A native modal `<dialog>` gives focus handling, Escape and an inert page for
  free. The `.ModalDialog` hook opens it and turns any native close (Escape, a
  click on the backdrop) into a patch to `close_to`.

  NOTE(Claude 2026-11-06): the server renders the dialog already `open` (not
  modal), so that it shows without JavaScript too, its Close link then being a
  plain link. The hook reopens it as a modal.
  """
  attr :id, :string, required: true
  attr :title_id, :string, required: true
  attr :close_to, :string, required: true
  slot :title, required: true
  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <%!-- NOTE(Claude 2026-11-04): `open` is set by `showModal()`, so LiveView
         must not strip it on re-render. --%>
    <dialog
      id={@id}
      open
      class="modal"
      aria-labelledby={@title_id}
      phx-hook=".ModalDialog"
      phx-mounted={JS.ignore_attributes(["open"])}
      data-close={JS.patch(@close_to)}
    >
      <div class="modal-panel">
        <div class="modal-header">
          <h2 id={@title_id}>{render_slot(@title)}</h2>
          <.link patch={@close_to} class="modal-close" autofocus>Close</.link>
        </div>
        {render_slot(@inner_block)}
      </div>
    </dialog>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".ModalDialog">
      export default {
        mounted() {
          // NOTE(Claude 2026-11-04): remember what had focus (the link that
          // opened the dialog) so focus can go back there when the server removes it.
          this.opener = document.activeElement
          // NOTE(Claude 2026-11-04): a click on the dialog element itself (not its
          // panel) is a click on the backdrop. It must also start there, so that
          // selecting text and releasing outside does not close it.
          this.el.addEventListener("pointerdown", e => { this.downOnBackdrop = e.target === this.el })
          this.el.addEventListener("click", e => {
            if (e.target === this.el && this.downOnBackdrop) this.el.close()
          })
          // Escape and backdrop clicks close the dialog natively; sync the URL.
          // NOTE(Claude 2026-11-06): the "close" event is dispatched later, so
          // the one from reopening below arrives with the dialog open again:
          // only a dialog that is still closed was closed by the user.
          this.el.addEventListener("close", () => {
            if (!this.el.open) this.liveSocket.execJS(this.el, this.el.dataset.close)
          })
          // NOTE(Claude 2026-11-06): rendered open (non-modal) by the server;
          // showModal() throws on an open dialog, so close it first.
          if (this.el.open) this.el.close()
          this.el.showModal()
        },
        destroyed() {
          if (this.opener && this.opener.isConnected && this.opener !== document.body) {
            this.opener.focus()
          }
        }
      }
    </script>
    """
  end

  @doc """
  Renders a version's state: "Draft" (seen by editors only), "Live"
  (published, seen by everyone) or "Archived". A Draft's title names its
  owning editor, if `owner` is given.
  """
  # NOTE(Claude 2026-11-06): shown to editors only; the public catalog lists
  # Live versions only.
  # NOTE(Claude 2026-11-16): `state` replaces `status`; the class names stay
  # `status-*`.
  attr :id, :string, required: true
  attr :state, :atom, required: true
  attr :owner, :any, default: nil, doc: "the owning editor (a user), if loaded"

  def status_badge(assigns) do
    ~H"""
    <span id={@id} class={["status-badge", "status-#{@state}"]} title={state_title(@state, @owner)}>
      {status_label(@state)}
    </span>
    """
  end

  defp state_title(:draft, %FGDataCatalog.Accounts.User{email: email}),
    do: "Draft owned by #{email}"

  defp state_title(:draft, _owner), do: "Draft without an owning editor"
  defp state_title(_state, _owner), do: nil

  attr :id, :string, required: true
  attr :entries, :list, required: true
  attr :words, :list, default: []

  def location(%{entries: []} = assigns) do
    ~H"""
    <.no_value />
    """
  end

  def location(%{entries: [%{value: value} = entry]} = assigns) do
    if Location.location_kind(value) == :link do
      assigns = assign(assigns, :entry, entry)

      ~H"""
      <a
        class={[
          "location-value",
          hidden_location_match?(@entries, @entry.label || @entry.value, @words) && "search-match"
        ]}
        href={@entry.value}
        title={@entry.value}
        target="_blank"
        rel="noopener noreferrer"
      >
        {highlight(@entry.label || @entry.value, @words)}
      </a>
      """
    else
      location_popover(
        assign(assigns, text: entry.label || "View path", visible_label: entry.label)
      )
    end
  end

  def location(assigns) do
    location_popover(
      assign(assigns, text: "#{length(assigns.entries)} locations", visible_label: nil)
    )
  end

  defp location_popover(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      class={[
        "location-value location-trigger",
        hidden_location_match?(@entries, @visible_label, @words) && "search-match"
      ]}
      popovertarget={"#{@id}-popover"}
      aria-controls={"#{@id}-popover"}
      style={"anchor-name: --#{@id}"}
    >
      {if @visible_label, do: highlight(@text, @words), else: @text}
    </button>
    <div
      id={"#{@id}-popover"}
      popover="auto"
      class="table-popover location-popover"
      data-table-popover
      data-trigger={@id}
      style={"position-anchor: --#{@id}"}
    >
      <ul>
        <li :for={{entry, index} <- Enum.with_index(@entries)}>
          <span :if={entry.label} class="location-label">{highlight(entry.label, @words)}</span>
          <%= if Location.location_kind(entry.value) == :link do %>
            <a href={entry.value} target="_blank" rel="noopener noreferrer">
              {highlight(entry.value, @words)}
            </a>
          <% else %>
            <code id={"#{@id}-path-#{index}"} class="location-path">{highlight(entry.value, @words)}</code>
            <button
              id={"#{@id}-copy-#{index}"}
              type="button"
              class="btn btn-secondary"
              aria-label={if(entry.label, do: "Copy #{entry.label} path", else: "Copy path")}
              data-copy-location={"#{@id}-path-#{index}"}
              data-copy-status={"#{@id}-status-#{index}"}
            >
              Copy
            </button>
            <span id={"#{@id}-status-#{index}"} class="location-copy-status" role="status"></span>
          <% end %>
        </li>
      </ul>
    </div>
    """
  end

  defp hidden_location_match?(entries, visible_label, words) do
    Enum.any?(words, fn word ->
      !location_matches?(visible_label, word) &&
        Enum.any?(entries, fn entry ->
          location_matches?(entry.value, word) || location_matches?(entry.label, word)
        end)
    end)
  end

  defp location_matches?(nil, _word), do: false

  defp location_matches?(text, word),
    do: String.contains?(String.downcase(text), word)

  @doc """
  Renders a field without a value: a shaded em dash, read as "No value" by
  screen readers. With a `title` (e.g. "Unknown", where a field may also be
  Not applicable, see `not_applicable/1`), shown on hover and read instead.
  """
  # NOTE(Claude 2026-11-06): shaded (muted) so that it reads as an absence,
  # not as data.
  # NOTE(Claude Opus 5.5 2026-11-18): the title only where the field may be Not
  # applicable: elsewhere (tags, documentation…) an empty field is not Unknown.
  attr :title, :string, default: nil

  def no_value(assigns) do
    ~H"""
    <span class={["no-value", @title && "has-title"]} title={@title}><span aria-hidden="true">—</span><span class="visually-hidden">{@title ||
      "No value"}</span></span>
    """
  end

  @doc """
  Renders a field that does not apply to the version: a shaded "n/a", with the
  title "Not applicable", read as "Not applicable" by screen readers. Not to be
  confused with `no_value/1` (Unknown).
  """
  # NOTE(Claude Opus 5.5 2026-11-18): see `DatasetVersion.not_applicable_fields/0`,
  # `DataQuality` and the OMOP-mapped values.
  attr :id, :string, default: nil

  def not_applicable(assigns) do
    ~H"""
    <span id={@id} class="not-applicable" title="Not applicable"><span aria-hidden="true">n/a</span><span class="visually-hidden">Not applicable</span></span>
    """
  end

  @doc """
  Renders `text`, or `no_value/1` if it is `nil` or empty. The search `words`
  in it are highlighted (see `highlight/2`).
  """
  attr :text, :any, required: true
  attr :words, :list, default: []

  def text_or_dash(assigns) do
    ~H"""
    <%= if @text in [nil, ""] do %>
      <.no_value />
    <% else %>
      {highlight(@text, @words)}
    <% end %>
    """
  end

  @doc """
  `text`, HTML-escaped, with each occurrence of the search `words` (ignoring
  case) in a `<mark class="search-match">`. Without words, `text` as is.

      iex> highlight("Kanta lab values", ["lab", "kan"]) |> Phoenix.HTML.safe_to_string()
      ~s(<mark class="search-match">Kan</mark>ta <mark class="search-match">lab</mark> values)
  """
  # NOTE(Claude 2026-11-06): a match is found as the search finds it (a word
  # anywhere in the text, any case); longer words first, so that a word inside
  # another one does not cut its mark short.
  def highlight(text, []), do: text
  def highlight(nil, _words), do: nil

  def highlight(text, words) do
    pattern =
      words
      |> Enum.sort_by(&String.length/1, :desc)
      |> Enum.map_join("|", &Regex.escape/1)
      |> Regex.compile!("iu")

    parts =
      pattern
      |> Regex.split(to_string(text), include_captures: true, trim: true)
      |> Enum.map(fn part ->
        escaped = part |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
        # A part between matches holds none, so a part that matches is one.
        if Regex.match?(pattern, part),
          do: [~s(<mark class="search-match">), escaped, "</mark>"],
          else: escaped
      end)

    {:safe, parts}
  end

  def status_label(:draft), do: "Draft"
  def status_label(:published), do: "Live"
  def status_label(:archived), do: "Archived"

  @doc """
  The catalog's path with the given URL parameters: `/` without any.
  """
  # NOTE(Claude 2026-11-06): used to keep the search when the dictionary modal
  # opens or closes.
  def catalog_path(params) when params == %{}, do: ~p"/"
  def catalog_path(params), do: ~p"/?#{params}"

  @doc """
  The catalog's path with `tag` added to the tag filter of `params`, or
  removed from it if it is already there; the other parameters are kept.
  """
  # NOTE(Claude 2026-11-12): the tags are kept in the URL as `tags[]=…`, in
  # the order they were clicked.
  def tag_filter_path(params, tag) do
    tags = Map.get(params, "tags", [])
    tags = if tag in tags, do: List.delete(tags, tag), else: tags ++ [tag]
    params |> put_tag_filter(tags) |> catalog_path()
  end

  @doc "The catalog's path with `params` but no tag filter."
  def clear_tag_filter_path(params), do: params |> put_tag_filter([]) |> catalog_path()

  defp tag_link_title(params, tag) do
    if tag in Map.get(params, "tags", []),
      do: "Stop filtering by “#{tag}”",
      else: "Show only the datasets tagged “#{tag}”"
  end

  defp put_tag_filter(params, []), do: Map.delete(params, "tags")
  defp put_tag_filter(params, tags), do: Map.put(params, "tags", tags)

  # NOTE(Claude 2026-11-05): a list field, sorted, as one comma-separated cell.
  # NOTE(Claude Opus 5.5 2026-11-17): the sorted tags split in two lines of
  # about the same width (the first line the longer one on a tie), so that the tag
  # column is as narrow as two lines allow. A chip's width is taken as its
  # length plus 2 (its padding and the gap). A single tag stays on one line.
  @doc false
  def tag_lines(tags) do
    case DatasetVersion.sort_values(tags) do
      [] ->
        []

      [_] = tags ->
        [tags]

      tags ->
        widths = Enum.map(tags, &(String.length(&1) + 2))
        total = Enum.sum(widths)

        # NOTE(Claude Opus 5.5 2026-11-17): the first line's width after each
        # tag; the split leaves the widest line as narrow as possible, and at
        # least one tag on each line.
        {_, count} =
          widths
          |> Enum.scan(&+/2)
          |> Enum.with_index(1)
          |> Enum.take(length(tags) - 1)
          |> Enum.min_by(fn {first, _count} -> {max(first, total - first), -first} end)

        tags |> Enum.split(count) |> Tuple.to_list()
    end
  end

  defp join_values(values), do: values |> DatasetVersion.sort_values() |> Enum.join(", ")

  defp toggle_previous_versions(dataset_id) do
    JS.toggle_attribute({"aria-expanded", "true", "false"})
    |> JS.toggle_attribute({"hidden", "hidden"}, to: "#dataset-#{dataset_id} .previous-version")
  end

  @doc """
  Renders a version's data quality score (e.g. `3/7`, or `?/7` while some
  criteria are Unknown, `n/a` if none applies) as a badge styled by its level (`DataQuality.level/2`),
  a link that opens its modal (`?quality=ID`, see
  `quality_criteria/1`), keeping the catalog's other URL parameters. Without
  `link` (Editor mode, where a click on the cell opens its quick edit), plain
  text, with the same accessible text.
  """
  attr :dataset, :map, required: true
  attr :version, DatasetVersion, required: true
  attr :list_params, :map, default: %{}
  attr :link, :boolean, default: true

  def quality_score(%{link: false} = assigns) do
    assigns = assign_quality_score(assigns)

    ~H"""
    <span
      id={"quality-score-#{@version.id}"}
      class={["quality-link", "quality-badge", "is-#{@level}"]}
      data-level={@level}
      title={@level == :na && "Not applicable"}
    >
      <span aria-hidden="true">{@score}</span>
      <span class="visually-hidden">Data quality: {@description}</span>
    </span>
    """
  end

  def quality_score(assigns) do
    assigns = assign_quality_score(assigns)

    ~H"""
    <.link
      id={"quality-link-#{@version.id}"}
      class={["quality-link", "quality-badge", "is-#{@level}"]}
      data-level={@level}
      title={@level == :na && "Not applicable"}
      patch={catalog_path(Map.put(@list_params, "quality", @version.id))}
      aria-label={"Data quality of #{@dataset.name} #{@version.version}: #{@description}"}
    >
      {@score}
    </.link>
    """
  end

  defp assign_quality_score(assigns) do
    answers = assigns.version.data_quality

    assign(assigns,
      score: DataQuality.score_text(answers),
      description: DataQuality.score_description(answers),
      level: DataQuality.level(answers)
    )
  end

  @doc """
  Lists the current data quality criteria, in order, each with its short label,
  the version's answer (Yes, No, Not applicable or Unknown), and under it what
  the user has to do if the answer is no (but for a criterion Not applicable).
  """
  attr :answers, :map, required: true, doc: "the version's `data_quality`"

  # NOTE(Claude 2026-11-16): the answers are words, Yes in bold (not told apart
  # by colour); the "If no" text is always shown (no more help button).
  def quality_criteria(assigns) do
    ~H"""
    <ul id="quality-criteria" class="quality-criteria">
      <li
        :for={criterion <- DataQuality.criteria()}
        id={"quality-criterion-#{criterion.key}"}
        class="quality-criterion"
      >
        <div class="quality-criterion-line">
          <span class="quality-criterion-label">{criterion.label}</span>
          <.quality_answer
            id={"quality-answer-#{criterion.key}"}
            answer={DataQuality.answer(@answers, criterion.key)}
          />
        </div>
        <p
          :if={DataQuality.answer(@answers, criterion.key) != :na}
          id={"quality-if-no-#{criterion.key}"}
          class="quality-help-text"
        >
          {DataQuality.if_no_text(criterion)}
        </p>
      </li>
    </ul>
    """
  end

  attr :id, :string, required: true
  attr :answer, :atom, values: [:yes, :no, :na, :unknown], required: true

  defp quality_answer(assigns) do
    ~H"""
    <span id={@id} class={["quality-answer", "is-#{@answer}"]} data-answer={@answer}>
      {DataQuality.answer_label(@answer)}
    </span>
    """
  end

  @doc """
  The years spanned by the coverage periods and yearly counts of all the
  `datasets`' versions, as `{first, last}` (both included), or `nil` if none
  has any. Every sparkline of a table shares it, so their years line up.
  """
  # NOTE(Claude 2026-11-06): computed from the rows shown, so that it follows
  # the search.
  def year_domain(datasets) do
    years =
      for dataset <- datasets,
          version <- dataset.versions,
          year <-
            [version.coverage_start, version.coverage_end]
            |> Enum.reject(&is_nil/1)
            |> Kernel.++(Enum.map(version.yearly_counts, & &1.year)),
          do: year

    case years do
      [] -> nil
      years -> Enum.min_max(years)
    end
  end

  @doc """
  Renders a version's years on the shared time axis `domain` (see
  `year_domain/1`): a faint background over the whole axis, a light band for
  its coverage period and, above it, its count per year as steps, each year as
  wide as the axis gives it. Heights are relative to `y_max`, by default the
  version's busiest year. Behind the counts, a faint vertical gridline at
  every tick of `year_axis/1`, the year 2000's a little bolder. Over it
  all, a transparent band per `decade_chunks/2` chunk of the version's years,
  shaded on hover, whose `data-tip-years` and `data-tip-points` (shown above
  the sparkline by the catalog's `.SparkTip` hook) give its years and its
  total of data points. Inherits its color from `currentColor`.
  Renders nothing if the version has no years to show.
  """
  attr :counts, :list, required: true
  # NOTE(Claude Opus 5.5 2026-11-17): years, no longer dates.
  attr :coverage_start, :integer, default: nil, doc: "the coverage's start year"
  attr :coverage_end, :integer, default: nil, doc: "the coverage's end year, included"
  attr :domain, :any, required: true, doc: "`{first_year, last_year}`, or `nil`"

  attr :y_max, :integer,
    default: nil,
    doc:
      "the count drawn full height (the dataset's busiest year), or `nil` for the version's own"

  def sparkline(assigns) do
    assigns =
      assigns
      |> assign(:points, sparkline_points(assigns.counts, assigns.domain, assigns.y_max))
      |> assign(
        :chunks,
        chunk_bands(assigns.counts, assigns.coverage_start, assigns.coverage_end, assigns.domain)
      )
      |> assign(
        :band,
        coverage_band(assigns.coverage_start, assigns.coverage_end, assigns.domain)
      )

    assigns = assign(assigns, :gridlines, year_gridlines(assigns.domain))

    ~H"""
    <svg
      :if={@points || @band}
      class="sparkline"
      viewBox="0 0 100 20"
      preserveAspectRatio="none"
      role="img"
      aria-label={sparkline_label(@counts, @coverage_start, @coverage_end, @chunks)}
    >
      <%!-- NOTE(Claude Opus 5.5 2026-11-17): the whole shared axis, from the
           catalog's first year to its last, so that every plot is laid out
           on the same shaded span. --%>
      <rect class="axis-band" x="0" width="100" y="0" height="20" />
      <rect
        :if={@band}
        class="coverage-band"
        x={elem(@band, 0)}
        width={elem(@band, 1)}
        y="0"
        height="20"
        fill="currentColor"
      />
      <%!-- NOTE(Claude 2026-11-09): over the coverage band but under the
           counts, so that the time axis reads on the plot itself. --%>
      <line
        :for={{x, millennium?} <- @gridlines}
        class={["gridline", millennium? && "gridline-2000"]}
        x1={x}
        y1="0"
        x2={x}
        y2="20"
      />
      <polygon :if={@points} class="counts" points={@points} fill="currentColor" />
      <%!-- NOTE(Claude 2026-11-10): on top, to catch the pointer anywhere in
           the chunk; transparent until hovered (see `.sparkline .chunk`). --%>
      <rect
        :for={{x, width, years, points} <- @chunks}
        class="chunk"
        x={x}
        width={width}
        y="0"
        height="20"
        fill="currentColor"
        data-tip-years={years}
        data-tip-points={points}
      />
    </svg>
    """
  end

  @doc """
  Renders the shared time axis of the sparklines: a sparkline-wide scale with
  a tick rising from it at the start of every `year_ticks/1` year, its ends
  included, and the `year_labels/1` above.
  """
  attr :domain, :any, required: true

  def year_axis(assigns) do
    assigns =
      assigns
      |> assign(:ticks, if(assigns.domain, do: year_tick_xs(assigns.domain), else: []))
      |> assign(:labels, if(assigns.domain, do: year_labels(assigns.domain), else: []))

    ~H"""
    <span :if={@domain} class="year-axis" aria-hidden="true">
      <%!-- NOTE(Claude 2026-11-06): each label is centered on its place on the
           axis (a percentage of the scale's width). --%>
      <span class="year-labels">
        <%!-- NOTE(Claude 2026-11-06): an apostrophe (’, U+2019) before the
             two digits marks them as a year; it hangs left of them, so that
             the digits are what is centered on the tick. --%>
        <span
          :for={{x, label} <- @labels}
          class={label == "00" && "year-2000"}
          style={"left: #{x}%"}
        ><span class="year-apostrophe">’</span>{label}</span>
      </span>
      <%!-- NOTE(Claude 2026-11-06): the scale and its ticks, drawn on the same
           0 to 100 axis as the sparklines below; one-pixel strokes whatever
           the stretch. --%>
      <svg class="year-ticks" viewBox="0 0 100 4" preserveAspectRatio="none">
        <line x1="0" y1="3.5" x2="100" y2="3.5" />
        <line :for={x <- @ticks} class="year-tick" x1={x} y1="0" x2={x} y2="4" />
      </svg>
    </span>
    """
  end

  @doc """
  Renders the scale of the cohort meters, from 0 to `max` (the FinnGen total
  by default), drawn like `year_axis/1`: a meter-wide scale with a tick
  rising from it at every `cohort_ticks/1` count and the `cohort_labels/1`
  above.
  """
  attr :max, :integer, default: DatasetVersion.finngen_total()

  def cohort_axis(assigns) do
    assigns =
      assigns
      |> assign(:ticks, Enum.map(cohort_ticks(assigns.max), &round_x(&1 / assigns.max * 100)))
      |> assign(:labels, cohort_labels(assigns.max))

    ~H"""
    <span class="cohort-axis" aria-hidden="true">
      <span class="axis-labels">
        <span :for={{x, label} <- @labels} style={"left: #{x}%"}>{label}</span>
      </span>
      <svg class="axis-ticks" viewBox="0 0 100 4" preserveAspectRatio="none">
        <line x1="0" y1="3.5" x2="100" y2="3.5" />
        <line :for={x <- @ticks} x1={x} y1="0" x2={x} y2="4" />
      </svg>
    </span>
    """
  end

  @doc """
  The counts at which the cohort scale from 0 to `max` gets a tick: every
  multiple of 100,000.

      iex> cohort_ticks(520_210)
      [0, 100_000, 200_000, 300_000, 400_000, 500_000]
  """
  # NOTE(Claude Opus 5.5 2026-11-17): a tick per 100,000 (about 15px apart on
  # the 4.8rem meters), but none at the scale's end, which would be a couple of
  # pixels from the 500,000 one; the scale's line ends there anyway.
  @cohort_step 100_000
  @cohort_label_step 500_000

  def cohort_ticks(max), do: Enum.to_list(0..max//@cohort_step)

  @doc """
  The x of the cohort meters' gridlines, on their 0 to 100 axis up to the
  FinnGen total: the `cohort_ticks/1` but 0, the meter's edge.

      iex> cohort_gridlines()
      [19.22, 38.45, 57.67, 76.89, 96.12]
  """
  # NOTE(Claude Opus 5.5 2026-11-17): the scale's ticks carried onto the
  # meters, as `year_gridlines/1` carries the year scale's onto the sparklines.
  def cohort_gridlines(max \\ DatasetVersion.finngen_total()) do
    for count <- cohort_ticks(max), count > 0, do: round_x(count / max * 100)
  end

  @doc """
  The labels of the cohort scale from 0 to `max`, as `{x, label}` on the
  scale's 0 to 100 axis: every multiple of 500,000, in thousands.

      iex> cohort_labels(520_210)
      [{0.0, "0"}, {96.12, "500k"}]
  """
  # NOTE(Claude Opus 5.5 2026-11-17): on the 4.8rem meters only 0 and 500k have room for
  # a label; "100k" is wider than the gap between two ticks.
  def cohort_labels(max) do
    for count <- 0..max//@cohort_label_step do
      {round_x(count / max * 100), if(count == 0, do: "0", else: "#{div(count, 1000)}k")}
    end
  end

  @doc """
  The years at which the time axis `{first, last}` gets a tick: every multiple
  of a round step (see `year_step/1`), plus the axis' two ends (the start of
  `first` and the end of `last`).

      iex> year_ticks({1998, 2023})
      [1998, 2000, 2005, 2010, 2015, 2020, 2024]
  """
  def year_ticks({first, last} = domain) do
    step = year_step(domain)
    multiples = for year <- first..(last + 1), rem(year, step) == 0, do: year
    Enum.uniq([first | multiples] ++ [last + 1])
  end

  @doc """
  The labels of the time axis `{first, last}`, as `{x, label}`: the last two
  digits of each year (shown after an apostrophe, see `year_axis/1`), on the axis' 0 to 100 scale. With a step of one year,
  every year, in the middle of its span; otherwise the round ticks within the
  axis (not its ends, which are seldom round).

      iex> year_labels({1998, 2023})
      [{7.69, "00"}, {26.92, "05"}, {46.15, "10"}, {65.38, "15"}, {84.62, "20"}]

      iex> year_labels({2019, 2020})
      [{25.0, "19"}, {75.0, "20"}]
  """
  # NOTE(Claude 2026-11-06): two digits keep the labels short enough to sit
  # on their ticks without crowding; the full years are in each row's cell.
  def year_labels({first, last} = domain) do
    case year_step(domain) do
      1 ->
        for year <- first..last, do: {round_x(year_x(year + 0.5, domain)), two_digits(year)}

      step ->
        for year <- first..last,
            rem(year, step) == 0,
            do: {round_x(year_x(year, domain)), two_digits(year)}
    end
  end

  # NOTE(Claude 2026-11-06): a round step (1, 2, 5, 10, 20, 25, 50 or 100
  # years) giving at most eight steps on the axis.
  defp year_step({first, last}) do
    span = last + 1 - first
    Enum.find([1, 2, 5, 10, 20, 25, 50, 100], 100, &(div(span, &1) <= 8))
  end

  defp two_digits(year), do: year |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")

  defp round_x(x), do: Float.round(x / 1, 2)

  defp year_tick_xs(domain) do
    domain |> year_ticks() |> Enum.map(&round_x(year_x(&1, domain)))
  end

  # NOTE(Claude Opus 5.5 2026-11-17): the sparklines' gridlines as
  # `{x, year == 2000}`: the axis' ticks but its two ends, which are the
  # plot's edges, across the whole axis (no longer only within the coverage
  # band), as the shaded background behind them spans it.
  defp year_gridlines(nil), do: []

  defp year_gridlines({first, last} = domain) do
    for year <- year_ticks(domain), year not in [first, last + 1] do
      {round_x(year_x(year, domain)), year == 2000}
    end
  end

  # NOTE(Claude 2026-11-06): x is the position of a moment on the shared axis
  # (0 to 100), year `first` starting at 0 and year `last` ending at 100.
  defp year_x(year, {first, last}), do: (year - first) / (last + 1 - first) * 100

  @doc """
  Splits the years `first` to `last` (both included) into chunks of one decade
  at most, as `{from, to}`: each starts at a round year (a multiple of ten),
  but the first, which starts at `first`; the last ends at `last`.

      iex> decade_chunks(1995, 2023)
      [{1995, 1999}, {2000, 2009}, {2010, 2019}, {2020, 2023}]

      iex> decade_chunks(2020, 2020)
      [{2020, 2020}]
  """
  def decade_chunks(first, last) when first <= last do
    Enum.map(Enum.chunk_by(first..last, &div(&1, 10)), &{hd(&1), List.last(&1)})
  end

  # NOTE(Claude 2026-11-10): the busiest year's count of `dataset`'s versions
  # (or of a list of yearly counts), the full height of their sparklines; nil
  # without any count.
  defp counts_max(%{versions: versions}) when is_list(versions) do
    versions |> Enum.flat_map(& &1.yearly_counts) |> counts_max()
  end

  defp counts_max(%{}), do: nil
  defp counts_max([]), do: nil
  defp counts_max(counts), do: counts |> Enum.map(&(&1.count || 0)) |> Enum.max()

  # NOTE(Claude 2026-11-10): the `decade_chunks/2` of the version's years (its
  # coverage period and counted years; an open end of the period runs to the
  # axis' end, as the coverage band does), as `{x, width, years, points}` on the axis
  # `domain`, the tip giving the chunk's years and its total of data points.
  # None without counts: there would be nothing to tell.
  defp chunk_bands(_counts, _from, _to, nil), do: []
  defp chunk_bands([], _from, _to, _domain), do: []

  defp chunk_bands(counts, from, to, {domain_first, domain_last} = domain) do
    count_years = Enum.map(counts, & &1.year)

    coverage_years =
      if from || to,
        do: [from || domain_first, to || domain_last],
        else: []

    {first, last} = Enum.min_max(count_years ++ coverage_years)

    for {from, to} <- decade_chunks(first, last) do
      total = for(%{year: year, count: count} <- counts, year in from..to, do: count || 0)
      x = year_x(from, domain)
      width = year_x(to + 1, domain) - x
      {round_x(x), round_x(width), chunk_years(from, to), data_points(Enum.sum(total))}
    end
  end

  # NOTE(Claude 2026-11-12): the tooltip's two lines: the years, then the
  # total (see `.SparkTip`).
  defp chunk_years(year, year), do: "#{year}"
  defp chunk_years(from, to), do: "#{from}–#{to}"

  # NOTE(Claude Sonnet 5.5 2026-11-17): "data points: N", the label first.
  defp data_points(n), do: "data points: #{format_integer(n)}"

  # NOTE(Claude 2026-11-06): one step per year, from its start to its end;
  # missing years drop to zero, so gaps stay visible.
  defp sparkline_points(_counts, nil, _y_max), do: nil
  defp sparkline_points([], _domain, _y_max), do: nil

  defp sparkline_points(counts, domain, y_max) do
    counts = Enum.sort_by(counts, & &1.year)
    max_count = (y_max || counts_max(counts)) |> max(1)

    steps =
      counts
      |> Enum.chunk_every(2, 1)
      |> Enum.flat_map(fn
        [%{year: year, count: count} | next] ->
          y = 20 - (count || 0) / max_count * 20
          step = [{year_x(year, domain), y}, {year_x(year + 1, domain), y}]

          case next do
            [%{year: next_year}] when next_year > year + 1 ->
              step ++ [{year_x(year + 1, domain), 20}, {year_x(next_year, domain), 20}]

            _ ->
              step
          end
      end)

    first = year_x(hd(counts).year, domain)
    last = year_x(List.last(counts).year + 1, domain)

    [{first, 20} | steps]
    |> Kernel.++([{last, 20}])
    |> Enum.map_join(" ", fn {x, y} -> "#{Float.round(x / 1, 2)},#{Float.round(y / 1, 2)}" end)
  end

  # NOTE(Claude Opus 5.5 2026-11-17): the coverage period as `{x, width}`,
  # from the start of its start year to the end of its end year. An open end
  # runs to the edge of the axis.
  defp coverage_band(nil, nil, _domain), do: nil
  defp coverage_band(_from, _to, nil), do: nil

  defp coverage_band(from, to, {first, last} = domain) do
    x = if from, do: year_x(from, domain), else: 0.0
    x_end = year_x((to || last) + 1, domain)
    x = max(x, year_x(first, domain))
    {Float.round(x / 1, 2), Float.round(max(x_end - x, 0) / 1, 2)}
  end

  # NOTE(Claude 2026-11-10): with the decade totals of the tooltips, for screen
  # readers.
  defp sparkline_label(counts, from, to, chunks) do
    coverage = if from || to, do: "Coverage #{from || "?"} to #{to || "?"}"

    data =
      case Enum.sort_by(counts, & &1.year) do
        [] -> nil
        sorted -> "data points per year from #{hd(sorted).year} to #{List.last(sorted).year}"
      end

    tips = for {_x, _width, years, points} <- chunks, do: "#{years}: #{points}"
    [coverage, data | tips] |> Enum.reject(&is_nil/1) |> Enum.join("; ")
  end

  def access_type_label(:red), do: "Red account"
  def access_type_label(:green), do: "Green account"
  def access_type_label(:public), do: "Public"
  def access_type_label(nil), do: nil

  # NOTE(Claude 2026-11-10): the "OMOP-mapped" values; nil is unknown.
  def omop_label(:yes), do: "Yes"
  def omop_label(:no), do: "No"
  def omop_label(:not_applicable), do: "Not applicable"
  def omop_label(nil), do: nil

  @doc """
  Whether a version is OMOP-mapped, as an icon: a tick in a circle (yes), a
  bare cross (no), `not_applicable/1`, or the usual dash when unknown.
  """
  attr :value, :atom, required: true

  # NOTE(Claude 2026-11-10): the icon is hidden from screen readers (see
  # `icon/1`); the visually hidden text says the value, the title shows it on
  # hover. Only the tick has a circle (with both in circles they looked alike);
  # it reaches out of the circle through a gap (`priv/icons/check-circle-out.svg`).
  def omop_mapped(%{value: nil} = assigns), do: ~H|<.no_value title="Unknown" />|
  def omop_mapped(%{value: :not_applicable} = assigns), do: ~H"<.not_applicable />"

  def omop_mapped(assigns) do
    ~H"""
    <span class={["omop-mapped", "is-#{@value}"]} title={"OMOP-mapped: #{omop_label(@value)}"}>
      <.icon name={if @value == :yes, do: "app-check-circle-out", else: "hero-x-mark"} />
      <span class="visually-hidden">{omop_label(@value)}</span>
    </span>
    """
  end

  def pluralize(1, word), do: "1 #{word}"
  def pluralize(n, word), do: "#{n} #{word}s"

  def year_range(nil, nil), do: nil
  def year_range(from, to), do: "#{from}–#{to}"

  @doc """
  Formats an integer with thousands separators.

      iex> format_integer(520000)
      "520,000"
  """
  def format_integer(nil), do: nil

  def format_integer(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end
end
