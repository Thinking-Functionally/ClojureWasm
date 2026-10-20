// SPDX-License-Identifier: EPL-2.0
//! WASM Heap Builder: 生成 WASM 代碼喺 linear memory 構造 heap objects
//!
//! 呢個模組負責生成 WASM instructions 去：
//! 1. 呼叫 heap_alloc 分配 memory
//! 2. 寫入 HeapHeader (tag + flags + gc_and_lock)
//! 3. 寫入 collection data (count + elements/pairs)
//!
//! Simplified heap layout for WASM backend:
//! - Vector: [HeapHeader:8] [count:4] [_pad:4] [elements: count*8]
//! - Map:    [HeapHeader:8] [count:4] [_pad:4] [pairs: count*16]
//! - Set:    [HeapHeader:8] [count:4] [_pad:4] [elements: count*8]
//!
//! 呢個唔係 full persistent data structures，係 simplified representation
//! for standalone WASM execution. 但對 P99 tests 同 basic operations 已足夠。

const std = @import("std");
const Value = @import("../../../runtime/value/value.zig").Value;
const HeapTag = @import("../../../runtime/value/heap_tag.zig").HeapTag;

pub const HeapBuilderError = error{
    TooManyElements,
    InvalidTag,
} || std.mem.Allocator.Error;

/// Helper: 寫入 LEB128 unsigned integer
fn writeLEB128(list: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u32) !void {
    var v = value;
    while (true) {
        const byte: u8 = @intCast(v & 0x7F);
        v >>= 7;
        if (v == 0) {
            try list.append(allocator, byte);
            break;
        } else {
            try list.append(allocator, byte | 0x80);
        }
    }
}

