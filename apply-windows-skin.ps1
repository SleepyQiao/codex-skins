[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$SkinPackage,
  [ValidateRange(1, 65535)]
  [int]$Port = 9222,
  [ValidateRange(1, 120)]
  [int]$Timeout = 20
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

class LauncherFailure : System.Exception {
  [int]$ExitCode

  LauncherFailure([int]$exitCode, [string]$message) : base($message) {
    $this.ExitCode = $exitCode
  }
}

function Stop-Launcher([int]$Code, [string]$Message) {
  throw [LauncherFailure]::new($Code, $Message)
}

function Read-JsonFile([string]$Path, [string]$Label) {
  try {
    $value = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
  } catch {
    Stop-Launcher 2 "$Label 不是有效 JSON：$Path"
  }
  if ($null -eq $value -or $value -is [System.Array]) {
    Stop-Launcher 2 "$Label 必须是 JSON 对象：$Path"
  }
  return $value
}

function Get-ManifestValue($Manifest, [string]$Name) {
  $property = $Manifest.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

function Resolve-PackageFile(
  [string]$Root,
  $Relative,
  [string]$Label,
  [bool]$Optional = $false
) {
  if ($null -eq $Relative -and $Optional) { return $null }
  if ($Relative -isnot [string] -or [string]::IsNullOrWhiteSpace($Relative)) {
    Stop-Launcher 2 "skin.json 缺少 $Label"
  }
  $normalized = $Relative.Replace('\', '/')
  $hasInvalidSegment = @($normalized.Split('/') | Where-Object { $_ -eq '' -or $_ -eq '..' }).Count -gt 0
  if ([System.IO.Path]::IsPathRooted($normalized) -or $hasInvalidSegment) {
    Stop-Launcher 2 "$Label 必须是皮肤包内的相对路径"
  }
  $rootPath = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
  $candidate = [System.IO.Path]::GetFullPath((Join-Path $rootPath $normalized))
  if (-not $candidate.StartsWith("$rootPath$([System.IO.Path]::DirectorySeparatorChar)", [System.StringComparison]::OrdinalIgnoreCase)) {
    Stop-Launcher 2 "$Label 不得位于皮肤包外"
  }
  if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
    Stop-Launcher 2 "$Label 不存在：$normalized"
  }
  return $candidate
}

function Resolve-SkinPackage(
  [string]$Value,
  [string]$LauncherRoot = $PSScriptRoot
) {
  if ([string]::IsNullOrWhiteSpace($Value)) {
    Stop-Launcher 2 'Skin package path or ID cannot be empty.'
  }
  if ([System.IO.Path]::IsPathRooted($Value)) {
    return [System.IO.Path]::GetFullPath($Value)
  }
  if ($Value.Contains('..')) {
    Stop-Launcher 2 'Skin ID must not contain ..'
  }

  $normalized = $Value.Replace('/', '\')
  if ($normalized -notmatch '(^|\\)skins(\\|$)') {
    if (-not $normalized.Contains('\')) {
      $launcherRootPath = [System.IO.Path]::GetFullPath($LauncherRoot)
      return [System.IO.Path]::GetFullPath((Join-Path (Join-Path $launcherRootPath 'skins') $normalized))
    }
    $normalized = Join-Path 'skins' $normalized
  }
  return [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $normalized))
}
function Get-MimeType([string]$Path) {
  switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
    '.jpg' { return 'image/jpeg' }
    '.jpeg' { return 'image/jpeg' }
    '.png' { return 'image/png' }
    '.webp' { return 'image/webp' }
    default { return 'application/octet-stream' }
  }
}

function Convert-CodexAppearance($Value) {
  $appearance = ([string]$Value).Trim().ToLowerInvariant()
  if ($appearance -eq 'light' -or $appearance -eq 'dark') { return $appearance }
  return $null
}

function Get-CodexConfigPath {
  if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
    return [System.IO.Path]::GetFullPath((Join-Path $env:CODEX_HOME 'config.toml'))
  }
  if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
    return [System.IO.Path]::GetFullPath((Join-Path (Join-Path $env:USERPROFILE '.codex') 'config.toml'))
  }
  if (-not [string]::IsNullOrWhiteSpace($env:HOME)) {
    return [System.IO.Path]::GetFullPath((Join-Path (Join-Path $env:HOME '.codex') 'config.toml'))
  }
  return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'config.toml'))
}

