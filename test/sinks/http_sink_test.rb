require "test_helper"

class RbRunErrorReporter::Sdk::Ruby::Sinks::HttpSinkTest < ActiveSupport::TestCase
  Sink   = RbRunErrorReporter::Sdk::Ruby::Sinks::HttpSink
  Worker = RbRunErrorReporter::Sdk::Ruby::BackgroundWorker

  # Synchronous worker = ImmediateExecutor = the request hits WebMock
  # before `deliver` returns, so we can assert on stubs without races.
  def sync_worker; Worker.new(threads: 0); end

  def payload
    {
      schema_version:  1,
      exception_class: "RuntimeError",
      message:         "boom",
      occurred_at:     Time.now.utc.iso8601,
      environment:     "test",
      source:          "test"
    }
  end

  test "validates endpoint and token at construction" do
    assert_raises(ArgumentError) { Sink.new(endpoint: "not a url", token: "t") }
    assert_raises(ArgumentError) { Sink.new(endpoint: "https://x/y", token: "") }
    assert_raises(ArgumentError) { Sink.new(endpoint: "https://x/y", token: nil) }
  end

  test "POSTs JSON with Authorization bearer header" do
    stub = WebMock.stub_request(:post, "https://collector.example/errors")
                  .with(headers: {
                    "Authorization" => "Bearer abc123",
                    "Content-Type"  => "application/json"
                  })
                  .to_return(status: 202, body: '{"status":"accepted"}')

    sink = Sink.new(endpoint: "https://collector.example/errors", token: "abc123", worker: sync_worker)
    sink.deliver(payload)

    assert_requested stub
  end

  test "body is the JSON-serialized payload" do
    captured = nil
    WebMock.stub_request(:post, "https://collector.example/errors")
           .with { |req| captured = req.body; true }
           .to_return(status: 202)

    sink = Sink.new(endpoint: "https://collector.example/errors", token: "t", worker: sync_worker)
    sink.deliver(payload)

    parsed = JSON.parse(captured)
    assert_equal "RuntimeError", parsed["exception_class"]
    assert_equal 1, parsed["schema_version"]
  end

  test "gzips bodies above the threshold" do
    big = payload.merge(extra: { large: "x" * 40_000 })
    captured_body = nil
    captured_encoding = nil
    WebMock.stub_request(:post, "https://collector.example/errors")
           .with { |req|
             captured_body     = req.body
             captured_encoding = req.headers["Content-Encoding"]
             true
           }
           .to_return(status: 202)

    sink = Sink.new(endpoint: "https://collector.example/errors", token: "t", worker: sync_worker)
    sink.deliver(big)

    assert_equal "gzip", captured_encoding
    # Round-trip the gzip and confirm it's the same JSON we sent.
    json = Zlib.gunzip(captured_body)
    assert_equal "RuntimeError", JSON.parse(json)["exception_class"]
  end

  test "429 with Retry-After triggers backoff and drops next report" do
    WebMock.stub_request(:post, "https://collector.example/errors")
           .to_return(status: 429, headers: { "Retry-After" => "120" })

    sink = Sink.new(endpoint: "https://collector.example/errors", token: "t", worker: sync_worker)
    sink.deliver(payload)
    assert sink.backed_off?

    # Now the next deliver should NOT hit the network (worker not even called).
    refute sink.deliver(payload)
  end

  test "transport errors do not raise — funnel survives" do
    WebMock.stub_request(:post, "https://collector.example/errors")
           .to_raise(Errno::ECONNREFUSED)

    sink = Sink.new(endpoint: "https://collector.example/errors", token: "t", worker: sync_worker)
    assert_nothing_raised { sink.deliver(payload) }
  end

  test "401/403/5xx are logged and dropped, no raise" do
    [401, 500].each do |code|
      WebMock.reset!
      WebMock.stub_request(:post, "https://collector.example/errors").to_return(status: code)
      sink = Sink.new(endpoint: "https://collector.example/errors", token: "t", worker: sync_worker)
      assert_nothing_raised { sink.deliver(payload) }
    end
  end
end
