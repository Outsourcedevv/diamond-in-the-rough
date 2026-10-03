param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$ScratchDirectory = (Join-Path $env:TEMP "rough-installer-tests")
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
$fixtureRoot = Join-Path $ScratchDirectory ('installer-tests-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null
$helper = Join-Path $ProjectRoot 'updater\InstallUpdate.ps1'
$windowsPS = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$nativeBytes = [IO.File]::ReadAllBytes((Join-Path $env:SystemRoot 'System32\where.exe'))
$utf8 = New-Object Text.UTF8Encoding($false)
$checks = New-Object Collections.Generic.List[object]
$tokens = $null; $parseErrors = $null
[Management.Automation.Language.Parser]::ParseFile($helper, [ref]$tokens, [ref]$parseErrors) | Out-Null
if ($parseErrors.Count -gt 0) { throw ($parseErrors | Out-String) }

function New-Fixture([string]$Name, [int]$OldBuild = 0) {
    $folder = Join-Path $script:fixtureRoot $Name
    [IO.Directory]::CreateDirectory($folder) | Out-Null
    [IO.File]::WriteAllText((Join-Path $folder 'DiamondInTheRough.exe'), 'original-game-' + $Name, $script:utf8)
    [IO.File]::WriteAllText((Join-Path $folder 'build.json'), ('{"schema":1,"build":' + $OldBuild + '}'), $script:utf8)
    [IO.File]::WriteAllText((Join-Path $folder 'player-save.json'), '{"preserve":true}', $script:utf8)
    return $folder
}
function New-Package([string]$Name, [object[]]$Entries) {
    $zipPath = Join-Path $script:fixtureRoot ($Name + '.zip')
    $stream = [IO.File]::Open($zipPath, [IO.FileMode]::CreateNew)
    $zip = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create, $false)
    try {
        foreach ($item in $Entries) {
            $entry = $zip.CreateEntry($item.name, [IO.Compression.CompressionLevel]::Optimal)
            if ($null -ne $item.PSObject.Properties['attributes']) { $entry.ExternalAttributes = $item.attributes }
            $entryStream = $entry.Open()
            try { $entryStream.Write($item.bytes, 0, $item.bytes.Length) }
            finally { $entryStream.Dispose() }
        }
    }
    finally { $zip.Dispose(); $stream.Dispose() }
    return $zipPath
}
function Entry([string]$Name, [byte[]]$Bytes) { return [pscustomobject]@{name=$Name;bytes=$Bytes} }
function Valid-Entries([int]$Build = 1) {
    return @((Entry 'DiamondInTheRough.exe' $script:nativeBytes),
        (Entry 'build.json' $script:utf8.GetBytes('{"schema":1,"build":' + $Build + ',"version":"0.3.' + $Build + '"}')),
        (Entry 'README.txt' $script:utf8.GetBytes('Disposable updater fixture.')))
}
function Invoke-Fixture([string]$Name, [string]$Folder, [string]$Package, [bool]$ExpectSuccess,
    [string]$HashOverride = '', [int]$ExpectedBuild = 1, [int]$WaitPid = 0) {
    $initialExe = (Get-FileHash -LiteralPath (Join-Path $Folder 'DiamondInTheRough.exe') -Algorithm SHA256).Hash
    $initialManifest = [IO.File]::ReadAllText((Join-Path $Folder 'build.json'))
    $hash = (Get-FileHash -LiteralPath $Package -Algorithm SHA256).Hash
    if ($HashOverride -ne '') { $hash = $HashOverride }
    $resultPath = Join-Path $script:fixtureRoot ($Name + '-result.json')
    $gamePid = $PID
    if ($WaitPid -gt 0) { $gamePid = $WaitPid }
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $script:helper + '"'),
        '-InstallDir', ('"' + $Folder + '"'), '-PackagePath', ('"' + $Package + '"'),
        '-ExpectedSha256', $hash, '-ExpectedBuild', $ExpectedBuild.ToString(), '-GamePid', $gamePid.ToString(),
        '-ResultPath', ('"' + $resultPath + '"'), '-NoRestart')
    if ($WaitPid -le 0) { $arguments += '-NoWait' }
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $process = Start-Process -FilePath $script:windowsPS -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru `
        -RedirectStandardOutput (Join-Path $script:fixtureRoot ($Name + '-stdout.txt')) `
        -RedirectStandardError (Join-Path $script:fixtureRoot ($Name + '-stderr.txt'))
    $stopwatch.Stop()
    if (-not (Test-Path -LiteralPath $resultPath)) { throw "$Name did not produce a result." }
    $result = [IO.File]::ReadAllText($resultPath) | ConvertFrom-Json
    if ([bool]$result.success -ne $ExpectSuccess -or ($process.ExitCode -eq 0) -ne $ExpectSuccess) {
        throw "$Name unexpected result: $($result | ConvertTo-Json -Compress)"
    }
    if ([IO.File]::ReadAllText((Join-Path $Folder 'player-save.json')) -cne '{"preserve":true}') {
        throw "$Name changed player data."
    }
    $currentHash = (Get-FileHash -LiteralPath (Join-Path $Folder 'DiamondInTheRough.exe') -Algorithm SHA256).Hash
    if ($ExpectSuccess) {
        $backupHash = (Get-FileHash -LiteralPath (Join-Path $Folder 'DiamondInTheRough.exe.previous') -Algorithm SHA256).Hash
        if ($backupHash -ne $initialExe -or $currentHash -ne (Get-FileHash -LiteralPath (Join-Path $env:SystemRoot 'System32\where.exe')).Hash) {
            throw "$Name did not install or preserve the original executable."
        }
    }
    elseif ($currentHash -ne $initialExe -or [IO.File]::ReadAllText((Join-Path $Folder 'build.json')) -cne $initialManifest) {
        throw "$Name left a changed installation on failure."
    }
    if (@(Get-ChildItem -LiteralPath $Folder -File | Where-Object Name -Match '\.(update|restore)-').Count -ne 0) {
        throw "$Name left staging files."
    }
    $script:checks.Add([pscustomobject]@{name=$Name;passed=$true;exit_code=$process.ExitCode;rolled_back=$result.rolled_back;message=$result.message;elapsed_ms=$stopwatch.ElapsedMilliseconds})
    return $result
}

