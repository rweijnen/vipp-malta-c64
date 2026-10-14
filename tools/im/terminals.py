"""The VIPP Mission's security terminals: one Parallels product per terminal,
shown in the original's terminal screen (assets/im/terminal_*, see
extract_terminal.py) with the original's terminal font (the lift charset).

The font has A-Z, 0-9, * = > / . and no hyphen or comma: those two are added
in the same style (free characters $9d and $9e of our copy of the charset).

usage: terminals.py preview [LAYOUT]   -> build/shots/terminals_<layout>.png
       (the build uses build_screens() via gen_mission.py)
"""
import sys
import textwrap
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
IM = ROOT / "assets" / "im"

# product texts: parallels.com/products (Toolbox left out, the Desktop editions in one)
TERMINALS = [
    ("PARALLELS RAS",
     "DELIVER VIRTUAL APPS AND DESKTOPS SECURELY ACROSS DEVICES WITH CENTRALIZED MANAGEMENT."),
    ("PARALLELS DAAS",
     "CLOUD-NATIVE VIRTUAL DESKTOPS AND APPLICATIONS DELIVERED SECURELY TO ANY DEVICE."),
    ("PARALLELS SECURE WORKSPACE",
     "SECURELY ACCESS APPS, DESKTOPS AND FILES FROM ANY DEVICE THROUGH A UNIFIED BROWSER-BASED WORKSPACE."),
    ("PARALLELS BROWSER ISOLATION",
     "SECURE ACCESS TO SAAS, INTERNAL WEB APPS AND PRIVATE RESOURCES THROUGH ISOLATED BROWSER SESSIONS."),
    ("PARALLELS DESKTOP",
     "RUN WINDOWS ON MAC, FOR EVERYONE FROM HOME USERS TO DEVELOPERS AND ENTERPRISES. "
     "PRO / BUSINESS / ENTERPRISE."),
]

SPACE = 0x53
HYPHEN = 0x9d
COMMA = 0x9e
EXTRA_GLYPHS = {
    HYPHEN: [0, 0, 0, 0b00111100, 0, 0, 0, 0],
    COMMA: [0, 0, 0, 0, 0, 0, 0b01100000, 0b11000000],
}
BOX = 0xfd                      # the original's box line character
TEXT_COLS = 28                  # columns 6-33
LEFT = 6


def code(ch):
    if "A" <= ch <= "Z":
        return 0x71 + ord(ch) - ord("A")
    if "0" <= ch <= "9":
        return 0x8b + ord(ch) - ord("0")
    table = {" ": SPACE, "*": 0x95, "=": 0x96, ">": 0x97, ".": 0xfe, "/": 0xdd, "-": HYPHEN, ",": COMMA}
    if ch not in table:
        sys.exit(f"terminal text: no character for {ch!r}")
    return table[ch]


def put(scr, row, col, text):
    for i, ch in enumerate(text):
        scr[row * 40 + col + i] = code(ch)


