// {
//     "name": "Stack operations: function calls via SP, JAL, JALR",
//     "march": "rv32i",
//     "ram_size": 1024,
//     "initial_regs": {},
//     "expected_regs": {
//         "x1": 30,
//         "x2": "0x80000400"
//     },
//     "expected_debug": ""
// }
# Test nested function calls with stack frames.
# main calls add_triple(3, 7, 20) which calls add_two twice.
# Result: 3 + 7 + 20 = 30
.section .text
.globl _start
_start:
    lui  x2, 0x80000        # SP = 0x80000000
    addi x2, x2, 1024       # SP = top of 1KB RAM

    # Call add_triple(3, 7, 20)
    addi x10, x0, 3         # arg0 = 3
    addi x11, x0, 7         # arg1 = 7
    addi x12, x0, 20        # arg2 = 20
    jal  x1, add_triple

    # Result in x10, move to x1 for checking
    addi x1, x10, 0
    ebreak

# add_triple(a, b, c): returns a + b + c
# Uses add_two as a subroutine.
add_triple:
    addi x2, x2, -12        # allocate 3 words on stack
    sw   x1, 8(x2)          # save return address
    sw   x12, 4(x2)         # save arg2 (c)
    sw   x11, 0(x2)         # save arg1 (b)

    # x10 already has a, x11 has b
    jal  x1, add_two         # x10 = a + b

    # Now add c
    lw   x11, 4(x2)         # restore c
    jal  x1, add_two         # x10 = (a + b) + c

    lw   x1, 8(x2)          # restore return address
    addi x2, x2, 12         # deallocate stack frame
    jalr x0, x1, 0           # return

# add_two(a, b): returns a + b in x10
# Leaf function, no stack frame needed.
add_two:
    add  x10, x10, x11
    jalr x0, x1, 0           # return
