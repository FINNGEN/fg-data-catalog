defmodule FGDataCatalogWeb.AuthControllerTest do
  # NOTE(Claude 2026-11-06): sign-in with Google, Google's token endpoint being
  # stubbed with `Req.Test` (see `config/test.exs`). Each check of the callback
  # has a test of its own: the state, and each claim of the ID token. Not
  # async: signing in writes to the database.
  use FGDataCatalogWeb.ConnCase, async: false

  alias FGDataCatalog.Accounts
  alias FGDataCatalog.Accounts.{Google, Scope, User, UserToken}
  alias FGDataCatalog.Repo

  @moduletag role: :visitor

  defp redirect_uri, do: FGDataCatalogWeb.Endpoint.url() <> "/auth/google/callback"

  # Starts a sign-in: returns the conn (with the session cookie) and the
  # `state` and `nonce` sent to Google.
  defp start_sign_in do
    conn = get(build_conn(), ~p"/auth/google")
    %URI{query: query} = URI.parse(redirected_to(conn, 302))
    params = URI.decode_query(query)
    {conn, params}
  end

  defp id_token(claims) do
    encode = &Base.url_encode64(Jason.encode!(&1), padding: false)
    encode.(%{"alg" => "RS256"}) <> "." <> encode.(claims) <> ".signature"
  end

  defp valid_claims(nonce, overrides \\ %{}) do
    Map.merge(
      %{
        "iss" => "https://accounts.google.com",
        "aud" => "test-client-id",
        "exp" => System.os_time(:second) + 3600,
        "nonce" => nonce,
        "sub" => "google-123",
        "email" => "Jane.Doe@finngen.fi",
        "email_verified" => true,
        "hd" => "finngen.fi",
        "name" => "Jane Doe"
      },
      overrides
    )
  end

  # Google's token endpoint answers with an ID token of `claims`, after
  # checking what the app sent.
  defp stub_google(claims) do
    Req.Test.stub(Google, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      form = URI.decode_query(body)
      assert form["code"] == "the-code"
      assert form["client_id"] == "test-client-id"
      assert form["client_secret"] == "test-client-secret"
      assert form["redirect_uri"] == redirect_uri()
      assert form["grant_type"] == "authorization_code"
      Req.Test.json(conn, %{"id_token" => id_token(claims)})
    end)
  end

  defp callback(conn, params) do
    conn |> recycle() |> get(~p"/auth/google/callback", params)
  end

  defp signed_in?(conn), do: get_session(conn, "user_token") != nil

  test "sends the browser to Google with a state and a nonce" do
    {conn, params} = start_sign_in()

    assert redirected_to(conn, 302) =~ "https://accounts.google.com/o/oauth2/v2/auth?"
    assert params["client_id"] == "test-client-id"
    assert params["redirect_uri"] == redirect_uri()
    assert params["response_type"] == "code"
    assert params["scope"] == "openid email"
    assert params["hd"] == "finngen.fi"
    assert %{"state" => state, "nonce" => nonce} = get_session(conn, "google_auth")
    assert params["state"] == state
    assert params["nonce"] == nonce
    assert state != nonce
  end

  test "signs in a @finngen.fi account, creating its user" do
    {conn, %{"state" => state, "nonce" => nonce}} = start_sign_in()
    stub_google(valid_claims(nonce))

    conn = callback(conn, %{"state" => state, "code" => "the-code"})

    assert redirected_to(conn) == ~p"/"
    assert signed_in?(conn)
    assert get_session(conn, "google_auth") == nil

    assert %User{name: "Jane Doe", google_sub: "google-123"} =
             Accounts.get_user_by_email("jane.doe@finngen.fi")

    # The header shows who is signed in.
    conn = conn |> recycle() |> get(~p"/")
    assert html_response(conn, 200) =~ "jane.doe@finngen.fi"
  end

  test "a second sign-in updates the user's email and name" do
    {:ok, _} = Accounts.upsert_google_user(%{sub: "google-123", email: "old@finngen.fi"})
    {conn, %{"state" => state, "nonce" => nonce}} = start_sign_in()
    stub_google(valid_claims(nonce))

    callback(conn, %{"state" => state, "code" => "the-code"})

    assert [%User{email: "jane.doe@finngen.fi", name: "Jane Doe"}] = Repo.all(User)
  end

  test "the session is renewed: what was in it before signing in is dropped" do
    conn =
      build_conn() |> Plug.Test.init_test_session(%{"planted" => "x"}) |> get(~p"/auth/google")

    %URI{query: query} = URI.parse(redirected_to(conn, 302))
    %{"state" => state, "nonce" => nonce} = URI.decode_query(query)
    stub_google(valid_claims(nonce))

    conn = callback(conn, %{"state" => state, "code" => "the-code"})

    assert signed_in?(conn)
    assert get_session(conn, "planted") == nil
  end

  describe "refuses" do
    test "a wrong state, without asking Google" do
      {conn, %{"nonce" => _nonce}} = start_sign_in()
      Req.Test.stub(Google, fn _conn -> flunk("Google must not be called") end)

      conn = callback(conn, %{"state" => "forged", "code" => "the-code"})

      refute signed_in?(conn)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "failed"
    end

    test "a callback without a sign-in started in this browser" do
      Req.Test.stub(Google, fn _conn -> flunk("Google must not be called") end)
      conn = get(build_conn(), ~p"/auth/google/callback", %{"state" => "s", "code" => "c"})
      refute signed_in?(conn)
    end

    for {name, overrides} <- [
          {"another issuer", %{"iss" => "https://evil.example"}},
          {"another audience", %{"aud" => "someone-elses-client"}},
          {"an expired token", %{"exp" => 1_000}},
          {"another nonce", %{"nonce" => "replayed"}},
          {"an unverified email", %{"email_verified" => false}},
          {"another Workspace domain", %{"hd" => "example.org"}},
          {"a personal Google account (no hd)", %{"hd" => nil}}
        ] do
      @overrides overrides
      test name do
        {conn, %{"state" => state, "nonce" => nonce}} = start_sign_in()
        stub_google(valid_claims(nonce, @overrides))

        conn = callback(conn, %{"state" => state, "code" => "the-code"})

        refute signed_in?(conn)
        assert redirected_to(conn) == ~p"/"
        assert Repo.all(User) == []
      end
    end

    test "a personal account, telling to use the @finngen.fi one" do
      {conn, %{"state" => state, "nonce" => nonce}} = start_sign_in()
      stub_google(valid_claims(nonce, %{"hd" => nil, "email" => "jane@gmail.com"}))

      conn = callback(conn, %{"state" => state, "code" => "the-code"})
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "@finngen.fi"
    end

    test "a code Google does not accept" do
      {conn, %{"state" => state}} = start_sign_in()

      Req.Test.stub(Google, fn conn ->
        conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{"error" => "invalid_grant"})
      end)

      conn = callback(conn, %{"state" => state, "code" => "the-code"})
      refute signed_in?(conn)
    end

    test "a sign-in cancelled at Google" do
      {conn, %{"state" => state}} = start_sign_in()
      conn = callback(conn, %{"state" => state, "error" => "access_denied"})

      refute signed_in?(conn)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Sign-in cancelled."
    end
  end

  describe "signing out" do
    test "ends the session and its token" do
      conn = log_in(build_conn(), :editor)
      token = get_session(conn, "user_token")
      assert Accounts.get_user_by_session_token(token)

      conn = delete(conn, ~p"/auth/sign-out")

      assert redirected_to(conn) == ~p"/"
      refute signed_in?(conn)
      assert Accounts.get_user_by_session_token(token) == nil
    end
  end

  describe "sessions" do
    test "expire after 60 days" do
      user = user_fixture(:editor)
      token = Accounts.generate_user_session_token(user)
      old = DateTime.add(DateTime.utc_now(:second), -61, :day)
      Repo.update_all(UserToken, set: [inserted_at: old])

      assert Accounts.get_user_by_session_token(token) == nil
    end

    test "an unknown token signs nobody in" do
      assert Accounts.get_user_by_session_token(:crypto.strong_rand_bytes(32)) == nil
    end
  end

  describe "scopes" do
    test "every signed-in user is an editor, visitors are not" do
      assert Scope.editor?(scope_fixture(:editor))
      refute Scope.editor?(nil)
      assert Scope.actor(scope_fixture(:editor)) == "editor@finngen.fi"
      assert Scope.actor(nil) == nil
    end
  end
end
