const std = @import("std");
const token = @import("token.zig");

pub const Token = token.Token;
pub const TokenType = token.TokenType;

pub const LexerError = error{
    UnexpectedCharacter,
    UnterminatedString,
    UnterminatedLongBracket,
    InvalidNumber,
    OutOfMemory,
};

pub const Lexer = struct {
    source: []const u8,
    pos: usize,
    line: u32,
    column: u32,
    allocator: std.mem.Allocator,
    tokens: std.ArrayListUnmanaged(Token),

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Lexer {
        return .{
            .source = source,
            .pos = 0,
            .line = 1,
            .column = 1,
            .allocator = allocator,
            .tokens = .empty,
        };
    }

    pub fn deinit(self: *Lexer) void {
        self.tokens.deinit(self.allocator);
    }

    pub fn tokenize(self: *Lexer) LexerError![]const Token {
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];

            // 공백 스킵
            if (c == ' ' or c == '\t' or c == '\r') {
                self.advance();
                continue;
            }

            // 줄바꿈
            if (c == '\n') {
                self.advanceNewline();
                continue;
            }

            // 주석 또는 `--`
            if (c == '-' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '-') {
                try self.skipComment();
                continue;
            }

            // 문자열 리터럴
            if (c == '"' or c == '\'') {
                try self.scanString();
                continue;
            }

            // 롱 브래킷 문자열 [[...]] 또는 [=[...]=]
            if (c == '[' and self.pos + 1 < self.source.len) {
                const next = self.source[self.pos + 1];
                if (next == '[' or next == '=') {
                    if (self.detectLongBracketLevel()) |_| {
                        try self.scanLongString();
                        continue;
                    }
                }
            }

            // 숫자 리터럴
            if (std.ascii.isDigit(c)) {
                try self.scanNumber();
                continue;
            }
            // .5 같은 소수점으로 시작하는 숫자
            if (c == '.' and self.pos + 1 < self.source.len and std.ascii.isDigit(self.source[self.pos + 1])) {
                try self.scanNumber();
                continue;
            }

            // 식별자 / 키워드
            if (std.ascii.isAlphabetic(c) or c == '_') {
                self.scanIdentifier();
                continue;
            }

            // 연산자 / 구두점
            try self.scanOperator();
        }

        // EOF 토큰 추가
        try self.addToken(.eof, "", self.line, self.column);
        return self.tokens.items;
    }

    // =========================================================================
    // 내부 헬퍼
    // =========================================================================

    fn peek(self: *const Lexer) ?u8 {
        if (self.pos < self.source.len) return self.source[self.pos];
        return null;
    }

    fn peekNext(self: *const Lexer) ?u8 {
        if (self.pos + 1 < self.source.len) return self.source[self.pos + 1];
        return null;
    }

    fn advance(self: *Lexer) void {
        self.pos += 1;
        self.column += 1;
    }

    fn advanceNewline(self: *Lexer) void {
        self.pos += 1;
        self.line += 1;
        self.column = 1;
    }

    fn addToken(self: *Lexer, tt: TokenType, lexeme: []const u8, line: u32, col: u32) LexerError!void {
        try self.tokens.append(self.allocator, .{
            .type = tt,
            .lexeme = lexeme,
            .line = line,
            .column = col,
        });
    }

    // =========================================================================
    // 식별자 / 키워드 스캐닝
    // =========================================================================

    fn scanIdentifier(self: *Lexer) void {
        const start = self.pos;
        const start_col = self.column;
        while (self.pos < self.source.len) {
            const ch = self.source[self.pos];
            if (std.ascii.isAlphanumeric(ch) or ch == '_') {
                self.advance();
            } else {
                break;
            }
        }
        const lexeme = self.source[start..self.pos];
        const tt = TokenType.keyword(lexeme) orelse .identifier;
        self.addToken(tt, lexeme, self.line, start_col) catch {};
    }

    // =========================================================================
    // 연산자 / 구두점 스캐닝
    // =========================================================================

    fn scanOperator(self: *Lexer) LexerError!void {
        const c = self.source[self.pos];
        const start_line = self.line;
        const start_col = self.column;
        const start = self.pos;

        switch (c) {
            '+' => {
                self.advance();
                try self.addToken(.plus, self.source[start..self.pos], start_line, start_col);
            },
            '*' => {
                self.advance();
                try self.addToken(.star, self.source[start..self.pos], start_line, start_col);
            },
            '%' => {
                self.advance();
                try self.addToken(.percent, self.source[start..self.pos], start_line, start_col);
            },
            '^' => {
                self.advance();
                try self.addToken(.caret, self.source[start..self.pos], start_line, start_col);
            },
            '&' => {
                self.advance();
                try self.addToken(.ampersand, self.source[start..self.pos], start_line, start_col);
            },
            '|' => {
                self.advance();
                try self.addToken(.pipe, self.source[start..self.pos], start_line, start_col);
            },
            '#' => {
                self.advance();
                try self.addToken(.hash, self.source[start..self.pos], start_line, start_col);
            },
            '(' => {
                self.advance();
                try self.addToken(.left_paren, self.source[start..self.pos], start_line, start_col);
            },
            ')' => {
                self.advance();
                try self.addToken(.right_paren, self.source[start..self.pos], start_line, start_col);
            },
            '{' => {
                self.advance();
                try self.addToken(.left_brace, self.source[start..self.pos], start_line, start_col);
            },
            '}' => {
                self.advance();
                try self.addToken(.right_brace, self.source[start..self.pos], start_line, start_col);
            },
            '[' => {
                self.advance();
                try self.addToken(.left_bracket, self.source[start..self.pos], start_line, start_col);
            },
            ']' => {
                self.advance();
                try self.addToken(.right_bracket, self.source[start..self.pos], start_line, start_col);
            },
            ';' => {
                self.advance();
                try self.addToken(.semicolon, self.source[start..self.pos], start_line, start_col);
            },
            ',' => {
                self.advance();
                try self.addToken(.comma, self.source[start..self.pos], start_line, start_col);
            },

            // `-` : 단독 minus
            '-' => {
                self.advance();
                try self.addToken(.minus, self.source[start..self.pos], start_line, start_col);
            },

            // `/` vs `//`
            '/' => {
                self.advance();
                if (self.peek() == '/') {
                    self.advance();
                    try self.addToken(.slash_slash, self.source[start..self.pos], start_line, start_col);
                } else {
                    try self.addToken(.slash, self.source[start..self.pos], start_line, start_col);
                }
            },

            // `=` vs `==`
            '=' => {
                self.advance();
                if (self.peek() == '=') {
                    self.advance();
                    try self.addToken(.equal_equal, self.source[start..self.pos], start_line, start_col);
                } else {
                    try self.addToken(.equal, self.source[start..self.pos], start_line, start_col);
                }
            },

            // `~` vs `~=`
            '~' => {
                self.advance();
                if (self.peek() == '=') {
                    self.advance();
                    try self.addToken(.tilde_equal, self.source[start..self.pos], start_line, start_col);
                } else {
                    try self.addToken(.tilde, self.source[start..self.pos], start_line, start_col);
                }
            },

            // `<` vs `<=` vs `<<`
            '<' => {
                self.advance();
                if (self.peek() == '=') {
                    self.advance();
                    try self.addToken(.less_equal, self.source[start..self.pos], start_line, start_col);
                } else if (self.peek() == '<') {
                    self.advance();
                    try self.addToken(.less_less, self.source[start..self.pos], start_line, start_col);
                } else {
                    try self.addToken(.less, self.source[start..self.pos], start_line, start_col);
                }
            },

            // `>` vs `>=` vs `>>`
            '>' => {
                self.advance();
                if (self.peek() == '=') {
                    self.advance();
                    try self.addToken(.greater_equal, self.source[start..self.pos], start_line, start_col);
                } else if (self.peek() == '>') {
                    self.advance();
                    try self.addToken(.greater_greater, self.source[start..self.pos], start_line, start_col);
                } else {
                    try self.addToken(.greater, self.source[start..self.pos], start_line, start_col);
                }
            },

            // `.` vs `..` vs `...`
            '.' => {
                self.advance();
                if (self.peek() == '.') {
                    self.advance();
                    if (self.peek() == '.') {
                        self.advance();
                        try self.addToken(.dot_dot_dot, self.source[start..self.pos], start_line, start_col);
                    } else {
                        try self.addToken(.dot_dot, self.source[start..self.pos], start_line, start_col);
                    }
                } else {
                    try self.addToken(.dot, self.source[start..self.pos], start_line, start_col);
                }
            },

            // `:` vs `::`
            ':' => {
                self.advance();
                if (self.peek() == ':') {
                    self.advance();
                    try self.addToken(.colon_colon, self.source[start..self.pos], start_line, start_col);
                } else {
                    try self.addToken(.colon, self.source[start..self.pos], start_line, start_col);
                }
            },

            else => return error.UnexpectedCharacter,
        }
    }

    // =========================================================================
    // 숫자 스캐닝 (Session 3에서 구현)
    // =========================================================================

    fn scanNumber(self: *Lexer) LexerError!void {
        const start = self.pos;
        const start_col = self.column;
        var is_float = false;

        // 16진수
        if (self.source[self.pos] == '0' and self.pos + 1 < self.source.len and
            (self.source[self.pos + 1] == 'x' or self.source[self.pos + 1] == 'X'))
        {
            self.advance(); // '0'
            self.advance(); // 'x'/'X'
            while (self.pos < self.source.len and isHexDigit(self.source[self.pos])) {
                self.advance();
            }
        } else {
            // 10진수 정수부
            if (self.source[self.pos] == '.') {
                // .5 같은 경우
                is_float = true;
            } else {
                while (self.pos < self.source.len and std.ascii.isDigit(self.source[self.pos])) {
                    self.advance();
                }
            }

            // 소수점
            if (self.pos < self.source.len and self.source[self.pos] == '.') {
                // ..은 dot_dot 연산자이므로 소수점이 아님
                if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '.') {
                    // 숫자 뒤에 ..이 오는 경우 — 숫자까지만 처리
                } else {
                    is_float = true;
                    self.advance(); // '.'
                    while (self.pos < self.source.len and std.ascii.isDigit(self.source[self.pos])) {
                        self.advance();
                    }
                }
            }

            // 지수부 e/E
            if (self.pos < self.source.len and (self.source[self.pos] == 'e' or self.source[self.pos] == 'E')) {
                is_float = true;
                self.advance(); // 'e'/'E'
                if (self.pos < self.source.len and (self.source[self.pos] == '+' or self.source[self.pos] == '-')) {
                    self.advance(); // 부호
                }
                while (self.pos < self.source.len and std.ascii.isDigit(self.source[self.pos])) {
                    self.advance();
                }
            }
        }

        const lexeme = self.source[start..self.pos];
        const tt: TokenType = if (is_float) .float else .integer;
        try self.addToken(tt, lexeme, self.line, start_col);
    }

    fn isHexDigit(c: u8) bool {
        return std.ascii.isDigit(c) or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
    }

    // =========================================================================
    // 문자열 스캐닝 (Session 3에서 구현)
    // =========================================================================

    fn scanString(self: *Lexer) LexerError!void {
        const start = self.pos;
        const start_col = self.column;
        const quote = self.source[self.pos];
        self.advance(); // 여는 따옴표

        const content_start = self.pos;
        while (self.pos < self.source.len and self.source[self.pos] != quote) {
            if (self.source[self.pos] == '\\') {
                self.advance(); // 백슬래시
                if (self.pos < self.source.len) {
                    self.advance(); // 이스케이프 문자
                }
            } else if (self.source[self.pos] == '\n') {
                return error.UnterminatedString;
            } else {
                self.advance();
            }
        }

        if (self.pos >= self.source.len) {
            return error.UnterminatedString;
        }

        const content_end = self.pos;
        _ = content_start;
        _ = content_end;

        self.advance(); // 닫는 따옴표

        // lexeme은 따옴표 포함 전체
        const lexeme = self.source[start..self.pos];
        try self.addToken(.string, lexeme, self.line, start_col);
    }

    // =========================================================================
    // 롱 브래킷 문자열 스캐닝
    // =========================================================================

    /// 롱 브래킷 레벨 감지. `[==[` 형태에서 `=` 수를 반환. 롱 브래킷이 아니면 null.
    fn detectLongBracketLevel(self: *const Lexer) ?usize {
        if (self.pos >= self.source.len or self.source[self.pos] != '[') return null;
        var p = self.pos + 1;
        var level: usize = 0;
        while (p < self.source.len and self.source[p] == '=') {
            level += 1;
            p += 1;
        }
        if (p < self.source.len and self.source[p] == '[') {
            return level;
        }
        return null;
    }

    fn scanLongString(self: *Lexer) LexerError!void {
        const start = self.pos;
        const start_line = self.line;
        const start_col = self.column;
        const level = self.detectLongBracketLevel() orelse return error.UnterminatedLongBracket;

        // 여는 브래킷 스킵: [==[ (2 + level 글자)
        var skip: usize = 0;
        while (skip < 2 + level) : (skip += 1) {
            self.advance();
        }

        // 닫는 브래킷 찾기: ]==]
        while (self.pos < self.source.len) {
            if (self.source[self.pos] == '\n') {
                self.line += 1;
                self.column = 0; // advance에서 +1 되므로 0으로
            }
            if (self.source[self.pos] == ']') {
                // 닫는 브래킷 확인
                if (self.matchClosingLongBracket(level)) {
                    // 닫는 브래킷 스킵: ]==] (2 + level 글자)
                    var close_skip: usize = 0;
                    while (close_skip < 2 + level) : (close_skip += 1) {
                        self.advance();
                    }
                    const lexeme = self.source[start..self.pos];
                    try self.addToken(.string, lexeme, start_line, start_col);
                    return;
                }
            }
            self.advance();
        }

        return error.UnterminatedLongBracket;
    }

    fn matchClosingLongBracket(self: *const Lexer, level: usize) bool {
        var p = self.pos;
        if (p >= self.source.len or self.source[p] != ']') return false;
        p += 1;
        var count: usize = 0;
        while (count < level) : (count += 1) {
            if (p >= self.source.len or self.source[p] != '=') return false;
            p += 1;
        }
        if (p >= self.source.len or self.source[p] != ']') return false;
        return true;
    }

    // =========================================================================
    // 주석 스킵
    // =========================================================================

    fn skipComment(self: *Lexer) LexerError!void {
        // '--' 이미 확인됨. 스킵.
        self.advance(); // '-'
        self.advance(); // '-'

        // 멀티라인 주석 체크: --[[ 또는 --[=[
        if (self.detectLongBracketLevel()) |level| {
            // 여는 브래킷 스킵
            var skip: usize = 0;
            while (skip < 2 + level) : (skip += 1) {
                self.advance();
            }
            // 닫는 브래킷 찾기
            while (self.pos < self.source.len) {
                if (self.source[self.pos] == '\n') {
                    self.line += 1;
                    self.column = 0;
                }
                if (self.source[self.pos] == ']' and self.matchClosingLongBracket(level)) {
                    var close_skip: usize = 0;
                    while (close_skip < 2 + level) : (close_skip += 1) {
                        self.advance();
                    }
                    return;
                }
                self.advance();
            }
            // 파일 끝까지 도달 — 멀티라인 주석 미종료도 OK (Lua 스펙)
            return;
        }

        // 싱글라인 주석: 줄 끝까지 스킵
        while (self.pos < self.source.len and self.source[self.pos] != '\n') {
            self.advance();
        }
    }
};

