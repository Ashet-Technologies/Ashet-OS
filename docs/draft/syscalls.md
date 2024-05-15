# Syscall List Draft

# Required Changes

- Proper date/time syscalls
- Rework video out syscalls
  - Support for multiple video outputs
  => VideoOutput
- Terminate-and-stay-resident
  => process.terminate
  => process.thread.spawn
  => process.thread.kill
  => process.thread.join
  => process.thread.exit
- Window+Widget APIs
  - Register/Unregister widget
  - Create/destroy widget tree
  - Context menu APIs
  - Drag'n'Drop APIs
- Kernel Drawing/Graphics API
  - Semantic Drawing API
  - Screenshot API
    - Query semantic information
  => Framebuffer
- Update File APIs
  - Add/set mime-type
  - Store mime-type in database
- Clipboard system
  - Set
  - Get
  => clipboard.set
  => clipboard.get_type
  => clipboard.get_value
- Service Methods
  - Register/unregister service
  - Query registered services
  => service.register
  => service.unregister
  => service.count
  => service.get
- Input drivers can have an associated video output for absolute positioning

# List

```zig
draw.clear                (*const Framebuffer, ColorIndex) void 
draw.line                 (*const Framebuffer, ColorIndex, x0:i16,y0:16,x1:i16,y1:i16) void
draw.draw_rect            (*const Framebuffer, ColorIndex, x0:i16,y0:16,x1:i16,y1:i16) void
draw.fill_rect            (*const Framebuffer, ColorIndex, x0:i16,y0:16,x1:i16,y1:i16) void

# ui.createWindow           (title: [*]const u8, title_len: usize, min: Size, max: Size, startup: Size, flags: CreateWindowFlags) ?*const Window
# ui.destroyWindow          (*const Window) void
# ui.getSystemFont          (font_name_ptr: [*]const u8, font_name_len: usize, font_data_ptr: *[*]const u8, font_data_len: *usize) GetSystemFontError.Enum
# ui.invalidate             (*const Window, rect: Rectangle) void
# ui.moveWindow             (*const Window, x: i16, y: i16) void
# ui.resizeWindow           (*const Window, x: u16, y: u16) void
# ui.setWindowTitle         (*const Window, title: [*]const u8, title_len: usize) void -->


```