# `window.llamapressConfig` — injected, not rendered

## What it is

Every HTML page an app on this engine serves carries one small script in its
`<head>`:

```html
<script>window.llamapressConfig = {"feedbackBubbleEnabled":true,"userLoggedIn":true,"appVersion":"0.7.3","releasesUrl":"/llama_bot/releases"};</script>
```

The frontend reads it. Most importantly `feedback_bubble.js`, which refuses to
draw unless **both** `feedbackBubbleEnabled` and `userLoggedIn` are true:

```js
function shouldShowBubble() {
  const config = window.llamapressConfig || {};
  return config.feedbackBubbleEnabled && config.userLoggedIn;
}
```

## Why it is injected instead of rendered by a layout

It used to be one `<script>` block inside a layout partial
(`layouts/_llamapress_page_context`), rendered by one line of one client
overlay's `application.html.erb`.

That meant the config existed on exactly the pages that happened to go through
that layout. Everything else — the `prototypes` layout, admin shells, any layout
Leo generated, and **the base image's own `app/views/layouts/application.html.erb`,
which never had the block at all** — served pages where `window.llamapressConfig`
was `undefined`, `shouldShowBubble()` returned `false`, and the feedback bubble
simply was not there. No error, no console warning, nothing to notice.

A layout is the wrong home for something every page needs, because a layout is a
thing a person writes and can forget. So the engine writes it instead:
`LlamaBotRails::PageConfigInjection` is an `after_action` auto-included into
`ActionController::Base`, and it inserts the script straight after the opening
`<head>` of every HTML response. Nobody has to remember it, and a new layout
cannot regress it.

It lives in the **engine**, not the base image's `app/`, for the same reason
`ActivityTracking` does: client overlays volume-mount over `app/`, so anything
there disappears downstream.

## Where it goes in the page

Immediately after `<head>`, which puts it above `javascript_importmap_tags`.
`feedback_bubble.js` ships as a deferred ES module, so it runs after the document
parses — the config is always already set by then.

## What it will not do

- **Never overwrites a page that defines the config itself.** Older client
  overlays still render the partial; those pages are left exactly as they are.
  The check is for an *assignment* (`window.llamapressConfig =`), not a mention —
  a layout that only talks about it in a comment still gets the injection. (That
  distinction is not theoretical: the first cut of this used a substring check,
  and the replacement comment left behind in Leonardo's partial was enough to
  suppress injection across the whole app.)
- **Only touches `text/html`, 2xx, with a `<head`.** JSON, Turbo Streams,
  `send_file`, redirects, and layout-less renders are untouched.
- **Never fails a request.** The whole action is wrapped; any error is logged at
  debug and the page is served as-is.

## Configuration

```ruby
# config/initializers/llama_bot_rails.rb
Rails.application.config.llama_bot_rails.inject_page_config      = false  # stop injecting entirely
Rails.application.config.llama_bot_rails.feedback_bubble_enabled = false  # inject, but bubble off
```

Per controller:

```ruby
skip_llama_page_config             # whole controller
skip_llama_page_config only: :raw  # one action
```

## Who is "logged in"

`user_signed_in?` if the host app has it (Devise), else `current_user.present?`,
else `false`. Both are rescued — an app with neither is not an error.

## Tests

`spec/requests/llama_bot_rails/page_config_injection_spec.rb`, against dummy
controllers rendering `layouts/spec_page` — a deliberately forgetful layout that
has a `<head>` and never mentions the config.
