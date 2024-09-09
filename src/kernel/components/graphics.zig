const std = @import("std");
const ashet = @import("../main.zig");

const fonts = @import("graphics/fonts.zig");
const software_renderer = @import("graphics/software_renderer.zig");

pub const Framebuffer = struct {
    pub const Destructor = ashet.resources.Destructor(@This(), _internal_destroy);

    pub const Type = union(ashet.abi.FramebufferType) {
        memory: software_renderer.Framebuffer,
        video: *ashet.video.Output,
        window: *ashet.gui.Window,
        widget: *ashet.gui.Widget,
    };

    system_resource: ashet.resources.SystemResource = .{ .type = .framebuffer },
    type: Type,

    pub const destroy = Destructor.destroy;

    fn _internal_destroy(fb: *Framebuffer) void {
        switch (fb.type) {
            .memory => {},
            .video => {},
            .window => {},
            .widget => {},
        }
        @panic("Not implemented yet!");
    }
};

pub const Font = struct {
    pub const Destructor = ashet.resources.Destructor(@This(), _internal_destroy);
    system_resource: ashet.resources.SystemResource = .{ .type = .font },

    pub const destroy = Destructor.destroy;

    fn _internal_destroy(sock: *Font) void {
        _ = sock;
        @panic("Not implemented yet!");
    }
};

pub fn render_async(call: *ashet.overlapped.AsyncCall, inputs: ashet.abi.draw.Render.Inputs) void {
    _ = call;
    _ = inputs;

    @panic("asynchronous rendering not implemented yet");
}
