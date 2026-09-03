#!/bin/bash
# Smoke test for system binaries the image is expected to ship.
#
# Usage: bin/ci/system-deps-test.sh <container-name>
# Run against a BOOTED container built from this Dockerfile.
#
# Presence alone is not the assertion — a binary that installs but cannot
# process a real file is exactly the failure mode the chromium headless check
# in the Dockerfile exists to catch. So each tool is exercised on a PDF this
# script generates itself, and the OUTPUT is asserted.
set -u
C="${1:?usage: system-deps-test.sh <container-name>}"
fail=0

check() { # <desc> <rc>
  if [ "$2" -eq 0 ]; then
    echo "PASS: $1"
  else
    echo "FAIL: $1"
    fail=1
  fi
}

# poppler-utils: PDF -> text (pdftotext) and PDF -> image (pdftoppm).
# Build the fixture inside the container with the PDF writer the app already
# ships (Grover/Chromium), so the test needs no binary checked into the repo.
docker exec "$C" sh -c '
  set -e
  rm -rf /tmp/_poppler_probe && mkdir -p /tmp/_poppler_probe
  printf "<html><body><h1>POPPLERPROBE</h1></body></html>" > /tmp/_poppler_probe/in.html
  chromium --headless --no-sandbox --disable-dev-shm-usage \
    --print-to-pdf=/tmp/_poppler_probe/probe.pdf /tmp/_poppler_probe/in.html
  test -s /tmp/_poppler_probe/probe.pdf' >/dev/null 2>&1
check "fixture PDF generated in container" $?

docker exec "$C" sh -c 'pdftotext /tmp/_poppler_probe/probe.pdf - 2>/dev/null | grep -q POPPLERPROBE' 2>/dev/null
check "pdftotext extracts text from a PDF" $?

docker exec "$C" sh -c '
  pdftoppm -png -r 50 /tmp/_poppler_probe/probe.pdf /tmp/_poppler_probe/page >/dev/null 2>&1
  test -s /tmp/_poppler_probe/page-1.png' 2>/dev/null
check "pdftoppm renders a PDF page to PNG" $?

docker exec "$C" sh -c 'rm -rf /tmp/_poppler_probe' 2>/dev/null || true

exit $fail
