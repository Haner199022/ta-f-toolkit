#requires -Version 5.1
<#
.SYNOPSIS
  Sync TA-F toolkit source -> deploy repo -> GitHub Pages.

.DESCRIPTION
  - Copies index.html (this folder) into the deploy repo
  - Rewrites the AI Mesh Maker link from local relative path to deploy subpath
  - Copies the Blender plugin subsite into ./blender-plugin/
  - Commits + pushes if anything changed

.PARAMETER Message
  Commit message. If omitted, a timestamped one is generated.

.PARAMETER DryRun
  Stage files into the deploy repo but skip commit + push.

.EXAMPLE
  .\deploy.ps1
  .\deploy.ps1 -Message "tweak hero copy"
  .\deploy.ps1 -DryRun
#>
[CmdletBinding()]
param(
  [string]$Message,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# Locate git.exe (Git for Windows often isn't on PATH for PowerShell)
$git = (Get-Command git -ErrorAction SilentlyContinue).Source
if (-not $git) {
  foreach ($c in @(
      'C:\Program Files\Git\cmd\git.exe',
      'C:\Program Files (x86)\Git\cmd\git.exe',
      "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe")) {
    if (Test-Path -LiteralPath $c) { $git = $c; break }
  }
}
if (-not $git) { throw 'git.exe not found. Install Git for Windows or add it to PATH.' }

$SrcDir     = 'C:\Users\Administrator\iCloudDrive\iCloud~md~obsidian\Claude Code\Projects\TA-F\website'
$SrcBlender = 'C:\Users\Administrator\iCloudDrive\iCloud~md~obsidian\Claude Code\Projects\TA-F\BLENDER-PLUGIN\website\index.html'

# iCloud File Provider occasionally renames the canonical "index.html" to "index 2.html"
# after conflicting writes. Resolve to whichever exists.
$SrcMain = $null
foreach ($name in @('index.html','index 2.html','index 3.html')) {
  $candidate = Join-Path $SrcDir $name
  if (Test-Path -LiteralPath $candidate) { $SrcMain = $candidate; break }
}
if (-not $SrcMain) { throw "No index*.html found under $SrcDir" }
$Repo       = 'C:\Users\Administrator\projects\ta-f-toolkit'
$LiveURL    = 'https://haner199022.github.io/ta-f-toolkit/'

$LocalLink  = '../BLENDER-PLUGIN/website/index.html'
$DeployLink = './blender-plugin/'

function Step([int]$n, [string]$txt) { Write-Host ("[{0}] {1}" -f $n, $txt) -ForegroundColor Cyan }
function Ok  ([string]$txt)          { Write-Host ("    {0}" -f $txt) -ForegroundColor DarkGray }
function Fail([string]$txt)          { Write-Host ("    {0}" -f $txt) -ForegroundColor Red }

# ----- 0. Sanity ---------------------------------------------------------
foreach ($p in @($SrcMain, $SrcBlender)) {
  if (-not (Test-Path -LiteralPath $p)) { throw "Source missing: $p" }
}
if (-not (Test-Path -LiteralPath (Join-Path $Repo '.git'))) {
  throw "Deploy repo not found or not a git repo: $Repo"
}
if (-not (Test-Path -LiteralPath (Join-Path $Repo '.nojekyll'))) {
  New-Item -ItemType File -Path (Join-Path $Repo '.nojekyll') | Out-Null
  Ok '.nojekyll restored'
}

# ----- 1. Main site (copy + rewrite link) --------------------------------
Step 1 'Copy main site + rewrite Blender link'
$mainContent = Get-Content -LiteralPath $SrcMain -Raw -Encoding UTF8
$rewritten   = $mainContent -replace [regex]::Escape($LocalLink), $DeployLink
if ($rewritten -eq $mainContent) {
  Ok 'No Blender link found to rewrite (source already deploy-ready, or link removed).'
} else {
  Ok ("Rewrote  $LocalLink  ->  $DeployLink")
}
$utf8NoBom  = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $Repo 'index.html'), $rewritten, $utf8NoBom)
Ok ('->  ' + (Join-Path $Repo 'index.html'))

# ----- 2. Blender subsite ------------------------------------------------
Step 2 'Copy Blender subsite'
$blenderDir = Join-Path $Repo 'blender-plugin'
if (-not (Test-Path -LiteralPath $blenderDir)) {
  New-Item -ItemType Directory -Path $blenderDir | Out-Null
}
Copy-Item -LiteralPath $SrcBlender -Destination (Join-Path $blenderDir 'index.html') -Force
Ok ('->  ' + (Join-Path $blenderDir 'index.html'))

# ----- 3. Self-copy: keep deploy.ps1 in repo synced to the source one ----
Step 3 'Copy deploy.ps1 (self)'
Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $Repo 'deploy.ps1') -Force
Ok ('->  ' + (Join-Path $Repo 'deploy.ps1'))

# ----- 4..6. Git ---------------------------------------------------------
Push-Location $Repo
try {
  Step 4 'Check for changes'
  $status = & $git status --porcelain
  if (-not $status) {
    Ok 'Working tree clean. Nothing to deploy.'
    Write-Host ''
    Write-Host ("Live: {0}" -f $LiveURL) -ForegroundColor Green
    return
  }
  $status -split "`n" | ForEach-Object { if ($_.Trim()) { Ok $_.Trim() } }

  if ($DryRun) {
    Write-Host ''
    Write-Host '[dry-run] Files staged into deploy repo. Skipping commit + push.' -ForegroundColor Yellow
    Write-Host ("To finish manually: cd '{0}'; git add -A; git commit -m '...'; git push" -f $Repo)
    return
  }

  if (-not $Message) {
    $Message = 'Deploy: {0:yyyy-MM-dd HH:mm}' -f (Get-Date)
  }

  Step 5 ('Commit  "' + $Message + '"')
  & $git add -A
  if ($LASTEXITCODE -ne 0) { throw "git add failed (exit $LASTEXITCODE)" }
  & $git commit -m $Message
  if ($LASTEXITCODE -ne 0) { throw "git commit failed (exit $LASTEXITCODE)" }

  Step 6 'Push to GitHub'
  & $git push
  if ($LASTEXITCODE -ne 0) { throw "git push failed (exit $LASTEXITCODE)" }
}
finally {
  Pop-Location
}

Write-Host ''
Write-Host '=== Deployed ===' -ForegroundColor Green
Write-Host ("Live:  {0}" -f $LiveURL)
Write-Host 'Pages rebuild typically completes in 30-60 seconds.'
