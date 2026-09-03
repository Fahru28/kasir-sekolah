module LlamaBotRails
  class DirectMessage < ApplicationRecord
    belongs_to :conversation, class_name: 'LlamaBotRails::Conversation', touch: true
    has_many :notifications, as: :notifiable, class_name: 'LlamaBotRails::Notification', dependent: :destroy

    validates :body, presence: true
    validates :sender_id, presence: true

    scope :chronological, -> { order(created_at: :asc) }
    scope :recent_first, -> { order(created_at: :desc) }

    after_create :create_notifications
    after_create :broadcast_message

    def sender
      LlamaBotRails.user_resolver&.call(sender_id)
    end

    def sender_display_name
      sender&.email || 'Unknown User'
    end

    private

    def create_notifications
      # Notify all participants except the sender
      conversation.participants.where.not(user_id: sender_id).not_muted.find_each do |participant|
        Notification.create!(
          user_id: participant.user_id,
          actor_id: sender_id,
          notifiable: self,
          notification_type: 'new_message',
          message: "New message from #{sender_display_name}",
          metadata: { conversation_id: conversation_id }
        )
      end
    end

    def broadcast_message
      # Broadcast to all participants
      conversation.participants.pluck(:user_id).each do |user_id|
        ActionCable.server.broadcast(
          "notifications_#{user_id}",
          {
            type: 'new_message',
            conversation_id: conversation_id,
            message: {
              id: id,
              body: body,
              sender_id: sender_id,
              sender_name: sender_display_name,
              created_at: created_at.iso8601,
              is_own: sender_id == user_id
            }
          }
        )
      end
    end
  end
end