def centre(scr, row, text, width=TEXT_COLS, left=LEFT):
    if len(text) > width:
        sys.exit(f"terminal text too long for {width} columns: {text!r}")
    put(scr, row, left + (width - len(text)) // 2, text)


def box(scr, rows, c0, c1, text):
    """The original's framed line: box lines above and below, sides, ==> pointer."""
    top, mid, bot = rows
    for c in range(c0, c1 + 1):
        scr[top * 40 + c] = BOX
        scr[bot * 40 + c] = BOX
    scr[mid * 40 + c0] = BOX
    scr[mid * 40 + c1] = BOX
    put(scr, top, LEFT, "==>")
    inner = c1 - c0 - 1
    put(scr, mid, c0 + 1 + (inner - len(text)) // 2, text)


def screens(layout="A"):
    frame = (IM / "terminal_screen.bin").read_bytes()
    out = []
    for n, (name, text) in enumerate(TERMINALS, 1):
        scr = bytearray(frame)
        centre(scr, 3, f"*** SECURITY TERMINAL {n:02d} ***")
        centre(scr, 5, name)
        if layout == "A":
            lines = textwrap.wrap(text, 24)
            if len(lines) > 6:
                sys.exit(f"{name}: text needs {len(lines)} lines, layout A has 6")
            top, bottom = lines[:3], lines[3:]
            for i, line in enumerate(top):
                centre(scr, 7 + i, line)
            box(scr, (10, 11, 12), 10, 30, "ACCESS GRANTED")
            for i, line in enumerate(bottom):
                centre(scr, 13 + i, line)
        else:
            lines = textwrap.wrap(text, 26)
            if len(lines) > 6:
                sys.exit(f"{name}: text needs {len(lines)} lines, layout B has 6")
            for i, line in enumerate(lines):
                centre(scr, 7 + i, line)
            box(scr, (13, 14, 15), 10, 30, "ACCESS GRANTED")
        put(scr, 17, 10, "LOG OFF.")
        out.append(bytes(scr))
    return out


def charset():
    cs = bytearray((IM / "charset_lift.bin").read_bytes())
    for ch, rows in EXTRA_GLYPHS.items():
        if any(cs[ch * 8:ch * 8 + 8]):
            sys.exit(f"character ${ch:02x} is not free in the lift charset")
        cs[ch * 8:ch * 8 + 8] = bytes(rows)
    return bytes(cs)


def preview(layout):
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from extract import PAL  # noqa: E402
    from PIL import Image
    cs = charset()
    col = (IM / "terminal_colram.bin").read_bytes()
    spr = (IM / "terminal_sprites.bin").read_bytes()
    inc = (IM / "terminal.inc").read_text()
    val = {}
    for line in inc.splitlines():
        if "=" in line and not line.startswith(";") and "." not in line.split("=")[0]:
            k, v = line.split("=")
            val[k.strip()] = int(v.split(";")[0])
    xs = [int(x) for x in inc.split("term_spr_x   .word")[1].splitlines()[0].split(",")]
    ys = [int(x) for x in inc.split("term_spr_y   .byte")[1].splitlines()[0].split(",")]
    bl = [int(x) for x in inc.split("term_spr_blk .byte")[1].split(";")[0].split(",")]
    ims = []
    for scr in screens(layout):
        im = Image.new("RGB", (384, 272), PAL[val["TERM_BORDER"]])
        px = im.load()
        for r in range(25):
            for c in range(40):
                ch, cr = scr[r * 40 + c], col[r * 40 + c] & 15
                for y in range(8):
                    v = cs[ch * 8 + y]
                    X, Y = 32 + c * 8, 35 + r * 8 + y
                    if cr & 8:
                        for p in range(4):
                            b = (v >> (6 - 2 * p)) & 3
                            cc = {0: val["TERM_BG"], 1: val["TERM_MC1"], 2: val["TERM_MC2"], 3: cr & 7}[b]
                            px[X + 2 * p, Y] = px[X + 2 * p + 1, Y] = PAL[cc]
                    else:
                        for k in range(8):
                            px[X + k, Y] = PAL[cr if v & (0x80 >> k) else val["TERM_BG"]]
        for i in range(8):
            blk = spr[bl[i] * 64:bl[i] * 64 + 63]
            for y in range(21):
                for x in range(24):
                    if blk[y * 3 + x // 8] & (0x80 >> (x % 8)):
                        X, Y = xs[i] + 8 + x, ys[i] - 15 + y
                        if 0 <= X < 384 and 0 <= Y < 272:
                            px[X, Y] = PAL[val["TERM_SPR_COL"]]
        ims.append(im)
    sheet = Image.new("RGB", (3 * 384 + 16, 2 * 272 + 8), (40, 40, 40))
    for k, im in enumerate(ims):
        sheet.paste(im, ((k % 3) * 392, (k // 3) * 280))
    out = ROOT / "build" / "shots" / f"terminals_{layout}.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    print(f"wrote {out}")


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "preview":
        preview(sys.argv[2] if len(sys.argv) > 2 else "A")
    else:
        sys.exit(__doc__)
