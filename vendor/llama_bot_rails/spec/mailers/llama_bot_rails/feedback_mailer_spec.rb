require "rails_helper"

module LlamaBotRails
  RSpec.describe FeedbackMailer, type: :mailer do
    let(:config) { LlamaBotRails.config }

    before do
      ActionMailer::Base.deliveries.clear

      @saved = {
        from: config.feedback_email_from,
        host: config.feedback_email_url_host,
        emails: config.feedback_notification_emails
      }
      config.feedback_email_from = "feedback@llamapress.ai"
      config.feedback_email_url_host = "app.example.com"
      config.feedback_notification_emails = [ "manager@example.com" ]
    end

    after do
      config.feedback_email_from = @saved[:from]
      config.feedback_email_url_host = @saved[:host]
      config.feedback_notification_emails = @saved[:emails]
    end

    describe "#new_feedback" do
      let(:feedback) do
        UserFeedback.create!(
          user_id: 1,
          title: "Login is broken",
          description: "Cannot sign in",
          feedback_type: "bug",
          status: "open"
        )
      end

      it "is addressed to the configured manager recipients" do
        mail = described_class.new_feedback(feedback)
        expect(mail.to).to eq([ "manager@example.com" ])
        expect(mail.from).to eq([ "feedback@llamapress.ai" ])
        expect(mail.subject).to eq("New feedback: Login is broken")
      end

      it "includes the feedback details and an absolute link in the body" do
        mail = described_class.new_feedback(feedback)
        expect(mail.body.encoded).to include("Login is broken")
        expect(mail.body.encoded).to include("app.example.com")
      end

      it "does not deliver when no recipients are configured" do
        config.feedback_notification_emails = []
        expect {
          described_class.new_feedback(feedback).deliver_now
        }.not_to change { ActionMailer::Base.deliveries.count }
      end
    end

    describe "#feedback_activity" do
      let(:feedback) { UserFeedback.create!(user_id: 1, title: "Login is broken", status: "open") }

      def notification(type: "feedback_comment")
        Notification.new(
          user_id: 1,
          actor_id: 2,
          notifiable: feedback,
          notification_type: type,
          message: "Admin commented on your feedback: Login is broken",
          metadata: { "feedback_id" => feedback.id }
        )
      end

      before do
        LlamaBotRails.user_resolver = ->(_id) { Struct.new(:email).new("user@example.com") }
      end

      it "is addressed to the resolved recipient email" do
        mail = described_class.feedback_activity(notification)
        expect(mail.to).to eq([ "user@example.com" ])
        expect(mail.subject).to eq("New activity on your feedback")
        expect(mail.body.encoded).to include("Admin commented on your feedback")
      end

      it "uses a status-change subject for status-change notifications" do
        mail = described_class.feedback_activity(notification(type: "feedback_status_change"))
        expect(mail.subject).to eq("Your feedback status was updated")
      end

      it "does not deliver when the recipient cannot be resolved to an email" do
        LlamaBotRails.user_resolver = ->(_id) { nil }
        expect {
          described_class.feedback_activity(notification).deliver_now
        }.not_to change { ActionMailer::Base.deliveries.count }
      end
    end
  end
end
