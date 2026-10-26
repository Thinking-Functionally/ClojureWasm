// WasmGC Execution Architecture Proof-of-Concept
// Tests that we can: WAT → wasm-tools → WASM binary → zwasm → execute → Value
const std = @import("std");
const zwasm = @import("zwasm");
const testing = std.testing;

test "minimal WasmGC execution: (i64.const 42)" {
    const allocator = testing.allocator;

    // Simple WasmGC-style module
    const wat =
        \\(module
        \\  (func (export "main") (result i64)
        \\    i64.const 42
        \\  )
        \\)
    ;

    // Step 1: Write WAT to temp file
    const tmp_wat = "/tmp/test_wasmgc.wat";
    {
        const file = try std.fs.createFileAbsolute(tmp_wat, .{});
        defer file.close();
        try file.writeAll(wat);
    }

    // Step 2: Convert WAT → WASM with wasm-tools
    const tmp_wasm = "/tmp/test_wasmgc.wasm";
    const convert = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "wasm-tools", "parse", tmp_wat, "-o", tmp_wasm },
    });
    defer allocator.free(convert.stdout);
    defer allocator.free(convert.stderr);

    if (convert.term.Exited != 0) {
        std.debug.print("wasm-tools failed: {s}\n", .{convert.stderr});
        return error.ConversionFailed;
    }

    // Step 3: Load WASM with zwasm
    const wasm_bytes = try std.fs.readFileAlloc(allocator, tmp_wasm, 1024 * 1024);
    defer allocator.free(wasm_bytes);

    var engine = try zwasm.Engine.init(allocator);
    defer engine.deinit();

    var module = try zwasm.Module.init(&engine, wasm_bytes);
    defer module.deinit();

    var instance = try zwasm.Instance.init(&module, .{});
    defer instance.deinit();

    // Step 4: Call exported "main" function
    const result = try instance.call("main", &[_]zwasm.Value{}, allocator);
    defer if (result) |r| allocator.free(r);

    // Step 5: Verify result
    if (result) |values| {
        try testing.expect(values.len == 1);
        try testing.expect(values[0] == .i64);
        try testing.expectEqual(@as(i64, 42), values[0].i64);
    } else {
        return error.NoResult;
    }
}

test "execute add(1, 2) = 3 via zwasm (Option B proof)" {
    const allocator = testing.allocator;

    // WAT for (+ 1 2) compiled to WASM add function
    const wat =
        \\(module
        \\  (func (export "add") (param i64 i64) (result i64)
        \\    local.get 0
        \\    local.get 1
        \\    i64.add
        \\  )
        \\)
    ;

    // Step 1: Write WAT to temp file
    const tmp_wat = "/tmp/test_add_exec.wat";
    {
        const file = try std.fs.createFileAbsolute(tmp_wat, .{});
        defer file.close();
        try file.writeAll(wat);
    }

    // Step 2: Convert WAT → WASM with wasm-tools
    const tmp_wasm = "/tmp/test_add_exec.wasm";
    const convert = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "wasm-tools", "parse", tmp_wat, "-o", tmp_wasm },
    });
    defer allocator.free(convert.stdout);
    defer allocator.free(convert.stderr);

    if (convert.term.Exited != 0) {
        std.debug.print("wasm-tools failed: {s}\n", .{convert.stderr});
        return error.ConversionFailed;
    }

    // Step 3: Load WASM with zwasm
    const wasm_bytes = try std.fs.readFileAlloc(allocator, tmp_wasm, 1024 * 1024);
    defer allocator.free(wasm_bytes);

    var engine = try zwasm.Engine.init(allocator);
    defer engine.deinit();

    var module = try zwasm.Module.init(&engine, wasm_bytes);
    defer module.deinit();

    var instance = try zwasm.Instance.init(&module, .{});
    defer instance.deinit();

    // Step 4: Call add(1, 2)
    const args = [_]zwasm.Value{
        zwasm.Value{ .i64 = 1 },
        zwasm.Value{ .i64 = 2 },
    };
    const result = try instance.call("add", &args, allocator);
    defer if (result) |r| allocator.free(r);

    // Step 5: Verify result = 3
    if (result) |values| {
        try testing.expect(values.len == 1);
        try testing.expect(values[0] == .i64);
        try testing.expectEqual(@as(i64, 3), values[0].i64);

        std.debug.print("\n✓ SUCCESS: add(1, 2) = {}\n", .{values[0].i64});
        std.debug.print("✓ Option B PROVEN: WAT → WASM → zwasm → execute → result WORKS!\n", .{});
    } else {
        return error.NoResult;
    }
}
