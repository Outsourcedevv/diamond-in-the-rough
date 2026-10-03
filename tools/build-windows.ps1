[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Godot,
    [Parameter(Mandatory)][ValidateRange(1, 2147483647)][int]$BuildNumber,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$Commit,
    [switch]$SkipVerification
)

$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$enginePath = [IO.Path]::GetFullPath($Godot)
$buildDirectory = Join-Path $projectDirectory 'build'
New-Item -ItemType Directory -Path $buildDirectory -Force | Out-Null
$metadata = [ordered]@{schema = 1; build = $BuildNumber; commit = $Commit; version = "0.3.$BuildNumber"}
[IO.File]::WriteAllText((Join-Path $projectDirectory 'build.json'), ($metadata | ConvertTo-Json), [Text.UTF8Encoding]::new($false))

# Stamp Windows file properties without committing generated metadata or an EXE.
$presetPath = Join-Path $projectDirectory 'export_presets.cfg'
$presets = [IO.File]::ReadAllText($presetPath)
$fileVersion = "0.3.$([Math]::Floor($BuildNumber / 65536)).$($BuildNumber % 65536)"
$presets = [regex]::Replace($presets, '(application/(?:file|product)_version=")[^"]+("\s*)', ('${1}' + $fileVersion + '${2}'))
[IO.File]::WriteAllText($presetPath, $presets, [Text.UTF8Encoding]::new($false))

function Invoke-Engine([string[]]$Arguments, [string]$LogName) {
    $logPath = Join-Path $buildDirectory $LogName
    & $enginePath @Arguments --log-file $logPath
    if ($LASTEXITCODE -ne 0) { throw "Godot failed ($LASTEXITCODE); see $LogName." }
    if ((Test-Path -LiteralPath $logPath) -and (Select-String -LiteralPath $logPath -Pattern 'SCRIPT ERROR:|Parse Error:|Failed to load script' -Quiet)) {
        throw "Godot reported a script error; see $LogName."
    }
}

Invoke-Engine @('--headless', '--editor', '--path', $projectDirectory, '--quit') 'import.log'
Invoke-Engine @('--headless', '--path', $projectDirectory, '--check-only', '--script', 'game/main.gd') 'scripts.log'
$executable = Join-Path $buildDirectory 'DiamondInTheRough.exe'
Invoke-Engine @('--headless', '--path', $projectDirectory, '--export-release', 'Windows Desktop', $executable) 'export.log'

if (-not $SkipVerification) {
    $reportDirectory = Join-Path $buildDirectory 'verification'
    New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
    $logPath = Join-Path $buildDirectory 'solo-verification.log'
    # Native Windows binary, deterministic dummy renderer, isolated test saves.
    $process = Start-Process -FilePath $executable -ArgumentList @('--headless', '--log-file', ('"' + $logPath + '"'), '--', '--verify=solo', ('"--report-dir=' + $reportDirectory.Replace('\', '/') + '"')) -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(180000)) {
        Stop-Process -Id $process.Id -Force
        throw 'Native solo verification exceeded its three-minute limit.'
    }
    if ($process.ExitCode -ne 0) { throw "Native solo verification failed ($($process.ExitCode))." }
    $report = Get-Content -LiteralPath (Join-Path $reportDirectory 'solo_report.json') -Raw | ConvertFrom-Json
    if ($report.phase -ne 'complete' -or $report.errors.Count -ne 0 -or $report.checks.Count -lt 74) {
        throw 'Native solo report was incomplete or failed; update will not be published.'
    }
    Write-Host "Native solo verification passed $($report.checks.Count) checks."
    $redesignDirectory = Join-Path $buildDirectory 'redesign-verification'
    New-Item -ItemType Directory -Path $redesignDirectory -Force | Out-Null
    $redesignLog = Join-Path $buildDirectory 'redesign-verification.log'
    $redesignProcess = Start-Process -FilePath $executable -ArgumentList @('--headless', '--log-file', ('"' + $redesignLog + '"'), '--', '--verify-redesign', ('"--report-dir=' + $redesignDirectory.Replace('\', '/') + '"')) -WindowStyle Hidden -PassThru
    if (-not $redesignProcess.WaitForExit(180000)) {
        Stop-Process -Id $redesignProcess.Id -Force
        throw 'Native tutorial and screen-layout verification exceeded its three-minute limit.'
    }
    if ($redesignProcess.ExitCode -ne 0) { throw "Native redesign verification failed ($($redesignProcess.ExitCode))." }
    $redesignReport = Get-Content -LiteralPath (Join-Path $redesignDirectory 'redesign_report.json') -Raw | ConvertFrom-Json
    if ($redesignReport.phase -ne 'complete' -or $redesignReport.errors.Count -ne 0 -or $redesignReport.checks.Count -lt 97) {
        throw 'Native tutorial and screen-layout report was incomplete or failed; update will not be published.'
    }
    Write-Host "Native tutorial and screen-layout verification passed $($redesignReport.checks.Count) checks."
}
& (Join-Path $PSScriptRoot 'package-update.ps1') -ProjectRoot $projectDirectory -Executable $executable -OutputDirectory (Join-Path $buildDirectory 'release')
