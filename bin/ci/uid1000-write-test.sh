#!/bin/bash
# Regression test for SI#134 / SI#154: root-owned files under /rails/tmp/cache
# block uid-1000 test runs (EACCES).
#
# Usage: bin/ci/uid1000-write-test.sh <container-name>
# Run against a BOOTED container (server as root has populated tmp/cache).
#
# The assertion must be an UPDATE of a file root already created — creating a
# brand-new file in the 777 dirs works even on the broken image, so that alone
# must never be the assertion here.
#
# 2026-08-05: check 1 asserts the update pattern the real writers use, not an
# in-place truncate. Measured inside the booted image: bootsnap
# (ext/bootsnap/bootsnap.c atomic_write_cache_file) and sprockets
# (lib/sprockets/path_utils.rb:362) both write a temp file and rename it over
# the target. rename() needs write permission on the DIRECTORY, not on the
# file, so both succeed as uid 1000. Neither ever truncates a cache file.
#
# The old in-place truncate assertion failed on bootsnap compile-cache files
# for a reason that never reaches a user: bootsnap chmods each cache file to
# 0644 after creating it, and chmod resets the ACL mask, which drops write
# access for uid 1000 on that file. The file is still replaceable by rename, so
# warm runs work. That over-strict assertion also sampled ONE file via
# `head -1`, so it passed or failed depending on directory order.
set -u
C="${1:?usage: uid1000-write-test.sh <container-name>}"
fail=0

check() { # <desc> <expected: 0=ok> <actual rc>
  if [ "$3" -eq 0 ]; then
    echo "PASS: $1"
  else
    echo "FAIL: $1"
    fail=1
  fi
}

# Replace a root-created file the way bootsnap and sprockets do: uid 1000 copies
# the content to a temp file in the same directory, then renames it over the
# target. Content-preserving, so the cache stays valid for later checks.
# The replacement file belongs to uid 1000, so hand it back to root afterwards —
# otherwise the run consumes its own sample and a second run finds fewer
# root-owned targets.
replace_as_uid1000() { # <path>
  docker exec -u 1000:1000 "$C" sh -c "cp '$1' '$1.tmp.probe' && mv '$1.tmp.probe' '$1'" 2>/dev/null
  rc=$?
  docker exec -u root "$C" sh -c "chown root:root '$1'" 2>/dev/null || true
  return $rc
}

# 1. Update the bootsnap cache files the root server created at boot. Sample
#    across every cache class (load-path-cache, compile-cache-iseq,
#    compile-cache-yaml), not one file — the old `head -1` made the result
#    depend on directory order.
targets=$(docker exec "$C" sh -c '
  find /rails/tmp/cache/bootsnap -name load-path-cache -type f -user root | head -1
  for d in /rails/tmp/cache/bootsnap/bootsnap/compile-cache-*; do
    [ -d "$d" ] && find "$d" -type f -user root | head -3
  done')
if [ -z "$targets" ]; then
  echo "FAIL: no root-owned bootsnap cache file found — server did not boot as expected"
  exit 1
fi
sampled=0
bad=0
for f in $targets; do
  sampled=$((sampled + 1))
  replace_as_uid1000 "$f" || bad=$((bad + 1))
done
[ "$bad" -eq 0 ]
check "uid 1000 can replace root-created bootsnap cache files ($sampled sampled, $bad denied)" 0 $?

# 2. Add a NEW cache entry inside a directory root created at boot. Bootsnap
#    creates these shard dirs as root at runtime; uid 1000 must be able to write
#    new entries into them.
docker exec -u 1000:1000 "$C" sh -c '
  d=$(dirname $(find /rails/tmp/cache/bootsnap/bootsnap/compile-cache-* -type f -user root 2>/dev/null | head -1))
  [ -n "$d" ] && echo x > "$d/_perm_probe" && rm -f "$d/_perm_probe"' 2>/dev/null
check "uid 1000 can add new entries to root-created cache dirs" 0 $?

# 3. Overwrite a file root creates at RUNTIME (after boot — simulates the
#    sprockets/bootsnap writes a live server keeps doing).
docker exec "$C" sh -c 'mkdir -p /rails/tmp/cache/assets && echo x > /rails/tmp/cache/assets/_perm_probe'
docker exec -u 1000:1000 "$C" sh -c ': > /rails/tmp/cache/assets/_perm_probe' 2>/dev/null
check "uid 1000 can overwrite file root created after boot" 0 $?
docker exec "$C" sh -c 'rm -f /rails/tmp/cache/assets/_perm_probe'

# 4. SimpleCov: uid 1000 can create and write /rails/coverage (SI#154 addendum).
docker exec -u 1000:1000 "$C" sh -c 'mkdir -p /rails/coverage && echo x > /rails/coverage/_perm_probe' 2>/dev/null
check "uid 1000 can create/write /rails/coverage" 0 $?
docker exec "$C" sh -c 'rm -f /rails/coverage/_perm_probe' 2>/dev/null

# 5. Scaffolds/migrations: uid 1000 can overwrite a file root created in app dirs
#    (rails generate / db:migrate via docker exec run as root too).
docker exec "$C" sh -c 'echo x > /rails/db/_perm_probe'
docker exec -u 1000:1000 "$C" sh -c ': > /rails/db/_perm_probe' 2>/dev/null
check "uid 1000 can overwrite root-created file in /rails/db" 0 $?
docker exec "$C" sh -c 'rm -f /rails/db/_perm_probe'

exit $fail
