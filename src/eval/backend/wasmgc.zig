//! WasmGC backend: the third evaluation backend next to `tree_walk.zig` and
//! `vm.zig`. `driver.evalForm` calls `evalNode` for every top-level form.
//!
//! Pipeline: analyzer `Node` → WAT text → `wasm-tools parse` → WASM binary →
//! zwasm instance → result `Value`.
//!
//! All 25 `Node` kinds compile; there is no silent fallback. Every Clojure
//! value inside the module is an i32 handle into a host-side table
//! (`State.handles`), published to the GC as a root frame while WASM runs, so
//! any value (and its printing/equality) round-trips without per-type
//! marshalling. Clojure functions become exported WASM functions stamped onto
//! ordinary `Function` objects (`FunctionMethod.native`), so `fn?`, metadata,
//! protocols and `map`/`reduce` callbacks all work unchanged. `try`, `binding`,
//! `def`, literals, interop and calls go through host imports (module "h");
//! `clojure.core` and the other library functions are reached the same way.
//!
//! Per-thread state: zwasm instances are not re-entrant across threads and are
//! capped at 256 wasm frames, so each thread (and each ~100 nested activations)
//! runs on its own instance of the shared compiled module.

const std = @import("std");
const zwasm = @import("zwasm");
const Runtime = @import("../../runtime/runtime.zig").Runtime;
const Env = @import("../../runtime/env.zig").Env;
const Var = @import("../../runtime/env.zig").Var;
const Value = @import("../../runtime/value/value.zig").Value;
const node_mod = @import("../node.zig");
const Node = node_mod.Node;
const tree_walk = @import("tree_walk.zig");
const file_io = @import("../../runtime/file_io.zig");
const error_mod = @import("../../runtime/error/info.zig");
const dispatch = @import("../../runtime/dispatch.zig");
const host_class = @import("../../runtime/error/host_class.zig");
const ex_info_collection = @import("../../runtime/collection/ex_info.zig");
const keyword_mod = @import("../../runtime/keyword.zig");
const vector_collection = @import("../../runtime/collection/vector.zig");
const map_collection = @import("../../runtime/collection/map.zig");
const set_collection = @import("../../runtime/collection/set.zig");
const error_catalog = @import("../../runtime/error/catalog.zig");
const root_set = @import("../../runtime/gc/root_set.zig");
const eval_budget_mod = @import("../../runtime/concurrency/eval_budget.zig");

/// Map zwasm's own resource traps onto the Clojure errors TreeWalk/VM raise.
fn realError(s: *State, e: anyerror) anyerror {
    const real = s.err orelse e;
    s.err = null;
    if (real == error.CallStackExhausted)
        return error_catalog.raise(.stack_overflow, .{}, .{ .max = STACK_BUDGET_BYTES });
    return real;
}

/// Fixed handle-table capacity: the table's buffer address must stay stable
/// because it is published to the GC as a root frame.
const HANDLE_CAP: usize = 32768;

/// zwasm caps one instance at 256 wasm frames; continue on a fresh instance
/// well before that (an activation can use a few frames: method + thunks).
const MAX_WASM_DEPTH: u32 = 100;

/// Native-stack budget for Clojure recursion (same value as TreeWalk's).
const STACK_BUDGET_BYTES: usize = 6 * 1024 * 1024;

pub const MAX_CALL_ARGS = 7;

pub const CompileError = error{
    OutOfMemory,
    WasmgcUnsupportedNode,
    WasmgcRecurOutsideLoop,
    WasmgcTooManyArgs,
};

const LoopFrame = struct { id: u32, indices: []const u16 };

/// One compiled `fn` node: export ids of each fixed-arity method + variadic.
const FnInfo = struct { node: *const Node, method_ids: []const u32, variadic_id: ?u32 };

/// One compiled `try`: exported thunks for body, each catch body, finally.
const TryInfo = struct { node: *const node_mod.TryNode, body_id: u32, catch_ids: []const u32, finally_id: ?u32 };

/// One compiled `binding`: thunks for each init expression and the body.
const BindInfo = struct { node: *const node_mod.BindingNode, init_ids: []const u32, body_id: u32 };

