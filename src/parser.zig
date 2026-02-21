const std = @import("std");
const Token = @import("token.zig").Token;
const TokenType = @import("token.zig").TokenType;
const ast = @import("ast.zig");
const Expr = ast.Expr;
const Stmt = ast.Stmt;
const Block = ast.Block;
const Lexer = @import("lexer.zig").Lexer;

pub const ParserError = error{
    UnexpectedToken,
    ExpectedExpression,
    ExpectedToken,
    OutOfMemory,
};

pub const Parser = struct {
    tokens: []const Token,
    pos: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, tokens: []const Token) Parser {
        return .{
            .tokens = tokens,
            .pos = 0,
            .allocator = allocator,
        };
    }

    // =========================================================================
    // 토큰 유틸리티
    // =========================================================================

    fn current(self: *const Parser) Token {
        return self.tokens[self.pos];
    }

    fn currentType(self: *const Parser) TokenType {
        return self.tokens[self.pos].type;
    }

    fn advance_token(self: *Parser) Token {
        const tok = self.tokens[self.pos];
        if (self.pos < self.tokens.len - 1) {
            self.pos += 1;
        }
        return tok;
    }

    fn check(self: *const Parser, tt: TokenType) bool {
        return self.currentType() == tt;
    }

    fn match(self: *Parser, tt: TokenType) bool {
        if (self.check(tt)) {
            _ = self.advance_token();
            return true;
        }
        return false;
    }

    fn expect(self: *Parser, tt: TokenType) ParserError!Token {
        if (self.check(tt)) {
            return self.advance_token();
        }
        return error.ExpectedToken;
    }

    // =========================================================================
    // 표현식 파싱 (Pratt parser)
    // =========================================================================

    /// 연산자 우선순위 (Lua 5.4 스펙)
    const Precedence = enum(u8) {
        none = 0,
        or_ = 1,
        and_ = 2,
        comparison = 3,
        bitor = 4,
        bitxor = 5,
        bitand = 6,
        shift = 7,
        concat = 8,
        additive = 9,
        multiplicative = 10,
        unary = 11,
        power = 12,
    };

    fn getBinaryPrecedence(tt: TokenType) ?Precedence {
        return switch (tt) {
            .kw_or => .or_,
            .kw_and => .and_,
            .equal_equal, .tilde_equal, .less, .greater, .less_equal, .greater_equal => .comparison,
            .pipe => .bitor,
            .tilde => .bitxor,
            .ampersand => .bitand,
            .less_less, .greater_greater => .shift,
            .dot_dot => .concat,
            .plus, .minus => .additive,
            .star, .slash, .slash_slash, .percent => .multiplicative,
            .caret => .power,
            else => null,
        };
    }

    fn isRightAssociative(tt: TokenType) bool {
        return tt == .dot_dot or tt == .caret;
    }

    /// Pratt parser 메인 루프
    pub fn parseExpression(self: *Parser, min_prec: u8) ParserError!*Expr {
        var left = try self.parsePrefixExpr();

        while (true) {
            const tt = self.currentType();

            // 함수 호출: identifier( 형태
            if (tt == .left_paren) {
                left = try self.parseCall(left);
                continue;
            }

            const prec = getBinaryPrecedence(tt) orelse break;
            const prec_val = @intFromEnum(prec);
            if (prec_val < min_prec) break;

            const op = self.advance_token().type;

            // 우결합 연산자: 동일 우선순위에서 오른쪽 먼저 결합
            const next_min: u8 = if (isRightAssociative(op)) prec_val else prec_val + 1;
            const right = try self.parseExpression(next_min);

            const node = try self.allocator.create(Expr);
            node.* = .{ .binary_op = .{ .op = op, .left = left, .right = right } };
            left = node;
        }

        return left;
    }

    /// prefix 표현식 (리터럴, 식별자, 괄호, 단항 연산자)
    fn parsePrefixExpr(self: *Parser) ParserError!*Expr {
        const tt = self.currentType();

        // 단항 연산자: -, not, ~, #
        if (tt == .minus or tt == .kw_not or tt == .tilde or tt == .hash) {
            const op = self.advance_token().type;
            const operand = try self.parseExpression(@intFromEnum(Precedence.unary));
            const node = try self.allocator.create(Expr);
            node.* = .{ .unary_op = .{ .op = op, .operand = operand } };
            return node;
        }

        // 괄호
        if (tt == .left_paren) {
            _ = self.advance_token(); // '('
            const expr = try self.parseExpression(0);
            _ = try self.expect(.right_paren);
            return expr;
        }

        return try self.parsePrimary();
    }

    /// 기본 리터럴/식별자
    fn parsePrimary(self: *Parser) ParserError!*Expr {
        const tok = self.current();
        const node = try self.allocator.create(Expr);

        switch (tok.type) {
            .kw_nil => {
                _ = self.advance_token();
                node.* = .nil_literal;
            },
            .kw_true => {
                _ = self.advance_token();
                node.* = .{ .boolean_literal = true };
            },
            .kw_false => {
                _ = self.advance_token();
                node.* = .{ .boolean_literal = false };
            },
            .integer => {
                _ = self.advance_token();
                const val = parseInteger(tok.lexeme) catch {
                    self.allocator.destroy(node);
                    return error.UnexpectedToken;
                };
                node.* = .{ .integer_literal = val };
            },
            .float => {
                _ = self.advance_token();
                const val = parseFloat(tok.lexeme) catch {
                    self.allocator.destroy(node);
                    return error.UnexpectedToken;
                };
                node.* = .{ .float_literal = val };
            },
            .string => {
                _ = self.advance_token();
                // lexeme은 따옴표 포함. 내부 콘텐츠만 추출.
                const content = extractStringContent(tok.lexeme);
                node.* = .{ .string_literal = content };
            },
            .identifier => {
                _ = self.advance_token();
                node.* = .{ .identifier = tok.lexeme };
            },
            else => {
                self.allocator.destroy(node);
                return error.ExpectedExpression;
            },
        }

        return node;
    }

    /// 함수 호출 파싱
    fn parseCall(self: *Parser, callee: *Expr) ParserError!*Expr {
        _ = self.advance_token(); // '('
        var args = std.ArrayListUnmanaged(*Expr).empty;
        errdefer {
            for (args.items) |a| {
                a.*.deinit(self.allocator);
                self.allocator.destroy(a);
            }
            args.deinit(self.allocator);
        }

        if (!self.check(.right_paren)) {
            const first = try self.parseExpression(0);
            try args.append(self.allocator, first);

            while (self.match(.comma)) {
                const arg = try self.parseExpression(0);
                try args.append(self.allocator, arg);
            }
        }

        _ = try self.expect(.right_paren);

        const node = try self.allocator.create(Expr);
        node.* = .{ .call = .{
            .callee = callee,
            .args = try args.toOwnedSlice(self.allocator),
        } };
        return node;
    }

    // =========================================================================
    // 문장 파싱 (Session 5에서 완성)
    // =========================================================================

    pub fn parseBlock(self: *Parser) ParserError!Block {
        var stmts = std.ArrayListUnmanaged(*Stmt).empty;
        errdefer {
            for (stmts.items) |s| {
                s.*.deinit(self.allocator);
                self.allocator.destroy(s);
            }
            stmts.deinit(self.allocator);
        }

        while (!self.isBlockEnd()) {
            const stmt = try self.parseStatement();
            try stmts.append(self.allocator, stmt);
        }

        return try stmts.toOwnedSlice(self.allocator);
    }

    fn isBlockEnd(self: *const Parser) bool {
        const tt = self.currentType();
        return tt == .eof or tt == .kw_end or tt == .kw_else or
            tt == .kw_elseif or tt == .kw_until;
    }

    pub fn parseStatement(self: *Parser) ParserError!*Stmt {
        const tt = self.currentType();
        return switch (tt) {
            .kw_local => try self.parseLocalAssign(),
            .kw_if => try self.parseIf(),
            .kw_while => try self.parseWhile(),
            .kw_for => try self.parseFor(),
            .kw_repeat => try self.parseRepeat(),
            .kw_do => try self.parseDo(),
            .kw_return => try self.parseReturn(),
            .kw_break => try self.parseBreak(),
            else => try self.parseAssignOrExprStmt(),
        };
    }

    fn parseLocalAssign(self: *Parser) ParserError!*Stmt {
        _ = self.advance_token(); // 'local'

        var names = std.ArrayListUnmanaged([]const u8).empty;
        errdefer names.deinit(self.allocator);

        const first_name = try self.expect(.identifier);
        try names.append(self.allocator, first_name.lexeme);

        while (self.match(.comma)) {
            const name = try self.expect(.identifier);
            try names.append(self.allocator, name.lexeme);
        }

        var values = std.ArrayListUnmanaged(*Expr).empty;
        errdefer {
            for (values.items) |v| {
                v.*.deinit(self.allocator);
                self.allocator.destroy(v);
            }
            values.deinit(self.allocator);
        }

        if (self.match(.equal)) {
            const first_val = try self.parseExpression(0);
            try values.append(self.allocator, first_val);

            while (self.match(.comma)) {
                const val = try self.parseExpression(0);
                try values.append(self.allocator, val);
            }
        }

        // 세미콜론 옵션
        _ = self.match(.semicolon);

        const stmt = try self.allocator.create(Stmt);
        stmt.* = .{ .local_assign = .{
            .names = try names.toOwnedSlice(self.allocator),
            .values = try values.toOwnedSlice(self.allocator),
        } };
        return stmt;
    }

    fn parseIf(self: *Parser) ParserError!*Stmt {
        _ = self.advance_token(); // 'if'

        var conditions = std.ArrayListUnmanaged(*Expr).empty;
        errdefer {
            for (conditions.items) |c| {
                c.*.deinit(self.allocator);
                self.allocator.destroy(c);
            }
            conditions.deinit(self.allocator);
        }

        var bodies = std.ArrayListUnmanaged(Block).empty;
        errdefer {
            for (bodies.items) |body| {
                ast.freeBlock(body, self.allocator);
            }
            bodies.deinit(self.allocator);
        }

        // if condition then block
        const cond = try self.parseExpression(0);
        try conditions.append(self.allocator, cond);
        _ = try self.expect(.kw_then);
        const body = try self.parseBlock();
        try bodies.append(self.allocator, body);

        // elseif condition then block
        while (self.match(.kw_elseif)) {
            const elif_cond = try self.parseExpression(0);
            try conditions.append(self.allocator, elif_cond);
            _ = try self.expect(.kw_then);
            const elif_body = try self.parseBlock();
            try bodies.append(self.allocator, elif_body);
        }

        // else block
        var else_body: ?Block = null;
        if (self.match(.kw_else)) {
            else_body = try self.parseBlock();
        }

        _ = try self.expect(.kw_end);

        const stmt = try self.allocator.create(Stmt);
        stmt.* = .{ .if_stmt = .{
            .conditions = try conditions.toOwnedSlice(self.allocator),
            .bodies = try bodies.toOwnedSlice(self.allocator),
            .else_body = else_body,
        } };
        return stmt;
    }

    fn parseWhile(self: *Parser) ParserError!*Stmt {
        _ = self.advance_token(); // 'while'
        const condition = try self.parseExpression(0);
        _ = try self.expect(.kw_do);
        const body = try self.parseBlock();
        _ = try self.expect(.kw_end);

        const stmt = try self.allocator.create(Stmt);
        stmt.* = .{ .while_stmt = .{
            .condition = condition,
            .body = body,
        } };
        return stmt;
    }

    fn parseFor(self: *Parser) ParserError!*Stmt {
        _ = self.advance_token(); // 'for'
        const name = try self.expect(.identifier);
        _ = try self.expect(.equal);
        const start = try self.parseExpression(0);
        _ = try self.expect(.comma);
        const limit = try self.parseExpression(0);

        var step: ?*Expr = null;
        if (self.match(.comma)) {
            step = try self.parseExpression(0);
        }

        _ = try self.expect(.kw_do);
        const body = try self.parseBlock();
        _ = try self.expect(.kw_end);

        const stmt = try self.allocator.create(Stmt);
        stmt.* = .{ .for_numeric = .{
            .name = name.lexeme,
            .start = start,
            .limit = limit,
            .step = step,
            .body = body,
        } };
        return stmt;
    }

    fn parseRepeat(self: *Parser) ParserError!*Stmt {
        _ = self.advance_token(); // 'repeat'
        const body = try self.parseBlock();
        _ = try self.expect(.kw_until);
        const condition = try self.parseExpression(0);

        const stmt = try self.allocator.create(Stmt);
        stmt.* = .{ .repeat_stmt = .{
            .body = body,
            .condition = condition,
        } };
        return stmt;
    }

    fn parseDo(self: *Parser) ParserError!*Stmt {
        _ = self.advance_token(); // 'do'
        const body = try self.parseBlock();
        _ = try self.expect(.kw_end);

        const stmt = try self.allocator.create(Stmt);
        stmt.* = .{ .do_stmt = .{
            .body = body,
        } };
        return stmt;
    }

    fn parseReturn(self: *Parser) ParserError!*Stmt {
        _ = self.advance_token(); // 'return'

        var values = std.ArrayListUnmanaged(*Expr).empty;
        errdefer {
            for (values.items) |v| {
                v.*.deinit(self.allocator);
                self.allocator.destroy(v);
            }
            values.deinit(self.allocator);
        }

        if (!self.isBlockEnd() and !self.check(.semicolon)) {
            const first = try self.parseExpression(0);
            try values.append(self.allocator, first);

            while (self.match(.comma)) {
                const val = try self.parseExpression(0);
                try values.append(self.allocator, val);
            }
        }

        _ = self.match(.semicolon);

        const stmt = try self.allocator.create(Stmt);
        stmt.* = .{ .return_stmt = .{
            .values = try values.toOwnedSlice(self.allocator),
        } };
        return stmt;
    }

    fn parseBreak(self: *Parser) ParserError!*Stmt {
        _ = self.advance_token(); // 'break'
        const stmt = try self.allocator.create(Stmt);
        stmt.* = .break_stmt;
        return stmt;
    }

    /// 할당문 또는 표현식문 (함수 호출)
    fn parseAssignOrExprStmt(self: *Parser) ParserError!*Stmt {
        const expr = try self.parseExpression(0);

        // 할당문: expr = expr 또는 expr, expr = expr, expr
        if (self.check(.equal) or self.check(.comma)) {
            var targets = std.ArrayListUnmanaged(*Expr).empty;
            errdefer {
                for (targets.items) |t| {
                    t.*.deinit(self.allocator);
                    self.allocator.destroy(t);
                }
                targets.deinit(self.allocator);
            }
            try targets.append(self.allocator, expr);

            while (self.match(.comma)) {
                const target = try self.parseExpression(0);
                try targets.append(self.allocator, target);
            }

            _ = try self.expect(.equal);

            var values = std.ArrayListUnmanaged(*Expr).empty;
            errdefer {
                for (values.items) |v| {
                    v.*.deinit(self.allocator);
                    self.allocator.destroy(v);
                }
                values.deinit(self.allocator);
            }

            const first_val = try self.parseExpression(0);
            try values.append(self.allocator, first_val);

            while (self.match(.comma)) {
                const val = try self.parseExpression(0);
                try values.append(self.allocator, val);
            }

            _ = self.match(.semicolon);

            const stmt = try self.allocator.create(Stmt);
            stmt.* = .{ .assign = .{
                .targets = try targets.toOwnedSlice(self.allocator),
                .values = try values.toOwnedSlice(self.allocator),
            } };
            return stmt;
        }

        // 표현식문 (함수 호출 등)
        _ = self.match(.semicolon);

        const stmt = try self.allocator.create(Stmt);
        stmt.* = .{ .expr_stmt = .{ .expr = expr } };
        return stmt;
    }

    // =========================================================================
    // 숫자 파싱 헬퍼
    // =========================================================================

    fn parseInteger(lexeme: []const u8) !i64 {
        // 16진수
        if (lexeme.len > 2 and (lexeme[1] == 'x' or lexeme[1] == 'X')) {
            return std.fmt.parseInt(i64, lexeme, 0) catch return error.InvalidNumber;
        }
        return std.fmt.parseInt(i64, lexeme, 10) catch return error.InvalidNumber;
    }

    fn parseFloat(lexeme: []const u8) !f64 {
        return std.fmt.parseFloat(f64, lexeme) catch return error.InvalidNumber;
    }

    fn extractStringContent(lexeme: []const u8) []const u8 {
        if (lexeme.len < 2) return lexeme;
        const first = lexeme[0];
        if (first == '"' or first == '\'') {
            // 따옴표 문자열: 양끝 따옴표 제거
            return lexeme[1 .. lexeme.len - 1];
        }
        if (first == '[') {
            // 롱 브래킷 문자열: [=[ ... ]=] — 여는/닫는 브래킷 제거
            var level: usize = 0;
            var i: usize = 1;
            while (i < lexeme.len and lexeme[i] == '=') {
                level += 1;
                i += 1;
            }
            // i는 두 번째 '[' 위치. 콘텐츠는 i+1부터 끝 브래킷 전까지
            const start = i + 1;
            const end = lexeme.len - (2 + level);
            if (start <= end) return lexeme[start..end];
            return "";
        }
        return lexeme;
    }
};

