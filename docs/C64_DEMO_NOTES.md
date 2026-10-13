# C64 demo notes — what we learned building the VIPP Malta demo

Everything we found out, got wrong, or verified while building `vipp.prg` (v1–v4). It covers hardware limits, exact timings, the techniques that worked, the bugs we hit and how we tested. The aim is for the next demo to start from here instead of rediscovering it.

Target: **PAL C64**, real hardware: the Commodore 64 Ultimate (FPGA, cycle exact, HDMI). Everything was verified in VICE `x64sc`, which is cycle exact.

---

## 1. Hardware limits that shaped every decision

### Sprites
- **8 sprites per raster line, full stop.** Sprites in the side border still count, because DMA happens whenever Y matches, whatever X is. Every "can we add a…" question came down to this.
  - The VIPP logo used 7 sprites side by side (sprites 1–7), and the "10" used sprite 0. On the logo's lines nothing was free.
  - The laser gun could only exist on lines *without* the logo. That's why the "10" recoils clear of the logo before it is shot.
- Sprite size: 24×21 hires or 12×21 multicolor logical px (2 screen px wide). X/Y-expand doubles the size, not the detail.
- **Multicolor sprite colours:** `%01` = `$d025` (shared), `%10` = `$d027+n` (own), `%11` = `$d026` (shared). So only **one colour per sprite is free**.
  - Design artwork so each sprite column only needs one "own" colour (e.g. the bars in columns 1–2, the letters in 3–7).
  - The shared colours can be animated, which affects every multicolor sprite at once. We used that on purpose: the logo glows in the explosion colours.
- A **single multicolor sprite** (12 logical px wide) is too coarse for anything detailed. A hires "10" in one sprite looked fine, while a multicolor one was unreadable. For small detailed objects, use hires.
- **Priority:** a lower sprite number is drawn in front. Sprite 0 = the object that must be in front.
- **Collisions:** `$d01e` (sprite-sprite) latches until it is read, and reading clears it. Read it once per frame. **Multicolor `%01` pixels do not count** for collisions.
- **Reusing a sprite lower on the screen** (multiplexing): it only restarts after its previous 21 (or 42, expanded) lines are done. The new Y must be written after the old Y compare and before the new one.
  - Pointer/data changes must happen **after the last DMA fetch of the old row and before the first fetch of the new row**.
  - Sprite 0's data is fetched at cycles 58–59 of the *previous* line, sprite 7's at cycles 9–10 of the current line. So the safe window to swap all 8 pointers is about **cycles 11–57 of the first line of the new row**.

### Characters and colours
- **Multicolor chars:** `%01` = `$d022`, `%10` = `$d023`, `%11` = colour RAM. The colour RAM value must be **0–7** with bit 3 set (`| 8`) to enable multicolor. So no greys or light colours from colour RAM, only from `$d022`/`$d023`.
- 4×8 logical px per char (each 2 screen px wide). Our 2×2 font is 8×16 logical px per glyph, so 4 chars per glyph.
- **More shades per glyph:** give the top and bottom char of a 2×2 glyph different colour RAM values. That gave us a 5-shade gradient (white > yellow > orange > red).
- **A charset is 256 chars.** We ran out once (64 glyphs × 4). The fix was to **pack only the glyphs the texts use** (33 here), which freed room for 2 extra chars per glyph for the reflection. The generator fails loudly if the texts need more than fits.
- No drop shadow on the font: a multicolor char has only bg + 3 colours, and all were used.

### Palette
- Real C64 colours are muddy. Orange, brown and red read brown, and blue is dark.
- Preview with **Colodore**, VICE's default and close to the Ultimate's HDMI output, not Pepto, or everything looks worse than it will.
- Colours used successfully:
  - gold font: white / yellow (7) / orange (8) / red (2)
  - logo: light blue (14) with white highlights and blue (6) outline
  - fire: 1 > 7 > 10 > 8 > 2 > 9 > 11 > 12

