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
