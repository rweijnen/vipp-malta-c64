"""Record animated GIFs (and stills) of the demo in VICE for the README.

VICE runs the program; for each clip the tool waits for a moment in the
program (a label from build/vipp.lst, optionally with a zero page value),
then stops on every frame at an IRQ label and keeps every STEP-th screenshot.
The frames are assembled with Pillow (C64 palette, small files).

usage: vicegif.py OUTDIR
"""
import re
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from vicesession import Vice  # noqa: E402
sys.path.insert(0, str(Path(__file__).resolve().parent / "im"))
from extract import PAL  # noqa: E402
from PIL import Image  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
LST = (ROOT / "build" / "vipp.lst").read_text()


def label(name):
    m = re.search(r"^[.>]([0-9a-f]{4})\t[^\n]*?\t" + name + r"(\s|$)", LST, re.M) or \
        re.search(r"^\.([0-9a-f]{4})\s+" + name + r"$", LST, re.M)
    if not m:
        sys.exit(f"label {name} not in build/vipp.lst: build first")
    return int(m.group(1), 16)


# clip: name, wait for (label, zp address, value) or None, irq label, frames, step
CLIPS = [
    ("demo", None, "irq_bottom", 300, 3),
    ("mission_lift", ("scene_lift", 0x13, 330 & 255), "irq_main", 330, 3),   # back from room 18, the ride
    ("mission_room23", ("scene_room", 0x47, 2), "irq_main", 900, 4),
    ("mission_zap_death", ("die", None, None), "irq_main", 180, 3),
]
STILLS = [
    ("mission_terminal", ("scene_term", 0x47, 0), 25),
    ("mission_search", ("search_start", None, None), 100),
    ("mission_map", ("scene_lift", 0x47, 3), 260),                          # after room 29: the map
]


def wait_for(v, cond):
    adr = label(cond[0])
    v.cmd(f"break exec ${adr:04x}")
    while True:
        v.sock.settimeout(600)
        v.go_until_break()
        if cond[1] is None or v.peek(cond[1])[0] == cond[2]:
            break
    v.cmd("delete")


def frames(v, irq, n, step, tmp):
    v.cmd(f"break exec ${label(irq):04x}")
    out = []
    for k in range(n):
        v.go_until_break()
        if k % step == 0:
            f = tmp / f"f{k:05d}.png"
            v.screenshot(f)
            out.append(Image.open(f).convert("RGB"))
    v.cmd("delete")
    return out


def save_gif(ims, path, step):
    """The C64's 16 colours as the palette; frames before the picture is on
    (a scene switch turns the display off while drawing) are left out."""
    while len(ims) > 1 and len(ims[0].getcolors(100000)) <= 1:
        ims = ims[1:]
    pal = Image.new("P", (1, 1))
    colours = [c for rgb in PAL for c in rgb]
    pal.putpalette(colours + colours[:3] * (256 - len(PAL)))
    q = [im.quantize(palette=pal, dither=Image.Dither.NONE) for im in ims]
    q[0].save(path, save_all=True, append_images=q[1:], duration=int(1000 * step / 50), loop=0, optimize=True)


def main():
    out = Path(sys.argv[1])
    only = set(sys.argv[2:])
    out.mkdir(parents=True, exist_ok=True)
    tmp = Path(tempfile.mkdtemp())
    with Vice(ROOT / "build" / "vipp.prg") as v:
        v.cmd(f"break exec ${label('main_loop'):04x}")
        v.go_until_break()
        v.cmd("delete")
        name, _, irq, n, step = CLIPS[0]               # the demo
        if not only or name in only:
            v.run(2.0)
            save_gif(frames(v, irq, n, step, tmp), out / f"{name}.gif", step)
            print("wrote", name, flush=True)
        v.poke(label("want_mode"), 1)                   # Space: the mission
        todo = CLIPS[1:] + [(s[0], s[1], None, s[2], None) for s in STILLS]
        # in program order (the search still: in the next loop, it is inside the room 23 clip)
        order = ["mission_zap_death", "mission_terminal", "mission_lift", "mission_room23", "mission_map", "mission_search"]
        for name in order:
            if only and name not in only:
                continue
            clip = next(c for c in todo if c[0] == name)
            wait_for(v, clip[1])
            if clip[2] is None:                         # a still: some frames later
                frames(v, "irq_main", clip[3], clip[3] + 1, tmp)
                v.screenshot(out / f"{name}.png")
            else:
                save_gif(frames(v, clip[2], clip[3], clip[4], tmp), out / f"{name}.gif", clip[4])
            print("wrote", name, flush=True)


if __name__ == "__main__":
    main()
