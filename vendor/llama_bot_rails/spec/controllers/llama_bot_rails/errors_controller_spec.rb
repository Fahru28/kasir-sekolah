require 'rails_helper'

RSpec.describe LlamaBotRails::ErrorsController, type: :controller do
  routes { LlamaBotRails::Engine.routes }

  let(:valid_token) { Rails.application.message_verifier(:llamabot_ws).generate({ session_id: 'test', user_id: 123 }) }
  let(:mock_user) { double('User', id: 123) }

  def raised(klass = RuntimeError, message = 'boom')
    raise klass, message
  rescue Exception => e # rubocop:disable Lint/RescueException
    e
  end

  def rack_env(path: '/posts/3')
    Rack::MockRequest.env_for("http://example.test#{path}")
  end

  before do
    allow(LlamaBotRails).to receive(:current_user_resolver).and_return(->(_env) { mock_user })
    allow(LlamaBotRails).to receive(:user_resolver).and_return(->(id) { mock_user if id == 123 })
    allow(LlamaBotRails).to receive(:sign_in_method).and_return(->(_env, _user) { true })
    LlamaBotRails::ErrorLog.reset!
  end

  describe 'GET #index with the box feed token' do
    # The credential that matters in practice: LlamaBot reading this box's own
    # error log, with no dependency on whether a human holds a Devise session in
    # some browser tab. That dependency is what made the feature silently
    # no-op on 2026-08-24.
    let(:feed_token) { LlamaBotRails::ErrorFeedToken.expected }

    it 'accepts it with no Devise session and no agent token' do
      LlamaBotRails::ErrorLog.record(raised(TypeError, 'seen by the box'), env: rack_env)
      request.headers['Authorization'] = "LlamaBotFeed #{feed_token}"

      get :index, params: { within: 120 }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['errors'].map { |e| e['message'] }).to eq(['seen by the box'])
    end

    it 'rejects a wrong feed token' do
      request.headers['Authorization'] = 'LlamaBotFeed not-the-token'

      get :index

      expect(response).to have_http_status(:forbidden)
    end

    it 'rejects the right token under the wrong scheme' do
      request.headers['Authorization'] = "LlamaBot #{feed_token}"

      get :index

      expect(response).to have_http_status(:forbidden)
    end

    it 'rejects it when the box has no shared secret' do
      original = ENV['SECRET_KEY_BASE']
      ENV.delete('SECRET_KEY_BASE')
      request.headers['Authorization'] = "LlamaBotFeed #{original}"

      get :index

      expect(response).to have_http_status(:forbidden)
    ensure
      ENV['SECRET_KEY_BASE'] = original
    end
  end

  describe 'GET #index' do
    context 'without agent authentication' do
      it 'refuses to hand out backtraces' do
        get :index
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with agent authentication' do
      before { request.headers['Authorization'] = "LlamaBot #{valid_token}" }

      it 'returns the current cursor and no entries when no since is given' do
        LlamaBotRails::ErrorLog.record(raised(ArgumentError, 'old news'), env: rack_env)

        get :index

        body = JSON.parse(response.body)
        expect(response).to have_http_status(:ok)
        expect(body['seq']).to eq(LlamaBotRails::ErrorLog.latest_seq)
        expect(body['errors']).to eq([])
      end

      it 'returns only entries newer than since' do
        LlamaBotRails::ErrorLog.record(raised(ArgumentError, 'old news'), env: rack_env)
        cursor = LlamaBotRails::ErrorLog.latest_seq
        LlamaBotRails::ErrorLog.record(raised(TypeError, 'fresh breakage'), env: rack_env(path: '/x'))

        get :index, params: { since: cursor }

        body = JSON.parse(response.body)
        expect(body['errors'].map { |e| e['message'] }).to eq(['fresh breakage'])
        expect(body['errors'].first['error_class']).to eq('TypeError')
        expect(body['errors'].first['path']).to eq('/x')
        expect(body['seq']).to eq(LlamaBotRails::ErrorLog.latest_seq)
      end

      it 'returns an empty feed when the cursor is already current' do
        LlamaBotRails::ErrorLog.record(raised, env: rack_env)

        get :index, params: { since: LlamaBotRails::ErrorLog.latest_seq }

        expect(JSON.parse(response.body)['errors']).to eq([])
      end

      it 'returns recent entries for a within window' do
        LlamaBotRails::ErrorLog.record(raised(TypeError, 'broken right now'), env: rack_env)

        get :index, params: { within: 120 }

        body = JSON.parse(response.body)
        expect(body['errors'].map { |e| e['message'] }).to eq(['broken right now'])
        expect(body['seq']).to eq(LlamaBotRails::ErrorLog.latest_seq)
      end

      it 'excludes entries older than the within window' do
        LlamaBotRails::ErrorLog.record(
          raised(TypeError, 'ancient'), env: rack_env, now: Time.now - 600
        )

        get :index, params: { within: 120 }

        expect(JSON.parse(response.body)['errors']).to eq([])
      end

      it 'lets since win when both are given' do
        LlamaBotRails::ErrorLog.record(raised(TypeError, 'recent'), env: rack_env)

        get :index, params: { since: LlamaBotRails::ErrorLog.latest_seq, within: 600 }

        expect(JSON.parse(response.body)['errors']).to eq([])
      end

      it 'treats a non-numeric within as a cursor probe instead of raising' do
        LlamaBotRails::ErrorLog.record(raised, env: rack_env)

        get :index, params: { within: 'soon' }

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['errors']).to eq([])
      end

      it 'treats a non-numeric since as a cursor probe instead of raising' do
        LlamaBotRails::ErrorLog.record(raised, env: rack_env)

        get :index, params: { since: 'not-a-number' }

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['errors']).to eq([])
      end
    end
  end
end
