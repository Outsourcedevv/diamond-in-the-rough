[CmdletBinding()]
param([Parameter(Mandatory)][string]$Destination)

$ErrorActionPreference = 'Stop'
$version = '4.6.2-stable'
$editorName = "Godot_v${version}_win64.exe.zip"
$templateName = "Godot_v${version}_export_templates.tpz"
$releaseBase = "https://github.com/godotengine/godot-builds/releases/download/$version"
$editorHash = '14293422efb54b24a51f79d4cb55ab4001ef3d936e064a6c8af32e1f984024be'
$templateHash = '942366dc4e27e7686a99da4d3cfb1b8ae8d3eb9444f6d8217eef16245b599ef2'
$engineDirectory = [IO.Path]::GetFullPath($Destination)
New-Item -ItemType Directory -Path $engineDirectory -Force | Out-Null

function Get-VerifiedArchive([string]$Name, [string]$ExpectedHash) {
    $archivePath = Join-Path $engineDirectory $Name
    Invoke-WebRequest -Uri "$releaseBase/$Name" -OutFile $archivePath
    if ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $ExpectedHash) {
        throw "Official Godot archive checksum did not match: $Name"
    }
    return $archivePath
}

$editorArchive = Get-VerifiedArchive $editorName $editorHash
Expand-Archive -LiteralPath $editorArchive -DestinationPath $engineDirectory -Force

# Portable editor data keeps the engine and its matching templates together.
[IO.File]::WriteAllText((Join-Path $engineDirectory '_sc_'), '')
$templateDirectory = Join-Path $engineDirectory 'editor_data/export_templates/4.6.2.stable'
New-Item -ItemType Directory -Path $templateDirectory -Force | Out-Null
$templateArchive = Get-VerifiedArchive $templateName $templateHash
$zip = [IO.Compression.ZipFile]::OpenRead($templateArchive)
try {
    foreach ($name in @('windows_release_x86_64.exe', 'windows_debug_x86_64.exe', 'version.txt')) {
        $entry = $zip.GetEntry("templates/$name")
        if ($null -eq $entry) { throw "Missing matching Windows template: $name" }
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $templateDirectory $name), $true)
    }
} finally {
    $zip.Dispose()
}
Write-Host 'Installed checksum-verified Godot 4.6.2 and Windows x64 templates.'
