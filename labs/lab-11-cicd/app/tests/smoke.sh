#!/usr/bin/env bash
# Smoke tests for the built artefact. Usage: tests/smoke.sh [dist-dir]
# Seven assertions; the last four prove every placeholder was substituted.
set -uo pipefail
DIST="${1:-dist}"
PASS=0; FAIL=0
t() { if eval "$2" >/dev/null 2>&1; then echo "  ok   $1"; PASS=$((PASS+1)); else echo "  FAIL $1"; FAIL=$((FAIL+1)); fi; }
t "index.html was built"             "test -s '$DIST/index.html'"
t "healthz.html says ok"             "grep -qx ok '$DIST/healthz.html'"
t "build-metadata.json is valid JSON" "python3 -m json.tool '$DIST/build-metadata.json'"
t "no __RELEASE__ in index.html"     "test \"\$(grep -c __RELEASE__ '$DIST/index.html')\" -eq 0"
t "no __BUILT_AT__ in index.html"    "test \"\$(grep -c __BUILT_AT__ '$DIST/index.html')\" -eq 0"
t "no __RELEASE__ anywhere in dist"  "test -z \"\$(grep -rl __RELEASE__ '$DIST')\""
t "no __BUILT_AT__ anywhere in dist" "test -z \"\$(grep -rl __BUILT_AT__ '$DIST')\""
echo "smoke: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
