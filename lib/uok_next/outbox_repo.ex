defmodule UokNext.OutboxRepo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :uok_next,
    adapter: Ecto.Adapters.Postgres
end
