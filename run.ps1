# Build, then watch the demo in VICE (PAL, cycle exact, with sound)
$ErrorActionPreference = 'Stop'
& "$PSScriptRoot\build.ps1"
& "$PSScriptRoot\tools\vice\GTK3VICE-3.9-win64\bin\x64sc.exe" -pal -autostart "$PSScriptRoot\build\vipp.prg"
