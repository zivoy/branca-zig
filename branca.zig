const std = @import("std");
const base = @import("base-x").base;

pub const BrancaError = error{
    InvalidToken,
    InvalidVersion,
};

pub const Token = struct {
    message: []const u8,
    timestamp: u32,
};

pub const brancaKeyLength = 32;
const brancaVersion: u8 = 0xBA;
const timestampType = u32;

const nounceLength = 24; //[24]u8; // u192
const versionLength = 1; // @sizeOf(brancaVersion);
const timestampLength = @sizeOf(timestampType);
const brancaHeaderSize = versionLength + timestampLength + nounceLength;

const base62 = base("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz");

const chacha20poly1305 = std.crypto.aead.chacha_poly.XChaCha20Poly1305;

pub fn encode(allocator: std.mem.Allocator, key: [brancaKeyLength]u8, payload: []const u8) ![]const u8 {
    std.debug.assert(key.len == 32);

    const result = try allocator.alloc(u8, brancaHeaderSize + payload.len + chacha20poly1305.tag_length);

    result[0] = brancaVersion;
    const preNounceSize = versionLength + timestampLength;
    const time: timestampType = @intCast(std.time.timestamp());
    std.mem.writeInt(timestampType, result[versionLength..preNounceSize], time, std.builtin.Endian.big);

    std.crypto.random.bytes(result[preNounceSize .. preNounceSize + nounceLength]);
    const nounce: [nounceLength]u8 = result[preNounceSize .. preNounceSize + nounceLength].*;

    const payloadEnd = brancaHeaderSize + payload.len;
    const tag = @as(*[chacha20poly1305.tag_length]u8, @ptrCast(result[payloadEnd..]));
    chacha20poly1305.encrypt(result[brancaHeaderSize..payloadEnd], tag, payload, result[0..brancaHeaderSize], nounce, key);

    return result;
}

pub fn decode(allocator: std.mem.Allocator, key: [brancaKeyLength]u8, token: []const u8) ![]const u8 {
    if (token.len < brancaHeaderSize + chacha20poly1305.tag_length) {
        return BrancaError.InvalidToken;
    }
    if (token[0] != brancaVersion) {
        return BrancaError.InvalidVersion;
    }

    const result = try allocator.alloc(u8, token.len - brancaHeaderSize - chacha20poly1305.tag_length);

    const tag = @as(*[chacha20poly1305.tag_length]u8, @ptrCast(@constCast(token[token.len - chacha20poly1305.tag_length ..]))).*;
    const nounce = token[brancaHeaderSize - nounceLength .. brancaHeaderSize].*;
    const cypherText = token[brancaHeaderSize .. token.len - chacha20poly1305.tag_length];
    const header = token[0..brancaHeaderSize];

    try chacha20poly1305.decrypt(result, cypherText, tag, header, nounce, key);

    return result;
}
pub fn getTimestamp(token: []const u8) BrancaError!timestampType {
    if (token.len < brancaHeaderSize + chacha20poly1305.tag_length) {
        return BrancaError.InvalidToken;
    }
    if (token[0] != brancaVersion) {
        return BrancaError.InvalidVersion;
    }
    return std.mem.readInt(timestampType, token[versionLength .. versionLength + timestampLength], std.builtin.Endian.big);
}

////

pub fn encodeString(allocator: std.mem.Allocator, key: [brancaKeyLength]u8, payload: []const u8) ![]const u8 {
    const encoded = try encode(allocator, key, payload);
    defer allocator.free(encoded);
    const b62 = base62.init(allocator);
    return try b62.encode(encoded);
}

pub fn decodeString(allocator: std.mem.Allocator, key: [brancaKeyLength]u8, token: []const u8) ![]const u8 {
    const b62 = base62.init(allocator);
    const decoded = try b62.decode(token);
    defer allocator.free(decoded);
    return try decode(allocator, key, decoded);
}

pub fn getTimestampString(allocator: std.mem.Allocator, token: []const u8) !timestampType {
    const b62 = base62.init(allocator);
    const decoded = try b62.decode(token);
    defer allocator.free(decoded);
    return try getTimestamp(decoded);
}

////

const testing = std.testing;
test "encoding" {
    const key: [brancaKeyLength]u8 = "abcd1234abcd1234abcd1234abcd1234".*;
    const message = "some message";
    const data = try encode(testing.allocator, key, message);
    defer testing.allocator.free(data);

    try testing.expectEqual(brancaHeaderSize + message.len + chacha20poly1305.tag_length, data.len);
    // std.debug.print("{x}\n", .{data});
}

test "encoding decoding" {
    const key: [brancaKeyLength]u8 = "abcd1234abcd1234abcd1234abcd1234".*;
    const message = "some message";
    const data = try encode(testing.allocator, key, message);
    defer testing.allocator.free(data);

    const ret = try decode(testing.allocator, key, data);
    defer testing.allocator.free(ret);

    try testing.expect(std.mem.eql(u8, message, ret));
    // std.debug.print("{s}\n", .{ret});
}

test "encoding string" {
    const key: [brancaKeyLength]u8 = "abcd1234abcd1234abcd1234abcd1234".*;
    const message = "some message";
    const data = try encodeString(testing.allocator, key, message);
    defer testing.allocator.free(data);

    try testing.expectEqual(77, data.len);
    // std.debug.print("{s}\n", .{data});
}
test "encoding string string" {
    const key: [brancaKeyLength]u8 = "abcd1234abcd1234abcd1234abcd1234".*;
    const message = "some message";
    const data = try encodeString(testing.allocator, key, message);
    defer testing.allocator.free(data);

    const ret = try decodeString(testing.allocator, key, data);
    defer testing.allocator.free(ret);

    try testing.expect(std.mem.eql(u8, message, ret));
}

test "decode forign token" {
    const key: [brancaKeyLength]u8 = "abcd1234abcd1234abcd1234abcd1234".*;
    const token = "2XIIv43gjBaf6TLCoKHeA8IQWkb2Lfrl6ob7nRzzmLJC0bsVt5mFw1iYIafDz3U2JmbvPq2NQ2Kzqqm3d1LP";

    const result = "MySuperSecretData";
    const tokenCreated = 1257894000;

    const ret = try decodeString(testing.allocator, key, token);
    defer testing.allocator.free(ret);

    const created = try getTimestampString(testing.allocator, token);

    try testing.expect(std.mem.eql(u8, result, ret));
    try testing.expectEqual(tokenCreated, created);
}

// test "timestamp" {
//     const key: [brancaKeyLength]u8 = "abcdefghabcdefghabcdefghabcdefgh".*;
//     const message = "some message";
//     const data = try Encode(testing.allocator, key, message);
//     defer testing.allocator.free(data);
//     std.debug.print("{d}", .{try GetTimestamp(data)});
// }
// todo more tests
