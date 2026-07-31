#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
node_bin=''
for candidate in \
  '/Applications/Codex.app/Contents/Resources/cua_node/bin/node' \
  "$HOME/Applications/Codex.app/Contents/Resources/cua_node/bin/node" \
  '/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node' \
  "$HOME/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node"
do
  if [[ -x "$candidate" ]]; then
    node_bin="$candidate"
    break
  fi
done

if [[ -z "$node_bin" ]]; then
  echo 'no Codex or ChatGPT bundled Node runtime found' >&2
  exit 1
fi

"$node_bin" --check "$root/runtime/apply-skin.cjs"
bash -n "$root/apply-mac-skin.sh"

if [[ "$(head -n 1 "$root/apply-mac-skin.sh")" != '#!/bin/sh' ]]; then
  echo 'launcher must use the portable shell entrypoint.' >&2
  exit 1
fi

for marker in 'acquireLock' 'targetForPort' 'waitForTarget' 'new WebSocket' 'cua_node' 'ChatGPT.app' 'remote-debugging-port' 'Another skin application is already running' 'syncCodexThemeForSkin' 'appearanceTheme' '主题不一致'; do
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
