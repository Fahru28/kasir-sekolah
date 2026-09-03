require "rails_helper"

module LlamaBotRails
  RSpec.describe ReleasesController, type: :controller do
    routes { LlamaBotRails::Engine.routes }

    let(:admin)   { double("User", id: 1, email: "admin@example.com", admin?: true) }
    let(:regular) { double("User", id: 2, email: "user@example.com", admin?: false) }

    # Authenticate by stubbing the engine's current-user resolver.
    def sign_in_as(user)
      allow(LlamaBotRails).to receive(:current_user_resolver).and_return(->(_env) { user })
    end

    let!(:published) { Release.create!(version: "1.0.0", title: "GA", published: true) }
    let!(:draft)     { Release.create!(version: "1.1.0", title: "WIP", published: false) }

    describe "GET #index" do
      it "shows only published releases to a regular user" do
        sign_in_as(regular)
        get :index
        expect(response).to be_successful
        expect(assigns(:releases)).to include(published)
        expect(assigns(:releases)).not_to include(draft)
      end

      it "shows all releases (including drafts) to an admin" do
        sign_in_as(admin)
        get :index
        expect(assigns(:releases)).to include(published, draft)
      end
    end

    describe "POST #create" do
      let(:params) { { release: { version: "2.0.0", title: "Big", notes: "- thing", published: "1" } } }

      it "creates a release for an admin" do
        sign_in_as(admin)
        expect { post :create, params: params }.to change(Release, :count).by(1)
      end

      it "blocks a non-admin user" do
        sign_in_as(regular)
        expect { post :create, params: params }.not_to change(Release, :count)
        expect(response).to have_http_status(:redirect)
      end
    end

    describe "DELETE #destroy" do
      it "blocks a non-admin user" do
        sign_in_as(regular)
        expect { delete :destroy, params: { id: published.id } }.not_to change(Release, :count)
        expect(response).to have_http_status(:redirect)
      end
    end

    describe "POST #notify" do
      before do
        LlamaBotRails.config.release_email_enabled = true
        LlamaBotRails.config.release_notification_emails = ["clients@example.com"]
      end

      after do
        LlamaBotRails.config.release_email_enabled = false
        LlamaBotRails.config.release_notification_emails = []
      end

      it "queues an email and stamps emailed_at for an admin" do
        sign_in_as(admin)
        mail = double("mail", deliver_later: true)
        expect(LlamaBotRails::ReleaseMailer).to receive(:new_release).with(published).and_return(mail)

        post :notify, params: { id: published.id }

        expect(published.reload.emailed_at).to be_present
      end

      it "blocks a non-admin user and does not email" do
        sign_in_as(regular)
        expect(LlamaBotRails::ReleaseMailer).not_to receive(:new_release)

        post :notify, params: { id: published.id }

        expect(response).to have_http_status(:redirect)
        expect(published.reload.emailed_at).to be_nil
      end
    end
  end
end
