"""Pixel-art helpers for the VIPP demo: C64 palette, shaded multicolor logo and
multicolor 2x2 font. Everything works on 'logical' multicolor pixels, which
are 2 screen pixels wide and 1 line tall.

Used by preview_art.py (option sheets) and later by gen_assets.py.
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops

ROOT = Path(__file__).resolve().parent.parent

# Colodore palette (VICE's default, close to a real C64 / the Ultimate's HDMI)
PAL = [(0x00, 0x00, 0x00), (0xFF, 0xFF, 0xFF), (0x81, 0x33, 0x38), (0x75, 0xCE, 0xC8),
       (0x8E, 0x3C, 0x97), (0x56, 0xAC, 0x4D), (0x2E, 0x2C, 0x9B), (0xED, 0xF1, 0x71),
       (0x8E, 0x50, 0x29), (0x55, 0x38, 0x00), (0xC4, 0x6C, 0x71), (0x4A, 0x4A, 0x4A),
       (0x7B, 0x7B, 0x7B), (0xA9, 0xFF, 0x9F), (0x70, 0x6D, 0xEB), (0xB2, 0xB2, 0xB2)]

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


# --- explosion animation for the hires '10' sprite ---------------------------
EXPLOSION_COLOURS = [1, 1, 7, 7, 8, 10, 2, 9, 11, 11]


def explosion_frames(n=len(EXPLOSION_COLOURS), seed=10):
    """n hires frames (21 rows x 24 booleans) of a fireball that bursts out,
    breaks up into debris and fades. Designed for a Y-expanded sprite, so a
    pixel is 1 wide and 2 lines tall: distances use y * 2."""
    import random
    rnd = random.Random(seed)
    cx, cy = 11.5, 10
    # fixed jagged outline and debris so the frames animate coherently
    spikes = [rnd.uniform(0.75, 1.25) for _ in range(16)]
    debris = [(rnd.uniform(0, 2 * math.pi), rnd.uniform(0.6, 1.0)) for _ in range(22)]
    frames = []
    for k in range(n):
        t = (k + 1) / n
        radius = 3 + 11 * t ** 0.6           # in screen px (x) units
        hole = max(0.0, (t - 0.45) / 0.55) * radius * 0.9   # burns out from the middle
        g = [[False] * 24 for _ in range(21)]
        for y in range(21):
            for x in range(24):
                dx, dy = x - cx, (y - cy) * 2
                d = math.hypot(dx, dy)
                a = math.atan2(dy, dx)
                spike = spikes[int((a + math.pi) / (2 * math.pi) * 16) % 16]
                edge = radius * spike
                if hole < d <= edge:
                    # break the fireball up as it cools
                    density = 1.0 - 0.75 * max(0.0, t - 0.3) / 0.7
                    if rnd.random() < density:
                        g[y][x] = True
        for ang, speed in debris:
            if t < 0.25:
                continue
            r = radius * 1.15 * speed + 2
            x = round(cx + math.cos(ang) * r)
            y = round(cy + math.sin(ang) * r / 2)
            if 0 <= x < 24 and 0 <= y < 21 and rnd.random() < 1.1 - t:
                g[y][x] = True
        frames.append(g)
    return frames


SHATTER_COLOURS = [1, 7, 1, 7, 8, 10, 8, 2, 9, 11, 11, 11]


def shatter_frames(ten, n=len(SHATTER_COLOURS), seed=10):
    """The '10' cracks, shatters into chunks that fly apart (with gravity)
    while a fireball bursts out of the cracks. Hires 24 x 21 frames for a
    Y-expanded sprite (a pixel is 1 wide, 2 lines tall)."""
    import random
    rnd = random.Random(seed)
    H, W = len(ten), len(ten[0])
    pts = [(x, y) for y in range(H) for x in range(W) if ten[y][x]]
    cx = sum(x for x, _ in pts) / len(pts)
    cy = sum(y for _, y in pts) / len(pts)
    # chunks: a jittered grid of cells, each with its own velocity
    cell_w, cell_h = 4, 3
    chunks = {}
    for x, y in pts:
        key = ((x + (y // 5) % 2) // cell_w, (y + (x // 6) % 2) // cell_h)   # irregular cells
        chunks.setdefault(key, []).append((x, y))
    vel = {}
    for key, cps in chunks.items():
        mx = sum(p[0] for p in cps) / len(cps)
        my = sum(p[1] for p in cps) / len(cps)
        dx, dy = mx - cx, (my - cy) * 2
        d = math.hypot(dx, dy) or 1
        speed = rnd.uniform(1.6, 2.6)
        vel[key] = (dx / d * speed + rnd.uniform(-0.4, 0.4),
                    (dy / d * speed) / 2 + rnd.uniform(-0.3, 0.1))
    spikes = [rnd.uniform(0.7, 1.3) for _ in range(12)]
    frames = []
    for k in range(n):
        g = [[False] * W for _ in range(H)]
        if k == 0:
            # cracks: the cell borders open up, the digit is still in place
            for key, cps in chunks.items():
                for x, y in cps:
                    if (x + (y // 5) % 2) % cell_w and (y + (x // 6) % 2) % cell_h:
                        g[y][x] = True
            frames.append(g)
            continue
        t = k
        # flying chunks, shrinking (burning up) over time
        for key, cps in chunks.items():
            vx, vy = vel[key]
            ox = vx * t
            oy = vy * t + 0.06 * t * t          # gravity, in sprite rows
            keep = 1.0 - k / (n * 0.9)
            for x, y in cps:
                if rnd.random() > keep:
                    continue
                nx, ny = round(x + ox), round(y + oy)
                if 0 <= nx < W and 0 <= ny < H:
                    g[ny][nx] = True
        # fireball from the centre: grows, then burns out from the middle
        if k <= 8:
            r = 2 + 2.2 * k
            hole = max(0, k - 3) * 2.0
            for y in range(H):
                for x in range(W):
                    dx, dy = x - cx, (y - cy) * 2
                    d = math.hypot(dx, dy)
                    sp = spikes[int((math.atan2(dy, dx) + math.pi) / (2 * math.pi) * 12) % 12]
                    if hole < d <= r * sp and rnd.random() < 1.0 - k / 10:
                        g[y][x] = True
        frames.append(g)
    return frames


SHATTER2_COLOURS = [1, 1, 7, 1, 7, 7, 8, 10, 8, 2, 9, 11]


def shatter2_frames(ten, n=len(SHATTER2_COLOURS), seed=7):
    """Cleaner shatter: jagged crack lines split the '10' into ~6 chunks that
    first drift apart (still readable as a 10), then fly off with gravity and
    burn out one by one, with a sparse burst of sparks behind them."""
    import random
    rnd = random.Random(seed)
    H, W = len(ten), len(ten[0])
    pts = [(x, y) for y in range(H) for x in range(W) if ten[y][x]]
    xs = [x for x, _ in pts]
    split = (min(xs) + max(xs)) // 2 - 2            # between the 1 and the 0 (approx.)
    # gap column between the digits: the empty column closest to split
    cols = {x for x, _ in pts}
    gap = min((x for x in range(min(xs), max(xs)) if x not in cols), key=lambda x: abs(x - split), default=split)
    cx = sum(xs) / len(xs)
    cy = sum(y for _, y in pts) / len(pts)

    def piece(x, y):
        """Which chunk a pixel belongs to, or None on a crack line."""
        if x < gap:                                   # the 1: one diagonal crack
            c = y - (cy - 1) - (x - gap) * 0.6
            if abs(c) < 0.7:
                return None
            return 0 if c < 0 else 1
        # the 0: a jagged horizontal crack and a slanted vertical one
        h = y - (cy + (1 if (x // 2) % 2 else -0.0))
        v = x - (gap + (max(xs) - gap) / 2) - (cy - y) * 0.25
        if abs(h) < 0.6 or abs(v) < 0.6:
            return None
        return 2 + (h > 0) * 2 + (v > 0)

    chunks = {}
    for x, y in pts:
        p = piece(x, y)
        if p is not None:
            chunks.setdefault(p, []).append((x, y))
    vel, die = {}, {}
    order = sorted(chunks, key=lambda p: len(chunks[p]))
    for i, p in enumerate(order):                     # small chunks burn out first
        cps = chunks[p]
        mx = sum(q[0] for q in cps) / len(cps)
        my = sum(q[1] for q in cps) / len(cps)
        dx, dy = mx - cx, (my - cy) * 2
        d = math.hypot(dx, dy) or 1
        vel[p] = (dx / d, dy / d / 2 - 0.25)          # outward, a little upward kick
        die[p] = 6 + i * (n - 7) // max(1, len(order) - 1)
    sparks = [(rnd.uniform(0, 2 * math.pi), rnd.uniform(0.5, 1.0)) for _ in range(18)]
    frames = []
    for k in range(n):
        g = [[False] * W for _ in range(H)]
        # distance travelled: slow drift first, then fast (ease-in)
        s = 0.5 * k + 0.12 * k * k
        for p, cps in chunks.items():
            if k >= die[p]:
                continue
            vx, vy = vel[p]
            ox, oy = vx * s * 1.6, vy * s + 0.05 * k * k
            for x, y in cps:
                nx, ny = round(x + ox), round(y + oy)
                if 0 <= nx < W and 0 <= ny < H:
                    g[ny][nx] = True
        if 2 <= k <= 9:                                # sparks / fire ring
            r = 2.0 + 1.6 * (k - 2)
            for ang, sp in sparks:
                for rr in (r * sp, r * sp - 1.5):
                    x = round(cx + math.cos(ang) * rr)
                    y = round(cy + math.sin(ang) * rr / 2)
                    if 0 <= x < W and 0 <= y < H:
                        g[y][x] = True
        frames.append(g)
    return frames


# Multicolor fire: per frame the colours for heat 3 (hottest, %01 = $d025),
# heat 2 (%11 = $d026) and heat 1 (coolest, %10 = the 10's own colour).
# $d025/$d026 are shared with the VIPP logo, whose highlights and outline glow
# along during the explosion (never in the bars' red, so the bars stay apart).
FIRE_COLOURS = [(1, 7, 10), (1, 7, 10), (1, 7, 10), (7, 10, 2), (7, 10, 2), (7, 8, 2),
                (7, 8, 2), (10, 8, 2), (10, 8, 9), (8, 9, 11), (8, 11, 11), (12, 11, 11)]


def fire_frames(ten, n=len(FIRE_COLOURS), seed=7):
    """Multicolor explosion of the '10' (12 x 21 logical px, each 2 screen px
    wide; the sprite is Y-expanded). Returns per frame a grid of heat values
    0 (empty) .. 3 (hottest), which map to %00, %11, %10, %01."""
    import random
    rnd = random.Random(seed)
    debris = shatter2_frames(ten, n=n, seed=seed)          # flying chunks (hires)
    H, W = len(ten), len(ten[0])
    pts = [(x, y) for y in range(H) for x in range(W) if ten[y][x]]
    cx = sum(x for x, _ in pts) / len(pts) / 2              # in logical px
    cy = sum(y for _, y in pts) / len(pts)
    spikes = [rnd.uniform(0.65, 1.35) for _ in range(14)]
    noise = [[rnd.random() for _ in range(12)] for _ in range(21)]
    frames = []
    for k in range(n):
        heat = [[0] * 12 for _ in range(21)]
        # fireball: grows fast, hot core, burns out from the middle later on
        if k >= 1:
            R = min(6.5, 1.5 + 1.6 * k)                     # logical px (x); y counts double
            hole = max(0.0, (k - 6) * 1.3)
            for y in range(21):
                for x in range(12):
                    dx, dy = (x + 0.5 - cx) * 2, (y - cy) * 2
                    d = math.hypot(dx, dy) / 2
                    sp = spikes[int((math.atan2(dy, dx) + math.pi) / (2 * math.pi) * 14) % 14]
                    edge = R * sp
                    if hole < d <= edge:
                        f = 1 - d / edge + 0.35 * (noise[y][x] - 0.5)
                        h = 3 if f > 0.55 else 2 if f > 0.25 else 1
                        heat[y][x] = max(heat[y][x], h)
        # burning chunks of the 10 on top: hot at first, cooling
        dh = 3 if k < 3 else 2 if k < 7 else 1
        for y in range(H):
            for x in range(W):
                if debris[k][y][x]:
                    lx = x // 2
                    heat[y][lx] = max(heat[y][lx], dh)
        frames.append(heat)
    return frames


# --- water reflection of the 2x2 font ------------------------------------------
# A reflection row is 8 lines: the 14 glyph lines flipped and squashed (every
# other line, starting at the glyph's bottom). Colours come from the distance
# to the water line, not from the original gradient: a style gives, per
# reflection line, the bit pair to use and whether that line is thinned out
# (checker dither) for the water look. Bits: '1' = %01 ($d022, yellow),
# '2' = %10 ($d023, orange), 'C' = %11 (colour RAM of the reflection row).
REFL_STYLES = {
    "warm":  dict(lines=["1", "2", "2", "2C", "C", "C", "C", "C"], thin=[0, 0, 0, 0, 1, 0, 1, 1], cram=2),
    "water": dict(lines=["2", "2C", "C", "C", "C", "C", "C", "C"], thin=[0, 0, 0, 1, 0, 1, 1, 1], cram=6),
    "deep":  dict(lines=["2", "2", "2C", "C", "C", "C", "C", "C"], thin=[0, 0, 1, 0, 1, 0, 1, 1], cram=4),
}
REFL_BITS = {"1": 0b01, "2": 0b10, "C": 0b11}


def refl_cell_bits(rows, style):
    """7x7 glyph -> 8 lines x 8 logical px of multicolor bit pairs."""
    st = REFL_STYLES[style]
    cell = [[0] * 8 for _ in range(8)]
    for r in range(8):
        src = 13 - 2 * r                      # glyph line (0-13), bottom first
        if src < 0:
            continue
        spec = st["lines"][r]
        for x in range(7):
            if rows[src // 2][x] != "#":
                continue
            if st["thin"][r] and (x + r) & 1:
                continue
            s = spec[(x + r) & 1] if len(spec) == 2 else spec
            cell[r][x] = REFL_BITS[s]
    return cell
