const std = @import("std");
const suite = @import("agp-demosuite");

pub fn main() !void {
    var context = suite.create_context(std.heap.page_allocator);
    defer context.deinit();

    var framebuffer = try context.create_framebuffer(480, 320);
    defer framebuffer.deinit();

    const mono = try context.load_font(@embedFile("mono-6.font"), .{});
    const sans = try context.load_font(@embedFile("sans.font"), .{ .size = 12 });
    const enc = framebuffer.encoder();
    try enc.clear(.black);
    try enc.draw_line(100, 60, 200, 60, .white);
    try enc.draw_line(100, 70, 100, 150, .white);
    try enc.draw_rect(110, 70, 123, 35, .red);
    try enc.fill_rect(112, 72, 119, 31, .blue);
    try enc.set_pixel(100, 55, .red);
    try enc.set_pixel(102, 55, .green);
    try enc.set_pixel(104, 55, .blue);
    try enc.draw_line(100, 160, 110, 180, .red);
    try enc.draw_line(120, 160, 140, 180, .red);
    try enc.draw_line(150, 160, 180, 180, .red);
    try enc.draw_line(100, 210, 110, 190, .blue);
    try enc.draw_line(120, 210, 140, 190, .blue);
    try enc.draw_line(150, 210, 180, 190, .blue);
    try enc.draw_text(100, 230, mono, .purple, "Hello, World!");
    try enc.draw_text(100, 250, sans, .cyan, "Hello, World!");

    try framebuffer.write_to(std.fs.cwd(), "swrast.gif");
}