/// Per-form compilation state: WAT text, constant pool and host-eval nodes.
const Compiler = struct {
    arena: std.mem.Allocator,
    out: std.ArrayList(u8) = .empty,
    consts: std.ArrayList(Value) = .empty,
    nodes: std.ArrayList(*const Node) = .empty,
    vars: std.ArrayList(*const Var) = .empty,
    loops: std.ArrayList(LoopFrame) = .empty,
    funcs: std.ArrayList(u8) = .empty,
    fns: std.ArrayList(FnInfo) = .empty,
    tries: std.ArrayList(TryInfo) = .empty,
    bindings: std.ArrayList(BindInfo) = .empty,
    next_label: u32 = 0,
    next_func: u32 = 0,

    fn emit(self: *Compiler, comptime fmt: []const u8, args: anytype) !void {
        const s = try std.fmt.allocPrint(self.arena, fmt, args);
        try self.out.appendSlice(self.arena, s);
    }

    fn constant(self: *Compiler, v: Value) !void {
        const idx = self.consts.items.len;
        try self.consts.append(self.arena, v);
        try self.emit("(i32.const {d})\n", .{idx});
    }

    fn expr(self: *Compiler, n: *const Node) CompileError!void {
        switch (n.*) {
            .constant => |c| try self.constant(c.value),
            .quote_node => |q| try self.constant(q.quoted),
            .var_ref => |v| {
                const idx = self.vars.items.len;
                try self.vars.append(self.arena, v.var_ptr);
                try self.emit("(call $var (i32.const {d}))\n", .{idx});
            },
            .local_ref => |l| try self.emit("(call $local_get (i32.const {d}))\n", .{l.index}),
            .if_node => |i| {
                try self.expr(i.cond);
                try self.emit("(call $truthy)\n(if (result i32)\n(then\n", .{});
                try self.expr(i.then_branch);
                try self.emit(")\n(else\n", .{});
                if (i.else_branch) |e| try self.expr(e) else try self.constant(.nil_val);
                try self.emit("))\n", .{});
            },
            .do_node => |d| {
                if (d.forms.len == 0) return self.constant(.nil_val);
                for (d.forms, 0..) |*f, k| {
                    try self.expr(f);
                    if (k + 1 < d.forms.len) try self.emit("(drop)\n", .{});
                }
            },
            .let_node => |l| {
                for (l.bindings) |b| {
                    try self.expr(b.value_expr);
                    try self.emit("(i32.const {d})\n(call $local_set)\n", .{b.index});
                }
                try self.expr(l.body);
            },
            .loop_node => |l| {
                const id = self.next_label;
                self.next_label += 1;
                for (l.bindings) |b| {
                    try self.expr(b.value_expr);
                    try self.emit("(i32.const {d})\n(call $local_set)\n", .{b.index});
                }
                const idxs = try self.arena.alloc(u16, l.bindings.len);
                for (l.bindings, 0..) |b, k| idxs[k] = b.index;
                try self.loops.append(self.arena, .{ .id = id, .indices = idxs });
                try self.emit("(call $loop_mark)\n(loop $L{d} (result i32)\n", .{id});
                try self.expr(l.body);
                try self.emit(")\n(call $loop_end)\n", .{});
                _ = self.loops.pop();
            },
            .recur_node => |r| {
                if (self.loops.items.len == 0) return error.WasmgcRecurOutsideLoop;
                const lf = self.loops.items[self.loops.items.len - 1];
                if (lf.indices.len != r.args.len) return error.WasmgcUnsupportedNode;
                for (r.args) |*a| try self.expr(a);
                var k = r.args.len;
                while (k > 0) {
                    k -= 1;
                    try self.emit("(i32.const {d})\n(call $local_set)\n", .{lf.indices[k]});
                }
                try self.emit("(call $loop_reset)\n(br $L{d})\n(i32.const 0)\n", .{lf.id});
            },
            .call_node => |c| {
                try self.expr(c.callee);
                const idx = self.nodes.items.len;
                try self.nodes.append(self.arena, n);
                if (c.args.len > MAX_CALL_ARGS) {
                    try self.emit("(call $lit_begin (i32.const 3))\n", .{});
                    for (c.args) |*a| {
                        try self.expr(a);
                        try self.emit("(call $lit_add)\n", .{});
                    }
                    try self.emit("(i32.const {d})\n(call $callv)\n", .{idx});
                    return;
                }
                for (c.args) |*a| try self.expr(a);
                try self.emit("(i32.const {d})\n(call $call{d})\n", .{ idx, c.args.len });
            },
            .fn_node => |f| try self.compileFn(n, f),
            .throw_node => |t| {
                try self.expr(t.expr);
                try self.emit("(call $throw)\n", .{});
            },
            .try_node => |*t| {
                const body_id = try self.compileThunk(t.body);
                const cids = try self.arena.alloc(u32, t.catch_clauses.len);
                for (t.catch_clauses, 0..) |cc, k| cids[k] = try self.compileThunk(cc.body);
                const fid: ?u32 = if (t.finally_body) |fb| try self.compileThunk(fb) else null;
                const idx = self.tries.items.len;
                try self.tries.append(self.arena, .{ .node = t, .body_id = body_id, .catch_ids = cids, .finally_id = fid });
                try self.emit("(call $try (i32.const {d}))\n", .{idx});
            },
            .def_node => |d| {
                if (d.has_init) try self.expr(d.value_expr) else try self.constant(.nil_val);
                if (d.meta_expr) |me| try self.expr(me) else try self.constant(.nil_val);
                const idx = self.nodes.items.len;
                try self.nodes.append(self.arena, n);
                try self.emit("(i32.const {d})\n(call $def)\n", .{idx});
            },
            .vector_literal_node => |v| try self.literal(0, v.elements),
            // Pure host operations: no sub-expressions to compile.
            .in_ns_node, .require_node, .ns_node => try self.hostOp(n),
            .letfn_node => |l| {
                for (l.bindings) |b| try self.emit("(i32.const 0)\n(i32.const {d})\n(call $local_set)\n", .{b.index});
                for (l.bindings) |b| {
                    try self.expr(b.value_expr);
                    try self.emit("(i32.const {d})\n(call $local_set)\n", .{b.index});
                }
                if (l.bindings.len > 0)
                    try self.emit("(i32.const {d})\n(i32.const {d})\n(call $letfn_patch)\n", .{ l.bindings[0].index, l.bindings.len });
                try self.expr(l.body);
            },
            .binding_node => |*b| {
                const ids = try self.arena.alloc(u32, b.pairs.len);
                for (b.pairs, 0..) |p, k| ids[k] = try self.compileThunk(p.value_expr);
                const body_id = try self.compileThunk(b.body);
                const idx = self.bindings.items.len;
                try self.bindings.append(self.arena, .{ .node = b, .init_ids = ids, .body_id = body_id });
                try self.emit("(call $binding (i32.const {d}))\n", .{idx});
            },
            // Children are compiled natively; the host applies the operation
            // to the already-evaluated values.
            .interop_call_node => |ic| {
                try self.emit("(call $lit_begin (i32.const 3))\n", .{});
                if (ic.target) |t| {
                    try self.expr(t);
                    try self.emit("(call $lit_add)\n", .{});
                }
                for (ic.args) |*a| {
                    try self.expr(a);
                    try self.emit("(call $lit_add)\n", .{});
                }
                try self.applyOp(n);
            },
            .set_node => |sn| {
                try self.emit("(call $lit_begin (i32.const 3))\n", .{});
                try self.expr(sn.value_expr);
                try self.emit("(call $lit_add)\n", .{});
                try self.applyOp(n);
            },
            .set_field_node => |sf| {
                try self.emit("(call $lit_begin (i32.const 3))\n", .{});
                try self.expr(sf.target);
                try self.emit("(call $lit_add)\n", .{});
                try self.expr(sf.value_expr);
                try self.emit("(call $lit_add)\n", .{});
                try self.applyOp(n);
            },
            .map_literal_node => |m| try self.literal(1, m.elements),
            .set_literal_node => |st| try self.literal(2, st.elements),
        }
    }

    /// A node with no sub-expressions that is a pure host operation.
    fn hostOp(self: *Compiler, n: *const Node) CompileError!void {
        const idx = self.nodes.items.len;
        try self.nodes.append(self.arena, n);
        try self.emit("(call $eval (i32.const {d}))\n", .{idx});
    }

    /// Finish a pre-evaluated-children operation (builder already filled).
    fn applyOp(self: *Compiler, n: *const Node) CompileError!void {
        const idx = self.nodes.items.len;
        try self.nodes.append(self.arena, n);
        try self.emit("(call $apply (i32.const {d}))\n", .{idx});
    }

    /// Collection literal: begin a host builder, add each evaluated element, end.
    fn literal(self: *Compiler, kind: u32, elements: []const Node) CompileError!void {
        try self.emit("(call $lit_begin (i32.const {d}))\n", .{kind});
        for (elements) |*e| {
            try self.expr(e);
            try self.emit("(call $lit_add)\n", .{});
        }
        try self.emit("(call $lit_end)\n", .{});
    }

    /// Compile an expression into its own exported zero-arg WASM function
    /// (try body / catch body / finally) that runs over the shared locals.
    fn compileThunk(self: *Compiler, body: *const Node) CompileError!u32 {
        const id = self.next_func;
        self.next_func += 1;
        const saved_out = self.out;
        const saved_loops = self.loops;
        self.out = .empty;
        self.loops = .empty;
        defer {
            self.out = saved_out;
            self.loops = saved_loops;
        }
        try self.emit("(func $m{d} (export \"m{d}\") (result i32)\n", .{ id, id });
        try self.expr(body);
        try self.emit(")\n", .{});
        try self.funcs.appendSlice(self.arena, self.out.items);
        return id;
    }

    /// Compile every method body to its own exported WASM function; the value
    /// is created at run time by `h.make_fn`, which stamps each method's
    /// `native` hook so the standard Function dispatch reaches the WASM body.
    fn compileFn(self: *Compiler, n: *const Node, f: node_mod.FnNode) CompileError!void {
        const ids = try self.arena.alloc(u32, f.methods.len);
        for (f.methods, 0..) |m, k| ids[k] = try self.compileMethod(f, m);
        const vid: ?u32 = if (f.variadic) |v| try self.compileMethod(f, v) else null;
        const idx = self.fns.items.len;
        try self.fns.append(self.arena, .{ .node = n, .method_ids = ids, .variadic_id = vid });
        try self.emit("(call $make_fn (i32.const {d}))\n", .{idx});
    }

    fn compileMethod(self: *Compiler, f: node_mod.FnNode, m: node_mod.FnMethod) CompileError!u32 {
        const id = self.next_func;
        self.next_func += 1;
        const saved_out = self.out;
        const saved_loops = self.loops;
        self.out = .empty;
        self.loops = .empty;
        defer {
            self.out = saved_out;
            self.loops = saved_loops;
        }
        // A fn is an implicit loop over its parameter slots (recur target).
        const nslots: usize = @as(usize, m.arity) + @intFromBool(m.has_rest);
        const idxs = try self.arena.alloc(u16, nslots);
        for (idxs, 0..) |*x, k| x.* = f.slot_base + @as(u16, @intCast(k));
        const lid = self.next_label;
        self.next_label += 1;
        try self.loops.append(self.arena, .{ .id = lid, .indices = idxs });
        try self.emit("(func $m{d} (export \"m{d}\") (result i32)\n(call $loop_mark)\n(loop $L{d} (result i32)\n", .{ id, id, lid });
        try self.expr(m.body);
        try self.emit(")\n(call $loop_end)\n)\n", .{});
        try self.funcs.appendSlice(self.arena, self.out.items);
        return id;
    }
};

