const std = @import("std");
const compat = @import("compat");

/// Timestamp helpers shared by protocol tasks (e.g. ping result reporting).
/// Remote command execution has been removed from this agent.
pub fn utcNow(allocator: std.mem.Allocator) ![]const u8 {
    return utcFromTimestamp(allocator, compat.unixTimestamp());
}

pub fn utcFromTimestamp(allocator: std.mem.Allocator, timestamp: i64) ![]const u8 {
    const date = civilFromTimestamp(timestamp);
    const seconds_of_day = @mod(timestamp, std.time.s_per_day);
    const hour = @divFloor(seconds_of_day, 3600);
    const minute = @divFloor(@mod(seconds_of_day, 3600), 60);
    const second = @mod(seconds_of_day, 60);
    return std.fmt.allocPrint(
        allocator,
        "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z",
        .{
            @as(u32, @intCast(date.year)),
            @as(u8, @intCast(date.month)),
            @as(u8, @intCast(date.day)),
            @as(u8, @intCast(hour)),
            @as(u8, @intCast(minute)),
            @as(u8, @intCast(second)),
        },
    );
}

const CivilDate = struct { year: i32, month: i32, day: i32 };

fn civilFromTimestamp(timestamp: i64) CivilDate {
    const days = @divFloor(timestamp, std.time.s_per_day);
    const z = days + 719468;
    const era = @divFloor(z, 146097);
    const doe: i32 = @intCast(z - era * 146097);
    const yoe = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    var year: i32 = @intCast(yoe + era * 400);
    const doy = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp = @divFloor(5 * doy + 2, 153);
    const day = doy - @divFloor(153 * mp + 2, 5) + 1;
    const month = mp + @as(i32, if (mp < 10) 3 else -9);
    year += if (month <= 2) 1 else 0;
    return .{ .year = year, .month = month, .day = day };
}
