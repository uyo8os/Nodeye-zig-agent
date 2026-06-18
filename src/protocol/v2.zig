const std = @import("std");

pub const Version = "2.0";
pub const MethodAgentReport = "agent.report";
pub const MethodAgentBasicInfo = "agent.basicInfo";
pub const MethodAgentPingResult = "agent.pingResult";
pub const MethodAgentTaskResult = "agent.taskResult";
pub const MethodAgentExec = "agent.exec";
pub const MethodAgentPing = "agent.ping";
pub const MethodAgentMessage = "agent.message";
pub const MethodAgentEvent = "agent.event";
pub const MethodAgentTerminal = "agent.terminal.request";
pub const MethodAgentPull = "agent.pull";

pub const RpcError = struct {
    code: i32 = 0,
    message: []const u8 = "",
};

pub const Event = struct {
    id: []const u8 = "",
    method: []const u8 = "",
    params: ?std.json.Value = null,
};

pub const EventResult = struct {
    status: []const u8 = "",
    events: []Event = &.{},
};

pub const ParsedResponse = struct {
    result: ?std.json.Value = null,
    rpc_error: ?RpcError = null,
};

pub const PullParams = struct {
    capabilities: []const []const u8,
    ack_event_ids: []const []const u8,
};

pub fn writeNotification(writer: anytype, method: []const u8, params_json: []const u8) !void {
    try writer.print("{{\"jsonrpc\":\"{s}\",\"method\":{f}", .{ Version, std.json.fmt(method, .{}) });
    if (params_json.len != 0) try writer.print(",\"params\":{s}", .{params_json});
    try writer.writeAll("}");
}

pub fn writeRequest(writer: anytype, id: []const u8, method: []const u8, params_json: []const u8) !void {
    try writer.print("{{\"jsonrpc\":\"{s}\",\"method\":{f}", .{ Version, std.json.fmt(method, .{}) });
    if (params_json.len != 0) try writer.print(",\"params\":{s}", .{params_json});
    try writer.print(",\"id\":{f}}}", .{std.json.fmt(id, .{})});
}

pub fn allocReportNotification(allocator: std.mem.Allocator, report_json: []const u8) ![]u8 {
    var params = std.Io.Writer.Allocating.init(allocator);
    defer params.deinit();
    try params.writer.print("{{\"report\":{s}}}", .{report_json});

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeNotification(&out.writer, MethodAgentReport, params.writer.buffered());
    return out.toOwnedSlice();
}

pub fn allocReportRequest(allocator: std.mem.Allocator, id: []const u8, report_json: []const u8, ack_event_ids: []const []const u8) ![]u8 {
    var params = std.Io.Writer.Allocating.init(allocator);
    defer params.deinit();
    try params.writer.print("{{\"report\":{s},\"ack_event_ids\":[", .{report_json});
    for (ack_event_ids, 0..) |ack_id, i| {
        if (i != 0) try params.writer.writeAll(",");
        try params.writer.print("{f}", .{std.json.fmt(ack_id, .{})});
    }
    try params.writer.writeAll("]}");

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeRequest(&out.writer, id, MethodAgentReport, params.writer.buffered());
    return out.toOwnedSlice();
}

pub fn allocBasicInfoNotification(allocator: std.mem.Allocator, info_json: []const u8) ![]u8 {
    var params = std.Io.Writer.Allocating.init(allocator);
    defer params.deinit();
    try params.writer.print("{{\"info\":{s}}}", .{info_json});

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeNotification(&out.writer, MethodAgentBasicInfo, params.writer.buffered());
    return out.toOwnedSlice();
}

pub fn allocPingResultNotification(
    allocator: std.mem.Allocator,
    task_id: u64,
    ping_type: []const u8,
    value: i64,
    finished_at: []const u8,
) ![]u8 {
    var params = std.Io.Writer.Allocating.init(allocator);
    defer params.deinit();
    try params.writer.print(
        "{{\"task_id\":{},\"ping_type\":{f},\"value\":{},\"finished_at\":{f}}}",
        .{ task_id, std.json.fmt(ping_type, .{}), value, std.json.fmt(finished_at, .{}) },
    );
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeNotification(&out.writer, MethodAgentPingResult, params.writer.buffered());
    return out.toOwnedSlice();
}

