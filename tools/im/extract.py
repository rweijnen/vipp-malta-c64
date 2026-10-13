"""Extract Impossible Mission assets (Epyx, 1984) from a memory dump of the
running game, for the private VIPP event demo. Input is a RAM dump made with
VICE after the game loaded (the files on disk are packed). Writes to
assets/im/ (not in git) plus a preview sheet.

Data layout (VIC bank 1, $4000-$7fff), found by tracing the game:
  agent    sprite blocks $80-$bf: 3 hires pieces per frame (sprite 2 body,
           3 legs, 1 white overlay). 28 frames, frame -> first block at
           $8d41. Frames 0-13 run (7 poses x 2 arm variants, overlay +1 for
           frames 7-13), 14 standing, 15 facing camera, 16-27 somersault
           (played 27 -> 16, per-frame cumulative piece deltas: dy1 $8d05,
           dy2 $8d11, dy3 $8d1d, dx1/2 $8d29, dx3 $8d35; frames 20-25 have no
           body piece: legs = base, overlay = base+1). Byte 63 of a block
           records its current mirroring (bit-reverse table at $c500).
  robots   sprite blocks $c0-$c6, multicolor (colour 13, mc 6 / 3)
  icons    sprite blocks $10-$1f (zap bolt $14-$17)
  charsets $4800 (elevator/corridor), $5000 (rooms), multicolor
  speech   $e000-$f77f (played through the volume register, code $7d00-)

usage: extract.py RAMDUMP [--room SNAPDIR] [--out assets/im]
"""
import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
PAL = [(0, 0, 0), (255, 255, 255), (0x81, 0x33, 0x38), (0x75, 0xce, 0xc8),
       (0x8e, 0x3c, 0x97), (0x56, 0xac, 0x4d), (0x2e, 0x2c, 0x9b), (0xed, 0xf1, 0x71),
       (0x8e, 0x50, 0x29), (0x55, 0x38, 0x00), (0xc4, 0x6c, 0x71), (0x4a, 0x4a, 0x4a),
       (0x7b, 0x7b, 0x7b), (0xa9, 0xff, 0x9f), (0x70, 0x6d, 0xeb), (0xb2, 0xb2, 0xb2)]
REV = [int(f"{i:08b}"[::-1], 2) for i in range(256)]


def sb(v):
    return v - 256 if v > 127 else v


class Ram:
    def __init__(self, path):
        data = Path(path).read_bytes()
        if len(data) != 65538:
            raise SystemExit(f"{path}: expected a 64 KB VICE RAM dump (+2 byte address)")
        self.m = data[2:]

    def __getitem__(self, k):
        return self.m[k]

    def block(self, n, bank=0x4000):
        a = bank + n * 64
        return self.m[a:a + 64]


def agent_tables(ram):
    return dict(
        base=[ram[0x8d41 + i] for i in range(28)],
        dy1=[sb(ram[0x8d05 + i]) for i in range(12)],
        dy2=[sb(ram[0x8d11 + i]) for i in range(12)],
        dy3=[sb(ram[0x8d1d + i]) for i in range(12)],
        dx12=[sb(ram[0x8d29 + i]) for i in range(12)],
        dx3=[sb(ram[0x8d35 + i]) for i in range(12)],
    )


def normalised_block(ram, n, ref_flag):
    """Block n with its pixels in the reference facing (un-mirrored)."""
    d = bytearray(ram.block(n))
    if d[63] != ref_flag:
        for y in range(21):
            a, b, c = d[y * 3:y * 3 + 3]
            d[y * 3:y * 3 + 3] = bytes([REV[c], REV[b], REV[a]])
        d[63] = ref_flag
    return bytes(d)


def agent_frames(t):
    """Per frame: list of (sprite, block offset from $80, x, y). Somersault
    positions follow the game: drawn frame f carries the deltas of frames
    27..f+1."""
    frames = {}
    for f in range(16):
        b = t["base"][f] - 0x80
        frames[f] = [(2, b, 0, 0), (3, b + 1, 0, 21), (1, b + 2 + (1 if 7 <= f <= 13 else 0), 0, 12)]
    pos = {1: [0, 12], 2: [0, 0], 3: [0, 21]}
    prev = None
    for f in range(27, 15, -1):
        if prev is not None:
            i = prev - 16
            pos[1][1] += t["dy1"][i]; pos[2][1] += t["dy2"][i]; pos[3][1] += t["dy3"][i]
            pos[1][0] += t["dx12"][i]; pos[2][0] += t["dx12"][i]; pos[3][0] += t["dx3"][i]
        b = t["base"][f] - 0x80
        if 20 <= f <= 25:
            frames[f] = [(3, b, *pos[3]), (1, b + 1, *pos[1])]
        else:
            frames[f] = [(2, b, *pos[2]), (3, b + 1, *pos[3]), (1, b + 2, *pos[1])]
        prev = f
    return frames


def draw_hires(d, data, x0, y0, col, sc):
    for y in range(21):
        for k in range(3):
            v = data[y * 3 + k]
            for bit in range(8):
                if v & (0x80 >> bit):
                    X, Y = x0 + k * 8 + bit, y0 + y
                    d.rectangle((X * sc, Y * sc, (X + 1) * sc - 1, (Y + 1) * sc - 1), fill=PAL[col])


