# Zua

Pure Zig Lua 5.4 VM/Runtime (MVP) implementation.

Current version: **0.1.0**

---

## 한국어

### 개요
Zua는 Lua 5.4를 C 의존성 없이 Zig로 재구현하는 프로젝트입니다.  
현재 버전(`0.1.0`)은 MVP 단계로, `Lexer -> Parser -> Compiler -> VM` 파이프라인을 중심으로 동작합니다.

### 현재 구현 범위 (v0.1.0)
- 토큰화: 키워드, 식별자, 숫자, 문자열, 연산자, 주석
- 파싱: 표현식 우선순위/결합성, 문장 파싱(`local`, 할당, `if/while/for/repeat`, `break`, `return`)
- 컴파일: AST -> 바이트코드(스택 기반)
- 실행: 산술/비교/비트 연산, local/global 변수, 제어 흐름
- 내장 함수: `print(...)`
- CLI: 파일 실행 모드 + REPL 모드

### 현재 제한 사항 (v0.1.0)
- `table`, `metatable`, `closure`, `coroutine`, `userdata`, `thread` 미구현
- 일반 함수 정의/호출 의미론 미완성 (`print` 중심)
- REPL은 라인 단위 평가 방식(상태 유지 제한)
- 런타임 에러 진단 메시지 최소 수준

### 요구 사항
- Zig `0.15.x` (프로젝트 최소 버전: `0.15.0`)

### 빠른 시작

```bash
# build
zig build

# test
zig build test

# run (REPL)
zig build run

# run (file)
zig build run -- path/to/script.lua
```

### 예시

```lua
local sum = 0
for i = 1, 100 do
  sum = sum + i
end
print(sum)
```

Expected output:

```text
5050
```

### 문서
- Technical PRD: `docs/PRD.md`
- Session plans:
  - `docs/sessions/session-01-bootstrap.md`
  - `docs/sessions/session-02-lexer-core.md`
  - `docs/sessions/session-03-lexer-advanced.md`
  - `docs/sessions/session-04-parser-expr.md`
  - `docs/sessions/session-05-parser-stmt.md`
  - `docs/sessions/session-06-compiler-expr.md`
  - `docs/sessions/session-07-compiler-vm.md`
  - `docs/sessions/session-08-integration.md`
- Changelog: `CHANGELOGS.md`

---

## English

### Overview
Zua is a project to re-implement Lua 5.4 in pure Zig with zero C dependency.  
Current version (`0.1.0`) is an MVP focused on the `Lexer -> Parser -> Compiler -> VM` pipeline.

### Implemented Scope (v0.1.0)
- Lexing: keywords, identifiers, numbers, strings, operators, comments
- Parsing: expression precedence/associativity and statements (`local`, assignment, `if/while/for/repeat`, `break`, `return`)
- Compilation: AST -> stack-based bytecode
- Runtime: arithmetic/comparison/bitwise ops, local/global variables, control flow
- Built-in function: `print(...)`
- CLI: file execution mode + REPL mode

### Current Limits (v0.1.0)
- `table`, `metatable`, `closure`, `coroutine`, `userdata`, and `thread` are not implemented yet
- General function definition/call semantics are incomplete (currently centered on `print`)
- REPL currently evaluates line by line (limited state persistence)
- Runtime error diagnostics are still minimal

### Requirements
- Zig `0.15.x` (project minimum: `0.15.0`)

### Quick Start

```bash
# build
zig build

# test
zig build test

# run (REPL)
zig build run

# run (file)
zig build run -- path/to/script.lua
```

### Example

```lua
local sum = 0
for i = 1, 100 do
  sum = sum + i
end
print(sum)
```

Expected output:

```text
5050
```

### Documentation
- Technical PRD: `docs/PRD.md`
- Session plans:
  - `docs/sessions/session-01-bootstrap.md`
  - `docs/sessions/session-02-lexer-core.md`
  - `docs/sessions/session-03-lexer-advanced.md`
  - `docs/sessions/session-04-parser-expr.md`
  - `docs/sessions/session-05-parser-stmt.md`
  - `docs/sessions/session-06-compiler-expr.md`
  - `docs/sessions/session-07-compiler-vm.md`
  - `docs/sessions/session-08-integration.md`
- Changelog: `CHANGELOGS.md`

### License
MIT-style license text is available in `LICENSE`.

