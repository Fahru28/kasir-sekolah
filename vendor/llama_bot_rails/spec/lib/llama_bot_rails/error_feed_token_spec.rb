require 'rails_helper'

RSpec.describe LlamaBotRails::ErrorFeedToken do
  def with_secret(value)
    original = ENV['SECRET_KEY_BASE']
    value.nil? ? ENV.delete('SECRET_KEY_BASE') : ENV['SECRET_KEY_BASE'] = value
    yield
  ensure
    original.nil? ? ENV.delete('SECRET_KEY_BASE') : ENV['SECRET_KEY_BASE'] = original
  end

  it 'derives a stable token from the shared box secret' do
    with_secret('s3cret') do
      expect(described_class.expected).to eq(described_class.expected)
      expect(described_class.expected).to match(/\A[0-9a-f]{64}\z/)
    end
  end

  it 'derives a different token for a different secret' do
    a = with_secret('one') { described_class.expected }
    b = with_secret('two') { described_class.expected }

    expect(a).not_to eq(b)
  end

  it 'is unavailable when the box has no shared secret' do
    with_secret(nil) { expect(described_class.expected).to be_nil }
  end

  it 'is unavailable when the shared secret is blank' do
    with_secret('   ') { expect(described_class.expected).to be_nil }
  end

  describe '.valid?' do
    it 'accepts the derived token' do
      with_secret('s3cret') do
        expect(described_class.valid?(described_class.expected)).to be true
      end
    end

    it 'rejects a wrong token' do
      with_secret('s3cret') { expect(described_class.valid?('nope')).to be false }
    end

    it 'rejects nil and blank' do
      with_secret('s3cret') do
        expect(described_class.valid?(nil)).to be false
        expect(described_class.valid?('')).to be false
      end
    end

    it 'rejects everything when there is no secret to compare against' do
      # Never let a missing secret degrade into "any token works".
      with_secret(nil) do
        expect(described_class.valid?('anything')).to be false
        expect(described_class.valid?(nil)).to be false
      end
    end
  end
end
