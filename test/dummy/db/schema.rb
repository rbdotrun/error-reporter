# Test schema for the dummy host app. Kept in sync with the engine's
# real migrations (db/migrate/) — we load this directly instead of
# running migrations in the test boot to keep test setup fast and
# deterministic.
#
# Includes both:
#   * engine tables (error_reports, ingestion_credentials)
#   * test-stub tables (users, workspaces, memberships) — minimal
#     versions that exist purely so PayloadBuilder + ActiveJob context
#     extraction can be exercised end-to-end. Real client apps have
#     their own User/Workspace; these stubs are not the reference.

ActiveRecord::Schema[Rails::VERSION::STRING.to_f].define(version: 0) do
  enable_extension "pgcrypto"

  # ---- Engine tables ----------------------------------------------------

  create_table :error_reports, id: :uuid, force: true do |t|
    t.string  :fingerprint, null: false
    t.string  :exception_class, null: false
    t.text    :message
    t.string  :environment, null: false
    t.string  :release
    t.string  :source
    t.string  :source_app
    t.uuid    :user_id
    t.uuid    :workspace_id
    t.jsonb   :payload, null: false, default: {}
    t.datetime :occurred_at, null: false
    t.timestamps

    t.index :fingerprint
    t.index :exception_class
    t.index :occurred_at
    t.index [:workspace_id, :occurred_at]
    t.index [:source_app, :occurred_at]
  end

  create_table :ingestion_credentials, id: :uuid, force: true do |t|
    t.string   :name, null: false
    t.string   :token_digest, null: false
    t.string   :token_last_four, null: false
    t.datetime :revoked_at
    t.datetime :last_used_at
    t.timestamps

    t.index :name, unique: true
    t.index :token_digest, unique: true
  end

  # ---- Test-stub tables -------------------------------------------------

  create_table :users, id: :uuid, force: true do |t|
    t.string :email
    t.string :name
    t.timestamps
  end

  create_table :workspaces, id: :uuid, force: true do |t|
    t.string :slug
    t.string :name
    t.timestamps
  end

  create_table :memberships, id: :uuid, force: true do |t|
    t.references :user,      type: :uuid, null: false, foreign_key: true
    t.references :workspace, type: :uuid, null: false, foreign_key: true
    t.string :role
    t.timestamps
  end
end
