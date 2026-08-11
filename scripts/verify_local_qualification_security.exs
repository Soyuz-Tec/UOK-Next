repo_config = Application.fetch_env!(:uok_next, UokNext.Repo)
endpoint_config = Application.fetch_env!(:uok_next, UokNextWeb.Endpoint)
build_revision = Application.fetch_env!(:uok_next, :build_revision)

unless is_binary(build_revision) and Regex.match?(~r/\A[0-9a-f]{40}\z/, build_revision) do
  raise "local qualification release identity must be compiled from a full Git revision"
end

{:ok, effective_repo_config} =
  Ecto.Repo.Supervisor.init_config(:supervisor, UokNext.Repo, :uok_next, [])

unless repo_config |> Keyword.fetch!(:url) |> URI.parse() |> Map.fetch!(:host) == "postgres" do
  raise "local qualification database must use the isolated Compose dependency"
end

unless effective_repo_config[:ssl] == false do
  raise "local qualification is the only profile allowed to use its isolated plaintext database"
end

unless endpoint_config[:http][:ip] == {0, 0, 0, 0} do
  raise "local qualification container must bind its private container interface"
end

unless is_binary(Application.fetch_env!(:uok_next, :metrics_access_token)) do
  raise "local qualification must protect metrics with a bearer token"
end

IO.puts("Local qualification security configuration verification passed.")
