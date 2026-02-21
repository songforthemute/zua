# Session 04 — Value + AST + Parser 표현식

## 목표
- Lua 동적 타입(`Value`) 확정
- AST 표현식 노드 설계 및 메모리 해제 전략 구현
- Pratt parser 기반 표현식 파싱 완성

## 진입 조건
- Session 03 완료 (Lexer 완성)

## 산출물
- `src/value.zig`
- `src/ast.zig`
- `src/parser.zig`

## 구현 범위
- `value.zig`:
  - `Value = union(enum){ nil, boolean, integer, float, string }`
  - `isTruthy()`, `eql()`, `format()`
- `ast.zig`:
  - `Expr`: literal, identifier, unary, binary, call
  - `Stmt`: Session 5 확장을 위한 스텁
  - 재귀 `deinit` 지원
- `parser.zig`:
  - `parseExpression(min_precedence)`
  - prefix: literal/identifier/paren/unary
  - infix: 12단계 우선순위
  - 우결합 처리(`..`, `^`)
  - 함수 호출 파싱(`identifier(args...)`)

## TDD (RED → GREEN → REFACTOR)
- T4-1: Value 생성 검증
- T4-2: truthiness 검증 (nil/false만 falsy)
- T4-3: equality 검증
- T4-4: 리터럴 파싱
- T4-5: 단항 연산 파싱
- T4-6: 이항 산술 파싱
- T4-7: 우선순위 파싱 (`1 + 2 * 3`)
- T4-8: 괄호 파싱
- T4-9: `..` 우결합
- T4-10: `^` 우결합
- T4-11: 복합 논리식 파싱
- T4-12: 함수 호출 파싱
- T4-13: AST deinit 누수 없음

## 퇴장 조건
1. `zig build test` 성공 (누적 40 passed 목표)
2. 12단계 우선순위/결합성 일치
3. 함수 호출 인자 표현식 파싱 정상
4. 깊은 중첩 AST deinit 누수 없음
