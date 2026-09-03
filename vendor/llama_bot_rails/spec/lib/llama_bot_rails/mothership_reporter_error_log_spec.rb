require 'rails_helper'

# The local recovery feed hangs off the same funnel as mothership telemetry
# (see docs/dev/rails_auto_recovery.md in LlamaBot). These specs pin the part
# that matters: local recording must NOT inherit the mothership's config,
# throttle, or kill switch — a box with no telemetry creds still has to be able
# to fix itself.
RSpec.describe LlamaBotRails::MothershipReporter, 'local error feed' do
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

  def unmanaged_box(&block)
    with_env(
      'MOTHERSHIP_URL' => nil,
      'MOTHERSHIP_API_TOKEN' => nil,
      'MOTHERSHIP_INSTANCE_NAME' => nil,
      'LLAMA_BOT_ERROR_FEED' => nil,
      &block
    )
  end

  def raised(klass = RuntimeError, message = 'boom')
    raise klass, message
  rescue Exception => e # rubocop:disable Lint/RescueException
    e
  end

  before do
    described_class.async = false
    described_class.reset_throttle!
    LlamaBotRails::ErrorLog.reset!
  end

  after { described_class.async = nil }

  it 'records locally even when the mothership is not configured' do
    unmanaged_box do
      described_class.report_exception(raised(ArgumentError, 'no creds here'), recovered: false)
    end

    expect(LlamaBotRails::ErrorLog.since(0).map { |e| e[:message] }).to eq(['no creds here'])
  end

  it 'records locally even when the mothership throttle is exhausted' do
    unmanaged_box do
      allow(described_class).to receive(:throttled?).and_return(true)
      described_class.report_exception(raised(ArgumentError, 'still mine to fix'))
    end

    expect(LlamaBotRails::ErrorLog.since(0).length).to eq(1)
  end

  it 'skips exceptions Rails renders as a non-5xx (routing errors, 404s)' do
    unmanaged_box do
      described_class.report_exception(raised(ActionController::RoutingError, 'No route matches'))
    end

    expect(LlamaBotRails::ErrorLog.since(0)).to be_empty
  end

  it 'records the same exception object only once' do
    exception = raised(ArgumentError, 'reported twice')

    unmanaged_box do
      described_class.report_exception(exception, context: 'rack_middleware')
      described_class.report_exception(exception, context: 'rails_error_reporter')
    end

    expect(LlamaBotRails::ErrorLog.since(0).length).to eq(1)
  end

  it 'does not record when the feed kill switch is off' do
    # Order matters: unmanaged_box clears LLAMA_BOT_ERROR_FEED, so the switch
    # has to be set inside it.
    unmanaged_box do
      with_env('LLAMA_BOT_ERROR_FEED' => 'false') { described_class.report_exception(raised) }
    end

    expect(LlamaBotRails::ErrorLog.since(0)).to be_empty
  end
end
