"""Let the original Impossible Mission build each of its rooms and save them.

The game builds a room ($a39c, room number in $7e, room data via the pointer
table at $0e70) into a screen buffer at $c100-$c4e7 and the colour RAM, sets
the multicolours $d022/$d023, and keeps the background colour in $8d. This
tool stops the game in a room snapshot (any snapshot taken in a room, e.g.
from tools/vicerecord.py), calls the builder for every room number through a
3 byte stub and saves what it built.

usage: extract_rooms.py ROOM_SNAPSHOT.vsf [--rooms 0-31] [--out assets/im]
writes OUT/rooms.json (per room: screen, colours, bg, mc1, mc2) and
       OUT/rooms_preview.png (all rooms, rendered with the room charset)
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from vicesession import Vice  # noqa: E402
from extract import render_screen  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent.parent
STUB = 0x0340                   # jsr $a39c / brk (cassette buffer, unused by the game)
BUILD_ROOM = 0xa39c


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("snapshot")
    ap.add_argument("--rooms", default="0-31")
    ap.add_argument("--out", default=str(ROOT / "assets" / "im"))
    a = ap.parse_args()
    lo, hi = (int(x) for x in a.rooms.split("-"))
    out = Path(a.out)
    rooms = {}
    with Vice(None) as v:
        v.cmd("r")
        v.cmd(f'undump "{Path(a.snapshot).resolve().as_posix()}"')
        if v.peek(0xfffe, 0xffff) != [0xe7, 0x82]:
            sys.exit("not a snapshot of Impossible Mission in play (IRQ vector is not $82e7)")
        if v.peek(BUILD_ROOM, BUILD_ROOM + 2) != [0xa9, 0x00, 0x85]:
            sys.exit("room builder not found at $a39c: not the expected game version")
        # stop in the main program (not inside the IRQ), then run the stub
        v.cmd("break exec $8606")
        v.go_until_break()
        v.cmd("delete")
        ram = None
        for n in range(lo, hi + 1):
            v.poke(STUB, 0x20, BUILD_ROOM & 0xff, BUILD_ROOM >> 8, 0x00)
            v.poke(0x7e, n)
            v.cmd(f"break exec ${STUB + 3:04x}")
            v.cmd(f"r pc = {STUB:04x}")
            v.sock.settimeout(30)
            try:
                v.go_until_break()
            except TimeoutError:
                sys.exit(f"room {n}: the builder did not return")
            v.sock.settimeout(60)
            v.cmd("delete")
            scr = v.peek(0xc100, 0xc4e7)
            col = [c & 15 for c in v.peek(0xd800, 0xdbe7)]
            bg = v.peek(0x8d)[0] & 15
            mc1, mc2 = (x & 15 for x in v.peek(0xd022, 0xd023))
            # robots ($a68b): up to 4, sprites 4-7, state 6 bytes each at $55
            # (type, ...); positions in the sprite registers. $8e: sprites on.
            vic = v.peek(0xd000, 0xd02e)
            state = v.peek(0x55, 0x6e)
            on = v.peek(0x8e)[0]
            robots = []
            for k in range(4):
                s = 4 + k
                if on & (1 << s):
                    x = vic[2 * s] | (0x100 if vic[0x10] & (1 << s) else 0)
                    robots.append(dict(type=state[6 * k], x=x, y=vic[2 * s + 1], state=state[6 * k:6 * k + 6]))
            ball = None
            if on & 1:
                ball = dict(type=v.peek(0x6e)[0], x=vic[0] | (0x100 if vic[0x10] & 1 else 0), y=vic[1])
            rooms[n] = dict(screen=scr, colour=col, bg=bg, mc1=mc1, mc2=mc2, robots=robots, ball=ball,
                            sprite_mc=[vic[0x25] & 15, vic[0x26] & 15], robot_colours=[c & 15 for c in vic[0x2b:0x2f]])
            print(f"room {n:2d}: bg {bg} mc {mc1}/{mc2} robots " +
                  " ".join(f"(t{r['type']:02x} {r['x']},{r['y']})" for r in robots) + (f" ball {ball}" if ball else ""), flush=True)
            if ram is None:
                v.save_ram(out / "rooms_ram.bin")
                ram = bytearray((out / "rooms_ram.bin").read_bytes()[2:])
                (out / "rooms_ram.bin").unlink()
    (out / "rooms.json").write_text(json.dumps(rooms))

    ims = []
    for n, r in rooms.items():
        m = bytearray(ram)
        m[0xc100:0xc100 + 1000] = bytes(r["screen"])
        ims.append((n, render_screen(m, r["colour"], 0xc100, 0x5000, r["bg"], r["mc1"], r["mc2"])))
    cols = 6
    w, h = 320, 200
    sheet = Image.new("RGB", (cols * (w + 8), ((len(ims) + cols - 1) // cols) * (h + 20)), (40, 40, 40))
    d = ImageDraw.Draw(sheet)
    for k, (n, im) in enumerate(ims):
        x, y = (k % cols) * (w + 8), (k // cols) * (h + 20)
        d.text((x + 4, y + 2), f"room {n}", fill=(255, 255, 0))
        sheet.paste(im, (x, y + 18))
    sheet.save(out / "rooms_preview.png")
    print(f"wrote {out / 'rooms.json'} and rooms_preview.png ({len(rooms)} rooms)")


if __name__ == "__main__":
    main()
