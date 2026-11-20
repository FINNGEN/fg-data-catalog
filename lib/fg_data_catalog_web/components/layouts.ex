defmodule FGDataCatalogWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use FGDataCatalogWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  # NOTE(Claude Opus 5.5 2026-11-18): the page's `<title>`, before the site's
  # name: the page's own, or on an error page (rendered in the root layout by
  # `Phoenix.Endpoint.RenderErrors`, whose assigns have `:status` and `:kind`)
  # its heading. Neither: the site's name alone.
  defp page_title(%{page_title: title}) when is_binary(title), do: title

  defp page_title(%{status: status, kind: _}) when is_integer(status),
    do: FGDataCatalogWeb.ErrorHTML.title(status)

  defp page_title(_assigns), do: nil

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  slot :inner_block, required: true
  slot :header, doc: "extra content shown next to the site title"

  def app(assigns) do
    ~H"""
    <header class="site-header">
      <%!-- NOTE(Claude 2026-11-12): the bar before the title is drawn by the
           `.TitleSpark` hook below, on a canvas over `.title-bar` (see
           app.css). At rest, about every 3 s a pixel takes a wrong color,
           and the two white rules fetch it and carry it to its own band.
           A click on the title (or its bar) flashes the bar white, then
           rebuilds it pixel by pixel like sand pouring in, and sorts the
           pixels into the stacked bar. The link loads a new page, so the
           click is noted in `sessionStorage` and the new page plays it too,
           if it loads within 3 s. --%>
      <a href={~p"/"} id="site-title" class="site-title" phx-hook=".TitleSpark" phx-update="ignore"><span
        class="title-bar"
        aria-hidden="true"
      ></span>FinnGen Data Catalog</a>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".TitleSpark">
        // NOTE(Claude 2026-11-09): the timings of the rebuild, in ms
        // (gravity in pixels per second squared).
        const FLASH_MS = 70 // the bar, washed out, before it goes blank
        const BLANK_MS = 260 // when the pixels start to fall
        const SPAWN_MS = [8, 20] // between two pixels starting to fall
        const GRAVITY = 260
        const HOLD_MS = 150 // the full, unsorted bar stays a moment
        const SORT_MS = 45 // one round of the sort
        const END_MS = 60 // the finished bar stays a moment

        // NOTE(Claude 2026-11-12): the timings of the bar at rest, in ms.
        const CORRUPT_MS = [2500, 3500] // between two pixels going wrong
        const NOTICE_MS = 220 // the wrong pixel shows before the rules move
        const STEP_MS = 64 // a rule moving one row
        const GRAB_MS = 140 // the rules hold around the pixel they fetched
        const REST_MS = 200 // at least between a fetch and the next pixel

        const clamp = (n, low, high) => Math.min(high, Math.max(low, n))
        const between = ([low, high]) => low + Math.random() * (high - low)
        const pick = (list) => list[Math.floor(Math.random() * list.length)]
        const reducedMotion = () => matchMedia("(prefers-reduced-motion: reduce)").matches

        function shuffle(list) {
          for (let i = list.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1))
            ;[list[i], list[j]] = [list[j], list[i]]
          }
          return list
        }

        // NOTE(Claude 2026-11-12): the bar as it is, in pixels: the size (a
        // pixel is a CSS pixel), and how many pixels of each color (orange,
        // blue, purple) a column holds, from the bar's two boundaries
        // (`--title-bar-blue` and `--title-bar-purple` in app.css). Two rows
        // stay white, the one-pixel rules between the colors.
        function plan(bar) {
          const style = getComputedStyle(bar)
          const rect = bar.getBoundingClientRect()
          const cols = Math.max(1, Math.round(rect.width))
          const rows = Math.max(6, Math.round(rect.height))
          const share = (name, fallback) => {
            const value = parseFloat(style.getPropertyValue(name))
            return (Number.isFinite(value) ? value : fallback) / 100
          }
          const orange = clamp(Math.round(share("--title-bar-blue", 50) * rows), 1, rows - 4)
          const rule = clamp(Math.round(share("--title-bar-purple", 80) * rows), orange + 2, rows - 2)
          return { cols, rows, counts: [orange, rule - orange - 1, rows - 1 - rule] }
        }

        // The pixels of a column, in the order of the finished bar (bottom
        // first): the kinds are 0 orange, 2 blue, 4 purple, and 1 and 3 the
        // white rules between them. The rules are poured and sorted like the
        // colors (they are just not drawn), so the sort ends on the finished
        // bar, with nothing left to move into place.
        function arranged([orange, blue, purple]) {
          return [
            ...Array(orange).fill(0),
            1,
            ...Array(blue).fill(2),
            3,
            ...Array(purple).fill(4)
          ]
        }

        // NOTE(Claude-Opus-5.5 2026-11-17): a canvas over the bar, the size of
        // its plan, and a way to paint one pixel of a kind (`fill`). The
        // rules, kinds 1 and 3, are painted white in both themes (were left
        // unpainted, showing the header's background, dark in the dark
        // theme); the accents are plain values in app.css, the same in both.
        function surface(bar) {
          const { cols, rows, counts } = plan(bar)
          const root = getComputedStyle(document.documentElement)
          const colors = ["--color-accent", "#fff", "--color-blue", "#fff", "--color-purple"].map(
            (name) => (name.startsWith("--") ? root.getPropertyValue(name).trim() : name)
          )
          const dpr = window.devicePixelRatio || 1
          const canvas = document.createElement("canvas")
          canvas.width = Math.round(cols * dpr)
          canvas.height = Math.round(rows * dpr)
          const ctx = canvas.getContext("2d")
          const fill = (col, row, kind) => {
            if (!colors[kind]) return
            const x0 = Math.round(col * dpr)
            const y0 = Math.round(row * dpr)
            ctx.fillStyle = colors[kind]
            ctx.fillRect(x0, y0, Math.round((col + 1) * dpr) - x0, Math.round((row + 1) * dpr) - y0)
          }
          return { cols, rows, counts, canvas, ctx, fill }
        }

        export default {
          mounted() {
            this.el.addEventListener("click", () => {
              this.rebuild()
              sessionStorage.setItem("titleSpark", String(Date.now()))
            })
            // NOTE(Claude 2026-11-12): a zoom changes the bar's size in
            // pixels, so the bar at rest starts over on the new size.
            this.onResize = () => this.mode === "idle" && this.idle()
            window.addEventListener("resize", this.onResize)

            const clickedAt = Number(sessionStorage.getItem("titleSpark"))
            sessionStorage.removeItem("titleSpark")
            if (clickedAt && Date.now() - clickedAt < 3000) this.rebuild()
            else this.idle()
          },

          destroyed() {
            window.removeEventListener("resize", this.onResize)
            this.stop()
          },

          stop() {
            if (this.cleanup) this.cleanup()
            this.cleanup = null
            this.mode = null
          },

          // NOTE(Claude 2026-11-12): puts `canvas` over the bar,
          // hiding the bar's own gradient (`.is-drawn`) until `stop`.
          // `frame(now)` is called on every animation frame and returns
          // false when done.
          animate(bar, canvas, mode, frame) {
            let raf = null
            const loop = (now) => {
              if (frame(now) === false) return this.finish(mode)
              raf = requestAnimationFrame(loop)
            }
            this.cleanup = () => {
              cancelAnimationFrame(raf)
              canvas.remove()
              bar.classList.remove("is-drawn")
            }
            this.mode = mode
            bar.classList.add("is-drawn")
            bar.append(canvas)
            raf = requestAnimationFrame(loop)
          },

          // After a rebuild, the bar goes back to rest. The new canvas is
          // drawn before the browser paints, so nothing flickers.
          finish(mode) {
            this.stop()
            if (mode === "rebuild") this.idle()
          },

          // NOTE(Claude 2026-11-12): the bar at rest. Its columns are all
          // alike, so one column (`stack`, kinds bottom first) holds the
          // bar, and the wrong pixel (`bad`) and the one being carried
          // (`carried`) are drawn over it. A rule moves by swapping its row
          // with the next one, in every column at once: the rows it passes
          // shift by one, the way a boundary of a stacked bar moves. The
          // rules never cross, so the colors keep their order and the bar
          // is exactly as it was once both rules are back home.
          //
          // About every 3 s a pixel takes the color of another band. The
          // rules close in on it: from both sides when it is blue, between
          // them; otherwise both from its one side, the other rule right
          // behind the nearer one. One rule (the nearer one, or for a blue
          // pixel the one bordering the pixel's band) moves onto the pixel's
          // row: the row's own colors shift to where the rule was, so the
          // pixel's place gets its color back, and the wrong color, left on
          // the rule's row, rides on the white rule toward the band of that
          // color. The other rule stops next to it. The rules go back
          // home together; when the rule holding the pixel is home but its
          // band is the other rule's (the lower rule borders orange, the
          // upper one purple, both blue), it hands the pixel on to the other
          // rule, right next to it, which carries it on. Once home, the
          // carrying rule drops the pixel into its band, where it blends in.
          idle() {
            this.stop()
            if (reducedMotion()) return
            const bar = this.el.querySelector(".title-bar")
            if (!bar) return

            const { cols, rows, counts, canvas, ctx, fill } = surface(bar)
            const stack = arranged(counts)
            const at = (kind) => stack.indexOf(kind)
            const isRule = (kind) => kind === 1 || kind === 3
            const homes = { 1: at(1), 3: at(3) }

            let bad = null // { col, row, kind }
            let carried = null // { col, kind, rule (holding it), carrier (taking it home) }
            let targets = null // the row each rule is heading for, by kind
            let phase = "rest"
            let next = performance.now() + between(CORRUPT_MS)
            let corruptedAt = 0
            let dirty = true

            const draw = () => {
              ctx.clearRect(0, 0, canvas.width, canvas.height)
              stack.forEach((kind, i) => {
                for (let col = 0; col < cols; col++) fill(col, rows - 1 - i, kind)
              })
              if (bad) fill(bad.col, rows - 1 - bad.row, bad.kind)
              if (carried) fill(carried.col, rows - 1 - at(carried.rule), carried.kind)
              dirty = false
            }

            const corrupt = () => {
              const row = pick([...stack.keys()].filter((i) => !isRule(stack[i])))
              const kind = pick([0, 2, 4].filter((kind) => kind !== stack[row]))
              const col = Math.floor(Math.random() * cols)
              // NOTE(Claude 2026-11-12): the rule that moves onto the pixel's
              // row to hold it (`rule`, the other one stopping next to it),
              // and the one bordering the pixel's band (`carrier`).
              let rule
              if (row < homes[1]) rule = 1
              else if (row > homes[3]) rule = 3
              else rule = kind === 0 ? 1 : 3
              targets = rule === 1 ? { 1: row, 3: row + 1 } : { 3: row, 1: row - 1 }
              const carrier = kind === 0 ? 1 : kind === 4 ? 3 : rule
              bad = { col, row, kind, rule, carrier }
            }

            // NOTE(Claude 2026-11-12): each rule not at its target moves one
            // row toward it, unless that row is the other rule's, or the
            // wrong pixel's (only the rule fetching it may go there). Two passes,
            // so that the rule behind can follow the one ahead in the same
            // step. True once both are at their targets.
            const advance = () => {
              const moved = new Set()
              for (let pass = 0; pass < 2; pass++) {
                for (const rule of [1, 3]) {
                  const from = at(rule)
                  if (moved.has(rule) || from === targets[rule]) continue
                  const to = from + Math.sign(targets[rule] - from)
                  if ((bad && to === bad.row && rule !== bad.rule) || isRule(stack[to])) continue
                  ;[stack[from], stack[to]] = [stack[to], stack[from]]
                  moved.add(rule)
                }
              }
              return at(1) === targets[1] && at(3) === targets[3]
            }

            // The frames come at most once per step: after a hidden tab,
            // the bar goes on where it was rather than catching up.
            const frame = (now) => {
              if (now >= next) {
                dirty = true
                if (phase === "rest") {
                  corrupt()
                  corruptedAt = now
                  phase = "notice"
                  next = now + NOTICE_MS
                } else if (phase === "notice" || phase === "fetch") {
                  phase = advance() ? "grab" : "fetch"
                  next = now + (phase === "grab" ? GRAB_MS : STEP_MS)
                } else if (phase === "grab") {
                  const { col, kind, rule, carrier } = bad
                  carried = { col, kind, rule, carrier }
                  bad = null
                  targets = homes
                  phase = "return"
                  next = now + STEP_MS
                } else if (phase === "return") {
                  const done = advance()
                  if (carried && at(carried.rule) === homes[carried.rule]) {
                    if (carried.rule === carried.carrier) carried = null
                    else carried.rule = carried.carrier
                  }
                  if (done && !carried) {
                    phase = "rest"
                    next = Math.max(corruptedAt + between(CORRUPT_MS), now + REST_MS)
                  } else {
                    next = now + STEP_MS
                  }
                }
              }
              if (dirty) draw()
            }

            draw()
            this.animate(bar, canvas, "idle", frame)
          },

          // NOTE(Claude 2026-11-12): flash, pour the pixels in, sort them, on
          // a canvas of their own; the bar at rest takes over again after.
          rebuild() {
            this.stop()
            if (reducedMotion()) return
            const bar = this.el.querySelector(".title-bar")
            if (!bar) return

            const { cols, rows, counts, canvas, ctx, fill } = surface(bar)
            const finished = Array(cols).fill(arranged(counts))

            // Each column pours its own pixels, in random order.
            const queues = Array.from({ length: cols }, () => shuffle(arranged(counts)))
            const cells = Array.from({ length: cols }, () => Array(rows).fill(null))
            const height = Array(cols).fill(0)
            const falling = []
            let spawned = 0
            let nextSpawn = 0
            let phase = "flash"
            let phaseStart = performance.now()
            let last = phaseStart
            let round = 0
            let quiet = 0
            let nextRound = 0

            // `view` is the columns to show, bottom first; `washed` (0 to 1)
            // whitens it, like a flash.
            const draw = (view, washed = 0) => {
              ctx.clearRect(0, 0, canvas.width, canvas.height)
              view.forEach((column, col) =>
                column.forEach((color, i) => {
                  if (color !== null) fill(col, rows - 1 - i, color)
                })
              )
              for (const pixel of falling) {
                const row = Math.floor(pixel.y)
                if (row >= 0 && row < rows) fill(pixel.col, row, pixel.color)
              }
              if (washed > 0) {
                ctx.globalAlpha = washed
                ctx.fillStyle = "#fff"
                ctx.fillRect(0, 0, canvas.width, canvas.height)
                ctx.globalAlpha = 1
              }
            }

            const frame = (now) => {
              const dt = clamp((now - last) / 1000, 0, 0.05)
              last = now

              if (phase === "flash") {
                // The bar washes out, then goes blank.
                if (now - phaseStart < FLASH_MS) {
                  draw(finished, 0.7)
                } else if (now - phaseStart < BLANK_MS) {
                  draw([])
                } else {
                  phase = "pour"
                  nextSpawn = now
                }
              }

              if (phase === "pour") {
                // Pixels start to fall at random columns and pile up.
                while (spawned < cols * rows && now >= nextSpawn) {
                  const open = []
                  queues.forEach((queue, col) => queue.length > 0 && open.push(col))
                  const col = pick(open)
                  falling.push({ col, color: queues[col].shift(), y: -1, v: 0 })
                  spawned++
                  nextSpawn += between(SPAWN_MS)
                }

                for (let i = falling.length - 1; i >= 0; i--) {
                  const pixel = falling[i]
                  pixel.v += GRAVITY * dt
                  pixel.y += pixel.v * dt
                  if (pixel.y >= rows - 1 - height[pixel.col]) {
                    cells[pixel.col][height[pixel.col]++] = pixel.color
                    falling.splice(i, 1)
                  }
                }

                draw(cells)
                if (spawned === cols * rows && falling.length === 0) {
                  phase = "hold"
                  phaseStart = now
                }
              } else if (phase === "hold") {
                draw(cells)
                if (now - phaseStart >= HOLD_MS) {
                  phase = "sort"
                  nextRound = now
                }
              } else if (phase === "sort") {
                // Odd-even transposition sort: each round compares the pairs
                // of neighbors at even, then odd places, in every column,
                // and swaps those in the wrong order (the kinds, in numeric
                // order from the bottom). Done when two rounds in a row swap
                // nothing: the bar is then as it is at rest.
                if (now >= nextRound) {
                  let swapped = false
                  for (const column of cells) {
                    for (let i = round % 2; i + 1 < rows; i += 2) {
                      if (column[i] > column[i + 1]) {
                        ;[column[i], column[i + 1]] = [column[i + 1], column[i]]
                        swapped = true
                      }
                    }
                  }
                  quiet = swapped ? 0 : quiet + 1
                  round++
                  nextRound = now + SORT_MS
                }
                draw(cells)
                if (quiet >= 2) {
                  phase = "end"
                  phaseStart = now
                }
              } else if (phase === "end") {
                draw(cells)
                if (now - phaseStart >= END_MS) return false
              }
            }

            draw(finished, 0.7)
            this.animate(bar, canvas, "rebuild", frame)
          }
        }
      </script>
      {render_slot(@header)}
      <%!-- NOTE(Claude 2026-11-06): who is signed in, or a way to sign in. --%>
      <span id="account" class="site-account">
        <%= if @current_scope && @current_scope.user do %>
          <span id="account-email">{@current_scope.user.email}</span>
          <.link id="sign-out" href={~p"/auth/sign-out"} method="delete">Sign out</.link>
        <% else %>
          <.link id="sign-in" href={sign_in_path()}>Sign in</.link>
        <% end %>
      </span>
      <.theme_switch />
    </header>

    <main class="site-main">
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  The theme switch: System (the default), Light and Dark, icon buttons in a
  group, at the right end of the header.
  """
  # NOTE(Claude Opus 5.5 2026-11-17): the clicks are handled, and the choice
  # saved and applied, by the inline script in root.html.heex, which also sets
  # `aria-pressed` on the chosen button. `phx-update="ignore"`, so that
  # LiveView's patches keep that attribute.
  def theme_switch(assigns) do
    assigns =
      assign(assigns, :choices, [
        {"system", "hero-computer-desktop-mini", "System theme"},
        {"light", "hero-sun-mini", "Light theme"},
        {"dark", "hero-moon-mini", "Dark theme"}
      ])

    ~H"""
    <div id="theme-switch" class="theme-switch" role="group" aria-label="Theme" phx-update="ignore">
      <button
        :for={{choice, icon, label} <- @choices}
        id={"theme-#{choice}"}
        type="button"
        data-theme-choice={choice}
        aria-label={label}
        title={label}
      >
        <.icon name={icon} />
      </button>
    </div>
    """
  end

  # NOTE(Claude 2026-11-06): in development, a page offering made-up users as
  # well as Google (see `FGDataCatalogWeb.DevAuthController`).
  if Application.compile_env(:fg_data_catalog, :dev_routes) do
    defp sign_in_path, do: "/dev/sign-in"
  else
    defp sign_in_path, do: ~p"/auth/google"
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="We can't find the internet"
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect <.icon name="hero-arrow-path" class="icon-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect <.icon name="hero-arrow-path" class="icon-spin" />
      </.flash>
    </div>
    """
  end
end
