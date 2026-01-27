pub const datetime = struct {
    pub const DateTime = packed struct(i64) {
        milliseconds_of_day: u32, // 0 to 86,399,999
        days_since_epoch: i32, // 2000-01-01 = 0
    };

    pub const GregorianDate = struct {
        year: i16, // ± 32000
        month: u8, // 1-12
        day: u8, // 1-31
        hour: u8, // 0-23
        minute: u8, // 0-59
        second: u8, // 0-59
        millis: u16, // 0-999
    };

    // Syscalls
    pub fn local_now() DateTime;
    pub fn utc_now() DateTime;

    pub fn set_local(dt: DateTime) !void;
    pub fn set_utc(dt: DateTime) !void;

    pub fn from_gregorian(date: GregorianDate) !DateTime;
    pub fn to_gregorian(dt: DateTime) GregorianDate;

    pub fn to_local_gregorian(dt: DateTime) GregorianDate;
    pub fn to_utc_gregorian(dt: DateTime) GregorianDate;

    // Timezone management
    pub fn set_timezone_offset(offset_seconds: i16) void;
    pub fn get_timezone_offset() i16;

    // Optional: full tzdata support
    pub fn load_timezone_data(data: []const u8) !void;
};
