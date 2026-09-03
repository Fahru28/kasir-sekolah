# Unified Login — Phase 3: `GET /llamapress_auth/consume` (gem side)

> **Audience:** Developers working on `llama_bot_rails` and the LlamaPress stack.
>
> **Scope:** How the gem signs a user into the host Rails app's Devise session
> from a one-time login grant, so the chat's live-preview iframe skips the Devise
> login wall. This is the **Rails gem leg** of the Unified Login program.
> Phases 0+1 (mothership) and Phase 2 (LlamaBot) are separate.
>
> **Status:** implemented, tests green. **Inert until** the mothership flips
> `unified_login_mode` — nothing links to this route until then.

---

## 1  Why this exists

Unified Login makes `llamapress.ai` the identity provider for the box surfaces.
A grant minted by the mothership is redeemable **once per audience**: LlamaBot
consumes the `llamabot` audience (Phase 2), and the generated Rails app consumes
the `rails_app` audience (this phase). Consuming `rails_app` is what kills the
Devise login wall that otherwise appears inside the chat's live-preview iframe.

The frozen Phase 2 frontend (`IframeManager.js`) sets the iframe src to:

```
{railsUrl}/llamapress_auth/consume?token=<raw grant>&return_to=%2F
```

…but **only** when the top window arrived with `?rails_token=`. With no token,
the iframe loads exactly as it does today (the Devise wall). That is the entire
backwards-compat story — see §6.

---

## 2  Request flow

```
Browser (chat iframe)
   │  GET {railsUrl}/llamapress_auth/consume?token=<grant>&return_to=/
   ▼
UnifiedLoginController#consume  (host app root route, NOT under /llama_bot)
   │  1. sanitize return_to (open-redirect guard)
   │  2. no token? → redirect to return_to (never a wall, never an error)
   │  3. LlamaBotRails.grant_redeemer.call(token)  ── Option 1 ──▶ LlamaBot
   │                                                   POST /internal/redeem_rails_grant
   │                                                        │  server-to-server, holds the
   │                                                        ▼  mothership token, NOT Rails
   │                                              Mothership verify_login_grant(token,"rails_app")
   │  4. resolve host user:  LlamaBotRails.guid_user_resolver.call(guid, payload)
   │  5. sign in:            LlamaBotRails.sign_in_method.call(request.env, user)   (Warden)
   │  6. redirect to sanitized return_to
   ▼
Host app is now authenticated in the iframe.
```

### Why proxy through LlamaBot (Option 1)

The Rails container has **no mothership credentials** — `.leonardo/instance.json`
(with `mothership_api_token`) is mounted only into the **llamabot** service. So
the gem cannot call the mothership directly. Instead it calls a small internal
LlamaBot endpoint over the already-trusted Rails↔LlamaBot channel
(`config.llama_bot_rails.llamabot_api_url`, default `http://llamabot-backend:8000`).
This keeps the mothership token **out of the Rails container** — the whole point
of the Unified Login program (shrinking secret spread). The trade-off is that
Phase 3 is *also* a small LlamaBot change (the `/internal/redeem_rails_grant`
endpoint), not gem-only.

---

## 3  The pieces (this gem)

| File | Responsibility |
| --- | --- |
| `app/controllers/llama_bot_rails/unified_login_controller.rb` | The `consume` action + `return_to` open-redirect guard. |
| `lib/llama_bot_rails/engine.rb` | Initializer that **prepends** the root route onto the host app. |
| `lib/llama_bot_rails.rb` | Two injectable hooks + Devise defaults (`grant_redeemer`, `guid_user_resolver`). |
| `lib/llama_bot_rails/llama_bot.rb` | `redeem_rails_grant(token)` — the HTTP call to the LlamaBot proxy. |

### 3.1  Root-route injection (no host `routes.rb` edits)

The frozen frontend calls the route at the **app root**, but the engine is
mounted at `/llama_bot`. Rather than requiring every host app / fork to add a
line to its `routes.rb`, the engine prepends the route onto the host's route set
from an initializer:

```ruby
initializer "llama_bot_rails.unified_login_route" do |app|
  app.routes.prepend do
    get "/llamapress_auth/consume",
        to: "llama_bot_rails/unified_login#consume",
        as: :llamapress_auth_consume
  end
end
```

Every downstream app gets the route automatically on upgrade. `prepend` means it
resolves ahead of any host catch-all at the same path (no host uses this path
today).

### 3.2  Injectable seams (mirrors the existing `user_resolver` pattern)

The gem already integrates with host auth through configurable lambdas
(`user_resolver`, `current_user_resolver`, `sign_in_method`). Phase 3 adds two
more, both with Devise-aware defaults, overridable in a host initializer:

- **`LlamaBotRails.grant_redeemer`** — `token -> [payload, error_code]`.
  Default proxies through LlamaBot (Option 1). Never raises.
- **`LlamaBotRails.guid_user_resolver`** — `(guid, payload) -> User | nil`.
  Default looks the user up by a stable `llamapress_user_guid` column **when the
  host app has one**. **Never keys by email** (a grant's email is not proof of
  ownership of a local account). Host apps that model external identity
  differently (shadow-user table, first-user provisioning) override this.

Sign-in reuses the existing `sign_in_method` hook (`env['warden'].set_user`).

---

## 4  The redeem contract (gem ↔ LlamaBot)

