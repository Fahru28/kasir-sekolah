# LlamaPress-Simple

This is the **base Docker image** for all LlamaPress/Leonardo projects. It contains the Rails framework skeleton, Gemfile, npm packages, and vendored gems.

## Architecture Overview

```
LlamaPress-Simple (this repo - Base Image)
       │
       │ builds → kody06/llamapress-simple:X.X.X
       │
       ▼
┌──────────────────────────────────────────┐
│  Client Projects (Overlays)              │
│  - Leonardo (development template)       │
│  - RSB-Tender                            │
│  - clients/History-Education-Foundation  │
│  - clients/opto                          │
└──────────────────────────────────────────┘
       │
       │ volume mounts override: app/, db/, config/, spec/
       ▼
   Client-specific code runs on top of base image
```

## What Lives Here vs Client Projects

| This Repo (Baked into Image) | Client Projects (Mounted) |
|------------------------------|---------------------------|
| Gemfile / Gemfile.lock | app/controllers, models, views |
| package.json / npm deps | config/routes.rb |
| vendor/ gems (llama_bot_rails, etc.) | db/migrations |
| Base Rails framework | spec/ tests |
| Dockerfile | docker-compose.yml |

## Vendored Gems as Submodules

`llama_bot_rails` is a **git submodule** at `vendor/llama_bot_rails`:

```bash
# Initialize after cloning
git submodule update --init --recursive

# The submodule repo
https://github.com/KodyKendall/llama_bot_rails.git
```

**Important:** The Dockerfile removes `.git` files from submodules during build because they point to paths outside the Docker build context.

**Pinning the submodule — gem `main` is NOT the shipping line.** The gem's `origin/main`
is stale (`be26a7a`, "0.1.16"); the entire product line (tickets, feedback, releases,
unified login, migrations — verified 2026-07-05: `main` + 21 commits / +12.7k LOC) lives
on stacked **feature branches** that were never merged to gem `main`. The image bakes
whatever SHA the submodule points at, so:

- **Only ever bump the pointer to a DESCENDANT of the currently-shipped SHA.** Verify:
  `git -C vendor/llama_bot_rails merge-base --is-ancestor <shipped> <new>`. Pinning to a
  `main`-based branch would silently REGRESS the image (drop the 21 feature commits).
- Do NOT "PR to gem `main` → merge → bump pointer" — that rests on a false premise about
  the repo's topology. Pin to the immutable feature-branch SHA that carries the change.

See box memory `llama-bot-rails-ships-via-submodule-pointer`.

## Building the Docker Image

**IMPORTANT:** Full builds take ~20 minutes. Always preserve the cache when possible.

```bash
# Local build (single platform) - uses cache
docker build -t kody06/llamapress-simple:0.3.1 .

# Multi-platform build and push - uses cache
docker buildx build --file Dockerfile \
  --platform linux/amd64,linux/arm64 \
  --tag kody06/llamapress-simple:0.3.1 --push .
```

### Rebuilding After Changes (from Leonardo directory)

When you change files in `vendor/` (like `llama_bot_rails`), Docker may reuse an existing image instead of rebuilding. To force a rebuild while **preserving cache**:

```bash
cd /path/to/Leonardo

# Step 1: Stop the container (required before removing image)
docker compose -f docker-compose-dev.yml down llamapress

# Step 2: Remove the old image (this preserves layer cache!)
docker rmi leonardo-llamapress

# Step 3: Rebuild and start (uses cached layers, ~2-3 seconds if no gem changes)
docker compose -f docker-compose-dev.yml up -d --build llamapress
```

**Note:** If you get "container is using its referenced image" error on `docker rmi`, make sure you ran `docker compose down` first (not just `docker compose stop`).

**AVOID these unless absolutely necessary:**
```bash
# BAD: --no-cache rebuilds everything from scratch (~20 min)
docker compose -f docker-compose-dev.yml build --no-cache llamapress
```

The layer cache is stored separately from the image, so removing the image (`docker rmi`) still preserves cached layers for `apt-get`, `bundle install`, and `npm install`. You'll see "CACHED" for most steps in the build output.

## Releasing (Publishing a New Image Version)

**Do not run `docker buildx ... --push` by hand.** Publishing is automated and gated
on CI so an untested or uncommitted image can never reach production. The release
**git tag is the source of truth** for the version.

The flow:

1. **Develop on a branch → open a PR.** CI runs lint, brakeman, importmap audit,
   RSpec, and `build_image` (builds the Docker image and boots it, asserting the
   Rails `/up` health endpoint returns 200). All must be green.
2. **Merge to `main`.** `main` is always releasable. (Direct pushes to `main` are
   blocked by branch protection — go through a PR.)
