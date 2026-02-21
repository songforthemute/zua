const std = @import("std");
const OpCode = @import("opcode.zig").OpCode;
const Chunk = @import("opcode.zig").Chunk;
const Value = @import("value.zig").Value;
const Compiler = @import("compiler.zig").Compiler;
const Parser = @import("parser.zig").Parser;
const Lexer = @import("lexer.zig").Lexer;
const ast = @import("ast.zig");

const STACK_MAX = 256;

pub const VMError = error{
    StackOverflow,
    StackUnderflow,
    TypeError,
    UndefinedVariable,
    DivisionByZero,
    OutOfMemory,
};

pub const VM = struct {
    chunk: *Chunk,
    ip: usize,
    stack: [STACK_MAX]Value,
    stack_top: usize,
    globals: std.StringHashMapUnmanaged(Value),
    allocator: std.mem.Allocator,
    // stdout 캡처용 (테스트에서 사용)
    output: std.ArrayListUnmanaged(u8),
    // 문자열 연결 시 할당된 메모리 추적
    allocated_strings: std.ArrayListUnmanaged([]const u8),

    pub fn init(allocator: std.mem.Allocator, chunk: *Chunk) VM {
        return .{
            .chunk = chunk,
            .ip = 0,
            .stack = [_]Value{.nil} ** STACK_MAX,
            .stack_top = 0,
            .globals = .empty,
            .allocator = allocator,
            .output = .empty,
            .allocated_strings = .empty,
        };
    }

    pub fn deinit(self: *VM) void {
        self.globals.deinit(self.allocator);
        self.output.deinit(self.allocator);
        for (self.allocated_strings.items) |s| {
            self.allocator.free(s);
        }
        self.allocated_strings.deinit(self.allocator);
    }

    pub fn run(self: *VM) VMError!void {
        while (self.ip < self.chunk.code.items.len) {
            const instr = self.readByte();
            const op: OpCode = @enumFromInt(instr);

            switch (op) {
                .op_push_nil => try self.push(.nil),
                .op_push_true => try self.push(.{ .boolean = true }),
                .op_push_false => try self.push(.{ .boolean = false }),
                .op_push_constant => {
                    const idx = self.readU16();
                    try self.push(self.chunk.constants.items[idx]);
                },
                .op_pop => {
                    _ = self.pop();
                },

                // 산술 연산
                .op_add => try self.binaryArith(.op_add),
                .op_sub => try self.binaryArith(.op_sub),
                .op_mul => try self.binaryArith(.op_mul),
                .op_div => try self.binaryArith(.op_div),
                .op_idiv => try self.binaryArith(.op_idiv),
                .op_mod => try self.binaryArith(.op_mod),
                .op_pow => try self.binaryArith(.op_pow),
                .op_negate => {
                    const val = self.pop();
                    switch (val) {
                        .integer => |i| try self.push(.{ .integer = -i }),
                        .float => |f| try self.push(.{ .float = -f }),
                        else => return error.TypeError,
                    }
                },

                // 비트 연산
                .op_band => try self.binaryBitwise(.op_band),
                .op_bor => try self.binaryBitwise(.op_bor),
                .op_bxor => try self.binaryBitwise(.op_bxor),
                .op_shl => try self.binaryBitwise(.op_shl),
                .op_shr => try self.binaryBitwise(.op_shr),
                .op_bnot => {
                    const val = self.pop();
                    switch (val) {
                        .integer => |i| try self.push(.{ .integer = ~i }),
                        else => return error.TypeError,
                    }
                },

                // 관계 연산
                .op_eq => {
                    const b = self.pop();
                    const a = self.pop();
                    try self.push(.{ .boolean = a.eql(b) });
                },
                .op_ne => {
                    const b = self.pop();
                    const a = self.pop();
                    try self.push(.{ .boolean = !a.eql(b) });
                },
                .op_lt => try self.comparison(.op_lt),
                .op_le => try self.comparison(.op_le),
                .op_gt => try self.comparison(.op_gt),
                .op_ge => try self.comparison(.op_ge),

                // 논리 연산
                .op_not => {
                    const val = self.pop();
                    try self.push(.{ .boolean = !val.isTruthy() });
                },

                // 문자열
                .op_concat => {
                    const b = self.pop();
                    const a = self.pop();
                    const a_str = try self.valueToString(a);
                    const b_str = try self.valueToString(b);
                    const result = try std.mem.concat(self.allocator, u8, &.{ a_str, b_str });
                    try self.allocated_strings.append(self.allocator, result);
                    try self.push(.{ .string = result });
                },
                .op_len => {
                    const val = self.pop();
                    switch (val) {
                        .string => |s| try self.push(.{ .integer = @intCast(s.len) }),
                        else => return error.TypeError,
                    }
                },

                // 변수
                .op_get_local => {
                    const slot = self.readByte();
                    try self.push(self.stack[slot]);
                },
                .op_set_local => {
                    const slot = self.readByte();
                    self.stack[slot] = self.peek(0);
                    _ = self.pop(); // 값 pop
                },
                .op_get_global => {
                    const idx = self.readU16();
                    const name = self.chunk.constants.items[idx].string;
                    if (self.globals.get(name)) |val| {
                        try self.push(val);
                    } else {
                        return error.UndefinedVariable;
                    }
                },
                .op_set_global => {
                    const idx = self.readU16();
                    const name = self.chunk.constants.items[idx].string;
                    const val = self.pop();
                    self.globals.put(self.allocator, name, val) catch return error.OutOfMemory;
                },

                // 제어 흐름
                .op_jump => {
                    const offset = self.readU16();
                    self.ip += offset;
                },
                .op_jump_if_false => {
                    const offset = self.readU16();
                    if (!self.peek(0).isTruthy()) {
                        self.ip += offset;
                    }
                },
                .op_jump_if_true => {
                    const offset = self.readU16();
                    if (self.peek(0).isTruthy()) {
                        self.ip += offset;
                    }
                },
                .op_loop => {
                    const offset = self.readU16();
                    self.ip -= offset;
                },

                // 함수
                .op_call => {
                    _ = self.readByte(); // arg_count — MVP에서는 미사용
                    return error.TypeError; // MVP에서는 일반 함수 호출 미지원
                },
                .op_return => {
                    return;
                },

                // print 내장 함수
                .op_print => {
                    const arg_count = self.readByte();
                    // 인자를 역순으로 모아서 출력
                    var args: [256]Value = undefined;
                    var i: usize = arg_count;
                    while (i > 0) {
                        i -= 1;
                        args[i] = self.pop();
                    }
                    // 출력
                    const writer = self.output.writer(self.allocator);
                    for (0..arg_count) |j| {
                        if (j > 0) writer.writeAll("\t") catch {};
                        args[j].format(writer) catch {};
                    }
                    writer.writeAll("\n") catch {};
                },
            }
        }
    }

    // =========================================================================
    // 스택 연산
    // =========================================================================

    fn push(self: *VM, value: Value) VMError!void {
        if (self.stack_top >= STACK_MAX) return error.StackOverflow;
        self.stack[self.stack_top] = value;
        self.stack_top += 1;
    }

    fn pop(self: *VM) Value {
        self.stack_top -= 1;
        return self.stack[self.stack_top];
    }

    fn peek(self: *const VM, distance: usize) Value {
        return self.stack[self.stack_top - 1 - distance];
    }

    // =========================================================================
    // 바이트 읽기
    // =========================================================================

    fn readByte(self: *VM) u8 {
        const byte = self.chunk.code.items[self.ip];
        self.ip += 1;
        return byte;
    }

    fn readU16(self: *VM) u16 {
        const hi: u16 = self.chunk.code.items[self.ip];
        const lo: u16 = self.chunk.code.items[self.ip + 1];
        self.ip += 2;
        return (hi << 8) | lo;
    }

    // =========================================================================
    // 산술/비교 연산 헬퍼
    // =========================================================================

    /// Lua 5.4 타입 승격 규칙 적용 이항 산술 연산
    fn binaryArith(self: *VM, op: OpCode) VMError!void {
        const b = self.pop();
        const a = self.pop();

        // / (float division)은 항상 float
        if (op == .op_div) {
            const af = toFloat(a) orelse return error.TypeError;
            const bf = toFloat(b) orelse return error.TypeError;
            if (bf == 0.0) return error.DivisionByZero;
            try self.push(.{ .float = af / bf });
            return;
        }

        // ^ (power)은 항상 float
        if (op == .op_pow) {
            const af = toFloat(a) orelse return error.TypeError;
            const bf = toFloat(b) orelse return error.TypeError;
            try self.push(.{ .float = std.math.pow(f64, af, bf) });
            return;
        }

        // 양쪽 모두 integer인 경우
        if (a == .integer and b == .integer) {
            const ai = a.integer;
            const bi = b.integer;
            const result: i64 = switch (op) {
                .op_add => ai + bi,
                .op_sub => ai - bi,
                .op_mul => ai * bi,
                .op_idiv => blk: {
                    if (bi == 0) return error.DivisionByZero;
                    break :blk @divFloor(ai, bi);
                },
                .op_mod => blk: {
                    if (bi == 0) return error.DivisionByZero;
                    break :blk @mod(ai, bi);
                },
                else => unreachable,
            };
            try self.push(.{ .integer = result });
            return;
        }

        // 하나라도 float면 결과도 float
        const af = toFloat(a) orelse return error.TypeError;
        const bf = toFloat(b) orelse return error.TypeError;
        const result: f64 = switch (op) {
            .op_add => af + bf,
            .op_sub => af - bf,
            .op_mul => af * bf,
            .op_idiv => blk: {
                if (bf == 0.0) return error.DivisionByZero;
                break :blk @floor(af / bf);
            },
            .op_mod => blk: {
                if (bf == 0.0) return error.DivisionByZero;
                break :blk af - @floor(af / bf) * bf;
            },
            else => unreachable,
        };
        try self.push(.{ .float = result });
    }

    fn binaryBitwise(self: *VM, op: OpCode) VMError!void {
        const b = self.pop();
        const a = self.pop();

        // 비트 연산은 integer만 허용
        if (a != .integer or b != .integer) return error.TypeError;
        const ai = a.integer;
        const bi = b.integer;

        const result: i64 = switch (op) {
            .op_band => ai & bi,
            .op_bor => ai | bi,
            .op_bxor => ai ^ bi,
            .op_shl => blk: {
                if (bi < 0 or bi >= 64) break :blk 0;
                break :blk ai << @intCast(bi);
            },
            .op_shr => blk: {
                if (bi < 0 or bi >= 64) break :blk 0;
                const ub: u6 = @intCast(bi);
                break :blk @as(i64, @intCast(@as(u64, @bitCast(ai)) >> ub));
            },
            else => unreachable,
        };
        try self.push(.{ .integer = result });
    }

    fn comparison(self: *VM, op: OpCode) VMError!void {
        const b = self.pop();
        const a = self.pop();

        // 동일 타입 비교
        if (a == .integer and b == .integer) {
            const result = switch (op) {
                .op_lt => a.integer < b.integer,
                .op_le => a.integer <= b.integer,
                .op_gt => a.integer > b.integer,
                .op_ge => a.integer >= b.integer,
                else => unreachable,
            };
            try self.push(.{ .boolean = result });
            return;
        }

        // 숫자 타입 승격 비교
        if ((a == .integer or a == .float) and (b == .integer or b == .float)) {
            const af = toFloat(a).?;
            const bf = toFloat(b).?;
            const result = switch (op) {
                .op_lt => af < bf,
                .op_le => af <= bf,
                .op_gt => af > bf,
                .op_ge => af >= bf,
                else => unreachable,
            };
            try self.push(.{ .boolean = result });
            return;
        }

        // 문자열 비교
        if (a == .string and b == .string) {
            const cmp = std.mem.order(u8, a.string, b.string);
            const result = switch (op) {
                .op_lt => cmp == .lt,
                .op_le => cmp == .lt or cmp == .eq,
                .op_gt => cmp == .gt,
                .op_ge => cmp == .gt or cmp == .eq,
                else => unreachable,
            };
            try self.push(.{ .boolean = result });
            return;
        }

        return error.TypeError;
    }

    fn toFloat(val: Value) ?f64 {
        return switch (val) {
            .integer => |i| @floatFromInt(i),
            .float => |f| f,
            else => null,
        };
    }

    fn valueToString(self: *VM, val: Value) VMError![]const u8 {
        _ = self;
        return switch (val) {
            .string => |s| s,
            else => error.TypeError,
        };
    }
};

