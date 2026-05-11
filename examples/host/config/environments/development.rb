require "active_support/core_ext/integer/time"

ExampleHost::Application.configure do
  config.cache_classes      = false
  config.eager_load         = false
  config.consider_all_requests_local = true

  config.active_record.maintain_test_schema = false

  config.active_job.queue_adapter = :async

  # Allow the docker-network service name. Rails 8's
  # ActionDispatch::HostAuthorization defaults reject anything that
  # isn't localhost/127.0.0.1 in dev — including the docker-compose
  # service hostnames the client uses to reach us. Without this, the
  # client gets 403 back from every report and the demo fails
  # silently except for "unexpected response 403" SDK warnings.
  config.hosts << "host"
  config.hosts << "localhost"
end
