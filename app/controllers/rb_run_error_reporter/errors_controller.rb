require "zlib"
require "stringio"

module RbRunErrorReporter
  # Ingestion endpoint for the collector. Mounted at
  # `<engine_mount>/errors` (see config/routes.rb). Auth via
  # `Authorization: Bearer <token>`, validated against the
  # `IngestionCredential` table.
  #
  # Wire format is documented in WIRE_PROTOCOL.md — this controller is
  # the reference implementation.
  class ErrorsController < ApplicationController
    SUPPORTED_SCHEMA_VERSIONS = [1].freeze

    # The size cap is enforced in two places: the request layer (here,
    # reads Content-Length) and as a defensive check on the materialized
    # body. Both are needed because Content-Length can be missing or
    # lie, and we don't want to materialize a 10 GiB body just to
    # reject it.
    def create
      return render_error(401, "unauthorized") unless authenticate_credential

      raw_body = read_body
      return render_error(413, "payload_too_large") if raw_body.nil?

      payload = parse_json(raw_body)
      return render_error(400, "malformed_json") if payload.nil?

      reason = validate(payload)
      return render_error(400, reason) if reason

      payload = symbolize_top_level(payload)
      payload[:source_app] ||= @credential.name

      report = sink.deliver(payload)
      render json: { status: "accepted", id: report&.id }, status: :accepted
    rescue StandardError => e
      Rails.logger.error("[RbRunErrorReporter::ErrorsController] #{e.class}: #{e.message}") if defined?(Rails)
      render_error(500, "internal_error")
    end

    private

      # Bearer token comparison routes through `IngestionCredential.authenticate`,
      # which does the SHA256 digest lookup and the throttled
      # `last_used_at` update.
      def authenticate_credential
        header = request.headers["Authorization"].to_s
        return false unless header.start_with?("Bearer ")

        token = header.sub(/\ABearer\s+/, "").strip
        @credential = IngestionCredential.authenticate(token)
        !@credential.nil?
      end

      def read_body
        max = RbRunErrorReporter.configuration.max_payload_bytes
        content_length = request.content_length
        return nil if content_length && content_length > max

        body = request.body.read(max + 1)
        return nil if body.nil?
        return nil if body.bytesize > max

        if request.headers["Content-Encoding"].to_s.downcase.include?("gzip")
          begin
            body = Zlib.gunzip(body)
          rescue Zlib::Error
            return nil
          end
          return nil if body.bytesize > max
        end

        body
      end

      def parse_json(raw)
        JSON.parse(raw)
      rescue JSON::ParserError
        nil
      end

      # Returns a string reason (`schema_version_unsupported` or
      # `missing_field:<f>`) when invalid, nil when fine.
      def validate(payload)
        return "malformed_json" unless payload.is_a?(Hash)

        schema = payload["schema_version"]
        return "schema_version_unsupported" unless SUPPORTED_SCHEMA_VERSIONS.include?(schema)

        %w[exception_class message occurred_at environment source].each do |field|
          return "missing_field:#{field}" if payload[field].nil? || payload[field].to_s.empty?
        end
        nil
      end

      # The DatabaseSink expects symbol keys (same shape the SDK's
      # PayloadBuilder produces). Top-level only — `payload["request"]`
      # and `payload["extra"]` stay string-keyed inside the JSONB column,
      # which is the natural representation for nested user data.
      def symbolize_top_level(payload)
        payload.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
      end

      def sink
        @sink ||= Sdk::Ruby::Sinks::DatabaseSink.new
      end

      def render_error(status, reason)
        render json: { status: "error", reason: }, status:
      end
  end
end