threadlocal var tl_marker: u8 = 0;
threadlocal var tl_clones: std.AutoHashMapUnmanaged(*State, *State) = .empty;
/// This thread's States that currently hold a zwasm instance, least recently
/// used first (see `State.ensureLive`).
threadlocal var tl_live: std.ArrayList(*State) = .empty;

/// Per-thread cap on live zwasm instances (each pins roughly 2 MB).
const MAX_LIVE_INSTANCES: usize = 64;
var inst_lock = std.atomic.Value(bool).init(false);

fn lockInst() void {
    while (inst_lock.cmpxchgWeak(false, true, .acquire, .monotonic) != null) std.atomic.spinLoopHint();
}
fn unlockInst() void {
    inst_lock.store(false, .release);
}

/// Runtime state shared with the host imports (zwasm `Caller.data`).
/// Heap-allocated and never freed when the module defined functions, because
/// those functions outlive the top-level form that created them.
const State = struct {
    rt: *Runtime,
    env: *Env,
    locals: []Value,
    handles: std.ArrayList(Value),
    nodes: []const *const Node,
    vars: []const *const Var,
    fns: []const FnInfo,
    tries: []const TryInfo,
    bindings: []const BindInfo,
    builders: std.ArrayList(Builder) = .empty,
    inst: ?*zwasm.Instance = null,
    linker: ?*zwasm.Linker = null,
    gpa: std.mem.Allocator,
    err: ?anyerror = null,
    /// Mirror of `handles.items.len` for the GC root frame (`EvalFrame.sp`).
    hlen: u16 = 0,
    /// Handle-table high-water marks of the enclosing loops (see `loop_mark`).
    marks: std.ArrayList(u32) = .empty,
    /// Live activations on this instance, and the continuation instance used
    /// once `depth` reaches MAX_WASM_DEPTH.
    depth: u32 = 0,
    next: ?*State = null,
    /// Thread that owns this State (address of its threadlocal marker); the
    /// root State is shared by every thread, each running its own clone/instance.
    owner: *const u8 = undefined,
    root: *State = undefined,
    eng: ?*zwasm.Engine = null,
    mod: ?*zwasm.Module = null,
    /// The compiled module's bytes, kept so an evicted State can be rebuilt.
    wasm_bytes: []const u8 = &.{},
    consts: []const Value = &.{},

    /// The State to run on for the calling thread: a zwasm instance is not
    /// re-entrant across threads, so each thread lazily gets its own
    /// instance of the shared compiled module (all language state is
    /// host-side, so a fresh instance is semantically identical).
    fn forThread(self: *State) !*State {
        const me: *const u8 = &tl_marker;
        if (self.owner == me) return self;
        const root = self.root;
        if (root.owner == me) return root;
        const gop = try tl_clones.getOrPut(std.heap.page_allocator, root);
        if (gop.found_existing) return gop.value_ptr.*;
        errdefer _ = tl_clones.remove(root);
        const c = try cloneState(root, me);
        gop.value_ptr.* = c;
        return c;
    }

    /// Continuation State for activations deeper than one zwasm instance can
    /// hold (zwasm caps an instance at 256 wasm frames).
    fn child(self: *State) !*State {
        if (self.next) |n| return n;
        const c = try cloneState(self.root, self.owner);
        self.next = c;
        return c;
    }

    fn cloneState(root: *State, me: *const u8) !*State {
        const gpa = std.heap.page_allocator;
        const c = try gpa.create(State);
        c.* = root.*;
        c.handles = .empty;
        c.builders = .empty;
        c.marks = .empty;
        c.hlen = 0;
        c.err = null;
        c.depth = 0;
        c.next = null;
        c.owner = me;
        c.inst = null;
        c.linker = null;
        c.mod = null;
        c.eng = null;
        try c.revive();
        try tl_live.append(gpa, c);
        return c;
    }

    /// (Re)create this State's engine, module, instance and handle table from
    /// the retained wasm bytes. Each State owns its own so eviction frees all.
    fn revive(self: *State) !void {
        const gpa = std.heap.page_allocator;
        try self.handles.ensureTotalCapacity(gpa, HANDLE_CAP);
        self.handles.appendSliceAssumeCapacity(self.consts);
        self.hlen = @intCast(self.consts.len);
        lockInst();
        defer unlockInst();
        const eng = try gpa.create(zwasm.Engine);
        eng.* = try zwasm.Engine.init(gpa, .{});
        const mod = try gpa.create(zwasm.Module);
        mod.* = try eng.compile(self.wasm_bytes);
        const linker = try gpa.create(zwasm.Linker);
        linker.* = zwasm.Linker.init(eng);
        try defineImports(linker, self);
        const inst = try gpa.create(zwasm.Instance);
        inst.* = try linker.instantiate(mod, .{});
        self.eng = eng;
        self.mod = mod;
        self.linker = linker;
        self.inst = inst;
    }

    /// Drop the engine, module, instance and handle table of an idle State;
    /// `revive` rebuilds them from `wasm_bytes` on the next call.
    fn evict(self: *State) void {
        const gpa = std.heap.page_allocator;
        if (self.inst) |i| {
            i.deinit();
            gpa.destroy(i);
        }
        if (self.linker) |l| {
            l.deinit();
            gpa.destroy(l);
        }
        if (self.mod) |m| {
            m.deinit();
            gpa.destroy(m);
        }
        if (self.eng) |e| {
            e.deinit();
            gpa.destroy(e);
        }
        self.inst = null;
        self.linker = null;
        self.mod = null;
        self.eng = null;
        self.handles.deinit(gpa);
        self.handles = .empty;
        self.hlen = 0;
    }

    /// Evict idle least-recently-used States beyond the cap (never `keep`).
    fn trimLive(keep: *State) void {
        var i: usize = 0;
        while (tl_live.items.len > MAX_LIVE_INSTANCES and i < tl_live.items.len) {
            const v = tl_live.items[i];
            if (v != keep and v.depth == 0) {
                v.evict();
                _ = tl_live.orderedRemove(i);
            } else i += 1;
        }
    }

    /// Mark this State most-recently-used on the calling thread, reviving it if
    /// it was evicted, and trim. Only this thread's own States are tracked, so
    /// eviction never races.
    fn ensureLive(self: *State) !void {
        const gpa = std.heap.page_allocator;
        for (tl_live.items, 0..) |x, i| {
            if (x == self) {
                _ = tl_live.orderedRemove(i);
                break;
            }
        }
        try tl_live.append(gpa, self);
        if (self.inst == null) try self.revive();
        trimLive(self);
    }

    fn methodBody(self: *State, id: u32) !*const tree_walk.NativeBody {
        const ref = try self.gpa.create(MethodRef);
        ref.* = .{
            .state = self,
            .export_name = try std.fmt.allocPrint(self.gpa, "m{d}", .{id}),
            .body = .{ .ctx = ref, .run = &runMethod },
        };
        return &ref.body;
    }

    fn push(self: *State, v: Value) !i32 {
        const idx = self.handles.items.len;
        if (idx >= HANDLE_CAP) return error.WasmgcHandleOverflow;
        self.handles.appendAssumeCapacity(v);
        self.hlen = @intCast(idx + 1);
        return @intCast(idx);
    }

    fn truncate(self: *State, len: usize) void {
        self.handles.shrinkRetainingCapacity(len);
        self.hlen = @intCast(len);
    }

    /// Stash the real error; zwasm only accepts its own trap variants from a
    /// host function, so trap with `HostTrap` and let the caller recover it.
    fn fail(self: *State, e: anyerror) anyerror {
        self.err = e;
        return error.HostTrap;
    }

    fn doCall(self: *State, f: i32, hs: []const i32, node_idx: i32) anyerror!i32 {
        var args: [MAX_CALL_ARGS]Value = undefined;
        for (hs, 0..) |h, i| args[i] = self.handles.items[@intCast(h)];
        return self.doCallV(self.handles.items[@intCast(f)], args[0..hs.len], node_idx);
    }

    /// Dispatch with the call node's location and per-argument locations
    /// (arg-precise error carets), mirroring TreeWalk's `evalCall`.
    fn doCallV(self: *State, callee: Value, args: []const Value, node_idx: i32) anyerror!i32 {
        const vt = self.rt.vtable orelse return self.fail(error.WasmgcNoVtable);
        const cn = self.nodes[@intCast(node_idx)].call_node;
        var arg_locs: [64]error_mod.SourceLocation = undefined;
        const nl = @min(cn.args.len, arg_locs.len);
        for (cn.args[0..nl], 0..) |*a, i| arg_locs[i] = a.loc();
        const prev = error_mod.swapArgSources(arg_locs[0..nl]);
        defer _ = error_mod.swapArgSources(prev);
        const r = vt.callFn(self.rt, self.env, callee, args, cn.loc) catch |e| return self.fail(e);
        return self.push(r) catch |e| self.fail(e);
    }
};

