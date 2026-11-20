defmodule FGDataCatalog.Accounts.Google do
  @moduledoc """
  Sign-in with Google (OpenID Connect, authorization code flow).

  1. `authorize_url/3` sends the browser to Google, with a random `state` and
     `nonce` the caller keeps in the session.
  2. Google sends the browser back with a `code`; `fetch_claims/3` trades it
     for an ID token at Google's token endpoint and checks its claims.

  Configured under `config :fg_data_catalog, FGDataCatalog.Accounts.Google`:
  `:client_id`, `:client_secret` (the OAuth client of the environment),
  `:hosted_domain` (the Google Workspace domain whose accounts may sign in)
  and `:req_options` (for tests).
  """

  @authorize_url "https://accounts.google.com/o/oauth2/v2/auth"
  @token_url "https://oauth2.googleapis.com/token"
  @issuers ["https://accounts.google.com", "accounts.google.com"]

  @doc "Whether the OAuth client and the hosted domain are configured."
  # NOTE(Claude 2026-11-06): without a hosted domain, `check_claims/2` would
  # let in personal accounts (no `hd` claim), so sign-in is refused.
  def configured? do
    Enum.all?([:client_id, :client_secret, :hosted_domain], &(config(&1) not in [nil, ""]))
  end

  @doc "A random value for the `state` or `nonce` of a sign-in."
  def random_token, do: Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)

  @doc "The Google page that asks the user to sign in."
  def authorize_url(redirect_uri, state, nonce) do
    query =
      URI.encode_query(%{
        client_id: config(:client_id),
        redirect_uri: redirect_uri,
        response_type: "code",
        scope: "openid email",
        state: state,
        nonce: nonce,
        # NOTE(Claude 2026-11-06): only a hint for Google's account chooser;
        # the `hd` claim is what is checked, in `check_claims/2`.
        hd: config(:hosted_domain),
        prompt: "select_account"
      })

    @authorize_url <> "?" <> query
  end

  @doc """
  Trades the `code` Google sent back for the user's claims: `{:ok, %{sub:,
  email:, name:}}`, or `{:error, reason}` if the code is refused or the
  account may not sign in. `redirect_uri` must be the one given to
  `authorize_url/3`, `nonce` the one stored with it.
  """
  def fetch_claims(code, redirect_uri, nonce) when is_binary(code) and is_binary(nonce) do
    form = [
      code: code,
      client_id: config(:client_id),
      client_secret: config(:client_secret),
      redirect_uri: redirect_uri,
      grant_type: "authorization_code"
    ]

    case Req.post(@token_url, [form: form, retry: false] ++ (config(:req_options) || [])) do
      {:ok, %Req.Response{status: 200, body: %{"id_token" => id_token}}} ->
        with {:ok, claims} <- decode_id_token(id_token) do
          check_claims(claims, nonce)
        end

      {:ok, %Req.Response{}} ->
        {:error, :token_refused}

      {:error, _exception} ->
        {:error, :token_unreachable}
    end
  end

  # NOTE(Claude 2026-11-06): the ID token's signature is not checked. This is
  # allowed by OpenID Connect Core 1.0, section 3.1.3.7, when the token comes
  # straight from the token endpoint over TLS (Req checks Google's
  # certificate), as here, in exchange for the client secret. Never decode an
  # ID token received any other way (from the browser, say) like this.
  defp decode_id_token(id_token) do
    with [_header, payload, _signature] <- String.split(id_token, "."),
         {:ok, json} <- Base.url_decode64(payload, padding: false),
         {:ok, %{} = claims} <- Jason.decode(json) do
      {:ok, claims}
    else
      _ -> {:error, :invalid_id_token}
    end
  end

  # NOTE(Claude 2026-11-06): `hd` is set by Google only for Workspace accounts,
  # to their domain: an email ending in "@finngen.fi" alone proves nothing.
  defp check_claims(claims, nonce) do
    cond do
      claims["iss"] not in @issuers ->
        {:error, :wrong_issuer}

      claims["aud"] != config(:client_id) ->
        {:error, :wrong_audience}

      not (is_integer(claims["exp"]) and claims["exp"] > System.os_time(:second)) ->
        {:error, :expired}

      not (is_binary(claims["nonce"]) and Plug.Crypto.secure_compare(claims["nonce"], nonce)) ->
        {:error, :wrong_nonce}

      claims["email_verified"] != true ->
        {:error, :email_not_verified}

      claims["hd"] != config(:hosted_domain) ->
        {:error, :wrong_domain}

      not is_binary(claims["sub"]) or not is_binary(claims["email"]) ->
        {:error, :invalid_id_token}

      true ->
        {:ok, %{sub: claims["sub"], email: claims["email"], name: claims["name"]}}
    end
  end

  defp config(key) do
    :fg_data_catalog |> Application.get_env(__MODULE__, []) |> Keyword.get(key)
  end
end
