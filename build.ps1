# Build the VIPP demo: assets -> build/vipp_full.prg -> packed build/vipp.prg -> build/vipp.d64
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$tass  = "$PSScriptRoot\tools\64tass\64tass-1.60.3243\64tass.exe"
$c1541 = "$PSScriptRoot\tools\vice\GTK3VICE-3.9-win64\bin\c1541.exe"
$exo   = "$PSScriptRoot\tools\exomizer\exomizer.exe"

# The VIPP Mission mode needs data extracted from your own Impossible Mission
# disk image (never in git): see tools\im\extract.py
foreach ($f in 'agent_sprites.bin', 'charset_rooms.bin', 'robot_sprites.bin') {
    if (-not (Test-Path "assets\im\$f")) {
        throw "assets\im\$f is missing: run tools\im\extract.py on a memory dump of your impossible_mission.d64 first (see README)"
    }
}
foreach ($f in 'rooms.json', 'terminal_screen.bin', 'terminal_colram.bin', 'terminal_sprites.bin', 'terminal.inc', 'search_box.bin', 'speech.bin', 'speech_engine.bin') {
    if (-not (Test-Path "assets\im\$f")) {
        throw "assets\im\$f is missing: run tools\im\extract_rooms.py, extract_terminal.py and extract_search.py on snapshots of your own game (see README)"
    }
}
foreach ($f in 'charset_lift.bin', 'charset_panel.bin', 'lift_panel.bin', 'lift_inner.bin', 'corr_left.bin', 'corr_right.bin', 'lift_sprites.bin', 'lift.inc') {
    if (-not (Test-Path "assets\im\$f")) {
        throw "assets\im\$f is missing: record a lift ride with tools\im\record_lift.py and run tools\im\extract_lift.py (see README)"
    }
}
if (-not (Test-Path $exo)) { throw "Exomizer is missing: build it with tools\build-exomizer.bat (see README)" }

python tools\gen_assets.py
if ($LASTEXITCODE -ne 0) { throw "asset generation failed" }
python tools\im\gen_mission.py
if ($LASTEXITCODE -ne 0) { throw "mission table generation failed" }

& $tass -B -Wall -o build\vipp_full.prg -L build\vipp.lst src\main.asm
if ($LASTEXITCODE -ne 0) { throw "assembly failed" }
# 64tass lets a later section overwrite an earlier one without a word
python tools\check_overlap.py build\vipp.lst
if ($LASTEXITCODE -ne 0) { throw "two parts of the program are assembled at the same address" }

# one self-unpacking file: the full program spans $0801-$b7ff (and more later)
& $exo sfx sys -q -o build\vipp.prg build\vipp_full.prg
if ($LASTEXITCODE -ne 0) { throw "packing with exomizer failed" }

if (Test-Path build\vipp.d64) { Remove-Item build\vipp.d64 }
& $c1541 -format "vipp malta,26" d64 build\vipp.d64 -write build\vipp.prg "vipp malta" | Out-Null
if ($LASTEXITCODE -ne 0) { throw "creating the d64 failed" }

$full = (Get-Item build\vipp_full.prg).Length
$packed = (Get-Item build\vipp.prg).Length
Write-Host "Built build\vipp.prg ($packed bytes packed, $full unpacked) and build\vipp.d64"
