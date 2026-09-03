# The dummy app's schema.rb only carries the releases table, so specs that touch
# ActivityEvent have to stand up the table themselves. Same rules as
# spec/support/feedback_tables.rb: build ADDITIVELY, because the sqlite test DB
# persists between runs and a narrower version may already be there.
module LlamaBotRails
  module SpecSupport
    module ActivityTables
      COLUMNS = {
        event_type: :string,
        occurred_at: :datetime,
        actor_type: :string,
        actor_id: :string,
        actor_label: :string,
        subject_type: :string,
        subject_id: :string,
        subject_label: :string,
        workspace_id: :string,
        source: :string,
        request_id: :string,
        correlation_id: :string,
        parent_event_id: :bigint,
        controller: :string,
        action: :string,
        job_class: :string,
        job_id: :string,
        trigger_type: :string,
        trigger_name: :string,
        human: :boolean,
        changed_records_count: :integer,
        metadata: :json
      }.freeze

      # Matches the migration, so a row created without them behaves like one
      # written by the gem in a real app.
      DEFAULTS = {
        human: { default: false },
        changed_records_count: { default: 0 },
        metadata: { default: {} }
      }.freeze

      def self.build!
        conn = ActiveRecord::Base.connection

        unless conn.table_exists?(:llama_bot_rails_activity_events)
          conn.create_table :llama_bot_rails_activity_events do |t|
            t.string :event_type, null: false
            t.datetime :occurred_at, null: false
            t.string :source, null: false, default: "system"
            t.datetime :created_at, null: false
          end
        end

        COLUMNS.each do |column, type|
          next if conn.column_exists?(:llama_bot_rails_activity_events, column)

          conn.add_column :llama_bot_rails_activity_events, column, type, **DEFAULTS.fetch(column, {})
        end

        LlamaBotRails::ActivityEvent.reset_column_information
        LlamaBotRails::ActivityEvent.reset_availability!
      end
    end
  end
end
