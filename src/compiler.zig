const std = @import("std");
const ast = @import("ast.zig");
const Expr = ast.Expr;
const Stmt = ast.Stmt;
const Block = ast.Block;
const TokenType = @import("token.zig").TokenType;
const OpCode = @import("opcode.zig").OpCode;
const Chunk = @import("opcode.zig").Chunk;
const Value = @import("value.zig").Value;
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;

pub const CompilerError = error{
    OutOfMemory,
    TooManyConstants,
    TooManyLocals,
    UndefinedVariable,
    InvalidJumpOffset,
};

pub const CompileError = CompilerError;

const Local = struct {
    name: []const u8,
    depth: u32,
};

pub const Compiler = struct {
    chunk: Chunk,
    allocator: std.mem.Allocator,
    locals: std.ArrayListUnmanaged(Local),
    scope_depth: u32,
    // break 점프 패치용 스택
    break_jumps: std.ArrayListUnmanaged(usize),
    loop_depth: u32,

    pub fn init(allocator: std.mem.Allocator) Compiler {
        return .{
            .chunk = Chunk.init(allocator),
            .allocator = allocator,
            .locals = .empty,
            .scope_depth = 0,
            .break_jumps = .empty,
            .loop_depth = 0,
        };
    }

    pub fn deinit(self: *Compiler) void {
        self.chunk.deinit();
        self.locals.deinit(self.allocator);
        self.break_jumps.deinit(self.allocator);
    }

    /// Block을 컴파일하고 Chunk를 반환
    pub fn compile(self: *Compiler, block: Block) !Chunk {
        for (block) |stmt| {
            try self.compileStmt(stmt.*);
        }
        try self.emitOp(.op_return, 0);

        // Chunk 소유권을 호출자에게 이전
        const result = self.chunk;
        self.chunk = Chunk.init(self.allocator);
        return result;
    }

    // =========================================================================
    // 표현식 컴파일
    // =========================================================================

    pub fn compileExpr(self: *Compiler, expr: Expr) !void {
        switch (expr) {
            .nil_literal => try self.emitOp(.op_push_nil, 0),
            .boolean_literal => |b| {
                if (b) {
                    try self.emitOp(.op_push_true, 0);
                } else {
                    try self.emitOp(.op_push_false, 0);
                }
            },
            .integer_literal => |i| {
                try self.emitConstant(.{ .integer = i });
            },
            .float_literal => |f| {
                try self.emitConstant(.{ .float = f });
            },
            .string_literal => |s| {
                try self.emitConstant(.{ .string = s });
            },
            .identifier => |name| {
                // 로컬 변수 검색
                if (self.resolveLocal(name)) |slot| {
                    try self.emitOp(.op_get_local, 0);
                    try self.emitByte(slot, 0);
                } else {
                    // 글로벌 변수
                    const idx = try self.chunk.addConstant(.{ .string = name });
                    try self.emitOp(.op_get_global, 0);
                    try self.emitU16(idx, 0);
                }
            },
            .unary_op => |u| {
                try self.compileExpr(u.operand.*);
                const op: OpCode = switch (u.op) {
                    .minus => .op_negate,
                    .kw_not => .op_not,
                    .tilde => .op_bnot,
                    .hash => .op_len,
                    else => unreachable,
                };
                try self.emitOp(op, 0);
            },
            .binary_op => |b| {
                // 논리 연산자: 단락 평가 필요
                if (b.op == .kw_and) {
                    try self.compileExpr(b.left.*);
                    const jump = try self.emitJump(.op_jump_if_false);
                    try self.emitOp(.op_pop, 0);
                    try self.compileExpr(b.right.*);
                    try self.patchJump(jump);
                    return;
                }
                if (b.op == .kw_or) {
                    try self.compileExpr(b.left.*);
                    const jump = try self.emitJump(.op_jump_if_true);
                    try self.emitOp(.op_pop, 0);
                    try self.compileExpr(b.right.*);
                    try self.patchJump(jump);
                    return;
                }

                try self.compileExpr(b.left.*);
                try self.compileExpr(b.right.*);
                const op: OpCode = switch (b.op) {
                    .plus => .op_add,
                    .minus => .op_sub,
                    .star => .op_mul,
                    .slash => .op_div,
                    .slash_slash => .op_idiv,
                    .percent => .op_mod,
                    .caret => .op_pow,
                    .ampersand => .op_band,
                    .pipe => .op_bor,
                    .tilde => .op_bxor,
                    .less_less => .op_shl,
                    .greater_greater => .op_shr,
                    .equal_equal => .op_eq,
                    .tilde_equal => .op_ne,
                    .less => .op_lt,
                    .less_equal => .op_le,
                    .greater => .op_gt,
                    .greater_equal => .op_ge,
                    .dot_dot => .op_concat,
                    else => unreachable,
                };
                try self.emitOp(op, 0);
            },
            .call => |c| {
                // 특별 처리: print 내장 함수
                if (c.callee.* == .identifier) {
                    if (std.mem.eql(u8, c.callee.identifier, "print")) {
                        for (c.args) |arg| {
                            try self.compileExpr(arg.*);
                        }
                        try self.emitOp(.op_print, 0);
                        try self.emitByte(@intCast(c.args.len), 0);
                        return;
                    }
                }
                // 일반 함수 호출
                try self.compileExpr(c.callee.*);
                for (c.args) |arg| {
                    try self.compileExpr(arg.*);
                }
                try self.emitOp(.op_call, 0);
                try self.emitByte(@intCast(c.args.len), 0);
            },
        }
    }

    // =========================================================================
    // 문장 컴파일
    // =========================================================================

    pub fn compileStmt(self: *Compiler, stmt: Stmt) CompileError!void {
        switch (stmt) {
            .local_assign => |la| {
                // 값을 먼저 스택에 올림
                for (la.values) |val| {
                    try self.compileExpr(val.*);
                }
                // 값이 부족한 경우 nil 보충
                if (la.values.len < la.names.len) {
                    var i: usize = la.values.len;
                    while (i < la.names.len) : (i += 1) {
                        try self.emitOp(.op_push_nil, 0);
                    }
                }
                // 로컬 변수 등록
                for (la.names) |name| {
                    try self.addLocal(name);
                }
            },
            .assign => |a| {
                // 값을 먼저 모두 컴파일
                for (a.values) |val| {
                    try self.compileExpr(val.*);
                }
                // 역순으로 할당 (스택 순서)
                var i: usize = a.targets.len;
                while (i > 0) {
                    i -= 1;
                    const target = a.targets[i];
                    if (target.* == .identifier) {
                        if (self.resolveLocal(target.identifier)) |slot| {
                            try self.emitOp(.op_set_local, 0);
                            try self.emitByte(slot, 0);
                        } else {
                            const idx = try self.chunk.addConstant(.{ .string = target.identifier });
                            try self.emitOp(.op_set_global, 0);
                            try self.emitU16(idx, 0);
                        }
                    }
                }
            },
            .if_stmt => |is| {
                try self.compileIf(is);
            },
            .while_stmt => |ws| {
                try self.compileWhile(ws);
            },
            .for_numeric => |fn_| {
                try self.compileForNumeric(fn_);
            },
            .repeat_stmt => |rs| {
                try self.compileRepeat(rs);
            },
            .do_stmt => |ds| {
                self.beginScope();
                for (ds.body) |s| {
                    try self.compileStmt(s.*);
                }
                self.endScope();
            },
            .return_stmt => |ret| {
                if (ret.values.len > 0) {
                    try self.compileExpr(ret.values[0].*);
                }
                try self.emitOp(.op_return, 0);
            },
            .break_stmt => {
                // break: 무조건 점프, 나중에 패치
                const jump = try self.emitJump(.op_jump);
                try self.break_jumps.append(self.allocator, jump);
            },
            .expr_stmt => |es| {
                try self.compileExpr(es.expr.*);
                // print 내장함수는 스택에 결과를 남기지 않으므로 pop 스킵
                if (es.expr.* == .call) {
                    if (es.expr.call.callee.* == .identifier and
                        std.mem.eql(u8, es.expr.call.callee.identifier, "print"))
                    {
                        // print는 반환값 없음 — pop 불필요
                    } else {
                        try self.emitOp(.op_pop, 0);
                    }
                } else {
                    try self.emitOp(.op_pop, 0);
                }
            },
        }
    }

    fn compileIf(self: *Compiler, is: Stmt.IfStmt) CompileError!void {
        var end_jumps = std.ArrayListUnmanaged(usize).empty;
        defer end_jumps.deinit(self.allocator);

        for (is.conditions, 0..) |cond, i| {
            try self.compileExpr(cond.*);
            const false_jump = try self.emitJump(.op_jump_if_false);
            try self.emitOp(.op_pop, 0); // 조건값 제거

            // 분기 바디
            self.beginScope();
            for (is.bodies[i]) |s| {
                try self.compileStmt(s.*);
            }
            self.endScope();

            // 분기 끝에서 if 전체 끝으로 점프
            const end_jump = try self.emitJump(.op_jump);
            try end_jumps.append(self.allocator, end_jump);

            try self.patchJump(false_jump);
            try self.emitOp(.op_pop, 0); // 조건값 제거 (false 분기)
        }

        // else 바디
        if (is.else_body) |eb| {
            self.beginScope();
            for (eb) |s| {
                try self.compileStmt(s.*);
            }
            self.endScope();
        }

        // 모든 end_jump 패치
        for (end_jumps.items) |jump| {
            try self.patchJump(jump);
        }
    }

    fn compileWhile(self: *Compiler, ws: Stmt.WhileStmt) CompileError!void {
        const loop_start = self.chunk.currentOffset();

        // 이전 break 점프 저장
        const prev_break_count = self.break_jumps.items.len;
        self.loop_depth += 1;

        try self.compileExpr(ws.condition.*);
        const exit_jump = try self.emitJump(.op_jump_if_false);
        try self.emitOp(.op_pop, 0); // 조건값 제거

        self.beginScope();
        for (ws.body) |s| {
            try self.compileStmt(s.*);
        }
        self.endScope();

        try self.emitLoop(loop_start);

        try self.patchJump(exit_jump);
        try self.emitOp(.op_pop, 0); // 조건값 제거

        // break 점프 패치
        while (self.break_jumps.items.len > prev_break_count) {
            const jump = self.break_jumps.pop().?;
            try self.patchJump(jump);
        }
        self.loop_depth -= 1;
    }

    fn compileForNumeric(self: *Compiler, fn_: Stmt.ForNumeric) CompileError!void {
        self.beginScope();

        // 루프 변수, limit, step을 로컬로 할당
        // 내부 변수: __for_limit, __for_step, loop_var(i)
        try self.compileExpr(fn_.start.*);
        try self.addLocal("(for init)");

        try self.compileExpr(fn_.limit.*);
        try self.addLocal("(for limit)");

        if (fn_.step) |step| {
            try self.compileExpr(step.*);
        } else {
            try self.emitConstant(.{ .integer = 1 });
        }
        try self.addLocal("(for step)");

        // 루프 변수: start 값으로 초기화 (이미 스택에)
        // 실제 사용자 변수 i 를 위한 슬롯
        const init_slot = self.locals.items.len - 3; // start 값 슬롯

        // 루프 시작
        const loop_start = self.chunk.currentOffset();

        // 이전 break 점프 저장
        const prev_break_count = self.break_jumps.items.len;
        self.loop_depth += 1;

        // 조건 체크: init <= limit (step > 0) 또는 init >= limit (step < 0)
        // 간소화: step 슬롯과 비교
        const step_slot: u8 = @intCast(init_slot + 2);
        const limit_slot: u8 = @intCast(init_slot + 1);

        // step > 0 인지 확인 (런타임에서 처리해야 하지만 VM에서 처리)
        // 간소화: init, limit, step을 VM이 직접 관리하게 하는 대신
        //         컴파일러가 비교 코드를 방출

        // init_val을 스택에 올림
        try self.emitOp(.op_get_local, 0);
        try self.emitByte(@intCast(init_slot), 0);
        // limit을 스택에 올림
        try self.emitOp(.op_get_local, 0);
        try self.emitByte(limit_slot, 0);
        // step을 확인: step > 0 이면 init <= limit, step < 0 이면 init >= limit
        // 간소화를 위해 step > 0 기본 가정 → op_le 사용
        // 런타임에서 step 부호에 따라 다르게 처리해야 하지만 MVP에서는 간소화
        try self.emitOp(.op_get_local, 0);
        try self.emitByte(step_slot, 0);
        try self.emitConstant(.{ .integer = 0 });
        try self.emitOp(.op_lt, 0); // step < 0 ?

        // step < 0 이면 init >= limit 체크
        const neg_step_jump = try self.emitJump(.op_jump_if_false);
        try self.emitOp(.op_pop, 0); // step<0 결과 pop
        // step < 0: init >= limit → init가 먼저, limit가 다음이므로 ge
        try self.emitOp(.op_ge, 0);
        const after_cmp = try self.emitJump(.op_jump);

        try self.patchJump(neg_step_jump);
        try self.emitOp(.op_pop, 0); // step<0 결과 pop
        // step >= 0: init <= limit
        try self.emitOp(.op_le, 0);

        try self.patchJump(after_cmp);

        const exit_jump = try self.emitJump(.op_jump_if_false);
        try self.emitOp(.op_pop, 0); // 비교 결과 pop

        // 루프 변수 i를 사용자에게 노출
        try self.emitOp(.op_get_local, 0);
        try self.emitByte(@intCast(init_slot), 0);
        try self.addLocal(fn_.name);

        // 루프 바디
        for (fn_.body) |s| {
            try self.compileStmt(s.*);
        }

        // 사용자 루프 변수 pop
        self.locals.items.len -= 1;
        try self.emitOp(.op_pop, 0);

        // init += step
        try self.emitOp(.op_get_local, 0);
        try self.emitByte(@intCast(init_slot), 0);
        try self.emitOp(.op_get_local, 0);
        try self.emitByte(step_slot, 0);
        try self.emitOp(.op_add, 0);
        try self.emitOp(.op_set_local, 0);
        try self.emitByte(@intCast(init_slot), 0);

        try self.emitLoop(loop_start);

        try self.patchJump(exit_jump);
        try self.emitOp(.op_pop, 0); // 비교 결과 pop

        // break 점프 패치
        while (self.break_jumps.items.len > prev_break_count) {
            const jump = self.break_jumps.pop().?;
            try self.patchJump(jump);
        }
        self.loop_depth -= 1;

        self.endScope();
    }

    fn compileRepeat(self: *Compiler, rs: Stmt.RepeatStmt) CompileError!void {
        const loop_start = self.chunk.currentOffset();

        const prev_break_count = self.break_jumps.items.len;
        self.loop_depth += 1;

        self.beginScope();
        for (rs.body) |s| {
            try self.compileStmt(s.*);
        }

        try self.compileExpr(rs.condition.*);
        const exit_jump = try self.emitJump(.op_jump_if_false);
        try self.emitOp(.op_pop, 0); // 조건값 제거 (true — 루프 탈출)

        // 스코프 정리 후 점프하지 않음 (탈출)
        self.endScope();

        // break 패치를 여기서 (루프 후)
        while (self.break_jumps.items.len > prev_break_count) {
            const jump = self.break_jumps.pop().?;
            try self.patchJump(jump);
        }
        self.loop_depth -= 1;

        const end_jump = try self.emitJump(.op_jump);
        try self.patchJump(exit_jump);
        try self.emitOp(.op_pop, 0); // 조건값 제거 (false — 계속 반복)

        // 스코프를 여기서도 정리해야 하지만, 간소화: beginScope/endScope는 컴파일타임 추적
        try self.emitLoop(loop_start);

        try self.patchJump(end_jump);
    }

    // =========================================================================
    // 스코프 관리
    // =========================================================================

    fn beginScope(self: *Compiler) void {
        self.scope_depth += 1;
    }

    fn endScope(self: *Compiler) void {
        self.scope_depth -= 1;
        // 현재 스코프보다 깊은 로컬 변수 pop
        while (self.locals.items.len > 0 and
            self.locals.items[self.locals.items.len - 1].depth > self.scope_depth)
        {
            self.emitOp(.op_pop, 0) catch {};
            self.locals.items.len -= 1;
        }
    }

    fn addLocal(self: *Compiler, name: []const u8) !void {
        try self.locals.append(self.allocator, .{
            .name = name,
            .depth = self.scope_depth,
        });
    }

    fn resolveLocal(self: *const Compiler, name: []const u8) ?u8 {
        // 역순으로 검색 (내부 스코프 우선)
        var i: usize = self.locals.items.len;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, self.locals.items[i].name, name)) {
                return @intCast(i);
            }
        }
        return null;
    }

    // =========================================================================
    // 바이트코드 방출 헬퍼
    // =========================================================================

    fn emitOp(self: *Compiler, op: OpCode, line: u32) !void {
        try self.chunk.write(@intFromEnum(op), line);
    }

    fn emitByte(self: *Compiler, byte: u8, line: u32) !void {
        try self.chunk.write(byte, line);
    }

    fn emitU16(self: *Compiler, value: u16, line: u32) !void {
        try self.chunk.write(@intCast(value >> 8), line);
        try self.chunk.write(@intCast(value & 0xFF), line);
    }

    fn emitConstant(self: *Compiler, value: Value) !void {
        const idx = try self.chunk.addConstant(value);
        try self.emitOp(.op_push_constant, 0);
        try self.emitU16(idx, 0);
    }

    /// 점프 명령어 방출. 패치할 오프셋 반환.
    fn emitJump(self: *Compiler, op: OpCode) !usize {
        try self.emitOp(op, 0);
        // placeholder: 0xFFFF
        try self.emitByte(0xFF, 0);
        try self.emitByte(0xFF, 0);
        return self.chunk.currentOffset() - 2;
    }

    /// 점프 목적지 패치
    fn patchJump(self: *Compiler, offset: usize) !void {
        const jump = self.chunk.currentOffset() - offset - 2;
        if (jump > 0xFFFF) return error.InvalidJumpOffset;
        self.chunk.code.items[offset] = @intCast(jump >> 8);
        self.chunk.code.items[offset + 1] = @intCast(jump & 0xFF);
    }

    /// 역방향 루프 점프
    fn emitLoop(self: *Compiler, loop_start: usize) !void {
        try self.emitOp(.op_loop, 0);
        const offset = self.chunk.currentOffset() - loop_start + 2;
        if (offset > 0xFFFF) return error.InvalidJumpOffset;
        try self.emitU16(@intCast(offset), 0);
    }
};

