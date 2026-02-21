const std = @import("std");
const TokenType = @import("token.zig").TokenType;

/// 표현식 노드
pub const Expr = union(enum) {
    nil_literal,
    boolean_literal: bool,
    integer_literal: i64,
    float_literal: f64,
    string_literal: []const u8,
    identifier: []const u8,
    unary_op: UnaryOp,
    binary_op: BinaryOp,
    call: Call,

    pub const UnaryOp = struct {
        op: TokenType,
        operand: *Expr,
    };

    pub const BinaryOp = struct {
        op: TokenType,
        left: *Expr,
        right: *Expr,
    };

    pub const Call = struct {
        callee: *Expr,
        args: []const *Expr,
    };

    /// AST 노드 재귀 해제
    pub fn deinit(self: *Expr, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .unary_op => |*u| {
                u.operand.deinit(allocator);
                allocator.destroy(u.operand);
            },
            .binary_op => |*b| {
                b.left.deinit(allocator);
                allocator.destroy(b.left);
                b.right.deinit(allocator);
                allocator.destroy(b.right);
            },
            .call => |*c| {
                for (c.args) |arg| {
                    arg.*.deinit(allocator);
                    allocator.destroy(arg);
                }
                allocator.free(c.args);
                c.callee.deinit(allocator);
                allocator.destroy(c.callee);
            },
            else => {},
        }
    }
};

/// 문장 노드
pub const Stmt = union(enum) {
    local_assign: LocalAssign,
    assign: Assign,
    if_stmt: IfStmt,
    while_stmt: WhileStmt,
    for_numeric: ForNumeric,
    repeat_stmt: RepeatStmt,
    do_stmt: DoStmt,
    return_stmt: ReturnStmt,
    break_stmt,
    expr_stmt: ExprStmt,

    pub const LocalAssign = struct {
        names: []const []const u8,
        values: []const *Expr,
    };

    pub const Assign = struct {
        targets: []const *Expr,
        values: []const *Expr,
    };

    pub const IfStmt = struct {
        conditions: []const *Expr,
        bodies: []const Block,
        else_body: ?Block,
    };

    pub const WhileStmt = struct {
        condition: *Expr,
        body: Block,
    };

    pub const ForNumeric = struct {
        name: []const u8,
        start: *Expr,
        limit: *Expr,
        step: ?*Expr,
        body: Block,
    };

    pub const RepeatStmt = struct {
        body: Block,
        condition: *Expr,
    };

    pub const DoStmt = struct {
        body: Block,
    };

    pub const ReturnStmt = struct {
        values: []const *Expr,
    };

    pub const ExprStmt = struct {
        expr: *Expr,
    };

    /// 문장 노드 재귀 해제
    pub fn deinit(self: *Stmt, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .local_assign => |*la| {
                for (la.values) |v| {
                    v.*.deinit(allocator);
                    allocator.destroy(v);
                }
                allocator.free(la.values);
                allocator.free(la.names);
            },
            .assign => |*a| {
                for (a.targets) |t| {
                    t.*.deinit(allocator);
                    allocator.destroy(t);
                }
                allocator.free(a.targets);
                for (a.values) |v| {
                    v.*.deinit(allocator);
                    allocator.destroy(v);
                }
                allocator.free(a.values);
            },
            .if_stmt => |*is| {
                for (is.conditions) |c| {
                    c.*.deinit(allocator);
                    allocator.destroy(c);
                }
                allocator.free(is.conditions);
                for (is.bodies) |body| {
                    freeBlock(body, allocator);
                }
                allocator.free(is.bodies);
                if (is.else_body) |eb| {
                    freeBlock(eb, allocator);
                }
            },
            .while_stmt => |*ws| {
                ws.condition.deinit(allocator);
                allocator.destroy(ws.condition);
                freeBlock(ws.body, allocator);
            },
            .for_numeric => |*fn_| {
                fn_.start.deinit(allocator);
                allocator.destroy(fn_.start);
                fn_.limit.deinit(allocator);
                allocator.destroy(fn_.limit);
                if (fn_.step) |s| {
                    s.*.deinit(allocator);
                    allocator.destroy(s);
                }
                freeBlock(fn_.body, allocator);
            },
            .repeat_stmt => |*rs| {
                freeBlock(rs.body, allocator);
                rs.condition.deinit(allocator);
                allocator.destroy(rs.condition);
            },
            .do_stmt => |*ds| {
                freeBlock(ds.body, allocator);
            },
            .return_stmt => |*ret| {
                for (ret.values) |v| {
                    v.*.deinit(allocator);
                    allocator.destroy(v);
                }
                allocator.free(ret.values);
            },
            .break_stmt => {},
            .expr_stmt => |*es| {
                es.expr.deinit(allocator);
                allocator.destroy(es.expr);
            },
        }
    }
};

pub const Block = []const *Stmt;

pub fn freeBlock(block: Block, allocator: std.mem.Allocator) void {
    for (block) |stmt| {
        stmt.*.deinit(allocator);
        allocator.destroy(stmt);
    }
    allocator.free(block);
}
