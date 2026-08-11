ExUnit.start()

unless System.get_env("UOK_OBJECT_STORE_INTEGRATION") in ~w(true 1) do
  ExUnit.configure(exclude: [object_store_integration: true])
end

Ecto.Adapters.SQL.Sandbox.mode(UokNext.Repo, :manual)
