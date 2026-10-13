# VIPP Malta 2026 — C64 demo

A small PAL demo for real Commodore 64 hardware (made for the Commodore 64 Ultimate):

- the VIPP logo as 24 multicolor sprites (3 rows × 8), bouncing on a sine/gravity path
- a 2×2 multicolor scroller in an Ocean-style gold gradient, greeting all VIPP members
- music: *Commando* by Rob Hubbard (from HVSC)

## Run it

- **Emulator:** `.\run.ps1` builds the demo and opens it in VICE (PAL, normal speed, with sound).
- **Real C64 / C64 Ultimate:** copy `build\vipp.prg` (or `build\vipp.d64`) to a USB stick and start it from the Ultimate menu. Standard C64s load the `.d64` with `LOAD"*",8,1` and `RUN`.

The machine must be in **PAL** mode. On an NTSC machine the demo shows a message and stops.

## Build

`.\build.ps1` runs `tools\gen_assets.py`, assembles `src\main.asm` with 64tass and writes `build\vipp.prg` and `build\vipp.d64`.

The toolchain lives in `tools\`: 64tass 1.60 and VICE 3.9. You also need Python 3 with Pillow.

## Changing things

| What | Where |
|---|---|
| Member names | `assets\members.txt` (one per line) |
| Scroll text around the names, title | `tools\gen_assets.py` (`gen_scrolltext`, `TITLE`) |
| Logo shading / colours | `tools\art.py` (`shade`, `logo_roles`), colours in `tools\gen_assets.py` |
| Font glyphs / gradient | `tools\font7.py`, `GOLD` in `tools\art.py` |
| Motion | `Y_MIN`/`Y_MAX`/`Y_LEN`, `X_MIN`/`X_MAX` in `tools\gen_assets.py`, `X_SPEED` in `src\main.asm` |

`tools\preview_art.py` renders option sheets for the logo and font without touching the demo.

## How it works (raster)

- **Line 72–225 (FLD area):** an IRQ runs every raster line and keeps YSCROLL one line behind the raster, so there are no badlines. The sprites are reused for logo rows 2 and 3. Their pointers are swapped by switching `$d018` between three screens that share the same text. That is one register write, early in the line.
- **Line 227–242:** the scroller. Because of the FLD, screen rows 3–4 appear here.
- **Line 245:** music, movement, scrolling and colours, all done in the border area.

`tools\vicemon.py` drives VICE through its remote monitor. It captures exact full frames for testing and always closes VICE again.
