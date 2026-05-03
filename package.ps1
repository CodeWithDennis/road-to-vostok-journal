# Writes dist/journal.vmz with Metro layout: mod.txt at archive root,
# GDScript under mods/journal/ (matches res:// paths in mod.txt and preloads).
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$distDir = Join-Path $root 'dist'
$distZip = Join-Path $distDir 'journal.vmz'
$srcDir = Join-Path $root 'src'

if (-not (Test-Path $srcDir)) {
    throw "Missing folder: $srcDir"
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$null = New-Item -ItemType Directory -Path $distDir -Force
if (Test-Path $distZip) {
    Remove-Item -LiteralPath $distZip -Force
}

$modTxt = Join-Path $root 'mod.txt'
if (-not (Test-Path $modTxt)) {
    throw "Missing mod.txt at repo root."
}

$resolvedSrc = ((Resolve-Path $srcDir).Path).TrimEnd('\')
$zip = [System.IO.Compression.ZipFile]::Open(
    $distZip,
    [System.IO.Compression.ZipArchiveMode]::Create
)
try {
    [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $modTxt, 'mod.txt')

    Get-ChildItem -Path $srcDir -File -Recurse | ForEach-Object {
        $rel = $_.FullName.Substring($resolvedSrc.Length).TrimStart('\').Replace('\', '/')
        $entryName = "mods/journal/$rel"
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $zip,
            $_.FullName,
            $entryName
        )
    }
}
finally {
    $zip.Dispose()
}

Write-Host "Wrote $distZip"
