defmodule UokNext.Release do
  @moduledoc false

  alias UokNext.Kernel.DatabaseCompatibility

  @app :uok_next

  @spec migrate() :: :ok
  def migrate do
    load_app()

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, _result, _apps} = Ecto.Migrator.with_repo(repo, &migrate_repo/1)
    end

    :ok
  end

  @doc false
  @spec migrate_repo(module(), module()) :: term()
  def migrate_repo(repo, migrator \\ Ecto.Migrator) do
    DatabaseCompatibility.verify!(repo)
    migrator.run(repo, :up, all: true)
  end

  defp load_app do
    Application.load(@app)
  end
end
