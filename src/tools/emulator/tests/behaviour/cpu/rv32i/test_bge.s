// {
//     "name": "BGE: branch greater-or-equal (signed)",
//     "march": "rv32i",
//     "ram_size": 0,
//     "initial_regs": {},
//     "expected_regs": {
//         "x1": 1,
//         "x2": 1,
//         "x3": 1,
//         "x4": 1
//     },
//     "expected_debug": ""
// }
.section .text
.globl _start
_start:
    addi x10, x0, 10
    addi x11, x0, 5
    addi x12, x0, 10
    addi x13, x0, -3       # x13 = -3 (signed)

    # Test 1: 10 >= 5 should branch (greater)
    bge  x10, x11, t1_ok
    j    fail
t1_ok:
    addi x1, x0, 1

    # Test 2: 10 >= 10 should branch (equal)
    bge  x10, x12, t2_ok
    j    fail
t2_ok:
    addi x2, x0, 1

    # Test 3: 5 >= 10 should NOT branch
    bge  x11, x10, fail
    addi x3, x0, 1

    # Test 4: 5 >= -3 should branch (positive >= negative, signed)
    bge  x11, x13, t4_ok
    j    fail
t4_ok:
    addi x4, x0, 1
    ebreak

fail:
    ebreak
