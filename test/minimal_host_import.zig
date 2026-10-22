// Minimal test to isolate ArgArityMismatch with defineFuncCtx

const std = @import("std");
const zwasm = @import("zwasm");

pub fn testHostFunc(caller: *zwasm.Caller, param: i64) i64 {
    _ = caller;
    std.debug.print("[HOST] testHostFunc called with param={x}\n", .{param});
    return param + 1;
}

test "minimal (i64)->i64 host import" {
    const allocator = std.testing.allocator;

    var engine = try zwasm.Engine.init(allocator, .{});
    defer engine.deinit();

    var linker = zwasm.Linker.init(&engine);
    defer linker.deinit();

    const ctx: i32 = 42;
    const ctx_ptr: *anyopaque = @ptrCast(@constCast(&ctx));

    std.debug.print("Registering testHostFunc...\n", .{});
    std.debug.print("  Zig signature: {}\n", .{@TypeOf(testHostFunc)});

    try linker.defineFuncCtx("test", "testHostFunc", ctx_ptr, @TypeOf(testHostFunc), &testHostFunc);
    std.debug.print("Registration succeeded\n", .{});

    // Minimal Wasm module: import test.testHostFunc as (i64)->i64
    const wasm_bytes = [_]u8{
        0x00, 0x61, 0x73, 0x6d, // magic
        0x01, 0x00, 0x00, 0x00, // version

        // Type section
        0x01, 0x07,  // section 1, size 7
        0x01,        // 1 type
        0x60,        // func type
        0x01, 0x7e,  // 1 param: i64
        0x01, 0x7e,  // 1 result: i64

        // Import section
        0x02, 0x10,  // section 2, size 16
        0x01,        // 1 import
        0x04,        // module name length
        0x74, 0x65, 0x73, 0x74, // "test"
        0x08,        // field name length
        0x74, 0x65, 0x73, 0x74, 0x46, 0x75, 0x6e, 0x63, // "testFunc"
        0x00,        // import kind: function
        0x00,        // type index 0

        // Function section
        0x03, 0x02,  // section 3, size 2
        0x01,        // 1 function
        0x00,        // type 0

        // Export section
        0x07, 0x08,  // section 7, size 8
        0x01,        // 1 export
        0x04,        // name length
        0x6d, 0x61, 0x69, 0x6e, // "main"
        0x00,        // export kind: function
        0x01,        // function index 1 (import 0 + local 0)

        // Code section
        0x0a, 0x09,  // section 10, size 9
        0x01,        // 1 function body
        0x07,        // body size
        0x00,        // 0 locals
        0x42, 0x2a,  // i64.const 42
        0x10, 0x00,  // call 0 (the import)
        0x0b,        // end
    };

    std.debug.print("Compiling module...\n", .{});
    var module = try engine.compile(&wasm_bytes);
    defer module.deinit();

    std.debug.print("Instantiating module...\n", .{});
    var instance = linker.instantiate(&module, .{}) catch |err| {
        std.debug.print("Instantiate failed: {}\n", .{err});
        return err;
    };
    defer instance.deinit();

    std.debug.print("Calling main()...\n", .{});
    var results: [1]zwasm.Value = undefined;
    try instance.invoke("main", &[_]zwasm.Value{}, &results);

    std.debug.print("Result: {}\n", .{results[0].i64});
    try std.testing.expectEqual(@as(i64, 43), results[0].i64);
}
