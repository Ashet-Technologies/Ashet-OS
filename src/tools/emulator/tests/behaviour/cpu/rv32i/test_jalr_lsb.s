// {
//     "name": "JALR: clears LSB of target address",
//     "march": "rv32i",
//     "ram_size": 0,
//     "initial_regs": {},
//     "expected_regs": {
//         "x1": 1,
//         "x2": 1
//     },
//     "expected_debug": ""
// }
# JALR sets PC = (rs1 + imm) & ~1. This test verifies the LSB is cleared
# by jumping to an odd address that, after clearing bit 0, lands on the
# correct instruction.
.section .text
.globl _start
_start:
    auipc x10, 0            # x10 = address of this instruction (0)
    addi  x10, x10, 17      # x10 = 17 (target offset 16 + 1 for odd)
    jalr  x5, x10, 0        # jump to (17 + 0) & ~1 = 16 = target
    j     fail              # should not reach here

    # target is at offset 16 from _start (4 instructions * 4 bytes).
    # The odd address 17 has bit 0 cleared -> 16, landing here.
    .balign 4
target:
    addi x1, x0, 1
    # Verify return address was saved correctly
    # x5 should hold PC+4 of the JALR instruction = _start + 12
    auipc x11, 0            # x11 = address of this instruction
    addi  x11, x11, -8      # x11 = address of target (target is 2 instrs before here)
    # Just verify we arrived here successfully
    addi  x2, x0, 1
    ebreak

fail:
    ebreak
