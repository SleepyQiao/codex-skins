#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CODEX_SKIN_TEST_LIB=1
# shellcheck source=../apply-mac-skin.sh
source "$root/apply-mac-skin.sh"

assert_ok() { "$@" >/dev/null; }
assert_fail() { if "$@" >/dev/null 2>&1; then echo "expected failure: $*" >&2; exit 1; fi; }

assert_ok architecture_is_compatible arm64 "arm64 x86_64"
assert_ok architecture_is_compatible x86_64 "arm64 x86_64"
assert_ok architecture_is_compatible arm64 "arm64"
assert_ok architecture_is_compatible x86_64 "x86_64"
assert_fail architecture_is_compatible x86_64 "arm64"
assert_fail architecture_is_compatible arm64 "x86_64"

for marker in 'uname -m' 'lipo -archs' 'Runtime.evaluate' 'webSocketTaskWithURL' '--remote-debugging-port='; do
  grep -F -- "$marker" "$root/apply-mac-skin.sh" >/dev/null
done
if grep -F -- 'kill -9' "$root/apply-mac-skin.sh" >/dev/null; then
  echo 'macOS launcher must not force-terminate Codex.' >&2
  exit 1
fi
echo 'PASS: macOS launcher declares architecture compatibility and CDP injection behavior.'
