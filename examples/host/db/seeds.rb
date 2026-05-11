# Idempotently provisions one IngestionCredential whose plaintext token
# matches $ERROR_REPORTER_TOKEN. The example client (whose HttpSink uses
# the same env var) can then immediately authenticate against this host
# — no manual `issue!` step.
#
# Real operator workflow is the opposite direction: call `.issue!`,
# capture the returned plaintext, deliver it to the client out of band.
# This shortcut exists ONLY because the example token is pre-shared in
# `.env` for demonstration purposes.

token = ENV.fetch("ERROR_REPORTER_TOKEN")
digest = RbRunErrorReporter::IngestionCredential.digest_for(token)

cred = RbRunErrorReporter::IngestionCredential.find_or_initialize_by(token_digest: digest)
cred.name             = "example-client"
cred.token_last_four  = token.last(4)
cred.revoked_at       = nil
cred.save!

puts "[seed] ensured IngestionCredential name=#{cred.name} last_four=#{cred.token_last_four}"
