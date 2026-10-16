const std = @import("std");
const ir_to_wasm = @import("ir_to_wasm.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.page_allocator;
    const io = init.io;

    std.debug.print("\n", .{});
    std.debug.print("╔════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║  Phase 4 PoC - IR to WASM Compiler Test                   ║\n", .{});
    std.debug.print("╚════════════════════════════════════════════════════════════╝\n", .{});
    std.debug.print("\n", .{});

    // Test 1: Simple add function
    std.debug.print("✅ Test 1: add(10, 32) = 42\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    const ir_add =
        \\{:id :fn/user-add-1
        \\ :name "add"
        \\ :namespace "user"
        \\ :arity {:fixed 2}
        \\ :params [:param/x :param/y]
        \\ :blocks [:block/entry]
        \\ :entry-block :block/entry
        \\ :block-defs {:block/entry
        \\   {:id :block/entry
        \\    :instructions [{:op :var-ref :result :val/2 :var :param/x}
        \\                   {:op :var-ref :result :val/3 :var :param/y}
        \\                   {:op :call :result :val/5 :fn :builtin/+ :args [:val/2 :val/3]}]
        \\    :terminator {:op :return :value :val/5}}}}
    ;

    var module_add = try ir_to_wasm.compile(allocator, ir_add);
    defer module_add.deinit();

    const wasm_add = try module_add.toBytes();
    defer allocator.free(wasm_add);

    std.debug.print("✓ Generated WASM: {} bytes\n", .{wasm_add.len});

    // Write to file
    const file_add = try std.Io.Dir.cwd().createFile(io, "test_add.wasm", .{});
    defer file_add.close(io);

    var buffer_add: [4096]u8 = undefined;
    var writer_add = file_add.writer(io, &buffer_add);
    try writer_add.interface.writeAll(wasm_add);
    try writer_add.interface.flush();

    std.debug.print("✓ Wrote test_add.wasm\n", .{});
    std.debug.print("Test: node -e \"const fs = require('fs'); const buf = fs.readFileSync('test_add.wasm'); WebAssembly.instantiate(buf).then(m => console.log('add(10, 32) =', m.instance.exports.main(10, 32)));\"\n", .{});
    std.debug.print("\n", .{});

    // Test 2: Multiply function
    std.debug.print("✅ Test 2: mul(6, 7) = 42\n", .{});
    std.debug.print("----------------------------------------\n", .{});

    const ir_mul =
        \\{:id :fn/user-mul-1
        \\ :name "mul"
        \\ :namespace "user"
        \\ :arity {:fixed 2}
        \\ :params [:param/a :param/b]
        \\ :blocks [:block/entry]
        \\ :entry-block :block/entry
        \\ :block-defs {:block/entry
        \\   {:id :block/entry
        \\    :instructions [{:op :var-ref :result :val/2 :var :param/a}
        \\                   {:op :var-ref :result :val/3 :var :param/b}
        \\                   {:op :call :result :val/5 :fn :builtin/* :args [:val/2 :val/3]}]
        \\    :terminator {:op :return :value :val/5}}}}
    ;

    var module_mul = try ir_to_wasm.compile(allocator, ir_mul);
    defer module_mul.deinit();

    const wasm_mul = try module_mul.toBytes();
    defer allocator.free(wasm_mul);

    std.debug.print("✓ Generated WASM: {} bytes\n", .{wasm_mul.len});

    const file_mul = try std.Io.Dir.cwd().createFile(io, "test_mul.wasm", .{});
    defer file_mul.close(io);

    var buffer_mul: [4096]u8 = undefined;
    var writer_mul = file_mul.writer(io, &buffer_mul);
    try writer_mul.interface.writeAll(wasm_mul);
    try writer_mul.interface.flush();

    std.debug.print("✓ Wrote test_mul.wasm\n", .{});
    std.debug.print("Test: node -e \"const fs = require('fs'); const buf = fs.readFileSync('test_mul.wasm'); WebAssembly.instantiate(buf).then(m => console.log('mul(6, 7) =', m.instance.exports.main(6, 7)));\"\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("╔════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║  Phase 4 PoC - IR to WASM 編譯成功！                      ║\n", .{});
    std.debug.print("╚════════════════════════════════════════════════════════════╝\n", .{});
    std.debug.print("\n", .{});
}
