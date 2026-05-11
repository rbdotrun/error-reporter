RbRunErrorReporter.configure do |c|
  c.environment = Rails.env

  c.sink = RbRunErrorReporter::Sdk::Ruby::Sinks::HttpSink.new(
    endpoint: ENV.fetch("ERROR_REPORTER_ENDPOINT"),
    token:    ENV.fetch("ERROR_REPORTER_TOKEN"),

    # Synchronous delivery in this demo so `curl /boom` returns AFTER
    # the report has been persisted on the host — makes the demo
    # deterministic. Real clients use the default (async, 2 threads).
    worker: RbRunErrorReporter::Sdk::Ruby::BackgroundWorker.new(threads: 0)
  )
end
