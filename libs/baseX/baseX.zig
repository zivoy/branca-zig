// based on https://github.com/cryptocoinjs/base-x/blob/master/src/index.js
const std = @import("std");

pub fn base(comptime alphabet: []const u8) type {
    if (alphabet.len > 255) @compileError("alphabet too long");
    const BaseMap = val: {
        var baseMap: [256]u8 = undefined;
        @memset(&baseMap, 255);
        for (alphabet, 0..) |letter, i| {
            if (baseMap[letter] != 255) @compileError([_]u8{letter} ++ " appears more then once");
            baseMap[letter] = i;
        }
        break :val baseMap;
    };
    return struct {
        pub const BASE: u8 = @intCast(alphabet.len);
        const LEADER = alphabet[0];
        const FACTOR = @log(@as(f32, @floatFromInt(BASE))) / @log(@as(f32, 255));
        const iFACTOR = @log(@as(f32, 255)) / @log(@as(f32, @floatFromInt(BASE)));
        const Self = @This();

        allocator: std.mem.Allocator,
        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
            };
        }

        pub fn encode(self: Self, source: []const u8) ![]const u8 {
            if (source.len == 0) return "";

            var zeroes: usize = 0;
            var length: usize = 0;
            var pbegin: usize = 0;
            const pend = source.len;
            while (pbegin != pend and source[pbegin] == 0) {
                pbegin += 1;
                zeroes += 1;
            }
            // Allocate enough space in big-endian base58 representation.
            const size: usize = @intFromFloat(@trunc(@as(f32, @floatFromInt(pend - pbegin)) * iFACTOR + 1));
            var b58 = try self.allocator.alloc(u8, size);
            defer self.allocator.free(b58);
            @memset(b58, 0);

            // Process the bytes.
            for (pbegin..pend) |idx| {
                var carry: usize = @intCast(source[idx]);
                // Apply "b58 = b58 * 256 + ch".
                var i: usize = 0;
                var it1 = size - 1;
                while (carry != 0 or i < length) {
                    carry += 256 * @as(usize, @intCast(b58[it1]));
                    b58[it1] = @intCast(carry % BASE);
                    carry = carry / BASE;
                    i += 1;
                    if (it1 == 0) break;
                    it1 -= 1;
                }
                if (carry != 0) {
                    return error.NonZeroCarry;
                }
                length = i;
            }
            // Skip leading zeroes in base58 result.
            var it2 = size - length;
            while (it2 != size and b58[it2] == 0) {
                it2 += 1;
            }
            // Translate the result into a string.
            var str = std.ArrayList(u8).init(self.allocator);
            try str.appendNTimes(LEADER, zeroes);
            while (it2 < size) : (it2 += 1) {
                try str.append(alphabet[b58[it2]]);
            }
            return try str.toOwnedSlice();
        }

        pub fn decode(self: Self, data: []const u8) ![]const u8 {
            var psz: usize = 0;
            // Skip and count leading '1's.
            var zeroes: usize = 0;
            var length: usize = 0;
            while (data[psz] == LEADER) {
                zeroes += 1;
                psz += 1;
            }
            // Allocate enough space in big-endian base256 representation.
            const size: usize = @intFromFloat(@trunc(@as(f32, @floatFromInt(data.len - psz)) * FACTOR + 1)); // log(58) / log(256), rounded up.
            var b256 = try self.allocator.alloc(u8, size);
            defer self.allocator.free(b256);
            @memset(b256, 0);

            // Process the characters.
            for (psz..data.len) |idx| {
                // Decode character
                var carry: usize = @intCast(BaseMap[data[idx]]);
                // Invalid character
                if (carry == 255) {
                    // @breakpoint();
                    return error.InvalidCharacter;
                }
                var i: usize = 0;
                var it3 = size - 1;
                while ((carry != 0 or i < length) and (it3 != -1)) : (it3 -= 1) {
                    carry += BASE * @as(usize, @intCast(b256[it3]));
                    b256[it3] = @intCast(carry % 256);
                    carry = carry / 256;
                    i += 1;
                }
                if (carry != 0) {
                    return error.NonZeroCarry;
                }
                length = i;
            }
            // Skip leading zeroes in b256.
            var it4 = size - length;
            while (it4 != size and b256[it4] == 0) {
                it4 += 1;
            }
            var vch = try self.allocator.alloc(u8, zeroes + (size - it4));
            var j = zeroes;
            while (it4 != size) {
                vch[j] = b256[it4];
                j += 1;
                it4 += 1;
            }
            return vch;
        }
    };
}

const testing = std.testing;
test "encode base 16" {
    const encoding = base("0123456789abcdef").init(testing.allocator);
    const message = "hello!!";
    const encoded = try encoding.encode(message);
    defer testing.allocator.free(encoded);

    const decoded = try encoding.decode(encoded);
    defer testing.allocator.free(decoded);

    std.debug.print("message {s}\nencoded {s}\ndecoded {s}\n", .{ message, encoded, decoded });
    try testing.expect(std.mem.eql(u8, message, decoded));
}