const Caller = zwasm.Caller;

const Builder = struct { kind: u32, items: std.ArrayList(Value) };

const env_mod = @import("../../runtime/env.zig");

fn hLoopMark(c: *Caller) anyerror!void {
    const s = c.data(State);
    try s.marks.append(s.gpa, @intCast(s.handles.items.len));
}
fn hLoopReset(c: *Caller) anyerror!void {
    const s = c.data(State);
    // Back-edge: charge the in-process eval budget (parity with VM/TreeWalk).
    if (eval_budget_mod.current) |b| b.tick(s.rt.io) catch |e| return s.fail(e);
    s.truncate(s.marks.items[s.marks.items.len - 1]);
}
fn hLoopEnd(c: *Caller) anyerror!void {
    const s = c.data(State);
    _ = s.marks.pop();
}

fn hLetfnPatch(c: *Caller, base: i32, count: i32) anyerror!void {
    const s = c.data(State);
    tree_walk.patchLetfnClosures(s.locals, @intCast(base), @intCast(count));
}

/// Apply an interop / set! / set-field node to its already-evaluated children
/// (collected in the builder), by evaluating a copy whose children are constants.
fn hApply(c: *Caller, idx: i32) anyerror!i32 {
    const s = c.data(State);
    var b = s.builders.pop().?;
    defer b.items.deinit(s.gpa);
    var cn: [32]Node = undefined;
    const n = b.items.items.len;
    if (n > cn.len) return s.fail(error.WasmgcTooManyArgs);
    for (b.items.items, 0..) |v, i| cn[i] = .{ .constant = .{ .value = v } };
    var nn: Node = switch (s.nodes[@intCast(idx)].*) {
        .interop_call_node => |ic| blk: {
            var x = ic;
            var off: usize = 0;
            if (ic.target != null) {
                x.target = &cn[0];
                off = 1;
            }
            x.args = cn[off..n];
            break :blk .{ .interop_call_node = x };
        },
        .set_node => |sn| blk: {
            var x = sn;
            x.value_expr = &cn[0];
            break :blk .{ .set_node = x };
        },
        .set_field_node => |sf| blk: {
            var x = sf;
            x.target = &cn[0];
            x.value_expr = &cn[1];
            break :blk .{ .set_field_node = x };
        },
        else => unreachable,
    };
    const v = tree_walk.eval(s.rt, s.env, s.locals, &nn) catch |e| return s.fail(e);
    return s.push(v) catch |e| s.fail(e);
}

