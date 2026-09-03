# LlamaPress scaffold templates

`llama_bot_rails` overrides the standard Rails scaffold so that a plain

```bash
bin/rails generate scaffold Contact name:string email:string company:string status:string notes:text
```

in a host app produces a usable back-office UI instead of the stock all-fields
index:

- a condensed, scan-friendly table (max 5 columns, deterministic selection);
- a shared slide-out detail drawer (Turbo Frame `record_drawer`) used by
  show/edit/new;
- a collapsible filter panel driven by a normal GET form (shareable URLs);
- conservative generated search/filter/pagination via
  `LlamaBotRails::ScaffoldFiltering`.

No special generator command exists — the standard scaffold invocation is the
interface.

## Column selection rules (`LlamaBotRails::ScaffoldColumns`)

- Max **5** table columns. `created_at` is appended as the final informational
  column when a slot is free.
- Priority names win first slots, in order:
  `name, title, subject, full_name, username, email, company, status`; the rest
  fill from short scalar fields in declaration order.
- Never auto-selected for the table or search: `text`, JSON, binary,
  rich text, attachments, references, names matching
  `password|digest|token|secret|encrypted|id|_id`, timestamps (other than the
  appended `created_at`).
- Text search covers at most 4 short string columns; boolean attributes get an
  Any/Yes/No filter; `created_at` gets a date range (invalid dates are ignored,
  never a 500).
- Excluded fields still appear in the drawer show/edit views and permitted
  params.

## Architecture

- **Templates**: `lib/llama_bot_rails/scaffold_templates/` registered via
  `config.generators.templates` (engine initializer). The `erb/scaffold/` and
  `tailwindcss/scaffold/` sets MUST stay identical (spec-enforced) — Rails
  picks the view generator by the host's template engine
  (tailwindcss-rails hosts use the latter).
- **Precedence**: a host's own `lib/templates/...` always beats these
  (Rails unshifts it), so apps can re-override per convention.
- **Runtime behavior** lives in `LlamaBotRails::ScaffoldFiltering`
  (escaped ILIKE/LIKE search with explicit ESCAPE, bounded pagination with a
  Pagy backend when available and an offset fallback otherwise,
  `turbo_stream.refresh` after drawer saves). Fixes here reach every host via
  a gem update without regenerating.
- **Pagination**: `llama_pagination_nav(@pagy)` (LlamaBotRails::PaginationHelper)
  renders the one styled nav — page window with gaps, prev/next, count, and
  every other query param preserved. Generated indexes call it, hand-written
  ones should too, and Pagy's own `pagy_nav` is prepended to render it as well
  (`config.llama_bot_rails.styled_pagy_nav = false` restores Pagy's markup).
  Works with a real Pagy object or the `ScaffoldFiltering::Page` fallback.
- **Drawer shell**: render once per layout, near `</body>`:
  `<%= render "llama_bot_rails/record_drawer" %>`. Show/new/edit views wrap
  content in the `llama_record_frame` helper — frame requests get the
  `record_drawer` frame, direct visits render a normal full page.
- **JS**: the engine importmap pins
  `controllers/record_drawer_controller` and
  `controllers/filter_panel_controller`, so the standard
  `eagerLoadControllersFrom("controllers", application)` registers them with no
  host JS edits. **These two controller names are reserved** — host apps must
  not define Stimulus controllers with the same file names.
- **CSS**: Tailwind-v2-safe utility classes only (works under both the static
  v2 CDN and the Play CDN), plus `llama_bot_rails/scaffold.css` for drawer
  transitions. No Font Awesome — icons are inline SVG.

## Turbo contract

- Row links (and clicks on non-interactive row space, via `data-drawer-row`)
  load the record into the `record_drawer` frame; the drawer opens only after
  `turbo:frame-load`. Closing clears frame `src` + content, so reopening
  refetches.
- Successful create/update responds with `turbo_stream.refresh`: the index
  re-GETs its current URL (filters/page preserved) so the table is never
  stale, and the drawer closes with it.
- Destroy and the filter form target `_top`. Validation errors re-render
  inside the frame with `:unprocessable_entity`.
- A frame response without a matching frame (e.g. an auth redirect) becomes a
  full-page visit via the `turbo:frame-missing` handler.

## Customization / escape hatches

- **Per-resource tweaks**: generated code is plain app code — edit the views'
  column list, the controller's `search_columns:`/`boolean_columns:`, or
  `base_scope` (the authorization seam: e.g. `policy_scope(Contact)` or
  `current_user.contacts`).
- **Plain Rails scaffolds**: `LLAMAPRESS_SCAFFOLD=plain bin/rails g scaffold ...`
  skips the template override entirely (join tables, tiny settings models).
  For no UI at all, use `bin/rails g model`.
- **Shell overrides**: define
  `app/views/llama_bot_rails/_record_drawer.html.erb` in the host to replace
  the drawer shell (standard engine view override).

## Testing

- `spec/lib/scaffold_columns_spec.rb` — selection rules.
- `spec/lib/scaffold_filtering_spec.rb` — escaping, dates, pagination bounds.
- `spec/helpers/llama_bot_rails/pagination_helper_spec.rb` — nav markup, page
  window/gaps, param preservation, and the `pagy_nav` prepend.
- `spec/generators/scaffold_templates_spec.rb` — real generator run against a
  tmp destination: markers present, `notes:text` excluded from the table,
  every generated view/controller compiles; template-set parity.
