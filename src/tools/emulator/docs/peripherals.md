# MMIO Peripherals

Status of peripheral implementations in `src/emulator.zig`.

All peripherals are implemented using a vtable-based `Peripheral` interface with
page-indexed `MmioPageTable` dispatch. Each peripheral is a standalone struct with
a bus-facing API (read/write via vtable) and a host-facing API (push data in, poll state).

## Implemented

- [x] **Debug Output** (page 0x41) — Single-byte TX write register.
- [x] **System Info** (page 0x45) — Read-only RAM_SIZE register.
- [x] **Timer/RTC** (page 0x44) — MTIME/RTC with latching. Time pushed by host via `setTime()`.
- [x] **Video Control** (page 0x40) — Write-only FLUSH register. Host polls `isFlushRequested()` / `ackFlush()`.
- [x] **Framebuffer** (pages 0x00–0x3D) — 256,000 bytes (640x400 @ 8bpp), byte-addressable R/W. Host reads via `pixels()`.
- [x] **Keyboard** (page 0x42) — 16-entry FIFO, STATUS/DATA registers. Host pushes via `pushKey(usage, state)`. Deduplicates consecutive identical events.
- [x] **Mouse** (page 0x43) — X/Y/BUTTONS registers. Host pushes via `setState(x, y, buttons)`. Coordinates clamped to screen bounds.
- [x] **Block Device** (pages 0x46, 0x47) — STATUS/SIZE/LBA/COMMAND registers + 512-byte buffer. Async request/response pattern via `getPendingRequest()` / `transferBuffer()` / `complete()`.

## Tests

Unit tests for each peripheral in `tests/peripherals/test_*.zig` (50 tests total),
using the table-driven `testPeripheralAccess` helper from `tests/test_helpers.zig`.