// =============================================================================
// Tests — Session 4: Parser 표현식
// =============================================================================

fn tokenizeSource(allocator: std.mem.Allocator, source: []const u8) ![]const Token {
    var lexer = Lexer.init(allocator, source);
    return lexer.tokenize() catch |err| {
        lexer.deinit();
        return err;
    };
}

test "T4-4: 리터럴 파싱 — 정수" {
    const allocator = std.testing.allocator;
    var lexer = Lexer.init(allocator, "42");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    var parser = Parser.init(allocator, tokens);
    const expr = try parser.parseExpression(0);
    defer {
        expr.deinit(allocator);
        allocator.destroy(expr);
    }
    try std.testing.expectEqual(Expr{ .integer_literal = 42 }, expr.*);
}

test "T4-5: 단항 연산 — -42" {
    const allocator = std.testing.allocator;
    var lexer = Lexer.init(allocator, "-42");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    var parser = Parser.init(allocator, tokens);
    const expr = try parser.parseExpression(0);
    defer {
        expr.deinit(allocator);
        allocator.destroy(expr);
    }
    try std.testing.expectEqual(TokenType.minus, expr.unary_op.op);
    try std.testing.expectEqual(Expr{ .integer_literal = 42 }, expr.unary_op.operand.*);
}

test "T4-6: 이항 산술 — 1 + 2" {
    const allocator = std.testing.allocator;
    var lexer = Lexer.init(allocator, "1 + 2");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    var parser = Parser.init(allocator, tokens);
    const expr = try parser.parseExpression(0);
    defer {
        expr.deinit(allocator);
        allocator.destroy(expr);
    }
    try std.testing.expectEqual(TokenType.plus, expr.binary_op.op);
    try std.testing.expectEqual(Expr{ .integer_literal = 1 }, expr.binary_op.left.*);
    try std.testing.expectEqual(Expr{ .integer_literal = 2 }, expr.binary_op.right.*);
}

