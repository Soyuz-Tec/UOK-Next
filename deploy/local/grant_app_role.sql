\set ON_ERROR_STOP on

REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM uok_app;
REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public FROM uok_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM uok_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM uok_app;

GRANT SELECT ON TABLE schema_migrations TO uok_app;
GRANT SELECT, INSERT, UPDATE ON TABLE kernel_command_receipts TO uok_app;
GRANT SELECT, INSERT ON TABLE kernel_audit_events TO uok_app;
GRANT SELECT, INSERT ON TABLE kernel_outbox_events TO uok_app;
GRANT SELECT, INSERT, UPDATE ON TABLE master_parties TO uok_app;
GRANT SELECT, INSERT ON TABLE master_products TO uok_app;
GRANT SELECT, INSERT ON TABLE master_locations TO uok_app;
GRANT SELECT, INSERT, UPDATE ON TABLE trade_sourcing_lanes TO uok_app;
GRANT SELECT, INSERT, UPDATE ON TABLE trade_purchase_requisitions TO uok_app;
GRANT SELECT, INSERT, UPDATE ON TABLE trade_rfqs TO uok_app;
GRANT SELECT, INSERT ON TABLE trade_rfq_suppliers TO uok_app;
GRANT SELECT, INSERT, UPDATE ON TABLE trade_supplier_quotes TO uok_app;
GRANT SELECT, INSERT, UPDATE ON TABLE trade_quote_comparisons TO uok_app;
GRANT SELECT, INSERT, UPDATE ON TABLE trade_purchase_commitment_proposals TO uok_app;
GRANT SELECT, INSERT, UPDATE ON TABLE trade_shipment_readiness_cases TO uok_app;
GRANT SELECT, INSERT, UPDATE ON TABLE platform_workflow_human_tasks TO uok_app;
GRANT SELECT, INSERT, UPDATE ON TABLE platform_integrations_connector_receipts TO uok_app;
GRANT SELECT, INSERT ON TABLE platform_integrations_communication_links TO uok_app;
GRANT SELECT, INSERT, UPDATE ON TABLE platform_agents_plans TO uok_app;
GRANT SELECT, INSERT, UPDATE ON TABLE platform_evidence_objects TO uok_app;
GRANT SELECT, INSERT, UPDATE ON TABLE platform_identity_users TO uok_app;
GRANT SELECT, INSERT, UPDATE ON TABLE platform_identity_password_credentials TO uok_app;
GRANT SELECT, INSERT, UPDATE ON TABLE platform_identity_sessions TO uok_app;
GRANT SELECT, INSERT, UPDATE ON TABLE platform_identity_bootstrap_sessions TO uok_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE platform_identity_login_throttles TO uok_app;
