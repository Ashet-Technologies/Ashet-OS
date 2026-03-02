# Test various ALU operations.
# Assemble and convert to raw binary with:
#   riscv64-unknown-elf-gcc -march=rv32imc -mabi=ilp32 -nostdlib -Ttext=0x0 -o test_alu.elf test_alu.s
#   riscv64-unknown-elf-objcopy -O binary test_alu.elf test_alu.bin
#
# Expected results at EBREAK:
#   x1 = 10, x2 = 20, x3 = 30 (ADD), x4 = -10 as u32 (SUB),
#   x5 = 0 (AND 10&20), x6 = 30 (OR 10|20), x7 = 20 (XOR 10^30)
.section .text
.globl _start
_start:
    addi x1, x0, 10
    addi x2, x0, 20
    add  x3, x1, x2      # x3 = 30
    sub  x4, x1, x2      # x4 = -10
    and  x5, x1, x2      # x5 = 10 & 20 = 0
    or   x6, x1, x2      # x6 = 10 | 20 = 30
    addi x8, x0, 30
    xor  x7, x1, x8      # x7 = 10 ^ 30 = 20
    ebreak
