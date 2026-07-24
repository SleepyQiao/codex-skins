$ErrorActionPreference = 'Stop'

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$scriptPath = Join-Path $repositoryRoot 'apply-windows-skin.ps1'
$helperPath = Join-Path $repositoryRoot 'runtime\apply-skin.cjs'
$source = [System.IO.File]::ReadAllText($scriptPath, [System.Text.Encoding]::UTF8)

if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) {
  throw 'Windows launcher must include the internal-Node CDP helper.'
}
foreach ($fragment in @(
  'resources\cua_node\bin\node.exe',
  'runtime\apply-skin.cjs',
  "--platform' 'windows",
  'Get-CodexNodeRuntime',
  'Invoke-NodeCdpEvaluate',
  'WebSocket'
)) {
  if ($source.IndexOf($fragment, [System.StringComparison]::Ordinal) -lt 0) {
    throw "Windows launcher is missing internal-Node behavior: $fragment"
  }
}
if ($source -notmatch 'Invoke-NodeCdpEvaluate\s+\$nodePath') {
  throw 'Windows launcher must invoke the internal Node helper after discovering the CDP target.'
}

$helper = [System.IO.File]::ReadAllText($helperPath, [System.Text.Encoding]::UTF8)
foreach ($fragment in @('new WebSocket', 'Runtime.evaluate', '--expression-file')) {
  if ($helper.IndexOf($fragment, [System.StringComparison]::Ordinal) -lt 0) {
    throw "Internal-Node helper is missing: $fragment"
  }
}
if ($helper -match 'kill\s*\(\s*-9') { throw 'Internal-Node helper must not force-terminate Codex.' }

Write-Host 'PASS: Windows launcher uses the desktop-bundled Node runtime for CDP evaluation.'