// =============================================================================
// Tests — Session 2: Lexer 코어
// =============================================================================

test "T2-1: 빈 입력 → [eof]" {
    var lexer = Lexer.init(std.testing.allocator, "");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    try std.testing.expectEqual(1, tokens.len);
    try std.testing.expectEqual(TokenType.eof, tokens[0].type);
}

test "T2-2: 기본 키워드+식별자 — local x = y" {
    var lexer = Lexer.init(std.testing.allocator, "local x = y");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    try std.testing.expectEqual(5, tokens.len);
    try std.testing.expectEqual(TokenType.kw_local, tokens[0].type);
    try std.testing.expectEqual(TokenType.identifier, tokens[1].type);
    try std.testing.expectEqualStrings("x", tokens[1].lexeme);
    try std.testing.expectEqual(TokenType.equal, tokens[2].type);
    try std.testing.expectEqual(TokenType.identifier, tokens[3].type);
    try std.testing.expectEqualStrings("y", tokens[3].lexeme);
    try std.testing.expectEqual(TokenType.eof, tokens[4].type);
}

test "T2-3: 모든 키워드 21개 검증" {
    const input = "and break do else elseif end false for function if in local nil not or repeat return then true until while";
    var lexer = Lexer.init(std.testing.allocator, input);
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    const expected = [_]TokenType{
        .kw_and,    .kw_break,  .kw_do,       .kw_else,   .kw_elseif, .kw_end,    .kw_false,
        .kw_for,    .kw_function, .kw_if,     .kw_in,     .kw_local,  .kw_nil,    .kw_not,
        .kw_or,     .kw_repeat, .kw_return,   .kw_then,   .kw_true,   .kw_until,  .kw_while,
        .eof,
    };
    try std.testing.expectEqual(expected.len, tokens.len);
    for (expected, 0..) |exp, i| {
        try std.testing.expectEqual(exp, tokens[i].type);
    }
}