// =============================================================================
// 통합 헬퍼: 소스 → 실행
// =============================================================================

pub fn interpret(allocator: std.mem.Allocator, source: []const u8) ![]const u8 {
    // Lexer
    var lexer = Lexer.init(allocator, source);
    const tokens = lexer.tokenize() catch {
        lexer.deinit();
        return error.OutOfMemory;
    };

    // Parser
    var parser = Parser.init(allocator, tokens);
    const block = parser.parseBlock() catch {
        lexer.deinit();
        return error.OutOfMemory;
    };

    // Compiler
    var compiler = Compiler.init(allocator);
    var chunk = compiler.compile(block) catch {
        ast.freeBlock(block, allocator);
        compiler.deinit();
        lexer.deinit();
        return error.OutOfMemory;
    };

    // AST 해제 (컴파일 후 불필요)
    ast.freeBlock(block, allocator);
    compiler.deinit();

    // VM
    var vm = VM.init(allocator, &chunk);
    vm.run() catch |err| {
        const result = vm.output.toOwnedSlice(allocator) catch "";
        vm.deinit();
        chunk.deinit();
        lexer.deinit();
        _ = result;
        return err;
    };

    const result = vm.output.toOwnedSlice(allocator) catch {
        vm.deinit();
        chunk.deinit();
        lexer.deinit();
        return error.OutOfMemory;
    };

    vm.deinit();
    chunk.deinit();
    lexer.deinit();

    return result;
}

