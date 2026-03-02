# Test debug output peripheral by writing "Hi" followed by newline.
# Assemble and convert to raw binary with:
#   riscv64-unknown-elf-gcc -march=rv32imc -mabi=ilp32 -nostdlib -Ttext=0x0 -o test_debug.elf test_debug.s
#   riscv64-unknown-elf-objcopy -O binary test_debug.elf test_debug.bin
#
# Expected: debug output captures bytes 0x48 ('H'), 0x69 ('i'), 0x0A ('\n')
.section .text
.globl _start
_start:
    lui  x1, 0x40041        # x1 = 0x40041000 (debug TX base)
    addi x2, x0, 0x48       # 'H'
    sb   x2, 0(x1)
    addi x2, x0, 0x69       # 'i'
    sb   x2, 0(x1)
    addi x2, x0, 0x0A       # '\n'
    sb   x2, 0(x1)
    ebreak
