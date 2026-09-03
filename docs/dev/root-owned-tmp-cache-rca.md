# RCA + design: root-owned `/rails/tmp/cache` blocks uid-1000 test runs

**Status:** fix implemented (option 0, default ACLs) per Kody's go-ahead 2026-07-19.
Changes: `acl` package + `ENTRYPOINT` in `Dockerfile`, setfacl in `bin/docker-entrypoint`
(revived from dead code), regression test `bin/ci/uid1000-write-test.sh` wired into the
`build_image` CI job (verified failing against the pre-fix image). Awaiting Kody review
before merge/release per the task gate.
**Incidents:** SI#134 (leo-palevi, 2026-07-07), SI#154 (leo-palevi-dev, 2026-07-19 — same paying customer, twice in one week).
**Investigated:** 2026-07-19 on `llamapress-dev`, against `LlamaPress-Simple` HEAD `8cbaa61`.

---

> **2026-08-05 correction — read this before trusting the mechanism below.**
> The claim that "bootsnap and sprockets overwrite cache files in place" is **wrong**,
> and probe A below does not reproduce what those libraries do. Both write a temp file
> and `rename()` it over the target (`bootsnap` `ext/bootsnap/bootsnap.c`
> `atomic_write_cache_file`; `sprockets` `lib/sprockets/path_utils.rb:362`). `rename()`
> needs write permission on the **directory**, not on the file. Measured inside the
> booted image: uid 1000 is denied an in-place truncate of a root-owned cache file, and
> succeeds at the temp-file + rename update those libraries actually perform. The
> directory permissions are therefore the load-bearing part of the fix, not the file
> ACLs. Probes C and D (`/rails/coverage`) stand unchanged — those were real failures.
> No stack trace from SI#134/SI#154 was ever captured, so the exact failing operation in
> those incidents remains unknown. See the 2026-08-05 addendum at the end.

## TL;DR

Puma runs as **root** inside the `llamapress` container; the customer's tests run as
**uid 1000**. Root-owned leaf files under `/rails/tmp/cache` cannot be truncated by
uid 1000. The original conclusion was that sprockets/bootsnap therefore hit `EACCES` and
the test run aborts — see the correction above: those libraries update by rename, so the
`chmod -R 777` on the *directories* is what keeps them working.

**The headline correction:** both prior theories about why non-root was disabled are wrong.
There was no deliberate revert for a technical blocker, and it was not "never enabled".
It was enabled at repo init and removed one day later as **collateral damage in an
unrelated Dockerfile rewrite**. There is no known blocker to re-enabling it.

---

## Confirmed mechanism (reproduced live, not inferred)

Probes run inside the running `llamapress` container on `llamapress-dev`:

| # | Operation as uid 1000 | Result |
|---|---|---|
| A | Truncate root-owned `tmp/cache/bootsnap/.../load-path-cache` | **Permission denied** (synthetic — no library does this; see 2026-08-05 correction) |
| B | Create a *new* file in the 777 `tmp/cache` dir | OK |
| C | Write into `/rails/coverage` (root, 755) | **Permission denied** |
| D | `mkdir` in `/rails` (root, 755) — i.e. recreate a wiped `coverage/` | **Permission denied** |

Supporting state: `puma ... [rails]` running as `UID 0`; **4,879** root-owned files
under `/rails/tmp/cache`.

A vs. B was read as the whole story: the directory permissions are fine, so new files are
creatable, and what fails is *overwriting a file root already created*. The second half of
that reading is wrong — bootsnap and sprockets do **not** overwrite in place on a warm run,
they rename over the target. Probe A is a synthetic operation. See the 2026-08-05 addendum.

C and D confirm the 07-19 addendum: `/rails/coverage` (SimpleCov) is the same bug class,
and after a container recreate uid 1000 cannot even recreate the directory, because
`/rails` itself is root-owned 755.

### Why it recurs after every recreate

`/rails/tmp` has **no volume** in the compose file — it lives on the container's writable
layer. `docker compose down/up` discards it, root-puma regenerates it root-owned, and the
box is broken again. Any fleet-wide maintenance recreate re-breaks every box whose
customer runs tests as uid 1000. Confirmed: no `tmp` mount in the llamapress service.

---

## Root cause in the Dockerfile

```
Dockerfile:105-107   rm -rf /rails/tmp/* ... && chmod -R 777 /rails/tmp /rails/log
Dockerfile:111-116   # (commented out) groupadd/useradd rails uid 1000 + chown ... ; # USER 1000:1000
Dockerfile:131       CMD ["sh","-c","bundle exec rails db:prepare && bundle exec rails server -b 0.0.0.0"]
bin/docker-entrypoint  exists but is DEAD CODE — no ENTRYPOINT line references it (verified by grep)
```