/// 生成 WASM code 去分配並構造一個 Vector
///
/// Stack 輸入：[elem_0, elem_1, ..., elem_N-1] (N elements，每個係 i64 Value)
/// Stack 輸出：[vector_ptr] (i64 pointer to HeapHeader，NaN-boxed as heap Value)
///
/// 生成嘅 WASM code 會：
/// 1. Call heap_alloc(16 + N*8) -> base_ptr (i32)
/// 2. Write HeapHeader at base_ptr (8 bytes)
/// 3. Write count at base_ptr+8 (4 bytes)
/// 4. Write each element at base_ptr+16+i*8 (8 bytes each)
/// 5. Convert base_ptr to NaN-boxed heap pointer (i64)
pub fn emitVectorConstruction(
    allocator: std.mem.Allocator,
    element_count: u32,
) ![]const u8 {
    var code: std.ArrayList(u8) = .empty;
    defer code.deinit(allocator);

    // 計算需要嘅 total size: 16 (header+count+pad) + N*8 (elements)
    const header_size = 16; // HeapHeader(8) + count(4) + pad(4)
    const total_size = header_size + element_count * 8;

    // 儲存所有 elements 到 locals
    // 我哋需要 N 個 locals (type i64) 去儲存 elements
    // 同埋 1 個 local (type i32) 去儲存 base_ptr
    // Total: N i64 locals + 1 i32 local

    // WASM function locals declaration: compressed format
    // [num_local_groups:u32] [group_0_count:u32] [group_0_type:valtype] ...
    // 我哋有兩組: N × i64, 1 × i32
    try writeLEB128(&code, allocator, 2); // 2 groups
    try writeLEB128(&code, allocator, element_count); // group 0: N locals
    try code.append(allocator, 0x7E); // i64
    try writeLEB128(&code, allocator, 1); // group 1: 1 local
    try code.append(allocator, 0x7F); // i32

    // Store elements from stack to locals (reverse order: stack top -> local N-1)
    // Stack: [elem_0, ..., elem_N-1] (elem_N-1 on top)
    var i: u32 = element_count;
    while (i > 0) {
        i -= 1;
        // local.set i (store stack top to local i)
        try code.append(allocator, 0x21); // local.set
        try writeLEB128(&code, allocator, i);
    }
    // Now stack is empty, all elements in locals 0..N-1

    // Call heap_alloc(total_size)
    try code.append(allocator, 0x41); // i32.const
    try writeLEB128(&code, allocator, total_size);
    try code.append(allocator, 0x10); // call
    try writeLEB128(&code, allocator, 1); // function index 1 = heap_alloc

    // Store base_ptr to local N (last local)
    try code.append(allocator, 0x21); // local.set
    try writeLEB128(&code, allocator, element_count); // local index N

    // Write HeapHeader (8 bytes)
    // [tag:u8] [flags:u8] [pad:u16] [gc_and_lock:u32]
    // tag = HeapTag.vector_small = 8
    // flags = 0
    // gc_and_lock = 0
    const base_local = element_count;

    // base_ptr + 0: tag (u8)
    try code.append(allocator, 0x20); // local.get base_ptr
    try writeLEB128(&code, allocator, base_local);
    try code.append(allocator, 0x41); // i32.const (tag value)
    try writeLEB128(&code, allocator, @intFromEnum(HeapTag.vector_small));
    try code.append(allocator, 0x3A); // i32.store8
    try code.append(allocator, 0x00); // align=0
    try code.append(allocator, 0x00); // offset=0

    // base_ptr + 1: flags (u8)
    try code.append(allocator, 0x20); // local.get
    try writeLEB128(&code, allocator, base_local);
    try code.append(allocator, 0x41); // i32.const 0
    try writeLEB128(&code, allocator, 0);
    try code.append(allocator, 0x3A); // i32.store8
    try code.append(allocator, 0x00); // align=0
    try code.append(allocator, 0x01); // offset=1

    // base_ptr + 4: gc_and_lock (u32) - skip pad bytes 2-3
    try code.append(allocator, 0x20); // local.get
    try writeLEB128(&code, allocator, base_local);
    try code.append(allocator, 0x41); // i32.const 0
    try writeLEB128(&code, allocator, 0);
    try code.append(allocator, 0x36); // i32.store
    try code.append(allocator, 0x02); // align=2
    try code.append(allocator, 0x04); // offset=4

    // base_ptr + 8: count (u32)
    try code.append(allocator, 0x20); // local.get
    try writeLEB128(&code, allocator, base_local);
    try code.append(allocator, 0x41); // i32.const count
    try writeLEB128(&code, allocator, element_count);
    try code.append(allocator, 0x36); // i32.store
    try code.append(allocator, 0x02); // align=2
    try code.append(allocator, 0x08); // offset=8

    // Write elements at base_ptr + 16 + i*8
    i = 0;
    while (i < element_count) : (i += 1) {
        const elem_offset = 16 + i * 8;

        // base_ptr (address)
        try code.append(allocator, 0x20); // local.get
        try writeLEB128(&code, allocator, base_local);

        // element value (i64) from local i
        try code.append(allocator, 0x20); // local.get
        try writeLEB128(&code, allocator, i);

        // i64.store at base_ptr + elem_offset
        try code.append(allocator, 0x37); // i64.store
        try code.append(allocator, 0x03); // align=3 (8-byte aligned)
        try writeLEB128(&code, allocator, elem_offset);
    }

    // Convert base_ptr (i32) to NaN-boxed heap pointer (i64)
    // NaN-boxed heap pointer format: 0xFFFC_0000_0000_0000 | ptr_u48
    // where ptr_u48 = zero-extend(base_ptr)

    // local.get base_ptr
    try code.append(allocator, 0x20); // local.get
    try writeLEB128(&code, allocator, base_local);

    // i64.extend_i32_u (zero-extend to i64)
    try code.append(allocator, 0xAD);

    // i64.const 0xFFFC_0000_0000_0000
    try code.append(allocator, 0x42); // i64.const
    // LEB128 for -0x0004_0000_0000_0000 (signed)
    // = 0xFFFC_0000_0000_0000 as i64
    // LEB128 encoding of large negative: write as unsigned and rely on sign extension
    const heap_tag_mask: u64 = 0xFFFC_0000_0000_0000;
    var mask = heap_tag_mask;
    while (true) {
        const byte: u8 = @intCast(mask & 0x7F);
        mask >>= 7;
        const more = (mask != 0) and (mask != @as(u64, @bitCast(@as(i64, -1))));
        if (more) {
            try code.append(allocator, byte | 0x80);
        } else {
            try code.append(allocator, byte);
            break;
        }
    }

    // i64.or
    try code.append(allocator, 0x84);

    // 現在 stack top 係 NaN-boxed Vector Value (i64)
    // End instruction (implicit in caller's context)

    return try code.toOwnedSlice(allocator);
}