test "T4-7: 연산자 우선순위 — 1 + 2 * 3" {
    const allocator = std.testing.allocator;
    var lexer = Lexer.init(allocator, "1 + 2 * 3");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    var parser = Parser.init(allocator, tokens);
    const expr = try parser.parseExpression(0);
    defer {
        expr.deinit(allocator);
        allocator.destroy(expr);
    }
    // 최외곽: +
    try std.testing.expectEqual(TokenType.plus, expr.binary_op.op);
    try std.testing.expectEqual(Expr{ .integer_literal = 1 }, expr.binary_op.left.*);
    // 우측: *
    try std.testing.expectEqual(TokenType.star, expr.binary_op.right.binary_op.op);
    try std.testing.expectEqual(Expr{ .integer_literal = 2 }, expr.binary_op.right.binary_op.left.*);
    try std.testing.expectEqual(Expr{ .integer_literal = 3 }, expr.binary_op.right.binary_op.right.*);
}

test "T4-8: 괄호 — (1 + 2) * 3" {
    const allocator = std.testing.allocator;
    var lexer = Lexer.init(allocator, "(1 + 2) * 3");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    var parser = Parser.init(allocator, tokens);
    const expr = try parser.parseExpression(0);
    defer {
        expr.deinit(allocator);
        allocator.destroy(expr);
    }
    // 최외곽: *
    try std.testing.expectEqual(TokenType.star, expr.binary_op.op);
    // 좌측: +
    try std.testing.expectEqual(TokenType.plus, expr.binary_op.left.binary_op.op);
    try std.testing.expectEqual(Expr{ .integer_literal = 3 }, expr.binary_op.right.*);
}

