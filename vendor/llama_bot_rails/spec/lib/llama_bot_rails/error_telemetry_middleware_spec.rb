require 'rails_helper'

RSpec.describe LlamaBotRails::ErrorTelemetryMiddleware do
  let(:env) { Rack::MockRequest.env_for('/boom', 'REQUEST_METHOD' => 'GET') }
  let(:reporter) { LlamaBotRails::MothershipReporter }

  it 'passes successful responses through untouched and reports nothing' do
    app = ->(_env) { [ 200, { 'Content-Type' => 'text/plain' }, [ 'ok' ] ] }
    expect(reporter).not_to receive(:report_exception)

    expect(described_class.new(app).call(env)).to eq([ 200, { 'Content-Type' => 'text/plain' }, [ 'ok' ] ])
  end

  it 'reports the exception and then re-raises it, unchanged' do
    boom = RuntimeError.new('kaboom')
    app = ->(_env) { raise boom }

    expect(reporter).to receive(:report_exception)
      .with(boom, hash_including(env: env, recovered: false, context: 'rack_middleware'))

    expect { described_class.new(app).call(env) }.to raise_error(boom)
  end

  # A pure observer must not swap the app's exception for a telemetry one —
  # that would lose the actual bug.
  it 'raises the ORIGINAL exception even when the reporter itself blows up' do
    app = ->(_env) { raise 'kaboom' }
    allow(reporter).to receive(:report_exception).and_raise('reporter is broken')

    expect { described_class.new(app).call(env) }.to raise_error(RuntimeError, 'kaboom')
  end

  it 'catches exceptions that are not StandardError' do
    app = ->(_env) { raise Exception, 'low level' }

    expect(reporter).to receive(:report_exception)

    expect { described_class.new(app).call(env) }.to raise_error(Exception, 'low level')
  end

  it 'sees pending migrations, which are raised below it in the stack' do
    app = ->(_env) { raise ActiveRecord::PendingMigrationError }

    expect(reporter).to receive(:report_exception)
      .with(instance_of(ActiveRecord::PendingMigrationError), any_args)

    expect { described_class.new(app).call(env) }.to raise_error(ActiveRecord::PendingMigrationError)
  end
end
