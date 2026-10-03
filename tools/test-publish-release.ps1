[CmdletBinding()]
param([Parameter(Mandatory)][string]$ScratchDirectory)

$ErrorActionPreference = 'Stop'
$testDirectory = Join-Path ([IO.Path]::GetFullPath($ScratchDirectory)) ([Guid]::NewGuid().ToString('N'))
$fixtureDirectory = Join-Path $testDirectory 'fixture'
$licenseDirectory = Join-Path $fixtureDirectory 'licenses'
$assetDirectory = Join-Path $testDirectory 'release'
New-Item -ItemType Directory -Path $licenseDirectory -Force | Out-Null
$commit = '0123456789abcdef0123456789abcdef01234567'
[IO.File]::WriteAllText((Join-Path $fixtureDirectory 'build.json'), ('{"schema":1,"build":27,"commit":"' + $commit + '","version":"0.3.27"}'))
foreach ($name in @('GODOT_LICENSE.txt', 'GODOT_THIRD_PARTY.txt')) { [IO.File]::WriteAllText((Join-Path $licenseDirectory $name), $name) }
$fixtureExecutable = Join-Path $fixtureDirectory 'fixture.exe'
[IO.File]::WriteAllBytes($fixtureExecutable, [byte[]]@(77, 90, 0, 1, 2, 3))
& (Join-Path $PSScriptRoot 'package-update.ps1') -ProjectRoot $fixtureDirectory -Executable $fixtureExecutable -OutputDirectory $assetDirectory
$publisher = Join-Path $PSScriptRoot 'publish-release.ps1'

# Stub only GitHub CLI; the real publisher and real manifest/hash checks run.
# This test creates no network requests, repository tags or releases.
$previousGh = Get-Item Function:\gh -ErrorAction SilentlyContinue
function global:gh {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    $key = ($Arguments[0..1] -join ' ')
    $global:PublishReleaseTest.calls.Add($key)
    $global:LASTEXITCODE = 0
    switch ($key) {
        'api repos/fixture/game/branches/main' {
            $global:PublishReleaseTest.headChecks++
            return $(if ($global:PublishReleaseTest.headChecks -eq 1) { $global:PublishReleaseTest.head } else { $global:PublishReleaseTest.finalHead })
        }
        'api repos/fixture/game/releases/latest' { return $global:PublishReleaseTest.latest }
        'release view' {
            if ($global:PublishReleaseTest.existing -eq 'missing') { $global:LASTEXITCODE = 1; return }
            return ('{"isDraft":' + $(if ($global:PublishReleaseTest.existing -eq 'draft') { 'true' } else { 'false' }) + ',"tagName":"build-27"}')
        }
        'release create' { return }
        'release upload' { return }
        'release edit' { return }
        default { throw "Unexpected mocked GitHub CLI invocation: $key" }
    }
}

function Reset-PublishTest([string]$Head = $commit, [string]$Latest = 'build-26', [string]$Existing = 'missing', [string]$FinalHead = $Head) {
    $global:PublishReleaseTest = @{head=$Head; finalHead=$FinalHead; headChecks=0; latest=$Latest; existing=$Existing; calls=[Collections.Generic.List[string]]::new()}
}
function Run-PublishTest {
    & $publisher -Repository 'fixture/game' -Commit $commit -BuildNumber 27 -AssetDirectory $assetDirectory
}
try {
    Reset-PublishTest
    Run-PublishTest
    $expectedCalls = @('api repos/fixture/game/branches/main', 'api repos/fixture/game/releases/latest', 'release view', 'release create', 'release upload', 'api repos/fixture/game/branches/main', 'release edit')
    if (($global:PublishReleaseTest.calls -join '|') -ne ($expectedCalls -join '|')) { throw 'Release was not uploaded as a draft before checking main again and publishing.' }

    Reset-PublishTest -Existing draft
    Run-PublishTest
    if ('release create' -in $global:PublishReleaseTest.calls -or 'release edit' -notin $global:PublishReleaseTest.calls) { throw 'An existing draft was not resumed.' }

    Reset-PublishTest -Existing published
    Run-PublishTest
    if ($global:PublishReleaseTest.calls.Count -ne 3) { throw 'A published release was mutated on rerun.' }

    Reset-PublishTest -Head ('a' * 40)
    Run-PublishTest
    if ($global:PublishReleaseTest.calls.Count -ne 1) { throw 'A stale main-branch revision was published.' }

    Reset-PublishTest -Latest build-99
    Run-PublishTest
    if ($global:PublishReleaseTest.calls.Count -ne 2) { throw 'Latest was allowed to move to a lower build number.' }

    Reset-PublishTest -FinalHead ('a' * 40)
    Run-PublishTest
    if ('release upload' -notin $global:PublishReleaseTest.calls -or 'release edit' -in $global:PublishReleaseTest.calls) { throw 'A revision superseded during asset upload was exposed as Latest.' }

    Reset-PublishTest
    $archive = Join-Path $assetDirectory 'DIAMOND_IN_THE_ROUGH_Update.zip'
    $originalBytes = [IO.File]::ReadAllBytes($archive)
    $tamperedBytes = [byte[]]$originalBytes.Clone()
    $tamperedBytes[0] = $tamperedBytes[0] -bxor 1
    [IO.File]::WriteAllBytes($archive, $tamperedBytes)
    $rejected = $false
    try { Run-PublishTest } catch { $rejected = $true }
    if (-not $rejected -or $global:PublishReleaseTest.calls.Count -ne 0) { throw 'A tampered ZIP reached the release API.' }
    [IO.File]::WriteAllBytes($archive, $originalBytes)
    Write-Host 'Publisher passed: draft-first publication, draft resume, immutable rerun, stale revision and older build rejection, superseded upload kept draft, tampered ZIP rejection before any API request.'
} finally {
    Remove-Item Function:\gh -ErrorAction SilentlyContinue
    if ($null -ne $previousGh) { Set-Item Function:\gh -Value $previousGh.ScriptBlock }
    Remove-Variable -Name PublishReleaseTest -Scope Global -ErrorAction SilentlyContinue
}
