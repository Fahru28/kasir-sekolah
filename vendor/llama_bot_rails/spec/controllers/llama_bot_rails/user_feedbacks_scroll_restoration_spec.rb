require 'rails_helper'

# Pins the markup contract behind "don't lose my scroll spot when I click into a
# feedback card and come back": the index gives every card an anchorable id, and
# the show page's back link targets that anchor. The anchor is the fallback path —
# when the user actually came from the index, the inline handler calls
# history.back() instead and the browser restores the scroll position itself.
#
# The dummy app's schema.rb only carries the releases table and the engine's
# migrations are deliberately not auto-loaded, so this spec stands up the tables
# the views touch (same approach as the feedback comments spec).
RSpec.describe LlamaBotRails::UserFeedbacksController, type: :controller do
  routes { LlamaBotRails::Engine.routes }
  render_views

  before(:all) do
    conn = ActiveRecord::Base.connection

    unless conn.table_exists?(:llama_bot_rails_user_feedbacks)
      conn.create_table :llama_bot_rails_user_feedbacks do |t|
        t.string :title, null: false
        t.text :description
        t.string :feedback_type, null: false, default: 'general'
        t.string :status, null: false, default: 'open'
        t.integer :priority, default: 0
        t.integer :user_id, null: false
        t.timestamps
      end
    end

    # The sqlite test DB persists between runs and other specs stand up a narrower
    # version of this table, so top up whatever columns are missing rather than
    # assuming we won the race to create it.
    {
      user_email: :string,
      admin_notes: :text,
      resolution: :string,
      resolved_at: :datetime,
      selected_element_html: :text,
      selected_element_selector: :string,
      selected_element_url: :string
    }.each do |column, type|
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

  # The dummy app sets `include_all_helpers = false`, so the engine's view helpers are
  # not auto-mixed into the controller the way they are under Rails' default (which is
  # what real host apps run). Wire them up so the views can actually render.
  before(:all) do
    LlamaBotRails::UserFeedbacksController.helper(
      LlamaBotRails::ApplicationHelper,
      LlamaBotRails::FeedbackHelper,
      LlamaBotRails::SsoHelper
    )
  end

  let(:user) { double('User', id: 123, email: 'user@example.com') }

  let!(:feedback) do
    LlamaBotRails::UserFeedback.create!(
      title: 'Scroll me back here',
      description: 'The card the user clicked into',
      feedback_type: 'bug',
      user_id: user.id,
      user_email: user.email
    )
  end

  let!(:other_feedback) do
    LlamaBotRails::UserFeedback.create!(
      title: 'Another card further down the list',
      description: 'Proves ids are per-card, not a single hardcoded anchor',
      feedback_type: 'general',
      user_id: user.id,
      user_email: user.email
    )
  end

  before do
    allow(LlamaBotRails).to receive(:current_user_resolver).and_return(->(_env) { user })
  end

  describe 'GET #index' do
    it 'gives every feedback card its own anchorable id' do
      get :index

      expect(response.body).to include(%(id="feedback-#{feedback.id}"))
      expect(response.body).to include(%(id="feedback-#{other_feedback.id}"))
    end

    it 'ships the script that scrolls to and flashes the returned-from card' do
      get :index

      expect(response.body).to include('restoreReturnedCard')
      expect(response.body).to include('returned-here')
    end
  end

  describe 'GET #show' do
    it 'links back to the index anchored at this feedback' do
      get :show, params: { id: feedback.id }

      expect(response.body).to include(%(href="#{user_feedbacks_path}#feedback-#{feedback.id}"))
    end

    it 'wires the back link to history.back() via the referrer check' do
      get :show, params: { id: feedback.id }

      expect(response.body).to include('backToFeedbackIndex(event)')
      expect(response.body).to include("const indexPath = '#{user_feedbacks_path}'")
      expect(response.body).to include('window.history.back()')
    end
  end
end
