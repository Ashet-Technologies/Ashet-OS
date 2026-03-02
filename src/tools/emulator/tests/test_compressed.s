# Test RV32C compressed instructions.
# GAS automatically emits compressed encodings when -march=rv32imc is set
# and the instruction is eligible for compression.
#
# Assemble and convert to raw binary with:
#   riscv64-unknown-elf-gcc -march=rv32imc -mabi=ilp32 -nostdlib -Ttext=0x0 -o test_compressed.elf test_compressed.s
#   riscv64-unknown-elf-objcopy -O binary test_compressed.elf test_compressed.bin
#
# Expected results at EBREAK:
#   x10 = 7  (c.li)
#   x11 = -3 as u32 (c.li with negative)
#   x12 = 7  (c.mv)
#   x13 = 14 (c.add)
#   x14 = 28 (c.slli by 2)
.section .text
.globl _start
_start:
    li   x10, 7           # c.li x10, 7
    li   x11, -3          # c.li x11, -3
    mv   x12, x10         # c.mv x12, x10
    add  x13, x10, x10    # c.add? no, this needs both operands...
    # Force a c.add: rd = rd + rs2
    mv   x13, x10         # c.mv x13, x10 (x13 = 7)
    add  x13, x13, x10    # c.add x13, x10 (x13 = 14)
    mv   x14, x13         # c.mv x14, x13 (x14 = 14)
    slli x14, x14, 1      # c.slli x14, 1 (x14 = 28)
    ebreak                 # c.ebreak
