const builtin = @import("builtin");
const std = @import("std");
const compat = @import("compat");

test "windows native piped process captures shell output" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    var child = try compat.spawnWindowsPiped(
        std.testing.allocator,
        &.{ "powershell.exe", "-NoLogo", "-NoProfile", "-Command", "[Console]::Out.Write('terminal-pipe-ok')" },
        null,
    );
    errdefer compat.terminateWindowsProcess(child.process.process, 1);
    defer {
        child.stdin.close(std.Options.debug_io);
        child.stdout.close(std.Options.debug_io);
        compat.closeWindowsProcessHandles(&child.process);
    }

    var reader_buf: [1024]u8 = undefined;
    var reader = child.stdout.reader(std.Options.debug_io, &reader_buf);
    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    var buf: [256]u8 = undefined;
    while (true) {
        const n = try reader.interface.readSliceShort(&buf);
        if (n == 0) break;
        try out.writer.writeAll(buf[0..n]);
    }

    try std.testing.expect(compat.waitWindowsProcess(child.process.process, 5000));
    const output = try out.toOwnedSlice();
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualStrings("terminal-pipe-ok", output);
}
