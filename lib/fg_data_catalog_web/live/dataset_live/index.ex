defmodule FGDataCatalogWeb.DatasetLive.Index do
  use FGDataCatalogWeb, :live_view

  import FGDataCatalogWeb.CatalogComponents

  alias FGDataCatalog.Accounts.Scope
  alias FGDataCatalog.Catalog
  alias FGDataCatalog.Catalog.{DataQuality, DatasetVersion}
  alias FGDataCatalog.Catalog.Search
  alias FGDataCatalog.Changelog
  alias FGDataCatalogWeb.DatasetFormComponents
  alias FGDataCatalogWeb.DatasetLive.VersionParams

  # NOTE(Claude 2026-11-10): the fields of the quick edit that open in a modal,
  # with the fields `DatasetFormComponents.version_fields/1` shows and their
  # label; the others are edited in place (see `quick_inline_fields/0`), but
  # OMOP-mapped, cycled.
  @quick_modal_fields %{
    "doc_links" => {[:doc_links], "Documentation"},
    "locations" => {[:locations], "Locations"},
    "data_dictionary" => {[:data_dictionary], "Data dictionary"},
    "years" => {[:years], "Years coverage"},
    # NOTE(Claude 2026-11-16): the answers to the data quality criteria.
    "data_quality" => {[:data_quality], "Data quality"},
    # NOTE(Claude Opus 5.5 2026-11-18): in a modal since it has a Not
    # applicable checkbox; was edited in place.
    "cohort_size" => {[:cohort_size], "Cohort coverage"}
  }

  @quick_fields quick_inline_fields() ++ Map.keys(@quick_modal_fields)

  # NOTE(Claude 2026-11-10): the quick edit of OMOP-mapped steps through its
  # values, Unknown (nil) first.
  # NOTE(Claude Opus 5.5 2026-11-18): Unknown, Yes, No, Not applicable.
  @omop_cycle [nil | DatasetVersion.omop_integrations()]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <:header>
        <span :if={@last_updated} id="last-updated" class="last-updated">
          Last updated
          <time data-local-date datetime={Date.to_iso8601(@last_updated)}>{@last_updated}</time>
        </span>
        <%!-- NOTE(Claude 2026-11-16): the archive and the changelog are for
             editors (signed-in users). --%>
        <.link :if={@can_edit} id="archive-link" navigate={~p"/archive"}>Archive</.link>
        <.link :if={@can_edit} id="changelog-link" navigate={~p"/changelog"}>Changelog</.link>
      </:header>

      <%!-- NOTE(Claude 2026-11-06): free-text search, kept in the URL (`?q=`).
           A plain GET form, so it also works without JavaScript. No debounce:
           each keystroke searches at once (about 1 ms on the server). --%>
      <.form
        for={@search_form}
        id="search-form"
        class="search-form"
        action={~p"/"}
        method="get"
        phx-change="search"
        phx-submit="search"
        role="search"
      >
        <.input
          field={@search_form[:q]}
          type="search"
          label="Search datasets"
          placeholder={
            if(@can_edit,
              do: "Name, tag, modality, format, maintainer…",
              else: "Name, tag, modality, format…"
            )
          }
          autocomplete="off"
        />
        <%!-- NOTE(Claude 2026-11-12): the tag filter, kept by a search sent
             without JavaScript. --%>
        <input :for={tag <- @tags} type="hidden" name="tags[]" value={tag} />
        <noscript><button type="submit">Search</button></noscript>
      </.form>

      <%!-- NOTE(Claude 2026-11-10): the line above the table and the table, in
           one box as wide as the table, so that the line ends at its right
           border. --%>
      <div class="table-frame">
        <%!-- NOTE(Claude 2026-11-10): the search count and, on the same line, the
           quick edit's hint, so that the table loses no height. --%>
        <div class="table-meta">
          <p id="search-count" class="search-count" role="status">
            {search_count(@query, @tags, length(@datasets), length(@all_datasets))}
          </p>
          <%!-- NOTE(Claude 2026-11-12): the tags the rows are filtered by (a click
             on a tag in the table adds it); each one removed by a click, all of
             them by Clear. --%>
          <div :if={@tags != []} id="tag-filter" class="tag-filter">
            <span class="tag-filter-label">Tagged</span>
            <ul class="tags">
              <li :for={tag <- @tags} class="is-tag-selected">
                <.link
                  patch={tag_filter_path(@list_params, tag)}
                  title={"Stop filtering by “#{tag}”"}
                  data-tag-filter={tag}
                >
                  {tag} <.icon name="hero-x-mark" class="tag-filter-remove" />
                </.link>
              </li>
            </ul>
            <.link
              id="clear-tag-filter"
              class="clear-tag-filter"
              patch={clear_tag_filter_path(@list_params)}
            >
              Clear
            </.link>
          </div>
          <%!-- NOTE(Claude 2026-11-10): the page opens in Viewer mode; editors
             switch to Editor mode (this button, or the M key) to quick edit: a
             hovered cell is outlined; a click or the E key opens its editor (see
             `.CatalogTable`). Not remembered: each visit starts in Viewer mode. --%>
          <div :if={@can_edit} id="editor-mode" class="editor-mode">
            <p :if={@editor_mode} id="quick-edit-hint" class="quick-edit-hint">
              Click a cell or press <kbd>E</kbd> to edit it · arrows to move · <kbd>Esc</kbd> to leave
            </p>
            <button
              type="button"
              id="editor-mode-toggle"
              class={["editor-mode-toggle", @editor_mode && "is-on"]}
              phx-click="toggle_editor_mode"
              aria-pressed={to_string(@editor_mode)}
              title="Switch between Viewer and Editor mode (M)"
            >
              <.icon name="hero-pencil-square" /> Editor mode <kbd>M</kbd>
            </button>
          </div>
        </div>

        <%!-- NOTE(Claude 2026-11-10): hovering a decade of a sparkline shows its
           total of data points in a tooltip (see `.SparkTip`). --%>
        <div
          id="catalog-scroll"
          class={["table-scroll", @editor_mode && "is-editor-mode"]}
          phx-hook=".SparkTip"
        >
          <%!-- NOTE(Claude 2026-11-10): hovering a tag highlights it and the same
             tag in every other row (client side only); the quick edit's keys,
             clicks and keyboard cursor are handled there too (`.CatalogTable`). --%>
          <table
            id="catalog-table"
            class="catalog-table"
            phx-hook=".CatalogTable"
            tabindex="-1"
            data-can-edit={to_string(@can_edit)}
            data-editor-mode={to_string(@editor_mode)}
          >
            <%!-- NOTE(Claude 2026-11-06): the table's name, for screen readers. --%>
            <caption class="visually-hidden">FinnGen datasets</caption>
            <thead>
              <tr>
                <th scope="col">Dataset</th>
                <th scope="col">Tags</th>
                <%!-- NOTE(Claude 2026-11-09): stacked headings, for the columns
                   that hold two values one above the other. --%>
                <th scope="col">
                  <span class="stacked-value">Environment</span>
                  <span class="stacked-value">Access type</span>
                </th>
                <th scope="col">
                  <span class="stacked-value">Version</span>
                  <span class="stacked-value">Release date</span>
                </th>
                <th scope="col">
                  <span class="stacked-value">Modality</span>
                  <span class="stacked-value">Format</span>
                </th>
                <th scope="col">Documentation</th>
                <th scope="col">Location</th>
                <th scope="col">Data dictionary</th>
                <th scope="col">Data quality</th>
                <%!-- NOTE(Claude 2026-11-10): was "In OMOP?". --%>
                <th scope="col">OMOP-mapped</th>
                <th scope="col">
                  <span class="years-heading">
                    Years coverage <.year_axis domain={@year_domain} />
                  </span>
                </th>
                <th scope="col">
                  <span class="cohort-heading">
                    Cohort coverage <.cohort_axis />
                  </span>
                </th>
                <%!-- NOTE(Claude Opus 5.5 2026-11-17): for signed-in users only. --%>
                <th :if={@can_edit} id="maintainer-heading" scope="col">Maintainer</th>
              </tr>
            </thead>
            <tbody :for={dataset <- @datasets} id={"dataset-#{dataset.id}"} class="dataset">
              <.version_row
                :for={{version, index} <- Enum.with_index(dataset.versions)}
                dataset={dataset}
                version={version}
                current={index == 0}
                previous_count={length(dataset.versions) - 1}
                scope={@current_scope}
                quick_editable={@editor_mode}
                list_params={@list_params}
                tag_links
                year_domain={@year_domain}
                words={Search.words(@query)}
                quick_edit={@quick_edit}
              />
            </tbody>
          </table>
        </div>
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".CatalogTable">
        // NOTE(Codex-GPT-Sol-6.2 2026-11-19): manage the table's action and location popovers.
        class TablePopovers {
          constructor(el) {
            this.el = el
            this.nativePopover = HTMLElement.prototype.hasOwnProperty("popover")
            // The same test as the CSS rule (`app.css`): flipping needs
            // `position-try-fallbacks`, which a partial support could lack.
            this.cssAnchor = this.nativePopover && !!(window.CSS && CSS.supports("anchor-name: --a")
              && CSS.supports("(position-area: bottom) and (position-try-fallbacks: flip-block)"))
            this.menu = null
            this.escaped = false
            this.onToggle = e => {
              if (e.target.matches && e.target.matches("[data-table-popover]")) {
                this.menuToggled(e.target, e.newState === "open")
              }
            }
            // `toggle` does not bubble; it is caught on its way down.
            this.el.addEventListener("toggle", this.onToggle, true)
            // Placed from here (no CSS anchor positioning), a popover is hidden
            // until then: `toggle` comes after it shows, where it would flash.
            this.onBeforeToggle = e => {
              if (!this.cssAnchor && e.newState === "open" && e.target.matches("[data-table-popover]")) {
                e.target.style.visibility = "hidden"
              }
            }
            this.el.addEventListener("beforetoggle", this.onBeforeToggle, true)
            this.onReflow = () => this.placeMenu()
            this.observer = new IntersectionObserver(entries => {
              if (entries.some(entry => !entry.isIntersecting)) this.closeMenu()
            })
            this.markFallbackTriggers()
          }

          updated() {
            this.markFallbackTriggers()
            this.syncMenu()
          }

          destroyed() {
            this.el.removeEventListener("toggle", this.onToggle, true)
            this.el.removeEventListener("beforetoggle", this.onBeforeToggle, true)
            this.forgetMenu()
          }

          keydown(e) {
            if (this.openMenu()) {
              if (e.key === "Escape") {
                this.escaped = true
                if (!this.nativePopover) {
                  e.preventDefault()
                  this.closeMenu()
                }
              }
              return true
            }
          }

          click(e) {
            const t = e.target
            if (!this.nativePopover && t.closest) {
              const open = this.openMenu()
              const trigger = t.closest("[popovertarget]")
              if (trigger && this.el.contains(trigger)) {
                const menu = document.getElementById(trigger.getAttribute("popovertarget"))
                this.closeMenu()
                if (menu && menu !== open) this.openFallbackMenu(menu)
                return true
              }
              if (open && !open.contains(t)) this.closeMenu()
            }
            return this.openMenu()?.contains(t)
          }

          openMenu() {
            const selector = this.nativePopover ? ":popover-open" : ".is-open"
            return this.el.querySelector(`[data-table-popover]${selector}`)
          }
          triggerOf(menu) {
            return menu ? document.getElementById(menu.dataset.trigger) : null
          }
          shown(el) {
            if (!el || !el.isConnected) return false
            return el.checkVisibility ? el.checkVisibility() : el.getClientRects().length > 0
          }
          // NOTE(Codex-GPT-Sol-6.2 2026-11-19): Called once a popover has opened or closed (its `toggle` event, or
          // the disclosure's click). Escape, or a closing with the focus left
          // inside, returns the focus to its button.
          menuToggled(menu, open) {
            if (open) {
              this.forgetMenu()
              this.menu = menu.id
              this.escaped = false
              const trigger = this.triggerOf(menu)
              if (trigger) this.observer.observe(trigger)
              if (!this.cssAnchor) {
                window.addEventListener("scroll", this.onReflow, true)
                window.addEventListener("resize", this.onReflow)
              }
              this.placeMenu()
            } else if (this.menu === menu.id) {
              const escaped = this.escaped
              this.forgetMenu()
              const trigger = this.triggerOf(menu)
              // Only if the focus is lost: a key pressed right after Escape may
              // have moved it already (this event comes a moment later).
              const active = document.activeElement
              const inside = menu.contains(active)
              const lost = inside || !active || active === document.body || active === this.el
              if (lost && (escaped || inside) && this.shown(trigger)) {
                trigger.focus({ preventScroll: true })
              }
            }
          }
          // NOTE(Codex-GPT-Sol-6.2 2026-11-19): A disclosure's button says whether its list is open.
          markFallbackTriggers() {
            if (this.nativePopover) return
            this.el.querySelectorAll("[popovertarget]:not([aria-expanded])")
              .forEach(b => b.setAttribute("aria-expanded", "false"))
          }
          forgetMenu() {
            this.menu = null
            this.escaped = false
            this.observer && this.observer.disconnect()
            window.removeEventListener("scroll", this.onReflow, true)
            window.removeEventListener("resize", this.onReflow)
          }
          openFallbackMenu(menu) {
            menu.classList.add("is-open")
            const trigger = this.triggerOf(menu)
            if (trigger) trigger.setAttribute("aria-expanded", "true")
            this.menuToggled(menu, true)
          }
          closeMenu() {
            const menu = this.openMenu()
            if (!menu) return
            if (this.nativePopover) return menu.hidePopover()
            menu.classList.remove("is-open")
            const trigger = this.triggerOf(menu)
            if (trigger) trigger.setAttribute("aria-expanded", "false")
            this.menuToggled(menu, false)
          }
          // NOTE(Codex-GPT-Sol-6.2 2026-11-19): Without CSS anchor positioning: under the button, its right edge on
          // the button's; above it if there is no room below; moved right if it
          // would cross the viewport's left edge (as the CSS fallbacks do).
          placeMenu() {
            const menu = this.openMenu()
            const trigger = this.triggerOf(menu)
            if (!menu || !trigger || this.cssAnchor) return
            const r = trigger.getBoundingClientRect()
            const width = menu.offsetWidth
            const height = menu.offsetHeight
            const gap = 4
            const edge = 8
            let top = r.bottom + gap
            if (top + height > window.innerHeight - edge && r.top - gap - height >= edge) {
              top = r.top - gap - height
            }
            let left = r.right - width
            if (left < edge) left = Math.min(r.left, window.innerWidth - width - edge)
            menu.style.top = `${Math.max(edge, top)}px`
            menu.style.left = `${Math.max(edge, left)}px`
            menu.style.visibility = ""
          }
          // NOTE(Codex-GPT-Sol-6.2 2026-11-19): After a LiveView patch: the open popover stays open while its
          // button is shown (a native one stays open by itself; a disclosure's
          // class and inline position, reset by the patch, are set again);
          // otherwise it is closed, and the table takes the focus if it was lost.
          syncMenu() {
            if (!this.menu) return
            const menu = document.getElementById(this.menu)
            const trigger = this.triggerOf(menu)
            if (!this.nativePopover && menu && this.shown(trigger)) {
              menu.classList.add("is-open")
              trigger.setAttribute("aria-expanded", "true")
            }
            if (this.openMenu() && this.shown(trigger)) return this.placeMenu()
            this.closeMenu()
            this.forgetMenu()
            const active = document.activeElement
            if (!active || active === document.body || !active.isConnected) {
              this.el.focus({ preventScroll: true })
            }
          }
        }

        export default {
          mounted() {
            // NOTE(Claude 2026-11-10): one delegated listener for all the chips;
            // the hovered tag is kept so that rows re-rendered live keep the mark.
            this.tag = null
            this.el.addEventListener("mouseover", e => {
              const chip = e.target.closest(".tags li[data-tag]")
              this.highlight(chip && this.el.contains(chip) ? chip.dataset.tag : null)
            })
            this.el.addEventListener("mouseleave", () => this.highlight(null))

            // NOTE(Claude 2026-11-10): the quick edit, for editors. The page
            // opens in Viewer mode; M switches to Editor mode (and back), where
            // the editable values (`data-quick-edit`) are marked. There, a click
            // on a value (not on a link or button in it), or E on the hovered
            // one, or Enter / F2 / E on the focused one, opens its editor. The
            // focused value is a cursor, moved with the arrow keys, Home and
            // End, and the table's only Tab stop; it gets the focus back when
            // its editor closes. Escape leaves Editor mode.
            // NOTE(Claude Opus 5.5 2026-11-19): so does a click outside the
            // table (`leavesEditorMode`).
            this.cursor = null
            this.restoreFocus = false
            this.wasEditorMode = false
            this.onKeydown = e => this.keydown(e)
            this.onClick = e => this.click(e)
            // NOTE(Claude Opus 5.5 2026-11-19): see `leavesEditorMode`.
            this.popoverOpenAtDown = false
            this.onPointerdown = () => { this.popoverOpenAtDown = !!this.popovers.openMenu() }
            window.addEventListener("keydown", this.onKeydown)
            document.addEventListener("click", this.onClick)
            document.addEventListener("pointerdown", this.onPointerdown, true)
            this.el.addEventListener("focusin", e => {
              if (e.target.matches("[data-quick-edit]")) {
                this.cursor = this.keyOf(e.target)
                this.syncCursor()
              }
            })
            this.syncCursor()

            this.popovers = new TablePopovers(this.el)
            this.handleEvent("row_action", ({ id, ok }) => {
              requestAnimationFrame(() => this.actionDone(id, ok))
            })
          },
          updated() {
            const tag = this.tag
            this.tag = null
            this.highlight(tag)
            this.syncCursor()
            this.popovers.updated()
          },
          destroyed() {
            window.removeEventListener("keydown", this.onKeydown)
            document.removeEventListener("click", this.onClick)
            document.removeEventListener("pointerdown", this.onPointerdown, true)
            this.popovers.destroyed()
          },

          // After Publish, Unpublish or Archive (`row_action`, sent once the
          // result is rendered): a failure leaves the popover open, to retry, if
          // its button is still shown. Otherwise the popover is closed and the
          // focus goes to the row's button, or to the table if it is gone.
          actionDone(id, ok) {
            const trigger = document.getElementById(`actions-${id}`)
            const shown = this.popovers.shown(trigger)
            if (!ok && shown) return
            if (this.popovers.openMenu()?.dataset.trigger === `actions-${id}`) {
              this.popovers.closeMenu()
              this.popovers.forgetMenu()
            }
            if (shown) trigger.focus({ preventScroll: true })
            else this.el.focus({ preventScroll: true })
          },
          highlight(tag) {
            if (tag === this.tag) return
            this.tag = tag
            this.el.querySelectorAll(".tags li.is-tag-hovered")
              .forEach(li => li.classList.remove("is-tag-hovered"))
            if (tag === null) return
            this.el.querySelectorAll(".tags li[data-tag]").forEach(li => {
              if (li.dataset.tag === tag) li.classList.add("is-tag-hovered")
            })
          },

          canEdit() { return this.el.dataset.canEdit === "true" },
          editorMode() { return this.el.dataset.editorMode === "true" },
          inlineEditor() { return this.el.querySelector("#quick-edit-form") },
          dialogOpen() { return !!document.querySelector("dialog[open]") },
          rows() {
            return Array.from(this.el.querySelectorAll("tbody tr[data-version-id]")).filter(r => !r.hidden)
          },
          // The editable values of a cell, top to bottom; the dataset's name
          // and description are one.
          stops(cell) {
            if (!cell) return []
            if (cell.matches("[data-quick-edit]")) return [cell]
            const seen = new Set()
            return Array.from(cell.querySelectorAll("[data-quick-edit]")).filter(s => {
              if (seen.has(s.dataset.quickEdit)) return false
              seen.add(s.dataset.quickEdit)
              return true
            })
          },
          keyOf(stop) {
            return { id: stop.closest("tr[data-version-id]").dataset.versionId, field: stop.dataset.quickEdit }
          },
          find(key) {
            if (!key) return null
            const row = this.el.querySelector(`tr[data-version-id="${key.id}"]`)
            return row && !row.hidden ? row.querySelector(`[data-quick-edit="${key.field}"]`) : null
          },
          first() {
            for (const row of this.rows()) {
              const stop = row.querySelector("[data-quick-edit]")
              if (stop) return stop
            }
            return null
          },
          // NOTE(Claude 2026-11-10): the cursor is the table's Tab stop
          // (`tabindex` 0, the other values -1, as rendered); called after each
          // update, which renders them all at -1 again.
          // NOTE(Claude 2026-11-10): the cursor is kept in Viewer mode, so that
          // switching back to Editor mode returns to it (focused and scrolled
          // into view), if its row is still shown. Not kept across visits.
          syncCursor() {
            const editorMode = this.editorMode()
            const entering = editorMode && !this.wasEditorMode
            this.wasEditorMode = editorMode
            if (!editorMode) {
              this.restoreFocus = false
              return
            }
            const remembered = this.find(this.cursor)
            const stop = remembered || this.first()
            this.el.querySelectorAll('[data-quick-edit][tabindex="0"]')
              .forEach(s => { if (s !== stop) s.tabIndex = -1 })
            if (stop) stop.tabIndex = 0
            if (entering && remembered && !this.dialogOpen()) {
              remembered.focus({ preventScroll: true })
              this.reveal(remembered)
            } else if (this.restoreFocus && !this.inlineEditor() && !this.dialogOpen()) {
              this.restoreFocus = false
              // NOTE(Claude Opus 5.5 2026-11-19): or on the table itself, which a
              // click on a cell now focuses (`tabindex="-1"`).
              const active = document.activeElement
              if (stop && (!active || active === document.body || active === this.el)) stop.focus()
            }
          },
          moveTo(stop) {
            if (!stop) return
            this.cursor = this.keyOf(stop)
            this.syncCursor()
            stop.focus({ preventScroll: true })
            this.reveal(stop)
          },
          // NOTE(Claude 2026-11-10): scrolls `el` into the table's view, clear of
          // the sticky header row and first column (as wide as their content).
          reveal(el) {
            const scroll = this.el.closest(".table-scroll")
            const head = this.el.querySelector("thead")
            const first = this.el.querySelector("thead th")
            if (scroll) {
              scroll.style.scrollPaddingTop = `${head ? head.offsetHeight : 0}px`
              const sticky = el.closest("th") ? 0 : (first ? first.offsetWidth : 0)
              scroll.style.scrollPaddingLeft = `${sticky}px`
            }
            el.scrollIntoView({ block: "nearest", inline: "nearest" })
          },
          // The value next to `stop` in direction `key`: within a stacked cell
          // first, then in the next row (or column) that has one.
          next(stop, key) {
            const rows = this.rows()
            const row = stop.closest("tr")
            const r = rows.indexOf(row)
            const cell = stop.closest("td, th")
            const col = cell.cellIndex
            const here = this.stops(cell)
            const level = Math.max(0, here.findIndex(s => s.dataset.quickEdit === stop.dataset.quickEdit))
            const inRow = Array.from(row.cells).flatMap(c => this.stops(c))
            switch (key) {
              case "ArrowUp":
                if (level > 0) return here[level - 1]
                for (let i = r - 1; i >= 0; i--) {
                  const s = this.stops(rows[i].cells[col])
                  if (s.length) return s[s.length - 1]
                }
                return null
              case "ArrowDown":
                if (level < here.length - 1) return here[level + 1]
                for (let i = r + 1; i < rows.length; i++) {
                  const s = this.stops(rows[i].cells[col])
                  if (s.length) return s[0]
                }
                return null
              case "ArrowLeft":
              case "ArrowRight": {
                const step = key === "ArrowLeft" ? -1 : 1
                for (let c = col + step; c >= 0 && c < row.cells.length; c += step) {
                  const s = this.stops(row.cells[c])
                  if (s.length) return s[Math.min(level, s.length - 1)]
                }
                return null
              }
              case "Home": return inRow[0]
              case "End": return inRow[inRow.length - 1]
            }
            return null
          },
          // Opens the editor of `stop`.
          edit(stop) {
            this.cursor = this.keyOf(stop)
            this.restoreFocus = true
            // NOTE(Claude 2026-11-10): the reply comes once the editor is
            // rendered; scrolled into the table's view, so that its Save and
            // Cancel icons show in the last column too.
            this.pushEvent("quick_edit", this.cursor, () => {
              const form = this.inlineEditor()
              if (form) this.reveal(form)
            })
          },
          // NOTE(Claude 2026-11-10): no key works while typing, with a modifier,
          // or under a dialog; nor, but M, while an editor is open.
          // NOTE(Claude Opus 5.5 2026-11-19): no key works either while a row's
          // actions popover is open, but Escape closes it (the browser does, for
          // a native one) and gives the focus back to its button; the next
          // Escape leaves Editor mode.
          keydown(e) {
            if (this.popovers.keydown(e) || !this.canEdit()) return
            if (e.ctrlKey || e.metaKey || e.altKey) return
            const t = e.target
            if (t.closest && t.closest("input, textarea, select, [contenteditable], dialog")) return
            if (this.dialogOpen()) return
            const key = e.key
            if (key === "m" || key === "M") {
              if (!e.repeat) this.pushEvent("toggle_editor_mode", {})
              return e.preventDefault()
            }
            if (!this.editorMode() || this.inlineEditor()) return
            if (key === "Escape") return this.pushEvent("leave_editor_mode", {})

            const focused = t.matches && t.matches("[data-quick-edit]") && this.el.contains(t) ? t : null
            if (key === "e" || key === "E" || key === "Enter" || key === "F2") {
              if (e.repeat) return
              let stop = focused
              if (key === "e" || key === "E") {
                const hovered = this.el.querySelectorAll("[data-quick-edit]:hover")
                stop = hovered[hovered.length - 1] || focused
              }
              if (!stop) return
              e.preventDefault()
              return this.edit(stop)
            }
            if (!["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Home", "End"].includes(key)) return
            // Arrows from outside the table scroll the page as usual; from
            // nowhere (the body), they start at the cursor.
            if (!focused) {
              if (t !== document.body && !this.el.contains(t)) return
              e.preventDefault()
              return this.moveTo(this.find(this.cursor) || this.first())
            }
            e.preventDefault()
            this.moveTo(this.next(focused, key))
          },
          async copyLocation(button) {
            const path = document.getElementById(button.dataset.copyLocation)
            const status = document.getElementById(button.dataset.copyStatus)
            if (!path || !status) return
            try {
              await navigator.clipboard.writeText(path.textContent)
              status.textContent = "Copied"
            } catch {
              const range = document.createRange()
              range.selectNodeContents(path)
              const selection = window.getSelection()
              selection.removeAllRanges()
              selection.addRange(range)
              status.textContent = "Path selected. Use your browser’s copy shortcut."
            }
          },
          click(e) {
            const t = e.target
            const copy = t.closest("[data-copy-location]")
            if (copy && this.el.contains(copy)) this.copyLocation(copy)
            if (this.popovers.click(e) || !this.canEdit()) return
            const form = this.inlineEditor()
            if (form && form.contains(t)) return
            if (t.closest && t.closest("dialog")) return
            const stop = this.editorMode() && this.el.contains(t) ? t.closest("[data-quick-edit]") : null
            const interactive = t.closest && t.closest("a, button, input, select, textarea, label, summary")
            if (stop && !interactive) {
              // A click in the cell of the open editor, around it, keeps it.
              if (form && stop.contains(form)) return
              return this.edit(stop)
            }
            // NOTE(Claude Opus 5.5 2026-11-19): a click outside the table leaves
            // Editor mode (and closes any open editor with it).
            if (this.leavesEditorMode(e)) return this.pushEvent("leave_editor_mode", {})
            if (form) this.pushEvent("quick_cancel", {})
          },
          // NOTE(Claude Opus 5.5 2026-11-19): whether click `e` is outside the
          // table, in Editor mode. Not outside: the table and its popovers (in
          // it), the dialogs, the search field and tag filter, the Editor mode
          // button and hint, the flash messages, and the table's scroll bars.
          // The empty space of their boxes is outside: the search form and
          // `#editor-mode` span the page's width. Neither is a click that
          // dismissed a popover (closed on `pointerdown`, before the click): the
          // next one is.
          leavesEditorMode(e) {
            const t = e.target
            if (!this.editorMode() || this.popoverOpenAtDown || !t.closest) return false
            if (this.el.contains(t)) return false
            if (t.closest("dialog, #search-form .field, #tag-filter, #editor-mode-toggle, #quick-edit-hint, #flash-group")) return false
            const scroll = this.el.closest(".table-scroll")
            if (t === scroll && (e.offsetX >= scroll.clientWidth || e.offsetY >= scroll.clientHeight)) return false
            return true
          }
        }
      </script>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".SparkTip">
        export default {
          mounted() {
            // NOTE(Claude 2026-11-10): one tooltip for all the sparklines, on the
            // body, out of LiveView's reach; it shows the hovered chunk's
            // years and total (see `CatalogComponents.sparkline/1`).
            // NOTE(Claude 2026-11-12): on two lines, the years above the total.
            this.years = document.createElement("div")
            this.points = document.createElement("div")
            // NOTE(Claude 2026-11-12): placed above the chunk's sparkline, not the
            // chunk, so that it stays put as the pointer moves along the plot.
            this.tip = document.createElement("div")
            this.tip.className = "spark-tip"
            this.tip.setAttribute("aria-hidden", "true")
            this.tip.hidden = true
            this.tip.append(this.years, this.points)
            document.body.appendChild(this.tip)
            this.el.addEventListener("mouseover", e => {
              const chunk = e.target.closest && e.target.closest(".sparkline .chunk")
              if (!chunk) return this.hide()
              const box = chunk.closest("svg.sparkline").getBoundingClientRect()
              this.years.textContent = chunk.dataset.tipYears
              this.points.textContent = chunk.dataset.tipPoints
              // NOTE(Claude 2026-11-12): from the plot's left edge, not its
              // center, so that the text starts at the same place whatever its
              // length (see `.spark-tip`).
              this.tip.style.left = `${box.left}px`
              this.tip.style.top = `${box.top}px`
              this.tip.hidden = false
            })
            this.el.addEventListener("mouseleave", () => this.hide())
            this.el.addEventListener("scroll", () => this.hide(), { passive: true })
          },
          hide() { this.tip.hidden = true },
          destroyed() { this.tip.remove() }
        }
      </script>

      <p :if={@all_datasets == []} id="no-datasets" class="empty">No datasets yet.</p>
      <p :if={@datasets == [] and @all_datasets != []} id="no-results" class="empty">
        <%!-- NOTE(Claude 2026-11-12): with the tag filter too. --%>
        {no_results(@query, @tags)}
      </p>

      <%!-- NOTE(Claude 2026-11-04): an unsaved new dataset from an earlier visit
           is kept, and restored when the form page is opened again. --%>
      <p :if={@can_edit} class="add-dataset">
        <.link id="add-dataset" navigate={~p"/datasets/new"}>
          {if @has_draft, do: "Continue adding dataset", else: "Add missing dataset"}
        </.link>
      </p>

      <.modal
        :if={@dictionary}
        id="dictionary-modal"
        title_id="dictionary-title"
        close_to={catalog_path(@list_params)}
      >
        <:title>
          {elem(@dictionary, 0).name} {elem(@dictionary, 1).version} · Data dictionary
        </:title>
        <table class="dictionary-table">
          <thead>
            <tr>
              <th scope="col">Column</th>
              <th scope="col">Details</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={entry <- elem(@dictionary, 1).data_dictionary}>
              <td>{entry.col_name}</td>
              <td>
                <div class="dictionary-details">{entry.details}</div>
              </td>
            </tr>
          </tbody>
        </table>
      </.modal>

      <%!-- NOTE(Claude 2026-11-16): a version's data quality: its answer to each
           criterion, opened from its score (`?quality=ID`), for everyone. --%>
      <.modal
        :if={@quality}
        id="quality-modal"
        title_id="quality-title"
        close_to={catalog_path(@list_params)}
      >
        <:title>
          {elem(@quality, 0).name} {elem(@quality, 1).version} · Data quality · {DataQuality.score_text(
            elem(@quality, 1).data_quality
          )}
        </:title>
        <.quality_criteria answers={elem(@quality, 1).data_quality} />
      </.modal>

      <%!-- NOTE(Claude 2026-11-10): the quick edit of a field with several values
           (lists, links, CSV), too big for its cell: the edit page's input,
           alone in a modal, saved on Save (not as typed, as on the edit page). --%>
      <.modal
        :if={@quick_edit && @quick_edit.field not in quick_inline_fields()}
        id="quick-edit-modal"
        title_id="quick-edit-title"
        close_to={catalog_path(@list_params)}
      >
        <:title>
          {@quick_edit.dataset_name} {@quick_edit.version_name} · {quick_edit_label(@quick_edit.field)}
        </:title>
        <.form
          for={@quick_edit.form}
          id="quick-edit-form"
          class="dataset-form quick-edit-modal-form"
          phx-change="quick_validate"
          phx-submit="quick_save"
        >
          <DatasetFormComponents.version_fields
            form={@quick_edit.form}
            debounce="300"
            suggestions={@quick_edit.suggestions}
            only={quick_edit_only(@quick_edit.field)}
          />
          <div class="form-actions">
            <.button id="quick-edit-save" variant="primary">Save</.button>
            <button
              id="quick-edit-cancel"
              type="button"
              class="btn btn-secondary"
              phx-click="quick_cancel"
            >
              Cancel
            </button>
          </div>
        </.form>
      </.modal>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    # NOTE(Claude 2026-11-03): rows changed by anyone are updated live.
    if connected?(socket), do: Changelog.subscribe()

    # NOTE(Claude 2026-11-06): what the signed-in user may do (see
    # `FGDataCatalog.Accounts.Scope`); visitors only read.
    scope = socket.assigns.current_scope
    can_edit? = Scope.editor?(scope)

    {:ok,
     socket
     |> assign(:page_title, "Datasets")
     |> assign(:can_edit, can_edit?)
     |> assign(
       :has_draft,
       can_edit? and Catalog.get_dataset_draft_params(Scope.user_id(scope)) != nil
     )
     |> assign(:query, "")
     |> assign(:tags, [])
     |> assign(:list_params, %{})
     |> assign(:quick_edit, nil)
     |> assign(:editor_mode, false)
     |> assign(:quality, nil)
     |> assign_datasets()}
  end

  # NOTE(Claude 2026-11-02): `/?dictionary=ID` opens a version's data dictionary.
  # NOTE(Claude 2026-11-06): and `?q=` searches the catalog.
  # NOTE(Claude 2026-11-16): and `?quality=ID` opens a version's data quality.
  # NOTE(Claude 2026-11-12): and `?tags[]=` filters it by tags.
  @impl true
  def handle_params(params, _uri, socket) do
    query = params |> Map.get("q", "") |> to_string() |> String.trim()
    tags = tag_params(params["tags"])
    quality = find_version(socket.assigns.all_datasets, params["quality"])

    {:noreply,
     socket
     |> assign(:query, query)
     |> assign(:tags, tags)
     |> assign(:list_params, list_params(query, tags))
     |> assign_datasets(socket.assigns.all_datasets)
     |> assign(:dictionary, find_version(socket.assigns.all_datasets, params["dictionary"]))
     |> assign_quality(quality)
     # NOTE(Claude 2026-11-10): a patch (the search, or closing a modal, the
     # quick edit's too) ends any quick edit.
     |> assign(:quick_edit, nil)}
  end

  @impl true
  # NOTE(Claude 2026-11-16): an open data quality modal shows the new answers.
  def handle_info({:catalog_changed, _change_set_id}, socket) do
    socket = assign_datasets(socket)
    socket = assign_quality(socket, reload_version(socket, socket.assigns.quality))

    # NOTE(Claude 2026-11-10): a quick edit stays open, its form as typed,
    # unless its version is gone (archived, or no longer visible).
    case socket.assigns.quick_edit do
      %{version_id: id} ->
        if find_row(socket, to_string(id)),
          do: {:noreply, socket},
          else: {:noreply, assign(socket, :quick_edit, nil)}

      nil ->
        {:noreply, socket}
    end
  end

  # NOTE(Claude 2026-11-06): the search is kept in the URL (replacing the
  # history entry, so typing does not fill the history); any open dictionary
  # stays open.
  @impl true
  # NOTE(Claude 2026-11-12): the tag filter is kept too.
  def handle_event("search", %{"q" => query}, socket) do
    params = list_params(String.trim(query), socket.assigns.tags)

    params =
      case socket.assigns.dictionary do
        {_dataset, version} -> Map.put(params, "dictionary", version.id)
        nil -> params
      end

    # NOTE(Claude 2026-11-16): and any open data quality modal.
    params =
      case socket.assigns.quality do
        {_dataset, version} -> Map.put(params, "quality", version.id)
        nil -> params
      end

    {:noreply, push_patch(socket, to: catalog_path(params), replace: true)}
  end

  # NOTE(Claude 2026-11-16): the state transitions of the row actions. Checked
  # server-side: the `Catalog` functions refuse what `Catalog.can?/3` does not
  # allow on the version as it is in the database, whatever the page showed.
  def handle_event("archive", %{"id" => id}, socket) do
    transition(socket, id, &Catalog.archive_version/2, "archive")
  end

  def handle_event("publish", %{"id" => id}, socket) do
    transition(socket, id, &Catalog.publish_dataset_version/2, "publish")
  end

  def handle_event("unpublish", %{"id" => id}, socket) do
    transition(socket, id, &Catalog.unpublish_dataset_version/2, "unpublish")
  end

  # NOTE(Claude 2026-11-10): OMOP-mapped is not edited but cycled, saved at
  # once: Unknown, Yes, No, Unknown…
  # NOTE(Claude Opus 5.5 2026-11-18): Not applicable comes after No.
  def handle_event("quick_edit", %{"id" => id, "field" => "omop_integration"}, socket) do
    with true <- socket.assigns.can_edit and socket.assigns.editor_mode,
         {_dataset, version, _current?} <- find_row(socket, to_string(id)),
         true <- Catalog.can?(socket.assigns.current_scope, :write, version) do
      index = Enum.find_index(@omop_cycle, &(&1 == version.omop_integration)) || 0
      next = Enum.at(@omop_cycle, rem(index + 1, length(@omop_cycle)))
      save_toggle(socket, id, %{"omop_integration" => to_string(next)})
    else
      _ -> {:noreply, socket}
    end
  end

  # NOTE(Claude 2026-11-10): opens the quick edit of a version's `field`, for an
  # editor, on a version they may write (the same rule as the edit page, see
  # `Catalog.can?/3`).
  # NOTE(Claude 2026-11-17): the dataset's name and description through any
  # version, no longer the current one only.
  def handle_event("quick_edit", %{"id" => id, "field" => field}, socket) do
    with true <- socket.assigns.can_edit and socket.assigns.editor_mode,
         {dataset, version, _current?} <- find_row(socket, to_string(id)),
         true <- Catalog.can?(socket.assigns.current_scope, :write, version),
         true <- field in @quick_fields do
      quick_edit = %{
        version_id: version.id,
        dataset_name: Catalog.proposed_dataset(dataset, version).name,
        version_name: version.version,
        field: field,
        form: quick_form(field, dataset, version, %{}, nil),
        suggestions: quick_suggestions(field)
      }

      {:noreply, assign(socket, :quick_edit, quick_edit)}
    else
      _ -> {:noreply, socket}
    end
  end

  # NOTE(Claude 2026-11-10): a select saves on change, as Enter does not
  # submit a form from a select.
  def handle_event(
        "quick_validate",
        params,
        %{assigns: %{quick_edit: %{field: "access_type"}}} = socket
      ) do
    handle_event("quick_save", params, socket)
  end

  def handle_event("quick_validate", params, %{assigns: %{quick_edit: %{} = quick_edit}} = socket) do
    case find_row(socket, to_string(quick_edit.version_id)) do
      {dataset, version, _current?} ->
        form = quick_form(quick_edit.field, dataset, version, quick_params(params), :validate)
        {:noreply, assign(socket, :quick_edit, %{quick_edit | form: form})}

      nil ->
        {:noreply, assign(socket, :quick_edit, nil)}
    end
  end

  # NOTE(Claude 2026-11-10): saved like a change on the edit page (one change
  # set in the changelog), with the params of the quick edit's form (its
  # field's only), onto the version as now loaded; an invalid value is shown
  # with its errors and not saved.
  def handle_event("quick_save", params, %{assigns: %{quick_edit: %{} = quick_edit}} = socket) do
    with true <- socket.assigns.can_edit,
         {dataset, version, _current?} <- find_row(socket, to_string(quick_edit.version_id)) do
      params = quick_params(params)

      {dataset_params, version_params} =
        if quick_edit.field == "dataset",
          do: {Map.take(params, ~w(name description)), %{}},
          else: {%{}, VersionParams.split_lists(params)}

      case Catalog.update_dataset_row(dataset, dataset_params, version, version_params,
             scope: socket.assigns.current_scope
           ) do
        {:ok, _row} ->
          {:noreply, socket |> assign(:quick_edit, nil) |> assign_datasets()}

        # NOTE(Claude 2026-11-16): the version left the viewer's hands since
        # the page loaded (see `Catalog.can?/3`).
        {:error, :unauthorized} ->
          {:noreply,
           socket
           |> assign(:quick_edit, nil)
           |> assign_datasets()
           |> put_flash(:error, "You can no longer edit that version.")}

        {:error, %Ecto.Changeset{} = changeset} ->
          form = to_form(changeset, as: quick_form_name(quick_edit.field), action: :validate)
          {:noreply, assign(socket, :quick_edit, %{quick_edit | form: form})}
      end
    else
      _ -> {:noreply, assign(socket, :quick_edit, nil)}
    end
  end

  # NOTE(Claude 2026-11-10): Viewer mode (the default) and Editor mode, where
  # editors may quick edit; leaving Editor mode closes any quick edit.
  def handle_event("toggle_editor_mode", _params, socket) do
    set_editor_mode(socket, !socket.assigns.editor_mode)
  end

  def handle_event("leave_editor_mode", _params, socket), do: set_editor_mode(socket, false)

  def handle_event("quick_cancel", _params, socket) do
    {:noreply, assign(socket, :quick_edit, nil)}
  end

  # NOTE(Claude 2026-11-10): a quick edit event without a quick edit open
  # (e.g. from a stale page). Nothing to do.
  def handle_event(event, _params, socket) when event in ["quick_validate", "quick_save"] do
    {:noreply, socket}
  end

  # NOTE(Claude 2026-11-10): saves a one-action change of version `id` (a
  # cycled OMOP-mapped), as one change set; any open quick
  # edit is closed.
  defp save_toggle(socket, id, version_params) do
    with {dataset, version, _current?} <- find_row(socket, to_string(id)),
         {:ok, _row} <-
           Catalog.update_dataset_row(dataset, %{}, version, version_params,
             scope: socket.assigns.current_scope
           ) do
      {:noreply, socket |> assign(:quick_edit, nil) |> assign_datasets()}
    else
      _ -> {:noreply, put_flash(socket, :error, "That change could not be saved.")}
    end
  end

  defp set_editor_mode(socket, on?) do
    on? = on? and socket.assigns.can_edit
    socket = if on?, do: socket, else: assign(socket, :quick_edit, nil)
    {:noreply, assign(socket, :editor_mode, on?)}
  end

  # NOTE(Claude 2026-11-16): the dataset as the version shows it (a Draft's
  # proposed name and description, see `Catalog.update_dataset_row/5`).
  defp quick_form("dataset", dataset, version, params, action) do
    dataset = Catalog.proposed_dataset(dataset, version)
    to_form(Catalog.change_dataset(dataset, params), as: "quick_dataset", action: action)
  end

  defp quick_form(_field, _dataset, version, params, action) do
    changeset = Catalog.change_dataset_version(version, VersionParams.split_lists(params))
    to_form(changeset, as: "quick_version", action: action)
  end

  defp quick_form_name("dataset"), do: "quick_dataset"
  defp quick_form_name(_field), do: "quick_version"

  defp quick_params(%{"quick_dataset" => params}), do: params
  defp quick_params(%{"quick_version" => params}), do: params
  defp quick_params(_params), do: %{}

  # NOTE(Claude 2026-11-10): the existing values, suggested while typing, as
  # on the edit page.
  defp quick_suggestions("tags"), do: %{tags: Catalog.list_tags()}
  defp quick_suggestions("modalities"), do: %{modalities: Catalog.list_modalities()}
  defp quick_suggestions("formats"), do: %{formats: Catalog.list_formats()}
  defp quick_suggestions("environments"), do: %{environments: Catalog.list_environments()}
  defp quick_suggestions(_field), do: %{}

  defp quick_edit_only(field), do: @quick_modal_fields |> Map.fetch!(field) |> elem(0)
  defp quick_edit_label(field), do: @quick_modal_fields |> Map.fetch!(field) |> elem(1)

  # NOTE(Claude 2026-11-10): version `id` among those loaded (the viewer's), as
  # `{dataset, version, current?}`.
  defp find_row(socket, id) do
    Enum.find_value(socket.assigns.all_datasets, fn dataset ->
      case Enum.find_index(dataset.versions, &(to_string(&1.id) == id)) do
        nil -> nil
        index -> {dataset, Enum.at(dataset.versions, index), index == 0}
      end
    end)
  end

  # NOTE(Claude 2026-11-16): runs `fun.(scope, version)` on version `id`, among
  # those loaded; its refusal is shown.
  # NOTE(Claude Opus 5.5 2026-11-19): tells `.CatalogTable` how it went
  # (`row_action`), so that it closes the row's actions popover and moves the
  # focus after a success, and keeps the popover open after a failure.
  defp transition(socket, id, fun, verb) do
    version = find_loaded_version(socket, id)

    {socket, ok?} =
      with %{} <- version,
           {:ok, _} <- fun.(socket.assigns.current_scope, version) do
        {assign_datasets(socket), true}
      else
        {:error, %Ecto.Changeset{} = changeset} ->
          {put_flash(socket, :error, "Not published: #{dataset_errors(changeset)}."), false}

        _ ->
          {put_flash(socket, :error, "You cannot #{verb} that version."), false}
      end

    {:noreply, push_event(socket, "row_action", %{id: to_string(id), ok: ok?})}
  end

  # NOTE(Claude 2026-11-16): e.g. the proposed name, taken by another dataset
  # meanwhile.
  defp dataset_errors(changeset) do
    Enum.map_join(changeset.errors, "; ", fn {field, {message, _opts}} ->
      "the dataset #{field} #{message}"
    end)
  end

  defp find_loaded_version(socket, id) do
    socket.assigns.all_datasets
    |> Enum.flat_map(& &1.versions)
    |> Enum.find(&(to_string(&1.id) == id))
  end

  # NOTE(Claude 2026-11-16): with every Draft for an editor, none for a visitor.
  defp assign_datasets(socket) do
    datasets = Catalog.list_datasets(socket.assigns.current_scope)

    socket
    |> assign_datasets(datasets)
    |> assign(:last_updated, last_updated())
  end

  # NOTE(Claude 2026-11-06): `list_params` are the URL parameters of the list
  # (the search), kept when the dictionary modal opens or closes.
  # `all_datasets` are those the viewer may see,
  # `datasets` those matching the search, shown in the table.
  # NOTE(Claude 2026-11-12): and the tag filter.
  defp assign_datasets(socket, all_datasets) do
    shown =
      all_datasets
      |> Search.filter(socket.assigns.query, maintainer: socket.assigns.can_edit)
      |> Search.filter_tags(socket.assigns.tags)

    socket
    |> assign(:all_datasets, all_datasets)
    |> assign_shown(shown)
    |> assign(:search_form, to_form(%{"q" => socket.assigns.query}))
  end

  # NOTE(Claude 2026-11-12): the list's URL parameters; none when empty, so
  # that the URL stays clean.
  defp list_params(query, tags) do
    for {key, value} <- %{"q" => query, "tags" => tags},
        value not in ["", []],
        into: %{},
        do: {key, value}
  end

  # NOTE(Claude 2026-11-12): `tags[]=…` is a list, a hand-written `tags=…` a
  # string; blanks and repeats are dropped.
  defp tag_params(tags) do
    tags
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  # NOTE(Claude 2026-11-06): the sparklines share the years of the rows shown.
  defp assign_shown(socket, datasets) do
    socket
    |> assign(:datasets, datasets)
    |> assign(:year_domain, year_domain(datasets))
  end

  # NOTE(Claude 2026-11-12): shown with a search or a tag filter.
  defp search_count("", [], _shown, _total), do: nil
  defp search_count(_query, _tags, shown, total), do: "#{shown} of #{total} datasets"

  defp no_results(query, []), do: "No datasets match “#{query}”."
  defp no_results("", tags), do: "No datasets are tagged #{quoted_tags(tags)}."

  defp no_results(query, tags),
    do: "No datasets tagged #{quoted_tags(tags)} match “#{query}”."

  defp quoted_tags(tags), do: Enum.map_join(tags, " and ", &"“#{&1}”")

  # NOTE(Claude 2026-11-16): the data quality modal's version (`{dataset,
  # version}` or nil).
  defp assign_quality(socket, quality), do: assign(socket, :quality, quality)

  # NOTE(Claude 2026-11-16): `{dataset, version}` as now loaded, or nil if the
  # viewer no longer sees it.
  defp reload_version(socket, {_dataset, version}),
    do: find_version(socket.assigns.all_datasets, to_string(version.id))

  defp reload_version(_socket, nil), do: nil

  # NOTE(Claude 2026-11-02): looks the version up among the already loaded
  # ones, so a URL can never reveal a draft the viewer may not see.
  defp find_version(datasets, id) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} ->
        Enum.find_value(datasets, fn dataset ->
          version = Enum.find(dataset.versions, &(&1.id == id))
          version && {dataset, version}
        end)

      _ ->
        nil
    end
  end

  defp find_version(_datasets, _id), do: nil

  # NOTE(Claude 2026-11-06): the day of the latest change to the catalog (an
  # edit, addition, archiving or publication), not of the latest release.
  defp last_updated do
    case Changelog.last_changed_at() do
      nil -> nil
      datetime -> DateTime.to_date(datetime)
    end
  end
end