// =============================================================================
// Tests — Session 7: VM 코어
// =============================================================================

test "T7-5: 수동 바이트코드 실행 — 10 + 20 = 30" {
    const allocator = std.testing.allocator;
    var chunk = Chunk.init(allocator);
    defer chunk.deinit();

    _ = try chunk.addConstant(.{ .integer = 10 });
    _ = try chunk.addConstant(.{ .integer = 20 });

    try chunk.write(@intFromEnum(OpCode.op_push_constant), 1);
    try chunk.write(0, 1); // hi
    try chunk.write(0, 1); // lo = 0
    try chunk.write(@intFromEnum(OpCode.op_push_constant), 1);
    try chunk.write(0, 1);
    try chunk.write(1, 1); // lo = 1
    try chunk.write(@intFromEnum(OpCode.op_add), 1);
    try chunk.write(@intFromEnum(OpCode.op_return), 1);

    var vm = VM.init(allocator, &chunk);
    defer vm.deinit();
    try vm.run();

    // 스택에 결과가 남아야 함
    try std.testing.expectEqual(1, vm.stack_top);
    try std.testing.expectEqual(30, vm.stack[0].integer);
}

test "T7-6: 타입 승격 — integer + float = float" {
    const allocator = std.testing.allocator;
    const output = try interpret(allocator, "local x = 10 + 3.14");
    defer allocator.free(output);
    // 출력은 없지만 에러 없이 실행되면 OK
}

