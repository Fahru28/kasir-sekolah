require "rails_helper"
require_relative "../../support/feedback_tables"

# Opening a conversation is the only thing that clears its unread state, so it
# has to settle BOTH trackers: last_read_at (the per-thread count in the list)
# and the 'new_message' notifications (the red badges on the Messages tab and on
# the chat UI's Inbox tab). It marked only the participant read, so the badges
# never cleared no matter how many times you read the thread.
RSpec.describe LlamaBotRails::ConversationsController, type: :controller do
  routes { LlamaBotRails::Engine.routes }

  before(:all) { LlamaBotRails::SpecSupport::FeedbackTables.build_messaging! }

  let(:reader) { double('User', id: 501, email: 'reader@example.com') }
  let(:sender_id) { 502 }

  before do
    allow(LlamaBotRails).to receive(:current_user_resolver).and_return(->(_env) { reader })
  end

  let(:conversation) do
    LlamaBotRails::Conversation.create!(conversation_type: 'direct').tap do |c|
      [reader.id, sender_id].each { |id| c.participants.create!(user_id: id, joined_at: Time.current) }
    end
  end

  def incoming_message
    conversation.messages.create!(sender_id: sender_id, body: 'ping')
  end

  def unread_badge_count
    LlamaBotRails::Notification.unread_message_count_for(reader.id)
  end

  it "clears the unread badge when the conversation is opened" do
    incoming_message
    expect(unread_badge_count).to eq(1)

    get :show, params: { id: conversation.id }

    expect(response).to have_http_status(:ok)
    expect(unread_badge_count).to eq(0)
  end

  it "clears the unread badge when the messages are fetched by the JSON endpoint" do
    incoming_message

    get :messages, params: { id: conversation.id }

    expect(response).to have_http_status(:ok)
    expect(unread_badge_count).to eq(0)
  end

  it "still marks the participant read, which is what the per-thread count uses" do
    incoming_message

    get :show, params: { id: conversation.id }

    expect(conversation.unread_count_for(reader.id)).to eq(0)
  end
end
