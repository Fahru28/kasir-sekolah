require 'rails_helper'

# Anonymous feedback submissions (Kody, 2026-08-31; blocking leo-borro today).
#
# The purple feedback bubble only ever appeared for signed-in users, and four separate
# layers enforced that: the browser's shouldShowBubble(), the controller's
# require_llama_user!, the default permission_checker, and a NOT NULL user_id.
#
# The engine's own comment said Feedback "can never open up", because there is no honest
# way to show someone their inbox when you do not know who they are. That reasoning is
# right for READING and wrong for WRITING: the bubble does two jobs in one panel, and
# submitting feedback is not per-person. A stranger can do it honestly. So the two jobs
# are split — submitting can open, reading stays shut.
#
# The flag defaults to OFF, so no existing app changes behaviour on upgrade.
RSpec.describe 'anonymous feedback', type: :controller do
  render_views false

  controller_source = LlamaBotRails::Engine.root
    .join('app/controllers/llama_bot_rails/user_feedbacks_controller.rb').read

  # A public endpoint that writes rows will be found by bots, so a submission token is
  # issued with the page and required on submit. 2 hour expiry.
  def valid_token
    Rails.application.message_verifier(:llama_feedback).generate(
      { issued_at: Time.current.to_i }, expires_in: 2.hours
    )
  end

  describe 'the config flag' do
    it 'defaults to off so no existing app changes on upgrade' do
      expect(LlamaBotRails.config).to respond_to(:anonymous_feedback_enabled)
      expect(!!LlamaBotRails.config.anonymous_feedback_enabled).to be(false)
    end
  end

  describe 'the default permission checker' do
    # The checker only bites when require_authentication is on; that is the shape in
    # which a signed-out visitor is refused.
    around do |example|
      was = LlamaBotRails.config.require_authentication
      LlamaBotRails.config.require_authentication = true
      example.run
      LlamaBotRails.config.require_authentication = was
    end

    it 'refuses a stranger by default' do
      expect(LlamaBotRails.permission_checker.call(nil, :submit_feedback)).to be_falsey
    end

    it 'allows a stranger to submit once the flag is on' do
      was = LlamaBotRails.config.anonymous_feedback_enabled
      LlamaBotRails.config.anonymous_feedback_enabled = true
      expect(LlamaBotRails.permission_checker.call(nil, :submit_feedback)).to be_truthy
      LlamaBotRails.config.anonymous_feedback_enabled = was
    end

    it 'still refuses a stranger the per-person screens' do
      was = LlamaBotRails.config.anonymous_feedback_enabled
      LlamaBotRails.config.anonymous_feedback_enabled = true
      expect(LlamaBotRails.permission_checker.call(nil, :view_all_feedback)).to be_falsey
      expect(LlamaBotRails.permission_checker.call(nil, :moderate_feedback)).to be_falsey
      LlamaBotRails.config.anonymous_feedback_enabled = was
    end
  end

  describe 'the model' do
    it 'still demands a user when the flag is off' do
      feedback = LlamaBotRails::UserFeedback.new(title: 'x', description: 'x', user_id: nil)
      feedback.valid?
      expect(feedback.errors[:user_id]).not_to be_empty
    end

    it 'accepts a nil user when the flag is on' do
      was = LlamaBotRails.config.anonymous_feedback_enabled
      LlamaBotRails.config.anonymous_feedback_enabled = true
      feedback = LlamaBotRails::UserFeedback.new(title: 'x', description: 'x', user_id: nil)
      feedback.valid?
      expect(feedback.errors[:user_id]).to be_empty
      LlamaBotRails.config.anonymous_feedback_enabled = was
    end

    it 'has somewhere to record the source, so an abusive one can be traced' do
      expect(LlamaBotRails::UserFeedback.column_names).to include('submitted_ip')
    end
  end

  describe 'POST #create' do
    controller(LlamaBotRails::UserFeedbacksController) {}
    routes { LlamaBotRails::Engine.routes }

    let(:signed_in_user) { double('User', id: 123, email: 'user@example.com') }

    def sign_out!
      allow(LlamaBotRails).to receive(:current_user_resolver).and_return(->(_env) { nil })
    end

    def sign_in!
      allow(LlamaBotRails).to receive(:current_user_resolver).and_return(->(_env) { signed_in_user })
    end

    def enable_anonymous!(on = true)
      allow(LlamaBotRails.config).to receive(:anonymous_feedback_enabled).and_return(on)
    end

    context 'when the flag is OFF (the default)' do
      before { sign_out!; enable_anonymous!(false) }

      it 'does not let a stranger write a row' do
        expect {
          post :create, params: {
            user_feedback: { title: 'Stranger', description: 'from a stranger', feedback_type: 'bug' }
          }, format: :json
        }.not_to change(LlamaBotRails::UserFeedback, :count)

        expect(response).not_to have_http_status(:created)
      end
    end

    context 'when the flag is ON' do
      before { sign_out!; enable_anonymous!(true) }

      it 'accepts a submission carrying a valid token' do
        expect {
          post :create, params: {
            user_feedback: {
              title: 'Checkout',
              description: 'the checkout page is broken',
              feedback_type: 'bug',
              submission_token: valid_token
            }
          }, format: :json
        }.to change(LlamaBotRails::UserFeedback, :count).by(1)

        expect(response).to have_http_status(:created)
        feedback = LlamaBotRails::UserFeedback.last
        expect(feedback.user_id).to be_nil
        expect(feedback.submitted_ip).to be_present
      end

      # A bot that POSTs the endpoint directly, without ever loading a page, has no token.
      it 'refuses a submission with no token' do
        expect {
          post :create, params: {
            user_feedback: { title: 'Bot', description: 'bot', feedback_type: 'bug' }
          }, format: :json
        }.not_to change(LlamaBotRails::UserFeedback, :count)

        expect(response).to have_http_status(:forbidden)
      end

      it 'refuses a tampered token' do
        expect {
          post :create, params: {
            user_feedback: {
              title: 'Bot', description: 'bot', feedback_type: 'bug',
              submission_token: 'not-a-real-token'
            }
          }, format: :json
        }.not_to change(LlamaBotRails::UserFeedback, :count)

        expect(response).to have_http_status(:forbidden)
      end

      it 'refuses an expired token' do
        stale = Rails.application.message_verifier(:llama_feedback).generate(
          { issued_at: 1 }, expires_at: 1.hour.ago
        )
        expect {
          post :create, params: {
            user_feedback: {
              title: 'Stale', description: 'stale', feedback_type: 'bug',
              submission_token: stale
            }
          }, format: :json
        }.not_to change(LlamaBotRails::UserFeedback, :count)

        expect(response).to have_http_status(:forbidden)
      end

      # Return success so the bot cannot tell it failed and tune its way past the trap.
      it 'silently discards a submission that filled the honeypot' do
        expect {
          post :create, params: {
            user_feedback: {
              title: 'Bot', description: 'bot', feedback_type: 'bug',
              submission_token: valid_token
            },
            llama_hp: 'filled by a bot'
          }, format: :json
        }.not_to change(LlamaBotRails::UserFeedback, :count)

        expect(response).to have_http_status(:created)
        expect(JSON.parse(response.body)['success']).to be(true)
      end

      # For a stranger, the attachment path is an open file-upload endpoint. The hidden
      # buttons in the bubble are cosmetic; THIS is the control.
      it 'strips the fields a stranger must not be able to set' do
        post :create, params: {
          user_feedback: {
            title: 'No attachments',
            description: 'no attachments for you',
            feedback_type: 'bug',
            submission_token: valid_token,
            selected_element_html: '<button>x</button>',
            selected_element_selector: 'div#hero',
            selected_element_url: '/pricing'
          }
        }, format: :json

        feedback = LlamaBotRails::UserFeedback.last
        expect(feedback.selected_element_html).to be_nil
        expect(feedback.selected_element_selector).to be_nil
        expect(feedback.selected_element_url).to be_nil
        expect(feedback.attachments).to be_empty
      end
    end

    context 'when a real user is signed in' do
      before { sign_in!; enable_anonymous!(true) }

      # Existing submissions must not start failing because a token is now a thing.
      it 'needs no submission token' do
        expect {
          post :create, params: {
            user_feedback: { title: 'Signed in', description: 'signed in', feedback_type: 'bug' }
          }, format: :json
        }.to change(LlamaBotRails::UserFeedback, :count).by(1)

        expect(response).to have_http_status(:created)
        expect(LlamaBotRails::UserFeedback.last.user_id).to eq(123)
      end

      it 'still keeps the element context a signed-in user sends' do
        post :create, params: {
          user_feedback: {
            title: 'Signed in', description: 'signed in', feedback_type: 'bug',
            selected_element_selector: 'div#hero'
          }
        }, format: :json

        expect(LlamaBotRails::UserFeedback.last.selected_element_selector).to eq('div#hero')
      end
    end
  end

  describe 'the reading surfaces stay shut' do
    it 'leaves Messages behind the identity gate' do
      %w[conversations_controller direct_messages_controller].each do |name|
        src = LlamaBotRails::Engine.root
          .join("app/controllers/llama_bot_rails/#{name}.rb").read
        expect(src).to include('require_llama_user!'), "#{name} lost its identity gate"
        expect(src).not_to include('anonymous_feedback_enabled'),
          "#{name} must not consult the submit-only flag"
      end
    end

    it 'leaves Notifications behind the identity gate' do
      src = LlamaBotRails::Engine.root
        .join('app/controllers/llama_bot_rails/notifications_controller.rb').read
      expect(src).to include('require_llama_user!')
      expect(src).not_to include('anonymous_feedback_enabled')
    end
  end

  describe 'the browser is told, and the bot defences are wired' do
    it 'ships the flag and a submission token to the page' do
      src = LlamaBotRails::Engine.root
        .join('app/controllers/concerns/llama_bot_rails/page_config_injection.rb').read
      expect(src).to include('anonymousFeedbackEnabled')
      expect(src).to include('feedbackSubmissionToken')
    end

    it 'rate limits the public endpoint as a blunt backstop' do
      # Caddy on a Leo box overwrites X-Forwarded-For, so remote_ip there is the LXD
      # bridge and every visitor may share one IP. The token is the real defence; this
      # is only a backstop, and is deliberately not tuned.
      expect(controller_source).to match(/throttle|rate_limit/i)
    end
  end
