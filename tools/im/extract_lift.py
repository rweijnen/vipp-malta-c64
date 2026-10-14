"""Lift / shaft data of the original Impossible Mission for the VIPP Mission,
from a recorded lift ride (tools/im/record_lift.py).

The lift screen (as traced in the original):
  rows 0-14  the shaft view: lift charset ($4800), bg $0c, mc $02/$0a.
             Columns 17-22 are the inside of the shaft (cables, the car on
             rows 4-11) and never scroll; columns 0-16 and 23-39 (rock, the
             shaft walls in columns 16 and 23, corridors) scroll one
             character row every 2 frames.
  rows 15-24 the pocket computer panel: panel charset ($5800), bg 0, mc $0e/$06,
             switched by an IRQ at line 170.
  rock: 2x2 character tiles, top row (k+2, k), bottom row (k+3, k+1) for
        k = 0, 4, ... 28, colour 1. Walls: 20 / 24 / 25 repeating, colour 8.
  corridors: 8 rows (top edge, 5 fill rows, floor, bottom edge); the fill
             colour differs per corridor.

usage: extract_lift.py RIDEDIR [--out assets/im]
writes charset_lift.bin, charset_panel.bin, lift_panel.bin (400 chars + 400
colours), lift_inner.bin (15 rows x 6: chars, then colours), corr_right.bin,
corr_left.bin (8 rows x 17: chars, then colours; fill colour marked $10),
lift_sprites.bin (3 blocks), lift.inc, lift_preview.png
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from extract import render_screen  # noqa: E402
from PIL import Image  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent.parent
SCROLL_COLS = list(range(0, 17)) + list(range(23, 40))
FILL = 0x10


def load_dump(path, size):
    data = Path(path).read_bytes()
    if len(data) != size + 2:
        sys.exit(f"{path}: expected a VICE save of {size} bytes (+2 byte address), got {len(data)}")
    return data[2:]                     # skip the load address


def stitch(frames):
    """World rows (scrolling columns only) from the recorded frames: a frame
    counts when it equals the world at the current or next position (the
    game redraws the view in two halves, so every other frame is mixed)."""
    def rows(f):
        return [(tuple(f["scr"][r * 40 + c] for c in SCROLL_COLS),
                 tuple(f["col"][r * 40 + c] for c in SCROLL_COLS)) for r in range(15)]
    world = rows(frames[0])
    pos = 0
    for f in frames[1:]:
        fr = rows(f)
        for o in (pos, pos + 1):
            n = min(15, len(world) - o)
            if all(fr[r] == world[o + r] for r in range(n)):
                world += fr[n:]
                pos = o
                break
    return world


def corridor(world, side):
    """First complete corridor on a side ('L': columns 0-16, 'R': 23-39) as 8
    rows of 17 chars + colours, the fill colour replaced by the FILL mark."""
    sl = slice(0, 17) if side == "L" else slice(17, 34)
    for i in range(len(world) - 8):
        ch = world[i][0][sl]
        if 0x45 in ch and 0x47 in ch and all(0x28 in world[i + k][0][sl] for k in range(1, 6)):
            rows = [world[i + k] for k in range(8)]
            fill = rows[3][1][sl][8]
            chars = [list(r[0][sl]) for r in rows]
            cols = [[FILL if (1 <= k <= 5 and c == fill) else c for c in r[1][sl]] for k, r in enumerate(rows)]
            return chars, cols, fill, i
    sys.exit(f"no complete corridor on side {side} in the recording: record a longer ride")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ridedir")
    ap.add_argument("--out", default=str(ROOT / "assets" / "im"))
    a = ap.parse_args()
    rd, out = Path(a.ridedir), Path(a.out)
    ram = load_dump(rd / "lift.ram", 65536)
    col = [c & 15 for c in load_dump(rd / "lift.col", 1000)]
    frames = json.loads((rd / "ride.json").read_text())

    scr = ram[0x4000:0x4000 + 1000]
    # sanity: the recording starts at the top of a shaft with the car in view
    if scr[17:23] != bytes([0x3f, 0x40, 0x41, 0x42, 0x43, 0x44]) or scr[4 * 40 + 17] != 0x29:
        sys.exit("lift.ram: expected the agent in the lift at the top of a shaft (ceiling in row 0, car at rows 4-11)")

    (out / "charset_lift.bin").write_bytes(ram[0x4800:0x5000])
    (out / "charset_panel.bin").write_bytes(ram[0x5800:0x6000])
    (out / "lift_panel.bin").write_bytes(scr[600:1000] + bytes(col[600:1000]))
    inner_ch = bytes(scr[r * 40 + c] for r in range(15) for c in range(17, 23))
    inner_co = bytes(col[r * 40 + c] for r in range(15) for c in range(17, 23))
    (out / "lift_inner.bin").write_bytes(inner_ch + inner_co)

    world = stitch(frames)
    info = {}
    for side, name in (("R", "corr_right.bin"), ("L", "corr_left.bin")):
        chars, cols, fill, at = corridor(world, side)
        (out / name).write_bytes(bytes(sum(chars, [])) + bytes(sum(cols, [])))
        info[side] = (fill, at)

    ptr = ram[0x43f8:0x4400]
    blocks = [ptr[0], ptr[7], ptr[6]]          # side lines, car hanger, panel marker
    (out / "lift_sprites.bin").write_bytes(b"".join(ram[0x4000 + b * 64:0x4000 + b * 64 + 64] for b in blocks))

    (out / "lift.inc").write_text(
        "; generated by tools/im/extract_lift.py - do not edit\n"
        "LIFT_BG = $0c\nLIFT_MC1 = $02\nLIFT_MC2 = $0a\n"
        "PANEL_BG = $00\nPANEL_MC1 = $0e\nPANEL_MC2 = $06\n"
        f"CORR_FILL_R = {info['R'][0]}        ; fill colour of the recorded corridors\n"
        f"CORR_FILL_L = {info['L'][0]}\n")

    # preview: the start screen as recorded, and the same rebuilt from the
    # extracted pieces (must look identical in the scrolling columns)
    shot = render_screen(ram, col, 0x4000, 0x4800, 0x0c, 0x02, 0x0a)
    panel = render_screen(ram, col, 0x4000, 0x5800, 0x00, 0x0e, 0x06)
    shot.paste(panel.crop((0, 120, 320, 200)), (0, 120))
    shot.resize((640, 400), Image.NEAREST).save(out / "lift_preview.png")
    print(f"lift: {len(world)} shaft rows stitched, corridors R fill {info['R'][0]} (row {info['R'][1]}), "
          f"L fill {info['L'][0]} (row {info['L'][1]})")


if __name__ == "__main__":
    main()
