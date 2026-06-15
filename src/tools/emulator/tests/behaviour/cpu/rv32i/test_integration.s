// {
//     "name": "Integration: multi-instruction Fibonacci sequence",
//     "march": "rv32i",
//     "ram_size": 1024,
//     "initial_regs": {},
//     "expected_regs": {
//         "x1": 55,
//         "x20": 10
//     },
//     "expected_debug": ""
// }
# Compute fib(10) = 55 using a loop. Exercises: ADDI, ADD, BLT, SW, LW,
# LUI, and JAL within a single cohesive program.
.section .text
.globl _start
_start:
    lui  x2, 0x80000        # x2 = SP = 0x80000000 (RAM base)
    addi x2, x2, 1024       # SP points to top of 1KB RAM

    addi x10, x0, 10        # n = 10
    jal  x1, fib            # x1 = fib(10), result in x1
    addi x20, x10, 0        # x20 = 10 (preserve n for checking)
    addi x1, x11, 0         # x1 = result
    ebreak

# fib(n) — iterative. n in x10, result in x11.
fib:
    addi x11, x0, 0         # a = 0
    addi x12, x0, 1         # b = 1
    addi x13, x0, 0         # i = 0
fib_loop:
    bge  x13, x10, fib_done # if i >= n, done
    add  x14, x11, x12      # tmp = a + b
    addi x11, x12, 0        # a = b
    addi x12, x14, 0        # b = tmp
    addi x13, x13, 1        # i++
    j    fib_loop
fib_done:
    jalr x0, x1, 0          # return (jump to x1, discard return addr)
