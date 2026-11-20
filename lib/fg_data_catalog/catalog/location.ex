defmodule FGDataCatalog.Catalog.Location do
  @moduledoc "A web link or storage path for a dataset version, with an optional label."

  use Ecto.Schema
  import Ecto.Changeset

  @label_max_length 40

  @primary_key false
  embedded_schema do
    field :value, :string
    field :label, :string
  end

  def label_max_length, do: @label_max_length

  def changeset(location, attrs) do
    location
    |> cast(attrs, [:value, :label])
    |> update_change(:value, &(&1 && String.trim(&1)))
    |> update_change(:label, &(&1 && String.trim(&1)))
    |> validate_required([:value])
    |> validate_length(:label, max: @label_max_length)
    |> validate_change(:value, fn :value, value ->
      if location_kind(value),
        do: [],
        else: [value: "must be a web link (https://…), a Unix path (/…) or a gs:// path"]
    end)
    |> validate_label()
  end

  defp validate_label(changeset) do
    if get_field(changeset, :label) && !get_field(changeset, :value),
      do: add_error(changeset, :label, "needs a location to name"),
      else: changeset
  end

  @doc """
  What a location is: `:link` for a web link (`http://` or `https://`, with a
  host, no spaces), `:path` for a Unix path (starting with `/` or `~`, on one
  line) or a Google Cloud Storage path (`gs://` and a bucket name, then
  optionally `/` and an object path, on one line), `nil` for anything else.
  """
  def location_kind(location) when is_binary(location) do
    cond do
      String.match?(location, ~r/^https?:/i) -> if web_link?(location), do: :link
      String.starts_with?(location, "gs://") -> bucket_path(location)
      String.match?(location, ~r/^~?\//) or location == "~" -> unix_path(location)
      true -> nil
    end
  end

  def location_kind(_location), do: nil

  defp web_link?(location) do
    case URI.new(location) do
      {:ok, %URI{scheme: scheme, host: host}} when scheme in ["http", "https"] ->
        host not in [nil, ""] and not String.match?(location, ~r/\s/)

      _ ->
        false
    end
  end

  # NOTE(Claude Opus 5.5 2026-11-17): a path may contain spaces, but not line
  # breaks or other control characters, nor a link (`://`): one or the other,
  # not both.
  defp unix_path(location) do
    if String.match?(location, ~r/[[:cntrl:]]|:\/\//u), do: nil, else: :path
  end

  # NOTE(Claude Opus 5.5 2026-11-19): a bucket name is 3 or more lowercase
  # letters, digits, dots, dashes or underscores, starting and ending with a
  # letter or a digit; the object path, like a Unix path, may contain spaces
  # but no line breaks, nor another link.
  defp bucket_path("gs://" <> rest) do
    [bucket | object] = String.split(rest, "/", parts: 2)

    if String.match?(bucket, ~r/^[a-z0-9][a-z0-9._-]+[a-z0-9]$/) and
         not String.match?(Enum.join(object), ~r/[[:cntrl:]]|:\/\//u),
       do: :path
  end
end
