// SPDX-License-Identifier: EPL-2.0
//! Wasm linear memory allocator for heap-allocated Values.
//!
//! The Wasm backend cannot use host pointers (VM/TreeWalk use Zig allocator + host heap).
//! Instead, heap objects live in Wasm linear memory and Values encode memory offsets (u32)
//! instead of host pointers (u64).
//!
//! Memory layout:
//!   [0..1024]        Reserved (null pointer guard)
//!   [1024..N]        Heap objects (HeapHeader + data)
//!   [N..memory.size] Free space
//!
//! Each heap object starts with HeapHeader (8 bytes: tag + metadata) followed by
//! type-specific data (String: length + bytes; Vector: count + elements; etc.).

const std = @import("std");
const Value = @import("../../../runtime/value/value.zig").Value;
const HeapTag = @import("../../../runtime/value/value.zig").HeapTag;
const HeapHeader = @import("../../../runtime/value/value.zig").HeapHeader;

/// Linear memory allocator state
pub const WasmLinearMemory = struct {
    /// Current allocation pointer (offset into linear memory)
    next_offset: u32,
    /// Total memory size
    memory_size: u32,
    /// Allocator for metadata structures
    allocator: std.mem.Allocator,

    const RESERVED_START: u32 = 0;
    const RESERVED_END: u32 = 1024;
    const HEAP_START: u32 = 1024;

    pub fn init(allocator: std.mem.Allocator, memory_size: u32) WasmLinearMemory {
        return .{
            .next_offset = HEAP_START,
            .memory_size = memory_size,
            .allocator = allocator,
        };
    }

    /// Allocate space for a heap object. Returns offset into linear memory.
    /// The caller must write HeapHeader + object data to this offset.
    pub fn alloc(self: *WasmLinearMemory, size: u32) !u32 {
        // Align to 8 bytes (required for HeapHeader + Value pointer encoding)
        const aligned_size = std.mem.alignForward(u32, size, 8);

        if (self.next_offset + aligned_size > self.memory_size) {
            return error.OutOfMemory;
        }

        const offset = self.next_offset;
        self.next_offset += aligned_size;
        return offset;
    }

    /// Encode a linear memory offset as a Value with the given HeapTag.
    /// This replaces Value.encodeHeapPtr for Wasm backend.
    pub fn encodeOffset(offset: u32, ht: HeapTag) Value {
        // Phase 3b: Encode offset in NaN-box bits where host pointer would go.
        // The NaN-box encoding expects an 8-byte-aligned host pointer.
        // For Wasm, we encode the 32-bit memory offset in the same bit positions.
        // This works because:
        // 1. Offsets are 8-byte aligned (low 3 bits always 0)
        // 2. Offsets fit in 32 bits (Wasm linear memory is u32-addressed)
        // 3. Value.tag() discriminates heap vs immediate by top16 bits
        //
        // Note: This encoding is WASM-ONLY and cannot interop with
        // host-side Values (VM/TreeWalk encode real host pointers).
        // Cross-backend Value passing requires serialization.

        // Cast offset to usize to match Value.encodeHeapPtrRuntime signature
        // (it expects anytype pointer, but we pass an offset treated as pointer)
        const fake_ptr: *anyopaque = @ptrFromInt(@as(usize, offset));
        return Value.encodeHeapPtrRuntime(ht, fake_ptr);
    }

    /// Decode a linear memory offset from a Value.
    /// This replaces Value.decodePtr for Wasm backend.
    pub fn decodeOffset(val: Value) u32 {
        // Extract the fake pointer and cast back to u32 offset
        const ptr: *anyopaque = val.decodePtr(*anyopaque);
        const offset: u32 = @truncate(@intFromPtr(ptr));
        return offset;
    }
};
