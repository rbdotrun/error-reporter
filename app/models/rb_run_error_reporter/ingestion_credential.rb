require "openssl"
require "securerandom"
require "digest"

module RbRunErrorReporter
  # Bearer-token credential for the collector's POST /errors endpoint.
  #
  # Storage rule: **plaintext tokens are never persisted.** We store
  # `token_digest` (SHA256 hex) and `token_last_four` (display hint).
  # The plaintext token is returned exactly once — at `.issue!` time —
  # and must be copied to the client app's config then. There is no
  # way to recover it later; if lost, revoke and re-issue.
  #
  # Operator UX (via Rails console, no admin UI in v1):
  #
  #   cred = RbRunErrorReporter::IngestionCredential.issue!(name: "appA-prod")
  #   cred[:token]   # => "rbreport_v1_..." -- copy this NOW
  #   cred[:credential].id
  #
  #   cred[:credential].revoke!
  class IngestionCredential < ApplicationRecord
    self.table_name = "ingestion_credentials"

    # Throttle `last_used_at` writes. Without this every accepted POST
    # writes a row update, which is fine at low volume but turns into
    # write amplification at high volume. One write/minute/credential
    # is plenty for "is this still in use".
    LAST_USED_AT_WRITE_INTERVAL = 60

    TOKEN_PREFIX = "rbreport_v1_".freeze

    validates :name,         presence: true, uniqueness: { case_sensitive: false }
    validates :token_digest, presence: true, uniqueness: true

    scope :active, -> { where(revoked_at: nil) }

    # Issue a new credential. Returns a hash:
    #
    #   { credential: <IngestionCredential>, token: "<raw>" }
    #
    # The raw token is the value the client app must put in its
    # HttpSink configuration. We never store it.
    def self.issue!(name:)
      raw = generate_token
      cred = create!(
        name:,
        token_digest:     digest_for(raw),
        token_last_four:  raw.last(4)
      )
      { credential: cred, token: raw }
    end

    # Constant-time lookup for a presented bearer token. Returns the
    # active (non-revoked) credential or nil. Updates `last_used_at`
    # (throttled) on success.
    def self.authenticate(presented_token)
      return nil if presented_token.to_s.empty?

      digest = digest_for(presented_token)
      cred = active.where(token_digest: digest).first
      cred&.touch_last_used_at
      cred
    end

    def revoke!
      update!(revoked_at: Time.current) if revoked_at.nil?
    end

    def revoked?
      !revoked_at.nil?
    end

    def touch_last_used_at
      now = Time.current
      return if last_used_at && (now - last_used_at) < LAST_USED_AT_WRITE_INTERVAL

      update_column(:last_used_at, now)
    end

    def self.digest_for(raw)
      OpenSSL::Digest::SHA256.hexdigest(raw)
    end

    def self.generate_token
      # 32 bytes of randomness → 43 base64url chars. Plenty of entropy,
      # short enough to copy in one line. Prefixed for grep-ability in
      # accidentally-leaked logs.
      "#{TOKEN_PREFIX}#{SecureRandom.urlsafe_base64(32)}"
    end
  end
end
