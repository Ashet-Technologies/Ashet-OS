# MMIO Peripherals

Status of peripheral implementations in `src/emulator.zig`.

## Implemented

- [x] **Debug Output** (page 0x41) — Single-byte TX write register. Fully working.

## Not Implemented

- [ ] **System Info** (page 0x45) — ~15min. Return configured RAM size from a single read-only register.
- [ ] **Timer/RTC** (page 0x44) — ~1h. Read MTIME/RTC from host clock. Implement latching: reading LO latches HI.
- [ ] **Video Control** (page 0x40) — ~30min. Single FLUSH register (write 1 = present, write 0 = blank). Set a dirty flag for the frontend.
- [ ] **Framebuffer** (pages 0x00–0x3D) — ~1-2h. 250KB linear read/write region, byte-addressable. 640x400 @ 8bpp, fixed palette.
- [ ] **Keyboard** (page 0x42) — ~2h. FIFO queue with STATUS (bit 0 = data available) and DATA (pop: bit 31 = down/up, bits 15:0 = HID usage code). Needs host input wiring.
- [ ] **Mouse** (page 0x43) — ~1h. Three read-only registers: X (0–639), Y (0–399), BUTTONS (bits 0–2 = left/right/middle). Needs host input wiring.
- [ ] **Block Device 0** (page 0x46) — ~3h. STATUS/LBA/COMMAND registers + 512-byte buffer at +0x100. File-backed storage. Read/write flow with busy bit.
- [ ] **Block Device 1** (page 0x47) — ~3h. Second instance, same as Block Device 0.

Total: ~12h for all peripherals (emulator logic only, not counting frontend wiring).
