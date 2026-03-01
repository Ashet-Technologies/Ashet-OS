# RV32 System Emulator

## CPU

The emulator provides a RISC-V cpu with 32 bits system width and the `rv32imc` feature set.

The CPU provides no interrupts, and will just start executing code at address `0x00000000`.

## Memory Map

```
0x00000000 - 0x3FFFFFFF   ROM        (1 GB window)
0x40000000 - 0x7FFFFFFF   MMIO       (1 GB window)
0x80000000 - 0x81FFFFFF   RAM        (up to 32 MB; actual size in SYSINFO)
```

### MMIO Layout

```
0x40000000 – 0x4003DFFF   Framebuffer    250,000 bytes (640×400), padded to region end
                                         palette is fixed in the emulator, not exposed

0x40040000 – 0x40040FFF   Video Control
0x40041000 – 0x40041FFF   Debug Output
0x40042000 – 0x40042FFF   Keyboard
0x40043000 – 0x40043FFF   Mouse
0x40044000 – 0x40044FFF   Timer / RTC
0x40045000 – 0x40045FFF   System Info
0x40046000 – 0x40046FFF   Block Device 0
0x40047000 – 0x40047FFF   Block Device 1
```

## Peripherals

Register layouts are described as `+XX/Y` where XX is the relative offset to the peripheral base and Y is the size of the register.

### Framebuffer

A linear, row-major framebuffer with 8 bit per pixel, using the Ashet OS color palette.

### Video Control

```
+0x00/4   FLUSH       W   Write 1 to mark framebuffer as ready to present.
                          The emulator presents the framebuffer on its next display tick
                          and continues to do so on every tick thereafter until the OS
                          writes 0 (blank/hide screen). Does not clear automatically.
                          The OS is responsible for fully painting the framebuffer before
                          writing 1 — no double-buffering is provided.
```

### Debug Output

```
+0x00/1   TX          W   Write byte (low 8 bits). Always accepted immediately, no flow control.
```

### Keyboard

```
+0x00/4   STATUS      R   Bit 0 = at least one entry waiting in FIFO
+0x04/4   DATA        R   Pop and return one entry:
                            Bit 31    = 1 key-down, 0 key-up
                            Bits 15:0 = HID Usage Code (Usage Page 0x07, Keyboard)
                          Reading while FIFO empty returns 0x00000000
```

### Mouse

```
+0x00/4   X           R   Absolute X, clamped 0-639
+0x04/4   Y           R   Absolute Y, clamped 0-399
+0x08/4   BUTTONS     R   Bit 0 = left, Bit 1 = right, Bit 2 = middle
```

### Timer / RTC

```
; Monotonic - microseconds elapsed since emulator start
+0x00/4   MTIME_LO    R   Low  32 bits, free-running
+0x04/4   MTIME_HI    R   High 32 bits, latched

; RTC - Unix timestamp (seconds since 1970-01-01 00:00:00 UTC)
+0x10/4   RTC_LO      R   Low  32 bits, free-running
+0x14/4   RTC_HI      R   High 32 bits, latched
```

Reading `MTIME_LO` latches the value inside `MTIME_HI` to the upper 32 bits of the current time stamp.
Reading `RTC_LO` latches the value inside `RTC_HI` to the upper 32 bits of the current time stamp.

This means reading MTIME_LO/RTC_LO first, then MTIME_HI/RTC/HI second is always a safe operation.

### System Info

```
+0x00/4   RAM_SIZE    R   Total RAM in bytes (e.g. 0x00800000 for 8 MB)
```

### Block Device

```
+0x000/4    STATUS      R   Bit 0 = device present
                            Bit 1 = device busy
                            Bit 2 = last operation failed
+0x004/4    LBA         RW  Target block address (512-byte blocks)
+0x008/4    COMMAND     W   Bit 0 = 0 read / 1 write
                            Bit 1 = trigger (self-clears once operation begins)
+0x100/512  BUFFER      RW  512 bytes of transfer buffer (0x100–0x2FF)
```

Read flow: write LBA → write COMMAND 0b01 → poll STATUS bit 1 until clear → read BUFFER.

Write flow: fill BUFFER → write LBA → write COMMAND 0b11 → poll STATUS bit 1 until clear.

The gap between +0x00C and +0x100 is intentionally reserved. 