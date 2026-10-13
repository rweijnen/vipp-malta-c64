"""Pixel-art helpers for the VIPP demo: C64 palette, shaded multicolor logo and
multicolor 2x2 font. Everything works on 'logical' multicolor pixels, which
are 2 screen pixels wide and 1 line tall.

Used by preview_art.py (option sheets) and later by gen_assets.py.
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops

ROOT = Path(__file__).resolve().parent.parent

# Pepto's C64 palette
PAL = [(0x00, 0x00, 0x00), (0xFF, 0xFF, 0xFF), (0x68, 0x37, 0x2B), (0x70, 0xA4, 0xB2),
       (0x6F, 0x3D, 0x86), (0x58, 0x8D, 0x43), (0x35, 0x28, 0x79), (0xB8, 0xC7, 0x6F),
       (0x6F, 0x4F, 0x25), (0x43, 0x39, 0x00), (0x9A, 0x67, 0x59), (0x44, 0x44, 0x44),
       (0x6C, 0x6C, 0x6C), (0x9A, 0xD2, 0x84), (0x6C, 0x5E, 0xB5), (0x95, 0x95, 0x95)]

# roles of a shaded pixel
BG, OUTLINE, BODY, LIGHT = 0, 1, 2, 3


def coverage(mask, w, h):
    """Downsample an 'L' mask to w x h coverage values 0..1 (box filter)."""
    small = mask.resize((w, h), Image.BOX)
    px = small.load()
    return [[px[x, y] / 255 for x in range(w)] for y in range(h)]


def skew(mask, amount):
    """Italic slant: the top moves right by amount * height pixels."""
    w, h = mask.size
    extra = int(math.ceil(amount * h))
    return mask.transform((w + extra, h), Image.AFFINE, (1, amount, -extra, 0, 1, 0), Image.BILINEAR)


def shade(cov, light_rows=2, dither_rows=2, shadow=(1, 2), aa=True):
    """Turn coverage into roles, the way a pixel artist shades a logo:
    1px outline + drop shadow in the dark colour, a highlight band along the
    top/left inner edge fading into the body with a checker dither, a dithered
    dark rim on the bottom/right inner edge, and dithered anti-aliasing where
    the shape only partly covers a pixel."""
    h, w = len(cov), len(cov[0])
    inside = [[cov[y][x] >= 0.5 for x in range(w)] for y in range(h)]

    def ins(x, y):
        return 0 <= x < w and 0 <= y < h and inside[y][x]

    roles = [[BG] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            if not inside[y][x]:
                continue
            # distance to the edge going up / left (light comes from top-left)
            up = next((d for d in range(1, 8) if not ins(x, y - d)), 8)
            left = next((d for d in range(1, 4) if not ins(x - d, y)), 4)
            down = next((d for d in range(1, 4) if not ins(x, y + d)), 4)
            right = next((d for d in range(1, 3) if not ins(x + d, y)), 3)
            checker = (x + y) & 1
            r = BODY
            if up <= light_rows or left == 1:
                r = LIGHT
            elif up <= light_rows + dither_rows:
                r = LIGHT if checker else BODY
            if down == 1 and r != LIGHT:
                r = OUTLINE if checker else BODY      # soft dithered shadow at the bottom
            roles[y][x] = r
    # outline and drop shadow around the shape
    for y in range(h):
        for x in range(w):
            if inside[y][x]:
                continue
            near = any(ins(x + dx, y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1))
            sh = any(ins(x - shadow[0] + dx, y - shadow[1] + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1))
            if near or sh:
                roles[y][x] = OUTLINE
            elif aa and cov[y][x] >= 0.2:
                roles[y][x] = OUTLINE if (x + y) & 1 else BG
    # no stray black pixels squeezed between two shapes (e.g. the bar gap)
    for y in range(h):
        for x in range(1, w - 1):
            if roles[y][x] == BG and roles[y][x - 1] != BG and roles[y][x + 1] != BG:
                roles[y][x] = OUTLINE
    return roles


def render(grid, colors, scale=4, wide=2):
    """grid of C64 colour indices (or None = black) -> zoomed RGB image."""
    h, w = len(grid), len(grid[0])
    im = Image.new("RGB", (w * wide, h))
    px = im.load()
    for y in range(h):
        for x in range(w):
            c = PAL[grid[y][x] or 0]
            for k in range(wide):
                px[x * wide + k, y] = c
    return im.resize((w * wide * scale, h * scale), Image.NEAREST)


def logo_masks():
    """Red-bar and letter masks of the source logo, cropped to the content."""
    im = Image.open(ROOT / "assets/vipp_logo.png").convert("RGBA")
    red = Image.new("L", im.size, 0)
    txt = Image.new("L", im.size, 0)
    px, rp, tp = im.load(), red.load(), txt.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a < 128 or r + g + b < 40:
                continue
            if r > 100 and r > g + 60:
                rp[x, y] = 255
            elif b > r + 15:
                tp[x, y] = 255
    return red.crop(red.getbbox()), txt.crop(txt.getbbox())


def fit_logical(mask, max_w, max_h, slant):
    """Scale a source mask (square pixels) so that, after slanting, it fits
    max_w logical px (2 screen px each) by max_h lines. Returns coverage."""
    sw, sh = mask.size
    for h in range(max_h, 8, -1):
        scale = h / sh
        big = mask.resize((max(1, round(sw * scale * 8)), h * 8), Image.LANCZOS)
        if slant:
            big = skew(big, slant)
        w_screen = big.size[0] / 8
        w_log = math.ceil(w_screen / 2)
        if w_log <= max_w:
            return coverage(big, w_log, h)
    raise ValueError("mask does not fit")


# --- logo (8 x 3 multicolor sprites) -----------------------------------------
LOGO_W, LOGO_H = 96, 63      # logical px
BAR_W = 24                   # sprite columns 0-1 hold the bars, 2-7 the letters


def logo_roles(slant, cols=8, bar_cols=2, squeeze_bars=False):
    """The shaded VIPP logo as roles (BG/OUTLINE/BODY/LIGHT) on a grid of
    cols x 3 sprites (12 x 21 logical px each), bars in the first bar_cols
    sprite columns. Also returns, per sprite column, 'bar' or 'letter'."""
    LOGO_W, BAR_W = cols * 12, bar_cols * 12
    red, txt = logo_masks()
    tallest = max(red.size[1], txt.size[1])
    tc = fit_logical(txt, LOGO_W - BAR_W - 3, (LOGO_H - 4) * txt.size[1] // tallest, slant)
    th = len(tc)
    bh = round(th * red.size[1] / txt.size[1])
    if squeeze_bars:
        # keep the bars at full height, narrow them until they fit the column
        for f in [x / 20 for x in range(20, 4, -1)]:
            narrow = red.resize((max(1, round(red.size[0] * f)), red.size[1]), Image.LANCZOS)
            try:
                rc = fit_logical(narrow, BAR_W - 3, bh, slant)
            except ValueError:
                continue
            if len(rc) == bh:
                break
        else:
            raise ValueError("bars do not fit even when narrowed")
    else:
        rc = fit_logical(red, BAR_W - 3, bh, slant)
    grid = [[BG] * LOGO_W for _ in range(LOGO_H)]
    kind = [None] * cols

    def place(roles, ox, oy, what):
        for y, row in enumerate(roles):
            for x, r in enumerate(row):
                if r == BG:
                    continue
                gx, gy = ox + x, oy + y
                if not (0 <= gx < LOGO_W and 0 <= gy < LOGO_H):
                    raise ValueError(f"logo pixel outside the sprite grid at {gx},{gy}")
                grid[gy][gx] = r
                if r == BODY:
                    col = gx // 12
                    if kind[col] not in (None, what):
                        raise ValueError(f"sprite column {col} has bar and letter body pixels")
                    kind[col] = what

    # vertically centred on each other, as in the original logo
    place(shade(rc), 1, (LOGO_H - 3 - bh) // 2 + 1, "bar")
    place(shade(tc), BAR_W + 1, (LOGO_H - 3 - th) // 2 + 1, "letter")
    return grid, kind


# --- 2x2 multicolor font -----------------------------------------------------
# Per glyph line (14 lines) the colour source, or two checker-dithered ones:
# T = colour RAM of the top char, B = colour RAM of the bottom char,
# 1 = $d022, 2 = $d023.  Ocean style gold: white > yellow > orange > red.
GOLD = dict(T=1, B=2, c1=7, c2=8,
            lines=["T", "T", "T1", "1", "1", "1", "12", "2",
                   "2", "2", "2B", "B", "B", "B"])
MC_BITS = {"1": 0b01, "2": 0b10, "T": 0b11, "B": 0b11}


def font_cell_bits(rows, scheme):
    """7x7 glyph -> 16 lines x 8 logical px of multicolor bit pairs. Glyph line
    ln is pixel row ln // 2, so the glyph fills lines 0-13 of the cell."""
    cell = [[0] * 8 for _ in range(16)]
    for ln in range(14):
        spec = scheme["lines"][ln]
        for x in range(7):
            if rows[ln // 2][x] != "#":
                continue
            s = spec[(x + ln) & 1] if len(spec) == 2 else spec
            if (s == "T" and ln >= 8) or (s == "B" and ln < 8):
                raise ValueError(f"scheme uses {s} on line {ln}: wrong char half")
            cell[ln][x] = MC_BITS[s]
    return cell


# --- hires "10" (one sprite) -------------------------------------------------
def text_mask(font_file, text="10"):
    f = ImageFont.truetype(f"C:/Windows/Fonts/{font_file}", 300)
    im = Image.new("L", (800, 420), 0)
    ImageDraw.Draw(im).text((20, 20), text, font=f, fill=255)
    return im.crop(im.getbbox())


def hires_ten(font_file, slant, w=24, h=21, pad=0):
    """Fit '10' into a w x h hires grid (booleans), optionally slanted."""
    m = text_mask(font_file)
    best = None
    for hh in range(h - 2 * pad, 6, -1):
        big = m.resize((max(1, round(m.size[0] * hh / m.size[1])) * 8, hh * 8), Image.LANCZOS)
        if slant:
            big = skew(big, slant)
        ww = -(-big.size[0] // 8)
        if ww <= w - 2 * pad:
            best = (big, ww, hh)
            break
    big, ww, hh = best
    cov = coverage(big, ww, hh)
    g = [[False] * w for _ in range(h)]
    ox, oy = (w - ww) // 2, (h - hh) // 2
    for y in range(hh):
        for x in range(ww):
            g[oy + y][ox + x] = cov[y][x] >= 0.45
    return g
