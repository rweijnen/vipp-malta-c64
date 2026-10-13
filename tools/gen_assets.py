"""Generate binary assets for the VIPP C64 demo.

Outputs (in build/):
  logo_sprites.bin  24 multicolor sprites (3 rows x 8 columns), 64 bytes each
  logo_preview.png  how the logo looks on the C64 (for eyeballing)
  font.bin          2x2 multicolor charset (256 chars, Ocean style gold)
  font_preview.png  the font as it will look in the scroller
  bounce_x.bin      256 x-positions (low bytes) of the logo's left edge
  bounce_xhi.bin    256 matching high bits (0/1)
  bounce_y.bin      Y_LEN y-positions (sprite Y of logo row 1)
  tables.inc        constants for main.asm
  scrolltext.bin    screen-code scroll text, terminated with $FF
  title.bin         screen-code title shown in 2x2 chars at the top
"""
import math
import sys

import art
from art import BG, OUTLINE, BODY, LIGHT, ROOT
from font7 import GLYPHS

ASSETS = ROOT / "assets"
BUILD = ROOT / "build"

SPR_COLS, SPR_ROWS = 8, 3

# Logo Y range (must match the FLD region in src/main.asm, lines 72..225).
# Y_MAX is the "floor" the logo bounces on, just above the scroller.
Y_MIN, Y_MAX = 82, 160
Y_LEN = 160          # frames per bounce (3.2 s at 50 Hz)
# Logo X range of the left edge (visible area is 24..343, logo is 192 px wide)
X_MIN, X_MAX = 24, 343 - 192 + 1
# The x table has 256 entries; main.asm steps through it with an 8.8 phase.

SLANT = 0.22         # italic logo: screen px shifted right per line going up

# Logo colours (main.asm sets the registers from tables.inc)
COL_LIGHT = 1        # %01 -> $d025: highlights (white)
COL_OUTLINE = 6      # %11 -> $d026: outline + drop shadow (blue)
COL_BAR = 2          # %10 -> $d027+: body of the bar sprites (red)
COL_LETTER = 14      # %10 -> $d027+: body of the letter sprites (light blue)
SPRITE_BITS = {BG: 0b00, LIGHT: 0b01, BODY: 0b10, OUTLINE: 0b11}

TITLE = "* MALTA 2026 *"


