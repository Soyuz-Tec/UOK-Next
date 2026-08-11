defmodule UokNext.Release do
  @moduledoc false

  @app :uok_next

  @spec migrate() :: :ok
  def migrate do
    load_app()

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, _pid, _apps} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end

  defp load_app do
    Application.load(@app)
  end
end
