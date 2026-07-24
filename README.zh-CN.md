# Codex 皮肤

这是一个 Codex 桌面端皮肤集合。Windows 启动器会通过 Chrome DevTools Protocol (CDP) 注入所选皮肤。

## 运行要求

- 已安装 Codex 桌面端。启动器优先识别 Microsoft Store 版 `OpenAI.Codex`。
- Windows PowerShell 5.1 或更高版本。

## 平台限制

Windows 版 Codex 的工具栏及其他原生控件颜色可能仍由系统控制，因此皮肤无法保证所有工具栏元素的颜色完全统一。macOS 版没有此限制。

## Windows 使用方式

1. 先保存 Codex 中的工作。启动器会关闭可见的 Codex 窗口，再以启用 CDP 的方式重启；它不会强制结束 Codex 进程。
2. 打开 PowerShell，传入想使用的皮肤目录。

```powershell
cd E:\codex-skins
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\apply-windows-skin.ps1 .\skins\purple-gunner
```

把 `purple-gunner` 替换为下表中的任意皮肤 ID。默认 CDP 端口为 `9222`，可按需要传入 `-Port` 或 `-Timeout`。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\apply-windows-skin.ps1 .\skins\cyber-neon -Port 9223 -Timeout 30
```

运行成功后会输出已应用的皮肤名称。若只想检查启动器文件和皮肤路径校验，而不启动 Codex：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\test\apply-windows-skin.tests.ps1
```

## 可用皮肤

| ID | 皮肤 | 描述 |
| --- | --- | --- |
| `flame-zhaoxin` | 赤焰战场·赵信 | 赤焰战场 |
| `lanting-ink-yasuo` | 兰亭墨韵·亚索 | 水墨剑意 |
| `lanting-ink-tuer-suo` | 兰亭墨韵·托儿所 | 宣纸剑意 |
| `midnight-aurora` | 午夜极光·极光渐变 | 极光渐变 |
| `dragon-liqing` | 龙的传人·李青 | 金龙墨影 |
| `purple-gunner` | 跳跳倩影·女枪 | 紫晶柔光 |
| `sakura-dawn` | 樱粉晨曦·柔粉渐变 | 柔粉渐变 |
| `amber-dusk` | 琥珀黄昏·暖金渐变 | 暖金渐变 |
| `forest-mist` | 森野薄雾·森野渐变 | 森野渐变 |
| `cyber-neon` | 赛博霓虹·霓虹渐变 | 霓虹渐变 |
| `romantic-rose` | 桥本有菜·人物柔光 | 人物柔光 |

## 皮肤预览

点击缩略图可打开对应皮肤的完整背景图。

| | | |
| --- | --- | --- |
| <a href="skins/flame-zhaoxin/background.jpg"><img src="skins/flame-zhaoxin/thumb.jpg" alt="Flame Zhao Xin thumbnail" width="180"></a> | <a href="skins/lanting-ink-yasuo/background.jpg"><img src="skins/lanting-ink-yasuo/thumb.jpg" alt="Lanting Ink Yasuo thumbnail" width="180"></a> | <a href="skins/lanting-ink-tuer-suo/background.jpg"><img src="skins/lanting-ink-tuer-suo/thumb.jpg" alt="Lanting Ink Tuer Suo thumbnail" width="180"></a> |
| `flame-zhaoxin` | `lanting-ink-yasuo` | `lanting-ink-tuer-suo` |
| <a href="skins/midnight-aurora/background.jpg"><img src="skins/midnight-aurora/thumb.jpg" alt="Midnight Aurora thumbnail" width="180"></a> | <a href="skins/dragon-liqing/background.jpg"><img src="skins/dragon-liqing/thumb.jpg" alt="Dragon Lee Sin thumbnail" width="180"></a> | <a href="skins/purple-gunner/background.jpg"><img src="skins/purple-gunner/thumb.jpg" alt="Purple Gunner thumbnail" width="180"></a> |
| `midnight-aurora` | `dragon-liqing` | `purple-gunner` |
| <a href="skins/sakura-dawn/background.jpg"><img src="skins/sakura-dawn/thumb.jpg" alt="Sakura Dawn thumbnail" width="180"></a> | <a href="skins/amber-dusk/background.jpg"><img src="skins/amber-dusk/thumb.jpg" alt="Amber Dusk thumbnail" width="180"></a> | <a href="skins/forest-mist/background.jpg"><img src="skins/forest-mist/thumb.jpg" alt="Forest Mist thumbnail" width="180"></a> |
| `sakura-dawn` | `amber-dusk` | `forest-mist` |
| <a href="skins/cyber-neon/background.jpg"><img src="skins/cyber-neon/thumb.jpg" alt="Cyber Neon thumbnail" width="180"></a> | <a href="skins/romantic-rose/background.jpg"><img src="skins/romantic-rose/thumb.jpg" alt="Romantic Rose thumbnail" width="180"></a> | |
| `cyber-neon` | `romantic-rose` | |

## 仓库目录结构

```text
codex-skins/
|-- apply-windows-skin.ps1     # Windows 启动器
|-- apply-mac-skin.sh          # macOS 启动器占位文件
|-- runtime/
|   |-- renderer-inject.js     # CDP 页面注入载荷
|   `-- dream-skin.css         # 共享皮肤样式
|-- skins/
|   `-- <skin-id>/
|       |-- skin.json          # 皮肤元数据与资源路径
|       |-- theme.json         # 主题 ID、外观与配色
|       |-- style.css          # 可选的皮肤专属 CSS
|       |-- background.jpg     # 启动器使用的背景图
|       `-- thumb.jpg          # 预览图
`-- test/
    `-- apply-windows-skin.tests.ps1
```

## 皮肤包格式

每套皮肤必须放在独立的 `skins/<skin-id>/` 目录。`skin.json` 必须包含 `schemaVersion: 1`、`kind: "dream"`、非空的 `id` 与 `name`、`#RRGGBB` 格式的 `swatchColor`，以及相对皮肤包目录的 `background` 与 `theme` 路径；`style` 为可选项。

```json
{
  "schemaVersion": 1,
  "id": "my-skin",
  "name": "我的皮肤",
  "kind": "dream",
  "swatchColor": "#7c3aed",
  "background": "background.jpg",
  "theme": "theme.json",
  "style": "style.css"
}
```

不要使用绝对路径或包含 `..` 的资源路径。启动器会拒绝位于所选皮肤目录之外的资源。
