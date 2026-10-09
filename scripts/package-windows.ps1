$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
$VersionLine = Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*([^+]+)'
$Version = $VersionLine.Matches[0].Groups[1].Value
$SourceDir = Join-Path $Root 'build\windows\x64\runner\Release'
$OutputDir = Join-Path $Root 'build\releases\windows'
$IssFile = Join-Path $Root 'packaging\windows\fav.iss'

if (-not (Test-Path (Join-Path $SourceDir 'fav.exe'))) {
  throw "Windows release bundle not found; run 'flutter build windows --release' first."
}

$ForbiddenFiles = Get-ChildItem $SourceDir -Recurse -Force | Where-Object {
  $_.Name -eq '__pycache__' -or $_.Name -like '.__*' -or $_.Extension -eq '.pyc'
}
if ($ForbiddenFiles) {
  $Names = ($ForbiddenFiles.FullName -join "`n")
  throw "Refusing to package generated or metadata files:`n$Names"
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$IsccCandidates = @(
  "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
)
$Iscc = $IsccCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $Iscc) {
  throw 'Inno Setup 6 was not found.'
}

& $Iscc "/DAppVersion=$Version" "/DSourceDir=$SourceDir" "/DOutputDir=$OutputDir" $IssFile
if ($LASTEXITCODE -ne 0) {
  throw "Inno Setup failed with exit code $LASTEXITCODE."
}

$Zip = Join-Path $OutputDir "fav-$Version-windows-x64-portable.zip"
Compress-Archive -Path (Join-Path $SourceDir '*') -DestinationPath $Zip -Force
Get-ChildItem $OutputDir -File | Where-Object Name -notlike 'SHA256SUMS*' |
  Get-FileHash -Algorithm SHA256 |
  ForEach-Object { "$($_.Hash.ToLower())  $([IO.Path]::GetFileName($_.Path))" } |
  Set-Content -Encoding ascii (Join-Path $OutputDir 'SHA256SUMS-windows-x64')

Write-Host "Windows packages written to $OutputDir"
