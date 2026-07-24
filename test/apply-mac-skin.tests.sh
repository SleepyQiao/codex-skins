#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CODEX_SKIN_TEST_LIB=1
# shellcheck source=../apply-mac-skin.sh
source "$root/apply-mac-skin.sh"

assert_ok() { "$@" >/dev/null; }
assert_fail() { if "$@" >/dev/null 2>&1; then echo "expected failure: $*" >&2; exit 1; fi; }
assert_launcher_marker() {
  local marker="$1"
  if ! grep -F -- "$marker" "$root/apply-mac-skin.sh" >/dev/null; then
    echo "missing required launcher marker: $marker" >&2
    exit 1
  fi
}

assert_cdp_request_payload() {
  local expression="$1"
  local expected
  local actual

  expected='{"id":1,"method":"Runtime.evaluate","params":{"expression":"document.title","returnByValue":true}}'
  actual="$(cdp_request_payload "$expression")"
  if [[ "$actual" != "$expected" ]]; then
    echo "unexpected CDP request payload: $actual" >&2
    exit 1
  fi
}

assert_ok architecture_is_compatible arm64 "arm64 x86_64"
assert_ok architecture_is_compatible x86_64 "arm64 x86_64"
assert_ok architecture_is_compatible arm64 "arm64"
assert_ok architecture_is_compatible x86_64 "x86_64"
assert_fail architecture_is_compatible x86_64 "arm64"
assert_fail architecture_is_compatible arm64 "x86_64"

assert_cdp_request_payload document.title

for marker in 'uname -m' 'lipo -archs' 'webSocketTaskWithURL' '--remote-debugging-port='; do
  assert_launcher_marker "$marker"
done
if grep -F -- 'kill -9' "$root/apply-mac-skin.sh" >/dev/null; then
  echo 'macOS launcher must not force-terminate Codex.' >&2
  exit 1
fi
echo 'PASS: macOS launcher declares architecture compatibility and CDP injection behavior.'
