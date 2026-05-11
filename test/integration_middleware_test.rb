require "test_helper"

# Engine integration: asserts the middleware insertion + the actual
# Rack capture flow against the dummy host app. Uses a minimal chain
# of ONLY the two engine-inserted middlewares (no `Rails.application.middleware.build`,
# which pulls in ShowExceptions and pollutes global state).
#
# Separate from rack/capture_exceptions_test.rb because that exercises
# the middleware in isolation with a mock sink. THIS test goes all the
# way through Reporter → PayloadBuilder → DatabaseSink → error_reports
# row, which is the integration we care about.
class IntegrationMiddlewareTest < ActiveSupport::TestCase
  Interceptor = RbRunErrorReporter::Sdk::Ruby::Rack::RescuedExceptionInterceptor
  Capture     = RbRunErrorReporter::Sdk::Ruby::Rack::CaptureExceptions

  setup do
    @old_sink = RbRunErrorReporter.configuration.sink
    RbRunErrorReporter.configuration.sink = RbRunErrorReporter::Sdk::Ruby::Sinks::DatabaseSink.new
    RbRunErrorReporter::ErrorReport.delete_all
  end

  teardown do
    RbRunErrorReporter.configuration.sink = @old_sink
  end

  # Pure inspection — no `.build`, no calls. Just verify the engine's
  # initializer actually inserted both middlewares into the host's
  # middleware array on boot.
  test "engine inserts both middlewares into Rails.application.middleware" do
    classes = Rails.application.middleware.map(&:klass)
    assert_includes classes, Capture
    assert_includes classes, Interceptor
  end

  test "unhandled exception flows: inner raise → interceptor stashes → capture reports → re-raised" do
    user      = User.create!(email: "alice@example.com", name: "Alice")
    workspace = Workspace.create!(slug: "acme",         name: "Acme")
    Current.user = user
    Current.workspace = workspace

    inner = ->(_env) { raise RuntimeError, "integration_boom" }
    app   = Capture.new(Interceptor.new(inner))

    env = ::Rack::MockRequest.env_for("/_integration/boom")
    assert_raises(RuntimeError) { app.call(env) }

    report = RbRunErrorReporter::ErrorReport.last
    refute_nil report, "expected an ErrorReport row to be created"
    assert_equal "RuntimeError",     report.exception_class
    assert_equal "integration_boom", report.message
    assert_equal "rack",             report.source
    assert_equal user.id,            report.user_id
    assert_equal workspace.id,       report.workspace_id
    # `handled: false` because the inner app raised and the exception
    # propagated all the way up to Capture (not caught by an inner
    # rescuer first).
    assert_equal false, report.payload.dig("extra", "handled")
  end

  test "rescued path: exception stashed in env by Interceptor, read by Capture as handled" do
    inner_with_stash = ->(env) {
      env[Interceptor::ENV_KEY] = RuntimeError.new("stashed_in_env")
      [ 500, {}, [ "err page" ] ]
    }
    app = Capture.new(inner_with_stash)

    assert_nothing_raised { app.call(::Rack::MockRequest.env_for("/")) }
    report = RbRunErrorReporter::ErrorReport.last
    assert_equal "stashed_in_env", report.message
    assert_equal true, report.payload.dig("extra", "handled")
  end

  test "ignored exceptions (RecordNotFound etc.) are NOT persisted" do
    inner = ->(_env) { raise ActiveRecord::RecordNotFound, "no such" }
    app = Capture.new(Interceptor.new(inner))
    assert_raises(ActiveRecord::RecordNotFound) { app.call(::Rack::MockRequest.env_for("/")) }
    assert_equal 0, RbRunErrorReporter::ErrorReport.count
  end
end
