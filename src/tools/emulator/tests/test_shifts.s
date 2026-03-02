# Test shift instructions (SLL, SRL, SRA, SLLI, SRLI, SRAI).
# Assemble and convert to raw binary with:
#   riscv64-unknown-elf-gcc -march=rv32imc -mabi=ilp32 -nostdlib -Ttext=0x0 -o test_shifts.elf test_shifts.s
#   riscv64-unknown-elf-objcopy -O binary test_shifts.elf test_shifts.bin
#
# Expected results at EBREAK:
#   x3 = 0x28 (10 << 2 = 40)
#   x4 = 0x02 (10 >> 2 = 2)
#   x5 = 0xE0000000 (-1 << 29... actually 0x80000000 >> 2 arithmetic = 0xE0000000)
#   x6 = 0x14 (10 << 1 = 20)
#   x7 = 0x05 (10 >> 1 = 5)
.section .text
.globl _start
_start:
    addi x1, x0, 10
    addi x2, x0, 2
    sll  x3, x1, x2        # x3 = 10 << 2 = 40
    srl  x4, x1, x2        # x4 = 10 >> 2 = 2
    lui  x8, 0x80000        # x8 = 0x80000000
    sra  x5, x8, x2        # x5 = 0x80000000 >>a 2 = 0xE0000000
    slli x6, x1, 1          # x6 = 10 << 1 = 20
    srli x7, x1, 1          # x7 = 10 >> 1 = 5
    ebreak