Line numbers differ slightly from the task writeup (which said ~101/103-110/125); the
substance is identical.

---

## History: correcting the record

The task asked "why was running as uid 1000 reverted?" and the 07-19 addendum answered
"it was added already-commented-out in `1aaa2d4`, so it was never enabled". **Both are
wrong.** `git log -S'USER 1000:1000'` returns *three* commits, not one:

| Commit | Date | What happened |
|---|---|---|
| `3822d8b` "init" | 2025-08-20 | Stock Rails 8 production Dockerfile: `useradd rails --uid 1000`, `USER 1000:1000`, `ENTRYPOINT bin/docker-entrypoint`. **Non-root was live.** |
| `c137e0d` "save devise views, allow iframes" | 2025-08-21 | Dockerfile rewritten wholesale from multi-stage *production* to single-stage *development*. `USER`, `useradd`, and `ENTRYPOINT` were **deleted as part of that rewrite**. |
| `1aaa2d4` "0.3.5g" | 2026-03-03 | The block was re-introduced **already commented out** — an aspirational note, never active. |

The decisive evidence is the `c137e0d` diff: it replaced the entire prod-template
Dockerfile (multi-stage, `RAILS_ENV=production`, jemalloc, asset precompile) with the dev
image we still ship. The `USER` line vanished along with the whole final stage. The commit
message is about Devise views — the Dockerfile rewrite was incidental, and dropping
non-root was almost certainly not a considered decision at all.

`c137e0d` also removed the `ENTRYPOINT`, which is why `bin/docker-entrypoint` has been
dead code ever since.

**Conclusion: there is no hidden technical blocker to re-enabling non-root.** The
"deliberate prior revert" premise in the task should be dropped.

One adjacent data point worth surfacing to Kody: `Leonardo/docker-compose-dev.yml` carries
a commented `# user: "1000:1000"  # DISABLED for macOS - Docker Desktop handles permissions
differently`. So non-root *was* consciously avoided at least once — but for **macOS dev
ergonomics**, not for anything about the Linux fleet where the incidents happen.

---

## Risk assessment for fix (1) — run the server as uid 1000

I probed every path the server writes, as uid 1000:

| Path | Owner | uid-1000 writable? |
|---|---|---|
| `/rails/app`, `/rails/db`, `/rails/vendor/llama_bot_rails` (bind mounts) | **1000:1000** | OK |
| `/rails/log`, `/rails/tmp/pids` | root, but 777 | OK |
| `/rails/storage` (named volume `rails_storage`) | **root 775** | **DENIED** |
| `/rails/public` | root 775 | denied (only matters if assets are written at runtime) |

Two things fall out of this:

**Good news:** the candidate blocker the task worried about — "mounted overlay files owned
by a different uid" — is a non-issue. The host user on Leo boxes is uid 1000, so every bind
mount already arrives as 1000:1000. `db:prepare` works: `/rails/db` and `schema.rb` are
already 1000-owned. Port 3000 needs no privilege.

**The one real blocker:** `/rails/storage` is a **named volume**. Docker seeds a new named
volume from the image directory's contents *and ownership*, so a `chown` in the Dockerfile
fixes freshly-created volumes — but **existing boxes keep their root-owned volume** and
ActiveStorage uploads would start failing the moment they switch to uid 1000. That is a
worse failure than the bug we're fixing, and it is the thing to design around. Same
consideration applies to any other named volume in the fleet compose (I checked the dev
compose only; the fleet compose should be audited before shipping).

---

## Head-to-head boot test (2026-07-19, throwaway containers on llamapress-dev)

Both candidate fixes were booted from the current image with the real compose mounts
(including the existing root-owned `rails_storage` volume) and probed as uid 1000:

| Probe (as uid 1000) | `user: 1000:1000` (compose) | root puma + default ACLs |
|---|---|---|
| App boots, serves 200 | OK | OK |
| Overwrite server-created bootsnap file (the incident) | OK (files are 1000-owned) | **OK (ACL inherited)** |
| Overwrite server-created sprockets file | OK | **OK** |
| Write `/rails/storage` (ActiveStorage, existing volume) | **DENIED** | n/a (root puma, unchanged) |
| Create/write `/rails/coverage` | **DENIED** | OK (dir pre-created + ACL) |
| Write `/rails/log` | OK | OK |

The `user: 1000:1000` route also boots with `` `/` is not writable`` (uid 1000 has no
passwd entry / home), which bundler works around but other gems may not.

**This reproduces Kody's "everything broke" experience with the compose `user:` route:**
on any *existing* box the `rails_storage` named volume is root-owned, so ActiveStorage
uploads fail the moment the server drops to uid 1000 — and compose `user:` offers no
root phase in which to chown it first. Fixing that requires the entrypoint
chown-then-drop machinery (option 1 below), which Kody has ruled out for now.

