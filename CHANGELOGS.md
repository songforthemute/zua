# Changelog

All notable changes to this project are documented in this file.

## [0.1.0] - 2026-02-21

### Added
- Pure Zig (`0.15.x`) project bootstrap with build and test pipeline.
- Full source pipeline skeleton and implementation:
  - Lexer (`src/lexer.zig`)
  - Parser (`src/parser.zig`)
  - AST (`src/ast.zig`)
  - Value model (`src/value.zig`)
  - Bytecode opcodes/chunk (`src/opcode.zig`)
  - Compiler (`src/compiler.zig`)
  - VM runtime (`src/vm.zig`)
  - Disassembler (`src/debug.zig`)
  - CLI entrypoint (`src/main.zig`)
- Token system for Lua 5.4 MVP surface (`src/token.zig`).
- Technical PRD and session docs:
  - `docs/PRD.md`
  - `docs/sessions/session-01-bootstrap.md` ~ `docs/sessions/session-08-integration.md`

### Implemented (MVP Scope)
- Arithmetic and comparison execution with integer/float handling.
- Local/global assignment and lookup.
- Control flow:
  - `if / elseif / else`
  - `while`
  - numeric `for`
  - `repeat ... until`
  - `break`
- Built-in `print(...)`.
- String concatenation (`..`) and length (`#`) at VM level.
- End-to-end execution path (`source -> lexer -> parser -> compiler -> vm`).

### Testing
- Unit/integration tests across lexer, parser, compiler, VM, and debug modules.
- `zig build test` passing at this stage.
- Memory safety checks integrated through `std.testing.allocator` in test suites.

### Known Limits (Current Stage)
- No table/metatable/coroutine/closure runtime yet.
- General function definition/call semantics are not fully implemented.
- Runtime error reporting is currently minimal at CLI surface.
- REPL state is evaluated per line (no persistent global state across lines).

