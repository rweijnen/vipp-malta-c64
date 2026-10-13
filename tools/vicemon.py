"""Drive VICE x64sc through its remote text monitor for repeatable checks.

Starts the demo, waits until it runs, then stops on a breakpoint for a number
of consecutive hits. On each hit it saves a screenshot (and can run extra
monitor commands, whose output is printed). VICE is always closed at the end,
also on errors, so no window stays behind.

usage: vicemon.py PRG ADDR_HEX FRAMES OUTPREFIX [--until ADDR_HEX] [--skip N]
                  [--no-shot] [extra monitor cmds ...]

  --until ADDR  first wait until code at ADDR runs (e.g. start_explosion)
  --skip N      let N hits of ADDR pass before capturing
  --no-shot     no screenshots (only the extra commands)
  --every N     only take a screenshot on every Nth hit
  --boot S      seconds to let it boot before setting breakpoints (default 6)
  --until-hits N  wait for the Nth time the --until code runs (default 1)
  --watch       ADDR is a memory address: stop when it is written (not run)
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
    ap.add_argument("prg")
    ap.add_argument("addr")
    ap.add_argument("frames", type=int)
    ap.add_argument("prefix")
    ap.add_argument("--until")
    ap.add_argument("--skip", type=int, default=0)
    ap.add_argument("--no-shot", action="store_true")
    ap.add_argument("--every", type=int, default=1)
    ap.add_argument("--boot", type=float, default=6)
    ap.add_argument("--until-hits", type=int, default=1)
    ap.add_argument("--watch", action="store_true")
    ap.add_argument("extra", nargs="*")
    a = ap.parse_args()

    try:                                    # a leftover VICE would answer here
        socket.create_connection(("127.0.0.1", PORT), timeout=0.5).close()
        raise SystemExit(f"port {PORT} is in use: close the other VICE (x64sc) first")
    except OSError:
        pass
    proc = subprocess.Popen([str(X64SC), "-pal", "-default", "-sounddev", "dummy",
                             "-remotemonitor", "-remotemonitoraddress", f"ip4://127.0.0.1:{PORT}",
                             "-autostartprgmode", "1", "-autostart", a.prg],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
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

        def read_until_prompt():
            # The prompt can arrive before the command output, so read until a
            # prompt has been seen and the line has then been quiet for 0.3 s.
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

        def cmd(c):
            sock.sendall((c + "\n").encode())
            return read_until_prompt()

        time.sleep(a.boot)                  # let it boot and start the demo
        cmd("r")                            # any command pauses the emulator
        if a.until:
            cmd(f"break exec ${a.until}")
            for _ in range(a.until_hits):
                cmd("x")                    # runs until that code is reached
            cmd("delete")
        cmd(f"watch store ${a.addr}" if a.watch else f"break exec ${a.addr}")
        for _ in range(a.skip):
            cmd("x")
        for i in range(a.frames):
            cmd("x")
            if not a.no_shot and i % a.every == 0:
                cmd(f'screenshot "{a.prefix}_{i}.png" 2')
            for e in a.extra:
                print(cmd(e))
        sock.sendall(b"quit\n")
        time.sleep(0.5)
    finally:
        if proc.poll() is None:
            proc.kill()
        proc.wait()


if __name__ == "__main__":
    main()
