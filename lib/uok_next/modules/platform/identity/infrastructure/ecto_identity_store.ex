defmodule UokNext.Modules.Platform.Identity.Infrastructure.EctoIdentityStore do
  @moduledoc false

  @behaviour UokNext.Modules.Platform.Identity.Application.IdentityStore

  import Ecto.Query

  alias UokNext.Modules.Platform.Identity.Infrastructure.{
    BootstrapSessionRecord,
    LoginThrottleRecord,
    PasswordCredentialRecord,
    SessionRecord,
    UserRecord
  }

  alias UokNext.Repo

  @window_seconds 900
  @short_block_seconds 30
  @long_block_seconds 900

  @impl true
  def create_user(attrs, password_hash) do
    with {:ok, user} <- %UserRecord{} |> UserRecord.create_changeset(attrs) |> Repo.insert(),
         {:ok, credential} <-
           %PasswordCredentialRecord{}
           |> PasswordCredentialRecord.create_changeset(%{
             tenant_id: user.tenant_id,
             actor_id: user.id,
             password_hash: password_hash,
             generation: 1,
             changed_at: DateTime.utc_now()
           })
           |> Repo.insert() do
      {:ok, user, credential}
    else
      {:error, changeset} -> {:error, changeset_errors(changeset)}
    end
  end

  @impl true
  def list_users(tenant_id, limit) do
    from(user in UserRecord,
      where: user.tenant_id == ^tenant_id,
      order_by: [asc: user.normalized_username, asc: user.id],
      limit: ^limit
    )
    |> Repo.all()
  end

  @impl true
  def fetch_auth_by_username(tenant_id, username, lock?) do
    from(user in UserRecord,
      join: credential in PasswordCredentialRecord,
      on: credential.tenant_id == user.tenant_id and credential.actor_id == user.id,
      where: user.tenant_id == ^tenant_id and user.normalized_username == ^username,
      select: {user, credential}
    )
    |> maybe_lock(lock?)
    |> Repo.one()
    |> normalize_auth()
  end

  @impl true
  def fetch_auth_by_actor(tenant_id, actor_id, lock?) do
    from(user in UserRecord,
      join: credential in PasswordCredentialRecord,
      on: credential.tenant_id == user.tenant_id and credential.actor_id == user.id,
      where: user.tenant_id == ^tenant_id and user.id == ^actor_id,
      select: {user, credential}
    )
    |> maybe_lock(lock?)
    |> Repo.one()
    |> normalize_auth()
  end

  @impl true
  def create_session(attrs) do
    %SessionRecord{}
    |> SessionRecord.create_changeset(attrs)
    |> Repo.insert()
    |> normalize_write()
  end

  @impl true
  def fetch_session(tenant_id, session_id, lock?) do
    from(session in SessionRecord,
      join: user in UserRecord,
      on: user.tenant_id == session.tenant_id and user.id == session.actor_id,
      join: credential in PasswordCredentialRecord,
      on: credential.tenant_id == user.tenant_id and credential.actor_id == user.id,
      where: session.tenant_id == ^tenant_id and session.id == ^session_id,
      select: {session, user, credential}
    )
    |> maybe_lock(lock?)
    |> Repo.one()
    |> normalize_session()
  end

  @impl true
  def revoke_session(session, now) do
    session
    |> Ecto.Changeset.change(revoked_at: session.revoked_at || now)
    |> Repo.update()
    |> normalize_write()
  end

  @impl true
  def create_bootstrap_session(attrs) do
    %BootstrapSessionRecord{}
    |> BootstrapSessionRecord.create_changeset(attrs)
    |> Repo.insert()
    |> normalize_write()
  end

  @impl true
  def fetch_bootstrap_session(tenant_id, session_id, lock?) do
    from(session in BootstrapSessionRecord,
      where: session.tenant_id == ^tenant_id and session.id == ^session_id
    )
    |> maybe_lock(lock?)
    |> Repo.one()
    |> normalize_bootstrap_session()
  end

  @impl true
  def revoke_bootstrap_session(session, now) do
    session
    |> Ecto.Changeset.change(revoked_at: session.revoked_at || now)
    |> Repo.update()
    |> normalize_write()
  end

  @impl true
  def activate_and_rotate(user, credential, password_hash) do
    with {:ok, rotated} <-
           credential |> PasswordCredentialRecord.rotate_changeset(password_hash) |> Repo.update(),
         {:ok, activated} <-
           user
           |> UserRecord.activate_changeset()
           |> Repo.update(stale_error_field: :lock_version, stale_error_message: "is stale") do
      {:ok, activated, rotated}
    else
      {:error, changeset} -> normalize_update_error(changeset)
    end
  end

  @impl true
  def revoke_actor_sessions(tenant_id, actor_id, now) do
    {count, nil} =
      Repo.update_all(
        from(session in SessionRecord,
          where:
            session.tenant_id == ^tenant_id and session.actor_id == ^actor_id and
              is_nil(session.revoked_at)
        ),
        set: [revoked_at: now, updated_at: now]
      )

    count
  end

  @impl true
  def register_login_attempt(tenant_id, identifier_hash, now) do
    lock_identifier!(tenant_id, identifier_hash)

    current =
      from(throttle in LoginThrottleRecord,
        where: throttle.tenant_id == ^tenant_id and throttle.identifier_hash == ^identifier_hash,
        lock: "FOR UPDATE"
      )
      |> Repo.one()

    if currently_blocked?(current, now) do
      {:blocked, current.blocked_until}
    else
      attrs = failure_attrs(current, tenant_id, identifier_hash, now)

      Repo.insert_all(LoginThrottleRecord, [attrs],
        on_conflict: {:replace, [:failed_count, :window_started_at, :blocked_until, :updated_at]},
        conflict_target: [:tenant_id, :identifier_hash]
      )

      :ok
    end
  end

  @impl true
  def reset_login_failures(tenant_id, identifier_hash) do
    lock_identifier!(tenant_id, identifier_hash)

    Repo.delete_all(
      from(throttle in LoginThrottleRecord,
        where: throttle.tenant_id == ^tenant_id and throttle.identifier_hash == ^identifier_hash
      )
    )

    :ok
  end

  defp failure_attrs(current, tenant_id, identifier_hash, now) do
    {failed_count, window_started_at} = next_failure_window(current, now)

    %{
      tenant_id: tenant_id,
      identifier_hash: identifier_hash,
      failed_count: failed_count,
      window_started_at: window_started_at,
      blocked_until: blocked_until(failed_count, now),
      inserted_at: (current && current.inserted_at) || now,
      updated_at: now
    }
  end

  defp next_failure_window(nil, now), do: {1, now}

  defp next_failure_window(current, now) do
    if DateTime.diff(now, current.window_started_at, :second) >= @window_seconds do
      {1, now}
    else
      {min(current.failed_count + 1, 1000), current.window_started_at}
    end
  end

  defp blocked_until(failed_count, now) when failed_count >= 10,
    do: DateTime.add(now, @long_block_seconds, :second)

  defp blocked_until(failed_count, now) when failed_count >= 5,
    do: DateTime.add(now, @short_block_seconds, :second)

  defp blocked_until(_failed_count, _now), do: nil

  defp currently_blocked?(nil, _now), do: false

  defp currently_blocked?(current, now) do
    current.blocked_until && DateTime.after?(current.blocked_until, now)
  end

  defp lock_identifier!(tenant_id, identifier_hash) do
    encoded = tenant_id <> ":" <> Base.encode16(identifier_hash, case: :lower)

    Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [encoded],
      timeout: 1_000,
      log: false
    )
  end

  defp maybe_lock(query, true), do: lock(query, "FOR UPDATE")
  defp maybe_lock(query, false), do: query
  defp normalize_auth(nil), do: :not_found
  defp normalize_auth({user, credential}), do: {:ok, user, credential}
  defp normalize_session(nil), do: :not_found
  defp normalize_session({session, user, credential}), do: {:ok, session, user, credential}
  defp normalize_bootstrap_session(nil), do: :not_found
  defp normalize_bootstrap_session(session), do: {:ok, session}
  defp normalize_write({:ok, record}), do: {:ok, record}
  defp normalize_write({:error, changeset}), do: {:error, changeset_errors(changeset)}

  defp normalize_update_error(changeset) do
    if Keyword.has_key?(changeset.errors, :lock_version) do
      {:error, :stale}
    else
      {:error, changeset_errors(changeset)}
    end
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
      Enum.reduce(options, message, fn {key, value}, rendered ->
        String.replace(rendered, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
