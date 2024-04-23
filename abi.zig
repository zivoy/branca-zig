const std = @import("std");
const branca = @import("branca.zig");

comptime {
    @export(decodeStringC, .{ .name = "decodeString", .linkage = .strong });
    @export(encodeStringC, .{ .name = "encodeString", .linkage = .strong });
    @export(decodeC, .{ .name = "decode", .linkage = .strong });
    @export(encodeC, .{ .name = "encode", .linkage = .strong });
    @export(getTimestampStringC, .{ .name = "getTimestampString", .linkage = .strong });
    @export(getTimestampC, .{ .name = "getTimestamp", .linkage = .strong });
}

fn getKey(key: [*:0]u8) ![branca.brancaKeyLength]u8 {
    const length = std.mem.indexOfSentinel(u8, 0, key);
    if (length != 32) {
        return error.InvalidKey;
    }
    return key[0..32].*;
}

const allocator = std.heap.c_allocator; //page_allocator

// maybe make a way to pass in an allocator
fn decodeStringC(key: [*:0]u8, token: [*]const u8, token_len: usize, output: [*]u8, output_len: usize) callconv(.C) usize {
    const akey = getKey(key) catch return 0;
    const tkn = token[0..token_len];
    const ret = branca.decodeString(allocator, akey, tkn) catch return 0;
    if (output_len < ret.len) return 0;
    @memcpy(output, ret);
    return ret.len;
}
fn encodeStringC(key: [*:0]u8, payload: [*]const u8, payload_len: usize, output: [*]u8, output_len: usize) callconv(.C) usize {
    const akey = getKey(key) catch return 0;
    const data = payload[0..payload_len];
    const ret = branca.encodeString(allocator, akey, data) catch return 0;
    if (output_len < ret.len) return 0;
    @memcpy(output, ret);
    return ret.len;
}
fn decodeC(key: [*:0]u8, token: [*]const u8, token_len: usize, output: [*]u8, output_len: usize) callconv(.C) usize {
    const akey = getKey(key) catch return 0;
    const tkn = token[0..token_len];
    const ret = branca.decode(allocator, akey, tkn) catch return 0;
    if (output_len < ret.len) return 0;
    @memcpy(output, ret);
    return ret.len;
}
fn encodeC(key: [*:0]u8, payload: [*]const u8, payload_len: usize, output: [*]u8, output_len: usize) callconv(.C) usize {
    const akey = getKey(key) catch return 0;
    const data = payload[0..payload_len];
    const ret = branca.encode(allocator, akey, data) catch return 0;
    if (output_len < ret.len) return 0;
    @memcpy(output, ret);
    return ret.len;
}
fn getTimestampStringC(token: [*]const u8, token_len: usize) callconv(.C) c_long {
    const tkn = token[0..token_len];
    return @intCast(branca.getTimestampString(allocator, tkn) catch 0);
}
fn getTimestampC(token: [*]const u8, token_len: usize) callconv(.C) c_long {
    const tkn = token[0..token_len];
    return @intCast(branca.getTimestamp(tkn) catch 0);
}
