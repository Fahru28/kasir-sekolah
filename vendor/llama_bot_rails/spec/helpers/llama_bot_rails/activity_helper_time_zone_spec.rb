require "rails_helper"

# The activity screens render every clock through these helpers, so this is
# where "shown in Pacific, and say so" is actually enforced.
RSpec.describe LlamaBotRails::ActivityHelper, type: :helper do
  around do |example|
    original = LlamaBotRails.config.display_time_zone
    LlamaBotRails.config.display_time_zone = nil
    example.run
    LlamaBotRails.config.display_time_zone = original
  end

  # 2026-01-15 02:30 UTC is still 6:30 PM on the 14th in Pacific — a timestamp
  # that lands on the wrong clock AND the wrong day if it is rendered raw.
  let(:utc_time) { Time.utc(2026, 1, 15, 2, 30, 0) }

  describe "#llama_activity_time" do
    it "renders a UTC timestamp on the Pacific clock" do
      expect(helper.llama_activity_time(utc_time)).to eq("6:30 PM")
    end

    it "still renders an em dash for a missing time" do
      expect(helper.llama_activity_time(nil)).to eq("—")
    end
  end

  describe "#llama_activity_timestamp" do
    it "renders the full date on the Pacific clock" do
      expect(helper.llama_activity_timestamp(utc_time))
        .to eq("January 14, 2026 at 6:30:00 PM")
    end
  end

  describe "#llama_activity_day" do
    it "groups the event under the Pacific day, not the UTC one" do
      expect(helper.llama_activity_day(utc_time)).to eq("January 14, 2026")
    end

    it "calls the current Pacific day Today" do
      expect(helper.llama_activity_day(LlamaBotRails.display_time_zone.now)).to eq("Today")
    end
  end

  describe "#llama_activity_zone_label" do
    it "names the zone plainly so the page can print it" do
      expect(helper.llama_activity_zone_label).to match(/\APacific Time \(P[DS]T\)\z/)
    end
  end

  context "when the host app configures its own zone" do
    it "honours it instead of Pacific" do
      LlamaBotRails.config.display_time_zone = "Eastern Time (US & Canada)"

      expect(helper.llama_activity_time(utc_time)).to eq("9:30 PM")
      expect(helper.llama_activity_zone_label).to match(/\AEastern Time \(E[DS]T\)\z/)
    end
  end
end
