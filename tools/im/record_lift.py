"""Record a lift ride of the original Impossible Mission for extract_lift.py.

Input: a VICE snapshot (.vsf) taken while the agent stands in the lift at the
top of a shaft (record one with tools/vicerecord.py while playing your own
copy). The joystick reads are forced to "down" and every frame (at the game's
IRQ, $82e7, line 255) the upper screen rows, their colours and the SID are
saved. Also writes the RAM and colour RAM of the start state.

usage: record_lift.py SNAPSHOT.vsf OUTDIR [--frames N]
writes OUTDIR/lift.ram (VICE save: 2-byte address + 64 KB), OUTDIR/lift.col,
       OUTDIR/ride.json
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from vicesession import Vice  # noqa: E402

# every "lda $dc00" (joystick port 2) in the game
JOY_SITES = [0x3a3c, 0x3a7c, 0x3a85, 0x3aa4, 0x3b1e, 0x3e17, 0x7263, 0x81ea, 0x81f1,
             0x87f1, 0x8849, 0x98b8, 0x99c7, 0x9f5d, 0x9f68, 0x9f89, 0xa808, 0xaccf]
JOY_DOWN = 0xfd


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("snapshot")
    ap.add_argument("outdir")
    ap.add_argument("--frames", type=int, default=300)
    a = ap.parse_args()
    out = Path(a.outdir)
    out.mkdir(parents=True, exist_ok=True)
    with Vice(None) as v:
        v.cmd("r")
        v.cmd(f'undump "{Path(a.snapshot).resolve().as_posix()}"')
        if v.peek(0xfffe, 0xffff) != [0xe7, 0x82]:
            sys.exit("this snapshot is not Impossible Mission in play (IRQ vector is not $82e7)")
        v.save_ram(out / "lift.ram")
        v.cmd(f'save "{(out / "lift.col").as_posix()}" 0 d800 dbe7')
        patched = 0
        for adr in JOY_SITES:
            if v.peek(adr, adr + 2) == [0xad, 0x00, 0xdc]:
                v.poke(adr, 0xa9, JOY_DOWN, 0xea)
                patched += 1
        if patched == 0:
            sys.exit("no joystick reads found to patch: not the expected game version")
        v.cmd("break exec $82e7")
        frames = []
        while len(frames) < a.frames:
            v.go_until_break()
            if v.regs()["line"] < 200:
                continue                    # the game has a second IRQ at line 170
            frames.append(dict(scr=v.peek(0x4000, 0x4000 + 15 * 40 - 1),
                               col=[c & 15 for c in v.peek(0xd800, 0xd800 + 15 * 40 - 1)],
                               sid=v.peek(0xd400, 0xd418)))
            if len(frames) % 50 == 0:
                print(f"{len(frames)} frames", flush=True)
        v.cmd("delete")
    (out / "ride.json").write_text(json.dumps(frames))
    print(f"wrote {out}: lift.ram, lift.col, ride.json ({len(frames)} frames)")


if __name__ == "__main__":
    main()
