const std = @import("std");

pub const Value = union(enum) {
    nil,
    boolean: bool,
    integer: i64,
    float: f64,
    string: []const u8,

    /// Lua 진리값: nil과 false만 falsy, 나머지 모두 truthy (0, ""도 truthy)
    pub fn isTruthy(self: Value) bool {
        return switch (self) {
            .nil => false,
            .boolean => |b| b,
            else => true,
        };
    }

    /// 값 동등 비교
    pub fn eql(self: Value, other: Value) bool {
        const self_tag = std.meta.activeTag(self);
        const other_tag = std.meta.activeTag(other);
        if (self_tag != other_tag) return false;

        return switch (self) {
            .nil => true,
            .boolean => |b| b == other.boolean,
            .integer => |i| i == other.integer,
            .float => |f| f == other.float,
            .string => |s| std.mem.eql(u8, s, other.string),
        };
    }

    /// 디버그/출력용 포매팅
    pub fn format(self: Value, writer: anytype) !void {
        switch (self) {
            .nil => try writer.writeAll("nil"),
            .boolean => |b| try writer.print("{}", .{b}),
            .integer => |i| try writer.print("{}", .{i}),
            .float => |f| {
                // Lua 스타일: 정수 값이면 .0 추가하지 않음
                if (f == @floor(f) and !std.math.isInf(f) and !std.math.isNan(f)) {
                    // 정수처럼 보이는 float도 소수점 포함
                    try writer.print("{d}", .{f});
                } else {
                    try writer.print("{d}", .{f});
                }
            },
            .string => |s| try writer.writeAll(s),
        }
    }
};

// =============================================================================
// Tests
// =============================================================================

test "T4-1: Value 생성 — 각 타입별 초기화" {
    const nil_val = Value.nil;
    const bool_val = Value{ .boolean = true };
    const int_val = Value{ .integer = 42 };
    const float_val = Value{ .float = 3.14 };
    const str_val = Value{ .string = "hello" };

    try std.testing.expectEqual(Value.nil, nil_val);
    try std.testing.expectEqual(true, bool_val.boolean);
    try std.testing.expectEqual(42, int_val.integer);
    try std.testing.expectEqual(3.14, float_val.float);
    try std.testing.expectEqualStrings("hello", str_val.string);
}

test "T4-2: isTruthy — nil과 false만 falsy" {
    const nil_v: Value = .nil;
    try std.testing.expectEqual(false, nil_v.isTruthy());
    try std.testing.expectEqual(false, (Value{ .boolean = false }).isTruthy());
    try std.testing.expectEqual(true, (Value{ .boolean = true }).isTruthy());
    // Lua에서 0과 빈 문자열은 truthy
    try std.testing.expectEqual(true, (Value{ .integer = 0 }).isTruthy());
    try std.testing.expectEqual(true, (Value{ .string = "" }).isTruthy());
    try std.testing.expectEqual(true, (Value{ .float = 0.0 }).isTruthy());
}

test "T4-3: eql — 동일 타입/값 비교" {
    const nil_v: Value = .nil;
    try std.testing.expect(nil_v.eql(.nil));
    try std.testing.expect((Value{ .boolean = true }).eql(.{ .boolean = true }));
    try std.testing.expect((Value{ .integer = 42 }).eql(.{ .integer = 42 }));
    try std.testing.expect((Value{ .float = 3.14 }).eql(.{ .float = 3.14 }));
    try std.testing.expect((Value{ .string = "hello" }).eql(.{ .string = "hello" }));

    // 다른 타입은 항상 false
    try std.testing.expect(!nil_v.eql(.{ .boolean = false }));
    try std.testing.expect(!(Value{ .integer = 0 }).eql(.{ .float = 0.0 }));
}
