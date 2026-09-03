# Handoff: build an "Inbox" tab bar in the llama_bot_rails engine

Author: Claude (LlamaBot session)
Date: 2026-08-16 (MDT)
Status: ready to start
Owner decision needed: see "Open question" at the end.

---

## 1. Goal

Group five existing pages under one navigation area named "Inbox".

The five pages are:

1. Tickets
2. Feedback
3. Requests
4. Messages
5. Notifications

Add one shared tab bar. A tab bar is a row of links at the top of the page. The
tab bar must appear on all five pages. The tab bar must highlight the page the
user is currently viewing.

Do not merge the database tables. Do not merge the routes. "Inbox" is a
navigation group only.

---

## 2. Where the code lives

All five features live in the `llama_bot_rails` gem. A gem is a packaged Ruby
library. This gem contains a Rails engine. A Rails engine is a small Rails
application that plugs into a larger Rails application.

The `LlamaPress-Simple` skeleton application contains none of these five
features. The Leonardo `rails/app` overlay contains none of these five features.
So you will edit only the gem.

### Warning: two copies of the gem exist on this machine

| Path | Use it? |
|---|---|
| `~/dev/LlamaPress-Simple/vendor/llama_bot_rails` | Yes. Edit this copy. |
| `~/dev/llama_bot_rails` | No. This copy is older and has diverged. |

Edit only the submodule copy at `~/dev/LlamaPress-Simple/vendor/llama_bot_rails`.
A submodule is a Git repository nested inside another Git repository.

**Never copy a file between the two copies.** Copying a file between them
silently reverts commits in the copy you write into.

The submodule sat on branch `0.6.5` at the time of writing. Run
`git -C vendor/llama_bot_rails status` before you start. Confirm the branch
target with Kody before you create a branch.

### Note on deployment reach

Leonardo's `rails/app` overlay shadows the skeleton's `app/` directory at
runtime. The overlay does **not** shadow the gem engine. So changes you make in
the engine do reach real instances.

---

## 3. Current state

Verify each fact below before you rely on it.

### 3.1 There is no shared layout

A layout is the outer HTML wrapper that Rails reuses across pages.

The engine ships a layout file at
`app/views/layouts/llama_bot_rails/application.html.erb`. That file is 17 lines
long. That file loads no CSS framework and contains no navigation.

Five controllers set `layout false`. That setting tells Rails to skip the outer
wrapper.

| Controller file | Sets `layout false`? |
|---|---|
| `app/controllers/llama_bot_rails/tickets_controller.rb` | Yes |
| `app/controllers/llama_bot_rails/user_feedbacks_controller.rb` | Yes |
| `app/controllers/llama_bot_rails/user_requests_controller.rb` | Yes |
| `app/controllers/llama_bot_rails/conversations_controller.rb` | No |
| `app/controllers/llama_bot_rails/notifications_controller.rb` | No |

### 3.2 Every page writes its own complete HTML document

Nineteen view files start with `<!DOCTYPE html>`. Each one of those files loads
the Tailwind CSS CDN, the daisyUI stylesheet, and the Font Awesome stylesheet
again. Most of those files also carry their own inline `<style>` block.

| View file | Lines |
|---|---|
| `tickets/index.html.erb` | 1084 |
| `tickets/timeline.html.erb` | 966 |
| `tickets/show.html.erb` | 590 |
| `tickets/new.html.erb` | 27 |
| `tickets/edit.html.erb` | 27 |
| `user_feedbacks/index.html.erb` | 1181 |
| `user_feedbacks/show.html.erb` | 1076 |
| `user_feedbacks/kanban.html.erb` | 339 |
| `user_feedbacks/dashboard.html.erb` | 182 |
| `user_feedbacks/new.html.erb` | 34 |
| `user_feedbacks/edit.html.erb` | 34 |
| `user_requests/show.html.erb` | 330 |
| `user_requests/dashboard.html.erb` | 177 |
| `user_requests/index.html.erb` | 153 |
| `user_requests/new.html.erb` | 32 |
| `user_requests/edit.html.erb` | 32 |
| `conversations/show.html.erb` | 157 |
| `conversations/index.html.erb` | 100 |
| `notifications/index.html.erb` | 112 |

Total: 6633 lines across 19 files.

Nine other files in the same directories are partials. A partial is a reusable
fragment of a view. Partials do not start with `<!DOCTYPE html>`. Do not add a
doctype to a partial.

### 3.3 Two pages already produce invalid HTML

