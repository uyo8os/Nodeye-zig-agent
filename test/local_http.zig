const std = @import("std");

pub const RecordedRequest = struct {
    head: []u8,
    body: []u8,

    pub fn deinit(self: RecordedRequest, allocator: std.mem.Allocator) void {
        allocator.free(self.head);
        allocator.free(self.body);
    }

    pub fn requestLine(self: RecordedRequest) []const u8 {
        const end = std.mem.indexOf(u8, self.head, "\r\n") orelse self.head.len;
        return self.head[0..end];
    }

    pub fn header(self: RecordedRequest, name: []const u8) ?[]const u8 {
        var lines = std.mem.splitSequence(u8, self.head, "\r\n");
        _ = lines.next();
        while (lines.next()) |line| {
            if (line.len == 0) break;
            const sep = std.mem.indexOfScalar(u8, line, ':') orelse continue;
            const key = std.mem.trim(u8, line[0..sep], " \t");
            if (!std.ascii.eqlIgnoreCase(key, name)) continue;
            return std.mem.trim(u8, line[sep + 1 ..], " \t");
        }
        return null;
    }
};

pub const CompletedServer = struct {
    allocator: std.mem.Allocator,
    requests: []RecordedRequest,

    pub fn deinit(self: *CompletedServer) void {
        for (self.requests) |request| request.deinit(self.allocator);
        self.allocator.free(self.requests);
        self.* = undefined;
    }
};

pub const Server = struct {
    allocator: std.mem.Allocator,
    ctx: *Context,
    thread: std.Thread,
    joined: bool = false,

    const Context = struct {
        allocator: std.mem.Allocator,
        listener: std.Io.net.Server,
        responses: []const []const u8,
        requests: std.ArrayList(RecordedRequest) = .empty,
        err: ?anyerror = null,
    };

    pub fn start(allocator: std.mem.Allocator, responses: []const []const u8) !Server {
        var addr = try std.Io.net.IpAddress.parse("127.0.0.1", 0);
        var listener = try addr.listen(std.Options.debug_io, .{ .reuse_address = true });
        errdefer listener.deinit(std.Options.debug_io);

        const ctx = try allocator.create(Context);
        errdefer allocator.destroy(ctx);
        ctx.* = .{
            .allocator = allocator,
            .listener = listener,
            .responses = responses,
        };
        return .{
            .allocator = allocator,
            .ctx = ctx,
            .thread = try std.Thread.spawn(.{}, serve, .{ctx}),
        };
    }

    pub fn url(self: *const Server, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
        return std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}{s}", .{ self.ctx.listener.socket.address.getPort(), path });
    }

    pub fn join(self: *Server) !void {
        const ctx = self.ctx;
        defer self.allocator.destroy(ctx);
        defer freeRequests(self.allocator, &ctx.requests);
        try self.wait();
    }

    pub fn finish(self: *Server) !CompletedServer {
        const ctx = self.ctx;
        defer self.allocator.destroy(ctx);
        try self.wait();
        return .{
            .allocator = self.allocator,
            .requests = try ctx.requests.toOwnedSlice(self.allocator),
        };
    }

    fn serve(ctx: *Context) void {
        for (ctx.responses) |response| {
            var stream = ctx.listener.accept(std.Options.debug_io) catch |err| {
                ctx.err = err;
                return;
            };
            defer stream.close(std.Options.debug_io);

            const request = readRequest(ctx.allocator, &stream) catch |err| {
                ctx.err = err;
                return;
            };
            ctx.requests.append(ctx.allocator, request) catch |err| {
                request.deinit(ctx.allocator);
                ctx.err = err;
                return;
            };
            writeResponse(&stream, response) catch |err| {
                ctx.err = err;
                return;
            };
        }
    }

    fn readRequest(allocator: std.mem.Allocator, stream: *std.Io.net.Stream) !RecordedRequest {
        var reader_buf: [4096]u8 = undefined;
        var reader = stream.reader(std.Options.debug_io, &reader_buf);
        var head: std.ArrayList(u8) = .empty;
        errdefer head.deinit(allocator);
        while (head.items.len < 4096) {
            try head.append(allocator, try reader.interface.takeByte());
            if (std.mem.endsWith(u8, head.items, "\r\n\r\n")) break;
        }
        if (!std.mem.endsWith(u8, head.items, "\r\n\r\n")) return error.HttpRequestHeaderTooLarge;

        const content_length = parseContentLength(head.items) orelse 0;
        const body = try allocator.alloc(u8, content_length);
        errdefer allocator.free(body);
        if (content_length != 0) try reader.interface.readSliceAll(body);

        return .{
            .head = try head.toOwnedSlice(allocator),
            .body = body,
        };
    }

    fn writeResponse(stream: *std.Io.net.Stream, response: []const u8) !void {
        var writer_buf: [4096]u8 = undefined;
        var writer = stream.writer(std.Options.debug_io, &writer_buf);
        try writer.interface.writeAll(response);
        try writer.interface.flush();
    }

    fn wait(self: *Server) !void {
        if (!self.joined) {
            self.thread.join();
            self.ctx.listener.deinit(std.Options.debug_io);
            self.joined = true;
        }
        if (self.ctx.err) |err| return err;
    }

    fn freeRequests(allocator: std.mem.Allocator, requests: *std.ArrayList(RecordedRequest)) void {
        for (requests.items) |request| request.deinit(allocator);
        requests.deinit(allocator);
    }

    fn parseContentLength(head: []const u8) ?usize {
        var lines = std.mem.splitSequence(u8, head, "\r\n");
        _ = lines.next();
        while (lines.next()) |line| {
            if (line.len == 0) break;
            const sep = std.mem.indexOfScalar(u8, line, ':') orelse continue;
            const name = std.mem.trim(u8, line[0..sep], " \t");
            if (!std.ascii.eqlIgnoreCase(name, "Content-Length")) continue;
            const value = std.mem.trim(u8, line[sep + 1 ..], " \t");
            return std.fmt.parseInt(usize, value, 10) catch null;
        }
        return null;
    }
};
