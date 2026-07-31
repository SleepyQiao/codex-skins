#!/bin/sh
set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

for node_bin in \
  "/Applications/Codex.app/Contents/Resources/cua_node/bin/node" \
  "$HOME/Applications/Codex.app/Contents/Resources/cua_node/bin/node" \
  "/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node" \
  "$HOME/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node"
do
  if [ -x "$node_bin" ]; then
    exec "$node_bin" "$script_dir/runtime/apply-skin.cjs" "$@"
  fi
done

printf '%s\n' "No Codex or ChatGPT bundled Node runtime was found." >&2
exit 1