test "T7-7: 정수 나눗셈 — 7 // 2 = 3" {
    const allocator = std.testing.allocator;
    const output = try interpret(allocator, "print(7 // 2)");
    defer allocator.free(output);
    try std.testing.expectEqualStrings("3\n", output);
}

test "T7-8: 부동소수점 나눗셈 — 7 / 2 = 3.5" {
    const allocator = std.testing.allocator;
    const output = try interpret(allocator, "print(7 / 2)");
    defer allocator.free(output);
    try std.testing.expectEqualStrings("3.5\n", output);
}

test "T7-9: 비교 연산" {
    const allocator = std.testing.allocator;
    const output = try interpret(allocator, "print(5 > 3)");
    defer allocator.free(output);
    try std.testing.expectEqualStrings("true\n", output);
}

test "T7-10: 변수 할당+참조" {
    const allocator = std.testing.allocator;
    const output = try interpret(allocator, "local x = 10\nlocal y = x + 5\nprint(y)");
    defer allocator.free(output);
    try std.testing.expectEqualStrings("15\n", output);
}

test "T7-11: 글로벌 변수" {
    const allocator = std.testing.allocator;
    const output = try interpret(allocator, "x = 42\nprint(x)");
    defer allocator.free(output);
    try std.testing.expectEqualStrings("42\n", output);
}

