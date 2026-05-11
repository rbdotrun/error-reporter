require "test_helper"

class RbRunErrorReporter::Sdk::Ruby::PayloadBuilderTest < ActiveSupport::TestCase
  setup do
    @config = RbRunErrorReporter::Sdk::Ruby::Configuration.new
    @config.environment = "test"
    @config.release = "abc123"
    @builder = RbRunErrorReporter::Sdk::Ruby::PayloadBuilder.new(@config)
  end

  teardown do
    Current.user = nil
    Current.workspace = nil
    Current.membership = nil
  end

  test "produces a schema-versioned payload with class/message/backtrace" do
    exc = build_exception_with_backtrace("boom")
    payload = @builder.build(exc, source: "test")

    assert_equal 1, payload[:schema_version]
    assert_equal "RuntimeError", payload[:exception_class]
    assert_equal "boom", payload[:message]
    assert_kind_of Array, payload[:backtrace]
    refute_empty payload[:backtrace]
    assert_equal "test", payload[:source]
    assert_equal "test", payload[:environment]
    assert_equal "abc123", payload[:release]
    assert_match(/\A\d{4}-\d{2}-\d{2}T/, payload[:occurred_at])
  end

  test "caps backtrace to 50 frames" do
    exc = RuntimeError.new("x")
    exc.set_backtrace((1..100).map { |i| "frame_#{i}" })
    payload = @builder.build(exc)
    assert_equal 50, payload[:backtrace].size
  end

  test "attaches Current.user / Current.workspace when set" do
    user      = User.create!(email: "alice@example.com",  name: "Alice")
    workspace = Workspace.create!(slug: "acme",          name: "Acme")
    Current.user = user
    Current.workspace = workspace

    payload = @builder.build(RuntimeError.new("x"))

    assert_equal user.id,      payload[:user_id]
    assert_equal workspace.id, payload[:workspace_id]
  end

  test "absent Current values are simply omitted (compact)" do
    payload = @builder.build(RuntimeError.new("x"))
    refute payload.key?(:user_id)
    refute payload.key?(:workspace_id)
  end

  test "request data is extracted from env" do
    env = ::Rack::MockRequest.env_for("/foo/bar?id=1", :method => "POST",
                                      "HTTP_USER_AGENT" => "rspec-tester/1.0",
                                      "HTTP_REFERER" => "https://example.com/")
    payload = @builder.build(RuntimeError.new("boom"), env:)

    refute_nil payload[:request]
    assert_equal "POST", payload[:request][:method]
    assert_equal "/foo/bar", payload[:request][:path]
    assert_equal "/foo/bar?id=1", payload[:request][:full_path]
    assert_equal "rspec-tester/1.0", payload[:request][:user_agent]
    assert_equal "https://example.com/", payload[:request][:referer]
  end

  test "passes through caller-supplied extras" do
    payload = @builder.build(RuntimeError.new("x"), job: { class: "MyJob", id: "42" })
    assert_equal "MyJob", payload[:extra][:job][:class]
  end

  private

    def build_exception_with_backtrace(msg)
      raise msg
    rescue RuntimeError => e
      e
    end
end
