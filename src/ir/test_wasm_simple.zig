const std = @import("std");
const wasm = @import("wasm_codegen.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.page_allocator;
    const io = init.io;

    // Generate simple WASM: (f64) -> f64 that returns param + 10
    var module = wasm.WasmModule.init(allocator);
    defer module.deinit();

    // local.get 0 (get first parameter)
    try module.emitLocalGet(0);

    // f64.const 10.0
    try module.emitF64Const(10.0);

    // f64.add
    try module.emit(.f64_add);

    // Generate WASM bytes
    const wasm_bytes = try module.toBytes();
    defer allocator.free(wasm_bytes);

    std.debug.print("Generated WASM module: {} bytes\n", .{wasm_bytes.len});

    // Write to file
    const file = try std.Io.Dir.cwd().createFile(io, "test_simple.wasm", .{});
    defer file.close(io);

    var file_buffer: [4096]u8 = undefined;
    var file_writer = file.writer(io, &file_buffer);
    try file_writer.interface.writeAll(wasm_bytes);
    try file_writer.interface.flush();

    std.debug.print("✓ Wrote test_simple.wasm\n", .{});
    std.debug.print("Test with: node -e \"const fs = require('fs'); const buf = fs.readFileSync('test_simple.wasm'); WebAssembly.instantiate(buf).then(m => console.log('Result:', m.instance.exports.main(5)));\"\n", .{});
}
