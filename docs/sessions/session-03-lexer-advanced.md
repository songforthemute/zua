# Session 03 — Lexer 고급 (숫자/문자열/주석)

## 목표
- Lexer 기능 완성: 숫자, 문자열, 주석 스캐닝
- Phase 1(Lexer) 완료 기준 충족

## 진입 조건
- Session 02 완료 (`lexer.zig` 코어 동작)

## 산출물
- `src/lexer.zig` (확장)

## 구현 범위
- 숫자 리터럴:
  - decimal integer: `42`, `0`
  - decimal float: `3.14`, `.5`, `1e5`, `1.5e-3`
  - hex integer: `0xFF`, `0X10`
  - float 판별: 소수점/지수 포함 시 float
- 문자열 리터럴:
  - short string: `"..."`, `'...'`
  - 기본 이스케이프: `\n`, `\t`, `\\`, `\"`, `\'`
  - long bracket: `[[...]]`, `[=[...]=]`
- 주석:
  - single line: `-- ...`
  - multi line: `--[[...]]`, `--[=[...]=]`

## Conscious Debt (Session Scope)
- hex float(`0x1.8p3`) 미구현
- 고급 escape(`\xhh`, `\u{...}`, `\ddd`) 미구현

## TDD (RED → GREEN → REFACTOR)
- T3-1: 10진 정수 스캔
- T3-2: 10진 실수 스캔
- T3-3: 16진 정수 스캔
- T3-4: integer/float 타입 판별
- T3-5: 쌍따옴표 문자열 + escape
- T3-6: 홑따옴표 문자열 + escape
- T3-7: long bracket 문자열
- T3-8: level 매칭(`[=[...]=]`)
- T3-9: single-line 주석 스킵
- T3-10: multi-line 주석 스킵
- T3-11: 미종료 문자열 에러(`UnterminatedString`)
- T3-12: 통합 토큰화 시나리오
- T3-13: 누수 없음 검증

## 퇴장 조건
1. `zig build test` 성공 (누적 27 passed 목표)
2. 숫자 타입 구분 정확 (`integer` vs `float`)
3. short/long 문자열 모두 정상
4. single/multi-line 주석 완전 스킵
5. 에러 경로 포함 메모리 누수 없음
6. Phase 1 완료 기준 충족
