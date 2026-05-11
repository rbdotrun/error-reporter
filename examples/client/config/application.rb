require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "action_controller/railtie"
# Skip active_record/railtie — the client has no database.

Bundler.require(*Rails.groups)

require "rbrun_error_reporter"

module ExampleClient
  # Minimal Rails app that demonstrates the SDK install + HttpSink
  # config. Has one route: GET /boom, which raises. The SDK captures
  # the raise, POSTs to the host (via HttpSink), and the host persists
  # it. Real client apps look exactly like this — just bigger.
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f
    config.eager_load = false
    config.api_only   = true

    config.logger    = Logger.new($stdout)
    config.log_level = :info
  end
end
