# Ashet Graphics Protocol

The AGP (Ashet Graphics Protocol) is a protocol that can be used to encode commands to draw 2D graphics.

## Constraints

The protocol is meant to be simple, but compressed. It doesn't use fancy packed data types. It uses a 256-color palette
to reduce encoding size and enable widespread use for devices with low memory or displays with low color depth.

## Architecture

AGP is an in-memory transferred protocol that is meant to communicate between
different parts of the Ashet Operating System and allows userland applications
to queue densly packed draw commands to the rendering subsystem of the kernel.

Using several overlapped syscalls is inefficient, and having a generic typed data structure wouldn't be compact either, so we've chosen to use a byte-serialized list of rendering opcodes.

These opcodes still can encode pointers and resource handles.

## Commands

The commands are encoded as `struct` declarations using Zig types.

Each command has a fixed length and is always introduced by so called "command byte", which defines what command is executed.

Command parameters can point to data on the host system. If a pointer type (`*T`) is used in the `struct` definition, it is an alias to a 32-bit handle to `T`. Other pointers are encoded as a u64 holding the address.

### Clear

Fills the current target with `color` ignoring the current clip rectangle. This is roughly equivalent to a `fill_rect` command that always spans the full image, but has one important distinction:

*Clear* does discard the pixel values and will create a new blank slate. There won't be any "previous" colors to blend over in case of transparency, and it guarantess that always all pixels are cleared to the provided color.

**NOTE:** A *clear* command allows the backend to potentially exchange the internal pixel buffer for another one, allowing rendering into a new buffer, while the current one is still used for painting, while `fill_rect` will always assume that the buffer will retain the some of the old pixel data and thus must draw into the previous pixel buffer.

Command Byte: `0x00`

```zig
struct {
    color: u8,
}
```

### Set Clip Rect

Command Byte: `0x01`

```zig
struct {
    x: i16,
    y: i16,
    width: u16,
    height: u16,
}
```

### Set Pixel

Command Byte: `0x02`

```zig
struct {
    x: i16,
    y: i16,
    color: u8,
}
```

### Draw Line

Command Byte: `0x03`

```zig
struct {
    x1: i16,
    y1: i16,
    x2: i16,
    y2: i16,
    color: i16,
}
```

### Draw Rectangle

Command Byte: `0x04`

```zig
struct {
    x: i16,
    y: i16,
    width: u16,
    height: u16,
    color: u8,
}
```

### Fill Rectangle

Command Byte: `0x05`

```zig
struct {
    x: i16,
    y: i16,
    width: u16,
    height: u16,
    color: u8,
}
```

### Draw Text

Command Byte: `0x06`

```zig
struct {
    x: i16,
    y: i16,
    font: *Font,
    color: u8,
    text_ptr: [*]const u8,
    text_len: u16,
}
```

### Blit Bitmap

Command Byte: `0x07`

```zig
struct {
    x: i16,
    y: i16,
    bitmap: *Bitmap,
}
```

### Blit Framebuffer

Command Byte: `0x08`

```zig
struct {
    x: i16,
    y: i16,
    bitmap: *Framebuffer,
}
```

### Update Color

Command Byte: `0x09`

```zig
struct {
    index: u8,
    r: u8,
    g: u8,
    b: u8,
}
```

### Blit Partial Bitmap

Command Byte: `0x0A`

```zig
struct {
    x: i16,
    y: i16,
    width: u16,
    height: u16,
    src_x: u16,
    src_y: u16,
    bitmap: *Bitmap,
}
```

### Blit Partial Framebuffer

Command Byte: `0x0B`

```zig
struct {
    x: i16,
    y: i16,
    width: u16,
    height: u16,
    src_x: u16,
    src_y: u16,
    bitmap: *Framebuffer,
}
```
