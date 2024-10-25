const std = @import("std");
const ashet = @import("../main.zig");
const libashet = @import("ashet");
const logger = std.log.scoped(.apps);

pub const AppID = struct {
    name: []const u8,

    fn getName(app: AppID) []const u8 {
        return app.name;
    }
};

pub fn startApp(app: AppID) !void {
    var apps_dir = try libashet.fs.Directory.openDrive(.system, "apps");
    defer apps_dir.close();

    var app_file_buf: [120]u8 = undefined;

    const app_file_name = try std.fmt.bufPrint(&app_file_buf, "{s}.ashex", .{
        app.getName(),
    });

    var file = try apps_dir.openFile(app_file_name, .read_only, .open_existing);
    defer file.close();

    _ = try ashet.multi_tasking.spawn_blocking(app.getName(), &file, &.{});
}
