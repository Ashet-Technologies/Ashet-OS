# Web/WASM Frontend

Status: **Stub** — `src/main-web.zig` exports an empty `emu_init()` function.

## Dependencies

All MMIO peripherals are implemented. The WASM build target is already configured
in `build.zig`. The frontend needs JS glue to wire browser events to peripheral host APIs.

## Tasks (~8-10h)

- [ ] **WASM-host API design** (~2h) — Define exported functions: `emu_init`, `emu_step`, `emu_get_framebuffer_ptr`, `emu_key_event`, `emu_mouse_event`. Decide on memory ownership (WASM linear memory vs. JS-allocated buffers).
- [ ] **JavaScript/HTML wrapper** (~4-6h) — HTML page with `<canvas>` for framebuffer display. JS code to: load WASM module, fetch ROM binary, call `emu_step` on requestAnimationFrame, render framebuffer to canvas, forward keyboard/mouse events.
- [ ] **ROM loading via JS** (~1h) — Accept ROM binary from fetch or file input, pass pointer into WASM memory for emulator init.
- [ ] **Framebuffer export** (~1h) — Expose framebuffer memory region to JS via `pixels()` pointer. JS reads 8-bit pixels, applies palette, writes to canvas ImageData. Check flush flag via exported function.
