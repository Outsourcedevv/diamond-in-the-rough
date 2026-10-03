[CmdletBinding()]
param([Parameter(Mandatory)][string]$ScratchDirectory)

$ErrorActionPreference = 'Stop'
$testDirectory = Join-Path ([IO.Path]::GetFullPath($ScratchDirectory)) ([Guid]::NewGuid().ToString('N'))
$fixtureDirectory = Join-Path $testDirectory 'fixture'
$licenseDirectory = Join-Path $fixtureDirectory 'licenses'
$releaseDirectory = Join-Path $testDirectory 'release'
New-Item -ItemType Directory -Path $licenseDirectory -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $fixtureDirectory 'build.json'), '{"schema":1,"build":27,"commit":"0123456789abcdef0123456789abcdef01234567","version":"0.3.27"}')
foreach ($name in @('GODOT_LICENSE.txt', 'GODOT_THIRD_PARTY.txt')) {
    [IO.File]::WriteAllText((Join-Path $licenseDirectory $name), "Package test notice: $name")
}
$fixtureExecutable = Join-Path $fixtureDirectory 'fixture.exe'
[IO.File]::WriteAllBytes($fixtureExecutable, [byte[]]@(77, 90, 0, 1, 2, 3, 4, 5))
& (Join-Path $PSScriptRoot 'package-update.ps1') -ProjectRoot $fixtureDirectory -Executable $fixtureExecutable -OutputDirectory $releaseDirectory
$manifest = Get-Content -LiteralPath (Join-Path $releaseDirectory 'latest.json') -Raw | ConvertFrom-Json
$archivePath = Join-Path $releaseDirectory 'DIAMOND_IN_THE_ROUGH_Update.zip'
if ($manifest.build -ne 27 -or $manifest.version -ne '0.3.27' -or $manifest.size -ne (Get-Item -LiteralPath $archivePath).Length -or $manifest.sha256 -ne (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()) {
    throw 'Package manifest metadata, size or digest did not match the ZIP.'
}
$zip = [IO.Compression.ZipFile]::OpenRead($archivePath)
try {
    $actualNames = @($zip.Entries.FullName | Sort-Object)
    $expectedNames = @('DiamondInTheRough.exe', 'build.json', 'GODOT_LICENSE.txt', 'GODOT_THIRD_PARTY.txt', 'README.txt') | Sort-Object
    if (Compare-Object $expectedNames $actualNames) { throw 'Package did not contain exactly the five allowed flat files.' }
    $reader = [IO.StreamReader]::new($zip.GetEntry('build.json').Open())
    try { $zippedMetadata = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
    if ($zippedMetadata.commit -ne $manifest.commit -or $zippedMetadata.build -ne $manifest.build) { throw 'Packaged metadata differs from manifest metadata.' }
} finally {
    $zip.Dispose()
}

# Packaging must fail closed when metadata or the supposed EXE is malformed.
[IO.File]::WriteAllText((Join-Path $fixtureDirectory 'build.json'), '{"schema":1,"build":27,"commit":"not-a-commit","version":"0.3.27"}')
$rejected = $false
try { & (Join-Path $PSScriptRoot 'package-update.ps1') -ProjectRoot $fixtureDirectory -Executable $fixtureExecutable -OutputDirectory $releaseDirectory } catch { $rejected = $true }
if (-not $rejected) { throw 'Malformed build identity was packaged.' }
[IO.File]::WriteAllText((Join-Path $fixtureDirectory 'build.json'), '{"schema":1,"build":27,"commit":"0123456789abcdef0123456789abcdef01234567","version":"0.3.27"}')
[IO.File]::WriteAllBytes($fixtureExecutable, [byte[]]@(0, 0, 0, 1))
$rejected = $false
try { & (Join-Path $PSScriptRoot 'package-update.ps1') -ProjectRoot $fixtureDirectory -Executable $fixtureExecutable -OutputDirectory $releaseDirectory } catch { $rejected = $true }
if (-not $rejected) { throw 'Invalid executable header was packaged.' }
Write-Host 'Package tooling passed: exact flat contents, matching build identity, size/SHA256, invalid metadata rejection and invalid executable rejection.'
