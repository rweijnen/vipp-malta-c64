"""Generate binary assets for the VIPP C64 demo.

Outputs (in build/):
  logo_sprites.bin  24 sprite blocks: per row r, block r*8+s is sprite s.
                    Sprites 1-7 carry the VIPP logo (3 rows x 7), block 0 the
                    '10' (sprite 0: hires, Y-expanded), blocks 8 and 16 unused
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

SPR_ROWS = 3
VIPP_COLS = 7        # VIPP logo: sprites 1-7
BAR_COLS = 2         # of which the first 2 columns hold the bars

# Logo Y range (must match the FLD region in src/main.asm, lines 72..225).
# Y_MAX is the "floor" the logo bounces on, just above the scroller.
Y_MIN, Y_MAX = 82, 160
Y_LEN = 160          # frames per bounce (3.2 s at 50 Hz)
# Logo X range of the left edge (visible area is 24..343, logo is 192 px wide)
X_MIN, X_MAX = 24, 343 - VIPP_COLS * 24 + 1
# The '10' (sprite 0, 24 x 42 on screen) bounces off these edges
TEN_X_MIN, TEN_X_MAX = 24, 344 - 24
TEN_Y_MIN, TEN_Y_MAX = 50, 251 - 42
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


def sprite_bytes(pixel_at):
    """64 bytes of one multicolor sprite; pixel_at(x, line) -> bit pair."""
    out = bytearray()
    for line in range(21):
        for byte in range(3):
            v = 0
            for p in range(4):
                v = (v << 2) | pixel_at(byte * 4 + p, line)
            out.append(v)
    return out + bytes(1)        # pad to 64 bytes


def hires_sprite_bytes(grid):
    """64 bytes of one hires sprite from a 21 x 24 grid of booleans."""
    out = bytearray()
    for row in grid:
        for byte in range(3):
            v = 0
            for p in range(8):
                v = (v << 1) | int(row[byte * 8 + p])
            out.append(v)
    return out + bytes(1)


def convert_logo():
    if not (ASSETS / "vipp_logo.png").exists():
        fail(f"missing {ASSETS / 'vipp_logo.png'}")
    try:
        roles, kind = art.logo_roles(SLANT, cols=VIPP_COLS, bar_cols=BAR_COLS)
        ten = art.hires_ten("impact.ttf", SLANT)
    except (ValueError, OSError) as e:
        fail(str(e))
    if kind != ["bar"] * BAR_COLS + ["letter"] * (VIPP_COLS - BAR_COLS):
        fail(f"expected {BAR_COLS} bar columns followed by letter columns, got {kind}")

    data = bytearray()
    for row in range(SPR_ROWS):
        for spr in range(8):
            if spr == 0:
                if row == 0:
                    data += hires_sprite_bytes(ten)
                else:
                    data += bytes(64)
            else:
                col = spr - 1
                data += sprite_bytes(lambda x, ln: SPRITE_BITS[roles[row * 21 + ln][col * 12 + x]])
    (BUILD / "logo_sprites.bin").write_bytes(data)

    w = VIPP_COLS * 12
    colours = [[None] * w for _ in range(art.LOGO_H)]
    for y in range(art.LOGO_H):
        for x in range(w):
            body = COL_BAR if x // 12 < BAR_COLS else COL_LETTER
            colours[y][x] = {BG: None, LIGHT: COL_LIGHT, OUTLINE: COL_OUTLINE, BODY: body}[roles[y][x]]
    art.render(colours, None, scale=4).save(BUILD / "logo_preview.png")
    print(f"logo: {VIPP_COLS} sprite columns ({BAR_COLS} bars) + 10, {len(data)} bytes")


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


def gen_tables():
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
        f"BAR_COLS = {BAR_COLS}\nVIPP_COLS = {VIPP_COLS}\n"
        f"TEN_X_MIN = {TEN_X_MIN}\nTEN_X_MAX = {TEN_X_MAX}\n"
        f"TEN_Y_MIN = {TEN_Y_MIN}\nTEN_Y_MAX = {TEN_Y_MAX}\n"
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
    convert_logo()
    gen_font()
    gen_tables()
    gen_scrolltext()
    gen_title()
