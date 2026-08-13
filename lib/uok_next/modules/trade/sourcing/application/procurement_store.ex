defmodule UokNext.Modules.Trade.Sourcing.Application.ProcurementStore do
  @moduledoc "Persistence port for requisition, RFQ, quote, and comparison records."

  @callback create_requisition(map(), term()) :: tuple()
  @callback fetch_requisition(Ecto.UUID.t(), Ecto.UUID.t(), term(), keyword()) :: tuple()
  @callback list_requisitions(Ecto.UUID.t(), pos_integer(), term()) :: list()
  @callback update_requisition(term(), map(), term()) :: tuple()
  @callback create_rfq(map(), [map()], term()) :: tuple()
  @callback fetch_rfq(Ecto.UUID.t(), Ecto.UUID.t(), term(), keyword()) :: tuple()
  @callback list_rfqs(Ecto.UUID.t(), pos_integer(), term()) :: list()
  @callback rfq_supplier_ids(Ecto.UUID.t(), Ecto.UUID.t(), term()) :: [Ecto.UUID.t()]
  @callback update_rfq(term(), map(), term()) :: tuple()
  @callback invited_supplier?(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t(), term()) :: boolean()
  @callback create_quote(map(), term()) :: tuple()
  @callback fetch_quote(Ecto.UUID.t(), Ecto.UUID.t(), term(), keyword()) :: tuple()
  @callback list_quotes(Ecto.UUID.t(), Ecto.UUID.t() | nil, pos_integer(), term()) :: list()
  @callback update_quote(term(), map(), term()) :: tuple()
  @callback create_comparison(map(), term()) :: tuple()
  @callback fetch_comparison(Ecto.UUID.t(), Ecto.UUID.t(), term(), keyword()) :: tuple()
  @callback list_comparisons(Ecto.UUID.t(), pos_integer(), term()) :: list()
  @callback update_comparison(term(), map(), term()) :: tuple()
end
