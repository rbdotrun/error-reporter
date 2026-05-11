require "test_helper"

class RbRunErrorReporter::Sdk::Ruby::ActiveJobExtensionTest < ActiveSupport::TestCase
  class CapturingSink
    attr_reader :deliveries
    def initialize; @deliveries = []; end
    def deliver(p); @deliveries << p; p; end
    def flush; end
  end

  class BoomJob < ActiveJob::Base
    def perform(_arg = nil); raise "job_failed"; end
  end

  setup do
    RbRunErrorReporter.reset_configuration!
    @sink = CapturingSink.new
    RbRunErrorReporter.configure { |c| c.sink = @sink }
  end

  teardown { RbRunErrorReporter.reset_configuration! }

  test "captures failed perform_now and re-raises" do
    assert_raises(RuntimeError) { BoomJob.perform_now("anything") }
    assert_equal 1, @sink.deliveries.size
    payload = @sink.deliveries.first
    assert_equal "RuntimeError", payload[:exception_class]
    assert_equal "active_job",   payload[:source]
    assert_equal "RbRunErrorReporter::Sdk::Ruby::ActiveJobExtensionTest::BoomJob",
                 payload[:extra][:job][:class]
  end

  test "captures the job arguments (scalars passed through)" do
    assert_raises(RuntimeError) { BoomJob.perform_now("scalar_arg") }
    payload = @sink.deliveries.first
    assert_equal [ "scalar_arg" ], payload[:extra][:job][:arguments]
  end
end