`ConversationsController` and `NotificationsController` do not set
`layout false`. Both controllers inherit from
`LlamaBotRails::ApplicationController`, which declares no layout. So Rails wraps
those views in the 17-line engine layout. Those views then write a second
`<!DOCTYPE html>` and a second `<html>` element inside the first one.

The result is one HTML document nested inside another HTML document. Browsers
tolerate the nesting, so the pages still render. The markup is still invalid.
Step 6 below fixes this problem.

### 3.4 Cross-page links are hand written

Some pages link to other pages. Each link is a button typed by hand inside that
one page. For example, `conversations/index.html.erb` links to Feedback and to
Notifications. `tickets/index.html.erb` links to no other page.

### 3.5 A partial navigation bar already exists

The file `app/views/llama_bot_rails/user_feedbacks/_navbar.html.erb` renders a
"Back to App" link and a user badge. That partial is 31 lines long. Six feedback
views render that partial. That partial contains no tabs. Reuse that partial as
the starting point for the new tab bar.

---

## 4. Routes to link from the tab bar

Read `config/routes.rb` in the gem. Use these route helpers.

| Tab label | Route helper | Path |
|---|---|---|
| Tickets | `tickets_path` | `/tickets` |
| Feedback | `user_feedbacks_path` | `/feedback` |
| Requests | `user_requests_path` | `/requests` |
| Messages | `conversations_path` | `/conversations` |
| Notifications | `notifications_path` | `/notifications` |

All five routes live inside `LlamaBotRails::Engine`. Do not change any route.

---

## 5. Steps

Complete these steps in this order.

1. Run `git -C vendor/llama_bot_rails status`. Record any uncommitted changes
   that already exist. Do not revert those changes.
2. Create a new layout file at
   `app/views/layouts/llama_bot_rails/inbox.html.erb`.
3. Copy the `<head>` contents from `tickets/index.html.erb` into the new layout
   file. Those contents include the Tailwind CSS CDN script tag, the daisyUI
   stylesheet link, the Font Awesome stylesheet link, the viewport meta tag, and
   `csrf_meta_tags`.
4. Add `<%= yield :head %>` inside the `<head>` element of the new layout file.
   This line lets each page add its own CSS and JavaScript.
5. Add the tab bar markup to the new layout file. Include one link for each of
   the five routes listed in section 4.
6. Mark the active tab. Read the Rails `controller_name` helper. That helper
   returns the name of the controller that is handling the current request.
   Compare `controller_name` against the controller for each tab. Apply an
   active CSS class to the matching tab only.
7. Merge the contents of `user_feedbacks/_navbar.html.erb` into the new layout
   file. Keep the "Back to App" link. Keep the user badge.
8. Change `layout false` to `layout "llama_bot_rails/inbox"` in these three
   controllers:
   - `app/controllers/llama_bot_rails/tickets_controller.rb`
   - `app/controllers/llama_bot_rails/user_feedbacks_controller.rb`
   - `app/controllers/llama_bot_rails/user_requests_controller.rb`
9. Add `layout "llama_bot_rails/inbox"` to these two controllers:
   - `app/controllers/llama_bot_rails/conversations_controller.rb`
   - `app/controllers/llama_bot_rails/notifications_controller.rb`
10. Edit each of the 19 view files listed in section 3.2. In each file, delete
    the `<!DOCTYPE html>` declaration. Delete the opening and closing `<html>`
    tags. Delete the opening and closing `<head>` tags and everything between
    them. Delete the opening and closing `<body>` tags. Keep the content that
    sat inside the `<body>` element.
11. Move any page specific CSS or JavaScript from a deleted `<head>` into a
    `<% content_for :head do %>` block at the top of that same view file.
12. Move each page title into the layout. Set the title with
    `content_for :title` in the view. Read the title in the layout. Keep the
    existing title text for each page.
13. Delete the `<%= render 'navbar' %>` line from the six feedback views that
    call it. The layout now renders that content.
14. Delete `app/views/llama_bot_rails/user_feedbacks/_navbar.html.erb` after
    step 13 is complete.
15. Run the gem test suite. Section 7 gives the commands.
16. Load all five pages in a browser and confirm the tab bar appears on each
    one. Section 8 gives the URLs.

### Warning about step 10

Some of the deleted `<head>` blocks load a page specific library. For example,
`tickets/index.html.erb` loads `sortablejs`. Do not delete a library tag without
moving it. Move each page specific library tag into the `content_for :head`
block for that page, as described in step 11.

---

## 6. Split the work into three pull requests