pub fn allocTaskResultNotification(
    allocator: std.mem.Allocator,
    task_id: []const u8,
    result: []const u8,
    exit_code: i32,
    finished_at: []const u8,
) ![]u8 {
    var params = std.Io.Writer.Allocating.init(allocator);
    defer params.deinit();
    try params.writer.print(
        "{{\"task_id\":{f},\"result\":{f},\"exit_code\":{},\"finished_at\":{f}}}",
        .{ std.json.fmt(task_id, .{}), std.json.fmt(result, .{}), exit_code, std.json.fmt(finished_at, .{}) },
    );
    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeNotification(&out.writer, MethodAgentTaskResult, params.writer.buffered());
    return out.toOwnedSlice();
}

pub fn allocPullRequest(allocator: std.mem.Allocator, id: []const u8, params: PullParams) ![]u8 {
    var body = std.Io.Writer.Allocating.init(allocator);
    defer body.deinit();
    try body.writer.writeAll("{\"capabilities\":[");
    for (params.capabilities, 0..) |capability, i| {
        if (i != 0) try body.writer.writeAll(",");
        try body.writer.print("{f}", .{std.json.fmt(capability, .{})});
    }
    try body.writer.writeAll("],\"ack_event_ids\":[");
    for (params.ack_event_ids, 0..) |ack_id, i| {
        if (i != 0) try body.writer.writeAll(",");
        try body.writer.print("{f}", .{std.json.fmt(ack_id, .{})});
    }
    try body.writer.writeAll("]}");

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try writeRequest(&out.writer, id, MethodAgentPull, body.writer.buffered());
    return out.toOwnedSlice();
}

pub fn parseResponse(allocator: std.mem.Allocator, body: []const u8) !ParsedResponse {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    if (parsed.value != .object) return error.InvalidV2Response;
    const object = parsed.value.object;
    const jsonrpc = object.get("jsonrpc") orelse return error.InvalidV2Response;
    if (jsonrpc != .string or !std.mem.eql(u8, jsonrpc.string, Version)) return error.InvalidV2Response;

    var result: ParsedResponse = .{};
    if (object.get("error")) |err_value| {
        if (err_value != .object) return error.InvalidV2Response;
        const err_obj = err_value.object;
        result.rpc_error = .{
            .code = intField(err_obj, "code"),
            .message = stringField(err_obj, "message"),
        };
    }
    if (object.get("result")) |result_value| {
        result.result = result_value;
    }
    return result;
}

pub fn parseEventResult(allocator: std.mem.Allocator, value: std.json.Value) !EventResult {
    if (value != .object) return error.InvalidV2EventResult;
    const object = value.object;
    var events_out: std.ArrayList(Event) = .empty;
    errdefer {
        for (events_out.items) |event| {
            allocator.free(event.id);
            allocator.free(event.method);
        }
        events_out.deinit(allocator);
    }

    if (object.get("events")) |events_value| {
        if (events_value != .array) return error.InvalidV2EventResult;
        for (events_value.array.items) |item| {
            if (item != .object) continue;
            const event_obj = item.object;
            try events_out.append(allocator, .{
                .id = try allocator.dupe(u8, stringField(event_obj, "id")),
                .method = try allocator.dupe(u8, stringField(event_obj, "method")),
                .params = event_obj.get("params"),
            });
        }
    }

    return .{
        .status = if (object.get("status")) |status| if (status == .string) try allocator.dupe(u8, status.string) else try allocator.dupe(u8, "") else try allocator.dupe(u8, ""),
        .events = try events_out.toOwnedSlice(allocator),
    };
}

pub fn deinitEventResult(allocator: std.mem.Allocator, result: EventResult) void {
    allocator.free(result.status);
    for (result.events) |event| {
        allocator.free(event.id);
        allocator.free(event.method);
    }
    allocator.free(result.events);
}

fn intField(object: std.json.ObjectMap, key: []const u8) i32 {
    if (object.get(key)) |value| {
        return switch (value) {
            .integer => |n| @intCast(n),
            .string => |text| std.fmt.parseInt(i32, text, 10) catch 0,
            else => 0,
        };
    }
    return 0;
}

fn stringField(object: std.json.ObjectMap, key: []const u8) []const u8 {
    if (object.get(key)) |value| {
        if (value == .string) return value.string;
    }
    return "";
}
