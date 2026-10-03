# DIAMOND IN THE ROUGH: install one verified, explicitly requested Windows update.
# Runs without elevation and does not change machine execution-policy settings.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$InstallDir,
    [Parameter(Mandatory = $true)][string]$PackagePath,
    [Parameter(Mandatory = $true)][string]$ExpectedSha256,
    [Parameter(Mandatory = $true)][ValidateRange(1, 2147483647)][int]$ExpectedBuild,
    [Parameter(Mandatory = $true)][ValidateRange(1, 2147483647)][int]$GamePid,
    [Parameter(Mandatory = $true)][string]$ResultPath,
    # These switches are for disposable installation fixtures in automated tests.
    [switch]$NoRestart,
    [switch]$NoWait
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$exeName = 'DiamondInTheRough.exe'
$manifestName = 'build.json'
$maximumArchiveBytes = 160MB
$maximumExecutableBytes = 140MB
$maximumTextBytes = 2MB
$updateId = [Guid]::NewGuid().ToString('N')
$installRoot = $null
$stagedExe = $null
$stagedManifest = $null
$exeReplaced = $false
$manifestReplaced = $false
$manifestCreated = $false
$restartProcess = $null
$installMutex = $null
$mutexOwned = $false
$phase = 'validation'
$result = [ordered]@{
    success = $false
    build = $ExpectedBuild
    phase = $phase
    message = ''
    rolled_back = $false
    timestamp_utc = [DateTime]::UtcNow.ToString('o')
}

function Assert-AbsolutePath([string]$PathValue, [string]$Label) {
    if ([string]::IsNullOrWhiteSpace($PathValue) -or
        -not [IO.Path]::IsPathRooted($PathValue) -or
        $PathValue -notmatch '\A[A-Za-z]:[\\/]' -or
        $PathValue.StartsWith('\\') -or $PathValue.Contains([char]0)) {
        throw "$Label must be a local absolute path."
    }
    return [IO.Path]::GetFullPath($PathValue)
}

function Assert-NoReparsePoints([string]$PathValue) {
    # Resolve-Path does not resolve every Windows junction, so reject link ancestors.
    $candidate = $PathValue
    while (-not [string]::IsNullOrEmpty($candidate)) {
        if (Test-Path -LiteralPath $candidate) {
            $item = Get-Item -LiteralPath $candidate -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'An update path contains a symbolic link or junction.'
            }
        }
        $parent = [IO.Path]::GetDirectoryName($candidate.TrimEnd('\'))
        if ($parent -eq $candidate) { break }
        $candidate = $parent
    }
}

function Get-InstallFile([string]$Name) {
    if ($Name -match '[\\/:]' -or $Name -eq '.' -or $Name -eq '..') {
        throw 'An installation filename is invalid.'
    }
    $resolved = [IO.Path]::GetFullPath([IO.Path]::Combine($script:installRoot, $Name))
    if (-not [string]::Equals([IO.Path]::GetDirectoryName($resolved),
        $script:installRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'An update target escaped the installation folder.'
    }
    Assert-NoReparsePoints $resolved
    if ((Test-Path -LiteralPath $resolved) -and
        (Get-Item -LiteralPath $resolved -Force).PSIsContainer) {
        throw 'An update target is a directory.'
    }
    return $resolved
}

function Read-BuildManifest([string]$Json, [string]$Label, [int]$MinimumBuild = 1) {
    if ($Json.Length -gt 65536) { throw "$Label is too large." }
    $manifest = ConvertFrom-Json -InputObject $Json
    if ($null -eq $manifest -or $manifest -is [Array] -or
        $null -eq $manifest.PSObject.Properties['build']) {
        throw "$Label must contain an integer build number."
    }
    $buildValue = $manifest.build
    if (($buildValue -isnot [int] -and $buildValue -isnot [long]) -or
        $buildValue -lt $MinimumBuild -or $buildValue -gt 2147483647) {
        throw "$Label contains an invalid integer build number."
    }
    if ($null -ne $manifest.PSObject.Properties['executable'] -and
        $manifest.executable -cne $script:exeName) {
        throw "$Label names an unexpected executable."
    }
    return $manifest
}

function Assert-WindowsExecutable([string]$PathValue) {
    $stream = [IO.File]::OpenRead($PathValue)
    $reader = New-Object IO.BinaryReader($stream)
    try {
        if ($stream.Length -lt 256 -or $reader.ReadUInt16() -ne 0x5A4D) {
            throw 'The update does not contain a Windows executable.'
        }
        $stream.Position = 0x3C
        $peOffset = $reader.ReadInt32()
        if ($peOffset -lt 64 -or $peOffset -gt 1MB -or
            $peOffset -gt ($stream.Length - 24)) {
            throw 'The executable header is invalid.'
        }
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550 -or $reader.ReadUInt16() -ne 0x8664) {
            throw 'The update must contain the 64-bit Windows game.'
        }
    }
    finally { $reader.Dispose(); $stream.Dispose() }
}

function Copy-ZipEntry([IO.Compression.ZipArchiveEntry]$Entry, [string]$Destination) {
    # CreateNew prevents accidental replacement while staging beside the executable.
    $inputStream = $Entry.Open()
    $outputStream = [IO.File]::Open($Destination, [IO.FileMode]::CreateNew,
        [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $inputStream.CopyTo($outputStream); $outputStream.Flush($true) }
    finally { $outputStream.Dispose(); $inputStream.Dispose() }
    if ((Get-Item -LiteralPath $Destination).Length -ne $Entry.Length) {
        throw 'The extracted update has an unexpected size.'
    }
}

function Restore-FromBackup([string]$Name) {
    $target = Get-InstallFile $Name
    $backup = Get-InstallFile ($Name + '.previous')
    if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) {
        throw 'The previous game version could not be found for recovery.'
    }
    $restoreName = $Name + '.restore-' + $script:updateId
    $restorePath = Get-InstallFile $restoreName
    try {
        [IO.File]::Copy($backup, $restorePath, $false)
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            [IO.File]::Replace($restorePath, $target, [Management.Automation.Language.NullString]::Value, $true)
        }
        else { [IO.File]::Move($restorePath, $target) }
    }
    finally {
        $restorePath = Get-InstallFile $restoreName
        if (Test-Path -LiteralPath $restorePath -PathType Leaf) {
            Remove-Item -LiteralPath $restorePath -Force
        }
    }
}

