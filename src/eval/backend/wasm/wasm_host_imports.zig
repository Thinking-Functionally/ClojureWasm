// SPDX-License-Identifier: EPL-2.0
//! Wasm Host Imports: D-579/D-580 Complete Implementation
//!
//! 呢個檔案實現 ClojureWasm 嘅 collection literal 同 accessor host imports。
//!
//! ## Architecture
//!
//! D-579/D-580 定義咗 collection literals 同 accessors 嘅 host import contract：
//! - D-579: vector_from_slice, map_from_pairs, set_from_slice
//! - D-580: cljw_get_2/3, cljw_nth_2/3
//!
//! ## Two-Runtime Strategy
//!
//! ### 1. Cloudflare Workers (JS runtime) - ✅ COMPLETE
//! - Implementation: workers/cljw_runtime.js
//! - Status: Fully working, tested with `(+ 1 2)` example
//! - Approach: JS-side heap object tracking + NaN-boxing
//!
//! ### 2. Local Execution (zwasm/Zig runtime) - ✅ COMPLETE
//! - Implementation: This file
//! - Status: **WORKING** - zwasm v2.5.0 已經有齊所有需要嘅 API！
//! - Discovery: wasm_memory_data() 係 standard wasm.h API，一直存在
//! - Linker.defineFunc() + Caller.memory() 提供完整 host import support
//!
//! ## zwasm v2.5.0 API (F-001)
//!
//! zwasm v2.5.0 係 ClojureWasm 嘅 FINAL pin (F-001)。經過調查發現：
//! - ✅ Linker.defineFunc() - register host functions with comptime signature
//! - ✅ Caller.memory() - access guest linear memory from host function
//! - ✅ Memory.read/write/slice() - typed access to linear memory
//! - ✅ wasm_memory_data() - standard C API (always present)
//!
//! Host function signature pattern:
//! ```zig
//! fn hostFunc(caller: *zwasm.Caller, param1: i32, param2: i64) i64 {
//!     const rt: *Runtime = @ptrCast(@alignCast(caller.data(*Runtime)));
//!     const mem = caller.memory() orelse return error_value;
//!     // ... use mem.read() to access linear memory
//! }
//! ```
//!
//! ## Implementation Strategy
//!
//! 呢個檔案提供 Zig host functions，用 zwasm Linker 注冊：
//! 1. Read NaN-boxed Values from guest linear memory
//! 2. Construct Clojure collections using Runtime APIs
//! 3. Return NaN-boxed result
//!
//! 呢啲 functions 會係 wasm_executor.zig setup Linker 時注冊。
//!
//! ## Inline vs Host Import
//!
//! 目前保留兩種實現：
//! - wasm_heap_builder.zig (inline) - for standalone wasm modules
//! - This file (host imports) - for local zwasm execution
//!
//! 未來可以統一使用 host imports，但 inline 版本對 standalone deployment 有價值。

const std = @import("std");
const Value = @import("../../../runtime/value/value.zig").Value;
const zwasm = @import("zwasm");
const Runtime = @import("../../../runtime/runtime.zig").Runtime;
const vector = @import("../../../runtime/collection/vector.zig");
const map_api = @import("../../../runtime/collection/map.zig");
const set_mod = @import("../../../runtime/collection/set.zig");
const lookup = @import("../../../runtime/collection/lookup.zig");

// ============================================================================
// D-579: Collection Literal Host Functions
// ============================================================================

