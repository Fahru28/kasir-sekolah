# llama_bot_rails

A Rails engine that integrates LlamaBot (LangGraph AI agent) into Ruby on Rails applications.

## Location in the Ecosystem

This gem is a **git submodule** of `LlamaPress-Simple`:

```
LlamaPress-Simple/
  └── vendor/
      └── llama_bot_rails/  ← You are here (submodule)
```

**Submodule URL:** https://github.com/KodyKendall/llama_bot_rails.git

## Symlink for Cross-Project Access

A symlink at `/LLMPress/llama_bot_rails_symlink` points here for legacy compatibility.

## Preferred development path (on the llamapress-dev box)

**Develop directly in the vendored copy** at
`LlamaPress-Simple/vendor/llama_bot_rails` — do NOT use the standalone clone at
`~/dev/llama_bot_rails` for active work. Rationale (Kody, 2026-07-05): this is faster
for everything, and our distribution pattern is that **LlamaPress-Simple gets baked
into a Docker image** (`kody06/llamapress-simple`) and shipped that way — the vendored
copy is what actually ships, and it hot-reloads into the running `llamapress`
container via the compose mount. The standalone clone is only for opening PRs against
the gem's own GitHub repo when that's explicitly needed. Editing here leaves the
LlamaPress-Simple parent repo showing a dirty submodule until commits are moved over;
that's expected and fine — the human manages git.

## Making Changes

Since this is a submodule, changes must be committed separately:

```bash
# 1. Make changes here
cd /LLMPress/LlamaPress-Simple/vendor/llama_bot_rails

# 2. Commit to the submodule repo
git add .
git commit -m "Your changes"
git push

# 3. Update parent repo to track new commit
cd /LLMPress/LlamaPress-Simple
git add vendor/llama_bot_rails
git commit -m "Update llama_bot_rails submodule"
```

## Running Tests Locally

```bash
# Activate Ruby via mise
source ~/.zshrc
# or
eval "$(mise activate bash)"

# Run tests
bundle install
bundle exec rspec
```

## Running Tests in Docker

The gem has its **own** dependency set (its `Gemfile.lock` — Rails 8.1.x, rspec-rails,
sqlite3) that is separate from the host app's bundle baked into the `llamapress`
container. So you must install the gem's bundle to a local (gitignored) path first,
then run RSpec with the container's Postgres env unset (the dummy app uses sqlite; a
leaked `DATABASE_URL` makes Rails demand `pg`, which isn't in the gem's bundle):

**Never run `bundle config set --local …` inside the container.** The image sets
`BUNDLE_APP_CONFIG=/usr/local/bundle`, so "local" config is written **container-global**:
`path vendor/bundle` re-points the HOST APP's bundle at `/rails/vendor/bundle` (empty),
and `leonardo-llamapress-1` crash-loops with `bundler: command not found: rails`. Recover
with `docker compose -f docker-compose-dev.yml up -d --force-recreate llamapress`. Pass the
paths as env for the one command instead:

```bash
cd ~/dev/Leonardo
# one-time: install the gem's own bundle into ./vendor/bundle (gitignored)
docker compose -f docker-compose-dev.yml exec -T llamapress bash -lc \
  'cd /rails/vendor/llama_bot_rails && env BUNDLE_PATH=/rails/vendor/llama_bot_rails/vendor/bundle \
   BUNDLE_GEMFILE=/rails/vendor/llama_bot_rails/Gemfile BUNDLE_FROZEN=false bundle install'

# run the suite (unset DATABASE_URL/DB_URI so the dummy app uses sqlite)
docker compose -f docker-compose-dev.yml exec -T llamapress bash -lc \
  'cd /rails/vendor/llama_bot_rails && env -u DATABASE_URL -u DB_URI \
   BUNDLE_PATH=/rails/vendor/llama_bot_rails/vendor/bundle \
   BUNDLE_GEMFILE=/rails/vendor/llama_bot_rails/Gemfile \
   BUNDLE_FROZEN=false RAILS_ENV=test bundle exec rspec'
```

### Fresh container: `PendingMigrationError` aborts the whole suite (exit 1)

On a freshly (re)created `llamapress` container the dummy app's test DB
(`spec/dummy/storage/test.sqlite3`, gitignored) has an empty `schema_migrations`,
so `rails_helper`'s `maintain_test_schema!` sees every migration as pending and
`exit 1`s the entire run before any example executes. You **cannot** fix it with
`rake app:db:migrate`: the committed `spec/dummy/db/schema.rb` is `version: 0`
(so `db:test:prepare` stamps nothing), and one existing migration
(`20260213000001_create_llama_bot_rails_shared_links`) adds an FK to
`active_storage_attachments`, a table the dummy app never creates → sqlite
`no such table` aborts the migrate. (These are also the source of the ~40
pre-existing spec failures — unrelated to Unified Login.)

