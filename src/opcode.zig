const std = @import("std");
const Value = @import("value.zig").Value;

pub const OpCode = enum(u8) {
    // --- 스택 조작 ---
    op_push_nil,
    op_push_true,
    op_push_false,
    op_push_constant, // operand: constant_index (u16)
    op_pop,

    // --- 산술 연산 ---
    op_add,
    op_sub,
    op_mul,
    op_div, // / (항상 float)
    op_idiv, // // (정수 나눗셈)
    op_mod, // %
    op_pow, // ^ (항상 float)
    op_negate, // 단항 -

    // --- 비트 연산 ---
    op_band,
    op_bor,
    op_bxor,
    op_bnot,
    op_shl,
    op_shr,

    // --- 관계 연산 ---
    op_eq,
    op_ne,
    op_lt,
    op_le,
    op_gt,
    op_ge,

    // --- 논리 연산 ---
    op_not,

    // --- 문자열 ---
    op_concat,
    op_len,

    // --- 변수 ---
    op_get_local, // operand: stack_slot (u8)
    op_set_local, // operand: stack_slot (u8)
    op_get_global, // operand: name_index (u16)
    op_set_global, // operand: name_index (u16)

    // --- 제어 흐름 ---
    op_jump, // operand: offset (u16)
    op_jump_if_false, // operand: offset (u16)
    op_jump_if_true, // operand: offset (u16)
    op_loop, // operand: offset (u16) — 역방향 점프

    // --- 함수 ---
    op_call, // operand: arg_count (u8)
    op_return,

    // --- 특수 ---
    op_print, // operand: arg_count (u8)
};

/// 컴파일 결과물: 바이트코드 + 상수 풀 + 디버깅 정보
pub const Chunk = struct {
    code: std.ArrayListUnmanaged(u8),
    constants: std.ArrayListUnmanaged(Value),
    lines: std.ArrayListUnmanaged(u32),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Chunk {
        return .{
            .code = .empty,
            .constants = .empty,
            .lines = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Chunk) void {
        self.code.deinit(self.allocator);
        self.constants.deinit(self.allocator);
        self.lines.deinit(self.allocator);
    }

    /// 바이트를 코드에 추가
    pub fn write(self: *Chunk, byte: u8, line: u32) !void {
        try self.code.append(self.allocator, byte);
        try self.lines.append(self.allocator, line);
    }

    /// 상수를 상수 풀에 추가하고 인덱스를 반환
    pub fn addConstant(self: *Chunk, value: Value) !u16 {
        const index = self.constants.items.len;
        try self.constants.append(self.allocator, value);
        return @intCast(index);
    }

    /// 현재 코드 크기 (다음 바이트의 오프셋)
    pub fn currentOffset(self: *const Chunk) usize {
        return self.code.items.len;
    }
};

// =============================================================================
// Tests
// =============================================================================

test "T6-1: Chunk 초기화/해제" {
    var chunk = Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    try chunk.write(@intFromEnum(OpCode.op_push_nil), 1);
    try chunk.write(@intFromEnum(OpCode.op_return), 1);
    try std.testing.expectEqual(2, chunk.code.items.len);
}

test "T6-2: 상수 풀 — addConstant" {
    var chunk = Chunk.init(std.testing.allocator);
    defer chunk.deinit();
    const idx = try chunk.addConstant(.{ .integer = 42 });
    try std.testing.expectEqual(0, idx);
    try std.testing.expectEqual(42, chunk.constants.items[0].integer);
    const idx2 = try chunk.addConstant(.{ .float = 3.14 });
    try std.testing.expectEqual(1, idx2);
}
