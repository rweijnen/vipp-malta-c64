# Build the VIPP demo: assets -> build/vipp.prg -> build/vipp.d64
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$tass  = "$PSScriptRoot\tools\64tass\64tass-1.60.3243\64tass.exe"
$c1541 = "$PSScriptRoot\tools\vice\GTK3VICE-3.9-win64\bin\c1541.exe"

python tools\gen_assets.py
if ($LASTEXITCODE -ne 0) { throw "asset generation failed" }

& $tass -B -Wall -o build\vipp.prg -L build\vipp.lst src\main.asm
if ($LASTEXITCODE -ne 0) { throw "assembly failed" }

if (Test-Path build\vipp.d64) { Remove-Item build\vipp.d64 }
& $c1541 -format "vipp malta,26" d64 build\vipp.d64 -write build\vipp.prg "vipp malta" | Out-Null
if ($LASTEXITCODE -ne 0) { throw "creating the d64 failed" }

Write-Host "Built build\vipp.prg and build\vipp.d64"