test "T4-9: 우결합 — 문자열 연결" {
    const allocator = std.testing.allocator;
    var lexer = Lexer.init(allocator, "\"a\" .. \"b\" .. \"c\"");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    var parser = Parser.init(allocator, tokens);
    const expr = try parser.parseExpression(0);
    defer {
        expr.deinit(allocator);
        allocator.destroy(expr);
    }
    // 우결합: (.., "a", (.., "b", "c"))
    try std.testing.expectEqual(TokenType.dot_dot, expr.binary_op.op);
    try std.testing.expectEqualStrings("a", expr.binary_op.left.string_literal);
    try std.testing.expectEqual(TokenType.dot_dot, expr.binary_op.right.binary_op.op);
    try std.testing.expectEqualStrings("b", expr.binary_op.right.binary_op.left.string_literal);
    try std.testing.expectEqualStrings("c", expr.binary_op.right.binary_op.right.string_literal);
}

test "T4-10: 거듭제곱 우결합 — 2 ^ 3 ^ 4" {
    const allocator = std.testing.allocator;
    var lexer = Lexer.init(allocator, "2 ^ 3 ^ 4");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    var parser = Parser.init(allocator, tokens);
    const expr = try parser.parseExpression(0);
    defer {
        expr.deinit(allocator);
        allocator.destroy(expr);
    }
    // 우결합: (^, 2, (^, 3, 4))
    try std.testing.expectEqual(TokenType.caret, expr.binary_op.op);
    try std.testing.expectEqual(Expr{ .integer_literal = 2 }, expr.binary_op.left.*);
    try std.testing.expectEqual(TokenType.caret, expr.binary_op.right.binary_op.op);
    try std.testing.expectEqual(Expr{ .integer_literal = 3 }, expr.binary_op.right.binary_op.left.*);
    try std.testing.expectEqual(Expr{ .integer_literal = 4 }, expr.binary_op.right.binary_op.right.*);
}

