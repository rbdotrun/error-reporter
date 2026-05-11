require "test_helper"

class RbRunErrorReporter::Sdk::Ruby::RailsErrorSubscriberTest < ActiveSupport::TestCase
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
    @subscriber = RbRunErrorReporter::Sdk::Ruby::RailsErrorSubscriber.new
  end

  teardown { RbRunErrorReporter.reset_configuration! }

  test "forwards reported errors with source = rails.error by default" do
    @subscriber.report(RuntimeError.new("rescued"), handled: true, severity: :error, context: {}, source: nil)
    assert_equal 1, @sink.deliveries.size
    assert_equal "rails.error", @sink.deliveries.first[:source]
  end

  test "preserves an explicit source argument" do
    @subscriber.report(RuntimeError.new("x"), handled: false, severity: :error, context: { foo: "bar" }, source: "action_cable.subscription")
    assert_equal "action_cable.subscription", @sink.deliveries.first[:source]
    assert_equal({ foo: "bar" }, @sink.deliveries.first[:extra][:rails_context])
  end

  test "skips noisy active_support.cache_store sources" do
    @subscriber.report(RuntimeError.new("cache"), handled: true, severity: :warn, context: {}, source: "active_support.cache_store")
    assert_empty @sink.deliveries
  end
end
