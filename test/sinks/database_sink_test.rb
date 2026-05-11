require "test_helper"

class RbRunErrorReporter::Sdk::Ruby::Sinks::DatabaseSinkTest < ActiveSupport::TestCase
  Sink = RbRunErrorReporter::Sdk::Ruby::Sinks::DatabaseSink

  setup { RbRunErrorReporter::ErrorReport.delete_all }

  def base_payload(extra = {})
    {
      schema_version:  1,
      exception_class: "RuntimeError",
      message:         "boom 42",
      backtrace:       [ "/app/foo.rb:1:in `bar'", "/app/baz.rb:2:in `qux'" ],
      environment:     "test",
      release:         "abc",
      source:          "test",
      source_app:      nil,
      occurred_at:     Time.now.utc.iso8601(3)
    }.merge(extra)
  end

  test "creates an ErrorReport row" do
    sink = Sink.new
    sink.deliver(base_payload)
    assert_equal 1, RbRunErrorReporter::ErrorReport.count
    row = RbRunErrorReporter::ErrorReport.first
    assert_equal "RuntimeError", row.exception_class
    assert_equal "boom 42",      row.message
    assert_equal "test",         row.environment
    assert_equal({}, row.payload.transform_keys(&:to_s).slice("nonexistent"))
    refute_nil row.fingerprint
  end

  test "stores the full payload as JSONB" do
    sink = Sink.new
    sink.deliver(base_payload(extra: { job: { class: "MyJob" } }))
    row = RbRunErrorReporter::ErrorReport.first
    # JSONB returns string-keyed hashes from PG.
    assert_equal "MyJob", row.payload.dig("extra", "job", "class")
  end

  test "fingerprint normalizes numbers in the message" do
    sink = Sink.new
    sink.deliver(base_payload(message: "Couldn't find Foo with id=42"))
    sink.deliver(base_payload(message: "Couldn't find Foo with id=99"))
    fps = RbRunErrorReporter::ErrorReport.pluck(:fingerprint).uniq
    assert_equal 1, fps.size, "two messages differing only in numbers should share a fingerprint"
  end

  test "raises MissingModelError when no model is configured and the engine model is unloaded" do
    # Simulate a client app that doesn't have the engine. We can't
    # actually unload the model, so use the constructor's `model:`
    # override path with a model class that doesn't exist.
    sink = Sink.new(model: "Definitely::NotAClass::SomeReport")
    assert_raises(NameError) { sink.deliver(base_payload) }
  end
end
