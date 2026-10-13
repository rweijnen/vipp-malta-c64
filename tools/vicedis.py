"""Disassemble / dump ranges of a RAM dump with VICE's monitor, without
running the program: VICE starts paused, the dump is loaded into RAM, then
each argument range is disassembled ("d") or shown as memory ("m").

usage: vicedis.py RAMDUMP d:8700-8780 m:9700-9720 ...
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from vicesession import Vice   # noqa: E402


def main():
    dump = Path(sys.argv[1]).resolve()
    with Vice(None) as v:
        v.cmd("r")
        v.cmd("bank ram")
        v.cmd(f'l "{dump.as_posix()}" 0')
        for spec in sys.argv[2:]:
            kind, rng = spec.split(":")
            a, b = rng.split("-")
            out = v.cmd(f"{kind} {a} {b}")
            print(f"===== {spec}")
            for line in out.splitlines():
                if line.startswith("(C:"):
                    continue
                print(line)


if __name__ == "__main__":
    main()
