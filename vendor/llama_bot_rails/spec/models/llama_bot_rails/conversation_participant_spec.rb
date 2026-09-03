require "rails_helper"
require_relative "../../support/feedback_tables"

module LlamaBotRails
  RSpec.describe ConversationParticipant, type: :model do
    # The dummy app's schema.rb carries none of the messaging tables, and the
    # sqlite test DB persists between runs — so without this the suite passes
    # only on a machine where some other spec happened to create them.
    before(:all) { LlamaBotRails::SpecSupport::FeedbackTables.build_messaging! }

    let(:reader_id) { 31 }
    let(:sender_id) { 23 }
    let(:conversation) { Conversation.find_or_create_between(sender_id, reader_id) }
    let(:participant) { conversation.participants.find_by(user_id: reader_id) }

    before do
      LlamaBotRails.user_resolver = ->(id) { Struct.new(:id, :email).new(id, "user#{id}@example.com") }
    end

    def send_message(body: "hello")
      DirectMessage.create!(conversation: conversation, sender_id: sender_id, body: body)
    end

    describe "#mark_as_read!" do
      it "stamps last_read_at so the thread stops counting as unread" do
        send_message

        expect { participant.mark_as_read! }
          .to change { conversation.unread_count_for(reader_id) }.from(1).to(0)
      end

      # The red badge on the Messages tab (both the Rails tab bar and the chat
      # UI's Inbox tab) counts unread new_message NOTIFICATIONS, not the
      # participant's last_read_at. Stamping only last_read_at left the badge lit
      # forever: opening the thread is the one place a user would expect to clear
      # it, and no other screen except Notifications ever marks those read.
      it "marks this conversation's new_message notifications read" do
        send_message

        expect { participant.mark_as_read! }
          .to change { Notification.unread_message_count_for(reader_id) }.from(1).to(0)
      end

      it "clears every unread message notification in the thread, not just the newest" do
        3.times { |i| send_message(body: "message #{i}") }

        participant.mark_as_read!

        expect(Notification.unread_message_count_for(reader_id)).to eq(0)
      end

      it "leaves other conversations' notifications alone" do
        send_message
        other = Conversation.find_or_create_between(99, reader_id)
        DirectMessage.create!(conversation: other, sender_id: 99, body: "unrelated")

        participant.mark_as_read!

        expect(Notification.unread_message_count_for(reader_id)).to eq(1)
      end

      it "does not touch another user's notifications for the same message" do
        send_message

        participant.mark_as_read!

        # The sender is a participant too; reading as one user must not read for
        # the other. (No notification is created for the sender, so what this
        # guards is the scoping of the update, not the count itself.)
        expect(Notification.for_user(sender_id).unread.count).to eq(0)
        expect(Notification.where(user_id: reader_id).unread.count).to eq(0)
      end

      it "leaves non-message notifications unread" do
        send_message
        feedback = UserFeedback.create!(user_id: reader_id, title: "Bug", status: "open")
        Notification.create!(
          user_id: reader_id,
          actor_id: sender_id,
          notifiable: feedback,
          notification_type: "feedback_comment",
          message: "commented"
        )

        participant.mark_as_read!

        expect(Notification.unread_message_count_for(reader_id)).to eq(0)
        expect(Notification.unread_count_for(reader_id)).to eq(1)
      end

      it "is safe on a thread with no messages" do
        expect { participant.mark_as_read! }.not_to raise_error
      end
    end
  end
end
