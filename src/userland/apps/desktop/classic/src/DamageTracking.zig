const std = @import("std");
const ashet = @import("ashet");

const logger = std.log.scoped(.dirt_track);

const Rectangle = ashet.abi.Rectangle;

const DamageTracking = @This();

tracked_area: Rectangle,

invalidation_areas: std.ArrayList(Rectangle),

pub fn init(tracked_area: Rectangle, tracking_buffer: []Rectangle) DamageTracking {
    std.debug.assert(tracking_buffer.len >= 1);
    return .{
        .tracked_area = tracked_area,
        .invalidation_areas = .initBuffer(tracking_buffer),
    };
}

pub fn clear(dt: *DamageTracking) void {
    dt.invalidation_areas.clearRetainingCapacity();
}

pub fn tainted_regions(dt: *const DamageTracking) []const Rectangle {
    return dt.invalidation_areas.items;
}

pub fn is_tainted(dt: DamageTracking) bool {
    return (dt.invalidation_areas.items.len > 0);
}

pub fn invalidate_screen(dt: *DamageTracking) void {
    dt.invalidation_areas.clearRetainingCapacity();
    dt.invalidation_areas.appendAssumeCapacity(dt.tracked_area);
}

pub fn invalidate_region(dt: *DamageTracking, region: Rectangle) void {
    if (region.empty())
        return;

    const target = dt.tracked_area.overlappedRegion(region);

    // check if we already have this region invalidated
    for (dt.invalidation_areas.items) |rect| {
        if (rect.containsRectangle(target))
            return;
    }

    // logger.debug("invalidate {}", .{target});

    if (dt.invalidation_areas.items.len == dt.invalidation_areas.capacity) {
        dt.invalidate_screen();
        return;
    }

    dt.invalidation_areas.appendAssumeCapacity(target);
}

pub fn is_area_tainted(dt: DamageTracking, rect: Rectangle) bool {
    for (dt.invalidation_areas.items) |r| {
        if (r.intersects(rect))
            return true;
    }
    return false;
}
