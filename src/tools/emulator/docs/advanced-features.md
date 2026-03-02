# Advanced Features

Optional features needed only if the emulator must run the actual Ashet OS kernel or serve as a development debugger. Not required for running simple test programs and demos.

## CSR Support (~6-10h)

- [ ] **CSR register file** (~2h) — Implement machine-mode CSRs: mstatus, misa, mtvec, mcause, mepc, mtval, mscratch, mie, mip.
- [ ] **CSR instructions** (~2h) — CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI (Zicsr extension).
- [ ] **Read-only CSRs** (~1h) — mvendorid, marchid, mimpid, mhartid, cycle, time, instret counters.
- [ ] **Tests** (~1-2h) — Verify CSR read/write/set/clear semantics, read-only protection.

## Interrupt / Exception Handling (~8-12h)

- [ ] **Trap mechanism** (~3-4h) — On exception: save PC to mepc, set mcause, jump to mtvec. Implement MRET to return.
- [ ] **Synchronous exceptions** (~2h) — Illegal instruction, misaligned access, ecall, ebreak routed through trap vector instead of halting.
- [ ] **External interrupts** (~3-4h) — Timer interrupt (compare MTIME against mtimecmp), software interrupt. Priority and masking via mie/mip.
- [ ] **Tests** (~2h) — Trap entry/exit, nested exceptions, interrupt masking.

## ELF Loading (~3-4h)

- [ ] **ELF header parsing** (~1-2h) — Parse ELF32 headers, identify LOAD segments.
- [ ] **Segment loading** (~1h) — Map segments to correct physical addresses (ROM/RAM regions).
- [ ] **Entry point** (~30min) — Set initial PC from ELF entry point instead of 0x00000000.
- [ ] **Symbol table** (optional, ~1h) — Parse symtab for debug display of function names.

## GDB Remote Stub (~10-15h)

- [ ] **RSP protocol** (~4-5h) — Implement GDB Remote Serial Protocol over TCP socket. Handle g/G (registers), m/M (memory), s (step), c (continue), ? (halt reason).
- [ ] **Breakpoints** (~2-3h) — Software breakpoints (EBREAK insertion), hardware breakpoints (address match).
- [ ] **Single-stepping** (~1h) — Execute one instruction and halt.
- [ ] **Memory inspection** (~1h) — Read/write arbitrary memory through GDB.
- [ ] **Register access** (~1h) — Read/write all 32 GPRs + PC through GDB.
- [ ] **Integration** (~1-2h) — Run GDB stub alongside normal execution, pause/resume.

## Total: ~27-41h
