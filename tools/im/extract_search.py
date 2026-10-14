"""The "Searching" box of the original Impossible Mission, from a VICE snapshot
taken while the agent searches a piece of furniture.

The box (as traced): 8 x 4 characters of the room screen above the agent,
the top and bottom row solid ($52), the middle rows characters $00-$0f of the
room charset, which the game redraws: "Searching" in the background colour
on solid ink, under it a bar (pixel rows 5-7 of the lower character row)
that empties from the left while searching. Colour 1 (white, hires).

usage: extract_search.py SEARCH_SNAPSHOT.vsf [--out assets/im]
writes search_box.bin: the 16 characters (128 bytes) with the bar full
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from vicesession import Vice  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent.parent


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
    print(f"search box found at row {i // 40}, column {i % 40}: wrote search_box.bin")


if __name__ == "__main__":
    main()
