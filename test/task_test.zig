const std = @import("std");
const task = @import("protocol_task");

test "utc timestamp formats as unsigned rfc3339" {
    const text = try task.utcFromTimestamp(std.testing.allocator, 0);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("1970-01-01T00:00:00Z", text);
}
