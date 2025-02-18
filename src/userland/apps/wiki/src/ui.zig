const std = @import("std");
const ashet = @import("ashet");
const gui = @import("ashet-gui");
const system_assets = @import("system-assets");
const Widget = gui.Widget;
const Rectangle = gui.Rectangle;
const Interface = gui.Interface;
const Layout = @This();

pub const Icons = struct {
    back: ashet.graphics.Framebuffer,
    forward: ashet.graphics.Framebuffer,
    home: ashet.graphics.Framebuffer,
    menu: ashet.graphics.Framebuffer,
};

interface: Interface = .{},

untitled_widget_0: Widget = undefined,
nav_backward: Widget = undefined,
nav_forward: Widget = undefined,
nav_home: Widget = undefined,
app_menu: Widget = undefined,
tree_scrollbar: Widget = undefined,
doc_h_scrollbar: Widget = undefined,
doc_v_scrollbar: Widget = undefined,
tree_view: Widget = undefined,
doc_view: Widget = undefined,

pub fn layout(self: *Layout, container_rectangle: Rectangle) void {
    self.untitled_widget_0.bounds.x = 0; // $window.left
    const w0_right: i16 = @as(i16, @intCast(container_rectangle.width)); // $window.right
    self.untitled_widget_0.bounds.y = 0; // $window.top
    self.nav_backward.bounds.x = self.untitled_widget_0.bounds.x + 4; // untitled_widget_0.left + 4
    const w1_right: i16 = self.nav_backward.bounds.x + @as(i16, @intCast(self.nav_backward.bounds.width));
    self.nav_backward.bounds.y = self.untitled_widget_0.bounds.y + 4; // untitled_widget_0.top + 4
    const w1_bottom: i16 = self.nav_backward.bounds.y + @as(i16, @intCast(self.nav_backward.bounds.height));
    self.nav_forward.bounds.x = w1_right + 4; // nav_backward.right + 4
    const w2_right: i16 = self.nav_forward.bounds.x + @as(i16, @intCast(self.nav_forward.bounds.width));
    self.nav_forward.bounds.y = self.untitled_widget_0.bounds.y + 4; // untitled_widget_0.top + 4
    const w2_bottom: i16 = self.nav_forward.bounds.y + @as(i16, @intCast(self.nav_forward.bounds.height));
    self.nav_home.bounds.x = w2_right + 4; // nav_forward.right + 4
    const w3_right: i16 = self.nav_home.bounds.x + @as(i16, @intCast(self.nav_home.bounds.width));
    self.nav_home.bounds.y = self.untitled_widget_0.bounds.y + 4; // untitled_widget_0.top + 4
    const w3_bottom: i16 = self.nav_home.bounds.y + @as(i16, @intCast(self.nav_home.bounds.height));
    const w4_right: i16 = w0_right - 4; // untitled_widget_0.right - 4
    self.app_menu.bounds.y = self.untitled_widget_0.bounds.y + 4; // untitled_widget_0.top + 4
    const w4_bottom: i16 = self.app_menu.bounds.y + @as(i16, @intCast(self.app_menu.bounds.height));
    const w6_bottom: i16 = @as(i16, @intCast(container_rectangle.height)); // $window.bottom
    const w7_right: i16 = @as(i16, @intCast(container_rectangle.width)); // $window.right
    self.tree_view.bounds.x = 0; // $window.left
    self.tree_view.bounds.width = 100; // 100
    const w0_bottom: i16 = w4_bottom + 4; // app_menu.bottom + 4
    self.tree_scrollbar.bounds.y = w0_bottom; // untitled_widget_0.bottom
    const w5_bottom: i16 = @as(i16, @intCast(container_rectangle.height)); // $window.bottom
    self.doc_v_scrollbar.bounds.y = w0_bottom; // untitled_widget_0.bottom
    const w7_bottom: i16 = @as(i16, @intCast(container_rectangle.height)) - 11; // $window.bottom - 11
    const w8_right: i16 = self.tree_view.bounds.x + @as(i16, @intCast(self.tree_view.bounds.width));
    self.tree_view.bounds.y = w0_bottom; // untitled_widget_0.bottom
    const w8_bottom: i16 = @as(i16, @intCast(container_rectangle.height)); // $window.bottom
    self.doc_view.bounds.y = w0_bottom; // untitled_widget_0.bottom
    const w9_bottom: i16 = self.doc_h_scrollbar.bounds.y; // doc_h_scrollbar.top
    self.tree_scrollbar.bounds.x = w8_right; // tree_view.right
    const w5_right: i16 = self.tree_scrollbar.bounds.x + @as(i16, @intCast(self.tree_scrollbar.bounds.width));
    self.doc_h_scrollbar.bounds.x = w5_right; // tree_scrollbar.right
    const w6_right: i16 = @as(i16, @intCast(container_rectangle.width)) - 11; // $window.right - 11
    self.doc_view.bounds.x = w5_right; // tree_scrollbar.right
    const w9_right: i16 = self.doc_v_scrollbar.bounds.x; // doc_v_scrollbar.left
    self.untitled_widget_0.bounds.width = @intCast(@max(0, w0_right - self.untitled_widget_0.bounds.x)); // untitled_widget_0.right
    self.nav_backward.bounds.width = @intCast(@max(0, w1_right - self.nav_backward.bounds.x)); // nav_backward.right
    self.nav_backward.bounds.height = @intCast(@max(0, w1_bottom - self.nav_backward.bounds.y)); // nav_backward.bottom
    self.nav_forward.bounds.width = @intCast(@max(0, w2_right - self.nav_forward.bounds.x)); // nav_forward.right
    self.nav_forward.bounds.height = @intCast(@max(0, w2_bottom - self.nav_forward.bounds.y)); // nav_forward.bottom
    self.nav_home.bounds.width = @intCast(@max(0, w3_right - self.nav_home.bounds.x)); // nav_home.right
    self.nav_home.bounds.height = @intCast(@max(0, w3_bottom - self.nav_home.bounds.y)); // nav_home.bottom
    self.app_menu.bounds.x = w4_right - @as(i16, @intCast(self.app_menu.bounds.width)); // app_menu.right
    self.app_menu.bounds.height = @intCast(@max(0, w4_bottom - self.app_menu.bounds.y)); // app_menu.bottom
    self.doc_h_scrollbar.bounds.y = w6_bottom - @as(i16, @intCast(self.doc_h_scrollbar.bounds.height)); // doc_h_scrollbar.bottom
    self.doc_v_scrollbar.bounds.x = w7_right - @as(i16, @intCast(self.doc_v_scrollbar.bounds.width)); // doc_v_scrollbar.right
    self.untitled_widget_0.bounds.height = @intCast(@max(0, w0_bottom - self.untitled_widget_0.bounds.y)); // untitled_widget_0.bottom
    self.tree_scrollbar.bounds.height = @intCast(@max(0, w5_bottom - self.tree_scrollbar.bounds.y)); // tree_scrollbar.bottom
    self.doc_v_scrollbar.bounds.height = @intCast(@max(0, w7_bottom - self.doc_v_scrollbar.bounds.y)); // doc_v_scrollbar.bottom
    self.tree_view.bounds.x = w8_right - @as(i16, @intCast(self.tree_view.bounds.width)); // tree_view.right
    self.tree_view.bounds.height = @intCast(@max(0, w8_bottom - self.tree_view.bounds.y)); // tree_view.bottom
    self.doc_view.bounds.height = @intCast(@max(0, w9_bottom - self.doc_view.bounds.y)); // doc_view.bottom
    self.tree_scrollbar.bounds.width = @intCast(@max(0, w5_right - self.tree_scrollbar.bounds.x)); // tree_scrollbar.right
    self.doc_h_scrollbar.bounds.width = @intCast(@max(0, w6_right - self.doc_h_scrollbar.bounds.x)); // doc_h_scrollbar.right
    self.doc_view.bounds.width = @intCast(@max(0, w9_right - self.doc_view.bounds.x)); // doc_view.right
}
pub fn linkAndInit(self: *Layout, icons: Icons) void {
    self.* = Layout{};
    self.untitled_widget_0 = gui.Panel.new(5, 5, 172, 57);
    self.nav_backward = gui.ToolButton.new(69, 42, icons.back);
    self.nav_forward = gui.ToolButton.new(69, 42, icons.forward);
    self.nav_home = gui.ToolButton.new(69, 42, icons.home);
    self.app_menu = gui.ToolButton.new(69, 42, icons.menu);
    self.tree_scrollbar = gui.ScrollBar.new(0, 0, .vertical, 100, 1000);
    self.doc_h_scrollbar = gui.ScrollBar.new(0, 0, .horizontal, 100, 1000);
    self.doc_v_scrollbar = gui.ScrollBar.new(0, 0, .vertical, 100, 1000);
    self.tree_view = gui.Panel.new(5, 5, 172, 57);
    self.doc_view = gui.Panel.new(5, 5, 172, 57);
    self.interface.appendWidget(&self.untitled_widget_0);
    self.interface.appendWidget(&self.nav_backward);
    self.interface.appendWidget(&self.nav_forward);
    self.interface.appendWidget(&self.nav_home);
    self.interface.appendWidget(&self.app_menu);
    self.interface.appendWidget(&self.tree_scrollbar);
    self.interface.appendWidget(&self.doc_h_scrollbar);
    self.interface.appendWidget(&self.doc_v_scrollbar);
    self.interface.appendWidget(&self.tree_view);
    self.interface.appendWidget(&self.doc_view);
}