test "T4-11: 복합 표현식 — not a and b or c" {
    const allocator = std.testing.allocator;
    var lexer = Lexer.init(allocator, "not a and b or c");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    var parser = Parser.init(allocator, tokens);
    const expr = try parser.parseExpression(0);
    defer {
        expr.deinit(allocator);
        allocator.destroy(expr);
    }
    // or(and(not(a), b), c)
    try std.testing.expectEqual(TokenType.kw_or, expr.binary_op.op);
    const left = expr.binary_op.left;
    try std.testing.expectEqual(TokenType.kw_and, left.binary_op.op);
    try std.testing.expectEqual(TokenType.kw_not, left.binary_op.left.unary_op.op);
}

test "T4-12: 함수 호출 — print(1, 2)" {
    const allocator = std.testing.allocator;
    var lexer = Lexer.init(allocator, "print(1, 2)");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    var parser = Parser.init(allocator, tokens);
    const expr = try parser.parseExpression(0);
    defer {
        expr.deinit(allocator);
        allocator.destroy(expr);
    }
    try std.testing.expectEqualStrings("print", expr.call.callee.identifier);
    try std.testing.expectEqual(2, expr.call.args.len);
    try std.testing.expectEqual(Expr{ .integer_literal = 1 }, expr.call.args[0].*);
    try std.testing.expectEqual(Expr{ .integer_literal = 2 }, expr.call.args[1].*);
}

