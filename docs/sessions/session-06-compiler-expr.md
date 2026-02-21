# Session 06 — Opcode + Compiler 표현식

## 목표
- 바이트코드 명령어 집합과 Chunk 구조 정의
- 표현식 AST를 바이트코드로 컴파일
- 디스어셈블러 기반 가시성 확보

## 진입 조건
- Session 05 완료 (Parser 완성)

## 산출물
- `src/opcode.zig`
- `src/compiler.zig`
- `src/debug.zig`

## 구현 범위
- `opcode.zig`:
  - `OpCode enum(u8)` 정의
  - `Chunk` (`code`, `constants`, `lines`) 및 init/deinit/write/addConstant
- `compiler.zig`:
  - `compileExpr()` 재귀 구현
  - literal → `push_*` 또는 `push_constant`
  - unary/binary → 피연산자 컴파일 후 opcode emit
  - 상수 풀 관리
- `debug.zig`:
  - `disassemble(chunk)`
  - 사람이 읽을 수 있는 `OP_*` 포맷 출력

## TDD (RED → GREEN → REFACTOR)
- T6-1: Chunk 생성/해제
- T6-2: 상수 풀 인덱스 검증
- T6-3: 정수 리터럴 컴파일
- T6-4: bool 리터럴 컴파일
- T6-5: nil 컴파일
- T6-6: `1 + 2` 컴파일
- T6-7: `1 + 2 * 3` postfix 컴파일
- T6-8: `-42` 컴파일
- T6-9: 비교 연산 컴파일
- T6-10: 비트 연산 컴파일
- T6-11: 문자열 연결 컴파일
- T6-12: 컴파일 결과 deinit 누수 없음
- T6-13: 디스어셈블 출력 형식 검증

## 퇴장 조건
1. `zig build test` 성공 (누적 68 passed 목표)
2. 표현식 컴파일이 postfix 순서로 정확
3. 상수 풀 인덱싱 정상
4. 디스어셈블러 출력 가독성 확보
5. Chunk/Compiler 메모리 누수 없음
