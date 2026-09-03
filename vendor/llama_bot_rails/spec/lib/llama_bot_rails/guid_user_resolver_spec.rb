require 'rails_helper'

# Unified Login SSO: an authorized user (owner / assigned operator — the mothership
# only ever issues a grant to those) clicks "Sign in with your LlamaPress.ai account".
#
# LlamaBot chat already auto-creates a shadow user on first consume. The Rails surface
# did not: the default resolver only signed in a PRE-EXISTING Devise user already
# stamped with llamapress_user_guid, so first-time SSO dead-ended with
# `[LlamaBot] unified_login consume: no host user for guid=… — degrading to /`
# (verified live on crm, 2026-07-07).
#
# Safe by construction: the resolver only runs AFTER grant_redeemer succeeds, so
# payload.user.email is mothership-verified server-to-server — NOT user input. That is
# why keying on it here is not the spoofable email-login the default rightly avoids.
#
# The dummy app ships no Devise and no User model, so this spec stands up a minimal
# ActiveRecord model plus a stubbed Devise mapping and exercises the real lambda.
RSpec.describe 'LlamaBotRails.guid_user_resolver' do
  before(:all) do
    conn = ActiveRecord::Base.connection
    unless conn.table_exists?(:sso_resolver_test_users)
      conn.create_table :sso_resolver_test_users do |t|
        t.string :email
        t.string :encrypted_password
        t.string :llamapress_user_guid
        t.timestamps
      end
      conn.add_index :sso_resolver_test_users, :llamapress_user_guid, unique: true
      conn.add_index :sso_resolver_test_users, :email, unique: true
    end

    stub_class = Class.new(ActiveRecord::Base) do
      self.table_name = 'sso_resolver_test_users'
      # Stand in for Devise's writer so the lambda's `respond_to?(:password=)`
      # branch is actually exercised.
      def password=(value)
        self.encrypted_password = value
      end
    end
    Object.const_set(:SsoResolverTestUser, stub_class)
  end

  after(:all) do
    Object.send(:remove_const, :SsoResolverTestUser) if Object.const_defined?(:SsoResolverTestUser)
  end

  let(:user_class) { SsoResolverTestUser }
  let(:guid)    { 'guid-abc-123' }
  let(:email)   { 'operator@example.com' }
  let(:payload) { { 'user' => { 'email' => email } } }

  # Mutable so a single example can point Devise at a different user model.
  let(:mapped_class) { { to: user_class } }

  before do
    user_class.delete_all

    holder = mapped_class
    fake_devise = Module.new do
      define_singleton_method(:default_scope) { :user }
      define_singleton_method(:mappings) do
        { user: Struct.new(:to).new(holder[:to]) }
      end
    end
    stub_const('Devise', fake_devise)
  end

  around do |example|
    previous = LlamaBotRails.provision_sso_users
    example.run
    LlamaBotRails.provision_sso_users = previous
  end

  def resolve(g = guid, p = payload)
    LlamaBotRails.guid_user_resolver.call(g, p)
  end

  describe 'default (provision_sso_users = false) — self-hosters stay opt-out' do
    before { LlamaBotRails.provision_sso_users = false }

    it 'returns an already-linked user by guid' do
      user = user_class.create!(email: 'linked@example.com', llamapress_user_guid: guid)
      expect(resolve).to eq(user)
    end

    it 'returns nil for an unknown guid even when the payload carries an email' do
      user_class.create!(email: email)
      expect(resolve).to be_nil
    end

    it 'never creates a user' do
      expect { resolve }.not_to change(user_class, :count)
    end
  end

  describe 'when provision_sso_users = true (managed Leo boxes)' do
    before { LlamaBotRails.provision_sso_users = true }

    it 'still prefers the guid match over the email match' do
      by_guid = user_class.create!(email: 'other@example.com', llamapress_user_guid: guid)
      user_class.create!(email: email)

      expect(resolve).to eq(by_guid)
    end

    it 'links an existing user with the verified email and stamps the guid' do
      existing = user_class.create!(email: email)

      expect { expect(resolve).to eq(existing) }.not_to change(user_class, :count)
      expect(existing.reload.llamapress_user_guid).to eq(guid)
    end

    it 'provisions a fresh SSO-only user when no one matches' do
      expect { resolve }.to change(user_class, :count).by(1)

      created = user_class.find_by(llamapress_user_guid: guid)
      expect(created).to be_present
      expect(created.email).to eq(email)
    end

    it 'gives the provisioned user a random, unguessable password' do
      resolve
      created = user_class.find_by(llamapress_user_guid: guid)

      expect(created.encrypted_password).to match(/\A[0-9a-f]{64}\z/),
        'the provisioned user must get a random secret, never a blank/known password'
    end

    it 'returns nil when the payload has no email (nothing verified to key on)' do
      expect(resolve(guid, { 'user' => {} })).to be_nil
      expect(resolve(guid, nil)).to be_nil
      expect(user_class.count).to eq(0)
    end

    it 'accepts a symbol-keyed payload' do
      expect { resolve(guid, { user: { email: email } }) }.to change(user_class, :count).by(1)
    end

    it 'returns nil for a blank guid' do
      expect(resolve('', payload)).to be_nil
      expect(resolve(nil, payload)).to be_nil
    end

    it 'is idempotent — a second consume for the same guid reuses the user' do
      first = resolve
      expect { expect(resolve).to eq(first) }.not_to change(user_class, :count)
    end

    it 'recovers instead of raising when a concurrent consume wins the insert race' do
      winner = user_class.create!(email: email, llamapress_user_guid: guid)

      # Simulate the race: both lookups miss, then the unique index rejects our insert.
      allow(user_class).to receive(:find_by).with(llamapress_user_guid: guid).and_return(nil, winner)
      allow(user_class).to receive(:find_by).with(email: email).and_return(nil)

      expect { expect(resolve).to eq(winner) }.not_to raise_error
    end

    it 'returns nil when the host user model has no guid column' do
      no_guid_class = Class.new(ActiveRecord::Base) do
        self.table_name = 'sso_resolver_test_users'
        def self.column_names = %w[id email]
      end
      mapped_class[:to] = no_guid_class

      expect(resolve).to be_nil
    end
  end
end
