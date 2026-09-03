module LlamaBotRails
  class NotificationsController < ApplicationController
    include Authorizable

    layout "llama_bot_rails/inbox"
    before_action :require_llama_user!

    # GET /notifications
    def index
      @notifications = Notification
        .for_user(current_llama_user.id)
        .recent
        .limit(50)

      respond_to do |format|
        format.html
        format.json do
          render json: {
            notifications: @notifications.map { |n| notification_json(n) },
            unread_count: Notification.unread_count_for(current_llama_user.id)
          }
        end
      end
    end

    # GET /notifications/unread_count
    #
    # unread_message_count is broken out for the Messages tab badge in the chat
    # UI, which must not light up for feedback mentions (see
    # Notification.unread_message_count_for).
    def unread_count
      render json: {
        unread_count: Notification.unread_count_for(current_llama_user.id),
        unread_message_count: Notification.unread_message_count_for(current_llama_user.id)
      }
    end

    # POST /notifications/mark_read
    def mark_read
      if params[:notification_id].present?
        notification = Notification.for_user(current_llama_user.id).find(params[:notification_id])
        notification.mark_as_read!
      else
        Notification.mark_all_read_for(current_llama_user.id)
      end

      render json: {
        success: true,
        unread_count: Notification.unread_count_for(current_llama_user.id)
      }
    end

    # POST /notifications/:id/read
    def read
      notification = Notification.for_user(current_llama_user.id).find(params[:id])
      notification.mark_as_read!

      render json: notification_json(notification)
    end

    private

    def notification_json(notification)
      {
        id: notification.id,
        type: notification.notification_type,
        message: notification.message,
        read: notification.read?,
        created_at: notification.created_at.iso8601,
        metadata: notification.metadata,
        actor: notification.actor ? { id: notification.actor_id, email: notification.actor.email } : nil
      }
    end
  end
end