Prep the test DB once by stamping the existing migration versions as applied
(pure local test-DB state, no committed-file changes), then run rspec normally:

```bash
docker compose -f docker-compose-dev.yml exec -T llamapress bash -lc \
  'cd /rails/vendor/llama_bot_rails && env -u DATABASE_URL -u DB_URI RAILS_ENV=test bundle exec rake app:db:test:prepare && \
   env -u DATABASE_URL -u DB_URI BUNDLE_GEMFILE=$PWD/Gemfile bundle exec ruby -e "
     require %q{sqlite3}; db = SQLite3::Database.new(%q{spec/dummy/storage/test.sqlite3})
     db.execute(%q{CREATE TABLE IF NOT EXISTS schema_migrations (version varchar NOT NULL PRIMARY KEY)})
     Dir[%q{db/migrate/*.rb}].each { |f| db.execute(%q{INSERT OR IGNORE INTO schema_migrations (version) VALUES (?)}, [File.basename(f).split(%q{_}).first]) }"'
```

Re-run the stamp step after ADDING a new migration file (its version is unstamped
→ pending again). Specs that build their own tables (e.g. the Unified Login
migration spec) then pass without needing the real schema.

### The suite is RED by default — baseline before/after, don't trust an absolute count

Once the DB is prepped, the suite still reports a large fixed number of failures —
**416 examples / 52 failures** at `5ee54f6` (2026-08-17); re-measure rather than
trusting that number. (e.g. `agent_controller_spec` does `get :chat`, but
`agent/chat`, `/`, `agent/chat_ws` are **commented out** in `config/routes.rb` →
`No route matches agent#chat`; plus the `active_storage` FK feature specs, and every
controller spec that renders the Inbox layout, where `InboxHelper` is not wired into
the view context.) These are **pre-existing and unrelated to whatever you're
building.** So:

- **Never assume red = you broke it.** Measure the *delta*: run the suite before
  your change (or with your new specs `--exclude-pattern`'d / your new route
  initializer env-guarded), note `N examples / F failures`, then confirm your
  change moves it to `N+k / F` — same failure count, `+k` passing. Cheapest way to get
  a true baseline without stashing: `git worktree add tmp/baseline_head HEAD --detach`
  INSIDE the gem dir (it is inside the container mount), prep its own sqlite test DB the
  same way, run rspec there, then `git worktree remove` (the container writes root-owned
  files — `chown` them back from a root exec first). (Worked
  example: a clean additive feature went `197/40 → 222/40`, i.e. +25 passing, 0
  new failures.)
- **This branch has no meaningful green CI gate.** A red run looks identical
  whether or not a real regression is hiding in it. Before shipping via a
  submodule bump, triage those failures (or delete the dead specs) so CI actually
  protects the release — otherwise a genuine break is invisible.

The old one-liner below fails on this box: the container bundle can't resolve the
gem's gems (`Bundler::GemNotFound`), and even after `bundle install` a leaked
`DATABASE_URL` triggers `pg is not part of the bundle`.
```bash
# (does NOT work as-is here — see above)
docker compose exec llamapress bash -c "cd /rails/vendor/llama_bot_rails && bundle exec rspec"
```

## Docker Build Note

The Dockerfile in `LlamaPress-Simple` removes `.git` files from this submodule during build:
```dockerfile
RUN find vendor -name ".git" -type f -delete
```

This is necessary because the `.git` file points to `../../.git/modules/vendor/llama_bot_rails` which doesn't exist in the Docker build context.

## Mounting the Engine

In client projects, add to `config/routes.rb`:
```ruby
mount LlamaBotRails::Engine => "/llama_bot"
```

## Unified Login — `GET /llamapress_auth/consume` (Phase 3)

Full design + rollout: **`docs/dev/unified_login_consume.md`**. Load-bearing facts
that bite if forgotten:

- **The route is at the host ROOT, not under `/llama_bot`.** The frozen Phase 2
  frontend calls `{railsUrl}/llamapress_auth/consume`. The engine **prepends** it
  onto the host app's routes from an initializer (`engine.rb`) — do NOT move it
  under the engine mount, and do NOT expect it in `config/routes.rb`.
- **Never key a user by email.** `LlamaBotRails.guid_user_resolver` maps a stable
  `llamapress_user_guid` → host user. Email in a grant is not proof of ownership.
