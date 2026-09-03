require "rails_helper"

# Activity timestamps are stored in UTC; which zone they were rendered in was
# left entirely to the host app (the LlamaPress skeleton sets Pacific, a bare
# host app renders UTC) and no screen said which. These pin the resolution
# order the gem now applies itself:
#
#   explicit gem config > host app's config.time_zone > Pacific
#
# and the fact that the zone gets a plain, readable name.
RSpec.describe "LlamaBotRails.display_time_zone" do
  around do |example|
    original_config = LlamaBotRails.config.display_time_zone
    original_app = Rails.application.config.time_zone
    example.run
    LlamaBotRails.config.display_time_zone = original_config
    Rails.application.config.time_zone = original_app
  end

  describe "resolution order" do
    it "defaults to Pacific when nothing is configured" do
      LlamaBotRails.config.display_time_zone = nil
      Rails.application.config.time_zone = "UTC"

      expect(LlamaBotRails.display_time_zone.tzinfo.name).to eq("America/Los_Angeles")
    end

    it "follows the host app's config.time_zone when it sets one" do
      LlamaBotRails.config.display_time_zone = nil
      Rails.application.config.time_zone = "Eastern Time (US & Canada)"

      expect(LlamaBotRails.display_time_zone.tzinfo.name).to eq("America/New_York")
    end

    it "lets the gem setting override the host app" do
      LlamaBotRails.config.display_time_zone = "UTC"
      Rails.application.config.time_zone = "Eastern Time (US & Canada)"

      expect(LlamaBotRails.display_time_zone.name).to eq("UTC")
    end

    it "falls back to Pacific rather than blowing up on a bogus zone name" do
      LlamaBotRails.config.display_time_zone = "Middle Earth"

      expect(LlamaBotRails.display_time_zone.tzinfo.name).to eq("America/Los_Angeles")
    end
  end

  describe "the label the screens print" do
    it "names Pacific plainly, with its current abbreviation" do
      LlamaBotRails.config.display_time_zone = nil
      Rails.application.config.time_zone = "UTC"

      expect(LlamaBotRails.display_time_zone_label).to match(/\APacific Time \(P[DS]T\)\z/)
    end

    it "does not stutter when the zone is its own abbreviation" do
      LlamaBotRails.config.display_time_zone = "UTC"

      expect(LlamaBotRails.display_time_zone_label).to eq("UTC")
    end
  end
end
