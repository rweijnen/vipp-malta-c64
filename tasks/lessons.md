# Lessons

- Show visual changes (logo, font, motion) as preview images first and wait for approval before building them into the demo.
- VICE test runs with -warp open visible, flickering windows and give unreliable screenshots (frame skipping). Use tools/vicemon.py (remote monitor, breakpoint on irq_bottom) for clean full-frame captures; it always closes VICE.
- Never leave VICE stopped in the monitor (a breakpoint without a script driving it hangs the window).
