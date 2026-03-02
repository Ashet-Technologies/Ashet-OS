# Test load/store instructions using RAM at 0x80000000.
# Assemble and convert to raw binary with:
#   riscv64-unknown-elf-gcc -march=rv32imc -mabi=ilp32 -nostdlib -Ttext=0x0 -o test_mem.elf test_mem.s
#   riscv64-unknown-elf-objcopy -O binary test_mem.elf test_mem.bin
#
# Expected results at EBREAK:
#   x3 = 0xDEADBEEF (SW/LW round-trip)
#   x4 = 0xFFFFFFEF (LB sign-extends 0xEF)
#   x5 = 0x000000EF (LBU zero-extends 0xEF)
.section .text
.globl _start
_start:
    lui  x1, 0x80000         # x1 = 0x80000000 (RAM base)
    li   x2, 0xDEADBEEF      # x2 = 0xDEADBEEF (assembler handles lui+addi)
    sw   x2, 0(x1)           # store to RAM
    lw   x3, 0(x1)           # x3 should be 0xDEADBEEF
    lb   x4, 0(x1)           # x4 = sign_extend(0xEF) = 0xFFFFFFEF
    lbu  x5, 0(x1)           # x5 = 0x000000EF
    ebreak
