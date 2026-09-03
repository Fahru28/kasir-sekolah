module LlamaBotRails
  class Notification < ApplicationRecord
    TYPES = %w[
      new_message
      feedback_comment
      feedback_status_change
      feedback_mention
      request_response
    ].freeze

    # Notification types that also trigger an email to the recipient (opt-in).
    EMAILABLE_TYPES = %w[
      feedback_comment
      feedback_status_change
      feedback_mention
    ].freeze

    belongs_to :notifiable, polymorphic: true

    validates :user_id, presence: true
    validates :notification_type, presence: true, inclusion: { in: TYPES }

    scope :unread, -> { where(read_at: nil) }
    scope :read, -> { where.not(read_at: nil) }
    scope :recent, -> { order(created_at: :desc) }
    scope :for_user, ->(user_id) { where(user_id: user_id) }

    after_create :broadcast_notification
    after_create :deliver_email_notification

    def user
      LlamaBotRails.user_resolver&.call(user_id)
    end

    def actor
      LlamaBotRails.user_resolver&.call(actor_id) if actor_id
    end

    def read?
      read_at.present?
    end

    def mark_as_read!
      update!(read_at: Time.current) unless read?
    end

    def self.mark_all_read_for(user_id)
      for_user(user_id).unread.update_all(read_at: Time.current)
    end

    def self.unread_count_for(user_id)
      for_user(user_id).unread.count
    end

    # Unread direct messages only — what the red badge on the chat UI's Messages
    # tab counts. Deliberately narrower than unread_count_for: a badge on the
    # Messages tab that also counted feedback mentions would send the user to a
    # screen with nothing new on it.
    def self.unread_message_count_for(user_id)
      for_user(user_id).unread.where(notification_type: 'new_message').count
    end

    private

    # Enqueue an email for this notification when feedback emails are enabled and
    # the recipient resolves to an address. Best-effort: a failure here must never
    # break notification creation (which happens inside the request flow).
    def deliver_email_notification
      return unless LlamaBotRails.config.feedback_email_enabled
      return unless EMAILABLE_TYPES.include?(notification_type)

      recipient = user
      return unless recipient.respond_to?(:email) && recipient.email.present?

      LlamaBotRails::FeedbackMailer.feedback_activity(self).deliver_later
    rescue => e
      Rails.logger.error("[[LlamaBot]] Failed to enqueue feedback activity email: #{e.message}")
    end

    def broadcast_notification
      ActionCable.server.broadcast(
        "notifications_#{user_id}",
        {
          type: 'notification',
          notification: {
            id: id,
            notification_type: notification_type,
            message: message,
            read: read?,
            created_at: created_at.iso8601,
            metadata: metadata
          },
          unread_count: Notification.unread_count_for(user_id)
        }
      )
    end
  end
end
