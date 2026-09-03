require "rails_helper"

module LlamaBotRails
  RSpec.describe Release, type: :model do
    describe "validations" do
      it { is_expected.to validate_presence_of(:version) }

      it "requires version to be unique" do
        Release.create!(version: "1.0.0")
        duplicate = Release.new(version: "1.0.0")

        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:version]).to be_present
      end
    end

    describe "scopes" do
      let!(:draft) { Release.create!(version: "0.1.0", published: false, released_at: 2.days.ago) }
      let!(:older) { Release.create!(version: "0.2.0", published: true, released_at: 3.days.ago) }
      let!(:newer) { Release.create!(version: "0.3.0", published: true, released_at: 1.day.ago) }

      it "published returns only published releases" do
        expect(Release.published).to match_array([older, newer])
      end

      it "ordered sorts by released_at descending" do
        expect(Release.published.ordered.to_a).to eq([newer, older])
      end
    end

    describe ".current and #current?" do
      it "matches the release for the running app version" do
        allow(LlamaBotRails).to receive(:app_version).and_return("9.9.9")
        running = Release.create!(version: "9.9.9")
        other = Release.create!(version: "8.8.8")

        expect(Release.current).to eq(running)
        expect(running.current?).to be(true)
        expect(other.current?).to be(false)
      end

      it "returns nil when no release matches the running version" do
        allow(LlamaBotRails).to receive(:app_version).and_return("0.0.0-none")
        Release.create!(version: "1.2.3")

        expect(Release.current).to be_nil
      end
    end
  end
end
