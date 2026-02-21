const std = @import("std");
const OpCode = @import("opcode.zig").OpCode;
const Chunk = @import("opcode.zig").Chunk;

/// 바이트코드 디스어셈블리 — 사람이 읽을 수 있는 형태로 변환
pub fn disassemble(chunk: *const Chunk, allocator: std.mem.Allocator) ![]u8 {
    var out = std.ArrayListUnmanaged(u8).empty;
    defer out.deinit(allocator);
    const writer = out.writer(allocator);

    var offset: usize = 0;
    while (offset < chunk.code.items.len) {
        const instr = chunk.code.items[offset];
        const op: OpCode = @enumFromInt(instr);

        try writer.print("{d:0>4} ", .{offset});

        switch (op) {
            .op_push_constant, .op_get_global, .op_set_global => {
                const idx = readU16(chunk, offset + 1);
                try writer.print("{s} {d}", .{ @tagName(op), idx });
                if (op == .op_push_constant and idx < chunk.constants.items.len) {
                    try writer.print(" (", .{});
                    try chunk.constants.items[idx].format(writer);
                    try writer.print(")", .{});
                }
                offset += 3;
            },
            .op_get_local, .op_set_local, .op_call, .op_print => {
                const arg = chunk.code.items[offset + 1];
                try writer.print("{s} {d}", .{ @tagName(op), arg });
                offset += 2;
            },
            .op_jump, .op_jump_if_false, .op_jump_if_true, .op_loop => {
                const jump_offset = readU16(chunk, offset + 1);
                try writer.print("{s} {d}", .{ @tagName(op), jump_offset });
                offset += 3;
            },
            else => {
                try writer.print("{s}", .{@tagName(op)});
                offset += 1;
            },
        }
        try writer.print("\n", .{});
    }

    return try out.toOwnedSlice(allocator);
}

fn readU16(chunk: *const Chunk, offset: usize) u16 {
    const hi: u16 = chunk.code.items[offset];
    const lo: u16 = chunk.code.items[offset + 1];
    return (hi << 8) | lo;
}

// =============================================================================
// Tests
// =============================================================================

test "T6-13: 디스어셈블 출력" {
    const allocator = std.testing.allocator;
    var chunk = Chunk.init(allocator);
    defer chunk.deinit();

    _ = try chunk.addConstant(.{ .integer = 42 });
    try chunk.write(@intFromEnum(OpCode.op_push_constant), 1);
    try chunk.write(0, 1); // high byte
    try chunk.write(0, 1); // low byte
    try chunk.write(@intFromEnum(OpCode.op_return), 1);

    const output = try disassemble(&chunk, allocator);
    defer allocator.free(output);

    try std.testing.expect(std.mem.indexOf(u8, output, "op_push_constant") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "42") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "op_return") != null);
}
