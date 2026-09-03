require 'rails_helper'

# The dummy app's schema.rb only carries the releases table and the engine's
# migrations are deliberately not auto-loaded, so — like the SSO resolver spec —
# this spec stands up the tables it exercises.
RSpec.describe LlamaBotRails::FeedbackCommentsController, type: :controller do
  include ActiveSupport::Testing::TimeHelpers

  routes { LlamaBotRails::Engine.routes }

  before(:all) do
    conn = ActiveRecord::Base.connection

    unless conn.table_exists?(:llama_bot_rails_user_feedbacks)
      conn.create_table :llama_bot_rails_user_feedbacks do |t|
        t.string :title
        t.text :description
        t.string :feedback_type
        t.string :status, default: 'open'
        t.integer :priority, default: 0
        t.integer :user_id
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

  let(:author) { double('User', id: 123, email: 'author@example.com') }
  let(:other_user) { double('User', id: 456, email: 'someone-else@example.com') }

  let(:feedback) do
    LlamaBotRails::UserFeedback.create!(
      title: 'Broken button',
      description: 'It does nothing',
      feedback_type: 'bug',
      user_id: author.id
    )
  end

  let!(:comment) do
    LlamaBotRails::FeedbackComment.create!(
      commentable: feedback,
      body: 'Teh butotn is broekn',
      user_id: author.id,
      author_name: author.email
    )
  end

  def sign_in_as(user)
    allow(LlamaBotRails).to receive(:current_user_resolver).and_return(->(_env) { user })
  end

  describe 'PATCH #update' do
    it 'lets the author fix their own comment' do
      sign_in_as(author)

      # Edits happen well after posting; edited? is a created_at/updated_at delta.
      travel_to(2.minutes.from_now) do
        patch :update, params: {
          user_feedback_id: feedback.id,
          id: comment.id,
          feedback_comment: { body: 'The button is broken' }
        }
      end

      expect(comment.reload.body).to eq('The button is broken')
      expect(comment.edited?).to be(true)
    end

    it 'does not let another user rewrite the comment' do
      sign_in_as(other_user)

      patch :update, params: {
        user_feedback_id: feedback.id,
        id: comment.id,
        feedback_comment: { body: 'Words I never wrote' }
      }

      expect(comment.reload.body).to eq('Teh butotn is broekn')
    end

    it 'rejects an empty body' do
      sign_in_as(author)

      patch :update, params: {
        user_feedback_id: feedback.id,
        id: comment.id,
        feedback_comment: { body: '' }
      }

      expect(comment.reload.body).to eq('Teh butotn is broekn')
      expect(flash[:alert]).to include('Failed to update comment')
    end

    it 'keeps existing attachments when the body is edited' do
      sign_in_as(author)
      comment.attachments.attach(
        io: StringIO.new('fake-png-bytes'),
        filename: 'screenshot.png',
        content_type: 'image/png'
      )

      patch :update, params: {
        user_feedback_id: feedback.id,
        id: comment.id,
        feedback_comment: { body: 'Now with context' }
      }

      expect(comment.reload.attachments.count).to eq(1)
      expect(comment.attachments.first.filename.to_s).to eq('screenshot.png')
    end

    it 'appends newly attached files instead of replacing them' do
      sign_in_as(author)
      comment.attachments.attach(
        io: StringIO.new('fake-png-bytes'),
        filename: 'screenshot.png',
        content_type: 'image/png'
      )

      patch :update, params: {
        user_feedback_id: feedback.id,
        id: comment.id,
        feedback_comment: {
          body: 'Adding a second shot',
          attachments: [
            Rack::Test::UploadedFile.new(
              StringIO.new('more-fake-bytes'),
              'image/png',
              original_filename: 'screenshot-2.png'
            )
          ]
        }
      }

      expect(comment.reload.attachments.map { |a| a.filename.to_s })
        .to contain_exactly('screenshot.png', 'screenshot-2.png')
    end
  end

  describe '#edited?' do
    it 'is false for a comment that was never touched' do
      expect(comment.edited?).to be(false)
    end
  end

  # This is what gates the pencil button in the view, so pin it directly.
  describe '#editable_by?' do
    it 'is true for the author' do
      expect(comment.editable_by?(author)).to be(true)
    end

    it 'is false for another signed-in user' do
      expect(comment.editable_by?(other_user)).to be(false)
    end

    it 'is false for a signed-out visitor' do
      expect(comment.editable_by?(nil)).to be(false)
    end

    it 'is false for an anonymous comment nobody owns' do
      anonymous = LlamaBotRails::FeedbackComment.create!(
        commentable: feedback, body: 'Posted with no account', user_id: nil
      )

      expect(anonymous.editable_by?(author)).to be(false)
    end
  end
end