function Write-InstallResult {
    # The result file contains status only: never a GitHub token or audio/user data.
    $destination = Assert-AbsolutePath $script:ResultPath 'ResultPath'
    if ([IO.Path]::GetExtension($destination) -cne '.json') {
        throw 'ResultPath must end in .json.'
    }
    Assert-NoReparsePoints $destination
    $resultDirectory = [IO.Path]::GetDirectoryName($destination)
    [IO.Directory]::CreateDirectory($resultDirectory) | Out-Null
    $temporaryResult = [IO.Path]::Combine($resultDirectory, 'install-result-' + $script:updateId + '.tmp')
    try {
        [IO.File]::WriteAllText($temporaryResult, ($script:result | ConvertTo-Json -Depth 4),
            (New-Object Text.UTF8Encoding($false)))
        Assert-NoReparsePoints $destination
        if (Test-Path -LiteralPath $destination) {
            if ((Get-Item -LiteralPath $destination -Force).PSIsContainer) {
                throw 'ResultPath is a directory.'
            }
            [IO.File]::Replace($temporaryResult, $destination, [Management.Automation.Language.NullString]::Value, $true)
        }
        else { [IO.File]::Move($temporaryResult, $destination) }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryResult -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryResult -Force
        }
    }
}

try {
    if ($NoWait -and -not $NoRestart) { throw 'NoWait is only supported with NoRestart in installation tests.' }
    if ($ExpectedSha256 -notmatch '\A[0-9a-fA-F]{64}\z') { throw 'The update checksum is invalid.' }
    $installRoot = (Assert-AbsolutePath $InstallDir 'InstallDir').TrimEnd('\')
    if (-not (Test-Path -LiteralPath $installRoot -PathType Container) -or
        [IO.Path]::GetPathRoot($installRoot).TrimEnd('\') -eq $installRoot) {
        throw 'The installation folder does not exist or is a drive root.'
    }
    Assert-NoReparsePoints $installRoot
    # Serialize updates for this exact installation folder, including separate game instances.
    $mutexHasher = [Security.Cryptography.SHA256]::Create()
    try {
        $mutexBytes = $mutexHasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($installRoot.ToLowerInvariant()))
        $mutexName = 'Local\DiamondInTheRough_Update_' + [BitConverter]::ToString($mutexBytes).Replace('-', '')
    }
    finally { $mutexHasher.Dispose() }
    $installMutex = New-Object Threading.Mutex($false, $mutexName)
    try { $mutexOwned = $installMutex.WaitOne(0) }
    catch [Threading.AbandonedMutexException] { $mutexOwned = $true }
    if (-not $mutexOwned) { throw 'An update is already running for this installation.' }
    $package = Assert-AbsolutePath $PackagePath 'PackagePath'
    Assert-NoReparsePoints $package
    if (-not (Test-Path -LiteralPath $package -PathType Leaf)) { throw 'The downloaded update could not be found.' }
    if ((Get-Item -LiteralPath $package).Length -gt $maximumArchiveBytes) { throw 'The update archive exceeds the size limit.' }
    # Validate ResultPath before any installation changes.
    $ResultPath = Assert-AbsolutePath $ResultPath 'ResultPath'
    if ([IO.Path]::GetExtension($ResultPath) -cne '.json') { throw 'ResultPath must end in .json.' }
    Assert-NoReparsePoints $ResultPath
    $currentExe = Get-InstallFile $exeName
    $currentManifest = Get-InstallFile $manifestName
    if (-not (Test-Path -LiteralPath $currentExe -PathType Leaf)) { throw 'Run the updater from an installed copy of the game.' }

    # Keep the ZIP open exclusively through validation and extraction (no hash/extraction race).
    Add-Type -AssemblyName System.IO.Compression
    $packageStream = [IO.File]::Open($package, [IO.FileMode]::Open,
        [IO.FileAccess]::Read, [IO.FileShare]::None)
    $zip = $null
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        if ($packageStream.Length -gt $maximumArchiveBytes) { throw 'The update archive exceeds the size limit.' }
        $actualHash = [BitConverter]::ToString($sha.ComputeHash($packageStream)).Replace('-', '').ToLowerInvariant()
        if ($actualHash -cne $ExpectedSha256.ToLowerInvariant()) { throw 'The update checksum did not match. Download the update again.' }
        $packageStream.Position = 0
        $zip = New-Object IO.Compression.ZipArchive($packageStream, [IO.Compression.ZipArchiveMode]::Read, $true)
        $allowedNames = @($exeName, $manifestName, 'README.txt', 'README.md',
            'GODOT_LICENSE.txt', 'GODOT_THIRD_PARTY.txt', 'LICENSE.txt', 'LICENSE.md')
        $entries = @{}
        [long]$uncompressedBytes = 0
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName
            if ($name -match '[\\/:]' -or $name -eq '.' -or $name -eq '..' -or
                $name.Contains([char]0) -or $allowedNames -cnotcontains $name -or $entries.ContainsKey($name)) {
                throw 'The archive contains an unexpected, duplicate, or unsafe path.'
            }
            # Unix type bits identify symlinks, sockets, and device entries. DOS directory/reparse bits also rejected.
            [long]$attributes = [long]$entry.ExternalAttributes -band 0xFFFFFFFFL
            [int]$unixType = [int](($attributes -shr 16) -band 0xF000)
            if (($unixType -ne 0 -and $unixType -ne 0x8000) -or
                ($attributes -band 0x410) -ne 0) {
                throw 'The archive contains a link or non-file entry.'
            }
            $limit = $maximumTextBytes
            if ($name -ceq $exeName) { $limit = $maximumExecutableBytes }
            if ($entry.Length -lt 1 -or $entry.Length -gt $limit) { throw 'An update file exceeds its size limit.' }
            $uncompressedBytes += $entry.Length
            if ($uncompressedBytes -gt $maximumArchiveBytes) { throw 'The extracted update exceeds the size limit.' }
            $entries[$name] = $entry
        }
        if (-not $entries.ContainsKey($exeName) -or -not $entries.ContainsKey($manifestName)) {
            throw 'The update is missing the game or build manifest.'
        }
        $manifestStream = $entries[$manifestName].Open()
        $manifestReader = New-Object IO.StreamReader($manifestStream, [Text.Encoding]::UTF8, $true)
        try { $newManifest = Read-BuildManifest ($manifestReader.ReadToEnd()) 'The update manifest' }
        finally { $manifestReader.Dispose(); $manifestStream.Dispose() }
        if ([int]$newManifest.build -ne $ExpectedBuild) { throw 'The update build number did not match the selected release.' }
        if (Test-Path -LiteralPath $currentManifest -PathType Leaf) {
            if ((Get-Item -LiteralPath $currentManifest).Length -gt 65536) { throw 'The installed manifest is too large.' }
            $oldManifest = Read-BuildManifest ([IO.File]::ReadAllText($currentManifest)) 'The installed manifest' 0
            if ([int]$oldManifest.build -ge $ExpectedBuild) { throw 'The installed game is already this build or newer.' }
        }
        $stagedExe = Get-InstallFile ($exeName + '.update-' + $updateId)
        $stagedManifest = Get-InstallFile ($manifestName + '.update-' + $updateId)
        Copy-ZipEntry $entries[$exeName] $stagedExe
        Copy-ZipEntry $entries[$manifestName] $stagedManifest
        Assert-WindowsExecutable $stagedExe
    }
    finally {
        if ($null -ne $zip) { $zip.Dispose() }
        $sha.Dispose()
        $packageStream.Dispose()
    }

    $phase = 'waiting_for_game'
    if (-not $NoWait) {
        $gameProcess = Get-Process -Id $GamePid -ErrorAction SilentlyContinue
        if ($null -ne $gameProcess) {
            if (-not $gameProcess.WaitForExit(60000)) { throw 'The game did not close within 60 seconds. Close it and try again.' }
            $gameProcess.Dispose()
        }
    }
    $phase = 'installing'
    $currentExe = Get-InstallFile $exeName
    $currentManifest = Get-InstallFile $manifestName
    $exeBackup = Get-InstallFile ($exeName + '.previous')
    $manifestBackup = Get-InstallFile ($manifestName + '.previous')
    # File.Replace is atomic on the installation volume and retains a recoverable previous version.
    [IO.File]::Replace($stagedExe, $currentExe, $exeBackup, $true)
    $stagedExe = $null
    $exeReplaced = $true
    if (Test-Path -LiteralPath $currentManifest -PathType Leaf) {
        [IO.File]::Replace($stagedManifest, $currentManifest, $manifestBackup, $true)
        $manifestReplaced = $true
    }
    else {
        [IO.File]::Move($stagedManifest, $currentManifest)
        $manifestCreated = $true
    }
    $stagedManifest = $null
    $phase = 'restarting'
    if (-not $NoRestart) {
        # The new game's startup can read this status before the helper's smoke check finishes.
        $result.success = $true
        $result.phase = 'installed'
        $result.message = 'Update installed. Starting the game.'
        Write-InstallResult
        $restartProcess = Start-Process -FilePath $currentExe -WorkingDirectory $installRoot -PassThru
        # Catch launch errors or an immediate startup crash. A normal clean quit is allowed.
        if ($restartProcess.WaitForExit(2000) -and $restartProcess.ExitCode -ne 0) {
            throw 'The new game closed with a startup error. The previous version will be restored.'
        }
    }
    $result.success = $true
    $result.phase = 'complete'
    $result.message = 'Update installed successfully.'
}
catch {
    $originalError = $_.Exception.Message
    $result.success = $false
    $result.phase = $phase
    $result.message = $originalError
    if ($exeReplaced -or $manifestReplaced -or $manifestCreated) {
        try {
            if ($null -ne $restartProcess -and -not $restartProcess.HasExited) {
                # Only stop the exact child we just launched to free our replaced executable.
                $restartProcess.Kill()
                $restartProcess.WaitForExit(5000) | Out-Null
            }
            if ($manifestReplaced) { Restore-FromBackup $manifestName }
            elseif ($manifestCreated) {
                $createdManifest = Get-InstallFile $manifestName
                Remove-Item -LiteralPath $createdManifest -Force
            }
            if ($exeReplaced) { Restore-FromBackup $exeName }
            $result.rolled_back = $true
            $result.message += ' The previous version was restored.'
        }
        catch {
            $result.message += ' Recovery could not finish: ' + $_.Exception.Message +
                ' The .previous backup remains in the installation folder.'
        }
    }
}
finally {
    foreach ($stagedPath in @($stagedExe, $stagedManifest)) {
        if (-not [string]::IsNullOrEmpty($stagedPath) -and $null -ne $installRoot) {
            try {
                $safePath = Get-InstallFile ([IO.Path]::GetFileName($stagedPath))
                if (Test-Path -LiteralPath $safePath -PathType Leaf) { Remove-Item -LiteralPath $safePath -Force }
            }
            catch { $result.message += ' Temporary-file cleanup could not finish.' }
        }
    }
    try { Write-InstallResult }
    catch { [Console]::Error.WriteLine('Could not save update status: ' + $_.Exception.Message) }
    if ($null -ne $installMutex) {
        if ($mutexOwned) { $installMutex.ReleaseMutex() }
        $installMutex.Dispose()
    }
}

if (-not $result.success) {
    [Console]::Error.WriteLine($result.message)
    if (-not $NoRestart) {
        try {
            Add-Type -AssemblyName System.Windows.Forms
            [Windows.Forms.MessageBox]::Show($result.message + "`r`n`r`nUpdate status: " + $ResultPath,
                'DIAMOND IN THE ROUGH - Update', [Windows.Forms.MessageBoxButtons]::OK,
                [Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
        catch { }
    }
    exit 1
}
exit 0