function Get-CodexConfiguredAppearance([string]$Content) {
  $inDesktop = $false
  foreach ($rawLine in ($Content -split "\r?\n")) {
    $line = $rawLine.Trim()
    if ($line.Length -eq 0 -or $line.StartsWith('#')) { continue }
    if ($line -match '^\[([^\]]+)\]$') {
      $inDesktop = $Matches[1] -eq 'desktop'
      continue
    }
    if (-not $inDesktop) { continue }
    if ($line -match '^appearanceTheme\s*=\s*"([^"]*)"\s*$') {
      $appearance = Convert-CodexAppearance $Matches[1]
      if ($null -ne $appearance) { return $appearance }
    }
  }
  return 'light'
}

function Set-CodexConfiguredAppearance([string]$Content, [string]$Appearance) {
  $newline = if ($Content.Contains("`r`n")) { "`r`n" } else { "`n" }
  $lines = [System.Collections.Generic.List[string]]::new()
  foreach ($line in ($Content -split "\r?\n")) { [void]$lines.Add($line) }
  $inDesktop = $false
  $desktopHeader = -1
  $insertAt = -1
  for ($index = 0; $index -lt $lines.Count; $index++) {
    $line = $lines[$index].Trim()
    if ($line -match '^\[([^\]]+)\]$') {
      if ($inDesktop -and $insertAt -lt 0) { $insertAt = $index }
      $inDesktop = $Matches[1] -eq 'desktop'
      if ($inDesktop) {
        $desktopHeader = $index
        $insertAt = -1
      }
      continue
    }
    if (-not $inDesktop) { continue }
    if ($line -match '^appearanceTheme\s*=') {
      $lines[$index] = "appearanceTheme = `"$Appearance`""
      return [string]::Join($newline, $lines)
    }
  }
  if ($desktopHeader -ge 0) {
    $targetIndex = if ($insertAt -ge 0) { $insertAt } else { $desktopHeader + 1 }
    $lines.Insert($targetIndex, "appearanceTheme = `"$Appearance`"")
    return [string]::Join($newline, $lines)
  }
  $suffix = if ($Content.Length -gt 0 -and -not $Content.EndsWith("`n")) { $newline } else { '' }
  return "${Content}${suffix}[desktop]${newline}appearanceTheme = `"$Appearance`"$newline"
}

function Sync-CodexThemeForSkin([string]$Appearance, [string]$SkinName) {
  $expected = Convert-CodexAppearance $Appearance
  if ($null -eq $expected) { return }
  $config = Get-CodexConfigPath
  $content = ''
  try {
    if (Test-Path -LiteralPath $config -PathType Leaf) {
      $content = Get-Content -LiteralPath $config -Raw -Encoding UTF8
    }
  } catch {
    Write-Warning "无法读取 Codex 主题配置：$($_.Exception.Message)；继续应用皮肤。"
    return
  }
  $current = Get-CodexConfiguredAppearance $content
  if ($current -eq $expected) { return }
  Write-Warning "主题不一致：当前 Codex 是 $current，皮肤 $SkinName 适配 $expected；已自动切换配置并继续应用皮肤。"
  try {
    $parent = Split-Path -Parent $config
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
      [void](New-Item -ItemType Directory -Path $parent -Force)
    }
    [System.IO.File]::WriteAllText($config, (Set-CodexConfiguredAppearance $content $expected), [System.Text.UTF8Encoding]::new($false))
  } catch {
    Write-Warning "无法更新 Codex 主题配置：$($_.Exception.Message)；继续应用皮肤。"
  }
}

function Get-CodexExecutable {
  $storePackage = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -ne $storePackage -and $storePackage.InstallLocation) {
    $candidate = Join-Path $storePackage.InstallLocation 'app\ChatGPT.exe'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
  }
  $runningProcess = Get-Process -Name 'Codex','ChatGPT' -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -ne $runningProcess -and $runningProcess.Path -and (Test-Path -LiteralPath $runningProcess.Path -PathType Leaf)) {
    return $runningProcess.Path
  }
  foreach ($commandName in @('Codex.exe', 'ChatGPT.exe')) {
    $command = Get-Command $commandName -ErrorAction SilentlyContinue
    if ($null -ne $command -and (Test-Path -LiteralPath $command.Source -PathType Leaf)) {
      return $command.Source
    }
  }
  $registryKeys = @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\Codex.exe',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\Codex.exe'
  )
  foreach ($key in $registryKeys) {
    if (Test-Path -LiteralPath $key) {
      $candidate = (Get-Item -LiteralPath $key).GetValue('')
      if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    }
  }
  $candidates = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Codex\Codex.exe'),
    (Join-Path $env:LOCALAPPDATA 'Codex\Codex.exe'),
    (Join-Path $env:ProgramFiles 'Codex\Codex.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Codex\Codex.exe')
  )
  foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
  }
  Stop-Launcher 3 '未找到 Codex.exe 或 ChatGPT.exe；已检查 PATH、App Paths、LocalAppData 和 Program Files。'
}

function Get-CodexNodeRuntime([string]$ExecutablePath) {
  $desktopRoot = Split-Path -Parent $ExecutablePath
  $nodePath = Join-Path $desktopRoot 'resources\cua_node\bin\node.exe'
  if (-not (Test-Path -LiteralPath $nodePath -PathType Leaf)) { Stop-Launcher 3 "Codex desktop Node runtime not found: $nodePath" }
  return $nodePath
}

function Invoke-NodeCdpEvaluate([string]$NodePath, [string]$WebSocketUrl, [string]$Expression) {
  $expressionFile = [System.IO.Path]::GetTempFileName()
  try {
    [System.IO.File]::WriteAllText($expressionFile, $Expression, [System.Text.UTF8Encoding]::new($false))
    $helper = Join-Path $PSScriptRoot 'runtime\apply-skin.cjs'
    $output = & $NodePath $helper '--platform' 'windows' '--websocket-url' $WebSocketUrl '--expression-file' $expressionFile 2>&1
    if ($LASTEXITCODE -ne 0) { Stop-Launcher 5 "CDP Node helper failed: $($output -join [Environment]::NewLine)" }
  } finally { Remove-Item -LiteralPath $expressionFile -Force -ErrorAction SilentlyContinue }
}
function Start-Codex([int]$DebugPort) {
  $executable = Get-CodexExecutable
  $tempRoot = [System.IO.Path]::GetTempPath()
  $profile = Join-Path $tempRoot ("codex-skin-cdp-$DebugPort")
  $lockfile = Join-Path $profile 'lockfile'
  $profileHasContent = Test-Path -LiteralPath $lockfile -PathType Leaf
  if (-not $profileHasContent -and (Test-Path -LiteralPath $profile -PathType Container)) {
    $profileHasContent = $null -ne (Get-ChildItem -LiteralPath $profile -Force | Select-Object -First 1)
  }
  if ($profileHasContent) {
    $profile = Join-Path $tempRoot ("codex-skin-cdp-$DebugPort-$PID")
  }
  [void](New-Item -ItemType Directory -Path $profile -Force)
  Start-Process -FilePath $executable -ArgumentList @("--remote-debugging-port=$DebugPort", "--user-data-dir=$profile") | Out-Null
}

function Stop-CodexGracefully(
  [string]$ExecutablePath,
  [int]$TimeoutSeconds = 15,
  [int[]]$ExcludeIds = @()
) {
  $processes = @(Get-Process -Name 'Codex','ChatGPT' -ErrorAction SilentlyContinue | Where-Object {
    $_.Path -eq $ExecutablePath
  })
  if ($processes.Count -eq 0) { return }

  $windowProcesses = @($processes | Where-Object {
    $_.MainWindowHandle -ne [IntPtr]::Zero -and $ExcludeIds -notcontains $_.Id
  })
  if ($windowProcesses.Count -eq 0) { return }
  foreach ($process in $windowProcesses) {
    $process.Refresh()
    [void]$process.CloseMainWindow()
  }

  $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
  while (@(Get-Process -Name 'Codex','ChatGPT' -ErrorAction SilentlyContinue | Where-Object {
    $_.Path -eq $ExecutablePath -and $_.MainWindowHandle -ne [IntPtr]::Zero -and $ExcludeIds -notcontains $_.Id
  }).Count -gt 0 -and [DateTime]::UtcNow -lt $deadline) {
    Start-Sleep -Milliseconds 200
  }
  if (@(Get-Process -Name 'Codex','ChatGPT' -ErrorAction SilentlyContinue | Where-Object {
    $_.Path -eq $ExecutablePath -and $_.MainWindowHandle -ne [IntPtr]::Zero -and $ExcludeIds -notcontains $_.Id
  }).Count -gt 0) {
    Stop-Launcher 3 'Codex/ChatGPT 未能正常关闭旧窗口；为避免意外终止，脚本没有强制结束进程。请先处理旧窗口中的未保存内容后重试。'
  }
}
function Stop-CodexBackgroundProcesses(
  [string]$ExecutablePath,
  [int[]]$ProcessIds,
  [int[]]$ExcludeIds = @()
) {
  foreach ($id in $ProcessIds) {
    if ($ExcludeIds -contains $id) { continue }
    $process = Get-Process -Id $id -ErrorAction SilentlyContinue
    if ($null -eq $process) { continue }
    try {
      if ($process.Path -ne $ExecutablePath) { continue }
      Stop-Process -Id $id -ErrorAction SilentlyContinue
    } catch {
      Write-Verbose "Unable to close old Codex process ${id}: $($_.Exception.Message)"
    }
  }
}
function Set-CodexWindowChrome([string]$SwatchColor, [int]$TimeoutSeconds = 4) {
  try {
    if ($SwatchColor -notmatch '^#[0-9a-fA-F]{6}$') { return }
    if (-not ('CodexSkinDwm' -as [type])) {
      Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class CodexSkinDwm {
  [DllImport("dwmapi.dll", PreserveSig = true)]
  public static extern int DwmSetWindowAttribute(
    IntPtr hwnd,
    int attribute,
    ref uint value,
    int valueSize);
}
'@
    }

    $hex = $SwatchColor.Substring(1)
    $red = [Convert]::ToByte($hex.Substring(0, 2), 16)
    $green = [Convert]::ToByte($hex.Substring(2, 2), 16)
    $blue = [Convert]::ToByte($hex.Substring(4, 2), 16)
    $captionColor = [uint32]($red + ($green * 256) + ($blue * 65536))
    $brightness = (($red * 299) + ($green * 587) + ($blue * 114)) / 1000
    $textColor = if ($brightness -ge 160) { [uint32]0x0033263b } else { [uint32]0x00ffffff }
    $DwmwaBorderColor = 34
    $DwmwaCaptionColor = 35
    $DwmwaTextColor = 36
    $colorSize = [Runtime.InteropServices.Marshal]::SizeOf([uint32])
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)

    while ([DateTime]::UtcNow -lt $deadline) {
      foreach ($process in @(Get-Process -Name 'Codex','ChatGPT' -ErrorAction SilentlyContinue)) {
        $process.Refresh()
        if ($process.MainWindowHandle -eq [IntPtr]::Zero) { continue }
        [void][CodexSkinDwm]::DwmSetWindowAttribute($process.MainWindowHandle, $DwmwaCaptionColor, [ref]$captionColor, $colorSize)
        [void][CodexSkinDwm]::DwmSetWindowAttribute($process.MainWindowHandle, $DwmwaBorderColor, [ref]$captionColor, $colorSize)
        [void][CodexSkinDwm]::DwmSetWindowAttribute($process.MainWindowHandle, $DwmwaTextColor, [ref]$textColor, $colorSize)
        return
      }
      Start-Sleep -Milliseconds 200
    }
  } catch {
    Write-Verbose "Unable to apply Codex window color: $($_.Exception.Message)"
  }
}

function Find-CdpTarget([int]$DebugPort, [int]$TimeoutSeconds) {
  $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
  while ([DateTime]::UtcNow -lt $deadline) {
    try {
      $targets = Invoke-RestMethod -Uri "http://127.0.0.1:$DebugPort/json/list" -TimeoutSec 2
      $pages = @($targets | Where-Object { $_.type -eq 'page' -and $_.webSocketDebuggerUrl })
      $target = @($pages | Where-Object { $_.url -eq 'app://-/index.html' } | Select-Object -First 1)
      if ($target.Count -eq 1) { return $target[0] }
      if ($pages.Count -eq 1) { return $pages[0] }
    } catch {
      # Codex may still be starting; retry until the deadline.
    }
    Start-Sleep -Milliseconds 250
  }
  Stop-Launcher 4 "CDP 在 $TimeoutSeconds 秒内未出现：http://127.0.0.1:$DebugPort/json/list"
}

function Invoke-CdpEvaluate([string]$WebSocketUrl, [string]$Expression) {
  $socket = [System.Net.WebSockets.ClientWebSocket]::new()
  $tokenSource = [System.Threading.CancellationTokenSource]::new()
  try {
    $tokenSource.CancelAfter(5000)
    $socket.ConnectAsync([uri]$WebSocketUrl, $tokenSource.Token).GetAwaiter().GetResult() | Out-Null
    $request = @{ id = 1; method = 'Runtime.evaluate'; params = @{ expression = $Expression; returnByValue = $true; awaitPromise = $false } } | ConvertTo-Json -Compress -Depth 8
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($request)
    $segment = [System.ArraySegment[byte]]::new($bytes)
    $socket.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $tokenSource.Token).GetAwaiter().GetResult() | Out-Null
    do {
      $stream = [System.IO.MemoryStream]::new()
      do {
        $buffer = New-Object byte[] 8192
        $result = $socket.ReceiveAsync([System.ArraySegment[byte]]::new($buffer), $tokenSource.Token).GetAwaiter().GetResult()
        if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
          Stop-Launcher 5 'CDP WebSocket 在返回结果前关闭。'
        }
        $stream.Write($buffer, 0, $result.Count)
      } while (-not $result.EndOfMessage)
      $response = [System.Text.Encoding]::UTF8.GetString($stream.ToArray()) | ConvertFrom-Json
    } while ($response.id -ne 1)
    $errorProperty = $response.PSObject.Properties['error']
    if ($null -ne $errorProperty -and $null -ne $errorProperty.Value) {
      Stop-Launcher 5 "CDP 执行失败：$($errorProperty.Value | ConvertTo-Json -Compress)"
    }
    $resultProperty = $response.PSObject.Properties['result']
    $exceptionDetailsProperty = if ($null -eq $resultProperty -or $null -eq $resultProperty.Value) {
      $null
    } else {
      $resultProperty.Value.PSObject.Properties['exceptionDetails']
    }
    if ($null -ne $exceptionDetailsProperty -and $null -ne $exceptionDetailsProperty.Value) {
      Stop-Launcher 5 "CDP 页面执行异常：$($exceptionDetailsProperty.Value | ConvertTo-Json -Compress -Depth 16)"
    }
    if ($null -eq $resultProperty -or $null -eq $resultProperty.Value) {
      Stop-Launcher 5 'CDP 未返回 Runtime.evaluate 结果。'
    }
    $evaluationResultProperty = $resultProperty.Value.PSObject.Properties['result']
    if ($null -eq $evaluationResultProperty -or $null -eq $evaluationResultProperty.Value) { return $null }
    $valueProperty = $evaluationResultProperty.Value.PSObject.Properties['value']
    if ($null -eq $valueProperty) { return $null }
    return $valueProperty.Value
  } catch [LauncherFailure] {
    throw
  } catch {
    Stop-Launcher 5 "CDP WebSocket 失败：$($_.Exception.Message)"
  } finally {
    if ($socket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
      try { $socket.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, 'done', [System.Threading.CancellationToken]::None).GetAwaiter().GetResult() | Out-Null } catch {}
    }
    $tokenSource.Dispose()
    $socket.Dispose()
  }
}

try {
  $packageRoot = Resolve-SkinPackage $SkinPackage $PSScriptRoot
  if (-not (Test-Path -LiteralPath $packageRoot -PathType Container)) { Stop-Launcher 2 "皮肤包目录不存在：$SkinPackage" }
  $runtime = Join-Path $PSScriptRoot 'runtime'
  foreach ($asset in @('dream-skin.css', 'renderer-inject.js')) {
    if (-not (Test-Path -LiteralPath (Join-Path $runtime $asset) -PathType Leaf)) { Stop-Launcher 5 "缺少启动器资源：$asset" }
  }
  $manifest = Read-JsonFile (Join-Path $packageRoot 'skin.json') 'skin.json'
  if ($manifest.schemaVersion -ne 1 -or $manifest.kind -ne 'dream') { Stop-Launcher 2 'skin.json 必须声明 schemaVersion: 1 和 kind: "dream"' }
  if ([string]::IsNullOrWhiteSpace([string](Get-ManifestValue $manifest 'id')) -or [string]::IsNullOrWhiteSpace([string](Get-ManifestValue $manifest 'name'))) { Stop-Launcher 2 'skin.json 必须包含非空 id 和 name' }
  $swatch = Get-ManifestValue $manifest 'swatchColor'
  if ($swatch -isnot [string] -or $swatch -notmatch '^#[0-9a-fA-F]{6}$') { Stop-Launcher 2 'skin.json 的 swatchColor 必须为 #RRGGBB' }
  $background = Resolve-PackageFile $packageRoot (Get-ManifestValue $manifest 'background') 'background'
  $themePath = Resolve-PackageFile $packageRoot (Get-ManifestValue $manifest 'theme') 'theme'
  $stylePath = Resolve-PackageFile $packageRoot (Get-ManifestValue $manifest 'style') 'style' $true
  $theme = Read-JsonFile $themePath 'theme.json'
  if ([string]::IsNullOrWhiteSpace([string](Get-ManifestValue $theme 'id'))) { Stop-Launcher 2 'theme.json 必须包含非空 id' }
  $appearance = Get-ManifestValue $theme 'appearance'
  if ($appearance -isnot [string] -or $appearance -notin @('system', 'light', 'dark')) { Stop-Launcher 2 'theme.json 的 appearance 必须为 system、light 或 dark。' }
  Sync-CodexThemeForSkin $appearance $manifest.name
  $css = Get-Content -LiteralPath (Join-Path $runtime 'dream-skin.css') -Raw -Encoding UTF8
  $renderer = Get-Content -LiteralPath (Join-Path $runtime 'renderer-inject.js') -Raw -Encoding UTF8
  $extension = if ($null -eq $stylePath) { '' } else { Get-Content -LiteralPath $stylePath -Raw -Encoding UTF8 }
  $resolvedCss = "$css`n$extension"
  $art = "data:$(Get-MimeType $background);base64,$([Convert]::ToBase64String([IO.File]::ReadAllBytes($background)))"
  $themeJson = $theme | ConvertTo-Json -Compress -Depth 32
  $payload = $renderer.Replace('__DREAM_SKIN_CSS_JSON__', ($resolvedCss | ConvertTo-Json -Compress)).Replace('__DREAM_SKIN_ART_JSON__', ($art | ConvertTo-Json -Compress)).Replace('__DREAM_SKIN_THEME_JSON__', $themeJson).Replace('__DREAM_SKIN_VERSION_JSON__', ('standalone-codex-skin-1' | ConvertTo-Json -Compress)).Replace('__DREAM_SKIN_STYLE_REVISION_JSON__', ("standalone-$($theme.id)-$($extension.Length)" | ConvertTo-Json -Compress))
  $executable = Get-CodexExecutable
  $target = $null
  $probePorts = @($Port)
  if ($Port -eq 9222) {
    $probePorts += 9223
  }
  foreach ($candidatePort in $probePorts) {
    try {
      $target = Find-CdpTarget $candidatePort 1
    } catch {
      $target = $null
    }
    if ($null -ne $target) {
      $Port = $candidatePort
      break
    }
  }
  if ($null -eq $target) {
    $existingProcessIds = @(Get-Process -Name 'Codex','ChatGPT' -ErrorAction SilentlyContinue |
      Where-Object { $_.Path -eq $executable } |
      Select-Object -ExpandProperty Id)
    $startupPort = if ($Port -eq 9222) { 9223 } else { $Port }
    Start-Codex $startupPort
    if ($startupPort -ne $Port) {
      $Port = $startupPort
      Write-Host "CDP 端口已切换到 $Port"
    }
    $target = Find-CdpTarget $Port $Timeout
    $newProcessIds = @(Get-Process -Name 'Codex','ChatGPT' -ErrorAction SilentlyContinue |
      Where-Object { $_.Path -eq $executable -and $existingProcessIds -notcontains $_.Id } |
      Select-Object -ExpandProperty Id)
    if ($newProcessIds.Count -eq 0) {
      Stop-Launcher 3 '已打开 CDP 页面但无法识别新启动的 Codex 进程；为避免关闭错误窗口，脚本停止执行。'
    }
    Stop-CodexGracefully $executable -ExcludeIds $newProcessIds
    Stop-CodexBackgroundProcesses $executable $existingProcessIds $newProcessIds
  }
  Set-CodexWindowChrome $swatch
  $nodePath = Get-CodexNodeRuntime $executable
  Invoke-NodeCdpEvaluate $nodePath $target.webSocketDebuggerUrl $payload
  Write-Host "已应用皮肤：$($manifest.name)"
  exit 0
} catch [LauncherFailure] {
  [Console]::Error.WriteLine($_.Exception.Message)
  exit $_.Exception.ExitCode
} catch {
  [Console]::Error.WriteLine($_.Exception.Message)
  exit 5
}
