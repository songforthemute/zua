# Session 05 — Parser 문장(Statements)

## 목표
- MVP 문장 타입 전체 파싱 완성
- Phase 2(Parser) 완료

## 진입 조건
- Session 04 완료 (표현식 파싱 동작)

## 산출물
- `src/ast.zig` (Stmt variants 확장)
- `src/parser.zig` (statement/block 파서 구현)

## 구현 범위
- `parseBlock()`:
  - 종료 토큰(`end`, `else`, `elseif`, `until`, `eof`)까지 수집
- `parseStatement()` 분기:
  - `local`, `if`, `while`, `for`, `repeat`, `do`, `return`, `break`
  - 할당문 vs 표현식문(함수 호출)
- 문장 파서 상세:
  - `parseLocalAssign`
  - `parseIf`
  - `parseWhile`
  - `parseFor`(numeric)
  - `parseRepeat`
  - `parseDo`
  - `parseReturn`

## TDD (RED → GREEN → REFACTOR)
- T5-1: local 할당
- T5-2: local 다중 할당
- T5-3: 글로벌 할당
- T5-4: if/then/end
- T5-5: if/elseif/else
- T5-6: while
- T5-7: for(step 포함)
- T5-8: for(step 생략)
- T5-9: repeat-until
- T5-10: do-end
- T5-11: return
- T5-12: break
- T5-13: 함수 호출문
- T5-14: 복합 프로그램
- T5-15: 블록 deinit 누수 없음

## 퇴장 조건
1. `zig build test` 성공 (누적 55 passed 목표)
2. 모든 MVP 문장 타입 파싱 성공
3. 중첩 구문(`for` 내부 `if`) 정상
4. AST 메모리 해제 누수 없음
5. Phase 2 완료 기준 충족