test "T4-13: AST 메모리 해제 — 복잡 표현식" {
    const allocator = std.testing.allocator;
    var lexer = Lexer.init(allocator, "1 + 2 * 3 - (4 + 5) ^ 6 ^ 7");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    var parser = Parser.init(allocator, tokens);
    const expr = try parser.parseExpression(0);
    expr.deinit(allocator);
    allocator.destroy(expr);
}

// =============================================================================
// Tests — Session 5: Parser 문장
// =============================================================================

/// 테스트 헬퍼: 소스 → 토큰 → Block 파싱 → 정리
fn parseSource(allocator: std.mem.Allocator, source: []const u8) !struct { block: Block, lexer: *Lexer } {
    const lex = try allocator.create(Lexer);
    lex.* = Lexer.init(allocator, source);
    const tokens = try lex.tokenize();
    var parser = Parser.init(allocator, tokens);
    const block = try parser.parseBlock();
    return .{ .block = block, .lexer = lex };
}

fn cleanupParse(allocator: std.mem.Allocator, block: Block, lex: *Lexer) void {
    ast.freeBlock(block, allocator);
    lex.deinit();
    allocator.destroy(lex);
}

test "T5-1: local 할당" {
    const allocator = std.testing.allocator;
    const result = try parseSource(allocator, "local x = 42");
    defer cleanupParse(allocator, result.block, result.lexer);

    try std.testing.expectEqual(1, result.block.len);
    const la = result.block[0].local_assign;
    try std.testing.expectEqual(1, la.names.len);
    try std.testing.expectEqualStrings("x", la.names[0]);
    try std.testing.expectEqual(1, la.values.len);
    try std.testing.expectEqual(Expr{ .integer_literal = 42 }, la.values[0].*);
}

