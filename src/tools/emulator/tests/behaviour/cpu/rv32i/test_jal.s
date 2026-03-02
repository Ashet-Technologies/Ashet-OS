# Test JAL and JALR instructions.
# Assemble and convert to raw binary with:
#   riscv64-unknown-elf-gcc -march=rv32imc -mabi=ilp32 -nostdlib -Ttext=0x0 -o test_jal.elf test_jal.s
#   riscv64-unknown-elf-objcopy -O binary test_jal.elf test_jal.bin
#
# Expected results at EBREAK:
#   x1 (ra) = address of instruction after JAL (0x04)
#   x10 = 99
#   x11 = address of instruction after JALR
.section .text
.globl _start
_start:
    jal  x1, target       # x1 = PC+4 = 0x04
    # We return here from target via JALR
    addi x10, x10, 0      # NOP-like, x10 already 99
    ebreak

target:
    addi x10, x0, 99      # x10 = 99
    jalr x11, x1, 0       # jump back to return address, x11 = PC+4
