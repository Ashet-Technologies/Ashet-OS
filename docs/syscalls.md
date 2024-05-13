# Ashet OS ABI and Syscall Interface

## Binary Formats

### ELF32

Ashet OS uses ELF object files with dynamically linked executables.

## Cross-platform

- Syscalls are imported via a shared library `libsyscall.so`.
- The symbols are prefixed with `ashet.` and have subgroups for namespacing
- The calling convention is the SysV C calling convention

The definition (and imports) of all syscalls can be found in [`abi.zig`](../src/abi/abi.zig).

## Platform specific

Syscalls have no platform specific properties anymore except the Elf format used.
