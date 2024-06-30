const std = @import("std");
const ashet = @import("ashet");

pub usingnamespace ashet.core;

pub fn main() !void {
    ashet.debug.write("Hello from App!\r\n");

    const window = try ashet.ui.createWindow(
        "Shepard",
        ashet.abi.Size.new(96, 48),
        ashet.abi.Size.new(96, 48),
        ashet.abi.Size.new(96, 48),
        .{ .popup = true },
    );
    defer ashet.ui.destroyWindow(window);

    for (window.pixels[0 .. window.stride * window.max_size.height]) |*c| {
        c.* = ashet.ui.ColorIndex.get(0);
    }

    const cx = (window.max_size.width - dummy_logo[0].len) / 2;
    const cy = (window.max_size.height - dummy_logo.len) / 2;

    for (dummy_logo, 0..) |row, y| {
        for (row, 0..) |pixel, x| {
            if (pixel) |color| {
                window.pixels[window.stride * (cy + y) + (cx + x)] = color;
            }
        }
    }

    app_loop: while (true) {
        const event = ashet.ui.getEvent(window);
        switch (event) {
            .mouse => {},
            .keyboard => {},
            .window_close => break :app_loop,
            .window_minimize => {},
            .window_restore => {},
            .window_moving => {},
            .window_moved => {},
            .window_resizing => {},
            .window_resized => {},
        }
    }
}

pub const dummy_logo = parse(
    \\                  FFFF                                           
    \\                  F   F                                          
    \\                  F   F F   F FFFF  FFFF  F   F                  
    \\                  F   F F   F F F F F F F F   F                  
    \\                  F   F F   F F F F F F F F   F                  
    \\                  F   F F   F F F F F F F F   F                  
    \\                  F   F F   F F   F F   F F   F                  
    \\                  FFFF   FFFF F   F F   F  FFFF                  
    \\                                              F                  
    \\                                              F                  
    \\                                          FFFF                   
    \\                                                                 
    \\ FFF               F      F                F      F              
    \\F   F              F                       F                     
    \\F   F FFFF  FFFF   F     FF    FFFF  FFF  FFF    FF    FFF  FFFF 
    \\F   F F   F F   F  F      F   F         F  F      F   F   F F   F
    \\FFFFF F   F F   F  F      F   F      FFFF  F      F   F   F F   F
    \\F   F F   F F   F  F      F   F     F   F  F      F   F   F F   F
    \\F   F F   F F   F  F      F   F     F   F  F      F   F   F F   F
    \\F   F FFFF  FFFF    FF    FF   FFFF  FFFF   FF    FF   FFF  F   F
    \\      F     F                                                    
    \\      F     F                                                    
    \\      F     F                                                    
);

fn parsedSpriteSize(comptime def: []const u8) ashet.ui.Size {
    @setEvalBranchQuota(100_000);
    var it = std.mem.splitScalar(u8, def, '\n');
    const first = it.next().?;
    const width = first.len;
    var height = 1;
    while (it.next()) |line| {
        std.debug.assert(line.len == width);
        height += 1;
    }
    return .{ .width = width, .height = height };
}

fn ParseResult(comptime def: []const u8) type {
    @setEvalBranchQuota(100_000);
    const size = parsedSpriteSize(def);
    return [size.height][size.width]?ashet.ui.ColorIndex;
}

fn parse(comptime def: []const u8) ParseResult(def) {
    @setEvalBranchQuota(100_000);

    const size = parsedSpriteSize(def);
    var icon: [size.height][size.width]?ashet.ui.ColorIndex = [1][size.width]?ashet.ui.ColorIndex{
        [1]?ashet.ui.ColorIndex{null} ** size.width,
    } ** size.height;

    var it = std.mem.splitScalar(u8, def, '\n');
    var y: usize = 0;
    while (it.next()) |line| : (y += 1) {
        var x: usize = 0;
        while (x < icon[0].len) : (x += 1) {
            icon[y][x] = if (std.fmt.parseInt(u8, line[x .. x + 1], 16)) |index|
                ashet.ui.ColorIndex.get(index)
            else |_|
                null;
        }
    }
    return icon;
}
