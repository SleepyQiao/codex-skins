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
  local expected="$2"
  local actual

  actual="$(cdp_request_payload "$expression")"
  if [[ "$actual" != "$expected" ]]; then
    echo "unexpected CDP request payload: $actual" >&2
    exit 1
  fi
}

assert_payload_file_handoff() {
  local payload_field_source
  local failed=0

  if grep -F -- 'printf %s "$payload"|payload_field' "$root/apply-mac-skin.sh" >/dev/null; then
    echo 'payload_field must receive a payload file path rather than piped stdin.' >&2
    failed=1
  fi
  if ! grep -F -- 'payload_field expression "$payload_file"' "$root/apply-mac-skin.sh" >/dev/null || \
     ! grep -F -- 'payload_field name "$payload_file"' "$root/apply-mac-skin.sh" >/dev/null; then
    echo 'payload_field must be called as payload_field <field> "$payload_file".' >&2
    failed=1
  fi

  payload_field_source="$(awk '/^payload_field[[:space:]]*\(\)/ { printing=1 } printing { print } /^cdp_eval[[:space:]]*\(\)/ { exit }' "$root/apply-mac-skin.sh")"
  if [[ -z "$payload_field_source" ]]; then
    echo 'missing payload_field JXA extractor.' >&2
    failed=1
  elif [[ "$payload_field_source" == *'fileHandleWithStandardInput'* ]]; then
    echo 'payload_field JXA extractor must read JSON from its second run argument file path, not standard input.' >&2
    failed=1
  fi
  if [[ "$payload_field_source" != *'ContentsOfFile'* || "$payload_field_source" != *'a[1]'* ]]; then
    echo 'payload_field JXA extractor must read JSON from its second run argument file path.' >&2
    failed=1
  fi

  (( failed == 0 ))
}

assert_ok architecture_is_compatible arm64 "arm64 x86_64"
assert_ok architecture_is_compatible x86_64 "arm64 x86_64"
assert_ok architecture_is_compatible arm64 "arm64"
assert_ok architecture_is_compatible x86_64 "x86_64"
assert_fail architecture_is_compatible x86_64 "arm64"
assert_fail architecture_is_compatible arm64 "x86_64"

assert_cdp_request_payload document.title '{"id":1,"method":"Runtime.evaluate","params":{"expression":"document.title","returnByValue":true}}'
assert_cdp_request_payload 'document.querySelector("a\b").textContent' '{"id":1,"method":"Runtime.evaluate","params":{"expression":"document.querySelector(\"a\\b\").textContent","returnByValue":true}}'

assert_payload_file_handoff

for marker in 'uname -m' 'lipo -archs' 'webSocketTaskWithURL' '--remote-debugging-port='; do
  assert_launcher_marker "$marker"
done
if grep -F -- 'kill -9' "$root/apply-mac-skin.sh" >/dev/null; then
  echo 'macOS launcher must not force-terminate Codex.' >&2
  exit 1
fi
echo 'PASS: macOS launcher declares architecture compatibility and CDP injection behavior.'
