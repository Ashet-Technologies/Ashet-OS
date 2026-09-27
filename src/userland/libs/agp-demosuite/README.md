# AGP demosuite

Host-side AGP rendering with `agp-swrast`. The package depends on `ashet-abi`,
`agp`, and `agp-swrast`.

```zig
const suite = @import("agp-demosuite");

var context = suite.create_context(allocator);
defer context.deinit();
var framebuffer = try context.create_framebuffer(640, 480);
defer framebuffer.deinit();

const font = try context.load_font(@embedFile("my.font"), .{ .size = 12 });
const size = try context.measure_text_size(font, "Hello");
const image = try context.load_bitmap(@embedFile("my.abm"));

const enc = framebuffer.encoder();
try enc.clear(.black);
try enc.draw_text(10, 10, font, .white, "Hello");
try enc.blit_bitmap(10, 20 + @as(i16, @intCast(size.height)), image);

const commands = framebuffer.get_agp_stream();
const pixels = try framebuffer.render();
try framebuffer.write_to(std.fs.cwd(), "output.gif");

var other = try context.create_framebuffer(640, 480);
defer other.deinit();
try other.encoder().blit_framebuffer(0, 0, framebuffer.handle());
_ = try other.render();
```

The command stream remains valid until the next encoder write. Each framebuffer
owns its stream and pixels, which are refreshed on each render. The context
copies font and ABM pixel data into an arena; deinitialize framebuffers before
the context. Render a source framebuffer before blitting it into another one.
Create handles after moving framebuffer values into place; a handle becomes
invalid if its framebuffer moves again or is deinitialized.
