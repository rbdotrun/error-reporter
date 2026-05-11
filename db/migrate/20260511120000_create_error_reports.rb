class CreateErrorReports < ActiveRecord::Migration[8.1]
  def change
    create_table :error_reports, id: :uuid do |t|
      # Stable identity for grouping. SDK side computes the same hash so
      # the same exception+message+top-of-stack always lands on the same
      # fingerprint (numeric-neutralized message so paginations and
      # primary keys don't fragment the group).
      t.string :fingerprint, null: false

      t.string :exception_class, null: false
      t.text   :message
      t.string :environment, null: false
      t.string :release
      t.string :source

      # Identifies the source app when reported via HttpSink. Null for
      # direct DatabaseSink writes from the collector host itself.
      t.string :source_app

      # Opaque identifiers from the reporting app's user / tenant model.
      # NO foreign keys — the collector accepts errors from any number
      # of apps, each with their own user table.
      t.uuid :user_id
      t.uuid :workspace_id

      t.jsonb     :payload, null: false, default: {}
      t.datetime  :occurred_at, null: false
      t.timestamps
    end

    add_index :error_reports, :fingerprint
    add_index :error_reports, :exception_class
    add_index :error_reports, :occurred_at
    add_index :error_reports, [:workspace_id, :occurred_at]
    add_index :error_reports, [:source_app, :occurred_at]
  end
end
