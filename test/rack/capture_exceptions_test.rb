require "test_helper"

class RbRunErrorReporter::Sdk::Ruby::Rack::CaptureExceptionsTest < ActiveSupport::TestCase
  CaptureMw   = RbRunErrorReporter::Sdk::Ruby::Rack::CaptureExceptions
  InterceptMw = RbRunErrorReporter::Sdk::Ruby::Rack::RescuedExceptionInterceptor

  class CapturingSink
    attr_reader :deliveries
    def initialize; @deliveries = []; end
    def deliver(p); @deliveries << p; p; end
    def flush; end
  end

  setup do
    RbRunErrorReporter.reset_configuration!
    @sink = CapturingSink.new
    RbRunErrorReporter.configure { |c| c.sink = @sink }
  end

  teardown { RbRunErrorReporter.reset_configuration! }

  test "reports an exception stashed in env (rescued path)" do
    inner = ->(env) {
      env[InterceptMw::ENV_KEY] = RuntimeError.new("stashed")
      [ 500, {}, [ "err" ] ]
    }
    mw = CaptureMw.new(inner)
    mw.call(::Rack::MockRequest.env_for("/"))
    assert_equal 1, @sink.deliveries.size
    assert_equal "RuntimeError", @sink.deliveries.first[:exception_class]
    assert_equal true, @sink.deliveries.first[:extra][:handled]
  end

  test "reports an exception read from action_dispatch.exception" do
    inner = ->(env) {
      env["action_dispatch.exception"] = ArgumentError.new("dispatched")
      [ 500, {}, [ "err" ] ]
    }
    mw = CaptureMw.new(inner)
    mw.call(::Rack::MockRequest.env_for("/"))
    assert_equal "ArgumentError", @sink.deliveries.first[:exception_class]
  end

  test "catches raw raise and re-raises (unhandled path)" do
    inner = ->(_env) { raise TypeError, "raw" }
    mw = CaptureMw.new(inner)
    assert_raises(TypeError) { mw.call(::Rack::MockRequest.env_for("/")) }
    assert_equal "TypeError", @sink.deliveries.first[:exception_class]
    assert_equal false, @sink.deliveries.first[:extra][:handled]
  end

  test "does nothing when env has no exception and inner returns normally" do
    mw = CaptureMw.new(->(_env) { [ 200, {}, [ "ok" ] ] })
    mw.call(::Rack::MockRequest.env_for("/"))
    assert_empty @sink.deliveries
  end
end
