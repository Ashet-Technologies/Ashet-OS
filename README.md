# Ashet Operating System

A tiny cross-platform operating system, focused on hackability.

[![Build](https://github.com/Ashet-Technologies/Ashet-OS/actions/workflows/build.yml/badge.svg)](https://github.com/Ashet-Technologies/Ashet-OS/actions/workflows/build.yml) [![Smoke Test](https://github.com/Ashet-Technologies/Ashet-OS/actions/workflows/smoketest.yml/badge.svg)](https://github.com/Ashet-Technologies/Ashet-OS/actions/workflows/smoketest.yml)

Supported platforms are:

- Linux/x86 "Hosted Simulation" (wip)
- RISC-V (wip)
- x86 (wip)
- Arm M-Profile (wip)

The OS is designed to run primarily on 32 bit hardware with "low" memory (measured in 10s of MB). It can obviously also use more memory if available, but it doesn't require more than 16 MB to run stable and fully usable.

## Platforms

The following list contains devices for which there is a planned port of Ashet OS.

### RISC-V

- ✅ [QEMU virt](https://www.qemu.org/docs/master/system/riscv/virt.html)
- ⌛ [Ox64](https://wiki.pine64.org/wiki/Ox64)
- ⌛ [Ashet Home Computer](https://github.com/Ashet-Technologies/Home-Computer)

### x86

- ✅ Linux (Yes, you can actually run the OS as an application!)
- ✅ Generic PC platform (486 and newer)
- ⌛ [QEMU microvm](https://www.qemu.org/docs/master/system/i386/microvm.html)

### Arm

- ✅ Ashet Virtual Home Computer (Custom QEMU Board, Cortex-M33)
- ☠️ [QEMU virt](https://www.qemu.org/docs/master/system/riscv/virt.html, Cortex-A7)
- ⌛ [Ashet Home Computer](https://github.com/Ashet-Technologies/Home-Computer)
- ⌛ [RaspberryPi 400](https://www.raspberrypi.com/products/raspberry-pi-400/)
- ⌛ [RaspberryPi 3 B+](https://www.raspberrypi.com/products/raspberry-pi-3-model-b-plus/)

## Project Goals

- Portability (Support at least two platforms)
  - `qemu` virt platform
  - Ashet Home Computer
- Cooperative multitasking
- Desktop OS
  - Open several window-based applications
  - Play games

## Planned Applications

### Applications

- Media Player (Grammophone)
- Ashet Commander (Shepard)
- Chat (Telegraph)
  - IRC
- Browser (Gateway)
  - Gemini
  - HTTP
  - Gopher
- Hyperlink Document Viewer + Editor (Hyper Wiki)
  - Interactive help
  - Notes / Notebook
- Terminal (Connex)
  - Console Services
  - Serial Ports
  - Netcat/TCP Monitor
- Code Editor (Craftworks)
- Paint (Dragon Craft)
- Direct I/O Access (I/O)
- System Management + Update (SysAdvance)
- Lola Scripting Env (LoLa Run!)
- Dungeon Crawler Game (Dungeon)
- Spreadsheet Software (Calc)

### Daemons

- Psi Compiler (Psi)
- LoLa Compiler (LoLa)
- Asm Compiler (Asm)
- Shell Service (Shell)

## Contributing

### Compiling The Project

The results of the compilation are usually disk images, except for a machine based on the `hosted` machine.

#### Compile everything

```sh-session
[user@host] $ zig build
[user@host] $ 
```

#### Compile for a single machine

```sh-session
[user@host] $ zig build <machine-name>
[user@host] $ 
```

## Useful Links

- [Free & Open RISC-V Reference Card](https://www.cl.cam.ac.uk/teaching/1617/ECAD+Arch/files/docs/RISCVGreenCardv8-20151013.pdf)
- [Application Binary Interface for the Arm® Architecture](https://github.com/ARM-software/abi-aa/tree/main)1
  - [ELF for the Arm® Architecture](https://github.com/ARM-software/abi-aa/blob/main/aaelf32/aaelf32.rst)
  - [Procedure Call Standard for the Arm® Architecture](https://github.com/ARM-software/abi-aa/blob/main/aapcs32/aapcs32.rst)
- [Arm® Cortex®-M33 Processor Technical Reference Manual](https://developer.arm.com/documentation/100230/0100?lang=en)
- [A Practical guide to ARM Cortex-M Exception Handling](https://interrupt.memfault.com/blog/arm-cortex-m-exceptions-and-nvic#registers-used-to-configure-cortex-m-exceptions)
- [musl dyynamic linker](https://github.com/lsds/musl/blob/master/ldso/dynlink.c)
- [x86 and amd64 instruction reference](https://www.felixcloutier.com/x86/)
- [GCC Documentation](https://gcc.gnu.org/onlinedocs/gcc/index.html)
  - [How to Use Inline Assembly Language in C Code](https://gcc.gnu.org/onlinedocs/gcc/Using-Assembly-Language-with-C.html)
- [Zig](https://ziglang.org/)
  - [Zig 0.13 Language Reference](https://ziglang.org/documentation/0.13.0/)
  - [Zig 0.13 StandarD Library Documentation](https://ziglang.org/documentation/0.13.0/std/)
- [QEMU Documentation](https://www.qemu.org/docs/master/system/introduction.html)
- [RP2350](https://www.raspberrypi.com/products/rp2350/)
  - [RP2350 Datasheet](https://datasheets.raspberrypi.com/rp2350/rp2350-datasheet.pdf)
  - [W25Q128JV Datasheet](https://www.mouser.de/datasheet/2/949/w25q128jv_revf_03272018_plus-1489608.pdf)