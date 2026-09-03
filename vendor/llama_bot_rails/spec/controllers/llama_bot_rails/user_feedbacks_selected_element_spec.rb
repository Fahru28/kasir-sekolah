require 'rails_helper'
require_relative '../../support/feedback_tables'

# Pins the "show me what I clicked on" contract: when feedback carries a captured
# element, the show page RENDERS that markup (in a contained, sandboxed frame) instead
# of only printing the source. The source stays available underneath.
RSpec.describe LlamaBotRails::UserFeedbacksController, type: :controller do
  routes { LlamaBotRails::Engine.routes }
  render_views

  before(:all) do
    LlamaBotRails::SpecSupport::FeedbackTables.build!
    LlamaBotRails::SpecSupport::FeedbackTables.wire_helpers!(described_class)
  end

  let(:user) { double('User', id: 123, email: 'user@example.com') }

  before do
    allow(LlamaBotRails).to receive(:current_user_resolver).and_return(->(_env) { user })
  end

  def create_feedback(attrs = {})
    LlamaBotRails::UserFeedback.create!({
      title: 'The Buy now button is the wrong colour',
      description: 'It should be green',
      feedback_type: 'bug',
      user_id: user.id,
      user_email: user.email
    }.merge(attrs))
  end

  describe 'GET #show with a captured element' do
    let(:element_html) { '<button class="btn btn-primary">Buy now</button>' }

    let!(:feedback) do
      create_feedback(
        selected_element_html: element_html,
        selected_element_selector: 'div#hero > button.cta',
        selected_element_url: '/pricing'
      )
    end

    it 'renders the captured markup in a preview frame' do
      get :show, params: { id: feedback.id }

      expect(response.body).to include('id="selected-element-preview"')
      # srcdoc carries the markup as an attribute value, so it arrives escaped in the
      # response and the browser parses it back into a live DOM inside the frame.
      expect(response.body).to include('&lt;button class=&quot;btn btn-primary&quot;&gt;Buy now&lt;/button&gt;')
    end

    it 'sandboxes the frame without same-origin access' do
      get :show, params: { id: feedback.id }

      expect(response.body).to include('sandbox="allow-scripts"')
      expect(response.body).not_to include('allow-same-origin')
    end

    it 'still offers the raw HTML underneath the preview' do
      get :show, params: { id: feedback.id }

      expect(response.body).to include('View HTML')
      expect(response.body).to include('&lt;button class=&quot;btn btn-primary&quot;&gt;Buy now&lt;/button&gt;')
    end

    it 'keeps the selector and source URL visible' do
      get :show, params: { id: feedback.id }

      expect(response.body).to include('div#hero &gt; button.cta')
      expect(response.body).to include('/pricing')
    end
  end

  describe 'GET #show with a script in the captured element' do
    let!(:feedback) do
      create_feedback(
        selected_element_html: %(<div class="card"><script>alert('xss')</script><p>Hi</p></div>)
      )
    end

    it 'drops the script before it reaches the preview frame' do
      get :show, params: { id: feedback.id }

      srcdoc = response.body[/srcdoc="([^"]*)"/, 1]
      expect(srcdoc).to include('&lt;p&gt;Hi&lt;/p&gt;')
      expect(srcdoc).not_to include('alert(')
    end
  end

  describe 'GET #show with an enormous captured element' do
    let!(:feedback) do
      create_feedback(
        selected_element_html: "<div>#{'x' * (LlamaBotRails::FeedbackHelper::SELECTED_ELEMENT_PREVIEW_LIMIT + 1)}</div>"
      )
    end

    it 'skips the preview frame rather than inlining the whole page' do
      get :show, params: { id: feedback.id }

      expect(response.body).not_to include('id="selected-element-preview"')
      expect(response.body).to include('too large to preview')
      expect(response.body).to include('View HTML')
    end
  end

  describe 'GET #show without a captured element' do
    let!(:feedback) { create_feedback }

    it 'renders no preview frame at all' do
      get :show, params: { id: feedback.id }

      expect(response.body).not_to include('id="selected-element-preview"')
      # the whole "Selected element" panel is gone (the heading's icon, not the
      # always-rendered HTML comment that labels the section in the template)
      expect(response.body).not_to include('fa-crosshairs')
    end
  end
end

RSpec.describe LlamaBotRails::FeedbackHelper, type: :helper do
  describe '#selected_element_preview_document' do
    it 'wraps the capture in a document that loads the dashboard stylesheets' do
      doc = helper.selected_element_preview_document('<button>Buy</button>')

      expect(doc).to include('<!DOCTYPE html>')
      expect(doc).to include('cdn.tailwindcss.com')
      expect(doc).to include('daisyui')
      expect(doc).to include('<button>Buy</button>')
    end

    it 'strips scripts, including self-closing and attributed ones' do
      doc = helper.selected_element_preview_document(
        %(<div><script src="/evil.js"></script><script type="text/javascript">steal()</script>ok</div>)
      )

      expect(doc).to include('ok')
      expect(doc).not_to include('evil.js')
      expect(doc).not_to include('steal()')
    end
  end

  describe '#selected_element_preview_too_large?' do
    it 'is false for an ordinary element and nil' do
      expect(helper.selected_element_preview_too_large?('<button>Buy</button>')).to be false
      expect(helper.selected_element_preview_too_large?(nil)).to be false
    end

    it 'is true past the limit' do
      oversized = 'x' * (described_class::SELECTED_ELEMENT_PREVIEW_LIMIT + 1)
      expect(helper.selected_element_preview_too_large?(oversized)).to be true
    end
  end
end