test "T2-4: 1글자 연산자" {
    const input = "+ - * % ^ # ( ) { } [ ] ; , :";
    var lexer = Lexer.init(std.testing.allocator, input);
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    const expected = [_]TokenType{
        .plus, .minus, .star, .percent, .caret, .hash,
        .left_paren, .right_paren, .left_brace, .right_brace,
        .left_bracket, .right_bracket, .semicolon, .comma, .colon,
        .eof,
    };
    try std.testing.expectEqual(expected.len, tokens.len);
    for (expected, 0..) |exp, i| {
        try std.testing.expectEqual(exp, tokens[i].type);
    }
}

test "T2-5: 2~3글자 연산자" {
    const input = "// == ~= <= >= << >> .. :: ...";
    var lexer = Lexer.init(std.testing.allocator, input);
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    const expected = [_]TokenType{
        .slash_slash, .equal_equal, .tilde_equal, .less_equal, .greater_equal,
        .less_less, .greater_greater, .dot_dot, .colon_colon, .dot_dot_dot,
        .eof,
    };
    try std.testing.expectEqual(expected.len, tokens.len);
    for (expected, 0..) |exp, i| {
        try std.testing.expectEqual(exp, tokens[i].type);
    }
}

test "T2-6: 구분자 혼합 — 공백 없이도 올바르게 분리" {
    const input = "a//b&c<<2";
    var lexer = Lexer.init(std.testing.allocator, input);
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    const expected = [_]TokenType{
        .identifier, .slash_slash, .identifier, .ampersand, .identifier, .less_less, .integer, .eof,
    };
    try std.testing.expectEqual(expected.len, tokens.len);
    for (expected, 0..) |exp, i| {
        try std.testing.expectEqual(exp, tokens[i].type);
    }
}