// =============================================================================
// Tests — Session 6: Compiler 표현식
// =============================================================================

test "T6-3: 정수 리터럴 컴파일" {
    const allocator = std.testing.allocator;
    var compiler = Compiler.init(allocator);
    defer compiler.deinit();

    const expr = Expr{ .integer_literal = 42 };
    try compiler.compileExpr(expr);

    try std.testing.expectEqual(@intFromEnum(OpCode.op_push_constant), compiler.chunk.code.items[0]);
    try std.testing.expectEqual(42, compiler.chunk.constants.items[0].integer);
}

test "T6-4: 불리언 컴파일" {
    const allocator = std.testing.allocator;
    var compiler = Compiler.init(allocator);
    defer compiler.deinit();

    try compiler.compileExpr(.{ .boolean_literal = true });
    try std.testing.expectEqual(@intFromEnum(OpCode.op_push_true), compiler.chunk.code.items[0]);

    try compiler.compileExpr(.{ .boolean_literal = false });
    try std.testing.expectEqual(@intFromEnum(OpCode.op_push_false), compiler.chunk.code.items[1]);
}

test "T6-5: nil 컴파일" {
    const allocator = std.testing.allocator;
    var compiler = Compiler.init(allocator);
    defer compiler.deinit();

    try compiler.compileExpr(.nil_literal);
    try std.testing.expectEqual(@intFromEnum(OpCode.op_push_nil), compiler.chunk.code.items[0]);
}

