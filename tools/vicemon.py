"""Drive VICE x64sc through its remote text monitor for repeatable checks.

Starts the demo, waits until it runs, then stops on a breakpoint for a number
of consecutive hits. On each hit it can save a screenshot and dump registers.
VICE is always closed at the end (also on errors), so no window stays behind.

usage: vicemon.py PRG ADDR_HEX FRAMES OUTPREFIX [extra monitor cmds ...]
"""
import socket
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
X64SC = ROOT / "tools/vice/GTK3VICE-3.9-win64/bin/x64sc.exe"
PORT = 6510


def main():
    prg, addr, frames, prefix = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
    extra = sys.argv[5:]
    proc = subprocess.Popen([str(X64SC), "-pal", "-default", "-sounddev", "dummy",
                             "-remotemonitor", "-remotemonitoraddress", f"ip4://127.0.0.1:{PORT}",
                             "-autostartprgmode", "1", "-autostart", prg],
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
        sock.settimeout(30)

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
                        sock.settimeout(30)
                    return buf.decode(errors="replace")

        time.sleep(6)                       # let it boot and start the demo
        sock.sendall(b"r\n")                # any command pauses the emulator
        read_until_prompt()
        sock.sendall(f"break exec ${addr}\n".encode())
        read_until_prompt()
        for i in range(frames):
            sock.sendall(b"x\n")
            read_until_prompt()
            sock.sendall(f'screenshot "{prefix}_{i}.png" 2\n'.encode())
            read_until_prompt()
            for e in extra:
                sock.sendall((e + "\n").encode())
                print(read_until_prompt())
        sock.sendall(b"quit\n")
        time.sleep(0.5)
    finally:
        if proc.poll() is None:
            proc.kill()
        proc.wait()


if __name__ == "__main__":
    main()
