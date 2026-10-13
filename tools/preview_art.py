"""Option sheets for the logo and the scroller font (preview only, nothing is
built into the demo). Writes build/preview_logo.png and build/preview_font.png.
"""
import sys
from PIL import Image, ImageDraw, ImageFont

from art import (PAL, BG, OUTLINE, BODY, LIGHT, ROOT, logo_masks, fit_logical,
                 shade, render, coverage)

BUILD = ROOT / "build"
W, H = 96, 63                 # logo grid in logical px (8 x 3 sprites)
BAR_COLS = 24                 # sprite columns 0-1 hold the bars


def logo_option(slant, light, outline, bar_body, txt_bodies):
    red, txt = logo_masks()
    tallest = max(red.size[1], txt.size[1])
    tc = fit_logical(txt, 72 - 3, (H - 4) * txt.size[1] // tallest, slant)
    th = len(tc)
    bh = round(th * red.size[1] / txt.size[1])
    rc = fit_logical(red, BAR_COLS - 3, bh, slant)
    rr, tr = shade(rc), shade(tc)
    grid = [[None] * W for _ in range(H)]
    col_use = [set() for _ in range(8)]

    def place(roles, ox, oy, body_of_col):
        for y, row in enumerate(roles):
            for x, r in enumerate(row):
                gx, gy = ox + x, oy + y
                if r == BG:
                    continue
                if not (0 <= gx < W and 0 <= gy < H):
                    raise SystemExit(f"pixel outside sprite grid at {gx},{gy}")
                c = {OUTLINE: outline, LIGHT: light, BODY: body_of_col(gx // 12)}[r]
                grid[gy][gx] = c
                if r == BODY:
                    col_use[gx // 12].add(c)

    # vertically centred on each other (as in the original logo)
    place(rr, 1, (H - 3 - len(rr)) // 2 + 1, lambda col: bar_body)
    place(tr, BAR_COLS + 1, (H - 3 - th) // 2 + 1, lambda col: txt_bodies[col - 2] if col >= 2 else None)
    for i, used in enumerate(col_use):
        if len(used) > 1 or None in used:
            raise SystemExit(f"sprite column {i} needs body colours {used}: breaks the 3-colour limit")
    return grid


def font_glyph(font_path, ch, gw=7, gh=13):
    f = ImageFont.truetype(font_path, 200)
    im = Image.new("L", (400, 300), 0)
    ImageDraw.Draw(im).text((20, 20), ch, font=f, fill=255)
    box = im.getbbox()
    if box is None:
        return [[0.0] * gw for _ in range(gh)]
    g = im.crop(box)
    # fit into gw logical (2*gw screen px) x gh lines, keep narrow glyphs narrow
    sw, sh = g.size
    tw = min(gw * 2, max(2, round(sw * gh / sh)))
    if ch in "1I.:-'!":
        tw = min(tw, round(sw * gh / sh)) or 2
    g = g.resize((tw * 8, gh * 8), Image.LANCZOS)
    cell = Image.new("L", (gw * 2 * 8, gh * 8), 0)
    cell.paste(g, ((gw * 2 * 8 - g.size[0]) // 2, 0))
    return coverage(cell, gw, gh)


def font_shade(cov):
    """Font style: highlight on top, body, dark drop shadow (1 right, 1 down)."""
    h, w = len(cov), len(cov[0])
    ins = lambda x, y: 0 <= x < w and 0 <= y < h and cov[y][x] >= 0.5
    out = [[BG] * (w + 1) for _ in range(h + 1)]
    for y in range(h):
        for x in range(w):
            if ins(x, y):
                up = next((d for d in range(1, 6) if not ins(x, y - d)), 6)
                if up <= 2 or (up <= 4 and (x + y) & 1 and y < h // 2):
                    out[y][x] = LIGHT
                else:
                    out[y][x] = BODY
    for y in range(h + 1):
        for x in range(w + 1):
            if out[y][x] == BG and ins(x - 1, y - 1):
                out[y][x] = OUTLINE
    return out


def font_sheet(font_path, text, light, shadow, bodies):
    glyphs = {c: font_shade(font_glyph(font_path, c)) for c in set(text) if c != " "}
    gw, gh = 8, 16
    grid = [[None] * (gw * len(text)) for _ in range(gh)]
    for i, c in enumerate(text):
        if c == " ":
            continue
        body = bodies[i % len(bodies)]
        for y, row in enumerate(glyphs[c]):
            for x, r in enumerate(row):
                if r != BG and x < gw and y < gh:
                    grid[y + 1][i * gw + x] = {OUTLINE: shadow, LIGHT: light, BODY: body}[r]
    return render(grid, None, scale=3)


def label(im, text):
    out = Image.new("RGB", (im.size[0], im.size[1] + 28), (30, 30, 30))
    out.paste(im, (0, 28))
    ImageDraw.Draw(out).text((8, 6), text, fill=(230, 230, 230),
                             font=ImageFont.truetype("C:/Windows/Fonts/segoeuib.ttf", 16))
    return out


def stack(images, pad=12):
    w = max(i.size[0] for i in images)
    h = sum(i.size[1] for i in images) + pad * (len(images) - 1)
    out = Image.new("RGB", (w, h), (30, 30, 30))
    y = 0
    for i in images:
        out.paste(i, (0, y))
        y += i.size[1] + pad
    return out


if __name__ == "__main__":
    what = sys.argv[1] if len(sys.argv) > 1 else "both"
    if what in ("logo", "both"):
        opts = [
            ("A: italic, white highlight, blue outline, light blue letters",
             logo_option(0.22, 1, 6, 2, [14] * 6)),
            ("B: upright (closest to the original), same colours",
             logo_option(0.0, 1, 6, 2, [14] * 6)),
            ("C: italic, light red bars (brighter on real CRT/HDMI), same letters",
             logo_option(0.22, 1, 6, 10, [14] * 6)),
        ]
        stack([label(render(g, None, scale=4), t) for t, g in opts]).save(BUILD / "preview_logo.png")
        print("wrote build/preview_logo.png")
    if what in ("font", "both"):
        text = "VIPP MALTA 2026 * REMKO WEIJNEN"
        rainbow = [2, 7, 5, 3, 6, 4]          # colour RAM colours 0-7 only
        fonts = [("Arial Black", "ariblk.ttf"), ("Impact", "impact.ttf"),
                 ("Rockwell Bold", "ROCKB.TTF"), ("Segoe UI Black", "seguibl.ttf"),
                 ("Franklin Gothic Demi Cond", "FRAMDCN.TTF"), ("Verdana Bold", "verdanab.ttf")]
        sheets = [label(font_sheet(f"C:/Windows/Fonts/{fn}", text, 1, 11, rainbow), name)
                  for name, fn in fonts]
        stack(sheets).save(BUILD / "preview_font.png")
        print("wrote build/preview_font.png")


# --- hand-pixeled font previews ------------------------------------------------
def pixel_font_roles(rows, style):
    """7x7 glyph rows -> 8 x 16 roles (1 logical px x 2 lines per glyph pixel,
    plus a drop shadow 1 px right / 2 lines down)."""
    ins = lambda x, ln: 0 <= x < 7 and 0 <= ln < 14 and rows[ln // 2][x] == "#"
    out = [[BG] * 8 for _ in range(16)]
    for ln in range(14):
        for x in range(7):
            if not ins(x, ln):
                continue
            if style == "bevel":
                top = not ins(x, ln - 1)          # top surface of a stroke
                r = LIGHT if top else BODY
            else:                                   # chrome bands
                band = ["L", "L", "LB", "B", "B", "B", "B", "L", "B", "B", "B", "BD", "D", "D"][ln]
                pick = band[(x + ln) & 1] if len(band) == 2 else band
                r = {"L": LIGHT, "B": BODY, "D": OUTLINE}[pick]
            out[ln][x] = r
    for ln in range(16):
        for x in range(8):
            if out[ln][x] == BG and ins(x - 1, ln - 2):
                out[ln][x] = OUTLINE
    return out


def pixel_font_sheet(text, style, light, dark, bodies):
    from font7 import GLYPHS
    grid = [[None] * (8 * len(text)) for _ in range(18)]
    for i, c in enumerate(text):
        roles = pixel_font_roles(GLYPHS[c], style)
        body = bodies[i % len(bodies)]
        for ln, row in enumerate(roles):
            for x, r in enumerate(row):
                if r != BG:
                    grid[ln + 1][i * 8 + x] = {OUTLINE: dark, LIGHT: light, BODY: body}[r]
    return render(grid, None, scale=3)


def font_previews():
    rainbow = [2, 7, 5, 3, 4]               # colour RAM: only colours 0-7 in multicolor
    lines = ["VIPP MALTA 2026 * REMKO WEIJNEN", "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "0123456789 *-:!.'?"]
    sheets = []
    for style, title in (("bevel", "1: bevel - white top edges, rainbow body, shadow"),
                         ("chrome", "2: chrome bands - white top + horizon line, dark bottom, shadow")):
        for dark, dn in ((6, "blue"), (11, "dark grey")):
            imgs = [pixel_font_sheet(t, style, 1, dark, rainbow) for t in lines]
            sheets.append(label(stack(imgs, pad=0), f"{title} ({dn})"))
    stack(sheets).save(BUILD / "preview_font.png")
    print("wrote build/preview_font.png")


if __name__ == "__main__" and len(sys.argv) > 1 and sys.argv[1] == "pixelfont":
    font_previews()


# --- per-line colour schemes (2x2 multicolor chars) ----------------------------
# A scheme gives each of the 14 glyph lines a colour source, or two sources
# that are checker-dithered. Sources: T = colour RAM of the top char,
# B = colour RAM of the bottom char (colours 0-7), 1 = $d022, 2 = $d023.
SCHEMES = {
    "chrome": dict(title="Last Ninja-style chrome: white > grey > dark grey, white horizon",
                   T=1, B=1, c1=12, c2=11,
                   lines=["T", "T", "T1", "1", "1", "12", "2", "2",
                          "B", "B1", "1", "1", "12", "2"]),
    "gold": dict(title="Ocean-style gold: white > yellow > orange > red",
                 T=1, B=2, c1=7, c2=8,
                 lines=["T", "T", "T1", "1", "1", "1", "12", "2",
                        "2", "2", "2B", "B", "B", "B"]),
    "stripes": dict(title="Rambo-style stripes: yellow lines with brown gaps, white top",
                    T=7, B=7, c1=1, c2=9,
                    lines=["1", "2", "T", "2", "T", "2", "T", "2",
                           "B", "2", "B", "2", "B", "2"]),
}


def scheme_sheet(glyphs, text, sch, shadow=None):
    grid = [[None] * (8 * len(text)) for _ in range(18)]
    src = {"T": sch["T"], "B": sch["B"], "1": sch["c1"], "2": sch["c2"]}
    for i, c in enumerate(text):
        rows = glyphs[c]
        ins = lambda x, ln: 0 <= x < 7 and 0 <= ln < 14 and rows[ln // 2][x] == "#"
        for ln in range(14):
            spec = sch["lines"][ln]
            for x in range(7):
                if ins(x, ln):
                    s = spec[(x + ln) & 1] if len(spec) == 2 else spec
                    if (s == "T" and ln >= 8) or (s == "B" and ln < 8):
                        raise SystemExit(f"scheme uses {s} on line {ln}: wrong char half")
                    grid[ln + 1][i * 8 + x] = src[s]
        if shadow is not None:
            for ln in range(16):
                for x in range(8):
                    if grid[ln + 1][i * 8 + x] is None and ins(x - 1, ln - 2):
                        grid[ln + 1][i * 8 + x] = shadow
    return render(grid, None, scale=3)


def scheme_previews():
    from font7 import GLYPHS as BOLD
    from font7thin import GLYPHS as THIN
    lines = ["VIPP MALTA 2026 * REMKO WEIJNEN", "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "0123456789 *-:!.'?"]
    sheets = []
    for key in ("chrome", "gold", "stripes"):
        sch = SCHEMES[key]
        imgs = [scheme_sheet(THIN, t, sch) for t in lines]
        sheets.append(label(stack(imgs, pad=0), f"thin wide font - {sch['title']}"))
    sch = SCHEMES["gold"]
    sheets.append(label(scheme_sheet(BOLD, lines[0], sch), "bold font for comparison - " + sch["title"]))
    stack(sheets).save(BUILD / "preview_font2.png")
    print("wrote build/preview_font2.png")


if __name__ == "__main__" and len(sys.argv) > 1 and sys.argv[1] == "schemes":
    scheme_previews()


# --- v2: 6-wide VIPP logo + "10" ---------------------------------------------
def ten_roles(font_file, slant, width=24, xexp=1):
    """'10' for width/12 sprites side by side (width x 21 logical px), shown
    Y-expanded (and X-expanded when xexp=2)."""
    f = ImageFont.truetype(f"C:/Windows/Fonts/{font_file}", 300)
    im = Image.new("L", (700, 400), 0)
    ImageDraw.Draw(im).text((20, 20), "10", font=f, fill=255)
    m = im.crop(im.getbbox())
    # Y-expanded: 21 logical lines show as 42 screen lines, so the source
    # aspect maps to 2 screen px per logical x and 2 lines per logical y
    sw, sh = m.size
    for h in range(21 - 3, 8, -1):
        w_screen = sw * (h * 2) / sh + slant * h * 2
        w = int(-(-w_screen // (2 * xexp)))
        if w <= width - 3:
            break
    big = m.resize((max(1, round(sw * h * 2 / sh / xexp)) * 4, h * 2 * 4), Image.LANCZOS)
    if slant:
        from art import skew
        big = skew(big, slant)
    cov = coverage(big, w, h * 2)
    cov = [cov[y] for y in range(0, h * 2, 2)]           # back to logical lines
    roles = shade(cov, light_rows=1, dither_rows=1, shadow=(1, 1))
    grid = [[BG] * width for _ in range(21)]
    ox, oy = (width - 3 - w) // 2 + 1, (21 - 3 - h) // 2 + 1
    for y, row in enumerate(roles):
        for x, r in enumerate(row):
            if r != BG:
                grid[oy + y][ox + x] = r
    return grid


def _colour(roles, kind, ten_body=None):
    def c(x, r):
        if r == BG:
            return None
        if r == BODY:
            return ten_body if ten_body is not None else (2 if kind[x // 12] == "bar" else 14)
        return {OUTLINE: 6, LIGHT: 1}[r]
    return [[c(x, r) for x, r in enumerate(row)] for row in roles]


def _expand(grid, xexp, yexp=2):
    return [[v for v in row for _ in range(xexp)] for row in grid for _ in range(yexp)]


def _combo(vipp, ten, gap=6):
    """VIPP (logical px) next to the 10 (already expanded to logical px)."""
    w = len(vipp[0]) + gap + len(ten[0])
    out = [[None] * w for _ in range(63)]
    for y in range(63):
        out[y][:len(vipp[0])] = vipp[y]
    for y, row in enumerate(ten):
        for x, v in enumerate(row):
            if v is not None:
                out[y + 10][len(vipp[0]) + gap + x] = v
    return out


def v2_previews():
    from art import logo_roles
    sheets = []
    # A: 6 wide, thinner bars, 10 = 2 sprites Y-expanded
    roles, kind = logo_roles(0.22, cols=6, bar_cols=1, squeeze_bars=True)
    vipp_a = _colour(roles, kind)
    ten_a = _expand(_colour(ten_roles("impact.ttf", 0.22), None, ten_body=7), 1)
    sheets.append(label(render(_combo(vipp_a, ten_a), None, scale=4),
                        "A: VIPP 6 sprites wide (thinner bars)  +  10 = 2 sprites, 48x42"))
    # B: 7 wide, normal bars, 10 = 1 sprite X+Y-expanded
    roles, kind = logo_roles(0.22, cols=7, bar_cols=2)
    vipp_b = _colour(roles, kind)
    ten_b = _expand(_colour(ten_roles("impact.ttf", 0.22, width=12, xexp=2), None, ten_body=7), 2)
    sheets.append(label(render(_combo(vipp_b, ten_b), None, scale=4),
                        "B: VIPP 7 sprites wide (normal bars)  +  10 = 1 sprite stretched, 48x42"))
    # current v1 logo for reference
    roles, kind = logo_roles(0.22)
    sheets.append(label(render(_colour(roles, kind), None, scale=4), "v1 for reference: 8 sprites wide"))
    # 10 colour options (design A)
    for body, name in ((7, "yellow"), (8, "orange"), (10, "light red"), (1, "white")):
        g = _expand(_colour(ten_roles("impact.ttf", 0.22), None, ten_body=body), 1)
        sheets.append(label(render(g, None, scale=4), f"10 in {name}"))
    stack(sheets).save(BUILD / "preview_v2.png")
    print("wrote build/preview_v2.png")


if __name__ == "__main__" and len(sys.argv) > 1 and sys.argv[1] == "v2":
    v2_previews()


def ten_hires(font_file, slant, outline=False):
    """'10' as one hires sprite: 24 x 21 pixels, each shown 2x2 (X+Y-expanded).
    Returns a 21 x 24 grid of booleans."""
    f = ImageFont.truetype(f"C:/Windows/Fonts/{font_file}", 300)
    im = Image.new("L", (700, 400), 0)
    ImageDraw.Draw(im).text((20, 20), "10", font=f, fill=255)
    m = im.crop(im.getbbox())
    from art import skew
    pad = 2 if outline else 1
    for h in range(21 - 2 * pad, 8, -1):
        big = m.resize((max(1, round(m.size[0] * h / m.size[1])) * 8, h * 8), Image.LANCZOS)
        if slant:
            big = skew(big, slant)
        w = -(-big.size[0] // 8)
        if w <= 24 - 2 * pad:
            break
    cov = coverage(big, w, h)
    grid = [[False] * 24 for _ in range(21)]
    ox, oy = (24 - w) // 2, (21 - h) // 2
    for y in range(h):
        for x in range(w):
            if cov[y][x] >= 0.45:
                grid[oy + y][ox + x] = True
    if outline:   # hollow: keep a 1px outline, the inside stays transparent
        solid = [row[:] for row in grid]
        ins = lambda x, y: 0 <= x < 24 and 0 <= y < 21 and solid[y][x]
        for y in range(21):
            for x in range(24):
                if solid[y][x] and all(ins(x + dx, y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1)):
                    grid[y][x] = False
    return grid


def v2b_previews():
    from art import logo_roles
    roles, kind = logo_roles(0.22, cols=7, bar_cols=2)
    vipp = _colour(roles, kind)
    sheets = []
    for font_file, slant, outline, col, name in (
            ("impact.ttf", 0.22, False, 7, "Impact italic, solid yellow"),
            ("ariblk.ttf", 0.22, False, 7, "Arial Black italic, solid yellow"),
            ("impact.ttf", 0.22, False, 1, "Impact italic, solid white"),
            ("ariblk.ttf", 0.0, False, 7, "Arial Black upright, solid yellow")):
        t = ten_hires(font_file, slant, outline)
        # hires pixel = 1 screen px; expanded 2x2. Show in 'half logical' units:
        # render() uses 2 screen px per cell, so a hires px expanded (2 px) = 1 cell
        g = [[col if v else None for v in row] for row in t]
        g2 = [row for row in g for _ in (0, 1)]
        combo = _combo(vipp, g2)
        sheets.append(label(render(combo, None, scale=4), f"C: VIPP 7 wide + hires 10 (1 sprite, 48x42): {name}"))
    stack(sheets).save(BUILD / "preview_v2c.png")
    print("wrote build/preview_v2c.png")


if __name__ == "__main__" and len(sys.argv) > 1 and sys.argv[1] == "v2c":
    v2b_previews()


