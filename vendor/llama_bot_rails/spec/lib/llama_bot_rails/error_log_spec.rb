require 'rails_helper'

RSpec.describe LlamaBotRails::ErrorLog do
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

  def raised(klass = RuntimeError, message = 'boom')
    raise klass, message
  rescue Exception => e # rubocop:disable Lint/RescueException
    e
  end

  def rack_env(method: 'GET', path: '/posts/3')
    Rack::MockRequest.env_for("http://example.test#{path}", method: method)
  end

  before { described_class.reset! }

  describe '.record' do
    it 'captures class, message, request method and path' do
      described_class.record(raised(ArgumentError, 'bad arg'), env: rack_env(path: '/posts/3'))

      entry = described_class.since(0).last
      expect(entry[:error_class]).to eq('ArgumentError')
      expect(entry[:message]).to eq('bad arg')
      expect(entry[:method]).to eq('GET')
      expect(entry[:path]).to eq('/posts/3')
      expect(entry[:backtrace]).to be_an(Array)
    end

    it 'assigns strictly increasing sequence numbers' do
      described_class.record(raised(ArgumentError, 'one'), env: rack_env)
      described_class.record(raised(TypeError, 'two'), env: rack_env)

      seqs = described_class.since(0).map { |e| e[:seq] }
      expect(seqs.length).to eq(2)
      expect(seqs.last).to be > seqs.first
    end

    it 'keeps only the most recent MAX_ENTRIES' do
      (described_class::MAX_ENTRIES + 5).times do |i|
        described_class.record(raised(RuntimeError, "boom #{i}"), env: rack_env)
      end

      entries = described_class.since(0)
      expect(entries.length).to eq(described_class::MAX_ENTRIES)
      expect(entries.first[:message]).to eq('boom 5')
    end

    it 'collapses a repeat of the newest fingerprint into a count' do
      described_class.record(raised(RuntimeError, 'same'), env: rack_env(path: '/a'))
      first_seq = described_class.since(0).last[:seq]
      described_class.record(raised(RuntimeError, 'same'), env: rack_env(path: '/a'))

      entries = described_class.since(0)
      expect(entries.length).to eq(1)
      expect(entries.last[:count]).to eq(2)
      # Re-stamped so a poller that already consumed it sees the repeat.
      expect(entries.last[:seq]).to be > first_seq
    end

    it 'does not collapse a different fingerprint' do
      described_class.record(raised(RuntimeError, 'one'), env: rack_env(path: '/a'))
      described_class.record(raised(RuntimeError, 'two'), env: rack_env(path: '/a'))

      expect(described_class.since(0).length).to eq(2)
    end

    it 'records an exception with no backtrace and no rack env' do
      expect { described_class.record(ArgumentError.new('bare')) }.not_to raise_error
      entry = described_class.since(0).last
      expect(entry[:error_class]).to eq('ArgumentError')
      expect(entry[:backtrace]).to eq([])
      expect(entry[:path]).to be_nil
    end

    it 'never raises when the entry cannot be built' do
      allow(described_class).to receive(:build_entry).and_raise('kaboom')
      expect { described_class.record(raised) }.not_to raise_error
      expect(described_class.since(0)).to be_empty
    end

    it 'is a no-op when LLAMA_BOT_ERROR_FEED is false' do
      with_env('LLAMA_BOT_ERROR_FEED' => 'false') do
        described_class.record(raised, env: rack_env)
        expect(described_class.since(0)).to be_empty
      end
    end
  end

  describe '.since' do
    it 'returns only entries newer than the given cursor' do
      described_class.record(raised(RuntimeError, 'one'), env: rack_env)
      cursor = described_class.latest_seq
      described_class.record(raised(TypeError, 'two'), env: rack_env)

      fresh = described_class.since(cursor)
      expect(fresh.map { |e| e[:message] }).to eq(['two'])
    end

    it 'returns nothing when the cursor is already current' do
      described_class.record(raised, env: rack_env)
      expect(described_class.since(described_class.latest_seq)).to be_empty
    end
  end
end

RSpec.describe LlamaBotRails::ErrorLog, '.within' do
  def raised(klass = RuntimeError, message = 'boom')
    raise klass, message
  rescue Exception => e # rubocop:disable Lint/RescueException
    e
  end

  def rack_env(path: '/')
    Rack::MockRequest.env_for("http://example.test#{path}")
  end

  before { described_class.reset! }

  # The "it was already broken when the user asked" case: a turn arms itself by
  # asking what has crashed RECENTLY, not by taking the whole ring (which would
  # replay ancient crashes into an unrelated request).
  it 'returns entries recorded inside the window' do
    described_class.record(raised(RuntimeError, 'just now'), env: rack_env)

    expect(described_class.within(120).map { |e| e[:message] }).to eq(['just now'])
  end

  it 'excludes entries older than the window' do
    described_class.record(
      raised(RuntimeError, 'ancient history'), env: rack_env, now: Time.now - 600
    )

    expect(described_class.within(120)).to be_empty
  end

  it 'keeps the newest entries when the window spans several crashes' do
    described_class.record(raised(RuntimeError, 'old'), env: rack_env(path: '/a'), now: Time.now - 600)
    described_class.record(raised(TypeError, 'recent'), env: rack_env(path: '/b'))

    expect(described_class.within(120).map { |e| e[:message] }).to eq(['recent'])
  end

  it 'does not leak internal bookkeeping into the entry' do
    described_class.record(raised, env: rack_env)

    expect(described_class.within(120).first).not_to have_key(:recorded_at)
    expect(described_class.since(0).first).not_to have_key(:recorded_at)
  end

  it 'is empty when the feed is disabled' do
    ENV['LLAMA_BOT_ERROR_FEED'] = 'false'
    described_class.record(raised, env: rack_env)
    expect(described_class.within(120)).to be_empty
  ensure
    ENV.delete('LLAMA_BOT_ERROR_FEED')
  end
end
