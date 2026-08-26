defmodule UokNextWeb.LocalUserAccessTest do
  use UokNextWeb.ConnCase, async: false

  alias UokNext.Kernel.{
    AuditEvent,
    CommandContext,
    CommandReceipt,
    OutboxEvent,
    TenantTransaction
  }

  alias UokNext.Modules.Platform.Identity.Infrastructure.{
    BootstrapSessionRecord,
    LoginThrottleRecord,
    PasswordCredentialRecord,
    SessionRecord,
    UserRecord
  }

  alias UokNext.Repo

  @access_code "uok-next-test-access-code-00000001"
  @temporary_password "Temporary onboarding passphrase 2026!"
  @new_password "Private onboarding passphrase for 2026!"

  test "creates and activates an attributable onboarding user without retaining plaintext", %{
    conn: conn
  } do
    admin_token = bootstrap_sign_in(conn)
    user = create_user(admin_token, "onboarding.operator")

    assert user["status"] == "pending_activation"
    assert user["must_change_password"]
    assert user["access_profile"] == "entity_onboarding_operator"

    users =
      build_conn()
      |> authenticated(admin_token)
      |> get(~p"/api/v1/identity/users")
      |> json_response(200)
      |> Map.fetch!("data")

    assert [%{"id" => user_id, "username" => "onboarding.operator"}] = users

    temporary_session = password_sign_in("ONBOARDING.OPERATOR", @temporary_password)
    assert temporary_session["password_change_required"]
    assert temporary_session["identity"]["permissions"] == ["identity:password:change"]

    forbidden =
      build_conn()
      |> authenticated(temporary_session["access_token"], Ecto.UUID.generate())
      |> post(~p"/api/v1/parties", party_params())
      |> json_response(403)

    assert forbidden["error"]["code"] == "forbidden"

    activated =
      build_conn()
      |> authenticated(temporary_session["access_token"], Ecto.UUID.generate())
      |> post(~p"/api/v1/session/password", %{
        "current_password" => @temporary_password,
        "new_password" => @new_password,
        "new_password_confirmation" => @new_password
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert activated["status"] == "active"
    refute activated["must_change_password"]
    assert activated["revoked_sessions"] == 1

    build_conn()
    |> authenticated(temporary_session["access_token"])
    |> get(~p"/api/v1/session")
    |> json_response(401)

    assert password_sign_in_status("onboarding.operator", @temporary_password) == 401

    active_session = password_sign_in("onboarding.operator", @new_password)
    assert active_session["identity"]["actor_id"] == user_id
    assert "parties:create" in active_session["identity"]["permissions"]
    refute "parties:approve" in active_session["identity"]["permissions"]

    forbidden_user_creation =
      build_conn()
      |> authenticated(active_session["access_token"], Ecto.UUID.generate())
      |> post(~p"/api/v1/identity/users", user_params("escalation.attempt"))
      |> json_response(403)

    assert forbidden_user_creation["error"]["code"] == "forbidden"

    created_party =
      build_conn()
      |> authenticated(active_session["access_token"], Ecto.UUID.generate())
      |> post(~p"/api/v1/parties", party_params())
      |> json_response(201)
      |> Map.fetch!("data")

    assert created_party["status"] == "draft"

    expire_session(active_session["session_id"])

    build_conn()
    |> authenticated(active_session["access_token"])
    |> get(~p"/api/v1/session")
    |> json_response(401)

    logout_session = password_sign_in("onboarding.operator", @new_password)

    build_conn()
    |> authenticated(logout_session["access_token"])
    |> delete(~p"/api/v1/session")
    |> json_response(200)

    build_conn()
    |> authenticated(logout_session["access_token"])
    |> get(~p"/api/v1/session")
    |> json_response(401)

    assert_no_plaintext_credentials()
  end

  test "rejects duplicate users, weak passwords, privilege escalation, and production activation",
       %{
         conn: conn
       } do
    admin_token = bootstrap_sign_in(conn)
    create_user(admin_token, "reviewer.user")

    duplicate =
      build_conn()
      |> authenticated(admin_token, Ecto.UUID.generate())
      |> post(~p"/api/v1/identity/users", user_params("REVIEWER.USER"))
      |> json_response(422)

    assert duplicate["error"]["code"] == "validation_failed"

    weak =
      build_conn()
      |> authenticated(admin_token, Ecto.UUID.generate())
      |> post(
        ~p"/api/v1/identity/users",
        user_params("weak.user", %{"temporary_password" => "password123456"})
      )
      |> json_response(422)

    assert weak["error"]["details"]["field"] == "password"

    escalated =
      build_conn()
      |> authenticated(admin_token, Ecto.UUID.generate())
      |> post(
        ~p"/api/v1/identity/users",
        user_params("admin.user", %{"access_profile" => "platform_administrator"})
      )
      |> json_response(422)

    assert escalated["error"]["details"]["field"] == "access_profile"

    previous = Application.get_env(:uok_next, :deployment_profile)
    Application.put_env(:uok_next, :deployment_profile, :production)
    on_exit(fn -> Application.put_env(:uok_next, :deployment_profile, previous) end)

    assert password_sign_in_status("reviewer.user", @temporary_password) == 404
  end

  test "applies one shared database throttle to repeated failed logins" do
    for _attempt <- 1..5 do
      assert password_sign_in_status("missing.user", @temporary_password) == 401
    end

    assert password_sign_in_status("missing.user", @temporary_password) == 429
  end

  test "bounds distinct unknown usernames and rejects browser-simple login bodies" do
    rejected =
      build_conn()
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("origin", "https://untrusted.invalid")
      |> post(~p"/api/v1/session", %{
        "username" => "browser.simple",
        "password" => @temporary_password
      })
      |> json_response(415)

    assert rejected["error"]["code"] == "unsupported_media_type"
    assert throttle_count() == 0

    for attempt <- 1..5 do
      assert password_sign_in_status("missing.user.#{attempt}", @temporary_password) == 401
    end

    assert password_sign_in_status("missing.user.6", @temporary_password) == 429
    assert throttle_count() == 1
  end

  test "revokes the exact bootstrap bearer at sign-out" do
    token = bootstrap_sign_in(build_conn())

    logout =
      build_conn()
      |> authenticated(token)
      |> delete(~p"/api/v1/session")
      |> json_response(200)

    assert logout["data"]["revoked"]

    build_conn()
    |> authenticated(token)
    |> get(~p"/api/v1/session")
    |> json_response(401)
  end

  test "database row-level security hides every local identity record from other tenants" do
    admin_token = bootstrap_sign_in(build_conn())
    create_user(admin_token, "tenant.boundary.user")
    password_sign_in("tenant.boundary.user", @temporary_password)
    assert password_sign_in_status("tenant.boundary.missing", @temporary_password) == 401

    owner_context = qualification_context()

    {:ok, other_context} =
      CommandContext.new(%{
        tenant_id: Ecto.UUID.generate(),
        actor_id: Ecto.UUID.generate(),
        correlation_id: Ecto.UUID.generate(),
        permissions: []
      })

    Repo.query!("SET LOCAL ROLE pg_read_all_data", [], log: false)
    Repo.query!("SELECT set_config('uok.tenant_id', '', true)", [], log: false)

    records = identity_records()

    Enum.each(records, fn record ->
      assert Repo.aggregate(record, :count) == 0, "unset tenant exposed #{inspect(record)}"
    end)

    Enum.each(records, fn record ->
      assert tenant_count(record, other_context) == 0, "foreign tenant exposed #{inspect(record)}"
    end)

    Enum.each(records, fn record ->
      assert tenant_count(record, owner_context) > 0, "owner cannot read #{inspect(record)}"
    end)
  end

  defp bootstrap_sign_in(conn) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(~p"/api/v1/session", %{"access_code" => @access_code})
    |> json_response(201)
    |> get_in(["data", "access_token"])
  end

  defp create_user(admin_token, username) do
    build_conn()
    |> authenticated(admin_token, Ecto.UUID.generate())
    |> post(~p"/api/v1/identity/users", user_params(username))
    |> json_response(201)
    |> Map.fetch!("data")
  end

  defp password_sign_in(username, password) do
    build_conn()
    |> put_req_header("content-type", "application/json")
    |> post(~p"/api/v1/session", %{"username" => username, "password" => password})
    |> json_response(201)
    |> Map.fetch!("data")
  end

  defp password_sign_in_status(username, password) do
    build_conn()
    |> put_req_header("content-type", "application/json")
    |> post(~p"/api/v1/session", %{"username" => username, "password" => password})
    |> Map.fetch!(:status)
  end

  defp authenticated(conn, token, idempotency_key \\ nil) do
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("accept", "application/json")
    |> maybe_idempotency(idempotency_key)
  end

  defp maybe_idempotency(conn, nil), do: conn
  defp maybe_idempotency(conn, key), do: put_req_header(conn, "idempotency-key", key)

  defp user_params(username, overrides \\ %{}) do
    Map.merge(
      %{
        "username" => username,
        "display_name" => "Onboarding Operator",
        "access_profile" => "entity_onboarding_operator",
        "temporary_password" => @temporary_password,
        "reason" => "Provision an attributable entity onboarding operator"
      },
      overrides
    )
  end

  defp party_params do
    %{
      "stable_identifier" => "regular-user-party-#{System.unique_integer([:positive])}",
      "legal_name" => "Regular User Trading Limited",
      "country_code" => "GH",
      "party_kind" => "organization",
      "reason" => "Create through a role-bounded regular user session"
    }
  end

  defp assert_no_plaintext_credentials do
    context = qualification_context()

    serialized =
      TenantTransaction.run(context, fn ->
        [
          Repo.all(UserRecord),
          Repo.all(PasswordCredentialRecord),
          Repo.all(SessionRecord),
          Repo.all(BootstrapSessionRecord),
          Repo.all(CommandReceipt),
          Repo.all(AuditEvent),
          Repo.all(OutboxEvent)
        ]
        |> inspect(limit: :infinity, printable_limit: :infinity)
      end)

    refute serialized =~ @temporary_password
    refute serialized =~ @new_password
    assert serialized =~ "pbkdf2-sha256$"
  end

  defp expire_session(session_id) do
    TenantTransaction.run(qualification_context(), fn ->
      SessionRecord
      |> Repo.get!(session_id)
      |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -1, :second))
      |> Repo.update!()
    end)
  end

  defp qualification_context do
    identity = Application.fetch_env!(:uok_next, :local_qualification_identity)

    {:ok, context} =
      CommandContext.new(%{
        tenant_id: identity.tenant_id,
        actor_id: identity.actor_id,
        correlation_id: Ecto.UUID.generate(),
        permissions: identity.permissions
      })

    context
  end

  defp tenant_count(record, context) do
    TenantTransaction.run(context, fn -> Repo.aggregate(record, :count) end)
  end

  defp throttle_count do
    TenantTransaction.run(qualification_context(), fn ->
      Repo.aggregate(LoginThrottleRecord, :count)
    end)
  end

  defp identity_records do
    [
      UserRecord,
      PasswordCredentialRecord,
      SessionRecord,
      BootstrapSessionRecord,
      LoginThrottleRecord
    ]
  end
end
