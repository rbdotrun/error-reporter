require "active_support/core_ext/integer/time"

ExampleClient::Application.configure do
  config.cache_classes      = false
  config.eager_load         = false
  config.consider_all_requests_local = true

  config.active_job.queue_adapter = :async
end
