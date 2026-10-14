# Lessons

- Show visual changes (logo, font, motion) as preview images first and wait for approval before building them into the demo.
- VICE test runs with -warp open visible, flickering windows and give unreliable screenshots (frame skipping). Use tools/vicemon.py (remote monitor, breakpoint on irq_bottom) for clean full-frame captures; it always closes VICE.
- Never leave VICE stopped in the monitor (a breakpoint without a script driving it hangs the window).
- Patch scripts: anchor on labels at line start ("\nlabel\n"), never on a bare name: "jsr label" matches first. Keep a backup copy before large patches.
- Bash heredocs mangle "\n" inside Python string literals here: write patch scripts to a file (scratchpad) instead.
- 64tass is case-insensitive by default: a constant GUN_X clashes with a variable gun_x.
- A RAM shadow of the SID breaks music that writes a register twice per frame (gate off/on): use write-through stubs.
- Verify sound changes by recording WAVs in VICE (no -warp: warp mutes sound) and comparing envelopes against the original.
- Prefer targeted captures (break at the event, a few frames, memory dumps) over long screenshot runs.
- Backslashes in heredocs/sed get eaten too ("\v", "\b", "\c" in Windows paths became control bytes): write any text with Windows paths via the Write/Edit tool, never through heredoc + Python string literals. Check with grep for control characters afterwards.
- Python test scripts that print through "| tail" show nothing until the end: run with -u and without tail so a hang shows where it stopped.
- Exomizer has no Windows binaries any more: tools/build-exomizer.bat builds 3.1.2 with MSVC (unistd.h shim; b2buf names the array after its argument).
- VICE `save` RAM dumps start with a 2-byte load address: skip it when analysing (offsets were off by 2).
- VICE monitor "m" output has a text column after 3 spaces that can look like hex: parse only before it (vicesession.parse_mem).
- Packed builds take ~12 s to unpack in VICE: tests must wait for a breakpoint on main_loop, never a fixed sleep (a poke during unpacking corrupts it).
- With -sounddev dummy VICE's SID readback (OSC3) differs from real emulation: test SID behaviour with a wav device.
- Volume-register speech is ~6x quieter on an 8580: detect the model (OSC3 after sawtooth start: 6581 = 3, 8580 = 2) and use the digi boost (test bit + pulse, sustain 15) only there.
- 64tass: `a` is a built-in (accumulator): never use it as a loop variable.