## Options

### (0) Default ACLs — RECOMMENDED (verified in the head-to-head above)

Keep root puma exactly as-is; make the kernel grant uid 1000 rw on every file root
creates under the shared paths:

```dockerfile
# in the apt-get install line:            + acl
```

plus an ENTRYPOINT (revive the dead `bin/docker-entrypoint`) that runs at every boot,
so it executes even when a compose file overrides `command:`, and re-covers `/rails/tmp`
after a recreate wipes it back to the image layer:

```sh
#!/bin/sh
mkdir -p /rails/coverage
setfacl -R -m u:1000:rwX -m d:u:1000:rwX /rails
exec "$@"
```

Scope decision (Kody, 2026-07-19): apply to the **whole `/rails` tree**, not just
tmp/log/coverage — root also creates files via `docker exec` (scaffolds, migrations,
`bundle install`), and every root-created file should be uid-1000 editable. ACLs only
ever add permission, so whole-tree scope has no downside. Note: ownership does NOT
change — files stay root-owned with an extra "uid 1000: rw" ACL entry (`ls -l` shows
a `+`). Files *moved* into a dir (vs created) keep their old perms — rare;
`fix_permissions` remains the backstop.

**Post-ship lesson (2026-07-19, first real box):** a single synchronous
`setfacl -R /rails` stalled boot ~2 minutes (one syscall per file across
`node_modules`' tens of thousands of files, process in D state) — no listener on
:3000, reverse proxy 502ing until Puma finally bound. Fixed (PR #49) by splitting
into a fast blocking pass over the small incident-path trees (`tmp`, `log`,
`coverage`, `db`, `app`, `config`, `spec`, `lib`, `public`) and a low-priority
background pass for the rest. Safe because files created after a dir has its
default ACL inherit it at creation — the slow pass only repairs pre-existing
files, and `fix_permissions` covers that brief window. Boot-to-listening: 9s.

Why it wins: the `d:` (default) entry is inherited by every file/dir created later —
enforced at creation time by the kernel, no watcher, no race, no chown loop. Nothing
about who puma runs as changes, so none of the uid-1000 breakage. `fix_permissions`
in LlamaBot stays as the reactive backstop.

Verified live: with the ACL set, root-puma-created bootsnap and sprockets files were
overwritable by uid 1000; coverage and log writable. Cost: `acl` package (+~100 kB)
and one `setfacl` line. Still a base-image change → gated tag + fleet/pool roll.

### (1) Run the server as uid 1000 — ruled out by Kody ("everything broke"); kept for the record

Uncomment the `useradd`/`chown`/`USER` block. Root never writes the cache; server and tests
share a uid; `/rails/coverage` is fixed by the same ownership change; and it survives
recreates permanently rather than being re-applied each boot.

Must be paired with a mitigation for the pre-existing root-owned `rails_storage` volume on
already-deployed boxes. Cleanest version: restore the dead `bin/docker-entrypoint` as a
real `ENTRYPOINT`, have it `chown` the volume-backed paths **while still root**, then
`exec` the server as uid 1000 (via `gosu`/`setpriv`, so the chown can happen before the
privilege drop). This also removes the "dead code" wart.

### (2) Normalize ownership on boot — stopgap

`chown -R 1000:1000 /rails/tmp /rails/coverage` in the entrypoint before starting root-puma
(plus `mkdir -p /rails/coverage`). Lower risk, and it fixes the recreate-wipes-tmp trigger
that drives the recurrence. **But root-puma keeps creating root-owned files at runtime**, so
a test run hours after boot can still hit it. Strictly weaker; also does not fix `mkdir` in
`/rails`.

### (3) `umask 000` on the server — not recommended

Makes root's cache files 666 so uid 1000 can overwrite them. Fragile, applies world-write to
more than intended, doesn't address `/rails/coverage` or `/rails` itself.

**Recommendation (updated 2026-07-19 after the head-to-head):** (0) default ACLs.
(1) is ruled out per Kody; the compose `user:` variant of it demonstrably breaks
ActiveStorage on existing boxes. (2) remains strictly weaker than (0) — root keeps
minting root-owned files after boot, so a long-lived box can still hit the bug.

---

## Test plan (failing test first)

Per box standing rules, the test lands before the fix and must fail on today's image:

1. Boot the image as shipped; let root-puma populate `tmp/cache` (hit the app once so
   sprockets/bootsnap write).
2. As uid 1000: truncate an existing `tmp/cache/bootsnap/**` file and an existing
   `tmp/cache/assets/sprockets/**` file → currently **EACCES** (probe A).
3. As uid 1000: create and write `/rails/coverage/x` → currently **EACCES** (probes C/D).
4. Post-fix, all must pass. Add a recreate cycle (`down`/`up`) between steps 1 and 2 to
   cover the actual recurrence trigger.

Note probe B (creating a *new* file in `tmp/cache`) passes today — a test that only checks
"can uid 1000 write in tmp/cache" would pass against the broken image. The assertion must be
an **overwrite of a root-created file**.

---

## Rollout notes

Base-image change: needs a new gated `kody06/llamapress-simple` tag rolled to the **fleet and
the instant pool**. Existing boxes stay broken until updated. Interim mitigations in place:
mothership one-off `chown`, plus a 15-min host cron on leo-palevi-dev (`perm-guard-tmp-cache`)
— retire that once the real fix reaches the box.

Audit the fleet compose for named volumes before shipping (1); the dev compose has
`rails_storage`, and any other volume-backed path has the same seeded-ownership trap.

---

## Open questions for Kody

1. Go with (0) default ACLs? It's the only option that fixes the incident with zero
   change to how puma runs and no stateful change to any volume.
2. Should the `setfacl` live in the Dockerfile CMD (fleet-wide automatically) or also be
   mirrored into the Leonardo compose `command:` for the dev box?

---

## Addendum 2026-08-05: probe A was synthetic, and the regression test was over-strict

**Trigger.** `build_image` went red on `main` on 2026-07-27 (`16846eb`) and again on
2026-08-04 (`78ab198`), on check 1 of `bin/ci/uid1000-write-test.sh`:
`FAIL: uid 1000 can overwrite root-created bootsnap cache file`. Nothing in the
entrypoint, Dockerfile, `config/boot.rb`, the test script, or the bootsnap version
(1.18.6) changed between the last green run and the first red one.

**Measured, in a locally built image booted the way CI boots it:**

| Operation as uid 1000 on a root-created bootsnap cache file | Result |
|---|---|
| In-place truncate (`: > file`) — what the test asserted | **Denied** |
| Temp file + `rename()` over it — what bootsnap/sprockets do | **OK** |
| Create a new entry in a root-created shard dir | **OK** |

3208 of 3209 bootsnap cache files are un-truncatable by uid 1000; only
`load-path-cache` is not. **No user-visible failure follows from that**, because no
writer truncates. `rename()` needs write permission on the directory, and the cache
directories are 777 with a working default ACL (`mask::rwx`).

**Why the file ACL is dropped.** `bootsnap.c:660` calls `chmod(tmp_path, 0644)` on each
cache file it writes. A `chmod` recomputes the ACL mask from the new group bits, so
`u:1000:rw` becomes `#effective:r--`. Verified directly:

```
before chmod:      user:1000:rwx  #effective:rw-   mask::rw-
after chmod 0644:  user:1000:rwx  #effective:r--   mask::r--
```

Directories escape this: bootsnap creates shard dirs with mode 0775, whose group bits
keep the mask at `rwx`.

**Why the test flipped without a code change.** It sampled ONE file
(`find … | head -1`) out of ~3200, so the result depended on directory order.
`load-path-cache` (written from Ruby, never chmod'ed, ACL intact) passes; every
`compile-cache-iseq` file fails. Six green runs between 07-19 and 07-20 happened to
sample the one good file. The gem changes in `16846eb` changed the cache contents, the
order changed, and the test began sampling a compile-cache file.

**Fix applied (2026-08-05).** `bin/ci/uid1000-write-test.sh` check 1 now asserts the
temp-file + rename update the real writers perform, samples every cache class instead of
one file, and restores root ownership so the run does not consume its own sample. A new
check 2 asserts uid 1000 can add entries to root-created shard dirs. Checks 3-5
(runtime-created file, `/rails/coverage`, `/rails/db`) are unchanged. Negative control:
stripping the ACLs and setting the cache tree to root-owned 755 fails checks 1 and 2, so
the test still catches the pre-fix state.

**Process gaps found (not yet fixed):**

1. `release.yml` never runs `bin/ci/uid1000-write-test.sh`. It boots the image, checks
   `/up`, and pushes. Every tag since 07-19 (v0.6.4c/d/x/e) shipped unchecked.
2. `release.yml` does not require a green `ci.yml`. `v0.6.4e` was published on
   2026-07-27 at 7:31 PM MDT, 8 minutes after CI went red on the same commit.

**Standing lesson.** A probe is not a reproduction. Probe A was written by hand to
demonstrate the theory, and it demonstrated a permission boundary that no library
crosses. Before asserting a mechanism, read the failing library's write path (or capture
a real stack trace). No stack trace from SI#134 or SI#154 was ever captured; if the
symptom returns, capture one first.