test "T2-7: 위치 추적 — line/column" {
    const input = "a\nb\nc";
    var lexer = Lexer.init(std.testing.allocator, input);
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    try std.testing.expectEqual(4, tokens.len); // a, b, c, eof
    try std.testing.expectEqual(1, tokens[0].line);
    try std.testing.expectEqual(1, tokens[0].column);
    try std.testing.expectEqual(2, tokens[1].line);
    try std.testing.expectEqual(1, tokens[1].column);
    try std.testing.expectEqual(3, tokens[2].line);
    try std.testing.expectEqual(1, tokens[2].column);
}

test "T2-8: 에러 — 인식 불가 문자" {
    var lexer = Lexer.init(std.testing.allocator, "x = @");
    defer lexer.deinit();
    const result = lexer.tokenize();
    try std.testing.expectError(error.UnexpectedCharacter, result);
}

test "T2-9: 공백 무시" {
    const input = "  \t  x  \t  ";
    var lexer = Lexer.init(std.testing.allocator, input);
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    try std.testing.expectEqual(2, tokens.len);
    try std.testing.expectEqual(TokenType.identifier, tokens[0].type);
    try std.testing.expectEqualStrings("x", tokens[0].lexeme);
    try std.testing.expectEqual(TokenType.eof, tokens[1].type);
}

