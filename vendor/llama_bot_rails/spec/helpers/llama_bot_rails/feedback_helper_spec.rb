require "rails_helper"

# The "where did this feedback come from" link on a feedback item. QA (Michaela) found
# the old link — a bare path behind a chain icon — hard to recognise as a link, and it
# gave no clue which element on the page the report was about. The link now carries the
# captured selector so the target page can ring the element on arrival.
RSpec.describe LlamaBotRails::FeedbackHelper, type: :helper do
  # A stand-in for UserFeedback: these helpers only read four attributes, and the gem's
  # dummy app has no feedback table to build a real record against.
  def feedback(url:, selector: nil, html: nil, id: 12)
    Struct.new(:id, :selected_element_url, :selected_element_selector, :selected_element_html)
          .new(id, url, selector, html)
  end

  describe "#feedback_page_path" do
    it "links to the page even when no element was picked" do
      expect(helper.feedback_page_path(feedback(url: "/tickets/3")))
        .to eq("/tickets/3")
    end

    it "carries the selector and the feedback id when an element was picked" do
      path = helper.feedback_page_path(feedback(url: "/tickets/3", selector: "#wrapper > button.btn"))

      query = Rack::Utils.parse_query(URI.parse(path).query)
      expect(URI.parse(path).path).to eq("/tickets/3")
      expect(query["lp_feedback_element"]).to eq("#wrapper > button.btn")
      expect(query["lp_feedback_id"]).to eq("12")
    end

    it "keeps the page's own query params" do
      path = helper.feedback_page_path(feedback(url: "/tickets?status=open", selector: "#a"))

      expect(Rack::Utils.parse_query(URI.parse(path).query)["status"]).to eq("open")
    end

    it "does not stack highlight params if the captured path already had them" do
      path = helper.feedback_page_path(
        feedback(url: "/tickets?lp_feedback_element=%23old&lp_feedback_id=9", selector: "#new")
      )

      expect(path.scan("lp_feedback_element").length).to eq(1)
      expect(Rack::Utils.parse_query(URI.parse(path).query)["lp_feedback_element"]).to eq("#new")
    end

    it "refuses anything that is not an in-app path" do
      expect(helper.feedback_page_path(feedback(url: "//evil.example/x"))).to be_nil
      expect(helper.feedback_page_path(feedback(url: "https://evil.example/x"))).to be_nil
      expect(helper.feedback_page_path(feedback(url: "javascript:alert(1)"))).to be_nil
      expect(helper.feedback_page_path(feedback(url: nil))).to be_nil
      expect(helper.feedback_page_path(feedback(url: ""))).to be_nil
    end
  end

  describe "#selected_element_label" do
    it "names the tag and its text" do
      expect(helper.selected_element_label(
        feedback(url: "/x", html: '<button class="btn">Save changes</button>')
      )).to eq("<button> Save changes")
    end

    it "falls back to the tag alone when the element has no text" do
      expect(helper.selected_element_label(feedback(url: "/x", html: '<img src="a.png">')))
        .to eq("<img>")
    end

    it "is nil when nothing was captured" do
      expect(helper.selected_element_label(feedback(url: "/x", html: nil))).to be_nil
    end
  end
end
