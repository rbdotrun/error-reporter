require "active_support/core_ext/integer/time"

Dummy::Application.configure do
  config.cache_classes = true
  config.eager_load = false

  config.consider_all_requests_local = true
  config.cache_store = :null_store

  config.action_controller.perform_caching = false
  config.action_controller.allow_forgery_protection = false

  config.active_support.deprecation = :stderr

  config.active_job.queue_adapter = :test

  # Skip Rails' auto-schema maintenance. We load test/dummy/db/schema.rb
  # explicitly in test_helper.rb (every `create_table` uses `force: true`
  # so the load is idempotent). Without this, `require "rails/test_help"`
  # fires `ActiveRecord::Migration.maintain_test_schema!` which looks for
  # `config/database.yml` relative to a path Rails can't resolve in the
  # gem-repo + dummy-app layout, and the whole test run aborts before
  # anything assertable runs.
  config.active_record.maintain_test_schema = false
end