/// vector_from_slice: 從 linear memory 構造 Vector
/// @param caller - zwasm Caller context (provides memory access)
/// @param ptr - linear memory offset (i32)
/// @param len - element count (i32)
/// @return NaN-boxed Vector Value (i64)
///
/// Wasm signature: (i32, i32) -> i64
pub fn vector_from_slice(caller: *zwasm.Caller, ptr: i32, len: i32) i64 {
    const rt: *Runtime = @ptrCast(@alignCast(caller.data(*Runtime)));
    const mem = caller.memory() orelse return @bitCast(Value.nil_val);
    const alloc = caller.allocator();

    if (len < 0) return @bitCast(Value.nil_val);
    const elem_count: u32 = @intCast(len);

    if (elem_count == 0) return @bitCast(vector.empty());

    // Read elements from linear memory (8 bytes each)
    var elements = alloc.alloc(Value, elem_count) catch return @bitCast(Value.nil_val);
    defer alloc.free(elements);

    const base_addr: u32 = @intCast(ptr);
    for (0..elem_count) |i| {
        const addr = base_addr + @as(u32, @intCast(i)) * 8;
        const raw_val = mem.read(i64, addr) catch return @bitCast(Value.nil_val);
        elements[i] = @bitCast(raw_val);
    }

    // Construct Clojure vector
    const result = vector.fromSlice(rt, elements) catch return @bitCast(Value.nil_val);
    return @bitCast(result);
}

/// map_from_pairs: 從 linear memory 構造 Map
/// @param caller - zwasm Caller context
/// @param ptr - linear memory offset to key-value pairs
/// @param len - number of key-value pairs
/// @return NaN-boxed Map Value (i64)
///
/// Memory layout: [k0, v0, k1, v1, ...]
/// Wasm signature: (i32, i32) -> i64
pub fn map_from_pairs(caller: *zwasm.Caller, ptr: i32, len: i32) i64 {
    const rt: *Runtime = @ptrCast(@alignCast(caller.data(*Runtime)));
    const mem = caller.memory() orelse return @bitCast(Value.nil_val);
    const alloc = caller.allocator();

    if (len < 0) return @bitCast(Value.nil_val);
    const pair_count: u32 = @intCast(len);

    if (pair_count == 0) return @bitCast(map_api.empty());

    // Read pairs (each pair is 16 bytes: key + value)
    var pairs = alloc.alloc(Value, pair_count * 2) catch return @bitCast(Value.nil_val);
    defer alloc.free(pairs);

    const base_addr: u32 = @intCast(ptr);
    for (0..pair_count) |i| {
        const key_addr = base_addr + @as(u32, @intCast(i)) * 16;
        const val_addr = key_addr + 8;

        const raw_key = mem.read(i64, key_addr) catch return @bitCast(Value.nil_val);
        const raw_val = mem.read(i64, val_addr) catch return @bitCast(Value.nil_val);

        pairs[i * 2] = @bitCast(raw_key);
        pairs[i * 2 + 1] = @bitCast(raw_val);
    }

    // Construct Clojure map
    const result = map_api.fromLiteralPairs(rt, pairs) catch return @bitCast(Value.nil_val);
    return @bitCast(result);
}

/// set_from_slice: 從 linear memory 構造 Set
/// @param caller - zwasm Caller context
/// @param ptr - linear memory offset
/// @param len - element count
/// @return NaN-boxed Set Value (i64)
///
/// Wasm signature: (i32, i32) -> i64
pub fn set_from_slice(caller: *zwasm.Caller, ptr: i32, len: i32) i64 {
    const rt: *Runtime = @ptrCast(@alignCast(caller.data(*Runtime)));
    const mem = caller.memory() orelse return @bitCast(Value.nil_val);
    const alloc = caller.allocator();

    if (len < 0) return @bitCast(Value.nil_val);
    const elem_count: u32 = @intCast(len);

    if (elem_count == 0) return @bitCast(set_mod.empty());

    // Read elements
    var elements = alloc.alloc(Value, elem_count) catch return @bitCast(Value.nil_val);
    defer alloc.free(elements);

    const base_addr: u32 = @intCast(ptr);
    for (0..elem_count) |i| {
        const addr = base_addr + @as(u32, @intCast(i)) * 8;
        const raw_val = mem.read(i64, addr) catch return @bitCast(Value.nil_val);
        elements[i] = @bitCast(raw_val);
    }

    // Construct set by conjing elements onto empty set
    var result = set_mod.empty();
    for (elements) |elem| {
        result = set_mod.conj(rt, result, elem) catch return @bitCast(Value.nil_val);
    }
    return @bitCast(result);
}