test "T6-6: 산술 이항 — 1 + 2" {
    const allocator = std.testing.allocator;

    var lexer = Lexer.init(allocator, "1 + 2");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    var parser = Parser.init(allocator, tokens);
    const expr = try parser.parseExpression(0);
    defer {
        @constCast(expr).deinit(allocator);
        allocator.destroy(expr);
    }

    var compiler = Compiler.init(allocator);
    defer compiler.deinit();
    try compiler.compileExpr(expr.*);

    // push(1), push(2), add
    const code = compiler.chunk.code.items;
    try std.testing.expectEqual(@intFromEnum(OpCode.op_push_constant), code[0]); // push 1
    try std.testing.expectEqual(@intFromEnum(OpCode.op_push_constant), code[3]); // push 2
    try std.testing.expectEqual(@intFromEnum(OpCode.op_add), code[6]); // add
}

test "T6-7: 복합 산술 — 1 + 2 * 3" {
    const allocator = std.testing.allocator;

    var lexer = Lexer.init(allocator, "1 + 2 * 3");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    var parser = Parser.init(allocator, tokens);
    const expr = try parser.parseExpression(0);
    defer {
        @constCast(expr).deinit(allocator);
        allocator.destroy(expr);
    }

    var compiler = Compiler.init(allocator);
    defer compiler.deinit();
    try compiler.compileExpr(expr.*);

    // push(1), push(2), push(3), mul, add
    const code = compiler.chunk.code.items;
    const last_two = [_]u8{ code[code.len - 2], code[code.len - 1] };
    try std.testing.expectEqual(@intFromEnum(OpCode.op_mul), last_two[0]);
    try std.testing.expectEqual(@intFromEnum(OpCode.op_add), last_two[1]);
}

test "T6-8: 단항 부정 — -42" {
    const allocator = std.testing.allocator;

    var lexer = Lexer.init(allocator, "-42");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    var parser = Parser.init(allocator, tokens);
    const expr = try parser.parseExpression(0);
    defer {
        @constCast(expr).deinit(allocator);
        allocator.destroy(expr);
    }

    var compiler = Compiler.init(allocator);
    defer compiler.deinit();
    try compiler.compileExpr(expr.*);

    const code = compiler.chunk.code.items;
    try std.testing.expectEqual(@intFromEnum(OpCode.op_push_constant), code[0]); // push 42
    try std.testing.expectEqual(@intFromEnum(OpCode.op_negate), code[3]); // negate
}

test "T6-12: 컴파일 메모리 누수" {
    const allocator = std.testing.allocator;

    var lexer = Lexer.init(allocator, "1 + 2 * 3 - 4");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    var parser = Parser.init(allocator, tokens);
    const expr = try parser.parseExpression(0);
    defer {
        @constCast(expr).deinit(allocator);
        allocator.destroy(expr);
    }

    var compiler = Compiler.init(allocator);
    defer compiler.deinit();
    try compiler.compileExpr(expr.*);
}