test "T5-2: 다중 할당" {
    const allocator = std.testing.allocator;
    const result = try parseSource(allocator, "local a, b = 1, 2");
    defer cleanupParse(allocator, result.block, result.lexer);

    const la = result.block[0].local_assign;
    try std.testing.expectEqual(2, la.names.len);
    try std.testing.expectEqualStrings("a", la.names[0]);
    try std.testing.expectEqualStrings("b", la.names[1]);
    try std.testing.expectEqual(2, la.values.len);
}

test "T5-3: 글로벌 할당" {
    const allocator = std.testing.allocator;
    const result = try parseSource(allocator, "x = 42");
    defer cleanupParse(allocator, result.block, result.lexer);

    const assign = result.block[0].assign;
    try std.testing.expectEqual(1, assign.targets.len);
    try std.testing.expectEqualStrings("x", assign.targets[0].identifier);
    try std.testing.expectEqual(1, assign.values.len);
}

test "T5-4: if/then/end" {
    const allocator = std.testing.allocator;
    const result = try parseSource(allocator, "if x > 0 then y = 1 end");
    defer cleanupParse(allocator, result.block, result.lexer);

    const is = result.block[0].if_stmt;
    try std.testing.expectEqual(1, is.conditions.len);
    try std.testing.expectEqual(1, is.bodies.len);
    try std.testing.expectEqual(@as(?Block, null), is.else_body);
}

test "T5-5: if/elseif/else" {
    const allocator = std.testing.allocator;
    const result = try parseSource(allocator, "if a then b=1 elseif c then d=2 else e=3 end");
    defer cleanupParse(allocator, result.block, result.lexer);

    const is = result.block[0].if_stmt;
    try std.testing.expectEqual(2, is.conditions.len);
    try std.testing.expectEqual(2, is.bodies.len);
    try std.testing.expect(is.else_body != null);
}

