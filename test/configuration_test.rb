require "test_helper"

class RbRunErrorReporter::Sdk::Ruby::ConfigurationTest < ActiveSupport::TestCase
  setup do
    @config = RbRunErrorReporter::Sdk::Ruby::Configuration.new
  end

  test "ships with sensible defaults — but no sink (host must wire one)" do
    assert @config.enabled
    assert_nil @config.sink
    assert_equal 0, @config.dedup_window_seconds
    assert_includes @config.pii_fields, "password"
    assert_includes @config.ignored_exceptions, "ActiveRecord::RecordNotFound"
  end

  test "max_payload_bytes is 1 MiB by default" do
    assert_equal 1_048_576, @config.max_payload_bytes
  end

  test "ignore? matches by exact class name" do
    exc = ActionController::RoutingError.new("no route")
    assert @config.ignore?(exc)
  end

  test "ignore? matches by ancestor — subclass of an ignored class is ignored" do
    custom = Class.new(ActiveRecord::RecordNotFound)
    Object.const_set(:CustomMissingThing, custom)
    assert @config.ignore?(custom.new("nope"))
  ensure
    Object.send(:remove_const, :CustomMissingThing) if defined?(::CustomMissingThing)
  end

  test "ignore? respects ignored_paths" do
    @config.ignored_paths = [ %r{\A/skip/me} ]
    assert @config.ignore?(RuntimeError.new, path: "/skip/me/here")
    refute @config.ignore?(RuntimeError.new, path: "/keep")
  end
end
