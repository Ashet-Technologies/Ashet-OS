const std = @import("std");
const ashet = @import("ashet");

const logger = std.log.scoped(.dirt_track);

const Rectangle = ashet.abi.Rectangle;

const DamageTracking = @This();

tracked_area: Rectangle,

invalidation_areas: std.BoundedArray(Rectangle, 8) = .{},

pub fn init(tracked_area: Rectangle) DamageTracking {
    return .{
        .tracked_area = tracked_area,
    };
}

pub fn clear(dt: *DamageTracking) void {
    dt.invalidation_areas.len = 0;
}

pub fn tainted_regions(dt: *const DamageTracking) []const Rectangle {
    return dt.invalidation_areas.constSlice();
}

pub fn is_tainted(dt: DamageTracking) bool {
    return (dt.invalidation_areas.len > 0);
}

pub fn invalidate_screen(dt: *DamageTracking) void {
    dt.invalidation_areas.len = 1;
    dt.invalidation_areas.buffer[0] = dt.tracked_area;
}

pub fn invalidate_region(dt: *DamageTracking, region: Rectangle) void {
    if (region.empty())
        return;

    const target = dt.tracked_area.overlap(region);

    // check if we already have this region invalidated
    for (dt.invalidation_areas.slice()) |rect| {
        if (rect.containsRectangle(target))
            return;
    }

    logger.debug("invalidate {}", .{target});

    if (dt.invalidation_areas.len == dt.invalidation_areas.capacity()) {
        dt.invalidation_areas.len = 1;
        dt.invalidation_areas.buffer[0] = dt.tracked_area;
        return;
    }

    dt.invalidation_areas.appendAssumeCapacity(target);
}

pub fn is_area_tainted(dt: DamageTracking, rect: Rectangle) bool {
    for (dt.invalidation_areas.slice()) |r| {
        if (r.intersects(rect))
            return true;
    }
    return false;
}
