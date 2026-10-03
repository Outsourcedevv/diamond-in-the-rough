[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter(Mandatory)][string]$Executable,
    [Parameter(Mandatory)][string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$projectDirectory = [IO.Path]::GetFullPath($ProjectRoot)
$outputDirectoryPath = [IO.Path]::GetFullPath($OutputDirectory)
$executablePath = [IO.Path]::GetFullPath($Executable)
$metadataPath = Join-Path $projectDirectory 'build.json'
$metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
if ($metadata.schema -ne 1 -or $metadata.build -lt 0 -or $metadata.build -ne [Math]::Floor([double]$metadata.build) -or $metadata.commit -notmatch '^[0-9a-f]{40}$' -or $metadata.version -ne "0.3.$($metadata.build)") {
    throw 'Invalid build.json metadata; refusing to package an unidentified update.'
}
if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) { throw 'Windows executable is missing.' }
$stream = [IO.File]::OpenRead($executablePath)
try {
    if ($stream.ReadByte() -ne 77 -or $stream.ReadByte() -ne 90) { throw 'Windows executable does not have an MZ header.' }
} finally {
    $stream.Dispose()
}
New-Item -ItemType Directory -Path $outputDirectoryPath -Force | Out-Null
$stage = Join-Path $outputDirectoryPath ("stage-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage | Out-Null
Copy-Item -LiteralPath $executablePath -Destination (Join-Path $stage 'DiamondInTheRough.exe')
Copy-Item -LiteralPath $metadataPath -Destination (Join-Path $stage 'build.json')
foreach ($name in @('GODOT_LICENSE.txt', 'GODOT_THIRD_PARTY.txt')) {
    Copy-Item -LiteralPath (Join-Path $projectDirectory "licenses/$name") -Destination (Join-Path $stage $name)
}
$playingReadme = @'
DIAMOND IN THE ROUGH - Windows x64

Extract all files into a writable folder and run DiamondInTheRough.exe.
Your workshop saves and settings are stored separately in Windows user data.

WASD/mouse: move/look. E: interact. Right mouse: inspect. Esc: pause.
Hold V: nearby voice. M: mute microphone. Voices stop beyond 12 metres.

Work the mountain scree. The first session teaches the sorting loop in play.
Equipment is sold as physical models: aim at one and press E to buy it.
Names and prices are attached to the displays. How to play replays the guide.
The UI adapts to 4:3, 5:4, widescreen and ultrawide windows.

Use Updates from the main menu to check for a new build and install it.
Because the GitHub repository is private, updates require a GitHub account
with repository access. Sign in using GitHub CLI (gh auth login), or use the
read-only session credential option shown in the game's Updates menu.
Never distribute a repository owner's token with the game.

Updates save your workshop before closing, verify the download, replace
the executable and restart. Quit co-op before updating; peers must use
the same version. Keep the entire extracted folder together.

Source and playing guide:
https://github.com/Outsourcedevv/diamond-in-the-rough

Godot Engine and its third-party license notices are included beside the game.
These notices do not license this game's original source or assets.
'@
[IO.File]::WriteAllText((Join-Path $stage 'README.txt'), $playingReadme, [Text.UTF8Encoding]::new($false))
$assetName = 'DIAMOND_IN_THE_ROUGH_Update.zip'
$archivePath = Join-Path $outputDirectoryPath $assetName
if (Test-Path -LiteralPath $archivePath) { Remove-Item -LiteralPath $archivePath }
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $archivePath, [IO.Compression.CompressionLevel]::Optimal, $false)
$hash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
$manifest = [ordered]@{
    schema = 1
    build = [long]$metadata.build
    commit = [string]$metadata.commit
    version = [string]$metadata.version
    asset = $assetName
    sha256 = $hash
    size = (Get-Item -LiteralPath $archivePath).Length
    executable = 'DiamondInTheRough.exe'
}
[IO.File]::WriteAllText((Join-Path $outputDirectoryPath 'latest.json'), ($manifest | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
Write-Host "Packaged $($manifest.version), build $($manifest.build); ZIP SHA256 $hash"
