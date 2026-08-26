defmodule UokNext.Modules.Platform.Identity.Application.IdentityStore do
  @moduledoc false

  @callback create_user(map(), String.t()) :: {:ok, term(), term()} | {:error, map()}
  @callback list_users(Ecto.UUID.t(), pos_integer()) :: [term()]
  @callback fetch_auth_by_username(Ecto.UUID.t(), String.t(), boolean()) ::
              {:ok, term(), term()} | :not_found
  @callback fetch_auth_by_actor(Ecto.UUID.t(), Ecto.UUID.t(), boolean()) ::
              {:ok, term(), term()} | :not_found
  @callback create_session(map()) :: {:ok, term()} | {:error, map()}
  @callback fetch_session(Ecto.UUID.t(), Ecto.UUID.t(), boolean()) ::
              {:ok, term(), term(), term()} | :not_found
  @callback revoke_session(term(), DateTime.t()) :: {:ok, term()} | {:error, map()}
  @callback create_bootstrap_session(map()) :: {:ok, term()} | {:error, map()}
  @callback fetch_bootstrap_session(Ecto.UUID.t(), Ecto.UUID.t(), boolean()) ::
              {:ok, term()} | :not_found
  @callback revoke_bootstrap_session(term(), DateTime.t()) :: {:ok, term()} | {:error, map()}
  @callback activate_and_rotate(term(), term(), String.t()) ::
              {:ok, term(), term()} | {:error, :stale | map()}
  @callback revoke_actor_sessions(Ecto.UUID.t(), Ecto.UUID.t(), DateTime.t()) :: non_neg_integer()
  @callback register_login_attempt(Ecto.UUID.t(), binary(), DateTime.t()) ::
              :ok | {:blocked, DateTime.t()}
  @callback reset_login_failures(Ecto.UUID.t(), binary()) :: :ok
end
