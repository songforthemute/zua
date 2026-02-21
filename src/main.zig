const std = @import("std");
const vm = @import("vm.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len > 1) {
        try runFile(allocator, args[1]);
    } else {
        try repl(allocator);
    }
}

fn runFile(allocator: std.mem.Allocator, path: []const u8) !void {
    const source = std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024) catch {
        std.fs.File.stderr().writeAll("Error: cannot open file\n") catch {};
        std.process.exit(1);
    };
    defer allocator.free(source);

    const output = vm.interpret(allocator, source) catch {
        std.fs.File.stderr().writeAll("Error: execution failed\n") catch {};
        std.process.exit(1);
    };
    defer allocator.free(output);

    std.fs.File.stdout().writeAll(output) catch {};
}

fn repl(allocator: std.mem.Allocator) !void {
    const stdout = std.fs.File.stdout();
    const stdin_file = std.fs.File.stdin();

    stdout.writeAll("Zua 0.1.0 — Lua 5.4 in pure Zig\n") catch {};
    stdout.writeAll("Type Ctrl+D to exit\n") catch {};

    while (true) {
        stdout.writeAll("> ") catch {};

        // stdin에서 한 줄 읽기 (low-level)
        const line = readLine(stdin_file, allocator) catch {
            stdout.writeAll("\nError reading input\n") catch {};
            break;
        };
        if (line == null) {
            stdout.writeAll("\n") catch {};
            break;
        }
        defer allocator.free(line.?);

        if (line.?.len == 0) continue;

        const output = vm.interpret(allocator, line.?) catch {
            std.fs.File.stderr().writeAll("Error: execution failed\n") catch {};
            continue;
        };
        defer allocator.free(output);

        if (output.len > 0) {
            stdout.writeAll(output) catch {};
        }
    }
}

/// stdin에서 한 줄 읽기 (줄바꿈까지, 줄바꿈 제외)
fn readLine(file: std.fs.File, allocator: std.mem.Allocator) !?[]u8 {
    var list = std.ArrayListUnmanaged(u8).empty;
    errdefer list.deinit(allocator);

    while (true) {
        var byte: [1]u8 = undefined;
        const n = file.read(&byte) catch return error.ReadError;
        if (n == 0) {
            // EOF
            if (list.items.len == 0) return null;
            return try list.toOwnedSlice(allocator);
        }
        if (byte[0] == '\n') {
            return try list.toOwnedSlice(allocator);
        }
        try list.append(allocator, byte[0]);
    }
}
