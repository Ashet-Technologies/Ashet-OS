# Ashet Operating System

A tiny RISC-V operating system, focused on hackability.

## Project Goals

- Portability (Support at least two platforms)
  - `qemu` virt platform
  - Ashet Home Computer
- Cooperative multitasking
- Graphical and text mode
  - 64×32 characters text mode, with 16 colors foreground/background
  - 256×128 pixels graphical mode, with 8bpp palettized colors
- Basic file system support
  - Potentially only FAT32
