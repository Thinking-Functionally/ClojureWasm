// Proof of Concept: Execute WAT and return a result
// This proves Phase 1-4 architecture WITHOUT touching the broken compiler
const std = @import("std");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("=== WasmGC Execution PoC ===\n", .{});

    // Step 1: Write simple WAT
    const wat =
        \\(module
        \\  (func (export "main") (result i64)
        \\    i64.const 42
        \\  )
        \\)
    ;

    const wat_path = "/tmp/poc_test.wat";
    const wasm_path = "/tmp/poc_test.wasm";

    {
        const file = try std.fs.cwd().createFile(wat_path, .{});
        defer file.close();
        try file.writeAll(wat);
    }
    std.debug.print("[1] Wrote WAT to {s}\n", .{wat_path});

    // Step 2: Convert WAT → WASM with wasm-tools
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "wasm-tools", "parse", wat_path, "-o", wasm_path },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) {
        std.debug.print("ERROR: wasm-tools failed: {s}\n", .{result.stderr});
        return error.ConversionFailed;
    }
    std.debug.print("[2] Converted to WASM binary at {s}\n", .{wasm_path});

    // Step 3: Execute with wasmtime
    const exec_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "wasmtime", "run", "--invoke", "main", wasm_path },
    });
    defer allocator.free(exec_result.stdout);
    defer allocator.free(exec_result.stderr);

    if (exec_result.term.Exited != 0) {
        std.debug.print("ERROR: wasmtime failed: {s}\n", .{exec_result.stderr});
        return error.ExecutionFailed;
    }

    std.debug.print("[3] Executed WASM, output: {s}\n", .{exec_result.stdout});

    // Step 4: Parse result (in real implementation, this would convert to ClojureWasm Value)
    const trimmed = std.mem.trim(u8, exec_result.stdout, &std.ascii.whitespace);
    const value = try std.fmt.parseInt(i64, trimmed, 10);

    std.debug.print("[4] Parsed result as i64: {d}\n", .{value});
    std.debug.print("\n✅ SUCCESS: Proved we can execute WAT → WASM → Result\n", .{});
    std.debug.print("    This is the foundation for Phases 1-4.\n", .{});
    std.debug.print("    Next: Wire this into evalForm() to return ClojureWasm Values\n", .{});
}