test "T2-10: 메모리 누수 검증" {
    // std.testing.allocator가 자동으로 누수 탐지
    var lexer = Lexer.init(std.testing.allocator, "local x = y + z * w // q");
    defer lexer.deinit();
    _ = try lexer.tokenize();
}

// =============================================================================
// Tests — Session 3: Lexer 고급 (숫자, 문자열, 주석)
// =============================================================================

test "T3-1: 10진 정수" {
    var lexer = Lexer.init(std.testing.allocator, "42 0 100");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    try std.testing.expectEqual(4, tokens.len);
    try std.testing.expectEqual(TokenType.integer, tokens[0].type);
    try std.testing.expectEqualStrings("42", tokens[0].lexeme);
    try std.testing.expectEqual(TokenType.integer, tokens[1].type);
    try std.testing.expectEqualStrings("0", tokens[1].lexeme);
    try std.testing.expectEqual(TokenType.integer, tokens[2].type);
    try std.testing.expectEqualStrings("100", tokens[2].lexeme);
}

test "T3-2: 10진 실수" {
    var lexer = Lexer.init(std.testing.allocator, "3.14 .5 1e5 1.5e-3");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    try std.testing.expectEqual(5, tokens.len);
    for (0..4) |i| {
        try std.testing.expectEqual(TokenType.float, tokens[i].type);
    }
    try std.testing.expectEqualStrings("3.14", tokens[0].lexeme);
    try std.testing.expectEqualStrings(".5", tokens[1].lexeme);
    try std.testing.expectEqualStrings("1e5", tokens[2].lexeme);
    try std.testing.expectEqualStrings("1.5e-3", tokens[3].lexeme);
}

