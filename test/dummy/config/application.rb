require_relative "boot"

# Pull in only the Rails sub-frameworks the engine actually exercises.
# The collector is JSON-only; no view layer, no mailer, no Action Cable,
# no Active Storage. Keep the boot fast.
require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "active_job/railtie"
require "action_controller/railtie"

Bundler.require(*Rails.groups)

# Loads the engine code from ../../lib via the gem's gemspec.
require "rbrun_error_reporter"

module Dummy
  # Standalone host app for testing the rbrun-error-reporter engine in
  # isolation. Mirrors the standard `test/dummy/` pattern that
  # `rails plugin new --mountable` generates. Real client apps are
  # NOT supposed to look like this — this is purely a Rails harness
  # so we can exercise the engine without dragging in rbrun.
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f
    config.eager_load = false
    config.active_support.deprecation = :stderr

    # Logs to stderr at warn level — keeps test output clean while still
    # surfacing real problems.
    config.logger = Logger.new($stderr)
    config.log_level = :warn
  end
end
