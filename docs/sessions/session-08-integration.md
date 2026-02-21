# Session 08 — VM 제어흐름 + 통합 + CLI

## 목표
- 제어 흐름 opcode 실행 완성
- 내장 `print()` 구현
- `main.zig`에서 파일 실행 + REPL 통합
- Phase 3 및 MVP 완료

## 진입 조건
- Session 07 완료 (VM core 동작)

## 산출물
- `src/vm.zig` (jump/loop/print/concat/len/런타임 에러)
- `src/main.zig` (interpret 파이프라인, file mode, REPL mode)

## 구현 범위
- `vm.zig` 확장:
  - `op_jump`, `op_jump_if_false`, `op_jump_if_true`, `op_loop`
  - `op_print` (`print(1,2,3)` 탭 구분 출력)
  - `op_concat`, `op_len`
  - 타입 불일치 런타임 에러 + 라인 정보
- `main.zig`:
  - `interpret(source)` = Lexer → Parser → Compiler → VM
  - `zua script.lua` 파일 실행
  - `zua` REPL 실행

## TDD (RED → GREEN → REFACTOR)
- T8-1: if true 분기
- T8-2: if false 분기
- T8-3: if/elseif
- T8-4: while 루프
- T8-5: for loop
- T8-6: for loop(step)
- T8-7: repeat-until
- T8-8: 중첩 루프
- T8-9: break
- T8-10: print 단일 인자 stdout
- T8-11: print 다중 인자 stdout
- T8-12: 문자열 연결
- T8-13: 런타임 타입 에러
- T8-14: 통합 가우스 합
- T8-15: 통합 FizzBuzz
- T8-16: 전체 파이프라인 누수 없음

## 퇴장 조건
1. `zig build test` 성공 (누적 97 passed 목표)
2. 제어문 전체(if/while/for/repeat/break) 동작
3. `print()` 동작 및 출력 포맷 일치
4. 문자열 연결 동작
5. 통합 파이프라인 실행 성공
6. REPL 및 파일 실행 모드 동작
7. MVP 완료 기준 충족
