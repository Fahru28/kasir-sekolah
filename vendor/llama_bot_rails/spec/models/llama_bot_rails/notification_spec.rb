require "rails_helper"

module LlamaBotRails
  RSpec.describe Notification, type: :model do
    let(:config) { LlamaBotRails.config }
    let(:feedback) { UserFeedback.create!(user_id: 1, title: "Bug", status: "open") }

    def build_notification(type: "feedback_comment")
      Notification.new(
        user_id: 1,
        actor_id: 2,
        notifiable: feedback,
        notification_type: type,
        message: "something happened",
        metadata: { "feedback_id" => feedback.id }
      )
    end

    around do |example|
      saved = config.feedback_email_enabled
      example.run
      config.feedback_email_enabled = saved
    end

    context "when feedback emails are enabled and the recipient has an email" do
      before do
        config.feedback_email_enabled = true
        LlamaBotRails.user_resolver = ->(_id) { Struct.new(:email).new("user@example.com") }
      end

      it "enqueues a feedback activity email on create for emailable types" do
        expect {
          build_notification(type: "feedback_comment").save!
        }.to have_enqueued_mail(LlamaBotRails::FeedbackMailer, :feedback_activity)
      end

      it "does not enqueue for non-emailable types such as new_message" do
        expect {
          build_notification(type: "new_message").save!
        }.not_to have_enqueued_mail(LlamaBotRails::FeedbackMailer, :feedback_activity)
      end

      it "does not enqueue when the recipient cannot be resolved to an email" do
        LlamaBotRails.user_resolver = ->(_id) { nil }
        expect {
          build_notification(type: "feedback_comment").save!
        }.not_to have_enqueued_mail(LlamaBotRails::FeedbackMailer, :feedback_activity)
      end
    end

    context "when feedback emails are disabled" do
      before do
        config.feedback_email_enabled = false
        LlamaBotRails.user_resolver = ->(_id) { Struct.new(:email).new("user@example.com") }
      end

      it "does not enqueue any email" do
        expect {
          build_notification(type: "feedback_comment").save!
        }.not_to have_enqueued_mail(LlamaBotRails::FeedbackMailer, :feedback_activity)
      end
    end
  end
end
