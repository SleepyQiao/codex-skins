# macOS Architecture Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide a macOS skin launcher that injects a selected skin on Intel and Apple Silicon Macs without changing Windows behavior.

**Architecture:** `apply-mac-skin.sh` remains the single public macOS entrypoint. It exposes small shell functions for parsing, application discovery, executable architecture inspection, skin validation, and application startup; an embedded JXA program uses Foundation's native WebSocket client to call CDP `Runtime.evaluate` with the existing renderer payload.

**Tech Stack:** POSIX-compatible Bash, macOS `uname`, `defaults`, `lipo`, `sysctl`, `open`, `curl`, `osascript` JXA/Foundation, existing JSON/CSS/JavaScript runtime assets.

---

## File Structure

- Create: `test/apply-mac-skin.tests.sh` - isolated shell tests for host/app architecture compatibility and required launcher safety markers.
- Modify: `apply-mac-skin.sh` - macOS launcher and CDP injection implementation.
- Modify: `README.md` - English macOS usage and architecture compatibility notes.
- Modify: `README.zh-CN.md` - Chinese macOS usage and architecture compatibility notes.
- Do not modify: `apply-windows-skin.ps1`, `test/apply-windows-skin.tests.ps1`, or Windows usage content.

### Task 1: Define Mac Architecture Tests

**Files:**
- Create: `test/apply-mac-skin.tests.sh`
- Read: `apply-mac-skin.sh`

- [ ] **Step 1: Write the failing architecture test harness**

Create `test/apply-mac-skin.tests.sh` with these assertions. It sources the launcher in library mode so no application starts while testing.

```bash
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
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
bash test/apply-mac-skin.tests.sh
```

Expected: failure because the current launcher is empty and does not define `architecture_is_compatible`.

- [ ] **Step 3: Commit the failing test**

```bash
git add test/apply-mac-skin.tests.sh
git commit -m "test: cover macOS launcher architecture rules"
```

### Task 2: Implement the macOS Launcher

**Files:**
- Modify: `apply-mac-skin.sh`
- Test: `test/apply-mac-skin.tests.sh`

- [ ] **Step 1: Add command parsing and independent architecture functions**

Implement `architecture_is_compatible` exactly as a host-architecture membership check:

```bash
architecture_is_compatible() {
  local host_arch="$1"
  local app_arches="$2"
  case " $app_arches " in
    *" $host_arch "*) return 0 ;;
    *) return 1 ;;
  esac
}
```

Add `--app-path`, `--port`, and `--timeout` options; reject unknown options, a missing skin ID, unsupported host architectures, and invalid numeric option values with a non-zero exit.

- [ ] **Step 2: Add app discovery and executable validation**

Implement `resolve_codex_app` to choose an explicit `--app-path` first, then `/Applications/Codex.app`, `$HOME/Applications/Codex.app`, `/Applications/ChatGPT.app`, and `$HOME/Applications/ChatGPT.app`. Implement `resolve_app_executable` with `defaults read "$app/Contents/Info" CFBundleExecutable`, and reject an executable outside `Contents/MacOS/`. Read architectures using `lipo -archs`.

On `arm64`, allow an Intel-only app only when this command succeeds:

```bash
/usr/sbin/sysctl -in sysctl.proc_translated >/dev/null 2>&1 || /usr/bin/pgrep -x oahd >/dev/null 2>&1
```

Otherwise exit before launch with an instruction to install Rosetta using `softwareupdate --install-rosetta --agree-to-license`. Reject Intel hosts running arm64-only apps.

- [ ] **Step 3: Add skin and runtime validation**

Validate the selected `skins/<id>` directory, `skin.json`, `theme.json`, `background.jpg`, `runtime/dream-skin.css`, and `runtime/renderer-inject.js`. Reject skin identifiers containing `/`, `\\`, or `..`.

Use an embedded `osascript -l JavaScript` JXA program with Foundation to parse the two JSON files, read the CSS and optional skin stylesheet as UTF-8, base64-encode the background, and JSON-serialize the five replacements for `__DREAM_SKIN_*_JSON__` placeholders in `renderer-inject.js`. This keeps the launcher self-contained on macOS and avoids a Python, Node, or third-party WebSocket dependency.

