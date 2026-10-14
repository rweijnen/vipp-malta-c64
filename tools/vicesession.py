"""Scriptable VICE x64sc session through the remote text monitor, for
exploring other programs (e.g. extracting data from a game).

    from vicesession import Vice
    with Vice(image, ntsc=True, warp=True) as v:
        v.sleep(40); v.warp(False)
        v.cmd("m 1000 1010")
        v.poke(0xdd03, 0xff)
        v.run(2.0)            # let it run 2 s, then pause again
        v.screenshot("x.png")

VICE is always closed at the end, also on errors. Refuses to start when
another VICE holds the monitor port.
"""
import re
import socket
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
X64SC = ROOT / "tools/vice/GTK3VICE-3.9-win64/bin/x64sc.exe"
PORT = 6510
BINPORT = 6502                  # VICE binary monitor (joystick control)


def parse_mem(out, start, end):
    """Bytes of a monitor "m" listing. Rows look like
    ">C:4000  0e 0c 1e 1c  12 10 16 14  ...   nl^\\rpvt": hex groups are
    separated by 2 spaces, the text column by 3, and that text can look like
    hex ("ca", "fd"), so only the part before the 3 spaces counts. The prompt
    of a stop can precede the first row on the same line."""
    vals = []
    for m in re.finditer(r">C:([0-9a-f]{4})  (.*)", out):
        hexpart = m.group(2).split("   ")[0]
        vals += [int(b, 16) for b in hexpart.split()]
    if len(vals) < end - start + 1:
        raise SystemExit(f"monitor memory read ${start:04x}-${end:04x}: got {len(vals)} bytes")
    return vals[: end - start + 1]


