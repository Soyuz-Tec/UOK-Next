defmodule UokNextWeb.LocalQualificationTransport do
  @moduledoc """
  Restricts plaintext browser delivery to the isolated local qualifier.

  Production remains subject to the endpoint's HTTPS redirect. The exception
  opens only when all repository-owned local dependency and host invariants are
  active at the same time.
  """

  @local_hosts ~w(localhost 127.0.0.1)
  @local_database_hosts ~w(postgres host.containers.internal)

  @spec http_allowed?(Plug.Conn.t()) :: boolean()
  def http_allowed?(%Plug.Conn{host: host}) do
    Application.get_env(:uok_next, :deployment_profile) == :local_qualification and
      host in @local_hosts and local_endpoint?() and local_database?() and local_object_store?()
  end

  defp local_endpoint? do
    endpoint = Application.get_env(:uok_next, UokNextWeb.Endpoint, [])

    get_in(endpoint, [:url, :host]) == "localhost" and
      get_in(endpoint, [:http, :ip]) == {0, 0, 0, 0}
  end

  defp local_database? do
    with url when is_binary(url) <-
           Application.get_env(:uok_next, UokNext.Repo, []) |> Keyword.get(:url),
         %URI{host: host} when host in @local_database_hosts <- URI.parse(url) do
      true
    else
      _other -> false
    end
  end

  defp local_object_store? do
    object_store = Application.get_env(:uok_next, :object_store, [])

    object_store[:scheme] == "http://" and object_store[:host] == "object-store"
  end
end
