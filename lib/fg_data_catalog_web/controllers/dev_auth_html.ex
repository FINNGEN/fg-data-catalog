defmodule FGDataCatalogWeb.DevAuthHTML do
  @moduledoc false
  use FGDataCatalogWeb, :html

  # NOTE(Claude 2026-11-16): the development sign-in page (see
  # `FGDataCatalogWeb.DevAuthController`): two editors.
  def new(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="dev-sign-in" class="dev-sign-in">
        <h1>Sign in (development)</h1>
        <p>Sign in as a made-up user, without Google:</p>
        <ul>
          <li :for={{role, user} <- Enum.sort(@users)}>
            <.link
              id={"dev-sign-in-#{role}"}
              href={"/dev/sign-in?" <> URI.encode_query(role: role)}
              method="post"
            >
              As {role} ({user.email})
            </.link>
          </li>
        </ul>
        <p>
          Or <.link id="google-sign-in" href={~p"/auth/google"}>sign in with Google</.link>
          (needs <code>GOOGLE_CLIENT_ID</code>
          and <code>GOOGLE_CLIENT_SECRET</code>).
        </p>
      </section>
    </Layouts.app>
    """
  end
end
