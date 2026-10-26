const std = @import("std");
const Value = @import("Value");
const Node = @import("Node");
const Runtime = @import("Runtime");

const Executor = @import("wasmgc/executor.zig").Executor;
const SimpleWatGenerator = @import("wasmgc/simple_wat_gen.zig").SimpleWatGenerator;

/// Evaluate a Clojure AST node using the WasmGC backend
/// This is the entry point called from evalForm()
///
/// Strategy: Generate simple WAT → Execute with wasmtime → Return Value
/// Does NOT use the existing 6,069 LOC compiler (has compilation errors)
pub fn eval(rt: *Runtime, node: *const Node) !Value {
    var executor = try Executor.init(rt.arena);
    defer executor.deinit();

    var gen = SimpleWatGenerator.init(rt.arena);
    const wat = try gen.generate(node);
    defer rt.arena.free(wat);

    return try executor.executeWat(wat);
}
