$ErrorActionPreference = 'Stop'

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$scriptPath = Join-Path $repositoryRoot 'apply-windows-skin.ps1'
$runtimeRoot = Join-Path $repositoryRoot 'runtime'

foreach ($asset in @('renderer-inject.js', 'dream-skin.css')) {
  if (-not (Test-Path -LiteralPath (Join-Path $runtimeRoot $asset) -PathType Leaf)) {
    throw "Missing injection runtime asset: runtime/$asset"
  }
}

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw 'apply-windows-skin.ps1 must parse without errors.' }

$functions = @{}
foreach ($name in @('Resolve-PackageFile', 'Resolve-SkinPackage', 'Get-CodexExecutable', 'Stop-CodexGracefully', 'Find-CdpTarget', 'Invoke-CdpEvaluate')) {
  $functionAst = $ast.Find(
    { param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name },
    $true
  )
  if ($null -eq $functionAst) { throw "Missing launcher function: $name" }
  $functions[$name] = $functionAst
}

$source = [System.IO.File]::ReadAllText($scriptPath, [System.Text.Encoding]::UTF8)
foreach ($fragment in @(
  "Get-AppxPackage -Name 'OpenAI.Codex'",
  'app\ChatGPT.exe',
  '--remote-debugging-port=',
  'http://127.0.0.1:',
  'Runtime.evaluate',
  "PSObject.Properties['error']",
  "PSObject.Properties['exceptionDetails']",
  "Join-Path `$PSScriptRoot 'runtime'",
  'CloseMainWindow()',
  'Get-Process -Name ''Codex'',''ChatGPT'''
)) {
  if ($source.IndexOf($fragment, [System.StringComparison]::Ordinal) -lt 0) {
    throw "Launcher is missing required behavior: $fragment"
  }
}
if ($source -match 'Stop-Process\s+-Force') { throw 'Launcher must not force-terminate Codex.' }

function Stop-Launcher([int]$Code, [string]$Message) {
  throw "Launcher failure ${Code}: $Message"
}

. ([scriptblock]::Create($functions['Resolve-PackageFile'].Extent.Text))
. ([scriptblock]::Create($functions['Resolve-SkinPackage'].Extent.Text))

$expectedBuiltInPackage = Join-Path (Join-Path $repositoryRoot 'skins') 'purple-gunner'
$originalLocation = Get-Location
try {
  Set-Location $repositoryRoot
  if ((Resolve-SkinPackage '.\skins\purple-gunner' $repositoryRoot) -ne $expectedBuiltInPackage) {
    throw 'A relative skin directory path must resolve to the same package.'
  }
} finally {
  Set-Location $originalLocation
}
if ((Resolve-SkinPackage 'purple-gunner' $repositoryRoot) -ne $expectedBuiltInPackage) {
  throw 'A bare skin ID must resolve to skins/<id> beside the launcher.'
}

$originalLocation = Get-Location
try {
  Set-Location ([System.IO.Path]::GetTempPath())
  if ((Resolve-SkinPackage 'dragon-liqing' $repositoryRoot) -ne (Join-Path (Join-Path $repositoryRoot 'skins') 'dragon-liqing')) {
    throw 'A bare skin ID must resolve from the launcher root even outside the repository working directory.'
  }
} finally {
  Set-Location $originalLocation
}
$packageRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('codex-skin-test-' + [guid]::NewGuid())
try {
  [void](New-Item -ItemType Directory -Path $packageRoot)
  $background = Join-Path $packageRoot 'background.jpg'
  [System.IO.File]::WriteAllBytes($background, [byte[]](0))

  if ((Resolve-PackageFile $packageRoot 'background.jpg' 'background') -ne $background) {
    throw 'Package-relative skin assets must resolve inside the skin package.'
  }

  $absolutePathRejected = $false
  try { Resolve-PackageFile $packageRoot 'C:\outside\background.jpg' 'background' | Out-Null } catch { $absolutePathRejected = $true }
  if (-not $absolutePathRejected) { throw 'Absolute skin asset paths must be rejected.' }

  Write-Host 'PASS: Windows launcher validates skin paths and declares the required injection flow.'
} finally {
  Remove-Item -LiteralPath $packageRoot -Recurse -Force -ErrorAction SilentlyContinue
}
