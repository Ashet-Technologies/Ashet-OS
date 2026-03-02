# Test branch instructions.
# Assemble and convert to raw binary with:
#   riscv64-unknown-elf-gcc -march=rv32imc -mabi=ilp32 -nostdlib -Ttext=0x0 -o test_branch.elf test_branch.s
#   riscv64-unknown-elf-objcopy -O binary test_branch.elf test_branch.bin
#
# Expected results at EBREAK:
#   x1 = 1 (BEQ taken), x2 = 1 (BNE taken), x3 = 1 (BLT taken)
.section .text
.globl _start
_start:
    addi x10, x0, 5
    addi x11, x0, 5
    addi x12, x0, 10

    # Test BEQ: x10 == x11 should branch
    beq  x10, x11, beq_ok
    addi x1, x0, 0
    j    test_bne
beq_ok:
    addi x1, x0, 1

test_bne:
    # Test BNE: x10 != x12 should branch
    bne  x10, x12, bne_ok
    addi x2, x0, 0
    j    test_blt
bne_ok:
    addi x2, x0, 1

test_blt:
    # Test BLT: x10 < x12 should branch
    blt  x10, x12, blt_ok
    addi x3, x0, 0
    j    done
blt_ok:
    addi x3, x0, 1

done:
    ebreak
