defmodule FGDataCatalog.Catalog.DocLink do
  @moduledoc """
  A labelled documentation entry: either a link (`kind: :link`) or a text
  pasted in directly (`kind: :text`), e.g. the contents of a README.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :kind, Ecto.Enum, values: [:link, :text], default: :link
    field :label, :string
    field :url, :string
    field :text, :string
  end

  def changeset(link, attrs) do
    link
    |> cast(attrs, [:kind, :label, :url, :text])
    |> validate_required([:kind, :label])
    |> validate_kind()
  end

  # NOTE(Claude 2026-11-04): only the field matching the kind is required and
  # kept, so switching kind in the form does not leave stale content behind.
  defp validate_kind(changeset) do
    case get_field(changeset, :kind) do
      :text ->
        changeset
        |> validate_required([:text])
        |> put_change(:url, nil)

      _link ->
        changeset
        |> validate_required([:url])
        |> validate_format(:url, ~r{\Ahttps?://\S+\z}, message: "must be an http(s) URL")
        |> put_change(:text, nil)
    end
  end
end
