require "test_helper"

class RbRunErrorReporter::Sdk::Ruby::PiiScrubberTest < ActiveSupport::TestCase
  setup do
    @config = RbRunErrorReporter::Sdk::Ruby::Configuration.new
    @scrubber = RbRunErrorReporter::Sdk::Ruby::PiiScrubber.new(@config)
  end

  test "redacts top-level denied keys" do
    out = @scrubber.scrub({ password: "secret", username: "alice" })
    assert_equal "[FILTERED]", out[:password]
    assert_equal "alice",      out[:username]
  end

  test "redacts via case-insensitive substring (password_confirmation, MY_TOKEN, …)" do
    out = @scrubber.scrub({ "Password_Confirmation" => "x", "MY_TOKEN" => "y" })
    assert_equal "[FILTERED]", out["Password_Confirmation"]
    assert_equal "[FILTERED]", out["MY_TOKEN"]
  end

  test "walks nested hashes" do
    out = @scrubber.scrub({
      request: { params: { user: { password: "p" }, ok: 1 } }
    })
    assert_equal "[FILTERED]", out[:request][:params][:user][:password]
    assert_equal 1,            out[:request][:params][:ok]
  end

  test "walks arrays" do
    out = @scrubber.scrub([{ token: "a" }, { token: "b" }])
    assert_equal "[FILTERED]", out[0][:token]
    assert_equal "[FILTERED]", out[1][:token]
  end

  test "passes through non-container scalars unchanged" do
    assert_equal 42,      @scrubber.scrub(42)
    assert_equal "hello", @scrubber.scrub("hello")
    assert_nil            @scrubber.scrub(nil)
  end

  test "respects custom denylist via configuration" do
    @config.pii_fields = %w[my_secret_thing]
    scrubber = RbRunErrorReporter::Sdk::Ruby::PiiScrubber.new(@config)
    out = scrubber.scrub({ password: "kept", my_secret_thing: "redacted" })
    assert_equal "kept",       out[:password]
    assert_equal "[FILTERED]", out[:my_secret_thing]
  end
end
