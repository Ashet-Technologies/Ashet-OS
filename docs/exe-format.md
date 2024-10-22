# Ashet Executable Format (`.ashex`)

## Rationale

- ELF is too generic
  - Loading takes more time than necessary
- Simplifies kernel loading
- Reduced loading times
- Optimized for the OS
  - Icon Embedding
  - Potential future "Fat Executables" with multiple architectures available

## Rough File Structure

- os specific header
  - ashet os platform
  - total required static memory size
  - list of requested syscalls
  - entry point
  - optional app/exe icon
- list of (loadable) program headers, aligned to page boundary for ro/rw split
- list of null sections (bss)
- list of relocations

## File Structure

Each file section is aligned to 512 byte, so it is suitable to read directly from a
typical block device.

```zig
root File;

type File = struct {
    header: FileHeader,
    load_headers: [header.load_header_count]LoadHeader align(512),
    bss_headers: [header.bss_header_count]VirtualMemoryRange align(512),
    syscalls: [header.syscall_count]SystemCall align(512),
    relocations: [header.relocation_count]Relocation align(512),
};

type FileHeader = struct {
    magic_number: [4]u8 = { 'A', 'S', 'H', 'X' },
    file_version: u8 = 0,
    file_type: enum(u8) {
      // 32 bit CPU type
      machine32_le = 0,
    },
    platform: enum(u8) {
      riscv32 = 0, // RISC-V (32 bit, rv32icm)
      arm32 = 1, //Arm/Thumb (32 bit, v7a)
      x86 = 2, // x86 (32 bit)
    },

    _padding: [1]u8 = .{0},

    /// Points to an embedded file which contains the application
    /// icon that should be used by visual application browsers.
    /// No icon shalled be used if `icon.length == 0`
    icon: EmbeddedData,

    /// total size of the applications required virtual memory area
    /// This should be used to allocate all memory upfront.
    vmem_size: u32,

    /// Offset in virtual memory where the entry point is located.
    entry_point: u32,

    syscall_offset: u32,
    syscall_count: u32,

    load_header_offset: u32,
    load_header_count: u32,
    
    bss_header_offset: u32,
    bss_header_count: u32,
    
    relocation_offset: u32,
    relocation_count: u32,
};

/// A reference to a system call 
type SystemCall = struct {
    length: u16,
    name: [length]u16,
};

type Relocation = struct {
    // TODO: Define this better
    type: bitfield(u16) {
        size: enum(u2) { word8=0, word16=1, word32=2, word64=3 },
        addend: RelocField,
        base: RelocField,
        offset: RelocField,
        syscall: RelocField, // called 'symbol' in ELF
        // potentially required:
        // got_offset: RelocField,
        // got: RelocField,
        // plt_offset: RelocField,
    },
    
    if(type.syscall != .unused) {
      syscall: u16,
    }
    if(type.offset != .unused) {
      offset: u32,
    }
    if(type.addend != .unused) {
      addend: i32,
    }
};

type RelocField = enum(u2) {
    unused = 0b00,
    add = 0b10,
    subtract = 0b11,
};

type LoadHeader = struct {
    vmem_offset: u32,
    size: u32,
    data: [size]u8,
};

type VirtualMemoryRange = struct {
    vmem_offset: u32,
    size: u32,
};

/// An embedded binary blob
type EmbeddedData = struct {
    length: u32,
    data: u32<*align(512) [length]u8>,
};
```