test "T5-6: while" {
    const allocator = std.testing.allocator;
    const result = try parseSource(allocator, "while x > 0 do x = x - 1 end");
    defer cleanupParse(allocator, result.block, result.lexer);

    const ws = result.block[0].while_stmt;
    try std.testing.expectEqual(TokenType.greater, ws.condition.binary_op.op);
    try std.testing.expectEqual(1, ws.body.len);
}

test "T5-7: numeric for with step" {
    const allocator = std.testing.allocator;
    const result = try parseSource(allocator, "for i = 1, 10, 2 do print(i) end");
    defer cleanupParse(allocator, result.block, result.lexer);

    const fn_ = result.block[0].for_numeric;
    try std.testing.expectEqualStrings("i", fn_.name);
    try std.testing.expect(fn_.step != null);
}

test "T5-8: numeric for without step" {
    const allocator = std.testing.allocator;
    const result = try parseSource(allocator, "for i = 1, 10 do end");
    defer cleanupParse(allocator, result.block, result.lexer);

    const fn_ = result.block[0].for_numeric;
    try std.testing.expectEqualStrings("i", fn_.name);
    try std.testing.expectEqual(@as(?*Expr, null), fn_.step);
}

test "T5-9: repeat-until" {
    const allocator = std.testing.allocator;
    const result = try parseSource(allocator, "repeat x = x + 1 until x > 10");
    defer cleanupParse(allocator, result.block, result.lexer);

    const rs = result.block[0].repeat_stmt;
    try std.testing.expectEqual(1, rs.body.len);
    try std.testing.expectEqual(TokenType.greater, rs.condition.binary_op.op);
}

test "T5-10: do-end" {
    const allocator = std.testing.allocator;
    const result = try parseSource(allocator, "do local x = 1 end");
    defer cleanupParse(allocator, result.block, result.lexer);

    const ds = result.block[0].do_stmt;
    try std.testing.expectEqual(1, ds.body.len);
}

test "T5-11: return" {
    const allocator = std.testing.allocator;
    const result = try parseSource(allocator, "return 1, 2");
    defer cleanupParse(allocator, result.block, result.lexer);

    const ret = result.block[0].return_stmt;
    try std.testing.expectEqual(2, ret.values.len);
}

test "T5-12: break" {
    const allocator = std.testing.allocator;
    const result = try parseSource(allocator, "while true do break end");
    defer cleanupParse(allocator, result.block, result.lexer);

    const ws = result.block[0].while_stmt;
    try std.testing.expectEqual(Stmt.break_stmt, ws.body[0].*);
}

test "T5-13: 함수 호출문" {
    const allocator = std.testing.allocator;
    const result = try parseSource(allocator, "print(42)");
    defer cleanupParse(allocator, result.block, result.lexer);

    const es = result.block[0].expr_stmt;
    try std.testing.expectEqualStrings("print", es.expr.call.callee.identifier);
}

test "T5-14: 복합 프로그램" {
    const allocator = std.testing.allocator;
    const source =
        \\local sum = 0
        \\for i = 1, 100 do
        \\  if i % 2 == 0 then
        \\    sum = sum + i
        \\  end
        \\end
        \\print(sum)
    ;
    const result = try parseSource(allocator, source);
    defer cleanupParse(allocator, result.block, result.lexer);

    try std.testing.expectEqual(3, result.block.len);
    // local_assign, for_numeric, expr_stmt
    _ = result.block[0].local_assign;
    _ = result.block[1].for_numeric;
    _ = result.block[2].expr_stmt;
}

test "T5-15: 메모리 누수 — 복잡 Block" {
    const allocator = std.testing.allocator;
    const source =
        \\local x = 1
        \\if x > 0 then
        \\  while x < 10 do
        \\    x = x + 1
        \\  end
        \\else
        \\  repeat
        \\    x = x - 1
        \\  until x <= 0
        \\end
    ;
    const result = try parseSource(allocator, source);
    cleanupParse(allocator, result.block, result.lexer);
}
