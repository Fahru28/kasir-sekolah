require "rails_helper"

# The one styled pagination nav every list page in the fleet renders. Before this
# helper, index views either copied the scaffold's nav markup or called Pagy's
# pagy_nav, which emits unstyled markup that looks broken on a Tailwind page.
RSpec.describe LlamaBotRails::PaginationHelper, type: :helper do
  # Stands in for a Pagy object: the helper only reads these five values, which
  # is also all ScaffoldFiltering::Page (the no-Pagy fallback) exposes.
  def pagy(page:, pages:, count: nil)
    Struct.new(:page, :pages, :count, keyword_init: true) do
      def prev = page > 1 ? page - 1 : nil
      def next = page < pages ? page + 1 : nil
    end.new(page: page, pages: pages, count: count)
  end

  # The nav builds its links off the current URL, so filters survive paging.
  def on_url(path, query = "")
    request = ActionDispatch::TestRequest.create("PATH_INFO" => path, "QUERY_STRING" => query)
    allow(helper).to receive(:request).and_return(request)
  end

  before { on_url("/contacts") }

  describe "#llama_pagination_nav" do
    it "renders nothing when everything fits on one page" do
      expect(helper.llama_pagination_nav(pagy(page: 1, pages: 1, count: 4))).to be_nil
      expect(helper.llama_pagination_nav(nil)).to be_nil
    end

    it "renders prev/next and the page count" do
      html = Nokogiri::HTML.fragment(helper.llama_pagination_nav(pagy(page: 2, pages: 3, count: 60)))

      expect(html.at("p").text).to eq("Page 2 of 3 · 60 total")
      expect(html.at("a[rel='prev']")["href"]).to eq("/contacts?page=1")
      expect(html.at("a[rel='next']")["href"]).to eq("/contacts?page=3")
    end

    it "omits prev on the first page and next on the last" do
      first = Nokogiri::HTML.fragment(helper.llama_pagination_nav(pagy(page: 1, pages: 3)))
      last  = Nokogiri::HTML.fragment(helper.llama_pagination_nav(pagy(page: 3, pages: 3)))

      expect(first.at("a[rel='prev']")).to be_nil
      expect(last.at("a[rel='next']")).to be_nil
    end

    it "marks the current page instead of linking it" do
      html = Nokogiri::HTML.fragment(helper.llama_pagination_nav(pagy(page: 2, pages: 3)))

      expect(html.at("[aria-current='page']").text).to eq("2")
      expect(html.css("a").map(&:text)).not_to include("2")
    end

    it "keeps the other query params on every page link" do
      on_url("/contacts", "q=ada&status=true")
      html = Nokogiri::HTML.fragment(helper.llama_pagination_nav(pagy(page: 1, pages: 2)))

      href = html.at("a[rel='next']")["href"]
      expect(Rack::Utils.parse_query(URI.parse(href).query))
        .to eq("q" => "ada", "status" => "true", "page" => "2")
    end

    it "drops the count for countless pagination" do
      html = Nokogiri::HTML.fragment(helper.llama_pagination_nav(pagy(page: 2, pages: 4)))

      expect(html.at("p").text).to eq("Page 2 of 4")
    end

    it "accepts (and ignores) the keyword args Pagy passes to pagy_nav" do
      expect {
        helper.llama_pagination_nav(pagy(page: 1, pages: 2), id: "pager", anchor_string: 'data-turbo="false"')
      }.not_to raise_error
    end
  end

  describe "#llama_pagination_series" do
    it "lists every page while they still fit" do
      expect(helper.llama_pagination_series(3, 5)).to eq([ 1, 2, 3, 4, 5 ])
    end

    it "gaps the middle on long runs, keeping the ends and the current window" do
      expect(helper.llama_pagination_series(10, 20)).to eq([ 1, :gap, 8, 9, 10, 11, 12, :gap, 20 ])
    end

    it "does not gap a single skipped page" do
      expect(helper.llama_pagination_series(4, 7)).to eq([ 1, 2, 3, 4, 5, 6, 7 ])
    end
  end

  # Apps include Pagy::Frontend in ApplicationHelper, which is mixed in AFTER the
  # engine's helpers — so the styled nav is prepended onto Pagy::Frontend itself
  # rather than defined as a same-named helper, which would lose that race.
  describe LlamaBotRails::PagyNavOverride do
    let(:raw_frontend) do
      Class.new do
        def pagy_nav(_pagy, **_options) = "<nav>raw pagy</nav>"
      end.tap { |klass| klass.prepend(described_class) }
    end

    it "renders the styled nav in a view that has the LlamaPress helper" do
      styled = Class.new(raw_frontend) do
        def llama_pagination_nav(_pagy, **_options) = "<nav>styled</nav>"
      end

      expect(styled.new.pagy_nav(:pagy)).to eq("<nav>styled</nav>")
    end

    it "falls back to Pagy's own nav where the helper is not available" do
      expect(raw_frontend.new.pagy_nav(:pagy)).to eq("<nav>raw pagy</nav>")
    end

    it "is prepended onto Pagy::Frontend when the host has Pagy" do
      skip "host app has no Pagy" unless defined?(::Pagy::Frontend)

      expect(::Pagy::Frontend.ancestors).to include(LlamaBotRails::PagyNavOverride)
    end
  end
end