- [ ] **Step 4: Add graceful startup, CDP wait, and JXA evaluation**

Close only visible app windows with `osascript -e 'tell application id "com.openai.codex" to quit'` when the bundle identifier is available; never use `kill -9`. Launch with:

```bash
open -n "$app_path" --args "--remote-debugging-port=$port"
```

Poll `http://127.0.0.1:$port/json/list` with `curl --fail --silent` until the timeout, preferring `app://-/index.html` and otherwise accepting the sole `page` target. Pass its `webSocketDebuggerUrl` and expression to an embedded `osascript -l JavaScript` program that uses `NSURLSession.webSocketTaskWithURL`, sends `{ id: 1, method: "Runtime.evaluate", ... }`, waits on `NSRunLoop`, and fails on CDP protocol or JavaScript evaluation errors.

- [ ] **Step 5: Run tests to verify they pass**

Run:

```bash
bash -n apply-mac-skin.sh
bash test/apply-mac-skin.tests.sh
powershell -NoProfile -ExecutionPolicy Bypass -File test/apply-windows-skin.tests.ps1
```

Expected: shell syntax check succeeds, macOS test prints its `PASS:` line, and the existing Windows test prints its existing `PASS:` line.

- [ ] **Step 6: Commit the launcher**

```bash
git add apply-mac-skin.sh test/apply-mac-skin.tests.sh
git commit -m "Add macOS skin launcher architecture support"
```

### Task 3: Document macOS Usage

**Files:**
- Modify: `README.md`
- Modify: `README.zh-CN.md`
- Read: `apply-mac-skin.sh`

- [ ] **Step 1: Add English usage**

Add a `Use A Skin On macOS` section after the Windows section. Include the exact commands:

```bash
chmod +x ./apply-mac-skin.sh
./apply-mac-skin.sh flame-zhaoxin
./apply-mac-skin.sh flame-zhaoxin --app-path /Applications/Codex.app
```

Explain that the launcher detects Intel and Apple Silicon automatically, accepts Universal builds, and requires Rosetta only for an Intel-only app on Apple Silicon.

- [ ] **Step 2: Add Chinese usage**

Add a `macOS 使用方式` section with the same commands and the equivalent compatibility explanation: automatic Intel/M-series detection, Universal package support, and Rosetta required only for Intel-only applications on Apple Silicon.

- [ ] **Step 3: Verify documentation commands and Windows isolation**

Run:

```bash
rg -n "apply-mac-skin\.sh|Apple Silicon|Intel|M 系列|Rosetta" README.md README.zh-CN.md
git diff --name-only HEAD~1..HEAD
```

Expected: both READMEs include the macOS command and architecture guidance; no Windows launcher or Windows test is changed by this task.

- [ ] **Step 4: Commit documentation**

```bash
git add README.md README.zh-CN.md
git commit -m "Document macOS skin launcher usage"
```

### Task 4: Final Verification and Delivery

**Files:**
- Verify: `apply-mac-skin.sh`
- Verify: `test/apply-mac-skin.tests.sh`
- Verify: `apply-windows-skin.ps1`
- Verify: `test/apply-windows-skin.tests.ps1`

- [ ] **Step 1: Run the complete focused verification**

```bash
bash -n apply-mac-skin.sh
bash test/apply-mac-skin.tests.sh
powershell -NoProfile -ExecutionPolicy Bypass -File test/apply-windows-skin.tests.ps1
git diff --check origin/master...HEAD
git status --short
```

Expected: both test commands succeed, diff check reports no whitespace errors, and status is clean.

- [ ] **Step 2: Verify the Windows files are byte-identical to the design baseline**

```bash
git diff --exit-code 6d7389e -- apply-windows-skin.ps1 test/apply-windows-skin.tests.ps1
```

Expected: exit code 0 and no output.

- [ ] **Step 3: Push only after all verification commands pass**

```bash
git push origin master
```
