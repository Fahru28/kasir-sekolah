# The dummy app's schema.rb only carries the releases table and the engine's migrations
# are deliberately not auto-loaded, so specs that render the feedback views have to stand
# up the tables those views touch.
#
# Build them ADDITIVELY: the sqlite test DB persists between runs and other specs create
# narrower versions of the same tables, so `unless table_exists?` would silently skip a
# richer definition and you'd get `unknown attribute`. Create if absent, then top up any
# missing columns.
module LlamaBotRails
  module SpecSupport
    module FeedbackTables
      FEEDBACK_COLUMNS = {
        title: :string,
        description: :text,
        feedback_type: :string,
        status: :string,
        priority: :integer,
        user_id: :integer,
        user_email: :string,
        admin_notes: :text,
        resolution: :string,
        resolved_at: :datetime,
        selected_element_html: :text,
        selected_element_selector: :string,
        selected_element_url: :string
      }.freeze

      def self.build!
        conn = ActiveRecord::Base.connection

        unless conn.table_exists?(:llama_bot_rails_user_feedbacks)
          conn.create_table :llama_bot_rails_user_feedbacks do |t|
            t.string :title, null: false
            t.string :feedback_type, null: false, default: 'general'
            t.string :status, null: false, default: 'open'
            t.integer :user_id, null: false
            t.timestamps
          end
        end

        FEEDBACK_COLUMNS.each do |column, type|
          next if conn.column_exists?(:llama_bot_rails_user_feedbacks, column)
          conn.add_column :llama_bot_rails_user_feedbacks, column, type
        end
        LlamaBotRails::UserFeedback.reset_column_information

        unless conn.table_exists?(:llama_bot_rails_tags)
          conn.create_table :llama_bot_rails_tags do |t|
            t.string :name, null: false
            t.string :color
            t.timestamps
          end
        end

        unless conn.table_exists?(:llama_bot_rails_taggings)
          conn.create_table :llama_bot_rails_taggings do |t|
            t.references :tag, null: false
            t.references :taggable, polymorphic: true, null: false
            t.timestamps
          end
        end

        unless conn.table_exists?(:llama_bot_rails_feedback_comments)
          conn.create_table :llama_bot_rails_feedback_comments do |t|
            t.references :commentable, polymorphic: true, null: false
            t.text :body, null: false
            t.integer :user_id
            t.string :author_name
            t.boolean :is_admin_response, default: false
            t.integer :parent_id
            t.text :mentioned_user_ids
            t.timestamps
          end
        end

        unless conn.table_exists?(:llama_bot_rails_notifications)
          conn.create_table :llama_bot_rails_notifications do |t|
            t.integer :user_id, null: false
            t.integer :actor_id
            t.references :notifiable, polymorphic: true
            t.string :notification_type
            t.text :message
            t.text :metadata
            t.datetime :read_at
            t.timestamps
          end
        end

        unless conn.table_exists?(:active_storage_blobs)
          conn.create_table :active_storage_blobs do |t|
            t.string :key, null: false
            t.string :filename, null: false
            t.string :content_type
            t.text :metadata
            t.string :service_name, null: false
            t.bigint :byte_size, null: false
            t.string :checksum
            t.datetime :created_at, null: false
          end
          conn.add_index :active_storage_blobs, :key, unique: true
        end

        unless conn.table_exists?(:active_storage_attachments)
          conn.create_table :active_storage_attachments do |t|
            t.string :name, null: false
            t.references :record, polymorphic: true, null: false
            t.bigint :blob_id, null: false
            t.datetime :created_at, null: false
          end
          conn.add_index :active_storage_attachments,
                         [:record_type, :record_id, :name, :blob_id],
                         name: 'index_active_storage_attachments_uniqueness', unique: true
        end

        unless conn.table_exists?(:active_storage_variant_records)
          conn.create_table :active_storage_variant_records do |t|
            t.bigint :blob_id, null: false
            t.string :variation_digest, null: false
          end
        end
      end

      # Direct messaging (Conversation / ConversationParticipant / DirectMessage).
      # Split from build! because only the messaging specs need it; same additive
      # rule applies — create if absent, and the sqlite test DB persists.
      def self.build_messaging!
        build! # notifications live there, and a message creates one

        conn = ActiveRecord::Base.connection

        unless conn.table_exists?(:llama_bot_rails_conversations)
          conn.create_table :llama_bot_rails_conversations do |t|
            t.string :title
            t.string :conversation_type, null: false, default: 'direct'
            t.timestamps
          end
        end

        unless conn.table_exists?(:llama_bot_rails_conversation_participants)
          conn.create_table :llama_bot_rails_conversation_participants do |t|
            t.integer :conversation_id, null: false
            t.integer :user_id, null: false
            t.datetime :last_read_at
            t.boolean :muted, default: false
            t.datetime :joined_at, null: false
            t.timestamps
          end
        end

        unless conn.table_exists?(:llama_bot_rails_direct_messages)
          conn.create_table :llama_bot_rails_direct_messages do |t|
            t.integer :conversation_id, null: false
            t.integer :sender_id, null: false
            t.text :body, null: false
            t.datetime :edited_at
            t.timestamps
          end
        end
      end

      # The dummy app sets `include_all_helpers = false`, so the engine's view helpers are
      # not auto-mixed into the controller the way they are under Rails' default (which is
      # what real host apps run). Wire them up so the views can actually render.
      def self.wire_helpers!(controller)
        controller.helper(
          LlamaBotRails::ApplicationHelper,
          LlamaBotRails::FeedbackHelper,
          LlamaBotRails::SsoHelper
        )
      end
    end
  end
end
