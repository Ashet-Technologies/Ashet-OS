# Test Coverage

Current suite: 25 assembly integration tests + 50 Zig unit tests = 75 total.

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

## Peripheral Unit Tests (done)

50 Zig unit tests across 8 files in `tests/peripherals/`, using table-driven `testPeripheralAccess` helper:

- [x] **Debug Output** — write byte, read errors, size errors, offset errors.
- [x] **System Info** — read RAM_SIZE, write errors, size errors, offset errors.
- [x] **Timer/RTC** — MTIME_LO/HI latching, RTC_LO/HI latching, setTime updates, write errors, size errors.
- [x] **Video Control** — flush enable/disable, ackFlush, read errors, size errors, offset errors.
- [x] **Framebuffer** — u8/u32 read/write roundtrip, boundary errors, host pixel access.
- [x] **Keyboard** — push/pop events, FIFO capacity, deduplication, different states, write errors.
- [x] **Mouse** — setState + read registers, negative clamping, screen bounds clamping, write errors, size errors.
- [x] **Block Device** — not-present behavior, present status, buffer access, read/write command flow, error flag, clear error, no-pending-request error, LBA snapshot.
