require "net/http"
require "uri"
require "json"
require "zlib"
require "stringio"
require "concurrent/atomic/atomic_reference"

module RbRunErrorReporter
  module Sdk
    module Ruby
      module Sinks
        # POSTs payloads to a collector that has mounted
        # `RbRunErrorReporter::Engine`. See WIRE_PROTOCOL.md for the
        # cross-language contract this sink implements.
        #
        # Design notes (informed by sentry-ruby's `HTTPTransport`):
        #
        #   * **stdlib only** — `Net::HTTP`, no Faraday dependency. The
        #     SDK should leak as few deps as possible into client apps.
        #
        #   * **async by default** — delivery is submitted to a
        #     `BackgroundWorker`. The host's request thread doesn't
        #     wait on network I/O. Pass `worker:` to swap in your own
        #     (immediate executor for tests, larger pool for high traffic).
        #
        #   * **no retries** — a reporter that hangs is worse than one
        #     that drops events. On any transport error: log + drop.
        #
        #   * **gzip above threshold** — compresses bodies > 30 KB.
        #
        #   * **429 / Retry-After** — sets a backoff deadline; reports
        #     submitted while backed off are dropped.
        #
        #   * **never raises** — the worker block is `rescue StandardError`'d,
        #     so a misconfigured endpoint or a flaky network can't crash
        #     the host process. Reporter#capture is also rescued, but
        #     defense in depth.
        class HttpSink
          GZIP_THRESHOLD_BYTES = 30 * 1024
          DEFAULT_OPEN_TIMEOUT = 2
          DEFAULT_READ_TIMEOUT = 5
          DEFAULT_WRITE_TIMEOUT = 5
          RETRY_AFTER_DEFAULT_SECONDS = 60

          # Errors `Net::HTTP` is known to raise on the wire. List
          # lifted from sentry-ruby (which lifted it from Bundler).
          HTTP_ERRORS = [
            Timeout::Error,
            EOFError,
            SocketError,
            Errno::ENETDOWN,
            Errno::ENETUNREACH,
            Errno::EINVAL,
            Errno::ECONNRESET,
            Errno::ETIMEDOUT,
            Errno::EAGAIN,
            Net::HTTPBadResponse,
            Net::HTTPHeaderSyntaxError,
            Net::ProtocolError,
            Zlib::BufError,
            Errno::EHOSTUNREACH,
            Errno::ECONNREFUSED
          ].freeze

          attr_reader :endpoint

          def initialize(endpoint:,
                         token:,
                         worker: BackgroundWorker.new,
                         open_timeout: DEFAULT_OPEN_TIMEOUT,
                         read_timeout: DEFAULT_READ_TIMEOUT,
                         write_timeout: DEFAULT_WRITE_TIMEOUT,
                         user_agent: default_user_agent,
                         logger: nil)
            @endpoint =
              begin
                URI.parse(endpoint)
              rescue URI::InvalidURIError => e
                raise ArgumentError, "HttpSink endpoint is not a valid URL (#{endpoint.inspect}): #{e.message}"
              end
            unless @endpoint.is_a?(URI::HTTP) || @endpoint.is_a?(URI::HTTPS)
              raise ArgumentError, "HttpSink endpoint must be an http(s) URL, got #{endpoint.inspect}"
            end
            raise ArgumentError, "HttpSink token must be a non-empty string" if token.to_s.empty?

            @token         = token
            @worker        = worker
            @open_timeout  = open_timeout
            @read_timeout  = read_timeout
            @write_timeout = write_timeout
            @user_agent    = user_agent
            @logger        = logger
            @backoff_until = Concurrent::AtomicReference.new(nil)
          end

          def deliver(payload)
            if backed_off?
              log_warn("HttpSink: dropping report while backed off until #{@backoff_until.get}")
              return false
            end

            @worker.submit { perform_post(payload) }
          end

          def flush
            @worker.shutdown if @worker.respond_to?(:shutdown)
          end

          # Exposed for tests / metrics.
          def backed_off?
            deadline = @backoff_until.get
            deadline && Time.now < deadline
          end

          private

            def perform_post(payload)
              body, encoding = serialize_body(payload)
              response = post(body, encoding)

              case response.code
              when /\A2/
                # Stored.
              when "429"
                honor_retry_after(response)
              when "413"
                log_warn("HttpSink: 413 payload_too_large; dropping report (#{body.bytesize} bytes)")
              when "401"
                log_warn("HttpSink: 401 unauthorized; check the configured bearer token")
              else
                log_warn("HttpSink: unexpected response #{response.code}: #{response.body}")
              end
            rescue *HTTP_ERRORS => e
              log_warn("HttpSink: network error #{e.class}: #{e.message}")
            rescue StandardError => e
              log_warn("HttpSink: unexpected error #{e.class}: #{e.message}")
            end

            def serialize_body(payload)
              json = JSON.generate(payload)
              if json.bytesize >= GZIP_THRESHOLD_BYTES
                [Zlib.gzip(json), "gzip"]
              else
                [json, nil]
              end
            end

            def post(body, encoding)
              req = Net::HTTP::Post.new(@endpoint.request_uri)
              req["Authorization"]    = "Bearer #{@token}"
              req["Content-Type"]     = "application/json"
              req["Content-Encoding"] = encoding if encoding
              req["User-Agent"]       = @user_agent
              req.body = body

              http = Net::HTTP.new(@endpoint.host, @endpoint.port)
              http.use_ssl = @endpoint.scheme == "https"
              http.open_timeout  = @open_timeout
              http.read_timeout  = @read_timeout
              http.write_timeout = @write_timeout if http.respond_to?(:write_timeout=)
              http.request(req)
            end

            def honor_retry_after(response)
              seconds = parse_retry_after(response["retry-after"])
              deadline = Time.now + seconds
              @backoff_until.set(deadline)
              log_warn("HttpSink: 429 rate_limited; backing off until #{deadline}")
            end

            # Per RFC 7231 the value may be an integer seconds count OR an
            # HTTP-date. We accept the integer form and fall back to a
            # sane default — the date form is rare in practice.
            def parse_retry_after(header)
              n = header.to_i
              n > 0 ? n : RETRY_AFTER_DEFAULT_SECONDS
            end

            def log_warn(msg)
              logger&.warn("[RbRunErrorReporter] #{msg}")
            end

            def logger
              @logger ||= (defined?(Rails) && Rails.respond_to?(:logger) ? Rails.logger : nil)
            end

            def default_user_agent
              "rbrun-error-reporter-ruby/#{RbRunErrorReporter::VERSION}"
            end
        end
      end
    end
  end
end
