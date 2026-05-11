require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "active_job/railtie"
require "action_controller/railtie"

Bundler.require(*Rails.groups)

require "rbrun_error_reporter"

module ExampleHost
  # Minimal Rails app that mounts the rbrun-error-reporter engine and
  # persists incoming reports to PostgreSQL. Intended only to demonstrate
  # the end-to-end flow — real operator hosts (rbrun itself, eventually
  # any self-hoster) wire the engine into their existing app, they don't
  # stand up a dedicated process for it.
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f
    config.eager_load = false
    config.api_only   = true

    config.logger    = Logger.new($stdout)
    config.log_level = :info
  end
end
