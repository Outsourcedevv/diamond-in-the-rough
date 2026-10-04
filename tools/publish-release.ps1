[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')][string]$Repository,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$Commit,
    [Parameter(Mandatory)][ValidateRange(1, 2147483647)][int]$BuildNumber,
    [string]$AssetDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build/release')
)

$ErrorActionPreference = 'Stop'
$manifestPath = Join-Path $AssetDirectory 'latest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.schema -ne 1 -or $manifest.build -ne $BuildNumber -or $manifest.commit -ne $Commit -or $manifest.version -ne "0.3.$BuildNumber" -or $manifest.asset -ne 'DIAMOND_IN_THE_ROUGH_Update.zip' -or $manifest.executable -ne 'DiamondInTheRough.exe') {
    throw 'Release manifest does not identify this workflow revision.'
}
$archivePath = Join-Path $AssetDirectory $manifest.asset
if ((Get-Item -LiteralPath $archivePath).Length -ne $manifest.size -or (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $manifest.sha256) {
    throw 'Transferred ZIP does not match its update manifest.'
}

function Invoke-GitHub([string[]]$Arguments) {
    $result = & gh @Arguments
    if ($LASTEXITCODE -ne 0) { throw "GitHub CLI failed: $($Arguments[0]) $($Arguments[1])" }
    return ($result -join "`n")
}

function Test-StillCurrent {
    $head = Invoke-GitHub @('api', "repos/$Repository/branches/main", '--jq', '.commit.sha')
    if ($head.Trim() -ne $Commit) {
        Write-Host 'A newer main-branch push exists; this build will stay unpublished.'
        return $false
    }
    return $true
}

if (-not (Test-StillCurrent)) { return }
# A rerun of an older workflow must never move Latest backwards.
$latestTag = & gh api "repos/$Repository/releases/latest" --jq '.tag_name' 2>$null
if ($LASTEXITCODE -eq 0 -and $latestTag -match '^build-(\d+)$' -and [long]$Matches[1] -gt $BuildNumber) {
    Write-Host 'A newer numbered build is already published; keeping it as Latest.'
    return
}
$tag = "build-$BuildNumber"
$existingJson = & gh release view $tag --repo $Repository --json isDraft,tagName 2>$null
if ($LASTEXITCODE -eq 0) {
    $existing = ($existingJson -join "`n") | ConvertFrom-Json
    if (-not $existing.isDraft) {
        Write-Host "Build $BuildNumber is already published; its immutable assets remain unchanged."
        return
    }
} else {
    $notesPath = Join-Path $AssetDirectory 'release-notes.md'
    $notes = @"
Windows x64 build **$($manifest.version)** from commit $Commit.

Download ``DIAMOND_IN_THE_ROUGH_Update.zip``, extract it and open ``DiamondInTheRough.exe``. Existing installations can use **Updates** in the main menu. Workshop saves stay in the Windows user-data directory.

The repository is private: your GitHub account must have repository access to download updates. Sign in with GitHub CLI or use the game's read-only session credential option. Credentials are never included in this build.

This build includes the alpine mountain claim, physical equipment purchases, a playable tutorial and a responsive interface. It passed native solo progression, mountain, tutorial and screen-layout integration checks before publishing. Co-op peers should all use this build. ``latest.json`` supplies the version, build number, ZIP size and SHA256 used by the in-game updater.
"@
    [IO.File]::WriteAllText($notesPath, $notes, [Text.UTF8Encoding]::new($false))
    Invoke-GitHub @('release', 'create', $tag, '--repo', $Repository, '--target', $Commit, '--title', "DIAMOND IN THE ROUGH $($manifest.version)", '--notes-file', $notesPath, '--draft') | Write-Host
}
# Drafts are invisible to the game's latest-release request. Upload every asset
# first, then expose the completed release in one publish request.
Invoke-GitHub @('release', 'upload', $tag, $archivePath, $manifestPath, '--repo', $Repository, '--clobber') | Write-Host
if (-not (Test-StillCurrent)) { return }
Invoke-GitHub @('release', 'edit', $tag, '--repo', $Repository, '--draft=false', '--latest') | Write-Host
Write-Host "Published complete build $BuildNumber as Latest."
