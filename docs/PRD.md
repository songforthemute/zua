# Zua — Pure Zig Lua 5.4 VM Technical PRD

## 0. Context
Lua 5.4 인터프리터를 C 의존성 0%로, Zig 0.15.2 기반 100% 순수 Zig 구현으로 재작성한다.

핵심 목표:
- Lexer → Parser → Compiler → VM 4단계 파이프라인을 밑바닥부터 구축
- 단계별 TDD(RED → GREEN → REFACTOR)로 품질 보장
- MVP 범위에서 실행 가능한 Lua 5.4 코어 기능 확보

판단 준거:
- Zig 0.15.2 최신 패턴 준수 (`ArrayListUnmanaged`, `b.path()`)
- Lua 5.4 스펙 기준 준수 (integer/float 이중 숫자 타입, bit 연산자, `//` 정수 나눗셈)
- MVP: 산술 연산, 변수 할당, 제어문(`if/while/for/repeat`), 내장 `print()`

---

## 1. Project Structure

```text
zua/
├── build.zig
├── build.zig.zon
├── src/
│   ├── main.zig
│   ├── token.zig
│   ├── lexer.zig
│   ├── ast.zig
│   ├── parser.zig
│   ├── opcode.zig
│   ├── compiler.zig
│   ├── vm.zig
│   ├── value.zig
│   └── debug.zig
└── LICENSE
```

설계 근거:
- 파이프라인 단계별 파일 분리로 테스트 단위 독립성 확보
- 각 모듈 자체 테스트 블록 보유, `zig build test`로 통합 실행
- 디버그/실행(main) 계층을 별도 분리해 추적성과 유지보수성 확보

---

## 2. Core Type System — `value.zig`

Lua 5.4 동적 타입을 Zig Tagged Union으로 매핑한다.

```zig
pub const Value = union(enum) {
    nil,
    boolean: bool,
    integer: i64,
    float: f64,
    string: []const u8,
};
```

Lua 5.4 숫자 모델 핵심:
- `integer(i64)`와 `float(f64)`를 구분
- 연산 시 타입 승격 규칙 적용

승격/연산 규칙:
- `integer ⊕ integer` → `integer`
- 하나라도 `float` 포함 → `float`
- `/` → 항상 `float`
- `//` → 둘 다 integer면 integer, 아니면 float
- `^` → 항상 float

---

## 3. Phase 1 — Lexer

### 3.1 Token Model (`token.zig`)
- 리터럴: integer, float, string
- 식별자: identifier
- 키워드: Lua 5.4 기준 21개 (`and`, `break`, ..., `while`)
- 연산자:
  - 산술: `+ - * / // % ^`
  - 관계: `== ~= < > <= >=`
  - 비트: `& | ~ << >>`
  - 문자열/기타: `.. #`
- 구두점: `(){}[];,.:= :: ...`
- 특수: `eof`

`Token` 구조:
- `type: TokenType`
- `lexeme: []const u8`
- `line: u32`
- `column: u32`

### 3.2 Lexer Scope (`lexer.zig`)
- 입력 순회 상태: `pos`, `line`, `column`
- 공백/개행/주석 스킵
- 문자열(short/long bracket), 숫자(decimal/hex int), 식별자/키워드 스캔
- 다문자 연산자 룩어헤드 처리 (`//`, `==`, `...`, `::` 등)
- EOF 토큰 자동 부착

### 3.3 Phase 1 TDD Baseline
- 기본 토큰화
- Lua 5.4 연산자(`//`, `&`, `<<`) 검증
- 숫자 리터럴 구분(integer vs float)
- short/long 문자열 파싱
- single/multi-line 주석 무시
- line/column 위치 추적
- 에러 처리(`UnexpectedCharacter`, `UnterminatedString`)
- 빈 입력 처리
- allocator 기반 누수 검증

---

## 4. Phase 2 — Parser

### 4.1 AST Design (`ast.zig`)
`Expr`:
- 리터럴(nil/bool/int/float/string)
- identifier
- unary, binary
- call(callee + args)

`Stmt`:
- `local_assign`, `assign`
- `if_stmt`, `while_stmt`, `for_numeric`, `repeat_stmt`, `do_stmt`
- `return_stmt`, `break_stmt`
- `expr_stmt`

`Block`:
- `[]Stmt`

### 4.2 Parser Strategy (`parser.zig`)
- Recursive Descent + Pratt Parser 혼합
- `parseBlock`, `parseStatement`, `parseExpression`
- 연산자 우선순위 12단계 적용
- 우결합 연산자: `..`, `^`
- 문장 파서 범위:
  - local/global 할당
  - if/elseif/else
  - while
  - numeric for
  - repeat-until
  - do-end
  - return, break
  - 함수 호출문

### 4.3 Parser TDD Baseline
- 산술 우선순위/결합성
- 복합 논리식
- 제어문 구문 트리
- 함수 호출 파싱
- 중첩 블록 파싱
- AST deinit 시 누수 없음

---

## 5. Phase 3 — Compiler + VM

### 5.1 Bytecode Model (`opcode.zig`)
스택 기반 VM 명령어 집합:
- 스택: `push_*`, `pop`
- 산술: `add/sub/mul/div/idiv/mod/pow/negate`
- 비트: `band/bor/bxor/bnot/shl/shr`
- 비교/논리: `eq/ne/lt/le/gt/ge/not`
- 문자열: `concat/len`
- 변수: `get/set_local`, `get/set_global`
- 제어흐름: `jump`, `jump_if_false`, `jump_if_true`, `loop`
- 호출/반환: `call`, `return`
- 내장: `print`