3. **Cut a release by pushing a git tag:**
   ```bash
   git tag v0.4.0i          # strip-the-"v" → image tag 0.4.0i
   git push origin v0.4.0i
   ```
   The `release.yml` workflow then: builds amd64 → boots it (smoke test) → and only
   if that passes, builds multi-arch (amd64+arm64) and pushes to Docker Hub as both
   `kody06/llamapress-simple:0.4.0i` and `kody06/llamapress-simple:sha-<shortsha>`
   (so every image traces back to an exact commit).
4. **Roll out to dependent projects gradually.** Point one low-risk project at the
   new tag first, verify, then update the rest. Roll back by pointing back at the
   previous tag. **Never overwrite an already-published tag.**

**Dry run before the first real release** (or any time you change the Dockerfile):
GitHub → Actions → Release → "Run workflow" → set `dry_run = true`. This builds and
boots the image but pushes nothing.

**Secret required:** the workflow needs a `DOCKERHUB_TOKEN` repo secret (a Docker Hub
access token). The username `kody06` and image name are hardcoded in `release.yml`.

## How Client Projects Use This

**Option 1: Pre-built image (production/deployment)**
```yaml
# docker-compose.yml
services:
  llamapress:
    image: kody06/llamapress-simple:0.3.1
    volumes:
      - ./rails/app:/rails/app
      - ./rails/db:/rails/db
```

**Option 2: Local build (development)**
```yaml
# docker-compose-dev.yml
services:
  llamapress:
    build: ../LlamaPress-Simple
    volumes:
      - ./rails/app:/rails/app
      - ./rails/db:/rails/db
```

## Adding a New Gem

1. Edit `Gemfile` in this repo
2. Run `bundle lock` (or build the image to generate lock)
3. Build and push new image version
4. Update client `docker-compose.yml` to use new image tag

## Local Ruby Access

To access ruby locally (outside Docker):
```bash
source ~/.zshrc  # mise should activate
```

## Running Tests

All tests run through Docker:
```bash
docker compose exec llamapress bundle exec rspec
docker compose exec llamapress npm test
```

See `.claude/skills/test_execution.md` for detailed test documentation.

## HTML Linting (ERB Lint)

**Policy: Invalid HTML is a build-breaking defect.** If the DOM is wrong, everything above it (Stimulus/SortableJS/etc.) is operating on a lie.

This repo includes `erb_lint` and `better_html` gems for validating ERB templates. The configuration (`.erb_lint.yml`) focuses on catching structural HTML errors like missing closing tags.

### Running the Linter

```bash
# From Leonardo (or any client project using this base image)
docker compose exec llamapress bundle exec erb_lint --lint-all

# Lint specific files
docker compose exec llamapress bundle exec erb_lint app/views/some_view.html.erb
```

### What It Catches

- Missing closing `</div>` tags (the exact bug that caused the Tender Builder incident)
- Mismatched opening/closing tags
- Invalid HTML structure that would corrupt the DOM

### CI Integration

Client projects should add ERB lint to their CI workflow. See Leonardo's `.github/workflows/ci.yml` for an example.

## Fixing Permission Errors

If client projects see `Permission denied` or `EACCES` errors inside the container:

### For container-created directories (tmp/, coverage/, log/)

```bash
docker compose exec -u root llamapress rm -rf /rails/tmp/cache /rails/coverage
docker compose exec -u root llamapress mkdir -p /rails/tmp/cache /rails/coverage
docker compose exec -u root llamapress chmod -R 777 /rails/tmp/cache /rails/coverage
```

### For source files baked into the image

If vendor gems or config files have bad permissions, the fix must happen here in LlamaPress-Simple:

```bash
# Fix locally (in this repo)
find . -type f ! -path "./.git/*" ! -path "./node_modules/*" -perm 600 -exec chmod 644 {} \;
find . -type d ! -path "./.git/*" ! -path "./node_modules/*" -perm 700 -exec chmod 755 {} \;

# Then rebuild and push the image
docker buildx build --file Dockerfile \
  --platform linux/amd64,linux/arm64 \
  --tag kody06/llamapress-simple:X.X.X --push .
```

The Dockerfile also has a safety net that fixes permissions at build time (`find /rails -type f -exec chmod a+r`).

## Related Projects

- **Leonardo**: `/LLMPress/Leonardo` - Development template project
- **llama_bot_rails**: `vendor/llama_bot_rails` (submodule) - Rails engine for LlamaBot integration
- **LlamaBot**: `/LLMPress/LlamaBot` - Python LangGraph service
- **Clients**: `/LLMPress/clients/` - Production client projects

## Symlink for Cross-Project Development

A symlink exists at `/LLMPress/llama_bot_rails_symlink` pointing to `LlamaPress-Simple/vendor/llama_bot_rails` for legacy compatibility with other projects that reference the gem.
