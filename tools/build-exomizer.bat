@echo off
rem Build Exomizer 3.1.2 (sfx packer) with MSVC into tools\exomizer\exomizer.exe.
rem Source: https://bitbucket.org/magli143/exomizer/get/3.1.2.zip unpacked into tools\dl_exomizer
rem (the project offers no Windows binaries any more). Needs Visual Studio 2022 (C++ tools).
setlocal
set T=%~dp0
set B=%T%exomizer
for /d %%d in ("%T%dl_exomizer\magli143-exomizer-*") do set SRC=%%d\src
if not exist "%SRC%\exo_main.c" (echo Exomizer source not found under %T%dl_exomizer & exit /b 1)
call "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat" >NUL || (echo vcvars64.bat not found & exit /b 1)
if not exist "%B%\compat" mkdir "%B%\compat"
rem MSVC has no unistd.h; exomizer only needs isatty/fileno from it
(echo #include ^<io.h^>& echo #include ^<process.h^>) > "%B%\compat\unistd.h"
cd /d "%SRC%"
set CF=/nologo /O2 /W1 /D_CRT_SECURE_NO_WARNINGS /D_CRT_NONSTDC_NO_DEPRECATE /I"%B%\compat"
cl %CF% /Fe"%B%\exoraw.exe" /Fo"%B%\\" match.c search.c exo_raw.c optimal.c output.c buf_io.c chunkpool.c radix.c exo_helper.c exodec.c progress.c exo_util.c vec.c getflag.c log.c buf.c || exit /b 1
cl %CF% /Fe"%B%\b2buf.exe" /Fo"%B%\\" b2buf.c buf.c log.c buf_io.c || exit /b 1
"%B%\exoraw.exe" -q sfxdecr.s -o "%B%\sfxdecr" || exit /b 1
rem b2buf names the C array after its argument: run it on the bare name
pushd "%B%"
.\b2buf.exe sfxdecr > sfxdecr.c || exit /b 1
popd
cl %CF% /I. /Fe"%B%\exomizer.exe" /Fo"%B%\\" match.c search.c exo_main.c optimal.c output.c buf_io.c chunkpool.c radix.c exo_helper.c exodec.c progress.c asm.tab.c lex.yy.c parse.c expr.c pc.c vec.c named_buffer.c map.c desfx.c 6502emu.c exo_util.c areatrace.c "%B%\sfxdecr.c" table.c perf.c getflag.c log.c buf.c || exit /b 1
echo Built %B%\exomizer.exe
