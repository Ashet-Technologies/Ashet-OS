# Syscall List Draft

# Required Changes

- Rework video out syscalls
  - Support for multiple video outputs
- Terminate-and-stay-resident
- Window+Widget APIs
  - Register/Unregister widget
  - Create/destroy widget tree
  - Context menu APIs
  - Drag'n'Drop APIs
- Kernel Drawing/Graphics API
  - Semantic Drawing API
  - Screenshot API
    - Query semantic information
- Update File APIs
  - Add/set mime-type
  - Store mime-type in database
- Clipboard system
  - Set
  - Get
- Service Methods
  - Register/unregister service
  - Query registered services
- Input drivers can have an associated video output for absolute positioning

# List

```
    0   process.yield             fn () void
    1   process.exit              fn (u32) noreturn
    2   process.getBaseAddress    fn () usize
    3   process.breakpoint        fn () void
    4   time.nanoTimestamp        fn () i128
    5   video.acquire             fn () bool
    6   video.release             fn () void
    7   video.setBorder           fn (ColorIndex) void
    8   video.setResolution       fn (u16, u16) void
    9   video.getVideoMemory      fn () [*]align(4) ColorIndex
   10   video.getPaletteMemory    fn () *[palette_size]Color
   11   video.getPalette          fn (*[palette_size]Color) void
   14   ui.createWindow           fn (title: [*]const u8, title_len: usize, min: Size, max: Size, startup: Size, flags: CreateWindowFlags) ?*const Window
   15   ui.destroyWindow          fn (*const Window) void
   16   ui.moveWindow             fn (*const Window, x: i16, y: i16) void
   17   ui.resizeWindow           fn (*const Window, x: u16, y: u16) void
   18   ui.setWindowTitle         fn (*const Window, title: [*]const u8, title_len: usize) void
   20   ui.invalidate             fn (*const Window, rect: Rectangle) void
   21   ui.getSystemFont          fn (font_name_ptr: [*]const u8, font_name_len: usize, font_data_ptr: *[*]const u8, font_data_len: *usize) GetSystemFontError.Enum
   35   network.udp.createSocket  fn (result: *UdpSocket) udp.CreateError.Enum
   36   network.udp.destroySocket fn (UdpSocket) void
   44   network.tcp.createSocket  fn (out: *TcpSocket) tcp.CreateError.Enum
   45   network.tcp.destroySocket fn (TcpSocket) void
   50   io.scheduleAndAwait       fn (?*IOP, WaitIO) ?*IOP
   51   io.cancel                 fn (*IOP) void
   52   video.getMaxResolution    fn () Size
   53   video.getResolution       fn () Size
   60   fs.findFilesystem         fn (name_ptr: [*]const u8, name_len: usize) FileSystemId
   70   process.memory.allocate   fn (size: usize, ptr_align: u8) ?[*]u8
   71   process.memory.release    fn (ptr: [*]u8, size: usize, ptr_align: u8) void
   72   process.getFileName       fn () [*:0]const u8
   73   process.writeLog          fn (log_level: LogLevel, ptr: [*]const u8, len: usize) void
```