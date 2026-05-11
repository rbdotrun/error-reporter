ENV["RAILS_ENV"] ||= "test"

require_relative "dummy/config/environment"
require "rails/test_help"
require "webmock/minitest"
require "minitest/autorun"

# Build the test DB from test/dummy/db/schema.rb on every test process
# boot. Every `create_table` in there uses `force: true`, so this is
# idempotent and survives re-runs without explicit teardown.
ActiveRecord::Schema.verbose = false
load File.expand_path("dummy/db/schema.rb", __dir__)

# Block real network. HttpSink tests stub via WebMock; any unstubbed
# call raises loudly — matches rbrun's convention so silent leaks
# can't happen.
WebMock.disable_net_connect!(allow_localhost: true)

module ActiveSupport
  class TestCase
    # Wipe Current between tests so a leak in one doesn't poison
    # downstream assertions.
    teardown do
      Current.user = nil if defined?(::Current)
      Current.workspace = nil if defined?(::Current)
      Current.membership = nil if defined?(::Current)
    end
  end
end
