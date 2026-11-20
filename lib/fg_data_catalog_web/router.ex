defmodule FGDataCatalogWeb.Router do
  use FGDataCatalogWeb, :router

  import FGDataCatalogWeb.UserAuth, only: [fetch_current_scope: 2]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FGDataCatalogWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    # NOTE(Claude 2026-11-06): the signed-in user, if any (see `UserAuth`).
    plug :fetch_current_scope
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", FGDataCatalogWeb do
    pipe_through :browser

    # NOTE(Claude 2026-11-06): every page is open to visitors, who see the
    # Live versions only; each LiveView decides what the signed-in user's
    # scope may see or do.
    live_session :default, on_mount: [{FGDataCatalogWeb.UserAuth, :mount_current_scope}] do
      live "/", DatasetLive.Index, :index
      # NOTE(Claude 2026-11-04): the add and edit forms, each on a page of its own.
      live "/datasets/new", DatasetLive.Form, :new
      live "/versions/:id/edit", DatasetLive.Form, :edit
      # NOTE(Claude 2026-11-06): a new version of an existing dataset.
      live "/datasets/:id/versions/new", DatasetLive.Form, :new_version
      # NOTE(Claude 2026-11-16): the archived versions, for editors.
      live "/archive", DatasetLive.Archive, :index
      # NOTE(Claude 2026-11-16): every change made to the catalog, for editors.
      live "/changelog", ChangelogLive, :index
    end

    # NOTE(Claude 2026-11-06): sign-in with Google, and sign-out.
    get "/auth/google", AuthController, :request
    get "/auth/google/callback", AuthController, :callback
    delete "/auth/sign-out", AuthController, :delete
  end

  # NOTE(Claude 2026-11-06): sign-in without Google, in development only.
  if Application.compile_env(:fg_data_catalog, :dev_routes) do
    scope "/dev", FGDataCatalogWeb do
      pipe_through :browser

      get "/sign-in", DevAuthController, :new
      post "/sign-in", DevAuthController, :create
      # NOTE(Claude Opus 5.5 2026-11-18): a preview of the error pages.
      get "/errors/:status", DevErrorController, :show
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", FGDataCatalogWeb do
  #   pipe_through :api
  # end
end
