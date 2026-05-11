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
end
