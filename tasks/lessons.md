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
