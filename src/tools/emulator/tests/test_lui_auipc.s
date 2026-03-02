# Test LUI and AUIPC instructions.
# Assemble and convert to raw binary with:
#   riscv64-unknown-elf-gcc -march=rv32imc -mabi=ilp32 -nostdlib -Ttext=0x0 -o test_lui_auipc.elf test_lui_auipc.s
#   riscv64-unknown-elf-objcopy -O binary test_lui_auipc.elf test_lui_auipc.bin
#
# Expected results at EBREAK:
#   x1 = 0x12345000 (LUI)
#   x2 = 0x12345678 (LUI + ADDI)
#   x3 = 0x00001008 (AUIPC at PC=0x08 with imm=0x1000)
.section .text
.globl _start
_start:
    lui    x1, 0x12345       # x1 = 0x12345000
    lui    x2, 0x12345
    addi   x2, x2, 0x678    # x2 = 0x12345678
    auipc  x3, 1            # x3 = PC + 0x1000; PC here = 0x08, so x3 = 0x1008
    ebreak
