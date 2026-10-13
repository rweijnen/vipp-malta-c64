# VIPP Malta 2026 — C64 demo

A small PAL demo for real Commodore 64 hardware (made for the Commodore 64 Ultimate):

- the VIPP logo as 21 multicolor sprites (3 rows × 7), bouncing on a sine/gravity path
- a hires **"10"** for the 10-year anniversary (sprite 0), bouncing off the screen edges on its own path
- **the attack:** when the "10" bumps into the logo, both freeze (the logo trembles) and the "10" recoils back the way it came, just clear of the logo. A laser gun slides in and shoots it three times. The beam is cut exactly at the "10". The "10" then shatters in a multicolor fire explosion: the screen flashes, the logo shakes and glows in the fire colours. Afterwards everything resumes.
- laser and explosion **sound effects** on SID voice 3, which is borrowed from the music's drums the way games did it
- a 2×2 multicolor scroller in an Ocean-style gold gradient, greeting all VIPP members
- music: *Commando* by Rob Hubbard (from HVSC)

## Run it

- **Emulator:** `.\run.ps1` builds the demo and opens it in VICE (PAL, normal speed, with sound).
- **Real C64 / C64 Ultimate:** copy `build\vipp.prg` (or `build\vipp.d64`) to a USB stick and start it from the Ultimate menu. Standard C64s load the `.d64` with `LOAD"*",8,1` and `RUN`.

The machine must be in **PAL** mode. On an NTSC machine the demo shows a message and stops.

## Build

`.\build.ps1` runs `tools\gen_assets.py`, assembles `src\main.asm` with 64tass and writes `build\vipp.prg` and `build\vipp.d64`.

The toolchain lives in `tools\`: 64tass 1.60 and VICE 3.9. You also need Python 3 with Pillow.

Test builds (64tass `-D`):

- `SYNC_TEST=1` repeats the timer sync.
- `MUSIC_DIRECT=1` uses the original music player.
- `SFX_OFF=1` keeps the SID stubs but turns the effects off.
- `DEBUG=1` shows IRQ time in the border.

## Changing things

| What | Where |
|---|---|
| Member names | `assets\members.txt` (one per line) |
| Scroll text around the names, title | `tools\gen_assets.py` (`gen_scrolltext`, `TITLE`) |
| Logo shading / colours | `tools\art.py` (`shade`, `logo_roles`), colours in `tools\gen_assets.py` |
| The "10", explosion, gun | `art.hires_ten`, `art.fire_frames` / `FIRE_COLOURS`, `tools\gun.py` |
| Font glyphs / gradient | `tools\font7.py`, `GOLD` in `tools\art.py` |
| Motion | `Y_MIN`/`Y_MAX`/`Y_LEN`, `X_MIN`/`X_MAX` in `tools\gen_assets.py`, `X_SPEED` in `src\main.asm` |
| Attack timing, shots, recoil | `ATK_*`, `SHOT_LEN`, `SHOTS`, `RECOIL_MIN`, `COOL_FRAMES` in `src\main.asm` |
| Sound effects | `sfx_hi` / `sfx_ctrl` tables and `sfx_*v` per effect in `src\main.asm` |

`tools\preview_art.py` and `tools\preview_ten.py` render option sheets without touching the demo.

## How it works

- **Line 72–225 (FLD area):** one IRQ runs every raster line here.
  - It keeps YSCROLL one line behind the raster, so there are no badlines.
  - It works through a sorted list of events:
    - moving the sprites down for logo rows 2 and 3
    - swapping all 8 sprite pointers with one `$d018` write, which switches between three screens
    - lending sprite 7 to the gun and taking it back
    - drawing the laser beam
- **Laser beam:** CIA 1 timer A is synced to the raster at start-up with a double IRQ (period 63 cycles = one PAL line). One timer read gives the exact cycle. Then "sleds" of `cmp #$c9` bytes wait with single-cycle precision, so the background colour switches on and off exactly at the "10". It also switches only where needed, which avoids the 8565 "grey dot" bug.
- **Line 227–242:** the scroller. Because of the FLD, screen rows 3–4 appear here.
- **Line 245:** music, effects, movement, scrolling and colours, all done in the border area.
- **Sound:** every SID write of the music player goes through a generated stub (`build\music.inc`). The stub writes to the SID straight away, except voice 3 while an effect plays, and keeps a copy so voice 3 can be handed back afterwards.

`tools\vicemon.py` drives VICE through its remote monitor:

- It stops on code or memory writes.
- It takes exact full-frame screenshots and dumps registers/memory.
- It always closes VICE again, and refuses to start while another VICE holds the monitor port.
