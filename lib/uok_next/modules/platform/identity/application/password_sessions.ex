defmodule UokNext.Modules.Platform.Identity.Application.PasswordSessions do
  @moduledoc false

  alias UokNext.Kernel.{CommandContext, CommandError, CommandTransaction, TenantTransaction}
  alias UokNext.Modules.Platform.Identity.Application.{IdentityContext, IdentityEvidence}
  alias UokNext.Modules.Platform.Identity.Domain.{AccessProfile, CredentialInput, LocalUser}
  alias UokNext.Modules.Platform.Identity.Policies.Authorization

  @session_seconds 28_800
  @change_permission "identity:password:change"

  @spec authenticate(module(), map()) :: tuple()
  def authenticate(%{store: store, passwords: passwords, tokens: tokens} = services, attrs)
      when is_map(attrs) do
    with :ok <- Authorization.require_local_qualification(),
         {:ok, tenant_id} <- IdentityContext.local_tenant_id(),
         {:ok, username} <- normalize_username(attrs),
         {:ok, password} <- login_password(attrs),
         auth <- fetch_login_auth(store, tenant_id, username),
         throttle_identifier <- throttle_identifier(auth),
         :ok <- register_login_attempt(store, tokens, tenant_id, throttle_identifier),
         {:ok, user, credential} <- authenticate_credentials(auth, passwords, password),
         {:ok, permissions} <- permissions(user) do
      reset_throttle(store, tokens, tenant_id, throttle_identifier)
      issue_session(services, user, credential, permissions)
    else
      {:error, %CommandError{} = error} -> {:error, error}
      _failure -> unauthorized()
    end
  end

  def authenticate(_services, _attrs), do: unauthorized()

  @spec verify(module(), String.t()) :: tuple()
  def verify(%{store: store, tokens: tokens}, token) do
    with :ok <- Authorization.require_local_qualification(),
         {:ok, tenant_id} <- IdentityContext.local_tenant_id(),
         {:ok, session_id} <- tokens.parse(token),
         {:ok, session, user, credential} <- fetch_session(store, tenant_id, session_id),
         :ok <- valid_session(session, user, credential, token, tokens),
         {:ok, permissions} <- permissions(user) do
      {:ok, IdentityEvidence.identity(user, permissions)}
    else
      _failure -> unauthorized()
    end
  end

  @spec change_password(module(), map(), CommandContext.t(), String.t()) :: tuple()
  def change_password(%{store: store, passwords: passwords}, attrs, context, idempotency_key) do
    with :ok <- Authorization.require_local_qualification(),
         :ok <- Authorization.require_permission(context, @change_permission),
         {:ok, current_password} <- current_password(attrs),
         {:ok, new_password} <- new_password(attrs),
         :ok <- confirmation(new_password, attrs),
         {:ok, user, credential} <- fetch_auth(store, context),
         true <- user.must_change_password,
         true <- passwords.verify(current_password, credential.password_hash),
         false <- passwords.verify(new_password, credential.password_hash) do
      password_hash = passwords.hash(new_password)
      payload = password_change_payload(user, credential, new_password, passwords)

      CommandTransaction.execute(
        context,
        "platform.identity.activate_local_user",
        idempotency_key,
        payload,
        fn -> change_operation(store, user, credential, password_hash, context) end
      )
    else
      {:error, %CommandError{} = error} -> {:error, error}
      {:error, details} when is_map(details) -> validation_error(details)
      false -> validation_error(%{password: ["must differ from the temporary password"]})
      _failure -> unauthorized()
    end
  end

  @spec revoke(module(), String.t(), CommandContext.t()) :: tuple()
  def revoke(%{store: store, tokens: tokens}, token, context) do
    case tokens.parse(token) do
      {:ok, session_id} ->
        CommandTransaction.execute(
          context,
          "platform.identity.revoke_session",
          "logout:#{session_id}",
          %{session_id: session_id},
          fn -> revoke_operation(store, tokens, session_id, token, context) end
        )

      _not_password_session ->
        unauthorized()
    end
  end

  defp fetch_login_auth(store, tenant_id, username) do
    context = IdentityContext.lookup(tenant_id)

    TenantTransaction.run(context, fn ->
      store.fetch_auth_by_username(tenant_id, username, false)
    end)
  end

  defp authenticate_credentials(auth, passwords, password) do
    case auth do
      {:ok, user, credential} ->
        if valid_login_user?(user) and passwords.verify(password, credential.password_hash) do
          {:ok, user, credential}
        else
          unauthorized()
        end

      :not_found ->
        passwords.no_user_verify()
        unauthorized()
    end
  end

  defp throttle_identifier({:ok, user, _credential}), do: user.normalized_username
  defp throttle_identifier(:not_found), do: "__unknown_login__"

  defp issue_session(%{store: store, tokens: tokens}, user, credential, permissions) do
    session_id = Ecto.UUID.generate()
    token = tokens.generate(session_id)
    token_hash = tokens.digest(token)
    expires_at = DateTime.add(DateTime.utc_now(), @session_seconds, :second)
    {:ok, context} = IdentityContext.for_user(user, permissions)

    result =
      CommandTransaction.execute(
        context,
        "platform.identity.create_session",
        "login:#{session_id}",
        %{session_id: session_id, credential_generation: credential.generation},
        fn -> session_operation(store, user, credential, session_id, token_hash, expires_at) end
      )

    case result do
      {:ok, response, _disposition} ->
        {:ok,
         response
         |> Map.put("access_token", token)
         |> Map.put("token_type", "Bearer")
         |> Map.put("expires_in", @session_seconds)
         |> Map.put("identity", IdentityEvidence.identity(user, permissions))}

      {:error, %CommandError{} = error} ->
        {:error, error}
    end
  end

  defp session_operation(store, user, credential, session_id, token_hash, expires_at) do
    with {:ok, current_user, current_credential} <-
           fetch_auth_locked(store, user.tenant_id, user.id),
         true <- login_state_unchanged?(user, credential, current_user, current_credential),
         {:ok, session} <-
           store.create_session(%{
             id: session_id,
             tenant_id: user.tenant_id,
             actor_id: user.id,
             token_hash: token_hash,
             credential_generation: credential.generation,
             expires_at: expires_at
           }) do
      response = %{
        "session_id" => session.id,
        "password_change_required" => user.must_change_password
      }

      {:ok, response, IdentityEvidence.session_audit(session),
       [IdentityEvidence.session_event(session)]}
    else
      false -> unauthorized()
      :not_found -> unauthorized()
      {:error, details} when is_map(details) -> validation_error(details)
    end
  end

  defp change_operation(store, user, credential, password_hash, context) do
    with {:ok, current_user, current_credential} <-
           fetch_auth_locked(store, context.tenant_id, context.actor_id),
         true <- login_state_unchanged?(user, credential, current_user, current_credential),
         true <- current_user.must_change_password,
         {:ok, activated, rotated} <-
           store.activate_and_rotate(current_user, current_credential, password_hash) do
      now = DateTime.utc_now()
      revoked = store.revoke_actor_sessions(context.tenant_id, context.actor_id, now)
      response = IdentityEvidence.user_view(activated) |> Map.put("revoked_sessions", revoked)

      {:ok, response, IdentityEvidence.password_audit(activated),
       [IdentityEvidence.password_event(activated, rotated)]}
    else
      false -> stale()
      :not_found -> unauthorized()
      {:error, :stale} -> stale()
      {:error, details} when is_map(details) -> validation_error(details)
    end
  end

  defp revoke_operation(store, tokens, session_id, token, context) do
    case store.fetch_session(context.tenant_id, session_id, true) do
      {:ok, session, user, credential} ->
        with true <- session.actor_id == context.actor_id,
             :ok <- valid_session(session, user, credential, token, tokens),
             {:ok, revoked} <- store.revoke_session(session, DateTime.utc_now()) do
          response = %{"session_id" => revoked.id, "revoked" => true}

          {:ok, response, IdentityEvidence.revoke_audit(revoked),
           [IdentityEvidence.revoke_event(revoked)]}
        else
          _failure -> unauthorized()
        end

      :not_found ->
        unauthorized()
    end
  end

  defp fetch_session(store, tenant_id, session_id) do
    TenantTransaction.run(IdentityContext.lookup(tenant_id), fn ->
      case store.fetch_session(tenant_id, session_id, false) do
        {:ok, session, user, credential} -> {:ok, session, user, credential}
        :not_found -> unauthorized()
      end
    end)
  end

  defp fetch_auth(store, context) do
    TenantTransaction.run(context, fn ->
      case store.fetch_auth_by_actor(context.tenant_id, context.actor_id, false) do
        {:ok, user, credential} -> {:ok, user, credential}
        :not_found -> unauthorized()
      end
    end)
  end

  defp fetch_auth_locked(store, tenant_id, actor_id) do
    store.fetch_auth_by_actor(tenant_id, actor_id, true)
  end

  defp register_login_attempt(store, tokens, tenant_id, username) do
    hash = tokens.identifier_hash(username)

    result =
      TenantTransaction.run(IdentityContext.lookup(tenant_id), fn ->
        store.register_login_attempt(tenant_id, hash, DateTime.utc_now())
      end)

    case result do
      :ok -> :ok
      {:blocked, _until} -> rate_limited()
    end
  end

  defp reset_throttle(store, tokens, tenant_id, username) do
    TenantTransaction.run(IdentityContext.lookup(tenant_id), fn ->
      store.reset_login_failures(tenant_id, tokens.identifier_hash(username))
    end)
  end

  defp permissions(%{status: status, must_change_password: true})
       when status in ["pending_activation", "active"],
       do: {:ok, [@change_permission]}

  defp permissions(%{status: "active", access_profile: profile}),
    do: AccessProfile.permissions(profile)

  defp permissions(_user), do: :error

  defp valid_login_user?(user),
    do: user.status in ["pending_activation", "active"] and user.status != "suspended"

  defp valid_session(session, user, credential, token, tokens) do
    now = DateTime.utc_now()

    valid? =
      is_nil(session.revoked_at) and DateTime.after?(session.expires_at, now) and
        session.credential_generation == credential.generation and valid_login_user?(user) and
        tokens.matches?(session.token_hash, token)

    if valid?, do: :ok, else: :error
  end

  defp login_state_unchanged?(user, credential, current_user, current_credential) do
    user.lock_version == current_user.lock_version and user.status == current_user.status and
      user.must_change_password == current_user.must_change_password and
      credential.generation == current_credential.generation and
      credential.password_hash == current_credential.password_hash
  end

  defp normalize_username(attrs) do
    username = Map.get(attrs, "username", Map.get(attrs, :username))

    case LocalUser.normalize_login(username) do
      {:ok, normalized} -> {:ok, normalized}
      :error -> {:ok, "__invalid_login__"}
    end
  end

  defp login_password(attrs) do
    case Map.get(attrs, "password", Map.get(attrs, :password)) do
      password when is_binary(password) and byte_size(password) in 1..512 -> {:ok, password}
      _invalid -> {:ok, "invalid-password"}
    end
  end

  defp current_password(attrs) do
    attrs
    |> Map.get("current_password", Map.get(attrs, :current_password))
    |> CredentialInput.validate_current_password()
  end

  defp new_password(attrs) do
    attrs
    |> Map.get("new_password", Map.get(attrs, :new_password))
    |> CredentialInput.validate_password()
  end

  defp confirmation(password, attrs) do
    confirmation =
      Map.get(attrs, "new_password_confirmation", Map.get(attrs, :new_password_confirmation))

    CredentialInput.validate_confirmation(password, confirmation)
  end

  defp password_change_payload(user, credential, new_password, passwords) do
    %{
      actor_id: user.id,
      credential_generation: credential.generation,
      credential_fingerprint: passwords.fingerprint("local-password-change", new_password)
    }
  end

  defp validation_error(details) do
    {:error, CommandError.new("validation_failed", "credential validation failed", 422, details)}
  end

  defp stale, do: {:error, CommandError.new("stale_state", "credential changed", 409)}

  defp rate_limited,
    do: {:error, CommandError.new("rate_limited", "authentication temporarily unavailable", 429)}

  defp unauthorized, do: {:error, CommandError.new("unauthorized", "authentication failed", 401)}
end
