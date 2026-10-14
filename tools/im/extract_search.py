"""The "Searching" box of the original Impossible Mission, from a VICE snapshot
taken while the agent searches a piece of furniture.

The box (as traced): 8 x 4 characters of the room screen above the agent,
the top and bottom row solid ($52), the middle rows characters $00-$0f of the
room charset, which the game redraws: "Searching" in the background colour
on solid ink, under it a bar (pixel rows 5-7 of the lower character row)
that empties from the left while searching. Colour 1 (white, hires).

When the bar has run out the box says "Nothing here." (or what was found):
this tool lets the search run on (joystick held up) and saves that box too.

usage: extract_search.py SEARCH_SNAPSHOT.vsf [--out assets/im]
writes search_box.bin: the 16 characters (128 bytes) with the bar full,
       search_nothing.bin: the "Nothing here." box: its 8 x 4 screen codes
       (32 bytes) and the 18 characters it uses ($00-$11, 144 bytes)
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from vicesession import Vice  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent.parent
JOY_SITES = [0x3a3c, 0x3a7c, 0x3a85, 0x3aa4, 0x3b1e, 0x3e17, 0x7263, 0x81ea, 0x81f1,
             0x87f1, 0x8849, 0x98b8, 0x99c7, 0x9f5d, 0x9f68, 0x9f89, 0xa808, 0xaccf]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("snapshot")
    ap.add_argument("--out", default=str(ROOT / "assets" / "im"))
    a = ap.parse_args()
    with Vice(None) as v:
        v.cmd("r")
        v.cmd(f'undump "{Path(a.snapshot).resolve().as_posix()}"')
        scr = v.peek(0x4000, 0x43e7)
        chars = v.peek(0x5000, 0x507f)
        # let the search run on: every joystick read says "up"
        for adr in JOY_SITES:
            if v.peek(adr, adr + 2) == [0xad, 0x00, 0xdc]:
                v.poke(adr, 0xa9, 0xfe, 0xea)
        nothing = None
        for _ in range(40):
            v.run(0.25)
            now = v.peek(0x5000, 0x507f)
            if now[:64] != chars[:64]:          # the text changed: let it
                v.run(1.0)                      # finish drawing
                nothing = v.peek(0x5000, 0x508f)
                nscr = v.peek(0x4000, 0x43e7)
                break
        if nothing is None:
            sys.exit("the search did not end with a message within 10 s")
    # find the box: a row with chars 0-7 in a row, and 8-15 under it
    for i in range(1000 - 48):
        if scr[i:i + 8] == list(range(8)) and scr[i + 40:i + 48] == list(range(8, 16)):
            break
    else:
        sys.exit("no Searching box on this snapshot's screen")
    box = bytearray(chars)
    for c in range(8, 16):              # the bar: pixel rows 5-7 of chars 8-15, full
        for y in (5, 6, 7):
            box[c * 8 + y] = 0xff
    (Path(a.out) / "search_box.bin").write_bytes(bytes(box))
    top = i - 40                        # the box: from the solid row above
    layout = [nscr[top + r * 40 + c] for r in range(4) for c in range(8)]
    if any(c > 0x11 and c != 0x52 for c in layout):
        sys.exit(f"unexpected characters in the Nothing here box: {layout}")
    (Path(a.out) / "search_nothing.bin").write_bytes(bytes(layout) + bytes(nothing))
    print(f"search box found at row {i // 40}, column {i % 40}: wrote search_box.bin, search_nothing.bin")


if __name__ == "__main__":
    main()
