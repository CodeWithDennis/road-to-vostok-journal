# Stages mod into ./build, then zips ./build -> ./dist/journal.vmz (POSIX paths in ZIP).
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$buildRoot = Join-Path $root 'build'
$distDir = Join-Path $root 'dist'
$distZip = Join-Path $distDir 'journal.vmz'
$srcModsJournal = Join-Path $root 'mods\journal'

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

if (Test-Path $buildRoot) {
    Remove-Item -LiteralPath $buildRoot -Recurse -Force
}
$null = New-Item -ItemType Directory -Path $buildRoot -Force

Copy-Item -LiteralPath (Join-Path $root 'mod.txt') -Destination (Join-Path $buildRoot 'mod.txt')

$buildMods = Join-Path $buildRoot 'mods'
$null = New-Item -ItemType Directory -Path $buildMods -Force
Copy-Item -LiteralPath $srcModsJournal -Destination $buildMods -Recurse -Force

$null = New-Item -ItemType Directory -Path $distDir -Force
if (Test-Path $distZip) {
    Remove-Item -LiteralPath $distZip -Force
}

$resolvedBuild = (Resolve-Path $buildRoot).Path
$zip = [System.IO.Compression.ZipFile]::Open(
    $distZip,
    [System.IO.Compression.ZipArchiveMode]::Create
)
try {
    Get-ChildItem -Path $buildRoot -File -Recurse | ForEach-Object {
        $relative = $_.FullName.Substring($resolvedBuild.Length).TrimStart('\').Replace('\', '/')
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $zip, $_.FullName, $relative
        )
    }
}
finally {
    $zip.Dispose()
}

Write-Host "Wrote $distZip"