### Memory map (VIC bank 0, `$0000-$3fff`)

| Range | Use |
|---|---|
| `$0801–$1cff` | code, tables, variables (check with `.cerror code_end > CHARSET`) |
| `$1000–$1fff` | **the VIC sees char ROM here in bank 0**: never put a charset or sprites there (code is fine) |
| `$2000–$27ff` | packed multicolor charset |
| `$2800 / $2c00 / $3000` | three screens (A/B/C): identical text, different sprite pointers |
| `$3400–$3eff` | sprite blocks: logo, "10", explosion frames, gun frames |
| `$3fff` | VIC **idle byte**, shown in idle state (the FLD area): keep it `0` |
| `$5000–$5fc6` | Commando (SID) |
| `$6000–$65ff` | laser beam code, with page-aligned sleds |
| `$6600–$68cf` | SID write stubs (generated) |
| `$6f00` | SID register copy |

Lots of RAM above `$6000` is free. Use it for page-aligned code (sleds) instead of squeezing into the code area.

---

## 2. Timing (PAL) — numbers we measured or relied on

- **312 lines × 63 cycles = 19,656 cycles per frame**, 50 Hz.
- **Text rows:** char row `r` starts on raster line `51 + 8*r` (with YSCROLL=3). Badlines are lines where `(line & 7) == YSCROLL` within lines `$30–$f7` (48–247).
- **On a badline the CPU is stalled from cycle ~12 to 54.** On such a line there's effectively no time for exact writes.
- **Sprite DMA:** each sprite on a line costs ~2 cycles, plus 3 cycles of BA lead. With 8 sprites the CPU has only **~44 of 63 cycles per line**.
  - A per-line loop must stay well under that, or it skips lines.
  - Our first kernel used ~50 cycles per line and lost events, which made the logo break up and the scroller flicker.
- **Polling `$d012` (`cpx $d012 / beq`) has ~7 cycles of jitter.** A colour write right after detecting a new line lands at cycle ~3–15. That's still before the visible area (40-column display starts at cycle ~16–17), so it's fine for writes at the start of a line.
- The **visible area of a line is about cycles 16–55**. One cycle = 8 pixels.
- **The 8565 "grey dot" bug** (newer VIC, emulated by VICE, assume the Ultimate has it):
  - **every write to a colour register** (`$d020–$d02e`) leaves a one-pixel light-grey dot where the beam is at that moment
  - writes in the border are invisible
  - **rule: only write colour registers in the border, and only on lines where the value actually changes**
  - `$d016`, `$d011` and `$d018` are not colour registers, so no dots
- **Bottom IRQ budget:** with music, effects, movement, scrolling and colours it ended around line 16–36 of the next frame. That's fine as long as it finishes before the next raster IRQ (line 72).
  - Verify this: break at the kernel IRQ and check that it **always** starts on its line.

### Measured in this demo
- The double-IRQ stable raster at line 20 put `sync_point` at **line 22, cycle 3**, every time, for all start jitters.
- After the sync, the CIA timer (period 63) read 39 at cycle 46. The timer wrap was at cycles 22/23, outside the read window (~30–50).
- Beam writes were deterministic to the cycle across frames, at cycles 11 / 38 / 11 / 38 / 11 (instruction start, write +3).
- Sprite DMA steal on a line end with sprites 0 and 7 was ~10 cycles; that's just included in the calibrated constants.

---

## 3. Techniques that worked (and how)

### FLD area: no badlines in the middle of the screen
- **Idea:** from line 72 to 225, keep YSCROLL one line **behind** the raster, i.e. `YSCROLL = (line - 1) & 7`, which is the same as 7 ahead. Then no line ever matches, so there are no badlines. The VIC sits in idle state and shows the idle byte at `$3fff` (0 = nothing).
- **First version:** "YSCROLL 4 ahead" was too tight. When the loop ran late (8 sprites on the line), a badline slipped through. That consumed a char row, so the scroller showed the wrong row and flickered. With a lead of 7, a late iteration never matters.
- **Side effect:** the screen rows after the FLD area move down. Line 227 showed **screen row 3**, so the scroller lives in rows 3–4 and the reflection in row 5. This mapping is deterministic.
- **Benefit:** the CPU is never stalled for 40 cycles in the logo area, so sprite multiplexing and beam timing work at **any** Y.

