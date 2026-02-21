const std = @import("std");

pub const TokenType = enum(u8) {
    // --- 리터럴 ---
    integer, // 42, 0xFF
    float, // 3.14, 1e5
    string, // "hello", 'world', [[long]]

    // --- 식별자 ---
    identifier, // 변수명, 함수명

    // --- 키워드 (21개) ---
    kw_and,
    kw_break,
    kw_do,
    kw_else,
    kw_elseif,
    kw_end,
    kw_false,
    kw_for,
    kw_function,
    kw_if,
    kw_in,
    kw_local,
    kw_nil,
    kw_not,
    kw_or,
    kw_repeat,
    kw_return,
    kw_then,
    kw_true,
    kw_until,
    kw_while,

    // --- 산술 연산자 ---
    plus, // +
    minus, // -
    star, // *
    slash, // /
    slash_slash, // // (Lua 5.4 정수 나눗셈)
    percent, // %
    caret, // ^

    // --- 관계 연산자 ---
    equal_equal, // ==
    tilde_equal, // ~=
    less, // <
    greater, // >
    less_equal, // <=
    greater_equal, // >=

    // --- 비트 연산자 (Lua 5.4) ---
    ampersand, // &
    pipe, // |
    tilde, // ~ (단항: NOT, 이항: XOR)
    less_less, // <<
    greater_greater, // >>

    // --- 문자열/기타 연산자 ---
    dot_dot, // .. (문자열 연결)
    hash, // # (길이)

    // --- 구두점 ---
    left_paren, // (
    right_paren, // )
    left_brace, // {
    right_brace, // }
    left_bracket, // [
    right_bracket, // ]
    semicolon, // ;
    comma, // ,
    dot, // .
    colon, // :
    colon_colon, // :: (레이블, MVP 이후)
    equal, // =
    dot_dot_dot, // ... (가변 인자, MVP 이후)

    // --- 특수 ---
    eof,

    /// 키워드 문자열을 TokenType으로 변환. 키워드가 아니면 null 반환.
    pub fn keyword(str: []const u8) ?TokenType {
        const map = std.StaticStringMap(TokenType).initComptime(.{
            .{ "and", .kw_and },
            .{ "break", .kw_break },
            .{ "do", .kw_do },
            .{ "else", .kw_else },
            .{ "elseif", .kw_elseif },
            .{ "end", .kw_end },
            .{ "false", .kw_false },
            .{ "for", .kw_for },
            .{ "function", .kw_function },
            .{ "if", .kw_if },
            .{ "in", .kw_in },
            .{ "local", .kw_local },
            .{ "nil", .kw_nil },
            .{ "not", .kw_not },
            .{ "or", .kw_or },
            .{ "repeat", .kw_repeat },
            .{ "return", .kw_return },
            .{ "then", .kw_then },
            .{ "true", .kw_true },
            .{ "until", .kw_until },
            .{ "while", .kw_while },
        });
        return map.get(str);
    }
};

pub const Token = struct {
    type: TokenType,
    lexeme: []const u8, // 원본 소스의 슬라이스
    line: u32,
    column: u32,
};

// =============================================================================
// Tests
// =============================================================================

test "T1-1: TokenType enum은 u8에 맞는 크기" {
    try std.testing.expectEqual(1, @sizeOf(TokenType));
}

test "T1-2: Token 구조체 생성 및 필드 접근" {
    const source = "local";
    const tok = Token{
        .type = .kw_local,
        .lexeme = source[0..5],
        .line = 1,
        .column = 1,
    };
    try std.testing.expectEqual(TokenType.kw_local, tok.type);
    try std.testing.expectEqualStrings("local", tok.lexeme);
    try std.testing.expectEqual(1, tok.line);
    try std.testing.expectEqual(1, tok.column);
}

test "T1-3: keyword() 헬퍼 — 키워드 매핑 검증" {
    // 모든 21개 키워드 검증
    try std.testing.expectEqual(TokenType.kw_and, TokenType.keyword("and").?);
    try std.testing.expectEqual(TokenType.kw_break, TokenType.keyword("break").?);
    try std.testing.expectEqual(TokenType.kw_do, TokenType.keyword("do").?);
    try std.testing.expectEqual(TokenType.kw_else, TokenType.keyword("else").?);
    try std.testing.expectEqual(TokenType.kw_elseif, TokenType.keyword("elseif").?);
    try std.testing.expectEqual(TokenType.kw_end, TokenType.keyword("end").?);
    try std.testing.expectEqual(TokenType.kw_false, TokenType.keyword("false").?);
    try std.testing.expectEqual(TokenType.kw_for, TokenType.keyword("for").?);
    try std.testing.expectEqual(TokenType.kw_function, TokenType.keyword("function").?);
    try std.testing.expectEqual(TokenType.kw_if, TokenType.keyword("if").?);
    try std.testing.expectEqual(TokenType.kw_in, TokenType.keyword("in").?);
    try std.testing.expectEqual(TokenType.kw_local, TokenType.keyword("local").?);
    try std.testing.expectEqual(TokenType.kw_nil, TokenType.keyword("nil").?);
    try std.testing.expectEqual(TokenType.kw_not, TokenType.keyword("not").?);
    try std.testing.expectEqual(TokenType.kw_or, TokenType.keyword("or").?);
    try std.testing.expectEqual(TokenType.kw_repeat, TokenType.keyword("repeat").?);
    try std.testing.expectEqual(TokenType.kw_return, TokenType.keyword("return").?);
    try std.testing.expectEqual(TokenType.kw_then, TokenType.keyword("then").?);
    try std.testing.expectEqual(TokenType.kw_true, TokenType.keyword("true").?);
    try std.testing.expectEqual(TokenType.kw_until, TokenType.keyword("until").?);
    try std.testing.expectEqual(TokenType.kw_while, TokenType.keyword("while").?);

    // 키워드가 아닌 식별자는 null
    try std.testing.expectEqual(@as(?TokenType, null), TokenType.keyword("xyz"));
    try std.testing.expectEqual(@as(?TokenType, null), TokenType.keyword("Local")); // 대소문자 구분
    try std.testing.expectEqual(@as(?TokenType, null), TokenType.keyword(""));
}

test "T1-4: lexeme 슬라이스 참조 — 원본 소스의 슬라이스 유지" {
    const source = "local x = 42";
    const tok = Token{
        .type = .identifier,
        .lexeme = source[6..7], // "x"
        .line = 1,
        .column = 7,
    };
    try std.testing.expectEqualStrings("x", tok.lexeme);
    // 슬라이스가 원본 소스를 참조하는지 확인 (포인터 비교)
    try std.testing.expectEqual(@intFromPtr(source.ptr + 6), @intFromPtr(tok.lexeme.ptr));
}
