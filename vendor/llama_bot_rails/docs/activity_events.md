# Activity, audit and adoption (phase 1)

Every app built on the LlamaPress base image records **what happened, who caused
it, and which records it changed** — without the app writing any code for it.

Two layers:

| Layer | Question it answers | Storage |
|---|---|---|
| PaperTrail `versions` | What changed on this row, from what to what? | `versions` |
| `LlamaBotRails::ActivityEvent` | What operation happened, who caused it, through which interface? | `llama_bot_rails_activity_events` |

They are joined by a **correlation id**: one logical operation → one event → N
versions. That is what lets the UI say "Sarah completed Order #481, changing 5
records" instead of printing five disconnected rows.

This ships in the **engine**, not in the base image's `app/`. Client overlays
volume-mount over `app/`, `db/` and `config/`, so anything there disappears
downstream. The engine is the only layer every generated app inherits.

## What phase 1 gives you

- `LlamaBotRails::Current` — actor / source / correlation context for the
  request or job in flight.
- Automatic `ActivityEvent` rows for every successful write request.
- Every PaperTrail version stamped with `correlation_id`, `request_id`,
  `source`, and `activity_event_id`.
- Background-job attribution (`source: background_job`, `job_class`, `job_id`).
- A sensitive-attribute policy that keeps secrets out of version diffs.
- `human` on every event, so adoption metrics never count cron jobs as usage.

Not yet: a generic Data explorer, cross-process correlation propagation into
queued jobs, Leo tools, retention/rollups.

## The admin UI (phase 2)

Mounted under the engine, so an app that mounts `LlamaBotRails::Engine => "/llama_bot"`
gets these for free:

| Path | Page |
|---|---|
| `/llama_bot/activity` | application-wide feed, filterable by search, type, source, cause and date |
| `/llama_bot/activity/:id` | one operation: actor, source, every record it changed, field diffs |
| `/llama_bot/activity/history/:type/:id` | one record's whole story |
| `/llama_bot/activity/usage` | adoption: active people, meaningful actions, workflows, never-activated users |

All read-only, all gated on `can?(:view_activity)`.

### Record History inside your own pages

```erb
<%%= llama_activity_history(@contact) %>
```

Renders a timeline with field-level diffs, using plain Tailwind utilities so it
looks right inside a host layout. It returns nothing at all when the viewer
lacks activity permission, so it is safe to leave in a shared partial. The demo
scaffold's `app/views/contacts/show.html.erb` uses it.

### Permissions

`:view_activity` shows the operator view; `:view_activity_technical` reveals the
collapsed technical block (correlation/request ids, controller, job, metadata).

The default checker grants both to `admin?` users. In an app whose user model
has **no** `admin?` method — the single-operator Leo boxes — any signed-in user
qualifies, because otherwise the feature would be unreachable in the apps that
need it most. **An app with multiple untrusted users must define `admin?` or
override `LlamaBotRails.permission_checker`.**

## Installing in an app

```bash
bin/rails llama_bot_rails:install:migrations
bin/rails db:migrate
```

The versions migration is idempotent: an app that already ran PaperTrail's own
installer keeps its table and just gains the four correlation columns.

Then mark the models worth auditing:

```ruby
class Order < ApplicationRecord
  include LlamaBotRails::Auditable
end
```

That is the whole integration. Controllers and jobs need no changes — the
engine includes the tracking concerns into `ActionController::Base` and
`ActiveJob::Base` on load.

## Recording your own events

The interesting events are usually business operations, not CRUD:

```ruby
LlamaBotRails::ActivityEvent.record!("invoice.approved", subject: invoice)
```

Actor, source, workspace, controller and correlation come from the ambient
context. `record!` never raises — a failure to log must not fail the operation
being logged.

To rename the event a controller action records:

```ruby
class InvoicesController < ApplicationController
  llama_activity_event "invoice.approved"        # whole controller

  def approve
    LlamaBotRails::Current.event_type = "invoice.approved"   # one action
  end
end
```

Naming an event inside a `GET` action is also how you record a read that
matters (an export, a report) while ordinary page views stay unrecorded.

