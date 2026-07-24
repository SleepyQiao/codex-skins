# macOS Architecture Support Design

## Scope

Implement `apply-mac-skin.sh` as a standalone macOS launcher for Codex skins.
It must support Intel Macs (`x86_64`) and Apple Silicon Macs (`arm64`), including
universal application bundles. The existing Windows launcher, tests, and Windows
usage instructions are out of scope and must remain unchanged.

## Interface

The launcher accepts a skin identifier and optional application path:

```sh
./apply-mac-skin.sh <skin-id> [--app-path /Applications/Codex.app]
```

Without `--app-path`, it searches for the supported application bundle in the
user and system Applications directories. The script validates the skin assets
before changing application state.

## Architecture Compatibility

1. Read the host architecture with `uname -m`; only `arm64` and `x86_64` are
   supported.
2. Resolve the application bundle executable from its `Info.plist`.
3. Use `lipo -archs` to read the executable architectures.
4. Allow the app when it contains the host architecture or is universal.
5. On Apple Silicon, permit an Intel-only executable only when Rosetta is
   available; otherwise stop with a remediation message.
6. Stop before injection when the executable cannot be inspected or has no
   compatible architecture.

## Injection Flow

The script launches the validated application with a dedicated CDP port, waits
for the local debugging endpoint, injects the selected skin payload from
`runtime/`, and reports the result. It uses macOS-native tools only and leaves
the current application installation unmodified.

## Failure Handling

The script exits non-zero with actionable messages for an invalid skin ID,
missing runtime files, unsupported host architecture, missing app bundle,
missing app executable, incompatible executable architecture, unavailable
Rosetta, CDP startup timeout, or injection failure.

## Verification

Add shell-level tests using command stubs for architecture detection and
compatibility decisions. The tests must first fail against the empty launcher,
then pass after implementation. Run syntax validation with `bash -n`, the
focused macOS tests, and the existing Windows test without modifying its source.
