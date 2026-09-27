# AGP demosuite

Host-side AGP rendering with `agp-swrast`. The package depends on `ashet-abi`,
`agp`, and `agp-swrast`.

```zig
const suite = @import("agp-demosuite");

var context = try suite.create_context(allocator, 640, 480);
defer context.deinit();

const font = try context.load_font(@embedFile("my.font"), .{ .size = 12 });
const size = try context.measure_text_size(font, "Hello");
const image = try suite.bitmap_from_abm(@embedFile("my.abm"));

const enc = context.encoder();
try enc.clear(.black);
try enc.draw_text(10, 10, font, .white, "Hello");
try enc.blit_bitmap(10, 20 + @as(i16, @intCast(size.height)), &image);

const commands = context.get_agp_stream();
const pixels = try context.get_framebuffer();
try context.write_to(std.fs.cwd(), "output.gif");
```

The command stream remains valid until the next encoder write. The framebuffer
is owned by the context and is refreshed on each render. Font and ABM byte
slices must remain alive while the context renders their commands.
