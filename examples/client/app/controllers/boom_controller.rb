class BoomController < ApplicationController
  # The whole point of the example: this route raises. The SDK's Rack
  # middleware catches it, builds a payload, and HttpSink POSTs it to
  # the host. After the response (a 500), `RbRunErrorReporter::ErrorReport.last`
  # on the host shows the new row.
  def crash
    raise "boom from example client at #{Time.now.iso8601}"
  end
end
