#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
node_bin='/Applications/Codex.app/Contents/Resources/cua_node/bin/node'

"$node_bin" --check "$root/runtime/apply-skin.cjs"

if [[ "$(head -n 1 "$root/apply-mac-skin.sh")" != "#!$node_bin" ]]; then
  echo 'launcher must enter through the Codex-bundled Node runtime.' >&2
  exit 1
fi

for marker in 'acquireLock' 'targetForPort' 'waitForTarget' 'new WebSocket' 'cua_node' 'remote-debugging-port' 'Another skin application is already running'; do
  if ! grep -F -- "$marker" "$root/runtime/apply-skin.cjs" >/dev/null; then
    echo "missing required launcher marker: $marker" >&2
    exit 1
  fi
done

if grep -F -- 'BASH_ENV' "$root/runtime/apply-skin.cjs" >/dev/null; then
  echo 'Node launcher must not depend on Bash environment initialization.' >&2
  exit 1
fi

if grep -F -- 'kill -9' "$root/runtime/apply-skin.cjs" >/dev/null; then
  echo 'launcher must not force-terminate Codex.' >&2
  exit 1
fi

echo 'PASS: macOS launcher uses Node for CDP injection and process coordination.'