Opt out where the noise is not worth it:

```ruby
skip_llama_activity_tracking             # whole controller
skip_llama_activity_tracking only: :ping # one action
```

## Configuration

Set in the host app's `config/application.rb` or an initializer:

```ruby
config.llama_bot_rails.activity_tracking_enabled = true
config.llama_bot_rails.activity_track_get_requests = false
config.llama_bot_rails.activity_actor_method = :current_user
config.llama_bot_rails.activity_workspace_resolver = ->(controller) { controller.current_account&.id }
config.llama_bot_rails.activity_sensitive_attributes = %w[password_digest ...]
config.llama_bot_rails.activity_sensitive_attribute_patterns = [/_token\z/, /_secret\z/]
config.llama_bot_rails.activity_ignored_attributes = %w[]

# The zone every timestamp on these screens is rendered in, and named on the
# page. nil = use the host app's config.time_zone if it sets one, else Pacific.
config.llama_bot_rails.display_time_zone = nil
```

### What zone the screens show

Times are stored in UTC and displayed in **one resolved zone**, which the pages
state in words ("All times shown in Pacific Time (PDT)") rather than leaving the
reader to infer an offset. Precedence:

1. `config.llama_bot_rails.display_time_zone` — explicit, always wins.
2. The host app's `config.time_zone`, when it sets one. That is the app owner's
   answer and outranks the gem's.
3. **Pacific**, the default.

Rails cannot distinguish "never configured" from "deliberately set to UTC" —
both read back as `"UTC"` — so a bare UTC is treated as unconfigured and falls
through to Pacific. An app that genuinely wants UTC sets
`display_time_zone = "UTC"`.

The controller wraps its actions in `Time.use_zone`, so the From/To date filters
mean days in that zone too, not UTC days.

## Adoption queries

`human` is denormalized onto every event precisely so these stay cheap:

```ruby
events = LlamaBotRails::ActivityEvent.human.since(7.days.ago)

events.distinct.count(:actor_id)                    # weekly active users
events.count                                        # meaningful actions
events.group(:event_type).count                     # most-used workflows
LlamaBotRails::ActivityEvent.human.maximum(:occurred_at)  # last real usage
```

A job that rewrites 50,000 rows moves none of these numbers.

## Design notes worth knowing

**Correlation ids are minted server-side, never taken from a request header.**
An inbound `X-Correlation-Id` is kept in `metadata["upstream_correlation_id"]`
instead, so a client cannot join (or poison) somebody else's operation.

**Version metadata is attached at the model layer (`has_paper_trail meta:`),
not through PaperTrail's `info_for_paper_trail` controller hook.** Two reasons:
versions are also written from jobs, callbacks and the console, where no
controller exists; and PaperTrail includes its own controller module into
`ActionController::Base` *after* ours, so its `info_for_paper_trail` (which
returns `{}`) would win the ancestor lookup. Models that use bare
`has_paper_trail` instead of `LlamaBotRails::Auditable` therefore get versions
with no correlation — use the concern.

If your app defines `info_for_paper_trail` in `ApplicationController`, call
`super` so the correlation keys survive.

**Request params are never captured.** They are the most likely place for a
password or token to end up in the audit log. `metadata` holds method, path, IP
and response status only.

**The event is written after the action, from the versions the action produced.**
That is how one operation with five mutations becomes one event with
`changed_records_count: 5`, and how the event's subject is discovered without
any per-controller wiring.

**Failed writes record nothing.** A 422 from a validation error changed no data
and belongs in the logs, not the activity feed.

## Tests

The gem's own CI is lint-only, so the suite for this lives in **LlamaPress-Simple**
(real Postgres, runs on every PR):

- `spec/models/llama_bot_rails/activity_event_spec.rb`
- `spec/requests/activity_tracking_spec.rb`
- `spec/jobs/llama_bot_rails/job_activity_tracking_spec.rb`
- `spec/requests/activity_ui_spec.rb`
- `spec/system/activity_ui_spec.rb` (browser; runs with `INCLUDE_SYSTEM_SPECS=1`)
