module LlamaBotRails
  class NotificationChannel < ApplicationCable::Channel
    def subscribed
      # Get current user from the connection
      current_user = LlamaBotRails.current_user_resolver&.call(connection.env)

      if current_user
        stream_from "notifications_#{current_user.id}"
        Rails.logger.info "[LlamaBotRails::NotificationChannel] User #{current_user.id} subscribed to notifications"

        # Send initial unread count
        transmit({
          type: 'connected',
          unread_count: Notification.unread_count_for(current_user.id)
        })
      else
        reject
      end
    end

    def unsubscribed
      Rails.logger.info "[LlamaBotRails::NotificationChannel] User unsubscribed from notifications"
    end

    # Mark notification(s) as read
    def mark_read(data)
      current_user = LlamaBotRails.current_user_resolver&.call(connection.env)
      return unless current_user

      if data['notification_id'].present?
        notification = Notification.for_user(current_user.id).find_by(id: data['notification_id'])
        notification&.mark_as_read!
      else
        Notification.mark_all_read_for(current_user.id)
      end

      transmit({
        type: 'read_updated',
        unread_count: Notification.unread_count_for(current_user.id)
      })
    end

    # Fetch recent notifications
    def fetch_notifications(data)
      current_user = LlamaBotRails.current_user_resolver&.call(connection.env)
      return unless current_user

      limit = [data.fetch('limit', 20).to_i, 50].min
      notifications = Notification.for_user(current_user.id).recent.limit(limit)

      transmit({
        type: 'notifications_list',
        notifications: notifications.map { |n| notification_payload(n) },
        unread_count: Notification.unread_count_for(current_user.id)
      })
    end

    private

    def notification_payload(notification)
      {
        id: notification.id,
        type: notification.notification_type,
        message: notification.message,
        read: notification.read?,
        created_at: notification.created_at.iso8601,
        metadata: notification.metadata
      }
    end
  end
end
