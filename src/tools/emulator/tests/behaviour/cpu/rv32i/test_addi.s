# Test basic ADDI instruction.
# Assemble and convert to raw binary with:
#   riscv64-unknown-elf-gcc -march=rv32imc -mabi=ilp32 -nostdlib -Ttext=0x0 -o test_addi.elf test_addi.s
#   riscv64-unknown-elf-objcopy -O binary test_addi.elf test_addi.bin
#
# Expected result: x1 = 42, then EBREAK.
.section .text
.globl _start
_start:
    addi x1, x0, 42
    ebreak
