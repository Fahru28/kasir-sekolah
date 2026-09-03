require "rails_helper"

# Unified Login Phase 3 — Piece 3.
#
# The gem's default guid_user_resolver (lib/llama_bot_rails.rb) signs a user in
# by looking them up via a `llamapress_user_guid` column:
#
#     user_class.column_names.include?("llamapress_user_guid")
#       ? user_class.find_by(llamapress_user_guid: guid) : nil (warn)
#
# Without the column it warns and signs nobody in — Piece 1's consume controller
# is inert. This migration adds that column (nullable) + a PARTIAL unique index.
#
# The gem's dummy app has no Devise/users table (Piece 1's request specs stub the
# resolver wholesale), so we stand up a minimal `users` table here — simulating
# the host app's Devise table — run the REAL migration file against it, and
# assert the exact schema the resolver depends on. This exercises the migration,
# not a hand-written schema stub. The resolver's Devise wiring is separately
# covered by Piece 1's stubbed request specs.
RSpec.describe "AddLlamapressUserGuidToUsers migration" do
  # A throwaway model bound to the migrated table. Anonymous so it doesn't leak a
  # constant; mirrors the resolver's `user_class.find_by(llamapress_user_guid:)`.
  let(:user_model) do
    Class.new(ActiveRecord::Base) do
      self.table_name = "users"
    end
  end

  before(:all) do
    migration_path = File.expand_path(
      "../../../db/migrate/20260705000001_add_llamapress_user_guid_to_users.rb",
      __FILE__,
    )
    conn = ActiveRecord::Base.connection
    # The host's pre-migration Devise users table (id + a couple columns).
    conn.create_table :users, force: true do |t|
      t.string :email
      t.timestamps
    end
    load migration_path
    AddLlamapressUserGuidToUsers.new.tap { |m| m.verbose = false }.migrate(:up)
  end

  after(:all) do
    ActiveRecord::Base.connection.drop_table :users, if_exists: true
  end

  it "adds a llamapress_user_guid column the resolver detects" do
    # The exact predicate the resolver keys on.
    expect(user_model.column_names).to include("llamapress_user_guid")
  end

  it "resolves a user by llamapress_user_guid (the resolver's data call)" do
    u = user_model.create!(email: "owner@example.com", llamapress_user_guid: "guid-123")
    expect(user_model.find_by(llamapress_user_guid: "guid-123")).to eq(u)
  end

  it "rejects a duplicate non-null guid via the partial unique index" do
    user_model.create!(email: "a@example.com", llamapress_user_guid: "dup")
    expect {
      user_model.create!(email: "b@example.com", llamapress_user_guid: "dup")
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "allows many NULL guids to coexist (WHERE llamapress_user_guid IS NOT NULL)" do
    user_model.create!(email: "c@example.com", llamapress_user_guid: nil)
    expect {
      user_model.create!(email: "d@example.com", llamapress_user_guid: nil)
    }.not_to raise_error
  end
end
