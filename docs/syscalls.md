# Ashet OS ABI and Syscall Interface

## Cross-platform

- Syscalls are organized in a table of function pointers
- The table may be sparse

The definition of all syscalls can be found in [`abi.zig`](../src/abi/abi.zig).

## Platform specific

## x86

Applications receive a pointer to the syscall table via the register `ecx` on launch and have to save it to a static variable in order to do syscalls.

## RISC-V (32 Bit)

- The register `x4` is reserved by the OS for handling syscalls:

A pointer to the syscall table is stored in the `x4` (`tp`) register and can quickly be accessed by two instructions:

```asm
    lw      a0, SYSCALL_OFFSET(tp)
    jalr    a0
    li      a0, 0
```

## Arm (32 Bit)

Only Thumb instruction set is supported, no "legacy" Arm code is supported by Ashet OS.

Syscalls are not implemented/defined yet.