/// Port of TreeWalk `evalBinding` with init/body expressions run as thunks.
fn hBinding(c: *Caller, idx: i32) anyerror!i32 {
    const s = c.data(State);
    const info = s.bindings[@intCast(idx)];
    const n = info.node;
    const rt = s.rt;
    const marks_base = s.marks.items.len;
    defer s.marks.shrinkRetainingCapacity(marks_base);
    var frame: env_mod.BindingFrame = .{};
    defer frame.bindings.deinit(rt.gpa);
    for (n.pairs, 0..) |pair, i| {
        const v = callThunk(s, info.init_ids[i]) catch |e| return s.fail(e);
        frame.bindings.put(rt.gpa, pair.var_ptr, v) catch |e| return s.fail(e);
    }
    for (n.pairs) |pair| {
        if (!pair.var_ptr.flags.dynamic) {
            var name_buf: [512]u8 = undefined;
            const qualified = std.fmt.bufPrint(&name_buf, "{s}/{s}", .{ pair.var_ptr.ns.name, pair.var_ptr.name }) catch pair.var_ptr.name;
            return s.fail(error_catalog.raise(.binding_target_not_dynamic, n.loc, .{ .@"var" = qualified }));
        }
    }
    env_mod.pushFrame(&frame);
    defer s.env.refreshCurrentNs();
    defer env_mod.popFrame();
    s.env.refreshCurrentNs();
    const v = callThunk(s, info.body_id) catch |e| return s.fail(e);
    return s.push(v) catch |e| s.fail(e);
}

/// Run an exported thunk and return its Value; a failure yields the REAL error
/// (the one stashed by the failing host import), clearing the stash.
fn callThunk(s: *State, id: u32) anyerror!Value {
    var buf: [16]u8 = undefined;
    const name = std.fmt.bufPrint(&buf, "m{d}", .{id}) catch unreachable;
    const MainFn = fn () i32;
    const h = s.inst.?.typedFunc(MainFn, name).call(.{}) catch |e| return realError(s, e);
    return s.handles.items[@intCast(h)];
}

fn catchMatches(rt: *Runtime, target: node_mod.TryNode.CatchTarget, thrown: Value) !bool {
    return switch (target) {
        .class_name => |name| host_class.matches(thrown, name),
        .type_keyword => |kw_val| blk: {
            if (thrown.tag() != .ex_info) break :blk false;
            const data_v = ex_info_collection.data(thrown);
            const type_kw = (try keyword_mod.intern(rt, null, "type"));
            const got = map_collection.get(data_v, type_kw) catch break :blk false;
            break :blk @intFromEnum(got) == @intFromEnum(kw_val);
        },
    };
}

fn hThrow(c: *Caller, h: i32) anyerror!i32 {
    const s = c.data(State);
    const v = s.handles.items[@intCast(h)];
    dispatch.last_thrown_exception = v;
    ex_info_collection.stampTraceIfAbsent(s.rt, v, error_mod.currentStack());
    dispatch.last_thrown_context = error_mod.snapshotContext();
    return s.fail(error.ThrownValue);
}

/// Port of TreeWalk `evalTry` (same catch/finally/uncatchable semantics) with
/// each sub-body run as a WASM thunk.
fn tryImpl(s: *State, info: TryInfo) anyerror!Value {
    const marks_base = s.marks.items.len;
    defer s.marks.shrinkRetainingCapacity(marks_base);
    const n = info.node;
    if (callThunk(s, info.body_id)) |result| {
        if (info.finally_id) |f| _ = try callThunk(s, f);
        return result;
    } else |err| {
        var thrown: ?Value = null;
        if (err == error.ThrownValue) {
            thrown = dispatch.last_thrown_exception orelse return error.ThrownValue;
        } else if (error_mod.peekLastError()) |ei| {
            if (host_class.kindToHostClass(ei.kind)) |class| {
                const synth = try ex_info_collection.allocExceptionLoc(s.rt, ei.message, class, ei.location, ei.trace);
                dispatch.last_thrown_exception = synth;
                error_mod.clearLastError();
                thrown = synth;
            }
        }
        if (thrown) |tv| {
            for (n.catch_clauses, 0..) |cc, k| {
                if (try catchMatches(s.rt, cc.target, tv)) {
                    dispatch.last_thrown_exception = null;
                    dispatch.last_thrown_context = null;
                    if (cc.binding_index >= s.locals.len)
                        return error_catalog.raise(.slot_out_of_range, cc.loc, .{ .form = "catch", .index = cc.binding_index, .max = s.locals.len });
                    s.locals[cc.binding_index] = tv;
                    const caught = callThunk(s, info.catch_ids[k]);
                    if (info.finally_id) |f| _ = try callThunk(s, f);
                    return caught;
                }
            }
            if (info.finally_id) |f| _ = try callThunk(s, f);
            return error.ThrownValue;
        }
        if (info.finally_id) |f| _ = callThunk(s, f) catch {};
        return err;
    }
}

fn hTry(c: *Caller, idx: i32) anyerror!i32 {
    const s = c.data(State);
    const v = tryImpl(s, s.tries[@intCast(idx)]) catch |e| return s.fail(e);
    return s.push(v) catch |e| s.fail(e);
}