def draw_mc(d, data, x0, y0, cols, sc):
    for y in range(21):
        for k in range(3):
            v = data[y * 3 + k]
            for p in range(4):
                bits = (v >> (6 - 2 * p)) & 3
                if bits:
                    X, Y = x0 + k * 8 + p * 2, y0 + y
                    d.rectangle((X * sc, Y * sc, (X + 2) * sc - 1, (Y + 1) * sc - 1), fill=PAL[cols[bits]])


def render_screen(ram, colram, screen, charset, bg, mc1, mc2):
    im = Image.new("RGB", (320, 200))
    px = im.load()
    for r in range(25):
        for c in range(40):
            ch = ram[screen + r * 40 + c]
            cr = colram[r * 40 + c] & 15
            for y in range(8):
                v = ram[charset + ch * 8 + y]
                if cr & 8:
                    for p in range(4):
                        bits = (v >> (6 - 2 * p)) & 3
                        cc = {0: bg, 1: mc1, 2: mc2, 3: cr & 7}[bits]
                        px[c * 8 + p * 2, r * 8 + y] = px[c * 8 + p * 2 + 1, r * 8 + y] = PAL[cc]
                else:
                    for k in range(8):
                        px[c * 8 + k, r * 8 + y] = PAL[cr if v & (0x80 >> k) else bg]
    return im


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ramdump")
    ap.add_argument("--room", help="dir with ram.bin + colram.bin + vic.json of a room")
    ap.add_argument("--out", default=str(ROOT / "assets" / "im"))
    a = ap.parse_args()
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    ram = Ram(a.ramdump)

    t = agent_tables(ram)
    if t["base"][:7] != [0x80, 0x84, 0x88, 0x8c, 0x90, 0x94, 0x98]:
        raise SystemExit(f"agent frame table not where expected: {t['base'][:7]}")
    for k in ("dy1", "dy2", "dy3"):
        if sum(t[k]) != 0:
            raise SystemExit(f"somersault {k} does not sum to 0: {t[k]}")
    ref = ram.block(0x80)[63]
    agent = b"".join(normalised_block(ram, 0x80 + i, ref) for i in range(64))
    (out / "agent_sprites.bin").write_bytes(agent)
    frames = agent_frames(t)
    (out / "agent.json").write_text(json.dumps(dict(tables=t, frames=frames, facing_flag=ref), indent=1))
    (out / "robot_sprites.bin").write_bytes(b"".join(ram.block(0xc0 + i) for i in range(7)))
    (out / "icon_sprites.bin").write_bytes(b"".join(ram.block(0x10 + i) for i in range(16)))
    (out / "charset_rooms.bin").write_bytes(bytes(ram.m[0x5000:0x5800]))
    (out / "charset_elevator.bin").write_bytes(bytes(ram.m[0x4800:0x5000]))
    (out / "speech.bin").write_bytes(bytes(ram.m[0xe000:0xf780]))
    (out / "speech_player_7d00.bin").write_bytes(bytes(ram.m[0x7d00:0x8000]))

    # preview sheet
    sc = 3
    sheet = Image.new("RGB", (1500, 760), (24, 24, 48))
    d = ImageDraw.Draw(sheet)
    d.text((8, 4), "Impossible Mission - extracted assets (agent frames 0-27, robots, icons, room)", fill=(255, 255, 0))
    blocks = {i: agent[i * 64:(i + 1) * 64] for i in range(64)}
    for f in range(28):
        cx, cy = 8 + (f % 14) * 106, 24 + (f // 14) * 110
        pieces = frames[f]
        minx = min(p[2] for p in pieces)
        for spr, b, x, y in sorted(pieces, key=lambda p: p[0] != 1):
            col = 1 if spr == 1 else 11
            draw_hires(d, blocks[b], (cx // sc) + 2 + x - minx, (cy // sc) + 6 + y, col, sc)
        d.text((cx, cy + 96), f"{f}", fill=(255, 255, 0))
    for i in range(7):
        draw_mc(d, ram.block(0xc0 + i), (8 + i * 90) // sc, 260 // sc, {1: 6, 2: 13, 3: 3}, sc)
    for i in range(16):
        draw_hires(d, ram.block(0x10 + i), (8 + i * 90) // sc, 340 // sc, 1, sc)
    if a.room:
        rd = Path(a.room)
        rram = Ram(rd / "ram.bin")
        colram = (rd / "colram.bin").read_bytes()[2:]
        vic = json.loads((rd / "vic.json").read_text())
        room = render_screen(rram, colram, 0x4000, 0x5000, vic["bg"], vic["mc1"], vic["mc2"])
        (out / "room_test_screen.bin").write_bytes(bytes(rram.m[0x4000:0x4000 + 1000]))
        (out / "room_test_colram.bin").write_bytes(bytes(b & 15 for b in colram[:1000]))
        (out / "room_test.inc").write_text(
            f"ROOM_TEST_BG = {vic['bg']}\nROOM_TEST_MC1 = {vic['mc1']}\nROOM_TEST_MC2 = {vic['mc2']}\n")
        sheet.paste(room.resize((640, 400), Image.NEAREST), (820, 340))
        room.save(out / "room_preview.png")
    sheet.save(out / "preview.png")
    print(f"wrote {out}: agent (64 blocks, 28 frames), robots, icons, charsets, speech ({0xf780 - 0xe000} bytes)")


if __name__ == "__main__":
    main()
