//     const width = ashet.video.max_res_x;
//     const height = ashet.video.max_res_y;
//     const bounds = Rectangle{ .x = 0, .y = 0, .width = framebuffer.width, .height = framebuffer.height };

//     const fb = ashet.video.memory[0 .. width * height];

//     fn setPixel(x: i16, y: i16, color: ColorIndex) void {
//         if (x < 0 or y < 0 or x >= width or y >= height) return;
//         const ux = @intCast(usize, x);
//         const uy = @intCast(usize, y);
//         fb[uy * width + ux] = color;
//     }

//     fn rectangle(x: i16, y: i16, w: u16, h: u16, color: ColorIndex) void {
//         var i: i16 = y;
//         while (i < y + @intCast(u15, h)) : (i += 1) {
//             framebuffer.horizontalLine(x, i, w, color);
//         }
//     }

//     fn icon(x: i16, y: i16, sprite: anytype) void {
//         for (sprite) |row, dy| {
//             for (row) |pix, dx| {
//                 const optpix: ?ColorIndex = pix; // allow both u8 and ?u8
//                 const color = optpix orelse continue;
//                 setPixel(x + @intCast(i16, dx), y + @intCast(i16, dy), color);
//             }
//         }
//     }

//     fn text(x: i16, y: i16, string: []const u8, max_width: u16, color: ColorIndex) void {
//         const gw = 6;
//         const gh = 8;
//         const font = ashet.video.defaults.font;

//         var dx: i16 = x;
//         var dy: i16 = y;
//         for (string) |char| {
//             if (dx + gw > x + @intCast(u15, max_width)) {
//                 break;
//             }
//             const glyph = font[char];

//             var gx: u15 = 0;
//             while (gx < gw) : (gx += 1) {
//                 var bits = glyph[gx];

//                 comptime var gy: u15 = 0;
//                 inline while (gy < gh) : (gy += 1) {
//                     if ((bits & (1 << gy)) != 0) {
//                         setPixel(dx + gx, dy + gy, color);
//                     }
//                 }
//             }

//             dx += gw;
//         }
//     }

//     fn clear(color: ColorIndex) void {
//         @memset( fb, color);
//     }
