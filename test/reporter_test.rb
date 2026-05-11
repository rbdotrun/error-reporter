require "test_helper"

class RbRunErrorReporter::Sdk::Ruby::ReporterTest < ActiveSupport::TestCase
  # Capturing sink so we can assert what flowed through the funnel.
  class CapturingSink
    attr_reader :deliveries
    def initialize; @deliveries = []; end
    def deliver(p); @deliveries << p; p; end
    def flush; end
  end

  # Sink that always raises — used to prove the reporter never lets
  # internal failures escape. A reporter that crashes the request it
  # was protecting is worse than one that drops a report.
  class ExplodingSink
    def deliver(_p); raise "kaboom"; end
    def flush; end
  end

  setup do
    RbRunErrorReporter.reset_configuration!
    @sink = CapturingSink.new
    RbRunErrorReporter.configure do |c|
      c.sink = @sink
      c.enabled = true
    end
  end

  teardown { RbRunErrorReporter.reset_configuration! }

  def capture(exc, **ctx)
    RbRunErrorReporter::Sdk::Ruby::Reporter.new(RbRunErrorReporter.configuration).capture(exc, **ctx)
  end

  test "delivers payload through the sink" do
    capture(RuntimeError.new("boom"), source: "test")
    assert_equal 1, @sink.deliveries.size
    assert_equal "RuntimeError", @sink.deliveries.first[:exception_class]
  end

  test "returns nil and skips sink when disabled" do
    RbRunErrorReporter.configuration.enabled = false
    assert_nil capture(RuntimeError.new("x"))
    assert_empty @sink.deliveries
  end

  test "returns nil and skips sink when exception is nil" do
    assert_nil capture(nil)
    assert_empty @sink.deliveries
  end

  test "returns nil and skips sink for ignored exception classes" do
    capture(ActiveRecord::RecordNotFound.new("missing"))
    assert_empty @sink.deliveries
  end

  test "before_send returning nil drops the report" do
    RbRunErrorReporter.configuration.before_send = ->(_payload) { nil }
    capture(RuntimeError.new("boom"))
    assert_empty @sink.deliveries
  end

  test "before_send can mutate the payload before delivery" do
    RbRunErrorReporter.configuration.before_send = ->(p) { p.merge(mutated: true) }
    capture(RuntimeError.new("boom"))
    assert_equal true, @sink.deliveries.first[:mutated]
  end

  test "an exploding sink never raises out of capture — funnel returns nil" do
    RbRunErrorReporter.configuration.sink = ExplodingSink.new
    result = nil
    assert_nothing_raised { result = capture(RuntimeError.new("boom")) }
    assert_nil result
  end

  test "no sink configured short-circuits silently (no error)" do
    RbRunErrorReporter.configuration.sink = nil
    assert_nil capture(RuntimeError.new("boom"))
  end
end