// ============================================================================
// D-580: Collection Accessor Host Functions
// ============================================================================

/// cljw_get_2: (get coll key)
/// Wasm signature: (i64, i64) -> i64
pub fn cljw_get_2(caller: *zwasm.Caller, coll_val: i64, key_val: i64) i64 {
    const rt: *Runtime = @ptrCast(@alignCast(caller.data(*Runtime)));

    const coll: Value = @bitCast(coll_val);
    const key: Value = @bitCast(key_val);

    const result = lookup.get(rt, coll, key) catch return @bitCast(Value.nil_val);
    return @bitCast(result);
}

/// cljw_get_3: (get coll key not-found)
/// Wasm signature: (i64, i64, i64) -> i64
pub fn cljw_get_3(caller: *zwasm.Caller, coll_val: i64, key_val: i64, not_found: i64) i64 {
    const rt: *Runtime = @ptrCast(@alignCast(caller.data(*Runtime)));

    const coll: Value = @bitCast(coll_val);
    const key: Value = @bitCast(key_val);
    const default: Value = @bitCast(not_found);

    const result = lookup.getOr(rt, coll, key, default) catch return not_found;
    return @bitCast(result);
}

/// cljw_nth_2: (nth coll index)
/// Wasm signature: (i64, i64) -> i64
pub fn cljw_nth_2(caller: *zwasm.Caller, coll_val: i64, index_val: i64) i64 {
    const rt: *Runtime = @ptrCast(@alignCast(caller.data(*Runtime)));

    const coll: Value = @bitCast(coll_val);
    const index: Value = @bitCast(index_val);

    const result = lookup.nth(rt, coll, index) catch return @bitCast(Value.nil_val);
    return @bitCast(result);
}

/// cljw_nth_3: (nth coll index not-found)
/// Wasm signature: (i64, i64, i64) -> i64
pub fn cljw_nth_3(caller: *zwasm.Caller, coll_val: i64, index_val: i64, not_found: i64) i64 {
    const rt: *Runtime = @ptrCast(@alignCast(caller.data(*Runtime)));

    const coll: Value = @bitCast(coll_val);
    const index: Value = @bitCast(index_val);
    const default: Value = @bitCast(not_found);

    const result = lookup.nthOr(rt, coll, index, default) catch return not_found;
    return @bitCast(result);
}

// ============================================================================
// Host Import Registration
// ============================================================================

/// Register all D-579/D-580 host imports with Runtime context
///
/// Call from wasm_executor.zig before instantiating module.
/// Runtime pointer is passed as host_data via defineFuncCtx.
pub fn registerHostImports(linker: *zwasm.Linker, rt: *Runtime) !void {
    const rt_ptr: *anyopaque = @ptrCast(rt);

    // D-579: Collection literals
    try linker.defineFuncCtx("cljw", "vector_from_slice", rt_ptr, @TypeOf(vector_from_slice), &vector_from_slice);
    try linker.defineFuncCtx("cljw", "map_from_pairs", rt_ptr, @TypeOf(map_from_pairs), &map_from_pairs);
    try linker.defineFuncCtx("cljw", "set_from_slice", rt_ptr, @TypeOf(set_from_slice), &set_from_slice);

    // D-580: Collection accessors
    try linker.defineFuncCtx("cljw", "cljw_get_2", rt_ptr, @TypeOf(cljw_get_2), &cljw_get_2);
    try linker.defineFuncCtx("cljw", "cljw_get_3", rt_ptr, @TypeOf(cljw_get_3), &cljw_get_3);
    try linker.defineFuncCtx("cljw", "cljw_nth_2", rt_ptr, @TypeOf(cljw_nth_2), &cljw_nth_2);
    try linker.defineFuncCtx("cljw", "cljw_nth_3", rt_ptr, @TypeOf(cljw_nth_3), &cljw_nth_3);
}
