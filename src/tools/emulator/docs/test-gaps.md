# Test Coverage Gaps

Current suite: 25 assembly tests + 9 native unit tests.

## Instruction Tests (done)

- [x] **BGE branch test** — `test_bge.s`: signed greater-or-equal, 4 cases including negative values.
- [x] **BGEU branch test** — `test_bgeu.s`: unsigned greater-or-equal, 4 cases including large unsigned.
- [x] **FENCE as NOP** — `test_fence.s`: verify FENCE executes without side effects.
- [x] **JALR bit-clearing** — `test_jalr_lsb.s`: verify JALR clears LSB of target address.

## Edge Case Tests (done)

- [x] **Unaligned access faults** — `testsuite.zig`: 4 unit tests for misaligned LH/LW/SH/SW.
- [x] **Arithmetic overflow** — `test_overflow.s`: INT32_MAX+1, INT32_MIN-1, MAX+MAX, MIN-MIN.
- [x] **Shift by 0 and 31** — `test_shift_edge.s`: boundary shifts, SRL vs SRA distinction.
- [x] **Negative immediates** — `test_neg_imm.s`: ADDI/SLTI/SLTIU with negative sign-extended values.

## Integration / Stress Tests (done)

- [x] **Multi-instruction sequence** — `test_integration.s`: iterative Fibonacci(10) using loop, JAL, BGE.
- [x] **RAM stress test** — `test_ram_stress.s`: write/read pattern across 256 bytes, counting sum verification.
- [x] **Stack operations** — `test_stack.s`: nested function calls with stack frames (add_triple calls add_two).

## Missing Peripheral Tests (~2h)

One test per peripheral as they get implemented:

- [ ] **Timer/RTC** — Read MTIME_LO, verify MTIME_HI latching behavior.
- [ ] **System Info** — Read RAM_SIZE, verify it matches configured value.
- [ ] **Framebuffer** — Write and read back pixel data.
- [ ] **Keyboard** — Verify STATUS/DATA FIFO behavior, empty-read returns 0.
- [ ] **Block Device** — Write buffer, set LBA, trigger read/write, verify round-trip.
