require "test_helper"

class RbRunErrorReporter::Sdk::Ruby::Rack::RescuedExceptionInterceptorTest < ActiveSupport::TestCase
  Mw = RbRunErrorReporter::Sdk::Ruby::Rack::RescuedExceptionInterceptor

  test "passes through normal responses untouched" do
    app = ->(_env) { [200, {}, ["ok"]] }
    mw = Mw.new(app)
    status, _, body = mw.call(::Rack::MockRequest.env_for("/"))
    assert_equal 200, status
    assert_equal ["ok"], body
  end

  test "stashes the raw exception in env and re-raises" do
    raised = RuntimeError.new("boom")
    app = ->(_env) { raise raised }
    mw = Mw.new(app)
    env = ::Rack::MockRequest.env_for("/")
    assert_raises(RuntimeError) { mw.call(env) }
    assert_same raised, env[Mw::ENV_KEY]
  end
end