### Event-list raster kernel
- One IRQ runs every line of the FLD area. Each frame, the bottom IRQ builds a **sorted list of events**: line, kind, value.
- The line of the next event is **patched into a `cpx #imm`**, so a line without events costs ~28 cycles.
- Events use an **"at or past"** test, so a skipped line can't lose one. Several events on the same line run back to back, with the time-critical pointer swap first.
- **Event kinds:**
  - swap pointers via `$d018`
  - set sprite Y for the next row
  - lend/return a sprite
  - laser beam
- Events come from two sources: the logo (always 4) and the attack (0–3). They are merged in order.

### Sprite pointer swap via `$d018` (three screens)
- To change all 8 sprite pointers at once, keep **three screens with the same text** but different pointers (`$07f8+`), and switch screens with a single `$d018` write. It's atomic and needs a tiny timing window.
- In the FLD area the VIC is idle and doesn't read the screen, so only screen A needs text.

### Borrowing a sprite on other lines
- On lines **above** the logo, sprite 7 is the gun. It is set up in the bottom IRQ, and a kernel event gives it back to the logo before the logo starts. The event restores X, Y, `$d010` bit, colour, expand bits and pointer.
- On lines **below** the logo, a kernel event lends sprite 7 after the logo's last row. The pointer goes into **screen C**, because C is active by then. The next bottom IRQ undoes it.
- A Y-expanded sprite lasts 42 lines. **It must finish before the IRQ that resets it.** We hit this constraint with the gun near the bottom.

### Cycle-exact colour writes (laser beam cut at the "10")
1. **Stable raster once at start-up:** a double IRQ.
   - The first IRQ sets up the next line's IRQ, then `cli` plus a `nop` slide, leaving 0–1 cycles of jitter.
   - Then `lda $d012 / cmp $d012 / beq +` removes the last cycle.
   - **Verify it:** sync 8 times with different start delays; the result must be the same cycle every time.
