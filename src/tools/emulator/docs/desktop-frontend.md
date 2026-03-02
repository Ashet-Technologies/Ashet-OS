# Desktop Frontend

Status: **Stub** — `src/main-desktop.zig` currently prints "Hello, World!" and exits.

## Headless/Terminal Mode (~3-4h)

- [ ] **CLI argument parsing** (~1h) — Accept ROM file path, RAM size, optional block device image paths.
- [ ] **ROM loading** (~30min) — Read binary file into memory, pass to emulator as ROM.
- [ ] **Execution loop** (~1h) — Step CPU in a loop, handle EBREAK/ECALL/errors as exit conditions.
- [ ] **Debug output to terminal** (~15min) — Wire debug peripheral writer to stdout.

## Graphical Mode (additional ~12-16h)

Requires a display library (SDL2, raylib, or similar).

- [ ] **Window creation + event loop** (~3-4h) — Open a 640x400 window (or scaled), run main loop with frame timing.
- [ ] **Framebuffer rendering** (~3-4h) — Read 250KB framebuffer, map 8-bit palette indices to RGB, blit to window.
- [ ] **Palette implementation** (~1h) — Ashet OS fixed 256-color palette lookup table.
- [ ] **Keyboard input** (~2h) — Map host key events (SDL scancodes) to HID usage codes, push into keyboard peripheral FIFO.
- [ ] **Mouse input** (~1h) — Map host mouse position/buttons to mouse peripheral registers.
- [ ] **Block device file I/O** (~1h) — Open image files at startup, read/write 512-byte blocks on peripheral command.

## Total

- Headless CLI: ~3-4h
- Full graphical: ~16-20h
