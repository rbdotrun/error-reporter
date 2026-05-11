require "test_helper"

class RbRunErrorReporter::ErrorsControllerTest < ActionDispatch::IntegrationTest
  Cred = RbRunErrorReporter::IngestionCredential

  setup do
    RbRunErrorReporter::ErrorReport.delete_all
    Cred.delete_all
    result = Cred.issue!(name: "test-source")
    @credential = result[:credential]
    @token      = result[:token]
  end

  def auth_headers(token = @token)
    {
      "Authorization" => "Bearer #{token}",
      "Content-Type"  => "application/json"
    }
  end

  def valid_payload(overrides = {})
    {
      schema_version:  1,
      exception_class: "RuntimeError",
      message:         "boom",
      backtrace:       [ "/app/foo.rb:1" ],
      occurred_at:     Time.now.utc.iso8601,
      environment:     "production",
      release:         "abc1234",
      source:          "rack"
    }.merge(overrides)
  end

  test "POST with valid bearer + payload returns 202 and creates a row" do
    post "/error_reporter/errors", params: valid_payload.to_json, headers: auth_headers

    assert_response :accepted
    body = JSON.parse(response.body)
    assert_equal "accepted", body["status"]
    refute_nil body["id"]
    assert_equal 1, RbRunErrorReporter::ErrorReport.count
  end

  test "missing bearer returns 401" do
    post "/error_reporter/errors", params: valid_payload.to_json, headers: { "Content-Type" => "application/json" }
    assert_response :unauthorized
    assert_equal 0, RbRunErrorReporter::ErrorReport.count
  end

  test "bad bearer returns 401" do
    post "/error_reporter/errors", params: valid_payload.to_json, headers: auth_headers("rbreport_v1_bogus")
    assert_response :unauthorized
  end

  test "revoked bearer returns 401" do
    @credential.revoke!
    post "/error_reporter/errors", params: valid_payload.to_json, headers: auth_headers
    assert_response :unauthorized
  end

  test "malformed JSON returns 400" do
    post "/error_reporter/errors", params: "{not json", headers: auth_headers
    assert_response :bad_request
    assert_equal "malformed_json", JSON.parse(response.body)["reason"]
  end

  test "unsupported schema_version returns 400" do
    post "/error_reporter/errors", params: valid_payload(schema_version: 999).to_json, headers: auth_headers
    assert_response :bad_request
    assert_equal "schema_version_unsupported", JSON.parse(response.body)["reason"]
  end

  test "missing required field returns 400 with field name" do
    payload = valid_payload
    payload.delete(:exception_class)
    post "/error_reporter/errors", params: payload.to_json, headers: auth_headers
    assert_response :bad_request
    assert_equal "missing_field:exception_class", JSON.parse(response.body)["reason"]
  end

  test "source_app defaults to credential.name when omitted" do
    post "/error_reporter/errors", params: valid_payload.to_json, headers: auth_headers
    row = RbRunErrorReporter::ErrorReport.first
    assert_equal "test-source", row.source_app
  end

  test "explicit source_app in payload wins over credential default" do
    post "/error_reporter/errors", params: valid_payload(source_app: "explicit-name").to_json, headers: auth_headers
    row = RbRunErrorReporter::ErrorReport.first
    assert_equal "explicit-name", row.source_app
  end

  test "oversized payload returns 413" do
    RbRunErrorReporter.configure { |c| c.max_payload_bytes = 100 }
    payload = valid_payload(message: "x" * 500).to_json
    post "/error_reporter/errors", params: payload, headers: auth_headers
    assert_response :content_too_large
  ensure
    RbRunErrorReporter.configure { |c| c.max_payload_bytes = RbRunErrorReporter::Sdk::Ruby::Configuration::DEFAULT_MAX_PAYLOAD_BYTES }
  end

  test "gzipped request body is decompressed" do
    json = valid_payload.to_json
    gz   = Zlib.gzip(json)
    post "/error_reporter/errors",
         params: gz,
         headers: auth_headers.merge("Content-Encoding" => "gzip")
    assert_response :accepted
    assert_equal 1, RbRunErrorReporter::ErrorReport.count
  end

  test "last_used_at on the credential is updated on success" do
    @credential.update_column(:last_used_at, nil)
    post "/error_reporter/errors", params: valid_payload.to_json, headers: auth_headers
    @credential.reload
    refute_nil @credential.last_used_at
  end
end
