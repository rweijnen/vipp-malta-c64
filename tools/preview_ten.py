"""Preview sheet: options for a crisper '10' (one sprite), shown next to the
7-wide VIPP logo at real screen-pixel scale. Writes build/preview_ten.png."""
from PIL import Image, ImageDraw, ImageFont

from art import PAL, BG, OUTLINE, BODY, LIGHT, ROOT, logo_roles, coverage, skew, shade, text_mask, hires_ten

BUILD = ROOT / "build"


def vipp_screen():
    roles, kind = logo_roles(0.22, cols=7, bar_cols=2)
    h, w = len(roles), len(roles[0])
    im = Image.new("RGB", (w * 2, h), PAL[0])
    for y in range(h):
        for x in range(w):
            r = roles[y][x]
            if r != BG:
                c = {OUTLINE: 6, LIGHT: 1, BODY: 2 if kind[x // 12] == "bar" else 14}[r]
                im.putpixel((x * 2, y), PAL[c])
                im.putpixel((x * 2 + 1, y), PAL[c])
    return im


def hires_image(grid, colour, xexp, yexp):
    h, w = len(grid), len(grid[0])
    im = Image.new("RGB", (w * xexp, h * yexp), PAL[0])
    for y in range(h):
        for x in range(w):
            if grid[y][x]:
                for dx in range(xexp):
                    for dy in range(yexp):
                        im.putpixel((x * xexp + dx, y * yexp + dy), PAL[colour])
    return im


def mc_ten(font_file, slant, xexp):
    """Multicolor '10' (12 x 21 logical), white body + red outline, auto-shaded."""
    m = text_mask(font_file)
    w_log, h_log = 12, 21
    for hh in range(h_log - 3, 6, -1):
        # logical px are 2*xexp screen px wide, lines are 2 screen px (Y-expanded)
        big = m.resize((max(1, round(m.size[0] * hh * 2 / m.size[1] / xexp)) * 8, hh * 2 * 8), Image.LANCZOS)
        if slant:
            big = skew(big, slant / xexp)
        ww = -(-big.size[0] // 16)
        if ww <= w_log - 2:
            break
    cov = coverage(big, ww, hh * 2)
    cov = [cov[y] for y in range(0, hh * 2, 2)]
    roles = shade(cov, light_rows=0, dither_rows=0, shadow=(0, 0))
    im = Image.new("RGB", (w_log * 2 * xexp, h_log * 2), PAL[0])
    ox, oy = (w_log - len(roles[0])) // 2, (h_log - len(roles)) // 2
    for y, row in enumerate(roles):
        for x, r in enumerate(row):
            if r == BG:
                continue
            c = 2 if r == OUTLINE else 1
            for dx in range(2 * xexp):
                for dy in range(2):
                    im.putpixel(((ox + x) * 2 * xexp + dx, (oy + y) * 2 + dy), PAL[c])
    return im


def combo(vipp, ten_im, title):
    W = vipp.size[0] + 12 + ten_im.size[0]
    im = Image.new("RGB", (W, 63), PAL[0])
    im.paste(vipp, (0, 0))
    im.paste(ten_im, (vipp.size[0] + 12, (63 - ten_im.size[1]) // 2))
    im = im.resize((W * 4, 63 * 4), Image.NEAREST)
    out = Image.new("RGB", (im.size[0], im.size[1] + 28), (30, 30, 30))
    out.paste(im, (0, 28))
    ImageDraw.Draw(out).text((8, 6), title, fill=(230, 230, 230),
                             font=ImageFont.truetype("C:/Windows/Fonts/segoeuib.ttf", 16))
    return out


if __name__ == "__main__":
    vipp = vipp_screen()
    sheets = [
        combo(vipp, hires_image(hires_ten("impact.ttf", 0.22), 1, 2, 2),
              "1: hires, 48x42 - Impact italic, white (crisp, 1 colour)"),
        combo(vipp, hires_image(hires_ten("ariblk.ttf", 0.22), 1, 2, 2),
              "2: hires, 48x42 - Arial Black italic, white"),
        combo(vipp, hires_image(hires_ten("impact.ttf", 0.22), 1, 1, 2),
              "3: hires, 24x42 (taller, not stretched sideways) - Impact italic, white"),
        combo(vipp, mc_ten("impact.ttf", 0.22, 2),
              "4: multicolor, 48x42 - Impact italic, white + red outline (chunky)"),
        combo(vipp, mc_ten("impact.ttf", 0.22, 1),
              "5: multicolor, 24x42 - Impact italic, white + red outline (finer, smaller)"),
    ]
    W = max(s.size[0] for s in sheets)
    out = Image.new("RGB", (W, sum(s.size[1] + 12 for s in sheets)), (30, 30, 30))
    y = 0
    for s in sheets:
        out.paste(s, (0, y))
        y += s.size[1] + 12
    out.save(BUILD / "preview_ten.png")
    print("wrote build/preview_ten.png")