fn hDef(c: *Caller, value_h: i32, meta_h: i32, node_idx: i32) anyerror!i32 {
    const s = c.data(State);
    const n = s.nodes[@intCast(node_idx)].def_node;
    const env = s.env;
    const ns = env.current_ns orelse
        return s.fail(error_catalog.raiseInternal(n.loc, "def: no current namespace"));
    const var_ptr = (if (n.has_init)
        env.intern(ns, n.name, s.handles.items[@intCast(value_h)], null)
    else
        env.internDeclare(ns, n.name)) catch |e| return s.fail(e);
    var_ptr.flags.dynamic = n.is_dynamic;
    var_ptr.flags.macro_ = n.is_macro;
    var_ptr.flags.private = n.is_private;
    if (n.meta_expr != null) var_ptr.meta = s.handles.items[@intCast(meta_h)];
    return s.push(Value.encodeHeapPtr(.var_ref, var_ptr)) catch |e| s.fail(e);
}

fn hLitBegin(c: *Caller, kind: i32) anyerror!void {
    const s = c.data(State);
    try s.builders.append(s.gpa, .{ .kind = @intCast(kind), .items = .empty });
}
fn hLitAdd(c: *Caller, h: i32) anyerror!void {
    const s = c.data(State);
    const b = &s.builders.items[s.builders.items.len - 1];
    try b.items.append(s.gpa, s.handles.items[@intCast(h)]);
}
fn hLitEnd(c: *Caller) anyerror!i32 {
    const s = c.data(State);
    var b = s.builders.pop().?;
    defer b.items.deinit(s.gpa);
    const rt = s.rt;
    const v: Value = blk: {
        switch (b.kind) {
            0 => {
                var v = vector_collection.empty();
                for (b.items.items) |e| v = vector_collection.conj(rt, v, e) catch |er| return s.fail(er);
                break :blk v;
            },
            1 => {
                var m = map_collection.empty();
                var i: usize = 0;
                while (i + 1 < b.items.items.len) : (i += 2)
                    m = map_collection.assoc(rt, m, b.items.items[i], b.items.items[i + 1]) catch |er| return s.fail(er);
                break :blk m;
            },
            else => {
                var st = set_collection.empty();
                for (b.items.items) |e| st = set_collection.conj(rt, st, e) catch |er| return s.fail(er);
                break :blk st;
            },
        }
    };
    return s.push(v) catch |e| s.fail(e);
}

/// Per-method native body: which exported WASM function runs this method.
const MethodRef = struct {
    state: *State,
    export_name: []const u8,
    body: tree_walk.NativeBody,
};

fn runMethod(ctx: *anyopaque, rt: *Runtime, env: *Env, locals: []Value) anyerror!Value {
    _ = rt;
    const ref: *MethodRef = @ptrCast(@alignCast(ctx));
    // Same native-stack budget TreeWalk enforces: a catchable StackOverflowError
    // instead of a segfault on runaway recursion.
    {
        const sp = @frameAddress();
        if (root_set.conservative_stack_top == 0 or sp > root_set.conservative_stack_top) {
            root_set.conservative_stack_top = sp;
        } else if (root_set.conservative_stack_top - sp > STACK_BUDGET_BYTES) {
            return error_catalog.raise(.stack_overflow, .{}, .{ .max = STACK_BUDGET_BYTES });
        }
    }
    var s = try ref.state.forThread();
    while (s.depth >= MAX_WASM_DEPTH) s = try s.child();
    try s.ensureLive();
    s.depth += 1;
    defer s.depth -= 1;
    const saved_locals = s.locals;
    const saved_env = s.env;
    const base = s.handles.items.len;
    const marks_base = s.marks.items.len;
    s.locals = locals;
    s.env = env;
    // Publish the handle table to the GC for the activation's extent.
    var gf: root_set.EvalFrame = .{ .stack = s.handles.items.ptr, .sp = &s.hlen, .locals = &.{}, .parent = root_set.eval_frame_head };
    root_set.eval_frame_head = &gf;
    defer {
        root_set.eval_frame_head = gf.parent;
        s.locals = saved_locals;
        s.env = saved_env;
        s.truncate(base);
        s.marks.shrinkRetainingCapacity(marks_base);
    }
    const MainFn = fn () i32;
    const h = s.inst.?.typedFunc(MainFn, ref.export_name).call(.{}) catch |e| return realError(s, e);
    return s.handles.items[@intCast(h)];
}

fn hMakeFn(c: *Caller, fn_idx: i32) anyerror!i32 {
    const s = c.data(State);
    const info = s.fns[@intCast(fn_idx)];
    const fnode = info.node.fn_node;
    const v = tree_walk.allocFunction(s.rt, fnode, s.locals) catch |e| return s.fail(e);
    const f = v.decodePtr(*tree_walk.Function);
    const methods: []tree_walk.FunctionMethod = @constCast(f.methods);
    for (methods, 0..) |*m, k| m.native = try s.methodBody(info.method_ids[k]);
    if (f.variadic) |*vm| {
        const mm: *tree_walk.FunctionMethod = @constCast(vm);
        mm.native = try s.methodBody(info.variadic_id.?);
    }
    return s.push(v) catch |e| s.fail(e);
}

fn hLocalGet(c: *Caller, idx: i32) anyerror!i32 {
    const s = c.data(State);
    return s.push(s.locals[@intCast(idx)]) catch |e| s.fail(e);
}
fn hLocalSet(c: *Caller, h: i32, idx: i32) anyerror!void {
    const s = c.data(State);
    s.locals[@intCast(idx)] = s.handles.items[@intCast(h)];
}
fn hVar(c: *Caller, idx: i32) anyerror!i32 {
    const s = c.data(State);
    return s.push(s.vars[@intCast(idx)].deref()) catch |e| s.fail(e);
}
fn hTruthy(c: *Caller, h: i32) anyerror!i32 {
    const s = c.data(State);
    return @intFromBool(s.handles.items[@intCast(h)].isTruthy());
}
fn hEval(c: *Caller, node_idx: i32) anyerror!i32 {
    const s = c.data(State);
    const v = tree_walk.eval(s.rt, s.env, s.locals, s.nodes[@intCast(node_idx)]) catch |e| return s.fail(e);
    return s.push(v) catch |e| s.fail(e);
}
/// Call with an unbounded argument count: arguments collected in a builder.
fn hCallV(c: *Caller, f: i32, node_idx: i32) anyerror!i32 {
    const s = c.data(State);
    var b = s.builders.pop().?;
    defer b.items.deinit(s.gpa);
    return s.doCallV(s.handles.items[@intCast(f)], b.items.items, node_idx);
}
fn hCall0(c: *Caller, f: i32, n: i32) anyerror!i32 {
    return c.data(State).doCall(f, &.{}, n);
}
fn hCall1(c: *Caller, f: i32, a: i32, n: i32) anyerror!i32 {
    return c.data(State).doCall(f, &.{a}, n);
}
fn hCall2(c: *Caller, f: i32, a: i32, b: i32, n: i32) anyerror!i32 {
    return c.data(State).doCall(f, &.{ a, b }, n);
}
fn hCall3(c: *Caller, f: i32, a: i32, b: i32, d: i32, n: i32) anyerror!i32 {
    return c.data(State).doCall(f, &.{ a, b, d }, n);
}
fn hCall4(c: *Caller, f: i32, a: i32, b: i32, d: i32, e: i32, n: i32) anyerror!i32 {
    return c.data(State).doCall(f, &.{ a, b, d, e }, n);
}
fn hCall5(c: *Caller, f: i32, a: i32, b: i32, d: i32, e: i32, g: i32, n: i32) anyerror!i32 {
    return c.data(State).doCall(f, &.{ a, b, d, e, g }, n);
}
fn hCall6(c: *Caller, f: i32, a: i32, b: i32, d: i32, e: i32, g: i32, i: i32, n: i32) anyerror!i32 {
    return c.data(State).doCall(f, &.{ a, b, d, e, g, i }, n);
}
fn hCall7(c: *Caller, f: i32, a: i32, b: i32, d: i32, e: i32, g: i32, i: i32, j: i32, n: i32) anyerror!i32 {
    return c.data(State).doCall(f, &.{ a, b, d, e, g, i, j }, n);
}

