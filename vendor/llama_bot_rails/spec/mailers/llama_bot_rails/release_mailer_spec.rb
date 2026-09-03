require "rails_helper"

module LlamaBotRails
  RSpec.describe ReleaseMailer, type: :mailer do
    let(:config) { LlamaBotRails.config }

    before do
      ActionMailer::Base.deliveries.clear

      @saved = {
        from: config.release_email_from,
        host: config.release_email_url_host,
        emails: config.release_notification_emails
      }
      config.release_email_from = "releases@llamapress.ai"
      config.release_email_url_host = "app.example.com"
      config.release_notification_emails = ["clients@example.com"]
    end

    after do
      config.release_email_from = @saved[:from]
      config.release_email_url_host = @saved[:host]
      config.release_notification_emails = @saved[:emails]
    end

    let(:release) do
      Release.create!(
        version: "0.4.1",
        title: "Spring update",
        notes: "- New dashboard\n- Faster search",
        released_at: Time.current
      )
    end

    describe "#new_release" do
      it "is addressed to the configured recipients with the version in the subject" do
        mail = described_class.new_release(release)
        expect(mail.to).to eq(["clients@example.com"])
        expect(mail.from).to eq(["releases@llamapress.ai"])
        expect(mail.subject).to eq("Spring update — 0.4.1")
      end

      it "includes the notes and an absolute link in the body" do
        mail = described_class.new_release(release)
        expect(mail.body.encoded).to include("New dashboard")
        expect(mail.body.encoded).to include("app.example.com")
      end

      it "does not deliver when no recipients are configured" do
        config.release_notification_emails = []
        expect {
          described_class.new_release(release).deliver_now
        }.not_to change { ActionMailer::Base.deliveries.count }
      end
    end
  end
end