test "T3-3: 16진 정수" {
    var lexer = Lexer.init(std.testing.allocator, "0xFF 0X10 0xDEAD");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    try std.testing.expectEqual(4, tokens.len);
    for (0..3) |i| {
        try std.testing.expectEqual(TokenType.integer, tokens[i].type);
    }
    try std.testing.expectEqualStrings("0xFF", tokens[0].lexeme);
    try std.testing.expectEqualStrings("0X10", tokens[1].lexeme);
    try std.testing.expectEqualStrings("0xDEAD", tokens[2].lexeme);
}

test "T3-4: 숫자 타입 판별 — integer와 float 구분" {
    var lexer = Lexer.init(std.testing.allocator, "42 3.14 0xFF 1e5");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    try std.testing.expectEqual(TokenType.integer, tokens[0].type);
    try std.testing.expectEqual(TokenType.float, tokens[1].type);
    try std.testing.expectEqual(TokenType.integer, tokens[2].type);
    try std.testing.expectEqual(TokenType.float, tokens[3].type);
}

test "T3-5: 쌍따옴표 문자열" {
    var lexer = Lexer.init(std.testing.allocator, "\"hello\" \"a\\nb\"");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    try std.testing.expectEqual(3, tokens.len);
    try std.testing.expectEqual(TokenType.string, tokens[0].type);
    try std.testing.expectEqualStrings("\"hello\"", tokens[0].lexeme);
    try std.testing.expectEqual(TokenType.string, tokens[1].type);
    try std.testing.expectEqualStrings("\"a\\nb\"", tokens[1].lexeme);
}