const prelude =
    \\(module
    \\(import "h" "local_get" (func $local_get (param i32) (result i32)))
    \\(import "h" "local_set" (func $local_set (param i32 i32)))
    \\(import "h" "truthy" (func $truthy (param i32) (result i32)))
    \\(import "h" "eval" (func $eval (param i32) (result i32)))
    \\(import "h" "call0" (func $call0 (param i32 i32) (result i32)))
    \\(import "h" "call1" (func $call1 (param i32 i32 i32) (result i32)))
    \\(import "h" "call2" (func $call2 (param i32 i32 i32 i32) (result i32)))
    \\(import "h" "call3" (func $call3 (param i32 i32 i32 i32 i32) (result i32)))
    \\(import "h" "call4" (func $call4 (param i32 i32 i32 i32 i32 i32) (result i32)))
    \\(import "h" "call5" (func $call5 (param i32 i32 i32 i32 i32 i32 i32) (result i32)))
    \\(import "h" "call6" (func $call6 (param i32 i32 i32 i32 i32 i32 i32 i32) (result i32)))
    \\(import "h" "call7" (func $call7 (param i32 i32 i32 i32 i32 i32 i32 i32 i32) (result i32)))
    \\(import "h" "callv" (func $callv (param i32 i32) (result i32)))
    \\(import "h" "make_fn" (func $make_fn (param i32) (result i32)))
    \\(import "h" "var" (func $var (param i32) (result i32)))
    \\(import "h" "throw" (func $throw (param i32) (result i32)))
    \\(import "h" "try" (func $try (param i32) (result i32)))
    \\(import "h" "def" (func $def (param i32 i32 i32) (result i32)))
    \\(import "h" "lit_begin" (func $lit_begin (param i32)))
    \\(import "h" "lit_add" (func $lit_add (param i32)))
    \\(import "h" "lit_end" (func $lit_end (result i32)))
    \\(import "h" "apply" (func $apply (param i32) (result i32)))
    \\(import "h" "binding" (func $binding (param i32) (result i32)))
    \\(import "h" "letfn_patch" (func $letfn_patch (param i32 i32)))
    \\(import "h" "loop_mark" (func $loop_mark))
    \\(import "h" "loop_reset" (func $loop_reset))
    \\(import "h" "loop_end" (func $loop_end))
    \\
;

fn defineImports(linker: *zwasm.Linker, s: *State) !void {
    const p: *anyopaque = s;
    try linker.defineFuncCtx("h", "local_get", p, fn (*Caller, i32) anyerror!i32, hLocalGet);
    try linker.defineFuncCtx("h", "local_set", p, fn (*Caller, i32, i32) anyerror!void, hLocalSet);
    try linker.defineFuncCtx("h", "truthy", p, fn (*Caller, i32) anyerror!i32, hTruthy);
    try linker.defineFuncCtx("h", "eval", p, fn (*Caller, i32) anyerror!i32, hEval);
    try linker.defineFuncCtx("h", "make_fn", p, fn (*Caller, i32) anyerror!i32, hMakeFn);
    try linker.defineFuncCtx("h", "var", p, fn (*Caller, i32) anyerror!i32, hVar);
    try linker.defineFuncCtx("h", "throw", p, fn (*Caller, i32) anyerror!i32, hThrow);
    try linker.defineFuncCtx("h", "try", p, fn (*Caller, i32) anyerror!i32, hTry);
    try linker.defineFuncCtx("h", "def", p, fn (*Caller, i32, i32, i32) anyerror!i32, hDef);
    try linker.defineFuncCtx("h", "lit_begin", p, fn (*Caller, i32) anyerror!void, hLitBegin);
    try linker.defineFuncCtx("h", "lit_add", p, fn (*Caller, i32) anyerror!void, hLitAdd);
    try linker.defineFuncCtx("h", "lit_end", p, fn (*Caller) anyerror!i32, hLitEnd);
    try linker.defineFuncCtx("h", "apply", p, fn (*Caller, i32) anyerror!i32, hApply);
    try linker.defineFuncCtx("h", "binding", p, fn (*Caller, i32) anyerror!i32, hBinding);
    try linker.defineFuncCtx("h", "letfn_patch", p, fn (*Caller, i32, i32) anyerror!void, hLetfnPatch);
    try linker.defineFuncCtx("h", "loop_mark", p, fn (*Caller) anyerror!void, hLoopMark);
    try linker.defineFuncCtx("h", "loop_reset", p, fn (*Caller) anyerror!void, hLoopReset);
    try linker.defineFuncCtx("h", "loop_end", p, fn (*Caller) anyerror!void, hLoopEnd);
    try linker.defineFuncCtx("h", "call0", p, fn (*Caller, i32, i32) anyerror!i32, hCall0);
    try linker.defineFuncCtx("h", "call1", p, fn (*Caller, i32, i32, i32) anyerror!i32, hCall1);
    try linker.defineFuncCtx("h", "call2", p, fn (*Caller, i32, i32, i32, i32) anyerror!i32, hCall2);
    try linker.defineFuncCtx("h", "call3", p, fn (*Caller, i32, i32, i32, i32, i32) anyerror!i32, hCall3);
    try linker.defineFuncCtx("h", "call4", p, fn (*Caller, i32, i32, i32, i32, i32, i32) anyerror!i32, hCall4);
    try linker.defineFuncCtx("h", "call5", p, fn (*Caller, i32, i32, i32, i32, i32, i32, i32) anyerror!i32, hCall5);
    try linker.defineFuncCtx("h", "call6", p, fn (*Caller, i32, i32, i32, i32, i32, i32, i32, i32) anyerror!i32, hCall6);
    try linker.defineFuncCtx("h", "call7", p, fn (*Caller, i32, i32, i32, i32, i32, i32, i32, i32, i32) anyerror!i32, hCall7);
    try linker.defineFuncCtx("h", "callv", p, fn (*Caller, i32, i32) anyerror!i32, hCallV);
}

/// Compile one top-level `Node` to WAT text. Exposed for diagnostics.
fn compileToWat(arena: std.mem.Allocator, node: *const Node, c: *Compiler) CompileError![]const u8 {
    c.* = .{ .arena = arena };
    try c.expr(node);
    const body = c.out;
    c.out = .empty;
    try c.out.appendSlice(arena, prelude);
    try c.out.appendSlice(arena, c.funcs.items);
    try c.out.appendSlice(arena, "(func $__repl_expr (export \"__repl_expr\") (result i32)\n");
    try c.out.appendSlice(arena, body.items);
    try c.out.appendSlice(arena, ")\n)\n");
    return c.out.items;
}

var wasm_tools_path: ?[]const u8 = null;

/// Locate `wasm-tools` through the real process PATH (libc), caching the
/// absolute path: Zig's spawn resolves argv[0] via the Io's environment, which
/// is empty under `zig build test`.
fn wasmToolsPath() []const u8 {
    if (wasm_tools_path) |p| return p;
    const gpa = std.heap.page_allocator;
    var found: []const u8 = "wasm-tools";
    if (std.c.getenv("PATH")) |path_z| {
        var it = std.mem.splitScalar(u8, std.mem.span(path_z), ':');
        while (it.next()) |dir| {
            if (dir.len == 0) continue;
            const cand = std.fmt.allocPrintSentinel(gpa, "{s}/wasm-tools", .{dir}, 0) catch continue;
            if (std.c.access(cand.ptr, std.c.X_OK) == 0) {
                found = cand[0..cand.len];
                break;
            }
            gpa.free(cand);
        }
    }
    wasm_tools_path = found;
    return found;
}

/// Evaluate one top-level form on the WasmGC backend.
pub fn evalNode(
    rt: *Runtime,
    env: *Env,
    locals: []Value,
    arena: std.mem.Allocator,
    node: *const Node,
) anyerror!Value {
    var comp: Compiler = undefined;
    const wat = try compileToWat(arena, node, &comp);

    const pid: i32 = std.c.getpid();
    const wat_path = try std.fmt.allocPrint(arena, "/tmp/cljw_wasmgc_{d}.wat", .{pid});
    const wasm_path = try std.fmt.allocPrint(arena, "/tmp/cljw_wasmgc_{d}.wasm", .{pid});
    {
        const file = try std.Io.Dir.cwd().createFile(rt.io, wat_path, .{});
        defer file.close(rt.io);
        var buf: [4096]u8 = undefined;
        var fw = file.writer(rt.io, &buf);
        try fw.interface.writeAll(wat);
        try fw.flush();
    }
    const res = try std.process.run(arena, rt.io, .{
        .argv = &[_][]const u8{ wasmToolsPath(), "parse", wat_path, "-o", wasm_path },
    });
    if (res.term != .exited or res.term.exited != 0) {
        std.debug.print("wasm-tools parse failed:\n{s}\n--- WAT ---\n{s}\n", .{ res.stderr, wat });
        return error.WasmConversionFailed;
    }
    const wasm_bytes = try file_io.readAll(rt.io, arena, wasm_path);

    const gpa = std.heap.page_allocator;
    if (comp.consts.items.len + 1024 > HANDLE_CAP) return error.WasmgcHandleOverflow;
    const state = try gpa.create(State);
    state.* = .{
        .rt = rt,
        .env = env,
        .locals = locals,
        .handles = .empty,
        .nodes = try gpa.dupe(*const Node, comp.nodes.items),
        .vars = try gpa.dupe(*const Var, comp.vars.items),
        .fns = try gpa.dupe(FnInfo, comp.fns.items),
        .tries = try gpa.dupe(TryInfo, comp.tries.items),
        .bindings = try gpa.dupe(BindInfo, comp.bindings.items),
        .gpa = gpa,
        .consts = try gpa.dupe(Value, comp.consts.items),
        .wasm_bytes = try gpa.dupe(u8, wasm_bytes),
    };
    state.root = state;
    state.owner = &tl_marker;
    try state.revive();
    const inst = state.inst.?;

    const MainFn = fn () i32;
    // A form that defines no function leaves nothing referencing its instance
    // after it returns, so release everything (long loads like core.clj would
    // otherwise leak an engine + instance + handle table per form). Forms that
    // do define functions stay registered for LRU eviction (`MAX_LIVE_INSTANCES`).
    const escapes = comp.fns.items.len != 0;
    defer if (!escapes) {
        state.evict();
        state.builders.deinit(gpa);
        state.marks.deinit(gpa);
        gpa.free(state.nodes);
        gpa.free(state.vars);
        gpa.free(state.fns);
        gpa.free(state.tries);
        gpa.free(state.bindings);
        gpa.free(state.consts);
        gpa.free(state.wasm_bytes);
        gpa.destroy(state);
    };
    var gf: root_set.EvalFrame = .{ .stack = state.handles.items.ptr, .sp = &state.hlen, .locals = &.{}, .parent = root_set.eval_frame_head };
    root_set.eval_frame_head = &gf;
    defer root_set.eval_frame_head = gf.parent;
    if (escapes) {
        try tl_live.append(gpa, state);
        State.trimLive(state);
    }
    // Busy while its top-level code runs, so it is never evicted mid-run.
    state.depth += 1;
    defer state.depth -= 1;
    const main_fn = inst.typedFunc(MainFn, "__repl_expr");
    const h = main_fn.call(.{}) catch |e| return realError(state, e);
    const result = state.handles.items[@intCast(h)];
    // Drop the form's own temporaries (they would otherwise stay GC-rooted).
    if (escapes) state.truncate(state.consts.len);
    return result;
}
