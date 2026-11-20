defmodule FGDataCatalogWeb.CoreComponents do
  @moduledoc """
  Provides core UI components: flash notices, buttons, form inputs and icons.

  NOTE(Claude 2026-11-06): the app does not use Tailwind or daisyUI. The
  components use plain semantic classes (`field`, `field-label`, `input`,
  `btn`, `flash`…), styled in `assets/css/app.css`.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://phoenix-live-view.hexdocs.pm/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash
        id="welcome-back"
        kind={:info}
        phx-mounted={show("#welcome-back") |> JS.remove_attribute("hidden")}
        hidden
      >
        Welcome Back!
      </.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class={["toast", "flash", "flash-#{@kind}"]}
      {@rest}
    >
      <%!-- NOTE(Claude 2026-11-06): plain semantic classes, styled in app.css
           (the Tailwind and daisyUI classes are gone). --%>
      <div class="flash-body">
        <.icon :if={@kind == :info} name="hero-information-circle" class="flash-icon" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="flash-icon" />
        <div class="flash-text">
          <p :if={@title} class="flash-title">{@title}</p>
          <p>{msg}</p>
        </div>
        <button type="button" class="flash-close" aria-label="Close">
          <.icon name="hero-x-mark" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :any
  attr :variant, :string, values: ~w(primary)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    # NOTE(Claude 2026-11-06): styled in app.css.
    variants = %{"primary" => "btn-primary", nil => "btn-secondary"}

    assigns =
      assign_new(assigns, :class, fn ->
        ["btn", Map.fetch!(variants, assigns[:variant])]
      end)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" />
  <.input name="my-input" errors={["oh no!"]} />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://phoenix-html.hexdocs.pm/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  # NOTE(Claude 2026-11-12): for the edit form, which saves each change.
  attr :saved, :boolean, default: false, doc: "marks the field with a tick, as saved"

  # NOTE(Claude Opus 5.5 2026-11-17): a visible mark after the label, and
  # `aria-required` for screen readers. Not the native `required` attribute,
  # which would let the browser block a submit before the server shows its
  # own errors.
  attr :mark_required, :boolean,
    default: false,
    doc: "marks the field as required, after its label (see `required_mark/1`)"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  # NOTE(Claude 2026-11-06): an input with errors is marked invalid and
  # described by them, for screen readers (see `errors/1`).
  def input(%{type: type, errors: errors, rest: rest} = assigns)
      when type != "hidden" and errors != [] and not is_map_key(rest, :"aria-describedby") do
    rest = Map.merge(rest, %{"aria-invalid": "true", "aria-describedby": "#{assigns.id}-errors"})
    input(%{assigns | rest: rest})
  end

  def input(%{mark_required: true, rest: rest} = assigns)
      when not is_map_key(rest, :"aria-required") do
    input(%{assigns | rest: Map.put(rest, :"aria-required", "true")})
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class={["field", @errors != [] && "has-error"]}>
      <.saved_tick :if={@saved} id={@id} />
      <label for={@id}>
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <span class="field-label checkbox-label">
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class={@class || "checkbox"}
            {@rest}
          />{@label}
        </span>
      </label>
      <.errors id={@id} errors={@errors} />
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class={["field", @errors != [] && "has-error"]}>
      <.saved_tick :if={@saved} id={@id} />
      <label for={@id}>
        <span :if={@label} class="field-label">{@label}<.required_mark :if={@mark_required} /></span>
        <select
          id={@id}
          name={@name}
          class={[@class || "select", @errors != [] && @error_class]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.errors id={@id} errors={@errors} />
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class={["field", @errors != [] && "has-error"]}>
      <.saved_tick :if={@saved} id={@id} />
      <label for={@id}>
        <span :if={@label} class="field-label">{@label}<.required_mark :if={@mark_required} /></span>
        <textarea
          id={@id}
          name={@name}
          class={[@class || "textarea", @errors != [] && @error_class]}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.errors id={@id} errors={@errors} />
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class={["field", @errors != [] && "has-error"]}>
      <.saved_tick :if={@saved} id={@id} />
      <label for={@id}>
        <span :if={@label} class="field-label">{@label}<.required_mark :if={@mark_required} /></span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[@class || "input", @errors != [] && @error_class]}
          {@rest}
        />
      </label>
      <.errors id={@id} errors={@errors} />
    </div>
    """
  end

  @doc """
  Renders the mark of a required field, after its label: an asterisk, hidden
  from screen readers, which are told by the input's `aria-required` instead.
  See `required_note/1` for its legend.
  """
  # NOTE(Claude Opus 5.5 2026-11-17): required fields are marked, optional
  # ones are not labelled "optional".
  def required_mark(assigns) do
    ~H"""
    <span class="required-mark" title="Required" aria-hidden="true">*</span>
    """
  end

  @doc """
  Renders the legend of the required marks (see `required_mark/1`), at the top
  of a form.
  """
  attr :id, :string, required: true

  def required_note(assigns) do
    ~H"""
    <p id={@id} class="required-note">
      Fields marked <span class="required-mark" aria-hidden="true">*</span>
      <span class="visually-hidden">with an asterisk</span> are required.
    </p>
    """
  end

  @doc """
  Renders the tick marking a field (whose input has id `id`) as saved, in the
  margin left of its value (see `.saved-tick`). Hidden from screen readers, which
  hear the form's status instead.
  """
  # NOTE(Claude 2026-11-12): placed first in the field (CSS moves it down to
  # the input), or in a radio button's label.
  attr :id, :string, required: true

  def saved_tick(assigns) do
    ~H"""
    <span id={"#{@id}-saved"} class="saved-tick" title="Saved" aria-hidden="true">
      <.icon name="hero-check" />
    </span>
    """
  end

  # NOTE(Claude 2026-11-06): an input's errors, in one element its input
  # points to with `aria-describedby`.
  attr :id, :any, required: true
  attr :errors, :list, required: true

  defp errors(assigns) do
    ~H"""
    <div :if={@errors != []} id={"#{@id}-errors"} class="field-errors">
      <p :for={msg <- @errors} class="field-error">
        <.icon name="hero-exclamation-circle" />
        {msg}
      </p>
    </div>
    """
  end

  # NOTE(Claude 2026-11-06): the generated header, table and list components
  # were never used, and only styled by Tailwind: removed.

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  NOTE(Claude 2026-11-06): icons are read from `deps/heroicons` at compile time
  and rendered as inline SVG; `FGDataCatalogWeb.Icons` lists the icons
  available. An icon takes the current text color and, by default, the size of
  the text (`.icon` in app.css).

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="icon-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: nil

  # NOTE(Claude 2026-11-09): `app-*` icons too, drawn for the app.
  def icon(%{name: "hero-" <> _} = assigns), do: inline_icon(assigns)
  def icon(%{name: "app-" <> _} = assigns), do: inline_icon(assigns)

  defp inline_icon(assigns) do
    {svg_attrs, body} = FGDataCatalogWeb.Icons.fetch!(assigns.name)
    assigns = assign(assigns, svg_attrs: svg_attrs, body: Phoenix.HTML.raw(body))

    ~H"""
    <svg class={["icon", @name, @class]} {@svg_attrs} aria-hidden="true" focusable="false">
      {@body}
    </svg>
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 200,
      # NOTE(Claude 2026-11-06): classes defined in app.css.
      transition: {"fade-transition", "fade-out", "fade-in"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition: {"fade-transition", "fade-in", "fade-out"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # You can make use of gettext to translate error messages by
    # uncommenting and adjusting the following code:

    # if count = opts[:count] do
    #   Gettext.dngettext(FGDataCatalogWeb.Gettext, "errors", msg, msg, count, opts)
    # else
    #   Gettext.dgettext(FGDataCatalogWeb.Gettext, "errors", msg, opts)
    # end

    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