test "T3-6: 홑따옴표 문자열" {
    var lexer = Lexer.init(std.testing.allocator, "'world' 'it\\'s'");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    try std.testing.expectEqual(3, tokens.len);
    try std.testing.expectEqual(TokenType.string, tokens[0].type);
    try std.testing.expectEqualStrings("'world'", tokens[0].lexeme);
    try std.testing.expectEqual(TokenType.string, tokens[1].type);
}

test "T3-7: 롱 브래킷 문자열" {
    var lexer = Lexer.init(std.testing.allocator, "[[long\nstring]]");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    try std.testing.expectEqual(2, tokens.len);
    try std.testing.expectEqual(TokenType.string, tokens[0].type);
    try std.testing.expectEqualStrings("[[long\nstring]]", tokens[0].lexeme);
}

test "T3-8: 레벨 매칭 롱 브래킷" {
    var lexer = Lexer.init(std.testing.allocator, "[=[contains [[brackets]]]=]");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    try std.testing.expectEqual(2, tokens.len);
    try std.testing.expectEqual(TokenType.string, tokens[0].type);
    try std.testing.expectEqualStrings("[=[contains [[brackets]]]=]", tokens[0].lexeme);
}

test "T3-9: 싱글라인 주석 무시" {
    var lexer = Lexer.init(std.testing.allocator, "x = 1 -- comment\ny = 2");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    // x = 1 y = 2 eof
    try std.testing.expectEqual(7, tokens.len);
    try std.testing.expectEqual(TokenType.identifier, tokens[0].type);
    try std.testing.expectEqual(TokenType.equal, tokens[1].type);
    try std.testing.expectEqual(TokenType.integer, tokens[2].type);
    try std.testing.expectEqual(TokenType.identifier, tokens[3].type);
    try std.testing.expectEqualStrings("y", tokens[3].lexeme);
}

test "T3-10: 멀티라인 주석 무시" {
    var lexer = Lexer.init(std.testing.allocator, "--[[ block comment ]] x = 1");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    try std.testing.expectEqual(4, tokens.len);
    try std.testing.expectEqual(TokenType.identifier, tokens[0].type);
    try std.testing.expectEqualStrings("x", tokens[0].lexeme);
}

test "T3-11: 미종료 문자열 에러" {
    var lexer = Lexer.init(std.testing.allocator, "\"unterminated");
    defer lexer.deinit();
    const result = lexer.tokenize();
    try std.testing.expectError(error.UnterminatedString, result);
}

test "T3-12: 통합 — 복합 입력" {
    var lexer = Lexer.init(std.testing.allocator, "local x = 42 + 3.14 -- sum\nprint(x)");
    defer lexer.deinit();
    const tokens = try lexer.tokenize();
    const expected = [_]TokenType{
        .kw_local, .identifier, .equal, .integer, .plus, .float,
        .identifier, .left_paren, .identifier, .right_paren,
        .eof,
    };
    try std.testing.expectEqual(expected.len, tokens.len);
    for (expected, 0..) |exp, i| {
        try std.testing.expectEqual(exp, tokens[i].type);
    }
}

test "T3-13: 문자열 포함 복잡 입력 메모리 누수 검증" {
    var lexer = Lexer.init(std.testing.allocator, "local s = \"hello\" .. 'world' .. [[long]]");
    defer lexer.deinit();
    _ = try lexer.tokenize();
}
