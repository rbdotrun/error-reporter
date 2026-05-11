class CreateIngestionCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :ingestion_credentials, id: :uuid do |t|
      # Human label, e.g. "appA-prod". Used as default source_app when
      # an incoming payload omits one.
      t.string :name, null: false

      # SHA256 of the raw token. We never store plaintext — `.issue!`
      # is the only place the plaintext exists, and only briefly.
      t.string :token_digest, null: false

      # UI hint only — never used for authentication.
      t.string :token_last_four, null: false

      # Soft-revoke. Null = active. Setting this once disables the
      # credential; we keep the row for audit / last_used_at history.
      t.datetime :revoked_at

      # Throttled to one write per minute per credential by the model.
      t.datetime :last_used_at

      t.timestamps
    end

    add_index :ingestion_credentials, :name, unique: true
    add_index :ingestion_credentials, :token_digest, unique: true
  end
end
