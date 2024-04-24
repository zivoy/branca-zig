// based on https://github.com/cryptocoinjs/base-x/blob/master/src/index.js
const std = @import("std");
pub const alphabets = @import("bases.zig");

pub fn base(comptime alphabet: []const u8) type {
    if (alphabet.len > 255) @compileError("alphabet too long");
    const BaseMap = comptime val: {
        var baseMap: [256]u8 = undefined;
        @memset(&baseMap, 255);
        for (alphabet, 0..) |letter, i| {
            if (baseMap[letter] != 255) {
                var buf: [64]u8 = undefined;
                const message = std.fmt.bufPrint(&buf, "'{c}' appears more then once in alphabet at idx {d} and {d}", .{ letter, baseMap[letter], i }) catch @panic("OOM");
                @compileError(message);
            }
            baseMap[letter] = i;
        }
        break :val baseMap;
    };
    return struct {
        pub const BASE: u8 = @intCast(alphabet.len);
        const LEADER = alphabet[0];

        pub const Error = error{
            NonZeroCarry,
            InvalidCharacter,
        };
        const baseTranslationError = Error || std.mem.Allocator.Error;
        const Self = @This();

        allocator: std.mem.Allocator,
        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
            };
        }

        inline fn sizeEncoded(inputLen: usize) usize {
            const factor = comptime @log(@as(f32, 255)) / @log(@as(f32, @floatFromInt(alphabet.len)));
            return @intFromFloat(@as(f32, @floatFromInt(inputLen)) * factor + 1);
        }
        inline fn sizeDecoded(inputLen: usize) usize {
            const factor = comptime @log(@as(f32, @floatFromInt(alphabet.len))) / @log(@as(f32, 255));
            return @intFromFloat(@as(f32, @floatFromInt(inputLen)) * factor + 1);
        }

        pub fn encode(self: Self, source: []const u8) baseTranslationError![]const u8 {
            if (source.len == 0) return "";

            var zeroes: usize = 0;
            var length: usize = 0;
            while (zeroes != source.len and source[zeroes] == 0) {
                zeroes += 1;
            }
            const size: usize = sizeEncoded(source.len - zeroes);
            var bX = try self.allocator.alloc(u8, size);
            defer self.allocator.free(bX);
            @memset(bX, 0);

            // Process the bytes.
            for (source[zeroes..]) |letter| {
                var carry: usize = @intCast(letter);
                // Apply "bX = bX * 256 + ch".
                var i: usize = 0;
                var it1 = size - 1;
                while (carry != 0 or i < length) {
                    carry += 256 * @as(usize, @intCast(bX[it1]));
                    bX[it1] = @intCast(carry % BASE);
                    carry = carry / BASE;
                    i += 1;
                    if (it1 == 0) break;
                    it1 -= 1;
                }
                if (carry != 0) {
                    return Error.NonZeroCarry;
                }
                length = i;
            }
            // Skip leading zeroes in baseX result.
            var it2 = size - length;
            while (it2 != size and bX[it2] == 0) {
                it2 += 1;
            }
            var str = try self.allocator.alloc(u8, zeroes + (size - it2));
            @memset(str[0..zeroes], LEADER);
            for (zeroes..str.len, it2..) |i, j| {
                str[i] = alphabet[bX[j]];
            }
            return str;
        }

        pub fn decode(self: Self, data: []const u8) baseTranslationError![]const u8 {
            // Skip and count leader
            var zeroes: usize = 0;
            var length: usize = 0;
            while (zeroes < data.len and data[zeroes] == LEADER) {
                zeroes += 1;
            }
            // Allocate enough space in big-endian base256 representation.
            const size: usize = sizeDecoded(data.len - zeroes);
            var vch = try self.allocator.alloc(u8, size + zeroes);
            defer self.allocator.free(vch);
            @memset(vch, 0);
            var b256 = vch[zeroes..];

            for (data[zeroes..]) |letter| {
                var carry: usize = @intCast(BaseMap[letter]);
                // Invalid character
                if (carry == 255) {
                    // @breakpoint();
                    return Error.InvalidCharacter;
                }
                var i: usize = 0;
                var it3 = size - 1;
                while (carry != 0 or i < length) {
                    carry += BASE * @as(usize, @intCast(b256[it3]));
                    b256[it3] = @intCast(carry % 256);
                    carry = carry / 256;
                    i += 1;
                    if (it3 == 0) break;
                    it3 -= 1;
                }
                if (carry != 0) {
                    return Error.NonZeroCarry;
                }
                length = i;
            }
            var it4 = size - length;
            while (it4 != size and b256[it4] == 0) {
                it4 += 1;
            }
            var res = try self.allocator.alloc(u8, vch.len - it4);
            @memcpy(res[0..], vch[it4..]); // drop any leading useless chars
            return res;
        }
    };
}

const testing = std.testing;
test "encode base 16" {
    const b16 = base("0123456789abcdef").init(testing.allocator);
    const message = "hello!!";
    const encoded = try b16.encode(message);
    defer testing.allocator.free(encoded);

    const decoded = try b16.decode(encoded);
    defer testing.allocator.free(decoded);

    // std.debug.print("message {s}\nencoded {s}\ndecoded {s}\n", .{ message, encoded, decoded });
    try testing.expectEqualStrings(message, decoded);
}

test "base62" {
    const target = "2nUwTMpGcx8BkP17EP";
    const source = "hello there!!";
    const b62 = base(alphabets.base62).init(testing.allocator);
    const encoded = try b62.encode(source);
    defer testing.allocator.free(encoded);

    try testing.expectEqualStrings(target, encoded);

    const decoded = try b62.decode(encoded);
    defer testing.allocator.free(decoded);

    try testing.expectEqualStrings(source, decoded);
}

test "base58" {
    const target = "9hLF3DC578cdUPkTJg";
    const source = "hello there!!";
    const b58 = base(alphabets.base58).init(testing.allocator);

    const encoded = try b58.encode(source);
    defer testing.allocator.free(encoded);

    try testing.expectEqualStrings(target, encoded);

    const decoded = try b58.decode(encoded);
    defer testing.allocator.free(decoded);

    try testing.expectEqualStrings(source, decoded);
}

test "base 10 leading char" {
    const source: []const u8 = &[_]u8{ 0, 0, 0, 1, 4, 2, 5, 2, 3 } ++ "with extra";
    const target = "0001350038144802235762089578086238810721";
    const b10 = base("0123456789").init(testing.allocator);

    const encoded = try b10.encode(source);
    defer testing.allocator.free(encoded);

    try testing.expectEqualStrings(target, encoded);

    const decoded = try b10.decode(encoded);
    defer testing.allocator.free(decoded);

    try testing.expectEqualStrings(source, decoded);
}
test "base 16 all 0" {
    const source: []const u8 = &[_]u8{ 0, 0, 0, 0, 0 };
    const target = "00000";
    const b16 = base(alphabets.base16).init(testing.allocator);

    const encoded = try b16.encode(source);
    defer testing.allocator.free(encoded);

    try testing.expectEqualStrings(target, encoded);

    const decoded = try b16.decode(encoded);
    defer testing.allocator.free(decoded);

    try testing.expectEqualStrings(source, decoded);
}

test "base64 no padding" {
    const source = "some data";
    const target = "c29tZSBkYXRh";
    const b64 = base(alphabets.base64).init(testing.allocator);

    const encoded = try b64.encode(source);
    defer testing.allocator.free(encoded);

    try testing.expectEqualStrings(target, encoded);

    const decoded = try b64.decode(encoded);
    defer testing.allocator.free(decoded);

    try testing.expectEqualStrings(source, decoded);
}
