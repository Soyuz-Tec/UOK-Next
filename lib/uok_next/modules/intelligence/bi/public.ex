defmodule UokNext.Modules.Intelligence.Bi.Public do
  @moduledoc "Supported query boundary for `intelligence.bi`."

  alias UokNext.Modules.Intelligence.Bi.Application.OperationalReports

  @spec operational_report(String.t(), integer(), term()) :: tuple()
  def operational_report(readiness_case_id, expected_version, context) do
    OperationalReports.get(readiness_case_id, expected_version, context)
  end
end
