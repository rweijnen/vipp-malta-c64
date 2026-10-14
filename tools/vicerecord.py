"""Record a VICE session while the user plays: VICE runs at normal speed with
sound and joystick port 2 on the numeric keypad (8/2/4/6 move, 0 or 5 fire).
Four times a second the emulator is paused for a few milliseconds and the
sprite state, VIC/CIA2 bank, $d018 and SID registers are logged; every 2 s a
screenshot, every 5 s a full VICE snapshot (.vsf), every 10 s a RAM dump. Ends when the VICE window is closed
or after --minutes.

usage: vicerecord.py IMAGE OUTDIR [--ntsc] [--warp-load S] [--minutes M]
                     [--config VICERC]   (e.g. tools/vice-config/joy-cursor.vicerc:
                                          cursor keys + space = joystick 2)
"""
import argparse
import json
import socket
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from vicesession import parse_mem  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
X64SC = ROOT / "tools/vice/GTK3VICE-3.9-win64/bin/x64sc.exe"
PORT = 6510


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("outdir")
    ap.add_argument("--ntsc", action="store_true")
    ap.add_argument("--warp-load", type=float, default=25)
    ap.add_argument("--minutes", type=float, default=10)
    ap.add_argument("--config")
    a = ap.parse_args()
    out = Path(a.outdir)
    out.mkdir(parents=True, exist_ok=True)
    try:
        socket.create_connection(("127.0.0.1", PORT), timeout=0.5).close()
        raise SystemExit(f"port {PORT} is in use: close the other VICE (x64sc) first")
    except OSError:
        pass
    args = [str(X64SC), "-ntsc" if a.ntsc else "-pal"]
    if a.config:
        # no -default here: it would reset the settings loaded from the config
        args += ["-config", str(Path(a.config).resolve())]
    else:
        args += ["-default", "-joydev2", "1"]      # numeric keypad = joystick 2
    args += [
            "-remotemonitor", "-remotemonitoraddress", f"ip4://127.0.0.1:{PORT}",
            "-warp", "-autostart", a.image]
    proc = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    sock = None
    try:
        for _ in range(100):
            try:
                sock = socket.create_connection(("127.0.0.1", PORT), timeout=2)
                break
            except OSError:
                time.sleep(0.1)
        if sock is None:
            raise SystemExit("could not connect to the VICE remote monitor")
        sock.settimeout(30)

        def cmd(c):
            sock.sendall((c + "\n").encode())
            buf = b""
            while True:
                chunk = sock.recv(65536)
                if not chunk:
                    raise ConnectionError("closed")
                buf += chunk
                lines = buf.splitlines()
                if lines and lines[-1].startswith(b"(C:$"):
                    sock.settimeout(0.05)
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

        def mem(start, end):
            return parse_mem(cmd(f"m {start:04x} {end:04x}"), start, end)

        time.sleep(a.warp_load)
        cmd("warp off")
        sock.sendall(b"x\n")
        print("VICE is running: play now (joystick 2 on the keys you chose).")
        print("Close the VICE window when done.", flush=True)

        samples = []
        t0 = time.time()
        n = 0
        while time.time() - t0 < a.minutes * 60 and proc.poll() is None:
            time.sleep(0.25)
            try:
                vic = mem(0xd000, 0xd02e)
                cia2 = mem(0xdd00, 0xdd00)
                sid = mem(0xd400, 0xd418)
                bank = (3 - (cia2[0] & 3)) * 0x4000 if cia2 else 0
                screen = bank + ((vic[0x18] >> 4) * 0x400) if len(vic) > 0x18 else 0
                ptr = mem(screen + 0x3f8, screen + 0x3ff)
                ptr_4000 = mem(0x43f8, 0x43ff)      # where Impossible Mission writes them
                if len(vic) != 0x2f:
                    raise SystemExit(f"monitor parse error: got {len(vic)} VIC bytes")
                samples.append(dict(t=round(time.time() - t0, 2), vic=vic, dd00=cia2,
                                    screen=screen, ptr=ptr, ptr4000=ptr_4000, sid=sid))
                if n % 8 == 0:
                    cmd(f'screenshot "{(out / f"shot_{n // 8:04d}.png").as_posix()}" 2')
                if n % 20 == 0:             # full machine state, restorable with undump
                    cmd(f'dump "{(out / f"snap_{n // 20:03d}.vsf").as_posix()}"')
                if n % 40 == 0:
                    cmd("bank ram")
                    cmd(f'save "{(out / f"ram_{n // 40:03d}.bin").as_posix()}" 0 0000 ffff')
                    cmd("bank cpu")
                sock.sendall(b"x\n")
            except TimeoutError:
                # a slow monitor answer is no reason to stop recording: report
                # it, let the emulator run again and carry on
                print(f"warning: monitor timeout at {time.time() - t0:.0f} s, continuing", flush=True)
                try:
                    sock.sendall(b"x\n")
                except OSError:
                    break
                n += 1
                continue
            except (ConnectionError, OSError):
                if proc.poll() is None:
                    print(f"error: monitor connection lost at {time.time() - t0:.0f} s", flush=True)
                break
            n += 1
            if n % 40 == 0:
                (out / "samples.json").write_text(json.dumps(samples))
        (out / "samples.json").write_text(json.dumps(samples))
        print(f"recorded {len(samples)} samples in {time.time() - t0:.0f} s")
    finally:
        try:
            if sock and proc.poll() is None:
                sock.sendall(b"quit\n")
                time.sleep(0.5)
        except OSError:
            pass
        if proc.poll() is None:
            proc.kill()
        proc.wait()


if __name__ == "__main__":
    main()
