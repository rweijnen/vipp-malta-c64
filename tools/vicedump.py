"""Explore another program in VICE: autostart it, let it run, then dump the
full memory (64 KB RAM as the CPU sees it with all ROMs off is not possible
from the monitor, so we save RAM via the monitor's bank "ram"), the VIC/SID
registers and a screenshot. VICE is always closed afterwards.

usage: vicedump.py IMAGE OUTDIR [--ntsc] [--run SECONDS] [--warp-load SECONDS]
                   [--after CMD ...]   (monitor commands run before dumping)
"""
import argparse
import socket
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
X64SC = ROOT / "tools/vice/GTK3VICE-3.9-win64/bin/x64sc.exe"
PORT = 6510


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("outdir")
    ap.add_argument("--ntsc", action="store_true")
    ap.add_argument("--run", type=float, default=20, help="real seconds to run before dumping")
    ap.add_argument("--warp-load", type=float, default=0, help="seconds of warp at the start (loading)")
    ap.add_argument("--after", nargs="*", default=[])
    a = ap.parse_args()
    out = Path(a.outdir)
    out.mkdir(parents=True, exist_ok=True)
    try:
        socket.create_connection(("127.0.0.1", PORT), timeout=0.5).close()
        raise SystemExit(f"port {PORT} is in use: close the other VICE (x64sc) first")
    except OSError:
        pass
    args = [str(X64SC), "-ntsc" if a.ntsc else "-pal", "-default", "-sounddev", "dummy",
            "-remotemonitor", "-remotemonitoraddress", f"ip4://127.0.0.1:{PORT}",
            "-autostart", a.image]
    if a.warp_load:
        args.insert(1, "-warp")
    proc = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        sock = None
        for _ in range(100):
            try:
                sock = socket.create_connection(("127.0.0.1", PORT), timeout=2)
                break
            except OSError:
                time.sleep(0.1)
        if sock is None:
            raise SystemExit("could not connect to the VICE remote monitor")
        sock.settimeout(60)

        def cmd(c):
            sock.sendall((c + "\n").encode())
            buf = b""
            while True:
                chunk = sock.recv(65536)
                if not chunk:
                    raise SystemExit("monitor connection closed")
                buf += chunk
                lines = buf.splitlines()
                if lines and lines[-1].startswith(b"(C:$"):
                    sock.settimeout(0.3)
                    try:
                        while True:
                            more = sock.recv(65536)
                            if not more:
                                break
                            buf += more
                    except TimeoutError:
                        pass
                    finally:
                        sock.settimeout(60)
                    return buf.decode(errors="replace")

        if a.warp_load:
            time.sleep(a.warp_load)
            cmd("r")                                # pause first, then switch
            cmd("warp off")
            sock.sendall(b"x\n")                    # resume (no prompt until paused)
        time.sleep(a.run)
        cmd("r")                                    # pause
        log = []
        for c in a.after:
            log.append(f"> {c}\n" + cmd(c))
        log.append("> r\n" + cmd("r"))
        log.append("> io d000\n" + cmd("io d000"))
        log.append("> io d400\n" + cmd("io d400"))
        log.append("> io dc00\n" + cmd("io dc00"))
        log.append("> io dd00\n" + cmd("io dd00"))
        cmd(f'screenshot "{(out / "screen.png").as_posix()}" 2')
        cmd(f'bank ram')
        cmd(f'save "{(out / "ram.bin").as_posix()}" 0 0000 ffff')
        (out / "state.txt").write_text("\n".join(log))
        sock.sendall(b"quit\n")
        time.sleep(0.5)
    finally:
        if proc.poll() is None:
            proc.kill()
        proc.wait()


if __name__ == "__main__":
    main()
