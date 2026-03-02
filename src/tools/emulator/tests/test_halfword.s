# Test SH, LH, LHU (halfword store and load).
# Assemble with:
#   riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -Ttext=0x0 -o test_halfword.elf test_halfword.s
#   riscv64-unknown-elf-objcopy -O binary test_halfword.elf test_halfword.bin
#
# Expected:
#   x3 = 0xFFFFFFFF (LH sign-extends 0xFFFF)
#   x4 = 0x0000FFFF (LHU zero-extends 0xFFFF)
.section .text
.globl _start
_start:
    lui  x1, 0x80000       # x1 = 0x80000000 (RAM base)
    addi x2, x0, -1        # x2 = 0xFFFFFFFF
    sh   x2, 0(x1)         # store 0xFFFF to RAM
    lh   x3, 0(x1)         # x3 = sign_extend(0xFFFF) = 0xFFFFFFFF
    lhu  x4, 0(x1)         # x4 = 0x0000FFFF
    ebreak
