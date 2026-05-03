# Builds ../journal.vmz (mod.txt + entire mods/journal/, POSIX paths in ZIP).
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$out = Join-Path (Split-Path $root -Parent) 'journal.vmz'
$modFolder = Join-Path $root 'mods\journal'

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (Test-Path $out) {
    Remove-Item -LiteralPath $out -Force
}

$zip = [System.IO.Compression.ZipFile]::Open(
    $out,
    [System.IO.Compression.ZipArchiveMode]::Create
)
try {
    $modTxt = Join-Path $root 'mod.txt'
    [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
        $zip, $modTxt, 'mod.txt'
    )
    Get-ChildItem -Path $modFolder -File -Recurse | ForEach-Object {
        $rel = $_.FullName.Substring($root.Length + 1).Replace('\', '/')
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $zip, $_.FullName, $rel
        )
    }
}
finally {
    $zip.Dispose()
}

Write-Host "Wrote $out"
