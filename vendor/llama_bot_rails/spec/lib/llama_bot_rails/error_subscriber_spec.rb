require 'rails_helper'

RSpec.describe LlamaBotRails::ErrorSubscriber do
  let(:reporter) { LlamaBotRails::MothershipReporter }
  let(:error) { RuntimeError.new('job blew up') }

  it 'reports unhandled errors as not recovered' do
    expect(reporter).to receive(:report_exception)
      .with(error, hash_including(recovered: false))

    described_class.new.report(error, handled: false, severity: :error, context: {}, source: 'application')
  end

  it 'reports handled errors as recovered' do
    expect(reporter).to receive(:report_exception)
      .with(error, hash_including(recovered: true))

    described_class.new.report(error, handled: true, severity: :warning, context: {}, source: 'application')
  end

  it 'tags the source so the dashboard shows which hook caught it' do
    expect(reporter).to receive(:report_exception)
      .with(error, hash_including(context: 'rails_error_reporter:active_job'))

    described_class.new.report(error, handled: false, severity: :error, context: {}, source: 'active_job')
  end

  # :info is bookkeeping, not breakage — reporting it would burn the throttle
  # budget a real 500 needs.
  it 'ignores :info severity' do
    expect(reporter).not_to receive(:report_exception)

    described_class.new.report(error, handled: true, severity: :info, context: {}, source: 'application')
  end

  it 'never raises, even if the reporter does' do
    allow(reporter).to receive(:report_exception).and_raise('reporter is broken')

    expect {
      described_class.new.report(error, handled: false, severity: :error, context: {}, source: nil)
    }.not_to raise_error
  end

  # ActionDispatch::Executor/Reloader reports to Rails.error and only THEN
  # re-raises, and on a Leo box the Reloader sits inside both error middlewares.
  # So this subscriber wins the race on every HTTP 500 — if it doesn't pull the
  # request off the execution context, method/path are lost for good (the
  # exception is marked reported, and server-side dedup never upgrades a stored
  # traceback).
  describe 'request context on an HTTP crash' do
    let(:env) { Rack::MockRequest.env_for('/orders/12345', 'REQUEST_METHOD' => 'POST') }

    it 'recovers the rack env from the controller on the execution context' do
      controller = double('controller', request: ActionDispatch::Request.new(env))

      expect(reporter).to receive(:report_exception)
        .with(error, hash_including(env: env))

      described_class.new.report(error, handled: false, severity: :error,
                                        context: { controller: controller }, source: 'application.action_dispatch')
    end

    it 'accepts a request supplied directly on the context' do
      expect(reporter).to receive(:report_exception)
        .with(error, hash_including(env: env))

      described_class.new.report(error, handled: false, severity: :error,
                                        context: { request: ActionDispatch::Request.new(env) }, source: nil)
    end

    it 'passes no env for errors with no request (jobs, async queries)' do
      expect(reporter).to receive(:report_exception)
        .with(error, hash_including(env: nil))

      described_class.new.report(error, handled: false, severity: :error, context: {}, source: 'active_job')
    end

    it 'survives a controller whose request raises' do
      controller = double('controller')
      allow(controller).to receive(:request).and_raise('no request here')
      allow(reporter).to receive(:report_exception)

      expect {
        described_class.new.report(error, handled: false, severity: :error,
                                          context: { controller: controller }, source: nil)
      }.not_to raise_error
    end
  end

  it 'is wired into Rails.error at boot' do
    subscribers = Rails.error.instance_variable_get(:@subscribers) || []
    expect(subscribers.map(&:class)).to include(described_class)
  end
end
