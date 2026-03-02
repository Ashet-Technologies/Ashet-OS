// {
//     "name": "RAM stress: write/read pattern across 256 bytes",
//     "march": "rv32i",
//     "ram_size": 1024,
//     "initial_regs": {},
//     "expected_regs": {
//         "x1": 1,
//         "x2": "0xDEADBEEF",
//         "x3": "0xCAFEBABE",
//         "x4": "0x12345678"
//     },
//     "expected_debug": ""
// }
# Write a pattern of words across RAM, then read them all back and verify.
.section .text
.globl _start
_start:
    lui  x10, 0x80000        # x10 = 0x80000000 (RAM base)

    # Write distinct values at increasing offsets
    li   x20, 0xDEADBEEF
    sw   x20, 0(x10)
    li   x21, 0xCAFEBABE
    sw   x21, 4(x10)
    li   x22, 0x12345678
    sw   x22, 8(x10)

    # Write a counting pattern: store i at RAM[64 + i*4] for i=0..15
    addi x11, x10, 64       # base for counting region
    addi x12, x0, 0         # i = 0
    addi x13, x0, 16        # limit
write_loop:
    bge  x12, x13, read_back
    slli x14, x12, 2        # offset = i * 4
    add  x15, x11, x14      # addr = base + offset
    sw   x12, 0(x15)        # RAM[addr] = i
    addi x12, x12, 1
    j    write_loop

read_back:
    # Read back the counting pattern and sum it: 0+1+2+...+15 = 120
    addi x12, x0, 0         # i = 0
    addi x16, x0, 0         # sum = 0
read_loop:
    bge  x12, x13, verify
    slli x14, x12, 2
    add  x15, x11, x14
    lw   x17, 0(x15)
    add  x16, x16, x17      # sum += RAM[addr]
    addi x12, x12, 1
    j    read_loop

verify:
    # Sum of 0..15 = 120; verify
    addi x18, x0, 120
    beq  x16, x18, pass
    addi x1, x0, 0          # fail flag
    ebreak

pass:
    addi x1, x0, 1          # x1 = 1 (pass)
    # Also read back the initial distinct values
    lw   x2, 0(x10)         # x2 = 0xDEADBEEF
    lw   x3, 4(x10)         # x3 = 0xCAFEBABE
    lw   x4, 8(x10)         # x4 = 0x12345678
    ebreak