/// 生成 WASM code 去構造 Map
/// Stack 輸入：[k0, v0, k1, v1, ..., kN-1, vN-1]
/// Stack 輸出：[map_ptr]
pub fn emitMapConstruction(
    allocator: std.mem.Allocator,
    pair_count: u32,
) ![]const u8 {
    var code: std.ArrayList(u8) = .empty;
    defer code.deinit(allocator);

    const header_size = 16;
    const total_size = header_size + pair_count * 16; // each pair is 16 bytes

    // Locals: pair_count*2 i64s (keys+vals) + 1 i32 (base_ptr)
    const elem_count = pair_count * 2;

    try writeLEB128(&code, allocator, 2);
    try writeLEB128(&code, allocator, elem_count);
    try code.append(allocator, 0x7E); // i64
    try writeLEB128(&code, allocator, 1);
    try code.append(allocator, 0x7F); // i32

    // Store k-v pairs to locals (reverse order)
    var i: u32 = elem_count;
    while (i > 0) {
        i -= 1;
        try code.append(allocator, 0x21); // local.set
        try writeLEB128(&code, allocator, i);
    }

    // Allocate
    try code.append(allocator, 0x41); // i32.const
    try writeLEB128(&code, allocator, total_size);
    try code.append(allocator, 0x10); // call heap_alloc
    try writeLEB128(&code, allocator, 1);
    try code.append(allocator, 0x21); // local.set base_ptr
    try writeLEB128(&code, allocator, elem_count);

    const base_local = elem_count;

    // Write HeapHeader (tag = map_small = 10)
    try code.append(allocator, 0x20); // local.get
    try writeLEB128(&code, allocator, base_local);
    try code.append(allocator, 0x41); // i32.const
    try writeLEB128(&code, allocator, @intFromEnum(HeapTag.map_small));
    try code.append(allocator, 0x3A); // i32.store8
    try code.append(allocator, 0x00);
    try code.append(allocator, 0x00);

    // flags
    try code.append(allocator, 0x20);
    try writeLEB128(&code, allocator, base_local);
    try code.append(allocator, 0x41);
    try writeLEB128(&code, allocator, 0);
    try code.append(allocator, 0x3A);
    try code.append(allocator, 0x00);
    try code.append(allocator, 0x01);

    // gc_and_lock
    try code.append(allocator, 0x20);
    try writeLEB128(&code, allocator, base_local);
    try code.append(allocator, 0x41);
    try writeLEB128(&code, allocator, 0);
    try code.append(allocator, 0x36);
    try code.append(allocator, 0x02);
    try code.append(allocator, 0x04);

    // count
    try code.append(allocator, 0x20);
    try writeLEB128(&code, allocator, base_local);
    try code.append(allocator, 0x41);
    try writeLEB128(&code, allocator, pair_count);
    try code.append(allocator, 0x36);
    try code.append(allocator, 0x02);
    try code.append(allocator, 0x08);

    // Write pairs
    i = 0;
    while (i < pair_count) : (i += 1) {
        const pair_offset = 16 + i * 16;

        // Write key (local i*2)
        try code.append(allocator, 0x20); // local.get base
        try writeLEB128(&code, allocator, base_local);
        try code.append(allocator, 0x20); // local.get key
        try writeLEB128(&code, allocator, i * 2);
        try code.append(allocator, 0x37); // i64.store
        try code.append(allocator, 0x03);
        try writeLEB128(&code, allocator, pair_offset);

        // Write value (local i*2+1)
        try code.append(allocator, 0x20); // local.get base
        try writeLEB128(&code, allocator, base_local);
        try code.append(allocator, 0x20); // local.get val
        try writeLEB128(&code, allocator, i * 2 + 1);
        try code.append(allocator, 0x37); // i64.store
        try code.append(allocator, 0x03);
        try writeLEB128(&code, allocator, pair_offset + 8);
    }

    // NaN-box
    try code.append(allocator, 0x20);
    try writeLEB128(&code, allocator, base_local);
    try code.append(allocator, 0xAD); // i64.extend_i32_u
    try code.append(allocator, 0x42); // i64.const heap_tag_mask
    const heap_tag_mask: u64 = 0xFFFC_0000_0000_0000;
    var mask = heap_tag_mask;
    while (true) {
        const byte: u8 = @intCast(mask & 0x7F);
        mask >>= 7;
        const more = (mask != 0) and (mask != @as(u64, @bitCast(@as(i64, -1))));
        if (more) {
            try code.append(allocator, byte | 0x80);
        } else {
            try code.append(allocator, byte);
            break;
        }
    }
    try code.append(allocator, 0x84); // i64.or

    return try code.toOwnedSlice(allocator);
}