$validZip = New-Package 'valid' (Valid-Entries)
$successFolder = New-Fixture 'success'
Invoke-Fixture 'success' $successFolder $validZip $true | Out-Null
Invoke-Fixture 'same-build-rejected' $successFolder $validZip $false | Out-Null
Invoke-Fixture 'wrong-sha256' (New-Fixture 'wrong-sha256') $validZip $false ('0' * 64) | Out-Null
Invoke-Fixture 'manifest-mismatch' (New-Fixture 'manifest-mismatch') $validZip $false '' 2 | Out-Null
$entries = @(Valid-Entries) + (Entry '../escape.exe' $utf8.GetBytes('bad'))
Invoke-Fixture 'zip-slip-rejected' (New-Fixture 'zip-slip') (New-Package 'zip-slip' $entries) $false | Out-Null
$entries = @(Valid-Entries) + (Entry 'DiamondInTheRough.exe:secret' $utf8.GetBytes('bad'))
Invoke-Fixture 'ads-rejected' (New-Fixture 'ads') (New-Package 'ads' $entries) $false | Out-Null
$entries = @(Valid-Entries) + (Entry 'another.exe' $nativeBytes)
Invoke-Fixture 'extra-executable-rejected' (New-Fixture 'extra') (New-Package 'extra' $entries) $false | Out-Null
$entries = @(Valid-Entries) + (Entry 'build.json' $utf8.GetBytes('{"build":1}'))
Invoke-Fixture 'duplicate-rejected' (New-Fixture 'duplicate') (New-Package 'duplicate' $entries) $false | Out-Null
$symlinkType = [int]0xA1FF0000
$entries = @([pscustomobject]@{name='DiamondInTheRough.exe';bytes=$nativeBytes;attributes=$symlinkType},
    (Entry 'build.json' $utf8.GetBytes('{"build":1}')))
Invoke-Fixture 'symlink-rejected' (New-Fixture 'symlink') (New-Package 'symlink' $entries) $false | Out-Null
$entries = @((Entry 'DiamondInTheRough.exe' $utf8.GetBytes('Not an executable')),
    (Entry 'build.json' $utf8.GetBytes('{"build":1}')))
Invoke-Fixture 'invalid-pe-rejected' (New-Fixture 'invalid-pe') (New-Package 'invalid-pe' $entries) $false | Out-Null
$entries = @(Valid-Entries) + (Entry 'README.md' ([byte[]]::new(2MB + 1)))
Invoke-Fixture 'oversized-text-rejected' (New-Fixture 'oversized-text') (New-Package 'oversized-text' $entries) $false | Out-Null
$rollbackFolder = New-Fixture 'rollback'
$readonlyManifest = Join-Path $rollbackFolder 'build.json'
[IO.File]::SetAttributes($readonlyManifest, [IO.FileAttributes]::ReadOnly)
try {
    $rollbackResult = Invoke-Fixture 'rollback-after-exe-swap' $rollbackFolder $validZip $false
    if (-not $rollbackResult.rolled_back) { throw 'Rollback fixture did not exercise executable recovery.' }
}
finally { [IO.File]::SetAttributes($readonlyManifest, [IO.FileAttributes]::Normal) }
$waitProcess = Start-Process -FilePath $windowsPS -ArgumentList @('-NoProfile', '-Command', 'Start-Sleep -Seconds 3') -WindowStyle Hidden -PassThru
Invoke-Fixture 'wait-for-game-exit' (New-Fixture 'wait') $validZip $true '' 1 $waitProcess.Id | Out-Null
$report = [ordered]@{powershell_version=$PSVersionTable.PSVersion.ToString();helper=$helper;fixture_root=$fixtureRoot;checks=$checks.ToArray();passed=$true}
$reportPath = Join-Path $fixtureRoot 'report.json'
[IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 6), $utf8)
Write-Output ($report | ConvertTo-Json -Depth 6)