`Chunk`:
- `code: ArrayListUnmanaged(u8)`
- `constants: ArrayListUnmanaged(Value)`
- `lines: ArrayListUnmanaged(u32)`

### 5.2 Compiler (`compiler.zig`)
- AST 순회 기반 바이트코드 생성
- 상수 풀 관리
- 점프 패치 (`emitJump`, `patchJump`)
- 스코프 깊이/로컬 슬롯 추적
- 제어문 컴파일:
  - if/elseif/else
  - while
  - numeric for
  - repeat-until

### 5.3 VM (`vm.zig`)
- 고정 스택(`STACK_MAX`) + `stack_top`
- instruction pointer(`ip`) 기반 dispatch loop
- 타입 승격 포함 산술 실행
- 로컬/글로벌 변수 저장
- 점프/루프 실행
- `print` 내장 함수 실행
- 런타임 타입 에러 보고(라인 정보 포함)

### 5.4 Compiler + VM TDD Baseline
- 수동 바이트코드 실행 검증
- 산술/비교/비트/문자열 연산 검증
- 변수(local/global) 검증
- 제어문(if/while/for/repeat/break) 검증
- `print(42)`, `print(1,2,3)` stdout 검증
- 통합 파이프라인 테스트(가우스 합/FizzBuzz)
- 전체 deinit 누수 없음

---

## 6. Conscious Technical Debt

| 포기 항목 | 지금 감당 가능한 이유 | 회수 시점 |
|---|---|---|
| 메타테이블/코루틴/클로저 | MVP 목적은 코어 파이프라인 안정화 | table 타입 구현 직후 |
| 표준 라이브러리(math/os/string) | `print()`만으로 VM 기능 검증 가능 | Phase 3 통합 테스트 통과 후 |
| generic for (`for k,v in pairs`) | iterator 프로토콜은 function+table 의존 | 함수+테이블 구현 후 |
| `goto/label` | if/while/for로 대부분 제어흐름 커버 | Phase 3 안정화 후 선택 |
| 가변 인자(`...`) | 함수 시스템 MVP 범위 제한 | 함수 시스템 완성 후 |
| WASM 빌드 | 코어 로직 OS 의존 제거 우선 | Phase 3 이후 별도 태스크 |
| hex float (`0x1.8p3`) | 실사용 빈도 낮음 | Lexer 안정화 후 |
| 고급 이스케이프(`\u{}`, `\xhh`, `\ddd`) | 기본 이스케이프로 MVP 검증 가능 | 문자열 처리 고도화 시 |

의식적 부채 기준:
1. 무엇을 포기하는지 명시
2. 지금 감당 가능한 이유 명시
3. 회수 시점 명시

---

## 7. Session Dependency Graph

```text
Session 1 (Bootstrap)
    ↓
Session 2 (Lexer Core)
    ↓
Session 3 (Lexer Advanced)   ← Phase 1 완료
    ↓
Session 4 (Value + AST + Parser Expr)
    ↓
Session 5 (Parser Stmt)      ← Phase 2 완료
    ↓
Session 6 (Opcode + Compiler Expr)
    ↓
Session 7 (Compiler Stmt + VM Core)
    ↓
Session 8 (VM Control Flow + Integration) ← Phase 3/MVP 완료
```

---

## 8. Verification Strategy

| 검증 수단 | 방법 | 시점 |
|---|---|---|
| 단위 테스트 | `zig build test` | 매 세션 퇴장 시 |
| 메모리 안전성 | `std.testing.allocator` 누수 탐지 | 모든 테스트 |
| 통합 테스트 | 소스 → stdout 일치 | Session 8 |
| 수동 실행 검증 | `zig build run` + REPL 점검 | Session 8 |
| 바이트코드 검사 | `debug.disassemble()` 결과 확인 | Session 6 이후 |

정량 완료 기준(MVP):
- 전체 테스트 97개 통과
- 산술/비교/논리/비트/문자열 연산 동작
- local/global 변수 동작
- 제어문(`if/elseif/else`, `while`, numeric `for`, `repeat-until`, `break`) 동작
- `print()` 동작
- 전체 파이프라인 정상 동작
- 메모리 누수 0
- C 의존성 0%

---

## 9. Session Documents Index

세션별 실행 문서는 아래 파일로 분리한다.

- `docs/sessions/session-01-bootstrap.md`
- `docs/sessions/session-02-lexer-core.md`
- `docs/sessions/session-03-lexer-advanced.md`
- `docs/sessions/session-04-parser-expr.md`
- `docs/sessions/session-05-parser-stmt.md`
- `docs/sessions/session-06-compiler-expr.md`
- `docs/sessions/session-07-compiler-vm.md`
- `docs/sessions/session-08-integration.md`

운영 원칙:
- 각 세션 시작 시 해당 세션 문서만 로드해 컨텍스트를 최소화한다.
- 모든 세션은 RED → GREEN → REFACTOR 사이클을 따른다.
- 퇴장 조건(테스트/시나리오)을 통과해야 다음 세션으로 진입한다.
