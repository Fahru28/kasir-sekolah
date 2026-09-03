require 'rails_helper'

# Pins "picking a second file adds to the first" on the feedback form itself.
#
# A bare <input type="file" multiple> REPLACES its selection every time the native
# picker closes, so the only way to attach two images was to shift-click both in a
# single dialog. The comment boxes on the show page already merged each pick into
# what was staged; the new/edit form never did. Both now render the same shared
# staging script.
#
# The dummy app's schema.rb only carries the releases table and the engine's
# migrations are deliberately not auto-loaded, so this spec stands up the tables
# the views touch (same approach as the scroll-restoration spec).
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
      title: 'Attach a couple of screenshots',
      description: 'One picker trip per file',
      feedback_type: 'bug',
      user_id: user.id,
      user_email: user.email
    )
  end

  before do
    allow(LlamaBotRails).to receive(:current_user_resolver).and_return(->(_env) { user })
  end

  shared_examples 'a form that stages attachments across picks' do
    it 'merges each pick instead of letting the picker replace the selection' do
      expect(response.body).to include('onchange="mergePickedAttachments(this)"')
      expect(response.body).to include('function mergePickedAttachments(input)')
    end

    it 'previews what is staged and gives each file its own remove button' do
      expect(response.body).to include('data-preview-target="feedback-attachment-preview"')
      expect(response.body).to include('id="feedback-attachment-preview"')
      expect(response.body).to include('function removePendingAttachment(input, file)')
    end
  end

  describe 'GET #edit' do
    before { get :edit, params: { id: feedback.id } }

    it_behaves_like 'a form that stages attachments across picks'
  end

  describe 'GET #new' do
    before { get :new }

    it_behaves_like 'a form that stages attachments across picks'
  end

  describe 'GET #show' do
    it 'still ships the staging script for the comment boxes' do
      get :show, params: { id: feedback.id }

      expect(response.body).to include('function mergePickedAttachments(input)')
      expect(response.body).to include('onchange="mergePickedAttachments(this)"')
    end
  end
end
