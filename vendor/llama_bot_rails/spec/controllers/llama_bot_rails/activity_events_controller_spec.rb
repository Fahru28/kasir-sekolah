require "rails_helper"
require_relative "../../support/activity_tables"

# The Activity feed could be narrowed by type, source, cause and date, but not by
# PERSON — which is the question it gets asked most ("what has this user been
# doing?"). And its clocks ran in whatever zone the host app happened to set,
# unlabelled. Both pinned here.
module LlamaBotRails
  RSpec.describe ActivityEventsController, type: :controller do
    routes { LlamaBotRails::Engine.routes }

    before(:all) { LlamaBotRails::SpecSupport::ActivityTables.build! }

    let(:admin) { double("User", id: 1, email: "admin@example.com", admin?: true) }

    def sign_in_as(user)
      allow(LlamaBotRails).to receive(:current_user_resolver).and_return(->(_env) { user })
    end

    def event!(actor_id:, actor_label:, event_type: "contact.updated", occurred_at: Time.utc(2026, 1, 15, 2, 30))
      ActivityEvent.create!(
        event_type: event_type,
        occurred_at: occurred_at,
        source: "admin_ui",
        human: true,
        actor_type: "User",
        actor_id: actor_id.to_s,
        actor_label: actor_label
      )
    end

    before do
      ActivityEvent.delete_all
      sign_in_as(admin)
    end

    describe "GET #index filtered by person" do
      let!(:grace_event) { event!(actor_id: 7, actor_label: "Grace Hopper") }
      let!(:alan_event)  { event!(actor_id: 9, actor_label: "Alan Turing") }

      it "returns only that person's events" do
        get :index, params: { actor_id: "7" }

        expect(assigns(:events)).to include(grace_event)
        expect(assigns(:events)).not_to include(alan_event)
      end

      it "returns everyone when no person is chosen" do
        get :index

        expect(assigns(:events)).to include(grace_event, alan_event)
      end

      it "offers every actor as a filter option, alphabetically" do
        get :index

        expect(assigns(:actors)).to eq([ [ "Alan Turing", "9" ], [ "Grace Hopper", "7" ] ])
      end

      it "labels an actor by their most recent name, not an older one" do
        event!(actor_id: 7, actor_label: "Grace Hopper-Murray", occurred_at: Time.utc(2026, 2, 1, 12))
        get :index

        expect(assigns(:actors)).to include([ "Grace Hopper-Murray", "7" ])
        expect(assigns(:actors).map(&:first)).not_to include("Grace Hopper")
      end

      it "names the person being filtered so the page can say whose feed this is" do
        get :index, params: { actor_id: "7" }

        expect(assigns(:selected_actor)).to eq("7")
        expect(assigns(:selected_actor_label)).to eq("Grace Hopper")
      end

      it "falls back to an actor with no label rather than dropping them" do
        ActivityEvent.delete_all
        event!(actor_id: 42, actor_label: nil)
        get :index

        expect(assigns(:actors)).to eq([ [ "User #42", "42" ] ])
      end
    end

    describe "the display time zone" do
      around do |example|
        original = LlamaBotRails.config.display_time_zone
        LlamaBotRails.config.display_time_zone = nil
        example.run
        LlamaBotRails.config.display_time_zone = original
      end

      it "runs the action in the display zone, so dates and clocks agree" do
        get :index

        expect(assigns(:display_time_zone).tzinfo.name).to eq("America/Los_Angeles")
      end

      # A From/To date is a date in the READER's zone. Filtering in UTC silently
      # dropped the last hours of the chosen day for anyone west of Greenwich.
      it "reads a From date as a Pacific day, not a UTC one" do
        # 2026-01-15 02:30 UTC == 2026-01-14 18:30 Pacific.
        late_on_the_14th = event!(actor_id: 7, actor_label: "Grace Hopper")

        get :index, params: { from: "2026-01-14", to: "2026-01-14" }

        expect(assigns(:events)).to include(late_on_the_14th)
      end
    end
  end
end