def fail(msg):
    print(f"gen_assets: ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def convert_logo():
    if not (ASSETS / "vipp_logo.png").exists():
        fail(f"missing {ASSETS / 'vipp_logo.png'}")
    try:
        roles, kind = art.logo_roles(SLANT)
    except ValueError as e:
        fail(str(e))
    bars = kind.index("letter") if "letter" in kind else None
    if bars is None or any(k != "bar" for k in kind[:bars]) or any(k != "letter" for k in kind[bars:]):
        fail(f"expected bar columns followed by letter columns, got {kind}")

    data = bytearray()
    for row in range(SPR_ROWS):
        for col in range(SPR_COLS):
            for line in range(21):
                for byte in range(3):
                    v = 0
                    for p in range(4):
                        v = (v << 2) | SPRITE_BITS[roles[row * 21 + line][col * 12 + byte * 4 + p]]
                    data.append(v)
            data.append(0)  # pad to 64 bytes
    (BUILD / "logo_sprites.bin").write_bytes(data)

    colours = [[None] * art.LOGO_W for _ in range(art.LOGO_H)]
    for y in range(art.LOGO_H):
        for x in range(art.LOGO_W):
            r = roles[y][x]
            body = COL_BAR if x // 12 < bars else COL_LETTER
            colours[y][x] = {BG: None, LIGHT: COL_LIGHT, OUTLINE: COL_OUTLINE, BODY: body}[r]
    art.render(colours, None, scale=4).save(BUILD / "logo_preview.png")
    print(f"logo: {bars} bar sprite columns, {len(data)} bytes")
    return bars


def screencode(ch):
    if ch not in GLYPHS:
        fail(f"character {ch!r} is not in the scroller font (tools/font7.py)")
    if "A" <= ch <= "Z":
        return ord(ch) - ord("A") + 1
    if " " <= ch <= "?":
        return ord(ch)
    fail(f"character {ch!r} has no screen code")


def gen_font():
    """Glyph with screen code g becomes chars 4g (top left), 4g+1 (top right),
    4g+2 (bottom left), 4g+3 (bottom right)."""
    data = bytearray(2048)
    for ch, rows in GLYPHS.items():
        g = screencode(ch)
        cell = art.font_cell_bits(rows, art.GOLD)
        for k in range(4):
            x0 = (k & 1) * 4
            y0 = (k >> 1) * 8
            for line in range(8):
                v = 0
                for p in range(4):
                    v = (v << 2) | cell[y0 + line][x0 + p]
                data[(g * 4 + k) * 8 + line] = v
    (BUILD / "font.bin").write_bytes(data)

    # preview: decode the charset back, the way the VIC shows it
    text = "VIPP MALTA 2026 * REMKO WEIJNEN"
    src = {0b01: art.GOLD["c1"], 0b10: art.GOLD["c2"]}
    grid = [[None] * (8 * len(text)) for _ in range(16)]
    for i, ch in enumerate(text):
        g = screencode(ch)
        for k in range(4):
            cram = art.GOLD["T"] if k < 2 else art.GOLD["B"]
            for line in range(8):
                v = data[(g * 4 + k) * 8 + line]
                for p in range(4):
                    bits = (v >> (6 - 2 * p)) & 3
                    if bits:
                        grid[(k >> 1) * 8 + line][i * 8 + (k & 1) * 4 + p] = cram if bits == 3 else src[bits]
    art.render(grid, None, scale=3).save(BUILD / "font_preview.png")
    print(f"font: {len(GLYPHS)} glyphs")


def gen_tables(bar_sprites):
    xs_lo, xs_hi = bytearray(), bytearray()
    for i in range(256):
        t = i / 256 * 2 * math.pi
        x = round(X_MIN + (X_MAX - X_MIN) * (0.5 + 0.5 * math.sin(t)))
        xs_lo.append(x & 0xFF)
        xs_hi.append(x >> 8)
    # Gravity bounce: a parabola from the floor (Y_MAX) up to Y_MIN and back.
    ys = bytearray()
    for i in range(Y_LEN):
        u = 2 * i / Y_LEN - 1                      # -1 .. 1
        ys.append(round(Y_MAX - (Y_MAX - Y_MIN) * (1 - u * u)))
    (BUILD / "bounce_x.bin").write_bytes(xs_lo)
    (BUILD / "bounce_xhi.bin").write_bytes(xs_hi)
    (BUILD / "bounce_y.bin").write_bytes(bytes(ys))
    g = art.GOLD
    (BUILD / "tables.inc").write_text(
        f"Y_LEN = {Y_LEN}\n"
        f"BAR_SPRITES = {bar_sprites}\n"
        f"COL_LIGHT = {COL_LIGHT}\nCOL_OUTLINE = {COL_OUTLINE}\n"
        f"COL_BAR = {COL_BAR}\nCOL_LETTER = {COL_LETTER}\n"
        f"FONT_C1 = {g['c1']}\nFONT_C2 = {g['c2']}\n"
        f"FONT_TOP = {g['T']}\nFONT_BOTTOM = {g['B']}\n")


def gen_scrolltext():
    src = ASSETS / "members.txt"
    if not src.exists():
        fail(f"missing {src}")
    names = [n.strip() for n in src.read_text(encoding="utf-8").splitlines() if n.strip()]
    if not names:
        fail("members.txt is empty")
    text = (
        "      *** PARALLELS VIPP - MALTA 2026 ***   GREETINGS TO ALL VIPP MEMBERS:   "
        + "  *  ".join(names).upper()
        + "   ***   MUSIC: COMMANDO BY ROB HUBBARD   ***   SEE YOU NEXT TIME!      "
    )
    data = bytes(screencode(c) for c in text) + b"\xff"
    (BUILD / "scrolltext.bin").write_bytes(data)
    print(f"scrolltext: {len(names)} names, {len(data)} bytes")


def gen_title():
    data = bytes(screencode(c) for c in TITLE)
    if len(data) * 2 > 40:
        fail(f"title {TITLE!r} too wide for 2x2 font")
    (BUILD / "title.bin").write_bytes(data)


if __name__ == "__main__":
    BUILD.mkdir(exist_ok=True)
    bars = convert_logo()
    gen_font()
    gen_tables(bars)
    gen_scrolltext()
    gen_title()