Steps 2 through 9 are small. Steps 10 through 12 hold most of the work. Two view
files are over 1000 lines each.

Ship the work in this order.

1. **Pull request 1.** Ship the new layout, the tab bar, the controller changes,
   and the smaller pages: all five `user_requests` views, both `conversations`
   views, and `notifications/index.html.erb`. That is 8 view files.
2. **Pull request 2.** Ship the five `tickets` views. That is 2694 lines.
3. **Pull request 3.** Ship the six `user_feedbacks` views. That is 2846 lines.
   Delete the `_navbar` partial in this pull request.

Between pull request 1 and pull request 3, the tickets pages and the feedback
pages will still write their own `<head>`. Those pages will render the layout
tab bar and their own duplicate assets at the same time. That state is
acceptable and temporary. Confirm each page still renders before you merge.

---

## 7. How to run the gem test suite

Run the suite inside the `leonardo-llamapress-1` Docker container. There is no
Ruby toolchain on the host machine.

Use this command:

```bash
docker compose -f ~/dev/Leonardo/docker-compose-dev.yml exec llamapress \
  sh -c 'cd /rails/vendor/llama_bot_rails && \
  env -u DATABASE_URL RAILS_ENV=test BUNDLE_PATH=vendor/bundle \
  bundle exec rspec spec/lib spec/views spec/generators'
```

Four traps apply. Each trap has cost a debugging loop before.

1. Plain `bundle exec rspec` fails with `GemNotFound`. The gem has its own
   vendored bundle. Always pass `BUNDLE_PATH=vendor/bundle`.
2. The container exports `DATABASE_URL` for PostgreSQL. The dummy test
   application uses SQLite. Always pass `env -u DATABASE_URL`.
3. The container exports `RAILS_ENV=development`. Always pass `RAILS_ENV=test`
   explicitly. If you skip this, the suite runs against the wrong SQLite
   database and erases your schema stamps.
4. `bundle exec rails` run from the gem directory finds `/rails/bin/rails`
   instead. Do not run `bundle exec rails` from the gem directory.

If the whole suite aborts with `PendingMigrationError` before any test runs,
read the "Fresh container: PendingMigrationError" section in the gem's
`.claude/CLAUDE.md` file.

Two sets of failures already exist and are unrelated to this work:

- `spec/controllers/llama_bot_rails/agent_controller_spec.rb` has about 25
  pre-existing failures.
- Model, request, and feature specs need a repaired dummy database.

Confirm any failure is pre-existing before you investigate it. Confirm by
reverting your changed files and running the same command again.

Add view specs for the new layout under `spec/views`. At minimum, assert that
the tab bar renders five links. Assert that the correct tab receives the active
CSS class. Do not assert on exact styling text.

---

## 8. How to check the pages in a browser

Open these URLs on the dev instance.

- `https://rails-llamapress-dev.llamapress.ai/tickets`
- `https://rails-llamapress-dev.llamapress.ai/feedback`
- `https://rails-llamapress-dev.llamapress.ai/requests`
- `https://rails-llamapress-dev.llamapress.ai/conversations`
- `https://rails-llamapress-dev.llamapress.ai/notifications`

Sign in first. Check four things on each page.

1. The tab bar appears at the top.
2. The correct tab shows the active state.
3. The page content still renders with its original styling.
4. The browser console reports no new errors.

The `llamapress` container reloads Ruby code in development mode. So you do not
need to restart the container after you edit a view or a controller.

---

## 9. Rules you must follow

1. Do not run `git branch`, `git commit`, `git push`, or open a pull request
   without explicit permission from Kody. Ask first every time.
2. Do not force push. Do not push to `main`.
3. Do not change any route in `config/routes.rb`.
4. Do not change any model, migration, or database table.
5. Do not copy files between the two gem copies. See section 2.
6. Run only one test suite at a time. Two concurrent `rspec` or `pytest` runs in
   the container produce false failures.

---

## 10. Out of scope

Do not build a single merged `/inbox` feed in this task. A merged feed would
combine tickets, feedback, and messages into one list.

A merged feed is blocked for now. The four models do not share a common status
field, a common timestamp field, or a common actor field. A merged feed also
needs paging across those different data sources. Treat the merged feed as a
separate, later task.

---

## 11. Open question for Kody

Answer this before you start step 2.

- **Option A: tab bar only.** Complete sections 5 and 6 as written. This is the
  recommended option.
- **Option B: tab bar plus a merged `/inbox` feed.** This option needs a new
  design for a shared record format. This option is much larger than option A.
