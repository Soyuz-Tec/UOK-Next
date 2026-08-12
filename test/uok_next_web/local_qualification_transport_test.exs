defmodule UokNextWeb.LocalQualificationTransportTest do
  use ExUnit.Case, async: false

  alias UokNextWeb.LocalQualificationTransport

  @settings [
    {:uok_next, :deployment_profile},
    {:uok_next, UokNextWeb.Endpoint},
    {:uok_next, UokNext.Repo},
    {:uok_next, :object_store}
  ]

  setup do
    previous =
      Enum.map(@settings, fn {app, key} -> {app, key, Application.fetch_env(app, key)} end)

    on_exit(fn ->
      Enum.each(previous, fn
        {app, key, {:ok, value}} -> Application.put_env(app, key, value)
        {app, key, :error} -> Application.delete_env(app, key)
      end)
    end)

    Application.put_env(:uok_next, :deployment_profile, :local_qualification)

    Application.put_env(:uok_next, UokNextWeb.Endpoint,
      url: [host: "localhost"],
      http: [ip: {0, 0, 0, 0}]
    )

    Application.put_env(:uok_next, UokNext.Repo, url: "ecto://uok_app:local@postgres/uok_next")

    Application.put_env(:uok_next, :object_store,
      scheme: "http://",
      host: "object-store"
    )

    :ok
  end

  test "allows only loopback hosts when every local qualification invariant holds" do
    assert LocalQualificationTransport.http_allowed?(conn("127.0.0.1"))
    assert LocalQualificationTransport.http_allowed?(conn("localhost"))
    refute LocalQualificationTransport.http_allowed?(conn("example.invalid"))
  end

  test "fails closed outside the explicit local deployment profile" do
    Application.put_env(:uok_next, :deployment_profile, :production)
    refute LocalQualificationTransport.http_allowed?(conn("127.0.0.1"))
  end

  test "fails closed when the endpoint host changes" do
    Application.put_env(:uok_next, UokNextWeb.Endpoint,
      url: [host: "example.invalid"],
      http: [ip: {0, 0, 0, 0}]
    )

    refute LocalQualificationTransport.http_allowed?(conn("127.0.0.1"))
  end

  test "fails closed when the endpoint binding changes" do
    Application.put_env(:uok_next, UokNextWeb.Endpoint,
      url: [host: "localhost"],
      http: [ip: {0, 0, 0, 0, 0, 0, 0, 1}]
    )

    refute LocalQualificationTransport.http_allowed?(conn("127.0.0.1"))
  end

  test "fails closed when the database host changes" do
    Application.put_env(:uok_next, UokNext.Repo,
      url: "ecto://uok_app:local@database.example.invalid/uok_next"
    )

    refute LocalQualificationTransport.http_allowed?(conn("127.0.0.1"))
  end

  test "fails closed when the object-store transport changes" do
    Application.put_env(:uok_next, :object_store,
      scheme: "https://",
      host: "objects.example.invalid"
    )

    refute LocalQualificationTransport.http_allowed?(conn("127.0.0.1"))
  end

  defp conn(host), do: :get |> Plug.Test.conn("/") |> Map.put(:host, host)
end
