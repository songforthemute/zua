# Session 02 — Lexer 코어 (식별자/키워드/연산자/구두점)

## 목표
- 숫자/문자열/주석 제외한 Lexer 핵심 스캔 루프 완성
- line/column 추적 + EOF 처리 + 에러 처리 확립

## 진입 조건
- Session 01 완료 (`token.zig`, 빌드/테스트 기반 존재)

## 산출물
- `src/lexer.zig`

## 구현 범위
- `Lexer.init`, `Lexer.deinit`, `Lexer.tokenize`
- 공백/탭/개행 처리, 위치 추적
- 식별자 스캔 + 키워드 판별
- 룩어헤드 기반 다문자 토큰 스캔:
  - 1글자: `+ - * % ^ & | # ( ) { } [ ] ; , : = ~`
  - 2글자: `// == ~= <= >= << >> .. ::`
  - 3글자: `...`
- EOF 자동 추가
- 인식 불가 문자 시 `error.UnexpectedCharacter`

## TDD (RED → GREEN → REFACTOR)
- T2-1: 빈 입력 → `[eof]`
- T2-2: `local x = y` 기본 토큰화
- T2-3: 키워드 21개 전수 매핑
- T2-4: 1글자 연산자 전수 검증
- T2-5: 2~3글자 연산자 전수 검증
- T2-6: 공백 없는 입력 분리(`a//b&c<<2`)
- T2-7: 위치 추적(`a\nb\nc`)
- T2-8: `x = @` 에러 검증
- T2-9: 공백 무시 검증
- T2-10: tokenize/deinit 누수 없음

## 퇴장 조건
1. `zig build test` 성공 (누적 14 passed 목표)
2. 키워드/식별자/연산자 혼합 입력 토큰화 정확
3. 다중 줄 입력의 line/column 정확
4. 에러 경로에서도 누수 없음
