"""Fail when two parts of the program are assembled at the same address.

64tass silently lets a later section overwrite an earlier one in the output
file (this once put the mission's agent tables over the music's SID stubs).
This reads the listing (64tass -L) and reports every address emitted twice.

usage: check_overlap.py build/vipp.lst
"""
import re
import sys
from pathlib import Path


def main():
    lst = Path(sys.argv[1]).read_text(errors="replace").splitlines()
    owner = {}
    clashes = []
    for no, line in enumerate(lst, 1):
        m = re.match(r"^[.>]([0-9a-f]{4})\t((?:[0-9a-f]{2} ?)+)", line)
        if not m:
            continue
        adr = int(m.group(1), 16)
        n = len(m.group(2).split())
        for a in range(adr, adr + n):
            if a in owner:
                clashes.append((a, owner[a], no))
            else:
                owner[a] = no
    if clashes:
        first = {}
        for a, l1, l2 in clashes:
            first.setdefault((l1, l2), a)
        for (l1, l2), a in list(first.items())[:10]:
            print(f"overlap at ${a:04x}: listing line {l1}: {lst[l1 - 1][:70]!r}")
            print(f"            and listing line {l2}: {lst[l2 - 1][:70]!r}")
        sys.exit(f"{len(clashes)} bytes assembled twice: see above")
    print(f"no overlaps ({len(owner)} bytes)")


if __name__ == "__main__":
    main()
