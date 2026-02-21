# Session 01 — Bootstrap + Token 타입 정의

## 목표
- Zig 프로젝트 스캐폴딩 구성
- `TokenType`, `Token`, `keyword()` 헬퍼 구현
- `zig build`, `zig build test`, `zig build run` 기준 통과

## 진입 조건
- 저장소는 초기 상태(최소 `LICENSE`) 또는 동등한 상태

## 산출물
- `build.zig`
- `build.zig.zon`
- `src/main.zig`
- `src/token.zig`

## 구현 범위
- 빌드 파이프라인 구성(exe + test)
- `main.zig` 최소 실행 진입점
- `TokenType` enum 정의(리터럴/식별자/키워드/연산자/구두점/eof)
- `Token` struct 정의(`type`, `lexeme`, `line`, `column`)
- `keyword(lexeme)` 매핑(21개 키워드)

## TDD (RED → GREEN → REFACTOR)
- T1-1: `@sizeOf(TokenType) == 1`
- T1-2: `Token` 생성/필드 접근 검증
- T1-3: `keyword()` 매핑 검증 (`"local" -> .kw_local`, `"xyz" -> null`)
- T1-4: 원본 source 슬라이스 참조 무결성 검증

## 퇴장 조건
1. `zig build` 성공
2. `zig build test` 성공 (4 passed, 0 failed 목표)
3. `zig build run` 성공 (exit code 0)
4. 산출물 파일 존재 및 핵심 타입 정의 확인
