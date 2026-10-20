// SPDX-License-Identifier: EPL-2.0
//! Wasm Host Imports Implementation
//!
//! 實現 D-579/D-580 需要嘅 host functions：
//! - Collection literals (vector_from_slice, map_from_pairs, set_from_slice)
//! - Collection accessors (cljw_get_2, cljw_get_3, cljw_nth_2, cljw_nth_3)
//!
//! 呢啲 functions 可以用於：
//! 1. zwasm 本地執行（當 zwasm 支持 instantiate-with-imports）
//! 2. Cloudflare Workers JS binding（透過 JS wrapper）

const std = @import("std");
const Value = @import("../../runtime/value/value.zig").Value;
const Vec = @import("../../runtime/value/vector.zig").Vec;
const PersistentHashMap = @import("../../runtime/value/hash_map.zig").PersistentHashMap;
const PersistentHashSet = @import("../../runtime/value/hash_set.zig").PersistentHashSet;
const Runtime = @import("../../runtime/runtime.zig").Runtime;

/// Host imports context - 保存 runtime 引用
pub const HostContext = struct {
    rt: *Runtime,
    allocator: std.mem.Allocator,
};

/// D-579: vector_from_slice
/// 從 linear memory 讀取 Value slice，構造 Vector
/// @param ctx: HostContext pointer (type-erased)
/// @param ptr: linear memory offset (i32)
/// @param len: element count (i32)
/// @return NaN-boxed Value (i64)
pub fn vector_from_slice(ctx: *anyopaque, ptr: i32, len: i32) callconv(.C) i64 {
    const host_ctx: *HostContext = @ptrCast(@alignCast(ctx));

    // TODO(zwasm): read from wasm linear memory when zwasm supports host imports
    _ = ptr;
    _ = len;

    const empty_vec = Vec.empty(host_ctx.allocator) catch {
        return Value.nil().encode();
    };
    return Value.fromVec(empty_vec).encode();
}

/// D-579: map_from_pairs
/// 從 linear memory 讀取 key-value pairs，構造 Map
pub fn map_from_pairs(ctx: *anyopaque, ptr: i32, len: i32) callconv(.C) i64 {
    const host_ctx: *HostContext = @ptrCast(@alignCast(ctx));
    // TODO(zwasm): read from wasm linear memory when zwasm supports host imports
    _ = ptr;
    _ = len;

    const empty_map = PersistentHashMap.empty(host_ctx.allocator) catch {
        return Value.nil().encode();
    };
    return Value.fromMap(empty_map).encode();
}

/// D-579: set_from_slice
/// 從 linear memory 讀取 Value slice，構造 Set
pub fn set_from_slice(ctx: *anyopaque, ptr: i32, len: i32) callconv(.C) i64 {
    const host_ctx: *HostContext = @ptrCast(@alignCast(ctx));
    // TODO(zwasm): read from wasm linear memory when zwasm supports host imports
    _ = ptr;
    _ = len;

    const empty_set = PersistentHashSet.empty(host_ctx.allocator) catch {
        return Value.nil().encode();
    };
    return Value.fromSet(empty_set).encode();
}

/// D-580: cljw_get_2
/// (get map key) - 兩參數版本
pub fn cljw_get_2(ctx: *anyopaque, map_val: i64, key_val: i64) callconv(.C) i64 {
    _ = ctx;
    const map = Value.decode(map_val);
    const key = Value.decode(key_val);

    // TODO(zwasm): implement Map.get when zwasm supports host imports
    _ = map;
    _ = key;
    return Value.nil().encode();
}

/// D-580: cljw_get_3
/// (get map key not-found) - 三參數版本
pub fn cljw_get_3(ctx: *anyopaque, map_val: i64, key_val: i64, not_found: i64) callconv(.C) i64 {
    _ = ctx;
    _ = map_val;
    _ = key_val;
    // TODO(zwasm): implement Map.get when zwasm supports host imports
    return not_found;
}

/// D-580: cljw_nth_2
/// (nth coll index) - 兩參數版本
pub fn cljw_nth_2(ctx: *anyopaque, coll_val: i64, index: i32) callconv(.C) i64 {
    _ = ctx;
    const coll = Value.decode(coll_val);
    _ = coll;
    _ = index;
    // TODO(zwasm): implement Vec.nth when zwasm supports host imports
    return Value.nil().encode();
}

/// D-580: cljw_nth_3
/// (nth coll index not-found) - 三參數版本
pub fn cljw_nth_3(ctx: *anyopaque, coll_val: i64, index: i32, not_found: i64) callconv(.C) i64 {
    _ = ctx;
    _ = coll_val;
    _ = index;
    // TODO(zwasm): implement Vec.nth when zwasm supports host imports
    return not_found;
}

/// 創建 host function table（俾 zwasm 用）
pub fn createHostTable(allocator: std.mem.Allocator, rt: *Runtime) !HostContext {
    return HostContext{
        .rt = rt,
        .allocator = allocator,
    };
}
