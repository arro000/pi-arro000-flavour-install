$ErrorActionPreference = 'Stop'
if ($args.Count -ne 0) { throw 'Usage: install.ps1 (no arguments)' }

function Invoke-Checked($Command, $Arguments) {
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Command failed with exit code $LASTEXITCODE" }
}

$existingFnm = Get-Command fnm.exe -CommandType Application -ErrorAction SilentlyContinue
if ($existingFnm) {
    $fnm = $existingFnm.Source
} else {
    $dir = Join-Path $env:LOCALAPPDATA 'pi-flavour\fnm'
    $fnm = Join-Path $dir 'fnm.exe'
    if (-not (Test-Path -LiteralPath $fnm -PathType Leaf)) {
        $temp = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $temp | Out-Null
        try {
            $zip = Join-Path $temp 'fnm.zip'
            Invoke-WebRequest -UseBasicParsing 'https://github.com/Schniz/fnm/releases/latest/download/fnm-windows.zip' -OutFile $zip
            Expand-Archive -LiteralPath $zip -DestinationPath $temp
            $binary = Get-ChildItem -LiteralPath $temp -Filter fnm.exe -File -Recurse | Select-Object -First 1
            if (-not $binary) { throw 'fnm.exe not found in the release archive' }
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Move-Item -LiteralPath $binary.FullName -Destination $fnm
        } finally {
            Remove-Item -LiteralPath $temp -Recurse -Force
        }
    }
}

$version = Invoke-Checked $fnm @('list-remote') | ForEach-Object {
    if ($_ -match '^(v\d+\.\d+\.\d+)(?:\s|$)') { $Matches[1] }
} | Select-Object -Last 1
if (-not $version) { throw 'Could not resolve the latest stable Node.js release' }
Invoke-Checked $fnm @('install', $version)
Invoke-Checked $fnm @('default', $version)
$node = Invoke-Checked $fnm @('exec', '--using=default', 'node', '-p', 'process.execPath')
$env:Path = "$(Split-Path -Parent $node);$env:Path"
& $node (Join-Path $PSScriptRoot 'installer.mjs') $fnm
exit $LASTEXITCODE
