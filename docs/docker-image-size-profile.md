# Docker Image Size Profile

**Image:** `kody06/llamapress-simple` (built from `Dockerfile` in this repo)  
**Measured on:** `leonardo-llamapress:latest` (dev build, amd64)  
**Total uncompressed size:** ~3.64 GB  
**Base image:** `ruby:3.3-bookworm`

---

## Layer-by-Layer Breakdown

These are the image layers produced by the Dockerfile, largest first:

| Size | Layer (Dockerfile step) |
|------|-------------------------|
| 1.07 GB | `apt-get install` — system packages (Chromium, Node.js, awscli, build-essential, etc.) |
| 619 MB | Base Debian OS (`ruby:3.3-bookworm` parent layer) |
| 466 MB | `bundle install` — Ruby gems |
| 194 MB | Ruby toolchain (`ruby:3.3-bookworm` — compiling Ruby from source) |
| 115 MB | `npm ci` — Node.js packages |
| 75 MB | Ruby standard library (`ruby:3.3-bookworm`) |
| 8.0 MB | `COPY vendor/` — vendored gems (llama_bot_rails submodule) |
| 1.1 MB | `COPY . .` — application source code |
| ~0 MB | ENV, WORKDIR, EXPOSE, CMD, permission fixups |

---

## Inside the Container — Filesystem Breakdown

```
/usr          2.4 GB   (everything installed by apt + Ruby + Node)
/rails        119 MB   (app code + node_modules + tmp)
/root          32 MB   (root home — npm cache residue)
/var           28 MB   (package manager state)
/etc          2.5 MB   (config files)
```

### /usr breakdown (2.4 GB total)

```
/usr/lib                1.3 GB
  /usr/lib/x86_64-linux-gnu   590 MB   (shared libs: glibc, OpenSSL, gtk, mesa, etc.)
  /usr/lib/chromium           326 MB   (Chromium browser — the biggest single item)
  /usr/lib/gcc                120 MB   (GCC compiler toolchain from build-essential)
  /usr/lib/python3            169 MB   (awscli's Python runtime)

/usr/share              458 MB
  /usr/share/locale     123 MB   (i18n locale data — rarely needed at runtime)
  /usr/share/doc         78 MB   (Debian package docs)
  /usr/share/man         17 MB   (man pages)
  /usr/share/nodejs     144 MB   (Node.js system packages)

/usr/local              484 MB
  /usr/local/bundle     413 MB   (Bundler gem path — all installed Ruby gems)
  /usr/local/lib         69 MB   (Ruby stdlib + native extensions)
  /usr/local/bin        272 KB   (ruby, gem, bundler, etc.)
```

---

## Ruby Gems Breakdown (413 MB total in `/usr/local/bundle`)

Top gems by disk usage:

| Size | Gem |
|------|-----|
| 118 MB | `tailwindcss-ruby` (ships a pre-compiled Tailwind binary) |
| 19 MB | `twilio-ruby` |
| 18 MB | `stripe` |
| 13 MB | `pg` (native extension with bundled libpq) |
| 13 MB | `brakeman` (security scanner — dev/CI only) |
| 11 MB | `parser` (Ruby AST parser — brakeman/rubocop dependency) |
| 11 MB | `nokogiri` (ships libxml2 statically compiled in) |
| 8.4 MB | `faker` (dev/test only) |
| 7.9 MB | `prism` (Ruby parser) |
| 5.2 MB | `rubocop` (linter — dev/CI only) |
| 4.3 MB | `string_pattern` |
| 4.1 MB | `mail` |
| 4.0 MB | `aws-sdk-s3` |
| 3.5 MB | `activerecord` |

Note: `tailwindcss-ruby` alone accounts for **~29% of the entire gem layer** because it
bundles a standalone Tailwind CSS binary rather than using npm.

---

## Node.js Packages Breakdown (110 MB in `/rails/node_modules`)

| Size | Package |
|------|---------|
| 28 MB | `happy-dom` (headless DOM for JS tests) |
| 13 MB | `chromium-bidi` (browser automation protocol) |
| 12 MB | `puppeteer-core` |
| 9.3 MB | `@esbuild` (pre-compiled esbuild binary) |
| 4.2 MB | `@rollup` |
| 3.3 MB | `vite` |
| 3.1 MB | `devtools-protocol` |
| 2.8 MB | `rollup` |
| 2.7 MB | `@types` |
| 2.5 MB | `@testing-library` |
| 1.9 MB | `vitest` |

---

## Key Observations

### Why is the image so large?

1. **Chromium (326 MB)** — Installed via `apt` for browser-based tests (Capybara/Puppeteer).
   This is the single largest package. Only needed for test runs; production Rails serving
   doesn't use it.

2. **awscli + Python runtime (169 MB)** — The `awscli` apt package pulls in a full Python 3
   installation. This is used for S3 operations.

3. **build-essential / GCC (120 MB)** — Required to compile native gems (pg, nokogiri, etc.)
   at `bundle install` time. Not needed at runtime once gems are compiled.

4. **Node.js via apt (144 MB in `/usr/share/nodejs`)** — The Debian `nodejs` package includes
   the full Node source and bundled npm packages.

5. **Locale/doc data (200+ MB)** — `/usr/share/locale` and `/usr/share/doc` ship with Debian
   packages and are never used at runtime. These survive because `apt-get clean` only removes
   package lists, not installed share data.

6. **tailwindcss-ruby gem (118 MB)** — Ships a self-contained Tailwind binary for each
   platform (amd64 + arm64). Only the current platform binary is ever executed.

---

## Reduction Opportunities

| Opportunity | Estimated Saving | Complexity |
|-------------|-----------------|------------|
| Remove `/usr/share/locale` and `/usr/share/doc` after apt install | ~200 MB | Low — add to the apt RUN layer |
| Use `ruby:3.3-slim-bookworm` as base instead of `ruby:3.3-bookworm` | ~300 MB | Medium — need to re-add Ruby build deps |
| Move Chromium to a separate test image; strip it from the prod/base image | ~326 MB | Medium — requires multi-stage or split image strategy |
| Replace `awscli` (apt) with the Python pip version in a venv, or use the AWS CLI v2 standalone binary | ~100 MB | Low-Medium |
| Multi-stage build: compile gems in a builder stage, copy only gems (no GCC) to the final stage | ~120 MB | Medium |
| Remove `build-essential` after native gem compilation (same layer trick or multi-stage) | ~120 MB | Medium |
| Pin `tailwindcss-ruby` to a single-platform gem to drop the unused arch binary | ~60 MB | Low |

Realistically achievable without changing the development workflow: **~500–700 MB** by
cleaning locale/doc data and using a slim base image. Getting below 2 GB requires the
multi-stage or test/prod split approach.

---

## RAM at Runtime

The image size does not directly equal RAM usage — only loaded pages are mapped into memory.
Typical resident set for an idle Rails dev server (single Puma worker, no request load):

| Component | Approximate RSS |
|-----------|----------------|
| Rails / Puma process | 300–500 MB |
| Bootsnap cache (warm) | ~50 MB |
| PostgreSQL adapter (pg) | ~10 MB |
| Chromium (if running Capybara tests) | 200–400 MB per browser process |

The image layers on disk are not in memory; only files that are `mmap`'d or `read()` at
runtime contribute to RSS.
