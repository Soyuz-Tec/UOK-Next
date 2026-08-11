defmodule UokNext.ReleaseTest do
  use ExUnit.Case, async: false

  alias UokNext.Release

  defmodule PrereleaseRepo do
    def query(_statement, [], _options), do: {:ok, %{rows: [[190_000, "19beta2"]]}}
  end

  defmodule StableRepo do
    def query(_statement, [], _options), do: {:ok, %{rows: [[190_000, "19.0"]]}}
  end

  defmodule RecordingMigrator do
    def run(repo, :up, all: true) do
      send(self(), {:migration_started, repo})
      [:migrated]
    end
  end

  setup do
    previous = Application.fetch_env!(:uok_next, :database_prerelease_allowed)
    Application.put_env(:uok_next, :database_prerelease_allowed, false)

    on_exit(fn ->
      Application.put_env(:uok_next, :database_prerelease_allowed, previous)
    end)
  end

  test "rejects a production prerelease before the migrator runs" do
    assert_raise RuntimeError, ~r/database_prerelease_forbidden/, fn ->
      Release.migrate_repo(PrereleaseRepo, RecordingMigrator)
    end

    refute_received {:migration_started, _repo}
  end

  test "runs migrations after a stable target-major server passes preflight" do
    assert [:migrated] = Release.migrate_repo(StableRepo, RecordingMigrator)
    assert_received {:migration_started, StableRepo}
  end
end
