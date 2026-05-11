require "test_helper"
require "stringio"
require "logger"

class RbRunErrorReporter::Sdk::Ruby::Sinks::LogSinkTest < ActiveSupport::TestCase
  Sink = RbRunErrorReporter::Sdk::Ruby::Sinks::LogSink

  test "writes a single JSON line at error level" do
    io = StringIO.new
    sink = Sink.new(logger: Logger.new(io))
    sink.deliver({ exception_class: "RuntimeError", message: "boom", schema_version: 1 })
    io.rewind
    line = io.read
    assert_match(/ERROR/, line)
    assert_match(/\[RbRunErrorReporter\]/, line)
    assert_match(/"exception_class":"RuntimeError"/, line)
  end
end
