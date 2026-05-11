RbRunErrorReporter.configure do |c|
  c.environment = Rails.env

  # The collector-host itself uses DatabaseSink for its own errors —
  # no HTTP hop to itself.
  c.sink = RbRunErrorReporter::Sdk::Ruby::Sinks::DatabaseSink.new
end
