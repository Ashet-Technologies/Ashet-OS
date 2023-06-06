const std = @import("std");
const ashet = @import("ashet");
const gui = @import("ashet-gui");
const system_assets = @import("system-assets");

pub usingnamespace ashet.core;

const CoolBarSpec = struct {
    near_blocks: []const Section = &.{},
    expand_block: Section = .{},
    far_blocks: []const Section = &.{},

    const Section = struct {
        widgets: []const *gui.Widget = &.{},
    };
};

const CoolBar = struct {
    spec: *const CoolBarSpec,
    panels: []gui.Widget,

    pub fn create(comptime spec: CoolBarSpec) CoolBar {
        const count = spec.near_blocks.len + spec.far_blocks.len + 1;

        const Storage = struct {
            var panels: [count]gui.Widget = undefined;
        };

        return CoolBar{
            .spec = &spec,
            .panels = &Storage.panels,
        };
    }

    pub fn layout(cb: *CoolBar, target: gui.Rectangle) void {
        _ = cb;
        _ = target;
    }
};

var new_tab_button: gui.Widget = gui.ToolButton.new(0, 0, gui.Bitmap.embed(system_assets.@"system/icons/plus.abm").bitmap);
var copy_button: gui.Widget = gui.ToolButton.new(0, 0, gui.Bitmap.embed(system_assets.@"system/icons/copy.abm").bitmap);
var cut_button: gui.Widget = gui.ToolButton.new(0, 0, gui.Bitmap.embed(system_assets.@"system/icons/cut.abm").bitmap);
var paste_button: gui.Widget = gui.ToolButton.new(0, 0, gui.Bitmap.embed(system_assets.@"system/icons/paste.abm").bitmap);
var menu_button: gui.Widget = gui.ToolButton.new(0, 0, gui.Bitmap.embed(system_assets.@"system/icons/menu.abm").bitmap);

const app_bar = CoolBar.create(.{
    .near_blocks = &.{
        .{ .widgets = &.{&new_tab_button} },
        .{ .widgets = &.{ &copy_button, &cut_button, &paste_button } },
    },
    .far_blocks = &.{
        .{
            .widgets = &.{&menu_button},
        },
    },
});

pub fn main() !void {
    try gui.init();

    _ = app_bar;

    const window = try ashet.ui.createWindow(
        "Connex",
        ashet.abi.Size.new(100, 50),
        ashet.abi.Size.max,
        ashet.abi.Size.new(200, 150),
        .{ .popup = false },
    );
    defer ashet.ui.destroyWindow(window);

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
