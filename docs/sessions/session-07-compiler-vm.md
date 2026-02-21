# Session 07 — Compiler 문장 + VM 코어

## 목표
- 문장 단위 컴파일(변수/제어 흐름) 구현
- VM 실행 루프에서 산술/변수 동작 완료

## 진입 조건
- Session 06 완료 (표현식 컴파일 동작)

## 산출물
- `src/compiler.zig` (statement compile 확장)
- `src/vm.zig` (VM core)

## 구현 범위
- `compiler.zig` 확장:
  - `compileStmt()` 문장별 바이트코드 생성
  - local/global 변수 읽기/쓰기
  - if/while/for/repeat 점프/루프 패치
  - scope depth 추적, 블록 종료 시 로컬 정리
- `vm.zig`:
  - opcode dispatch 루프
  - stack push/pop
  - 산술 및 타입 승격 규칙 적용
  - 비교/논리 연산
  - local slot / global hashmap 처리

## TDD (RED → GREEN → REFACTOR)
- T7-1: local 변수 컴파일
- T7-2: 변수 참조 컴파일
- T7-3: global 변수 컴파일
- T7-4: if 점프 패치 검증
- T7-5: 수동 바이트코드 add 실행
- T7-6: integer+float 승격
- T7-7: integer `//` integer
- T7-8: `/` float division
- T7-9: 비교 연산
- T7-10: local 할당+참조 실행
- T7-11: global 할당+참조 실행
- T7-12: and/or short-circuit 의미 검증
- T7-13: VM deinit 누수 없음

## 퇴장 조건
1. `zig build test` 성공 (누적 81 passed 목표)
2. local/global 변수 시나리오 동작
3. integer/float 승격 규칙 충족
4. if/loop 점프 패치 정확
5. Compiler-VM 사이클 누수 없음
