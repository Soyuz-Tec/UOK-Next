defmodule UokNextWeb.Gate3SourcingAuthorityTest do
  use UokNextWeb.ConnCase, async: false

  @access_code "uok-next-test-access-code-00000001"

  test "creates tenant references and approves an evidence-bound sourcing lane", %{conn: conn} do
    token = sign_in(conn)
    supplier = create_approved_party(token)
    product = create_product(token)
    origin = create_location(token, "origin", "GH")
    destination = create_location(token, "destination", "GB")
    lane = create_lane(token, supplier, product, origin, destination)

    evidence_id = Ecto.UUID.generate()
    idempotency_key = Ecto.UUID.generate()

    evidenced =
      upload_lane_evidence(token, lane, evidence_id, idempotency_key, "route evidence")

    assert evidenced["status"] == "evidence_submitted"
    assert evidenced["review_task"]["subject_id"] == lane["id"]

    assert upload_lane_evidence(token, lane, evidence_id, idempotency_key, "route evidence") ==
             evidenced

    task = open_task(token, lane["id"])

    approved =
      build_conn()
      |> authenticated(token, Ecto.UUID.generate())
      |> post(~p"/api/v1/sourcing-lanes/#{lane["id"]}/decision", %{
        "decision" => "approve",
        "reason" => "Verified evidence supports the lane authority",
        "task_id" => task["id"],
        "expected_version" => evidenced["lock_version"]
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert approved["status"] == "approved"
    assert approved["review_task"]["resolution"] == "approve"

    detail =
      build_conn()
      |> authenticated(token)
      |> get(~p"/api/v1/sourcing-lanes/#{lane["id"]}")
      |> json_response(200)
      |> Map.fetch!("data")

    assert detail["supplier_party_id"] == supplier["id"]
    assert detail["product_id"] == product["id"]
    assert detail["origin_location_id"] == origin["id"]
    assert detail["destination_location_id"] == destination["id"]
    assert [%{"id" => ^evidence_id, "state" => "verified"}] = detail["evidence_objects"]
  end

  test "rejects an unapproved supplier and a same-origin route", %{conn: conn} do
    token = sign_in(conn)
    draft_supplier = create_party(token)
    product = create_product(token)
    location = create_location(token, "single", "GH")
    other_location = create_location(token, "other", "GB")

    hidden =
      build_conn()
      |> authenticated(token, Ecto.UUID.generate())
      |> post(
        ~p"/api/v1/sourcing-lanes",
        lane_attrs(draft_supplier, product, location, other_location)
      )
      |> json_response(404)

    assert hidden["error"]["code"] == "not_found"

    approved_supplier = create_approved_party(token)

    invalid_route =
      build_conn()
      |> authenticated(token, Ecto.UUID.generate())
      |> post(
        ~p"/api/v1/sourcing-lanes",
        lane_attrs(approved_supplier, product, location, location)
      )
      |> json_response(422)

    assert invalid_route["error"]["code"] == "validation_failed"
  end

  test "delivers requisition through approved deterministic quote comparison", %{conn: conn} do
    token = sign_in(conn)
    first_supplier = create_approved_party(token)
    second_supplier = create_approved_party(token)
    product = create_product(token)
    origin = create_location(token, "origin", "GH")
    destination = create_location(token, "destination", "GB")
    lane = create_lane(token, first_supplier, product, origin, destination)

    evidenced_lane =
      upload_lane_evidence(
        token,
        lane,
        Ecto.UUID.generate(),
        Ecto.UUID.generate(),
        "approved route evidence"
      )

    lane_task = open_task(token, lane["id"])

    approved_lane =
      build_conn()
      |> authenticated(token, Ecto.UUID.generate())
      |> post(~p"/api/v1/sourcing-lanes/#{lane["id"]}/decision", %{
        "decision" => "approve",
        "reason" => "Lane evidence supports procurement",
        "task_id" => lane_task["id"],
        "expected_version" => evidenced_lane["lock_version"]
      })
      |> json_response(200)
      |> Map.fetch!("data")

    requisition =
      build_conn()
      |> authenticated(token, Ecto.UUID.generate())
      |> post(~p"/api/v1/purchase-requisitions", %{
        "stable_identifier" => unique("requisition"),
        "sourcing_lane_id" => approved_lane["id"],
        "quantity" => "25",
        "unit_code" => "MT",
        "required_by" => Date.utc_today() |> Date.add(30) |> Date.to_iso8601(),
        "reason" => "Create a procurement requirement"
      })
      |> json_response(201)
      |> Map.fetch!("data")

    rfq =
      build_conn()
      |> authenticated(token, Ecto.UUID.generate())
      |> post(~p"/api/v1/rfqs", %{
        "stable_identifier" => unique("rfq"),
        "requisition_id" => requisition["id"],
        "expected_version" => requisition["lock_version"],
        "settlement_currency_code" => "USD",
        "response_deadline" =>
          DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601(),
        "supplier_party_ids" => [first_supplier["id"], second_supplier["id"]],
        "reason" => "Invite approved suppliers"
      })
      |> json_response(201)
      |> Map.fetch!("data")

    first_quote = create_quote(token, rfq, first_supplier, "100", 14, "first")
    second_quote = create_quote(token, rfq, second_supplier, "90", 21, "second")
    _first_submission = upload_quote_evidence(token, first_quote, "first quote evidence")
    _second_submission = upload_quote_evidence(token, second_quote, "second quote evidence")

    comparison =
      build_conn()
      |> authenticated(token, Ecto.UUID.generate())
      |> post(~p"/api/v1/quote-comparisons", %{
        "stable_identifier" => unique("comparison"),
        "rfq_id" => rfq["id"],
        "expected_version" => rfq["lock_version"],
        "reason" => "Compare attributable quotes"
      })
      |> json_response(201)
      |> Map.fetch!("data")

    assert comparison["recommended_quote_id"] == second_quote["id"]
    comparison_task = open_task(token, comparison["id"])

    approved =
      build_conn()
      |> authenticated(token, Ecto.UUID.generate())
      |> post(~p"/api/v1/quote-comparisons/#{comparison["id"]}/decision", %{
        "decision" => "approve",
        "reason" => "Comparison evidence passed review",
        "task_id" => comparison_task["id"],
        "expected_version" => comparison["lock_version"]
      })
      |> json_response(200)
      |> Map.fetch!("data")

    assert approved["status"] == "approved"

    quotes =
      build_conn()
      |> authenticated(token)
      |> get(~p"/api/v1/supplier-quotes?rfq_id=#{rfq["id"]}")
      |> json_response(200)
      |> Map.fetch!("data")

    assert Enum.map(quotes, & &1["status"]) == ["submitted", "submitted"]
  end

  defp sign_in(conn) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(~p"/api/v1/session", %{"access_code" => @access_code})
    |> json_response(201)
    |> get_in(["data", "access_token"])
  end

  defp create_approved_party(token) do
    party = create_party(token)
    evidence_id = Ecto.UUID.generate()

    evidenced =
      build_conn()
      |> authenticated(token, Ecto.UUID.generate())
      |> post(~p"/api/v1/parties/#{party["id"]}/evidence", %{
        "evidence_id" => evidence_id,
        "expected_version" => party["lock_version"],
        "classification" => "confidential",
        "reason" => "Verify supplier authority",
        "file" => upload_fixture("supplier authority")
      })
      |> json_response(200)
      |> Map.fetch!("data")

    task = open_task(token, party["id"])

    build_conn()
    |> authenticated(token, Ecto.UUID.generate())
    |> post(~p"/api/v1/parties/#{party["id"]}/decision", %{
      "decision" => "approve",
      "reason" => "Supplier evidence passed review",
      "task_id" => task["id"],
      "expected_version" => evidenced["lock_version"]
    })
    |> json_response(200)
    |> Map.fetch!("data")
  end

  defp create_party(token) do
    build_conn()
    |> authenticated(token, Ecto.UUID.generate())
    |> post(~p"/api/v1/parties", %{
      "stable_identifier" => unique("supplier"),
      "legal_name" => "Governed Supplier",
      "country_code" => "GH",
      "party_kind" => "organization",
      "reason" => "Create supplier authority candidate"
    })
    |> json_response(201)
    |> Map.fetch!("data")
  end

  defp create_product(token) do
    build_conn()
    |> authenticated(token, Ecto.UUID.generate())
    |> post(~p"/api/v1/products", %{
      "stable_identifier" => unique("product"),
      "name" => "Governed Product",
      "product_kind" => "commodity",
      "base_unit_code" => "MT",
      "reason" => "Create product authority"
    })
    |> json_response(201)
    |> Map.fetch!("data")
  end

  defp create_location(token, label, country_code) do
    build_conn()
    |> authenticated(token, Ecto.UUID.generate())
    |> post(~p"/api/v1/locations", %{
      "stable_identifier" => unique(label),
      "name" => "#{String.capitalize(label)} Location",
      "country_code" => country_code,
      "location_kind" => "port",
      "reason" => "Create route location authority"
    })
    |> json_response(201)
    |> Map.fetch!("data")
  end

  defp create_lane(token, supplier, product, origin, destination) do
    build_conn()
    |> authenticated(token, Ecto.UUID.generate())
    |> post(~p"/api/v1/sourcing-lanes", lane_attrs(supplier, product, origin, destination))
    |> json_response(201)
    |> Map.fetch!("data")
  end

  defp lane_attrs(supplier, product, origin, destination) do
    %{
      "stable_identifier" => unique("lane"),
      "name" => "Governed Sourcing Lane",
      "supplier_party_id" => supplier["id"],
      "product_id" => product["id"],
      "origin_location_id" => origin["id"],
      "destination_location_id" => destination["id"],
      "reason" => "Create evidence-governed route authority"
    }
  end

  defp upload_lane_evidence(token, lane, evidence_id, key, content) do
    build_conn()
    |> authenticated(token, key)
    |> post(~p"/api/v1/sourcing-lanes/#{lane["id"]}/evidence", %{
      "evidence_id" => evidence_id,
      "expected_version" => lane["lock_version"],
      "classification" => "confidential",
      "reason" => "Attach sourcing authority evidence",
      "file" => upload_fixture(content)
    })
    |> json_response(200)
    |> Map.fetch!("data")
  end

  defp create_quote(token, rfq, supplier, price, days, label) do
    build_conn()
    |> authenticated(token, Ecto.UUID.generate())
    |> post(~p"/api/v1/supplier-quotes", %{
      "stable_identifier" => unique("quote-#{label}"),
      "rfq_id" => rfq["id"],
      "supplier_party_id" => supplier["id"],
      "quoted_quantity" => "25",
      "unit_price" => price,
      "currency_code" => "USD",
      "delivery_days" => days,
      "reason" => "Record attributable supplier quote"
    })
    |> json_response(201)
    |> Map.fetch!("data")
  end

  defp upload_quote_evidence(token, quote, content) do
    build_conn()
    |> authenticated(token, Ecto.UUID.generate())
    |> post(~p"/api/v1/supplier-quotes/#{quote["id"]}/evidence", %{
      "evidence_id" => Ecto.UUID.generate(),
      "expected_version" => quote["lock_version"],
      "classification" => "confidential",
      "reason" => "Attach supplier quote evidence",
      "file" => upload_fixture(content)
    })
    |> json_response(200)
    |> Map.fetch!("data")
  end

  defp open_task(token, subject_id) do
    tasks =
      build_conn()
      |> authenticated(token)
      |> get(~p"/api/v1/review-tasks")
      |> json_response(200)
      |> Map.fetch!("data")

    Enum.find(tasks, &(&1["subject_id"] == subject_id)) || flunk("review task was not opened")
  end

  defp authenticated(conn, token, key \\ nil) do
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("accept", "application/json")
    |> then(fn conn -> if key, do: put_req_header(conn, "idempotency-key", key), else: conn end)
  end

  defp upload_fixture(content) do
    path = Path.join(System.tmp_dir!(), "uok-sourcing-#{Ecto.UUID.generate()}.txt")
    File.write!(path, content, [:binary])
    on_exit(fn -> File.rm(path) end)
    %Plug.Upload{path: path, filename: "evidence.txt", content_type: "text/plain"}
  end

  defp unique(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
end
