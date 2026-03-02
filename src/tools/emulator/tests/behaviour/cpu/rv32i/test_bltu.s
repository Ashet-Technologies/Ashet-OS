# Test BLTU (unsigned branch).
# Assemble with -march=rv32i to avoid compressed instructions in the test.
#   riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -Ttext=0x0 -o test_bltu.elf test_bltu.s
#   riscv64-unknown-elf-objcopy -O binary test_bltu.elf test_bltu.bin
#
# Expected: x3 = 1 (BLTU branch taken since 1 < 0xFFFFFFFF unsigned)
.section .text
.globl _start
_start:
    addi x1, x0, -1       # x1 = 0xFFFFFFFF
    addi x2, x0, 1        # x2 = 1
    bltu x2, x1, skip     # 1 < 0xFFFFFFFF → taken
    addi x3, x0, 0        # not reached
    j done
skip:
    addi x3, x0, 1
done:
    ebreak