`POST {llamabot_api_url}/internal/redeem_rails_grant`

Request: `{ "token": "<raw grant>" }`

The LlamaBot endpoint forwards to the mothership's
`verify_login_grant(token, "rails_app")` and relays the result verbatim:

- **Success** `200`:
  ```json
  { "success": true,
    "user": { "guid": "…", "email": "…", "name": "…" },
    "role": "owner", "permissions": ["chat", "rails_app"] }
  ```
  (For `rails_app` there is **no** `link_username` — that is llamabot-only.)
- **Failure**: `{ "success": false, "error_code": "…" }` with the mothership's
  status — `404 grant_not_found` · `410 grant_expired` · `409 grant_used` ·
  `422 bad_audience`. Transport failures map to `llamabot_unreachable`.

`redeem_rails_grant` returns `[payload, nil]` on success and `[nil, error_code]`
otherwise; a bare non-200 with no body maps to `redeem_failed_<code>`. It uses a
5s open/read timeout and **never raises**.

Grants are **5-minute, single-use per audience**. `grant_expired` / `grant_used`
are **expected** on refresh/bookmark — they must degrade gracefully (§5), never
error-page. LlamaBot already consumed the `llamabot` audience; the gem consumes
`rails_app`.

---

## 5  Failure handling — never a wall, never a 500

Every unhappy path resolves to a **plain redirect to the sanitized `return_to`
(default `/`)**:

| Situation | Behavior |
| --- | --- |
| No token | Redirect to `return_to`. (Someone hit the endpoint directly.) |
| Redeem failed (expired/used/not-found/unreachable) | Redirect to `return_to`. If a valid session already exists the user simply lands on the app; if not, they get the app's normal login. |
| Grant OK but no host user for the guid | Redirect to `return_to` (logged as a warning). |
| Grant OK, user resolved | Sign in, redirect to `return_to`. |

The **one-bounce-max retry** semantics (re-minting a fresh grant via the
mothership `sso/leo` endpoint) live on the mothership + LlamaBot, **not** the
gem. The gem's only obligation is to never error-page.

### `return_to` open-redirect guard

`sanitize_return_to` accepts only a same-origin, path-only target. Anything
absolute (`https://evil.com`), protocol-relative (`//evil.com`), scheme-bearing
(`javascript:…`), or containing backslashes falls back to `/`.

---

## 6  Backwards compatibility

**This change is additive and inert by default.**

- **No `rails_token` / normal iframe load → byte-identical to today.** The route
  only *adds* a new path; nothing links to it until the mothership flips
  `unified_login_mode`. A threaded token to a box that hasn't shipped this just
  404s → login, i.e. today's wall (the intended safe fallback).
- **Existing gem auth is untouched** — `agent/*` routes, ActionCable,
  `agent_auth.rb`, `controller_extensions.rb#llama_bot_allow`. The new hooks are
  brand-new accessors; they don't alter `user_resolver` / `sign_in_method`.
- **No existing route is shadowed** — no host app uses `/llamapress_auth/consume`
  today. (Forks that somehow do would see it prepended; none exist.)
- **Regression check:** the full gem suite was **197 examples / 40 failures**
  before this change (the 40 are pre-existing — commented-out `agent/*` routes)
  and **214 / 40** after: **+17 new passing specs, 0 new failures.** A later
  `redeem_rails_grant` spec adds 4 more (21 total for this feature).

The only requirement for the feature to *do* anything in a given host app is a
`llamapress_user_guid` column on `users` (or a `guid_user_resolver` override) —
see §7. Absent that, the default resolver logs a warning and returns nil, and
consume degrades to a redirect. So even a partially-rolled-out app is safe.

---

## 7  Remaining work (other repos)

1. **LlamaBot companion** (`~/dev/LlamaBot`, branch `0.4.1-alpha`):
   `POST /internal/redeem_rails_grant` → existing
   `MothershipClient.verify_login_grant(token, "rails_app")`, returning the shape
   in §4.
2. **Host `llamapress_user_guid` column**: a migration on `users` (+ unique
   partial index) in LlamaPress-Simple and Leonardo, so the default resolver has
   something to look up. The one-time linking of an existing local user to a guid
   is a host-app decision (mirror Phase 2's shadow-user resolution in the host
   schema).

---

## 8  Testing

The gem has its **own** bundle, separate from the host app baked into the
`llamapress` container. See `.claude/CLAUDE.md` → "Running Tests in Docker".
Short version:

```bash
cd ~/dev/Leonardo
docker compose -f docker-compose-dev.yml exec -T llamapress bash -lc \
  'cd /rails/vendor/llama_bot_rails && bundle config set --local path vendor/bundle && bundle install'
docker compose -f docker-compose-dev.yml exec -T llamapress bash -lc \
  'cd /rails/vendor/llama_bot_rails && env -u DATABASE_URL -u DB_URI RAILS_ENV=test bundle exec rspec \
     spec/requests/llama_bot_rails/unified_login_spec.rb \
     spec/lib/llama_bot_rails/redeem_rails_grant_spec.rb'
```

Specs stub the three DI seams (`grant_redeemer`, `guid_user_resolver`,
`sign_in_method`), so the controller logic is exercised without a real
mothership, HTTP call, or Warden stack. The redeemer spec uses WebMock to pin the
HTTP contract the LlamaBot companion must satisfy.
