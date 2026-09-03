# Rails error telemetry → the mothership

Reports unhandled Rails exceptions from every Leo box to the LlamaPress
mothership, so they land on `/admin/instance_errors` next to the ones LlamaBot
(the Python side) has always reported.

Before this, a customer-facing Rails crash — a pending migration after a bad
update, a CSRF failure, a 500 from agent-written code — was invisible to the
fleet unless a human SSHed into the box.

## Turning it on

Nothing to configure. It activates when all three env vars are present, which
is exactly the condition "this is a managed Leo box":

| Var | Source |
| --- | --- |
| `MOTHERSHIP_URL` | `.env` (mothership EnvFileBuilder), or `.leonardo/instance.json`; defaults to `https://llamapress.ai` |
| `MOTHERSHIP_API_TOKEN` | `.env`, or `.leonardo/instance.json` |
| `MOTHERSHIP_INSTANCE_NAME` | `.env`, or `.leonardo/instance.json` |

Because `MOTHERSHIP_URL` always ends up set (the skeleton defaults it), the
**token** is what actually decides whether a box reports. Local dev and ejected
apps have none, so they silently no-op.

Kill switch: `LLAMA_BOT_ERROR_TELEMETRY=false`.

## What gets sent

Only this:

```
error_class    RuntimeError
error_message  the exception message, stripped — nothing else (see below)
traceback      key: value header block (method, path, request_id, rails_env,
               gem/app version, capture hook, cause) + first 40 backtrace lines
source         "rails_app"
recovered      false for unhandled crashes
occurred_at    ISO8601
instance_name  which box
```

**Never sent:** params, headers, cookies, session, ENV. The path is
`request.path`, not `request.fullpath`, because the query string can carry
tokens and emails.

### The fingerprint contract

The mothership fingerprints on
`md5(error_class | first_line_of_message[:160] | agent_mode)` and dedups per
(instance, fingerprint) in a 10-minute window; spikes auto-open a
SupportIncident and SMS the founders.

So `error_message` carries **the exception message and nothing else**. Prepend
the request path or a timestamp and every single occurrence gets its own
fingerprint — clustering dies and the spike alerting stops firing. Request
context goes in `traceback` for exactly this reason.

## The three capture paths

1. **`ErrorTelemetryMiddleware`** — Rack middleware, inserted *after*
   `ActionDispatch::DebugExceptions`. "After" in a Rack stack means *inside*, so
   it wraps the router, the app, and `Migration::CheckPending`.

   Inserting higher (e.g. after `ActionDispatch::Executor`) does **not** work:
   that sits *outside* `ShowExceptions`/`DebugExceptions`, both of which render
   an error page without re-raising when `show_exceptions` is `:all`. Every Leo
   box runs `RAILS_ENV=development`, where it is `:all` — a middleware up there
   would never see a single application exception.

2. **`ErrorSubscriber`** — a `Rails.error.subscribe` subscriber, for errors that
   never travel the Rack stack: jobs, async queries, `Rails.error.handle`.
   `:info` severity is skipped.

   In practice this path also catches most **HTTP** crashes, and it gets there
   first. `ActionDispatch::Executor` (and its subclass `Reloader`) rescues,
   reports to `Rails.error`, and only *then* re-raises — and `Reloader` sits
   *inside* both middlewares below. So the subscriber wins the race on nearly
   every 500. That is why it digs the request out of
   `ActiveSupport::ExecutionContext[:controller]`: whatever context it fails to
   attach is gone for good, since the reporter marks the exception as reported
   and the server's dedup only bumps a counter — it never upgrades a traceback
   it already stored. Verified on a real box: without it, every 500 arrived
   with no `method` or `path`.

3. **The Leonardo overlay's `LeonardoErrorPageMiddleware`** calls the reporter
   directly. It sits *inside* our middleware and renders the "Ask Leo to fix
   this" page **without re-raising**, so without that call the crashes customers
   actually hit would be precisely the ones missing.

Overlap is fine: the reporter marks the **exception object** once reported, so
whichever path sees it first wins and the others no-op. (The marker lives on the
exception, not the Rack env, because path 2 has no env at all.)

## Noise filtering

Public boxes get scanned constantly. Exceptions Rails maps to a non-5xx status
via `ActionDispatch::ExceptionWrapper.rescue_responses` are dropped —
`RoutingError`, `RecordNotFound`, `BadRequest` and friends — so bot traffic
doesn't drown the dashboard or eat the throttle budget.

Two deliberate exceptions, in `ALWAYS_REPORT`:
`ActionController::InvalidAuthenticityToken` and `InvalidCrossOriginRequest`.
They render as 422 but CSRF breakage is a headline reason this exists.

`ActiveRecord::PendingMigrationError` isn't in the table at all, so it's treated
as a 500 and reported.

## Safety

A telemetry bug must never break or slow a customer request:

- Delivery runs on a background thread (`Net::HTTP`, 5s open/read/write
  timeouts, no retry) — mirroring the Python client's semantics.
- The public entrypoint rescues `Exception`, logs at debug, returns nil.
- The middleware separately guards its reporter call, so even a reporter that
  somehow raised could not replace the app's real exception with a telemetry one.
- In-process sliding-window throttle: 10 sends/minute. The server dedups, but a
  hot error loop shouldn't hammer the network path or spawn a thread per request.
- Config is snapshotted on the request thread and handed to the sender, so a
  payload can't be shipped with credentials that changed underneath it.

## Verifying on a real box

Throw a test error, then check
<https://llamapress.ai/admin/instance_errors> filtered to source `rails_app`.

### Verifying without touching production

The mothership app itself runs locally, so the whole loop can be exercised with
no production credentials — worth doing, since the request-context bug above was
invisible to unit tests and only showed up against the real receiver.

1. Boot `LlamaPressLeo` against the dev Postgres in its own database. It needs
   `AWS_REGION` + `AWS_BUCKET` (any values — ActiveStorage resolves its S3
   service when `Site`'s `has_many_attached` is defined, and the global layout
   dies without it) and a `REDIS_URL` (Devise enqueues mail on user create).
   Skip `db:seed`; the seeds make real AWS calls.
2. Create an admin `User` and a `UserInstance` whose `dns_name` and `api_token`
   match what the box will send.
3. Point the box at it by mounting a throwaway `.leonardo/instance.json` — never
   by editing the real one, which carries the box's production token and
   `mothership_url: https://llamapress.ai`.
4. Crash a route, then read `/admin/instance_errors`.

Watch for two traps. `config/initializers/` is **baked into the image**, so an
edit to `leonardo_instance.rb` is invisible to the container until it is mounted
or the image is rebuilt. And single-file bind mounts (`routes.rb`,
`instance.json`) break when an editor replaces the file rather than writing in
place — the container keeps the old inode until it is recreated.

## Rollout caveat

`rails/app/` on customer boxes is agent-owned and **not** in the `bin/update`
allowlist, so capture path 3 only reaches newly-cloned boxes automatically.
Existing boxes get paths 1 and 2, which miss whatever the Leonardo error page
swallows.
