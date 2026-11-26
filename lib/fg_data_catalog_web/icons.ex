defmodule FGDataCatalogWeb.Icons do
  @moduledoc """
  The SVG of each [Heroicon](https://heroicons.com) the app uses, read at
  compile time from `deps/heroicons` and rendered inline by
  `FGDataCatalogWeb.CoreComponents.icon/1`.

  Only the icons listed in `@names` are embedded. To use another icon, add its
  name here (with the `hero-` prefix and the `-solid`, `-mini` or `-micro`
  suffix, as in `<.icon name="...">`).

  NOTE(Claude 2026-11-09): icons drawn for the app, in the Heroicons outline
  style, are `app-*` names read from `priv/icons` (see `@app_names`).
  """

  # NOTE(Claude 2026-11-06): replaces the Tailwind plugin that turned each
  # `hero-*` class into a CSS mask; the app no longer uses Tailwind.

  @names ~w(
    hero-archive-box
    hero-arrow-path
    hero-arrow-uturn-left
    hero-check
    hero-check-circle
    hero-clock
    hero-computer-desktop-mini
    hero-ellipsis-horizontal
    hero-exclamation-circle
    hero-eye-slash
    hero-information-circle
    hero-magnifying-glass
    hero-moon-mini
    hero-pencil-square
    hero-sun-mini
    hero-trash
    hero-x-mark
  )

  # NOTE(Claude 2026-11-09): the app's own icons, each `priv/icons/<name>.svg`
  # for `app-<name>`.
  @app_names ~w(
    app-check-circle-out
    app-document-duplicate-plus
    app-forward-overlap
  )

  @root Path.expand("../../deps/heroicons/optimized", __DIR__)
  @app_root Path.expand("../../priv/icons", __DIR__)

  @paths Enum.map(@app_names, fn "app-" <> rest = name ->
           {name, Path.join(@app_root, rest <> ".svg")}
         end) ++
           Enum.map(@names, fn "hero-" <> rest = name ->
             {dir, file} =
               cond do
                 String.ends_with?(rest, "-solid") ->
                   {"24/solid", String.replace_suffix(rest, "-solid", "")}

                 String.ends_with?(rest, "-mini") ->
                   {"20/solid", String.replace_suffix(rest, "-mini", "")}

                 String.ends_with?(rest, "-micro") ->
                   {"16/solid", String.replace_suffix(rest, "-micro", "")}

                 true ->
                   {"24/outline", rest}
               end

             {name, Path.join([@root, dir, file <> ".svg"])}
           end)

  @svgs Map.new(@paths, fn {name, path} ->
          @external_resource path

          # NOTE(Claude 2026-11-06): the root `<svg ...>` tag is rebuilt at render
          # time (with the caller's class), so only its viewBox and the
          # attributes that draw it (fill, stroke) are kept here.
          svg = File.read!(path)
          [_, attrs, body] = Regex.run(~r/<svg([^>]*)>(.*)<\/svg>/s, svg)

          kept =
            ~r/\s(viewBox|fill|stroke|stroke-width)="([^"]*)"/
            |> Regex.scan(attrs)
            |> Enum.map(fn [_, key, value] -> {String.to_atom(key), value} end)

          {name, {kept, String.trim(body)}}
        end)

  @doc "Whether `name` is one of the embedded icons."
  def known?(name), do: Map.has_key?(@svgs, name)

  @doc """
  Returns the root `<svg>` attributes (a keyword list) and the inner markup of
  icon `name`. Raises for an icon that is not embedded.
  """
  def fetch!(name) do
    case Map.fetch(@svgs, name) do
      {:ok, svg} ->
        svg

      :error ->
        raise ArgumentError,
              "unknown icon #{inspect(name)}: add it to the list in FGDataCatalogWeb.Icons"
    end
  end
end
