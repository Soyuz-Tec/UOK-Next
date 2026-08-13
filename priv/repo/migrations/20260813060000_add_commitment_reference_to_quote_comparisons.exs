defmodule UokNext.Repo.Migrations.AddCommitmentReferenceToQuoteComparisons do
  @moduledoc "Owned by trade.sourcing; adds the public ADR-0020 reference key."

  use Ecto.Migration

  def change do
    create unique_index(
             :trade_quote_comparisons,
             [:tenant_id, :id, :recommended_quote_id],
             name: :trade_quote_comparisons_commitment_source_index
           )
  end
end
