module LlamaBotRails
  # Emails for the feedback feature. Delivery is opt-in via
  # `config.llama_bot_rails.feedback_email_enabled`; callers should only enqueue
  # these when the feature is enabled. SMTP is configured in the host app.
  class FeedbackMailer < ApplicationMailer
    # Sent to the app's configured manager recipients when a user submits new feedback.
    def new_feedback(feedback)
      @feedback = feedback
      @url = feedback_link(feedback.id)

      recipients = Array(LlamaBotRails.config.feedback_notification_emails).reject(&:blank?)
      return if recipients.empty?

      mail(
        to: recipients,
        from: from_address,
        subject: "New feedback: #{feedback.title.presence || '(no title)'}"
      )
    end

    # Sent to the affected user when there is new activity (comment, mention, or
    # status change) on a piece of feedback. Driven by LlamaBotRails::Notification.
    def feedback_activity(notification)
      @notification = notification
      @message = notification.message

      recipient = notification.user
      return unless recipient.respond_to?(:email) && recipient.email.present?

      @url = feedback_link(metadata_feedback_id(notification.metadata))

      mail(
        to: recipient.email,
        from: from_address,
        subject: activity_subject(notification)
      )
    end

    private

    def from_address
      LlamaBotRails.config.feedback_email_from.presence || "feedback@example.com"
    end

    def activity_subject(notification)
      case notification.notification_type
      when "feedback_status_change" then "Your feedback status was updated"
      when "feedback_mention"       then "You were tagged on feedback"
      else "New activity on your feedback"
      end
    end

    def metadata_feedback_id(metadata)
      return nil unless metadata.is_a?(Hash)

      metadata["feedback_id"] || metadata[:feedback_id]
    end

    # Builds an absolute URL to the feedback page, or nil if no host is configured.
    def feedback_link(feedback_id)
      host = LlamaBotRails.config.feedback_email_url_host
      return nil if host.blank? || feedback_id.blank?

      LlamaBotRails::Engine.routes.url_helpers.user_feedback_url(feedback_id, host: host)
    end
  end
end
