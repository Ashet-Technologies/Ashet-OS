# Ashet Operating System

A tiny cross-platform operating system, focused on hackability.

Supported platforms are:

- 🔧 Linux/x86 "Hosted Simulation" (wip)
- 🔧 RISC-V (wip)
- 🔧 x86 (wip)
- ⌛ Arm (planned)

The OS is designed to run primarily on 32 bit hardware with "low" memory (measured in 10s of MB). It can
obviously also use more memory if available, but it doesn't require more than 16 MB to run stable and
fully usable.

## Platforms

The following list contains devices for which there is a planned port of Ashet OS.

### RISC-V

- 🔧 [QEMU virt](https://www.qemu.org/docs/master/system/riscv/virt.html)
- ⌛ [Ox64](https://wiki.pine64.org/wiki/Ox64)
- ⌛ [Ashet Home Computer](https://ashet.computer/product/ashet.htm)

### x86

- 🔧 Generic PC platform (486 and newer)
- ⌛ [QEMU microvm](https://www.qemu.org/docs/master/system/i386/microvm.html)

### Arm

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

#### Compile everything:

```sh-session
[user@host] $ zig build
[user@host] $ 
```

#### Compile for a single machine:

```sh-session
[user@host] $ zig build <machine-name>
[user@host] $ 
```

## Useful Links

- [Free & Open RISC-V Reference Card](https://www.cl.cam.ac.uk/teaching/1617/ECAD+Arch/files/docs/RISCVGreenCardv8-20151013.pdf)
