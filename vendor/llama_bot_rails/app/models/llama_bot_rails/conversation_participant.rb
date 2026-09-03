module LlamaBotRails
  class ConversationParticipant < ApplicationRecord
    belongs_to :conversation, class_name: 'LlamaBotRails::Conversation', touch: true

    validates :user_id, presence: true, uniqueness: { scope: :conversation_id }
    validates :joined_at, presence: true

    scope :for_user, ->(user_id) { where(user_id: user_id) }
    scope :not_muted, -> { where(muted: false) }

    def user
      LlamaBotRails.user_resolver&.call(user_id)
    end

    def mark_as_read!
      update!(last_read_at: Time.current)
      mark_message_notifications_read!
    end

    def unread_messages_count
      if last_read_at
        conversation.messages.where('created_at > ?', last_read_at).count
      else
        conversation.messages.count
      end
    end

    private

    # last_read_at drives the per-thread count in the conversation list; the red
    # badge on the Messages tab (and on the chat UI's Inbox tab, which mirrors it)
    # counts unread new_message NOTIFICATIONS instead. Opening the thread is the
    # only place a user would expect that badge to clear, so reading has to clear
    # both — otherwise the badge stays lit until they happen to visit the
    # Notifications tab and mark everything read.
    #
    # Scoped through the conversation's own messages rather than the metadata
    # conversation_id: metadata is a free-form json blob, notifiable_id is the FK.
    def mark_message_notifications_read!
      Notification
        .for_user(user_id)
        .unread
        .where(
          notification_type: 'new_message',
          notifiable_type: 'LlamaBotRails::DirectMessage',
          notifiable_id: conversation.messages.select(:id)
        )
        .update_all(read_at: Time.current)
    end
  end
end
