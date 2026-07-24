# Codex Skins

A collection of desktop skins for Codex, with a Windows launcher that injects the selected skin through Chrome DevTools Protocol (CDP).

## Requirements

- Windows with the Codex desktop application installed. The launcher prefers the Microsoft Store package (`OpenAI.Codex`).
- Windows PowerShell 5.1 or later.

## Use A Skin On Windows

1. Save any work in Codex. The launcher closes only visible Codex windows before restarting the app with CDP enabled; it never force-terminates Codex processes.
2. Open PowerShell and run the launcher with a skin directory.

```powershell
cd E:\codex-skins
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\apply-windows-skin.ps1 .\skins\purple-gunner
```

Replace `purple-gunner` with any skin ID from the table below. The default CDP port is `9222`; use `-Port` or `-Timeout` when needed.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\apply-windows-skin.ps1 .\skins\cyber-neon -Port 9223 -Timeout 30
```

Successful execution prints the applied skin name. To verify the launcher files and package-path validation without starting Codex:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\test\apply-windows-skin.tests.ps1
```

## Available Skins

| ID | Skin | Description |
| --- | --- | --- |
| `flame-zhaoxin` | Flame Zhao Xin | Crimson battlefield |
| `lanting-ink-yasuo` | Lanting Ink Yasuo | Ink-wash sword intent |
| `lanting-ink-tuer-suo` | Lanting Ink Tuer Suo | Rice-paper sword intent |
| `midnight-aurora` | Midnight Aurora | Aurora gradient |
| `dragon-liqing` | Dragon Lee Sin | Golden dragon ink shadow |
| `purple-gunner` | Purple Gunner | Amethyst soft glow |
| `sakura-dawn` | Sakura Dawn | Soft pink gradient |
| `amber-dusk` | Amber Dusk | Warm gold gradient |
| `forest-mist` | Forest Mist | Forest gradient |
| `cyber-neon` | Cyber Neon | Neon gradient |
| `romantic-rose` | Romantic Rose | Portrait soft glow |

## Repository Layout

```text
codex-skins/
|-- apply-windows-skin.ps1     # Windows launcher
|-- apply-mac-skin.sh          # macOS launcher placeholder
|-- runtime/
|   |-- renderer-inject.js     # CDP page injection payload
|   `-- dream-skin.css         # Shared skin styles
|-- skins/
|   `-- <skin-id>/
|       |-- skin.json          # Package metadata and asset paths
|       |-- theme.json         # Theme ID, appearance, and palette
|       |-- style.css          # Optional skin-specific CSS
|       |-- background.jpg     # Background used by the launcher
|       `-- thumb.jpg          # Preview image
`-- test/
    `-- apply-windows-skin.tests.ps1
```

## Skin Package Format

Each skin must be contained in its own `skins/<skin-id>/` directory. `skin.json` requires `schemaVersion: 1`, `kind: "dream"`, a non-empty `id` and `name`, a `swatchColor` in `#RRGGBB` format, and package-relative `background` and `theme` paths. `style` is optional.

```json
{
  "schemaVersion": 1,
  "id": "my-skin",
  "name": "My Skin",
  "kind": "dream",
  "swatchColor": "#7c3aed",
  "background": "background.jpg",
  "theme": "theme.json",
  "style": "style.css"
}
```

Do not use absolute paths or `..` path segments in package assets. The launcher rejects assets outside the selected skin directory.
