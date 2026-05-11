require "test_helper"

class RbRunErrorReporter::IngestionCredentialTest < ActiveSupport::TestCase
  Cred = RbRunErrorReporter::IngestionCredential

  setup { Cred.delete_all }

  test "issue! returns a token once and never persists plaintext" do
    result = Cred.issue!(name: "appA-prod")
    assert_kind_of Cred, result[:credential]
    assert_match(/\Arbreport_v1_/, result[:token])

    cred = result[:credential]
    refute_includes Cred.column_names, "token"
    refute_nil cred.token_digest
    refute_equal result[:token], cred.token_digest
    assert_equal result[:token].last(4), cred.token_last_four
  end

  test "authenticate returns the active credential for a valid token" do
    result = Cred.issue!(name: "appA-prod")
    found = Cred.authenticate(result[:token])
    assert_equal result[:credential].id, found.id
  end

  test "authenticate returns nil for an unknown token" do
    Cred.issue!(name: "appA-prod")
    assert_nil Cred.authenticate("rbreport_v1_bogus")
  end

  test "authenticate returns nil for a revoked credential" do
    result = Cred.issue!(name: "appA-prod")
    result[:credential].revoke!
    assert_nil Cred.authenticate(result[:token])
  end

  test "authenticate updates last_used_at (throttled)" do
    result = Cred.issue!(name: "appA-prod")
    cred   = result[:credential]
    assert_nil cred.last_used_at

    Cred.authenticate(result[:token])
    cred.reload
    refute_nil cred.last_used_at
    first_seen = cred.last_used_at

    # Second call within the throttle window must NOT update.
    Cred.authenticate(result[:token])
    cred.reload
    assert_equal first_seen, cred.last_used_at
  end

  test "name is unique" do
    Cred.issue!(name: "appA-prod")
    assert_raises(ActiveRecord::RecordInvalid) { Cred.issue!(name: "appA-prod") }
  end
end
