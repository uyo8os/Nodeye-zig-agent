const std = @import("std");

const fallback_threshold = 3;

var requested_protocol_version = std.atomic.Value(i32).init(2);
var connection_protocol_version = std.atomic.Value(i32).init(0);
var v2_protocol_failures = std.atomic.Value(u32).init(0);

pub fn initRequestedProtocolVersion(version: i32) void {
    requested_protocol_version.store(if (version >= 2) 2 else 1, .release);
}

pub fn requestedProtocolVersion() i32 {
    return if (requested_protocol_version.load(.acquire) >= 2) 2 else 1;
}

pub fn uploadProtocolVersion() i32 {
    const connection_version = connection_protocol_version.load(.acquire);
    if (connection_version > 0) return connection_version;
    return requestedProtocolVersion();
}

pub fn setConnectionProtocolVersion(version: i32) void {
    connection_protocol_version.store(version, .release);
    if (version >= 2) v2_protocol_failures.store(0, .release);
}

pub fn resetConnectionProtocolVersion() void {
    connection_protocol_version.store(0, .release);
    v2_protocol_failures.store(0, .release);
}

pub fn resetV2ProtocolFailures(protocol_version: i32) void {
    if (protocol_version >= 2 and requestedProtocolVersion() >= 2) {
        v2_protocol_failures.store(0, .release);
    }
}

pub fn noteV2AttemptResult(protocol_version: i32, err: ?anyerror) struct { failures: u32, fallback: bool } {
    if (protocol_version < 2 or requestedProtocolVersion() < 2) return .{ .failures = 0, .fallback = false };
    if (err == null) {
        resetV2ProtocolFailures(protocol_version);
        return .{ .failures = 0, .fallback = false };
    }
    if (!isV2ProtocolFailure(err.?)) {
        return .{ .failures = v2_protocol_failures.load(.acquire), .fallback = false };
    }
    const failures = v2_protocol_failures.fetchAdd(1, .acq_rel) + 1;
    return .{ .failures = failures, .fallback = failures >= fallback_threshold };
}

pub fn shouldFallbackToV1(protocol_version: i32, err: anyerror) bool {
    const result = noteV2AttemptResult(protocol_version, err);
    return result.fallback;
}

pub fn isV2ProtocolFailure(err: anyerror) bool {
    return switch (err) {
        error.HttpStatusNotOk,
        error.HttpRedirectMissingLocation,
        error.HttpTooManyRedirects,
        error.HttpResponseTooLarge,
        error.WebSocketHandshakeFailed,
        error.InvalidHttpResponse,
        error.InvalidV2Response,
        error.InvalidV2EventResult,
        => true,
        else => false,
    };
}
