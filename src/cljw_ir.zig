// SPDX-License-Identifier: EPL-2.0
//! cljw-ir — Standalone IR compiler tool
//!
//! Compiles Clojure source files to IR EDN format without evaluation.
//! This tool is independent of the main cljw runtime and doesn't require
//! bootstrap (clojure.core) to be loaded.
//!
//! Usage:
//!   cljw-ir source.clj         # compile to IR, print to stdout
//!   cljw-ir -e '(+ 1 2)'       # compile expression to IR
//!
//! Phase 1 Status: Supports 11/24 Node types (see src/ir/codegen.zig)

const std = @import("std");

// Direct imports from src tree (cljw-ir shares infrastructure, not via main module)
const Reader = @import("eval/reader.zig").Reader;
const Analyzer = @import("eval/analyzer/analyzer.zig");
const Node = @import("eval/node.zig").Node;
const Runtime = @import("runtime/runtime.zig").Runtime;
const Env = @import("runtime/env.zig").Env;
const Value = @import("runtime/value/value.zig").Value;
const macro_dispatch = @import("eval/macro_dispatch.zig");
const macro_transforms = @import("lang/macro_transforms.zig");
const ir_codegen = @import("ir/codegen.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    // Minimal runtime setup (no bootstrap needed for IR compilation)
    var rt = Runtime.init(init.io, allocator);
    defer rt.deinit();

    // Parse command-line args using init.minimal.args.iterate()
    var args = init.minimal.args.iterate();
    _ = args.skip(); // skip argv[0]

    const arg1 = args.next() orelse {
        try printUsage(init.io);
        return;
    };

    // Analyze: Form → Node (need minimal Env, no bootstrap required)
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const source = if (std.mem.eql(u8, arg1, "-e"))
        args.next() orelse {
            try printUsage(init.io);
            return;
        }
    else
        try std.Io.Dir.cwd().readFileAlloc(init.io, arg1, arena_alloc, @enumFromInt(1024 * 1024));

    // Read form (use arena allocator for all Reader internal allocations)
    var reader = Reader.init(arena_alloc, source);
    const form = try reader.read() orelse {
        std.debug.print("No form read\n", .{});
        return;
    };

    // Minimal Env for symbol resolution (IR compilation doesn't eval, so no bootstrap)
    var env = try Env.init(&rt);
    defer env.deinit();

    // Register minimal core primitives for IR codegen Phase 1 testing
    // (analyzer needs these to resolve symbols; IR backend doesn't eval them)
    const core_ns = try env.findOrCreateNs("clojure.core");
    _ = try env.internDeclare(core_ns, "+");
    _ = try env.internDeclare(core_ns, "-");
    _ = try env.internDeclare(core_ns, "*");
    _ = try env.internDeclare(core_ns, "/");
    _ = try env.internDeclare(core_ns, "def");
    _ = try env.internDeclare(core_ns, "if");
    _ = try env.internDeclare(core_ns, "let");
    _ = try env.internDeclare(core_ns, "fn*");
    _ = try env.internDeclare(core_ns, "quote");

    // Set clojure.core as current namespace so analyzer can resolve unqualified symbols
    env.setCurrentNs(core_ns);

    // GC analysis frame for string constants and other heap-allocated forms
    const root_set = @import("runtime/gc/root_set.zig");
    var analysis_frame: root_set.AnalysisFrame = undefined;
    root_set.beginAnalysis(&analysis_frame, allocator); // use process-lifetime allocator (main GPA)
    defer root_set.endAnalysis(&analysis_frame);

    // Macro table with special forms registered (let, if, def, etc.)
    // IR backend doesn't expand user macros, but needs special forms for analysis
    var macro_table = macro_dispatch.Table.init(arena_alloc);
    try macro_transforms.registerInto(&env, &macro_table);

    // Minimal scope for let bindings (empty parent scope = top-level)
    var scope = Analyzer.Scope{ .parent = null };
    defer scope.deinit(arena_alloc);

    const node = try Analyzer.analyze(arena_alloc, &rt, &env, &scope, form, &macro_table);

    // Compile Node → IR
    var ctx = ir_codegen.CompileContext{ .allocator = arena_alloc };
    defer ctx.deinit();
    const ir_value = try ir_codegen.compileNode(&ctx, node);

    // Output IR EDN
    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buf);
    const stdout = &stdout_writer.interface;

    try stdout.print(";; IR Backend Phase 1\n", .{});
    try stdout.print("{f}\n", .{ir_value});
    try stdout.flush();
}

fn printUsage(io: std.Io) !void {
    var stderr_buf: [4096]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(io, &stderr_buf);
    const stderr = &stderr_writer.interface;
    try stderr.writeAll(
        \\cljw-ir — ClojureWasm IR Compiler
        \\
        \\Usage:
        \\  cljw-ir <file.clj>    Compile file to IR EDN
        \\  cljw-ir -e '<expr>'   Compile expression to IR EDN
        \\
        \\Phase 1 Status: 11/24 Node types supported
        \\
    );
    try stderr.flush();
}

fn printFunctionIR(func: *const ir_codegen.FunctionIR, writer: anytype) !void {
    try writer.print("{{:id \"{s}\"\n", .{func.id});
    if (func.name) |name| {
        try writer.print(" :name \"{s}\"\n", .{name});
    }
    try writer.print(" :arity ", .{});
    switch (func.arity) {
        .fixed => |n| try writer.print("{{:fixed {d}}}\n", .{n}),
        .variadic => |v| try writer.print("{{:variadic {{:required {d}}}}}\n", .{v.required}),
    }

    try writer.print(" :params [", .{});
    for (func.params, 0..) |param, i| {
        if (i > 0) try writer.print(" ", .{});
        try writer.print(":{s}", .{param});
    }
    try writer.print("]\n", .{});

    if (func.captures.len > 0) {
        try writer.print(" :captures [", .{});
        for (func.captures, 0..) |cap, i| {
            if (i > 0) try writer.print(" ", .{});
            try writer.print(":{s}", .{cap});
        }
        try writer.print("]\n", .{});
    }

    try writer.print(" :entry {}\n", .{func.entry_block});
    try writer.print(" :blocks []\n", .{}); // Simplified for Phase 1
    try writer.print("}}\n", .{});
}