/// 生成 Set construction code (similar to Vector)
pub fn emitSetConstruction(
    allocator: std.mem.Allocator,
    element_count: u32,
) ![]const u8 {
    // Set layout same as Vector, just different HeapTag
    var code: std.ArrayList(u8) = .empty;
    defer code.deinit(allocator);

    const header_size = 16;
    const total_size = header_size + element_count * 8;

    try writeLEB128(&code, allocator, 2);
    try writeLEB128(&code, allocator, element_count);
    try code.append(allocator, 0x7E);
    try writeLEB128(&code, allocator, 1);
    try code.append(allocator, 0x7F);

    var i: u32 = element_count;
    while (i > 0) {
        i -= 1;
        try code.append(allocator, 0x21);
        try writeLEB128(&code, allocator, i);
    }

    try code.append(allocator, 0x41);
    try writeLEB128(&code, allocator, total_size);
    try code.append(allocator, 0x10);
    try writeLEB128(&code, allocator, 1);
    try code.append(allocator, 0x21);
    try writeLEB128(&code, allocator, element_count);

    const base_local = element_count;

    // tag = set_small = 12
    try code.append(allocator, 0x20);
    try writeLEB128(&code, allocator, base_local);
    try code.append(allocator, 0x41);
    try writeLEB128(&code, allocator, @intFromEnum(HeapTag.set_small));
    try code.append(allocator, 0x3A);
    try code.append(allocator, 0x00);
    try code.append(allocator, 0x00);

    // flags + gc_and_lock + count (same as vector)
    try code.append(allocator, 0x20);
    try writeLEB128(&code, allocator, base_local);
    try code.append(allocator, 0x41);
    try writeLEB128(&code, allocator, 0);
    try code.append(allocator, 0x3A);
    try code.append(allocator, 0x00);
    try code.append(allocator, 0x01);

    try code.append(allocator, 0x20);
    try writeLEB128(&code, allocator, base_local);
    try code.append(allocator, 0x41);
    try writeLEB128(&code, allocator, 0);
    try code.append(allocator, 0x36);
    try code.append(allocator, 0x02);
    try code.append(allocator, 0x04);

    try code.append(allocator, 0x20);
    try writeLEB128(&code, allocator, base_local);
    try code.append(allocator, 0x41);
    try writeLEB128(&code, allocator, element_count);
    try code.append(allocator, 0x36);
    try code.append(allocator, 0x02);
    try code.append(allocator, 0x08);

    // Write elements
    i = 0;
    while (i < element_count) : (i += 1) {
        const elem_offset = 16 + i * 8;
        try code.append(allocator, 0x20);
        try writeLEB128(&code, allocator, base_local);
        try code.append(allocator, 0x20);
        try writeLEB128(&code, allocator, i);
        try code.append(allocator, 0x37);
        try code.append(allocator, 0x03);
        try writeLEB128(&code, allocator, elem_offset);
    }

    // NaN-box
    try code.append(allocator, 0x20);
    try writeLEB128(&code, allocator, base_local);
    try code.append(allocator, 0xAD);
    try code.append(allocator, 0x42);
    const heap_tag_mask: u64 = 0xFFFC_0000_0000_0000;
    var mask = heap_tag_mask;
    while (true) {
        const byte: u8 = @intCast(mask & 0x7F);
        mask >>= 7;
        const more = (mask != 0) and (mask != @as(u64, @bitCast(@as(i64, -1))));
        if (more) {
            try code.append(allocator, byte | 0x80);
        } else {
            try code.append(allocator, byte);
            break;
        }
    }
    try code.append(allocator, 0x84);

    return try code.toOwnedSlice(allocator);
}