class Vice:
    def __init__(self, image, ntsc=False, warp=False, sound=False, wav=None, sid_model=None):
        """wav: record the sound to this WAV file (normal speed, no warp).
        sid_model: VICE SidModel (0 = 6581, 1 = 8580)."""
        try:
            socket.create_connection(("127.0.0.1", PORT), timeout=0.5).close()
            raise SystemExit(f"port {PORT} is in use: close the other VICE (x64sc) first")
        except OSError:
            pass
        # -default first: placed later it would also reset -ntsc/-pal
        args = [str(X64SC), "-default", "-ntsc" if ntsc else "-pal",
                "-remotemonitor", "-remotemonitoraddress", f"ip4://127.0.0.1:{PORT}",
                "-binarymonitor", "-binarymonitoraddress", f"ip4://127.0.0.1:{BINPORT}",
                # a joystick device on both ports, else VICE ignores joyport values
                "-joydev1", "2", "-joydev2", "2"]
        if wav is not None:
            args += ["-sounddev", "wav", "-soundarg", str(Path(wav).resolve())]
        elif not sound:
            args += ["-sounddev", "dummy"]
        if sid_model is not None:
            args += ["-sidmodel", str(sid_model)]
        if warp:
            args.append("-warp")
        if image is not None:
            args += ["-autostart", str(image)]
        self.proc = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.sock = None
        for _ in range(100):
            try:
                self.sock = socket.create_connection(("127.0.0.1", PORT), timeout=2)
                break
            except OSError:
                time.sleep(0.1)
        if self.sock is None:
            self.close()
            raise SystemExit("could not connect to the VICE remote monitor")
        self.sock.settimeout(60)
        self.paused = False
        self.bin = None
        self.req_id = 0

    # --- low level --------------------------------------------------------
    def _read_prompt(self):
        buf = b""
        while True:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise SystemExit("monitor connection closed")
            buf += chunk
            lines = buf.splitlines()
            if lines and lines[-1].startswith(b"(C:$"):
                self.sock.settimeout(0.3)
                try:
                    while True:
                        more = self.sock.recv(65536)
                        if not more:
                            break
                        buf += more
                except TimeoutError:
                    pass
                finally:
                    self.sock.settimeout(60)
                return buf.decode(errors="replace")

    def cmd(self, c):
        """Run a monitor command (pauses the emulator) and return its output."""
        self.sock.sendall((c + "\n").encode())
        self.paused = True
        return self._read_prompt()

    def go(self):
        """Resume without waiting for a prompt (it only comes when it stops)."""
        self.sock.sendall(b"x\n")
        self.paused = False

    def go_until_break(self):
        """Resume and wait until a checkpoint stops it; returns the stop text."""
        self.sock.sendall(b"x\n")
        self.paused = True
        return self._read_prompt()

    # --- helpers ----------------------------------------------------------
    def sleep(self, s):
        if self.paused:
            self.go()
        time.sleep(s)

    def run(self, s):
        """Let it run s seconds, then pause."""
        self.sleep(s)
        self.cmd("r")

    def warp(self, on):
        self.cmd("warp " + ("on" if on else "off"))

    def peek(self, start, end=None):
        end = start if end is None else end
        out = self.cmd(f"m {start:04x} {end:04x}")
        return parse_mem(out, start, end)

    def poke(self, addr, *vals):
        self.cmd(f"> {addr:04x} " + " ".join(f"{v:02x}" for v in vals))

    def regs(self):
        out = self.cmd("r")
        for line in out.splitlines():
            if line.startswith(".;"):
                f = line.split()
                return dict(pc=int(f[0][2:], 16), a=int(f[1], 16), x=int(f[2], 16),
                            y=int(f[3], 16), line=int(f[8]), cycle=int(f[9]))
        return None

    # --- binary monitor: joystick ---------------------------------------------
    def _bin(self):
        if self.bin is None:
            for _ in range(50):
                try:
                    self.bin = socket.create_connection(("127.0.0.1", BINPORT), timeout=2)
                    break
                except OSError:
                    time.sleep(0.1)
            if self.bin is None:
                raise SystemExit("could not connect to the VICE binary monitor")
            self.bin.settimeout(10)
        return self.bin

    def _bin_request(self, command, body):
        sock = self._bin()
        self.req_id += 1
        rid = self.req_id
        sock.sendall(bytes([0x02, 0x02]) + len(body).to_bytes(4, "little")
                     + rid.to_bytes(4, "little") + bytes([command]) + body)
        while True:                     # skip events until our response arrives
            head = b""
            while len(head) < 12:
                chunk = sock.recv(12 - len(head))
                if not chunk:
                    raise SystemExit("binary monitor connection closed")
                head += chunk
            length = int.from_bytes(head[2:6], "little")
            rtype, err = head[6], head[7]
            resp_id = int.from_bytes(head[8:12], "little")
            body_in = b""
            while len(body_in) < length:
                chunk = sock.recv(length - len(body_in))
                if not chunk:
                    raise SystemExit("binary monitor connection closed")
                body_in += chunk
            if resp_id == rid:
                if err:
                    raise SystemExit(f"binary monitor command ${command:02x} failed: error {err}")
                return body_in

    def joy(self, bits, port=1):
        """Set a joystick: bits 1 up, 2 down, 4 left, 8 right, 16 fire (1 = pressed).
        port: VICE joyport index (0 = control port 1, 1 = control port 2)."""
        self._bin_request(0xa2, port.to_bytes(2, "little") + bits.to_bytes(2, "little"))

    def screenshot(self, path):
        self.cmd(f'screenshot "{Path(path).as_posix()}" 2')

    def save_ram(self, path, start=0x0000, end=0xffff):
        self.cmd("bank ram")
        self.cmd(f'save "{Path(path).as_posix()}" 0 {start:04x} {end:04x}')
        self.cmd("bank cpu")

    def close(self):
        try:
            if self.bin:
                self.bin.close()
        except OSError:
            pass
        try:
            if self.sock:
                self.sock.sendall(b"quit\n")
                time.sleep(0.5)
        except OSError:
            pass
        if self.proc.poll() is None:
            self.proc.kill()
        self.proc.wait()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()