end


# ---------------------------------------------------------------------------
# A submit without `title` must be a clean 422, never a stack trace
# ---------------------------------------------------------------------------
#
# Found by the mothership running section 5 of the 0.7.6 test plan against the dev
# box (2026-09-01). `title` is NOT NULL in the database
# (20260212000006_create_llama_bot_rails_user_feedbacks.rb:4) but the model only
# capped its length and allowed blank, so a POST omitting it passed every validation,
# reached the INSERT and raised ActiveRecord::NotNullViolation.
#
# Why that is worse than an ordinary 500: Leo boxes run RAILS_ENV=development in
# production, so consider_all_requests_local renders the FULL developer error page —
# our source and the failing SQL row, including the submitter's IP. Before 0.7.6 this
# path required a signed-in user; anonymous feedback opens it to the whole internet,
# and a stranger needs only a CSRF token and a submission token, both handed out on
# any page load. Same class as the Rails.env.development? gate in SI#418.
#
# The bubble always sends a title (feedback_bubble.js appends 'Quick Feedback'), which
# is why no manual test through the UI reaches it.
#
# Asserting on the STATUS, never the body: the developer error page contains
# everything, so a body match would pass against the very thing being prevented.
RSpec.describe 'feedback submitted without a title', type: :controller do
  controller(LlamaBotRails::UserFeedbacksController) {}
  routes { LlamaBotRails::Engine.routes }

  let(:signed_in_user) { double('User', id: 123, email: 'user@example.com') }

  def post_without_title
    post :create, params: {
      user_feedback: {
        description: 'no title field',
        feedback_type: 'general',
        submission_token: Rails.application.message_verifier(:llama_feedback).generate(
          { issued_at: Time.current.to_i }, expires_in: 2.hours
        )
      }
    }, format: :json
  end

  context 'signed out, with anonymous feedback enabled' do
    before do
      allow(LlamaBotRails).to receive(:current_user_resolver).and_return(->(_env) { nil })
      allow(LlamaBotRails.config).to receive(:anonymous_feedback_enabled).and_return(true)
    end

    it 'answers 422 instead of raising' do
      expect { post_without_title }.not_to raise_error
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'writes no row' do
      expect { post_without_title }.not_to change(LlamaBotRails::UserFeedback, :count)
    end
  end

  context 'signed in' do
    before do
      allow(LlamaBotRails).to receive(:current_user_resolver).and_return(->(_env) { signed_in_user })
    end

    it 'answers 422 instead of raising' do
      expect { post_without_title }.not_to raise_error
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
