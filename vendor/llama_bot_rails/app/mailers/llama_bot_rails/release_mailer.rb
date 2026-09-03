module LlamaBotRails
  # Emails for the release / version-notes feature. Delivery is opt-in via
  # `config.llama_bot_rails.release_email_enabled`; the controller only enqueues
  # this when the feature is enabled and recipients are configured. SMTP is
  # configured in the host app.
  class ReleaseMailer < ApplicationMailer
    # Sent to the app's configured recipient list when an admin clicks
    # "Email this release".
    def new_release(release)
      @release = release
      @url = release_link(release.id)

      recipients = Array(LlamaBotRails.config.release_notification_emails).reject(&:blank?)
      return if recipients.empty?

      mail(
        to: recipients,
        from: from_address,
        subject: subject_for(release)
      )
    end

    private

    def from_address
      LlamaBotRails.config.release_email_from.presence || "releases@llamapress.ai"
    end

    def subject_for(release)
      heading = release.title.presence || "What's new"
      "#{heading} — #{release.version}"
    end

    # Builds an absolute URL to the release page, or nil if no host is configured.
    def release_link(release_id)
      host = LlamaBotRails.config.release_email_url_host
      return nil if host.blank? || release_id.blank?

      LlamaBotRails::Engine.routes.url_helpers.release_url(release_id, host: host)
    end
  end
end
