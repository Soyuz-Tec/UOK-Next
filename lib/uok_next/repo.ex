defmodule UokNext.Repo do
  use Ecto.Repo,
    otp_app: :uok_next,
    adapter: Ecto.Adapters.Postgres
end