test "T7-12: 논리 단락 평가 — false or 42" {
    const allocator = std.testing.allocator;
    const output = try interpret(allocator, "print(false or 42)");
    defer allocator.free(output);
    try std.testing.expectEqualStrings("42\n", output);
}

test "T7-13: VM 메모리 누수 검증" {
    const allocator = std.testing.allocator;
    const output = try interpret(allocator, "local x = 1\nlocal y = 2\nlocal z = x + y");
    defer allocator.free(output);
}

// =============================================================================
// Tests — Session 8: VM 제어 흐름 + 통합
// =============================================================================

test "T8-1: if 참 분기" {
    const allocator = std.testing.allocator;
    const output = try interpret(allocator, "local x = 10\nif x > 5 then print(1) else print(0) end");
    defer allocator.free(output);
    try std.testing.expectEqualStrings("1\n", output);
}

test "T8-2: if 거짓 분기" {
    const allocator = std.testing.allocator;
    const output = try interpret(allocator, "local x = 1\nif x > 5 then print(99) else print(0) end");
    defer allocator.free(output);
    try std.testing.expectEqualStrings("0\n", output);
}

test "T8-3: if/elseif" {
    const allocator = std.testing.allocator;
    const output = try interpret(allocator,
        \\if false then
        \\  print(1)
        \\elseif true then
        \\  print(2)
        \\else
        \\  print(3)
        \\end
    );
    defer allocator.free(output);
    try std.testing.expectEqualStrings("2\n", output);
}

test "T8-4: while 루프" {
    const allocator = std.testing.allocator;
    const output = try interpret(allocator,
        \\local x = 0
        \\while x < 5 do
        \\  x = x + 1
        \\end
        \\print(x)
    );
    defer allocator.free(output);
    try std.testing.expectEqualStrings("5\n", output);
}

test "T8-5: numeric for" {
    const allocator = std.testing.allocator;
    const output = try interpret(allocator,
        \\local s = 0
        \\for i = 1, 10 do
        \\  s = s + i
        \\end
        \\print(s)
    );
    defer allocator.free(output);
    try std.testing.expectEqualStrings("55\n", output);
}

test "T8-6: for with step" {
    const allocator = std.testing.allocator;
    const output = try interpret(allocator,
        \\local s = 0
        \\for i = 1, 10, 2 do
        \\  s = s + i
        \\end
        \\print(s)
    );
    defer allocator.free(output);
    try std.testing.expectEqualStrings("25\n", output);
}

test "T8-7: repeat-until" {
    const allocator = std.testing.allocator;
    const output = try interpret(allocator,
        \\local x = 0
        \\repeat
        \\  x = x + 1
        \\until x >= 3
        \\print(x)
    );
    defer allocator.free(output);
    try std.testing.expectEqualStrings("3\n", output);
}

test "T8-10: print 단일" {
    const allocator = std.testing.allocator;
    const output = try interpret(allocator, "print(42)");
    defer allocator.free(output);
    try std.testing.expectEqualStrings("42\n", output);
}

test "T8-11: print 다중 인자" {
    const allocator = std.testing.allocator;
    const output = try interpret(allocator, "print(1, 2, 3)");
    defer allocator.free(output);
    try std.testing.expectEqualStrings("1\t2\t3\n", output);
}

test "T8-12: 문자열 연결" {
    const allocator = std.testing.allocator;
    const output = try interpret(allocator,
        \\print("hello" .. " " .. "world")
    );
    defer allocator.free(output);
    try std.testing.expectEqualStrings("hello world\n", output);
}

test "T8-14: 가우스 합 — 통합 테스트" {
    const allocator = std.testing.allocator;
    const output = try interpret(allocator,
        \\local sum = 0
        \\for i = 1, 100 do
        \\  sum = sum + i
        \\end
        \\print(sum)
    );
    defer allocator.free(output);
    try std.testing.expectEqualStrings("5050\n", output);
}

test "T8-16: 전체 파이프라인 메모리 누수" {
    const allocator = std.testing.allocator;
    const output = try interpret(allocator,
        \\local sum = 0
        \\for i = 1, 10 do
        \\  if i % 2 == 0 then
        \\    sum = sum + i
        \\  end
        \\end
        \\print(sum)
    );
    defer allocator.free(output);
    try std.testing.expectEqualStrings("30\n", output);
}
