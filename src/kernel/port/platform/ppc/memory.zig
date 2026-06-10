pub inline fn cachedFromPhysical(ptr: anytype) @TypeOf(ptr) {
    const address: usize = @intFromPtr(ptr);
    return @ptrFromInt(address + @as(usize, 0x80000000));
}

pub inline fn physicalFromPtr(ptr: anytype) @TypeOf(ptr) {
    const address: usize = @intFromPtr(ptr);
    return @ptrFromInt(address & ~@as(usize, 0xC0000000));
}

pub inline fn uncachedFromCached(ptr: anytype) @TypeOf(ptr) {
    const address: usize = @intFromPtr(ptr);
    return @ptrFromInt(address + @as(usize, 0xC0000000 - 0x80000000));
}

pub inline fn cachedFromUncached(ptr: anytype) @TypeOf(ptr) {
    const address: usize = @intFromPtr(ptr);
    return @ptrFromInt(address - @as(usize, 0xC0000000 - 0x80000000));
}
