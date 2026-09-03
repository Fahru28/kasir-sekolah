require 'rails_helper'

RSpec.describe LlamaBotRails::MothershipReporter do
  ENDPOINT = 'https://mothership.test/api/leonardo/report_error'.freeze

  # Real ENV swap rather than stubbing ENV#[] — the reporter reads three keys
  # through different paths and partial stubs hide ordering bugs.
  def with_env(overrides)
    original = {}
    overrides.each do |key, value|
      original[key] = ENV[key]
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
    yield
  ensure
    original.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def managed_box(extra = {}, &block)
    with_env({
      'MOTHERSHIP_URL' => 'https://mothership.test',
      'MOTHERSHIP_API_TOKEN' => 'tok_abc123',
      'MOTHERSHIP_INSTANCE_NAME' => 'leo-box-42',
      'LLAMA_BOT_ERROR_TELEMETRY' => nil
    }.merge(extra), &block)
  end

  def raised(klass = RuntimeError, message = 'boom')
    raise klass, message
  rescue Exception => e # rubocop:disable Lint/RescueException
    e
  end

  def last_payload
    JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last.body)
  end

  before do
    described_class.async = false
    described_class.reset_throttle!
    stub_request(:post, ENDPOINT).to_return(status: 200, body: '{}')
  end

  after { described_class.async = true }

  describe 'the enable gate' do
    it 'no-ops when there is no mothership token (local dev, ejected apps)' do
      managed_box('MOTHERSHIP_API_TOKEN' => nil) do
        described_class.report_exception(raised)
      end
      expect(a_request(:post, ENDPOINT)).not_to have_been_made
    end

    it 'no-ops when there is no instance name' do
      managed_box('MOTHERSHIP_INSTANCE_NAME' => nil) do
        described_class.report_exception(raised)
      end
      expect(a_request(:post, ENDPOINT)).not_to have_been_made
    end

    it 'no-ops when there is no mothership url' do
      managed_box('MOTHERSHIP_URL' => nil) do
        described_class.report_exception(raised)
      end
      expect(a_request(:post, ENDPOINT)).not_to have_been_made
    end

    it 'honors the LLAMA_BOT_ERROR_TELEMETRY=false kill switch' do
      managed_box('LLAMA_BOT_ERROR_TELEMETRY' => 'false') do
        described_class.report_exception(raised)
      end
      expect(a_request(:post, ENDPOINT)).not_to have_been_made
    end

    it 'reports when the box is a managed Leo instance' do
      managed_box { described_class.report_exception(raised) }
      expect(a_request(:post, ENDPOINT)).to have_been_made.once
    end
  end

  describe 'the receiver contract' do
    it 'posts JSON to the mothership with a bearer token' do
      managed_box { described_class.report_exception(raised) }

      expect(
        a_request(:post, ENDPOINT).with(
          headers: {
            'Authorization' => 'Bearer tok_abc123',
            'Content-Type' => 'application/json'
          }
        )
      ).to have_been_made
    end

    it 'sends source rails_app and the instance name' do
      managed_box { described_class.report_exception(raised) }

      expect(last_payload).to include(
        'source' => 'rails_app',
        'instance_name' => 'leo-box-42',
        'recovered' => false
      )
      expect(last_payload['occurred_at']).to match(/\A\d{4}-\d{2}-\d{2}T/)
    end

    # The server fingerprint is md5(error_class|first_line_of_message[:160]|agent_mode).
    # Anything varying per-request in error_message shatters clustering.
    it 'puts ONLY the exception message in error_message' do
      env = Rack::MockRequest.env_for('/orders/12345?token=secret')

      managed_box { described_class.report_exception(raised(RuntimeError, 'boom'), env: env) }

      expect(last_payload['error_class']).to eq('RuntimeError')
      expect(last_payload['error_message']).to eq('boom')
    end

    it 'puts request context in the traceback header block instead' do
      env = Rack::MockRequest.env_for('/orders/12345', 'REQUEST_METHOD' => 'POST')

      managed_box { described_class.report_exception(raised, env: env) }

      traceback = last_payload['traceback']
      expect(traceback).to include('method: POST')
      expect(traceback).to include('path: /orders/12345')
      expect(traceback).to include("gem_version: #{LlamaBotRails::VERSION}")
      expect(traceback).to include('rails_env: test')
    end

    it 'includes a backtrace slice, capped' do
      exception = raised
      exception.set_backtrace((1..100).map { |i| "/app/models/thing.rb:#{i}:in `call'" })

      managed_box { described_class.report_exception(exception) }

      backtrace_lines = last_payload['traceback'].lines.grep(/thing\.rb/)
      expect(backtrace_lines.size).to eq(described_class::BACKTRACE_LINES)
    end
  end

  describe 'privacy' do
    it 'sends the path without the query string' do
      env = Rack::MockRequest.env_for('/reset?reset_token=super-secret-value')

      managed_box { described_class.report_exception(raised, env: env) }

      expect(last_payload['traceback']).to include('path: /reset')
      expect(last_payload.to_json).not_to include('super-secret-value')
    end

    it 'never sends params, cookies, session, headers or env' do
      env = Rack::MockRequest.env_for(
        '/checkout',
        'REQUEST_METHOD' => 'POST',
        'HTTP_COOKIE' => '_session_id=cookie-secret',
        'HTTP_AUTHORIZATION' => 'Bearer user-secret',
        :input => 'credit_card=4111111111111111'
      )
      env['rack.session'] = { user_id: 99, secret: 'session-secret' }

      managed_box { described_class.report_exception(raised, env: env) }

      body = last_payload.to_json
      expect(body).not_to include('cookie-secret')
      expect(body).not_to include('user-secret')
      expect(body).not_to include('session-secret')
      expect(body).not_to include('4111111111111111')
      expect(last_payload.keys).to match_array(
        %w[instance_name error_class error_message traceback source recovered occurred_at]
      )
    end
  end

  describe 'never breaking the request' do
    it 'swallows a refused connection' do
      stub_request(:post, ENDPOINT).to_raise(Errno::ECONNREFUSED)

      expect {
        managed_box { described_class.report_exception(raised) }
      }.not_to raise_error
    end

    it 'swallows a timeout' do
      stub_request(:post, ENDPOINT).to_timeout

      expect {
        managed_box { described_class.report_exception(raised) }
      }.not_to raise_error
    end

    it 'swallows a 500 from the mothership' do
      stub_request(:post, ENDPOINT).to_return(status: 500, body: 'nope')

      expect {
        managed_box { described_class.report_exception(raised) }
      }.not_to raise_error
    end

    it 'swallows its own internal errors' do
      allow(described_class).to receive(:build_payload).and_raise('reporter bug')

      expect {
        managed_box { described_class.report_exception(raised) }
      }.not_to raise_error
    end

    it 'ignores non-exceptions' do
      expect {
        managed_box { described_class.report_exception('not an exception') }
      }.not_to raise_error
      expect(a_request(:post, ENDPOINT)).not_to have_been_made
    end
  end

  describe 'noise filtering' do
    it 'skips exceptions Rails renders as non-5xx (bot-scan 404s and friends)' do
      managed_box do
        described_class.report_exception(raised(ActionController::RoutingError, 'No route'))
        described_class.report_exception(raised(ActiveRecord::RecordNotFound, 'not found'))
        described_class.report_exception(raised(ActionController::BadRequest, 'bad'))
      end

      expect(a_request(:post, ENDPOINT)).not_to have_been_made
    end

    # 422, but the whole point of the feature.
    it 'always reports CSRF failures despite their non-5xx status' do
      managed_box do
        described_class.report_exception(raised(ActionController::InvalidAuthenticityToken, 'csrf'))
      end

      expect(last_payload['error_class']).to eq('ActionController::InvalidAuthenticityToken')
    end

    it 'reports pending migrations' do
      managed_box do
        described_class.report_exception(raised(ActiveRecord::PendingMigrationError, 'migrations pending'))
      end

      expect(last_payload['error_class']).to eq('ActiveRecord::PendingMigrationError')
    end

    # PendingMigrationError's real message starts with blank lines. The server
    # fingerprints and displays the first line, so an unstripped message shows
    # up on the dashboard as an empty headline.
    it 'strips leading blank lines so the first line is meaningful' do
      managed_box do
        described_class.report_exception(raised(RuntimeError, "\n\nMigrations are pending.\n\nRun bin/rails db:migrate\n"))
      end

      expect(last_payload['error_message'].lines.first).to eq("Migrations are pending.\n")
    end

    it 'reports ordinary 500s' do
      managed_box { described_class.report_exception(raised(NoMethodError, "undefined method `foo'")) }

      expect(last_payload['error_class']).to eq('NoMethodError')
    end
  end

  describe 'double-report guard' do
    it 'reports a given exception object only once, across capture paths' do
      exception = raised

      managed_box do
        described_class.report_exception(exception, env: {}, context: 'rack_middleware')
        described_class.report_exception(exception, context: 'rails_error_reporter')
        described_class.report_exception(exception, context: 'leonardo_error_page')
      end

      expect(a_request(:post, ENDPOINT)).to have_been_made.once
    end

    it 'marks the rack env so the flag is visible when debugging' do
      env = Rack::MockRequest.env_for('/boom')

      managed_box { described_class.report_exception(raised, env: env) }

      expect(env['llama_bot_rails.error_reported']).to be(true)
    end

    it 'still reports a different exception of the same class' do
      managed_box do
        described_class.report_exception(raised)
        described_class.report_exception(raised)
      end

      expect(a_request(:post, ENDPOINT)).to have_been_made.twice
    end
  end

  describe 'throttling' do
    it 'stops after THROTTLE_MAX reports in the window' do
      managed_box do
        (described_class::THROTTLE_MAX + 5).times { described_class.report_exception(raised) }
      end

      expect(a_request(:post, ENDPOINT)).to have_been_made.times(described_class::THROTTLE_MAX)
    end
  end

  describe 'async delivery' do
    it 'delivers off the request thread by default' do
      described_class.async = true

      thread = managed_box { described_class.report_exception(raised) }

      expect(thread).to be_a(Thread)
      thread.join
      expect(a_request(:post, ENDPOINT)).to have_been_made.once
    end
  end
end
