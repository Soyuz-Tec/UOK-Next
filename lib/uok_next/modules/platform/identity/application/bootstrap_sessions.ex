defmodule UokNext.Modules.Platform.Identity.Application.BootstrapSessions do
  @moduledoc false

  alias UokNext.Kernel.{CommandContext, CommandError, CommandTransaction, TenantTransaction}
  alias UokNext.Modules.Platform.Identity.Application.{IdentityContext, IdentityEvidence}
  alias UokNext.Modules.Platform.Identity.Policies.Authorization

  @session_seconds 28_800

  @spec authenticate(map(), term()) :: tuple()
  def authenticate(
        %{store: store, bootstrap_identity: identity_port, bootstrap_tokens: tokens},
        access_code
      ) do
    with :ok <- Authorization.require_local_qualification(),
         {:ok, identity} <- identity_port.authenticate(access_code),
         {:ok, context} <- IdentityContext.for_bootstrap(identity) do
      issue_session(store, tokens, identity, context)
    else
      _failure -> unauthorized()
    end
  end

  @spec verify(map(), String.t()) :: tuple()
  def verify(%{store: store, bootstrap_identity: identity_port, bootstrap_tokens: tokens}, token) do
    with :ok <- Authorization.require_local_qualification(),
         {:ok, identity} <- identity_port.current(),
         {:ok, session_id} <- tokens.parse(token),
         {:ok, session} <- fetch_session(store, identity.tenant_id, session_id),
         :ok <- valid_session(session, identity, token, tokens) do
      {:ok, public_identity(identity)}
    else
      _failure -> unauthorized()
    end
  end

  @spec revoke(map(), String.t(), CommandContext.t()) :: tuple()
  def revoke(%{store: store, bootstrap_tokens: tokens}, token, context) do
    case tokens.parse(token) do
      {:ok, session_id} ->
        CommandTransaction.execute(
          context,
          "platform.identity.revoke_bootstrap_session",
          "bootstrap-logout:#{session_id}",
          %{session_id: session_id},
          fn -> revoke_operation(store, tokens, session_id, token, context) end
        )

      _failure ->
        unauthorized()
    end
  end

  defp issue_session(store, tokens, identity, context) do
    session_id = Ecto.UUID.generate()
    token = tokens.generate(session_id)
    token_hash = tokens.digest(token)
    expires_at = DateTime.add(DateTime.utc_now(), @session_seconds, :second)

    result =
      CommandTransaction.execute(
        context,
        "platform.identity.create_bootstrap_session",
        "bootstrap-login:#{session_id}",
        %{session_id: session_id},
        fn -> create_operation(store, identity, session_id, token_hash, expires_at) end
      )

    case result do
      {:ok, response, _disposition} ->
        {:ok,
         response
         |> Map.put("access_token", token)
         |> Map.put("token_type", "Bearer")
         |> Map.put("expires_in", @session_seconds)
         |> Map.put("identity", public_identity(identity))}

      {:error, %CommandError{} = error} ->
        {:error, error}
    end
  end

  defp create_operation(store, identity, session_id, token_hash, expires_at) do
    case store.create_bootstrap_session(%{
           id: session_id,
           tenant_id: identity.tenant_id,
           actor_id: identity.actor_id,
           token_hash: token_hash,
           expires_at: expires_at
         }) do
      {:ok, session} ->
        response = %{"session_id" => session.id, "password_change_required" => false}

        {:ok, response, IdentityEvidence.session_audit(session),
         [IdentityEvidence.session_event(session)]}

      {:error, _details} ->
        unavailable()
    end
  end

  defp revoke_operation(store, tokens, session_id, token, context) do
    case store.fetch_bootstrap_session(context.tenant_id, session_id, true) do
      {:ok, session} ->
        with true <- session.actor_id == context.actor_id,
             :ok <- valid_stored_session(session, token, tokens),
             {:ok, revoked} <- store.revoke_bootstrap_session(session, DateTime.utc_now()) do
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
      case store.fetch_bootstrap_session(tenant_id, session_id, false) do
        {:ok, session} -> {:ok, session}
        :not_found -> unauthorized()
      end
    end)
  end

  defp valid_session(session, identity, token, tokens) do
    if session.actor_id == identity.actor_id do
      valid_stored_session(session, token, tokens)
    else
      :error
    end
  end

  defp valid_stored_session(session, token, tokens) do
    valid? =
      is_nil(session.revoked_at) and DateTime.after?(session.expires_at, DateTime.utc_now()) and
        tokens.matches?(session.token_hash, token)

    if valid?, do: :ok, else: :error
  end

  defp public_identity(identity) do
    %{
      "tenant_id" => identity.tenant_id,
      "actor_id" => identity.actor_id,
      "permissions" => Enum.sort(identity.permissions)
    }
  end

  defp unavailable,
    do: {:error, CommandError.new("identity_unavailable", "authentication unavailable", 503)}

  defp unauthorized, do: {:error, CommandError.new("unauthorized", "authentication failed", 401)}
end