2. **Start CIA1 timer A** at that exact moment: latch 62, continuous, so the period is 63 cycles (one PAL line). Its IRQ stays disabled; you only read the counter.
3. **Read the timer** to know the exact cycle in the line. Make sure the read never happens near the timer's wrap point; move the wrap by delaying the start if needed.
4. **Delay with a "sled":**
   - Use `n × $c9` (cmp #imm) followed by `$c5 $ea` (cmp zp).
   - Jump in at byte `k` and it waits `(n+3) - k` cycles with **1-cycle resolution**: entering at an odd offset turns the sled into a different instruction stream.
   - Use a page-aligned sled with a self-modified `jmp` low byte.
   - One timer read syncs; after that, several writes follow at fixed distances, each with its own sled and precomputed `k`.
5. **Minimum distance between two timed writes** (load + jmp + shortest sled + store) is ~13–15 cycles, **plus DMA steals** if a sprite fetch window falls in between.
   - That is why the "10" may not freeze too close to the screen edges: the recoil nudges it inward.
6. **Calibrate empirically:**
   - Break at each write instruction in the VICE monitor and read `LIN`/`CYC` across several events; it must be identical every time.
   - Adjust one constant per step type.
   - Then match pixels in a screenshot: cut cycle = `(x >> 3) + XC`.

### Smooth motion
- **Sine** for horizontal sweep (eases at the ends), **parabola** for a gravity bounce (decelerates at the top, accelerates at the floor). Use **8.8 fixed point** for slow speeds.
- **Recoil = ease-out:** move 1/8 of the remaining distance per frame (at least 1 px), separately in X and Y. That gives a straight line with a fast kick and a smooth stop. Constant speed looked like "running away".
- **Resume without re-colliding:**
  - mirror the bounce phase (`Y_LEN - i`: same height, opposite direction) so the logo moves away from the "10"
  - require a **fresh** contact (the collision bit must be clear for a frame) before the next attack
- Tiny ±1 px "tremble" tables sell the freeze.

### Explosion / art pipeline
- All artwork is **generated in Python** (`tools/art.py`) and previewed as PNG first:
  - logo shading (highlight band, dithered bottom edge, outline and drop shadow, anti-alias dither)
  - font glyph cells
  - explosion heat maps
  - reflection cells
- **Explosion:** the "10" cracks into chunks along jagged lines. The chunks drift apart (still readable), then fly off with gravity and burn out one by one.
  - The heat map (0–3) is mapped to multicolor bit pairs.
  - The palette per frame cools down from white through yellow to ash.
  - The sprite switches to multicolor only during the explosion.
- **Water reflection:**
  - Flip the glyph's 14 lines, take every other one, giving 8 lines (perspective squash).
  - Colour by distance from the waterline, with a checker dither on lower lines.
  - **Ripple:** per-line `$d016` ±1 px, written at the start of each line. It's not a colour register, so no grey dots. Clamp to 0..7.

### Sound effects without stopping the music
- Games borrow one voice. Voice 3 here was the drums (noise waveform), so losing it for a second is natural.
- **Don't** let the player write to a RAM copy of the SID that you copy once per frame:
  - Hubbard's player writes the control register **twice in some frames** (gate off, then the new waveform with gate on) to restart a note.
  - A copy keeps only the last value, so notes lose their attack. The envelope comparison dropped to 0.63.
- **Do this instead:**
  - At build time, replace each SID store in the player (`sta/stx/sty $d4xx[,x|y]`, always 3 bytes) with `jsr` to a generated **write-through stub**.
  - The stub writes to the SID immediately, preserving A, X, Y, flags and write order, except voice 3 while an effect is active. It also keeps a copy, used to hand voice 3 back.
  - Check first that the player never **reads** the SID.
- **Effects:**
  - Start with one row of test bit (`$08`) to reset oscillator and envelope.
  - Laser: pulse wave, fast falling pitch.
  - Explosion: noise, falling pitch, gate off early, long release.
- **Zero the register copy at start-up.** The player never writes some registers (the filter); copying garbage (`$ff`) to `$d417` routed all voices into the filter with no mode set, which made the demo **silent**.

### PAL/NTSC
- Detect via the last raster line before the wrap: `$37` (311) on PAL, `$05/$06` on NTSC. On NTSC, show a clear message and stop.
- Never run with broken timing.

---

## 4. Bugs we hit (and the real cause)

| Symptom | Cause | Fix |
|---|---|---|
| Logo rows misaligned at some Y positions | Pointer swap fell on a badline (CPU stalled) | FLD: no badlines in the logo area |
| Scroller shows the wrong half of the letters / flicker | A badline slipped into the FLD area, consuming a char row | YSCROLL lead 7 (one line behind) |
| Logo broken in 1 of 5 frames, in pairs | Kernel loop ~50 cycles > 44 available, so lines and events were skipped | Event list, self-modified compare, "at or past" |
| Grey single pixels | 8565 grey dot on colour register writes in the visible area | Only write colours in the border, only on change |
| White block from the beam to the scroller | "Beam off" event fell on a skipped line | Beam events in the event list, write at the next line start |
| Beam start/end staircase | Write landed mid-line | Write at the start of the next line, or cycle-exact via timer |
| Demo completely silent | SID copy contained `$ff` in unused filter regs | Zero the copy at start |
| Music articulation changed | RAM copy lost the double gate write per frame | Write-through stubs |
| `place_gun` / `start_explosion` duplicated, code deleted | Patch script anchored on `label` and matched `jsr label` first | Anchor on `\nlabel\n`; keep a backup before big patches |
| "duplicate definition" | **64tass is case-insensitive** by default: `GUN_X` vs `gun_x` | Distinct names (or `-C`) |
| `adc #4` in a heredoc became a newline | Bash heredoc + `\n` escapes mangled Python strings | Write patch scripts to a file |

---

## 5. Tooling and verification (what made it reliable)

- **Toolchain:** 64tass 1.60 (`-B -Wall`), VICE 3.9 (`x64sc`, `c1541`), Python 3 + Pillow for all asset generation.
- **Build fails loudly** on every problem:
  - overlapping memory (`.cerror`)
  - characters missing from the font
  - charset overflow
  - unexpected SID size / store count
  - sprite art outside the grid
- **`tools/vicemon.py`** (VICE remote monitor on port 6510) is the most important test tool:
  - `break exec` or `--watch` (store), `--until ADDR [--until-hits N]`, `--skip`, `--every N`, `--boot S`
  - On each hit it takes an **exact full-frame screenshot**: break on the bottom IRQ, *after* the area you want to see is drawn.
  - It runs extra monitor commands (`r`, `m`, `io d400`).
  - It **always kills VICE**, and refuses to start if port 6510 is in use (a leftover VICE blocked it once).
- **Screenshot pitfalls:**
  - **Never trust `-warp` + `-exitscreenshot`.** Warp skips frames and captures half-drawn frames. It also **mutes sound**, so WAV files come out empty.
  - `-exitscreenshot` without warp still captures mid-frame. Use monitor breakpoints instead.
  - Warp windows appear on the user's screen and look like crazy flicker. Tell them, or avoid.
- **Proof instead of eyeballing:**
  - kernel IRQ start line over hundreds of frames, including during an attack (always 72)
  - write cycles at each timed store (identical every time)
  - frame integrity: count lit scroller lines and logo pixels over 30–60 consecutive frames
  - motion: dump `ten_x`/`ten_y` per frame (cheap, no screenshots)
  - grey dots: search screenshots for isolated light-grey pixels
  - sound: record WAV at normal speed (`-sounddev wav -soundarg file.wav`); compare 20 ms loudness envelopes against a reference build (after aligning the start offset)
- **Targeted captures beat bulk captures.** Break at the event (`plan_attack`, `beam_event`) and capture a few frames. A 1,500-frame screenshot run was slow and found nothing useful.
- **Debug border colours** (`DEBUG=1`): set `$d020` at IRQ entry and reset at exit to see raster time.
- **Test builds via `-D`:**
  - `SYNC_TEST` repeats the sync
  - `MUSIC_DIRECT` uses the original player
  - `SFX_OFF` keeps the stubs without effects
  - `DEBUG`

---

## 6. Working agreements with the user (process lessons)

- **Show visuals as preview images first** (zoomed, real palette) and let the user choose. That covers logo, font, the "10", the explosion, the gun and the reflection. Don't build first.
- **Explain hardware trade-offs before building** (sprite budget, colour limits), with 2–3 concrete options and a recommendation.
- **Discuss designs before building** when asked to, and confirm the interpretation of vague requests ("shoot where it collides", "keep VIPP where it is").
- Commit and tag each milestone (`v1`…`v4`); commit messages without co-author lines.
- Keep the user informed during long runs, and never leave a VICE window stopped in the monitor.

---

## 7. Ideas we didn't do (and why)

- **Bigger sprite-carpet logo** (8×N sprites): possible with the event kernel, but it costs vertical bounce room.
- **Glint sweep over the font** (colour RAM band) and **rolling "molten gold"** (`$d022/$d023` per line, cycle-timed, in the border): both feasible with the techniques above.
- **Opening the side borders:** no characters in the border, and it doesn't add sprites per line.
- **Diagonal/vertical lasers:** they would need per-line timed segments on lines with VIPP events. Possible with the timer technique, but heavy.
