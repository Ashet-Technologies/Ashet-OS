# Test MULH, MULHU, MULHSU (upper 32 bits of 64-bit products).
# Assemble with:
#   riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 -nostdlib -Ttext=0x0 -o test_mulh.elf test_mulh.s
#   riscv64-unknown-elf-objcopy -O binary test_mulh.elf test_mulh.bin
#
# Using x1 = 0x80000000, x2 = 2:
#   mulh  x3 = upper((-2^31) * 2) = upper(-2^32) = 0xFFFFFFFF
#   mulhu x4 = upper(0x80000000 * 2) = upper(0x100000000) = 1
#   mulhsu x5 = upper((-2^31) * 2u) = upper(-2^32) = 0xFFFFFFFF
.section .text
.globl _start
_start:
    lui  x1, 0x80000       # x1 = 0x80000000
    addi x2, x0, 2         # x2 = 2
    mulh   x3, x1, x2
    mulhu  x4, x1, x2
    mulhsu x5, x1, x2
    ebreak
