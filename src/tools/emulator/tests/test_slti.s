# Test SLTI and SLTIU instructions.
# Assemble with:
#   riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -Ttext=0x0 -o test_slti.elf test_slti.s
#   riscv64-unknown-elf-objcopy -O binary test_slti.elf test_slti.bin
#
# Expected:
#   x1 = 0xFFFFFFFB (-5)
#   x2 = 1 (SLTI: -5 < 0 signed)
#   x3 = 0 (SLTIU: 0xFFFFFFFB > 0 unsigned)
.section .text
.globl _start
_start:
    addi  x1, x0, -5       # x1 = -5
    slti  x2, x1, 0        # x2 = 1 (-5 < 0 signed)
    sltiu x3, x1, 0        # x3 = 0 (0xFFFFFFFB > 0 unsigned)
    ebreak