- **Cross-repo contract with LlamaBot** (`app/routers/unified_login.py`
  `POST /internal/redeem_rails_grant` → mothership `verify_login_grant(_, "rails_app")`):
  a **200 response MUST carry `success: true`** in its body — the gem's
  `redeem_rails_grant` treats a 200 without it as failure (`redeem_failed_200`).
  Both sides are pinned by tests (gem: `spec/lib/.../redeem_rails_grant_spec.rb`;
  LlamaBot: `app/tests/test_unified_login.py`) but the contract is only real if
  they agree — verify both when touching either.
- **Inert until two things land:** the mothership flips `unified_login_mode`, AND
  the host app has the `llamapress_user_guid` column installed
  (`rails llama_bot_rails:install:migrations` in the client app — "Piece 3c").
  Without the column the default resolver just warns and signs no one in; consume
  degrades to a redirect. Safe, but the feature does nothing on the fleet until 3c.

## Migrations

**Important:** Migrations are NOT auto-loaded. They must be explicitly installed.

### Why explicit installation?

Auto-loading migrations was causing `PG::DuplicateTable` errors in downstream forks. When apps ran `rails llama_bot_rails:install:migrations`, the migrations were copied to `db/migrate/` with new timestamps. The auto-loader then appended the engine's original migrations (with different timestamps), causing Rails to see BOTH sets and try to run both.

See [engine.rb](lib/llama_bot_rails/engine.rb) for the detailed explanation in comments.

### Workflow for Upstream Leonardo

When adding new migrations to llama_bot_rails:

```bash
# 1. Add migration file to vendor/llama_bot_rails/db/migrate/

# 2. In Leonardo, install the new migrations
rails llama_bot_rails:install:migrations
rails db:migrate

# 3. Commit both the engine migration AND the installed copy
git add vendor/llama_bot_rails/db/migrate/
git add db/migrate/
git commit -m "Add new llama_bot_rails migration"
```

### Workflow for Downstream Forks

**DO NOT run `rails llama_bot_rails:install:migrations` on downstream forks!**

Downstream apps just merge from upstream - migrations are already in `db/migrate/`:

```bash
git fetch upstream
git merge upstream/main
rails db:migrate
```

Running `install:migrations` on a downstream fork will create NEW migration files with different timestamps, causing `PG::DuplicateTable` errors because the tables already exist but `schema_migrations` has different version numbers.

### One-Time Fix for Downstream Forks (Migration Mismatch)

If a downstream fork has `PG::DuplicateTable` errors after merging from upstream, the database has tables created with OLD timestamps (from the deprecated auto-loader) but `schema_migrations` doesn't have the NEW timestamps from upstream's installed migrations.

**Fix:** Mark the new migrations as already run, then remove orphaned old timestamps:

```bash
# 1. Find which migrations are failing (look for "down" status where table exists)
docker compose exec llamapress bundle exec rails db:migrate:status

# 2. Insert the new migration versions that came from upstream
# (Replace these with the actual versions from your db/migrate/ files)
docker compose exec llamapress bundle exec rails runner '
  # Get all llama_bot_rails migration versions from files
  migrations = Dir["/rails/db/migrate/*llama_bot_rails*.rb"].map { |f| File.basename(f).split("_").first }
  migrations.each do |v|
    ActiveRecord::Base.connection.execute("INSERT INTO schema_migrations (version) VALUES ('\''#{v}'\'') ON CONFLICT DO NOTHING")
    puts "Inserted #{v}"
  end
'

# 3. Remove orphaned "NO FILE" entries (old auto-loaded timestamps)
docker compose exec llamapress bundle exec rails runner '
  # Find versions with no corresponding file
  all_versions = ActiveRecord::Base.connection.select_values("SELECT version FROM schema_migrations ORDER BY version")
  all_files = Dir["/rails/db/migrate/*.rb"].map { |f| File.basename(f).split("_").first }
  orphans = all_versions - all_files
  orphans.each do |v|
    ActiveRecord::Base.connection.execute("DELETE FROM schema_migrations WHERE version = '\''#{v}'\''")
    puts "Deleted orphan #{v}"
  end
'

# 4. Verify - should show no "NO FILE" entries for llama_bot_rails
docker compose exec llamapress bundle exec rails db:migrate:status | grep llama
```

### Key Points

- **Single source of truth**: Migrations live in Leonardo's `db/migrate/`, committed to git
- **Consistent timestamps**: Everyone uses the same migration timestamps from upstream
- **Idempotent**: `rails llama_bot_rails:install:migrations` only copies new migrations
- **Rails standard**: This is the [recommended approach](https://guides.rubyonrails.org/engines.html#migrations)

## Related Projects

- **LlamaPress-Simple**: Parent repo (base Docker image)
- **Leonardo**: Development template that uses this engine
- **LlamaBot**: Python LangGraph service this engine communicates with
