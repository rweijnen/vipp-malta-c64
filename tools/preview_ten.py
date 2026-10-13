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


def explosion_sheet():
    from art import explosion_frames, EXPLOSION_COLOURS
    from art import hires_ten
    frames = [hires_ten("impact.ttf", 0.22)] + explosion_frames()
    cols = [1] + EXPLOSION_COLOURS
    ims = [hires_image(f, c, 1, 2) for f, c in zip(frames, cols)]
    W = sum(i.size[0] + 8 for i in ims)
    strip = Image.new("RGB", (W, 42), PAL[0])
    x = 0
    for i in ims:
        strip.paste(i, (x, 0))
        x += i.size[0] + 8
    strip = strip.resize((W * 4, 42 * 4), Image.NEAREST)
    out = Image.new("RGB", (strip.size[0], strip.size[1] + 28), (30, 30, 30))
    out.paste(strip, (0, 28))
    ImageDraw.Draw(out).text((8, 6), "explosion: the 10, then 10 frames (2 video frames each), Y-expanded hires sprite",
                             fill=(230, 230, 230), font=ImageFont.truetype("C:/Windows/Fonts/segoeuib.ttf", 16))
    out.save(BUILD / "preview_explosion.png")
    print("wrote build/preview_explosion.png")


if __name__ == "__main__":
    explosion_sheet()


def fire_sheet(path="preview_explosion.png"):
    """Multicolor fire explosion strip + one mid-explosion scene with the VIPP
    logo glowing in the shared fire colours."""
    from art import hires_ten, fire_frames, FIRE_COLOURS

    def mc_image(heat, cols):
        im = Image.new("RGB", (24, 42), PAL[0])
        m = {3: cols[0], 2: cols[1], 1: cols[2]}
        for y, row in enumerate(heat):
            for x, h in enumerate(row):
                if h:
                    for dx in (0, 1):
                        for dy in (0, 1):
                            im.putpixel((x * 2 + dx, y * 2 + dy), PAL[m[h]])
        return im

    def vipp(light, outline):
        roles, kind = logo_roles(0.22, cols=7, bar_cols=2)
        im = Image.new("RGB", (len(roles[0]) * 2, 63), PAL[0])
        for y, row in enumerate(roles):
            for x, r in enumerate(row):
                if r != BG:
                    c = {OUTLINE: outline, LIGHT: light, BODY: 2 if kind[x // 12] == "bar" else 14}[r]
                    im.putpixel((x * 2, y), PAL[c])
                    im.putpixel((x * 2 + 1, y), PAL[c])
        return im

    ten = hires_ten("impact.ttf", 0.22)
    fr = fire_frames(ten)
    ims = [hires_image(ten, 1, 1, 2)] + [mc_image(h, c) for h, c in zip(fr, FIRE_COLOURS)]
    W = sum(i.size[0] + 8 for i in ims)
    strip = Image.new("RGB", (W, 42), PAL[0])
    x = 0
    for i in ims:
        strip.paste(i, (x, 0))
        x += i.size[0] + 8
    strip = strip.resize((W * 4, 42 * 4), Image.NEAREST)
    scenes = []
    for k in (1, 4, 8):
        sc = Image.new("RGB", (168 + 40, 63), PAL[0])
        sc.paste(vipp(FIRE_COLOURS[k][0], FIRE_COLOURS[k][1]), (0, 0))
        sc.paste(mc_image(fr[k], FIRE_COLOURS[k]), (168 + 8, 10))
        scenes.append(sc.resize((sc.size[0] * 3, 63 * 3), Image.NEAREST))
    font = ImageFont.truetype("C:/Windows/Fonts/segoeuib.ttf", 16)
    sw = sum(s.size[0] + 12 for s in scenes)
    out = Image.new("RGB", (max(strip.size[0], sw), strip.size[1] + scenes[0].size[1] + 70), (30, 30, 30))
    d = ImageDraw.Draw(out)
    d.text((8, 6), "multicolor fire: the 10 cracks and shatters, cooling white > yellow > light red > orange > red > ash",
           fill=(230, 230, 230), font=font)
    out.paste(strip, (0, 28))
    d.text((8, strip.size[1] + 40), "early / mid / late: the VIPP highlights and outline glow with the fire (shared colour registers)",
           fill=(230, 230, 230), font=font)
    x = 0
    for s in scenes:
        out.paste(s, (x, strip.size[1] + 66))
        x += s.size[0] + 12
    out.save(BUILD / path)
    print(f"wrote build/{path}")


if __name__ == "__main__":
    fire_sheet()
