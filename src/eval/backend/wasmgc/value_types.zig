// SPDX-License-Identifier: EPL-2.0
//! WasmGC Value Type Mapping
//!
//! Defines how Clojure types map to WasmGC native types (struct/array/ref).
//! Uses tagged union representation (Option B from Phase 4 proposal).
//!
//! Type tag mapping:
//!   0 = nil
//!   1 = boolean
//!   2 = long (i64)
//!   3 = double (f64)
//!   4 = string
//!   5 = symbol
//!   6 = keyword
//!   7 = list
//!   8 = vector
//!   9 = map
//!   10 = set
//!
//! Spec reference: Phase 4 詳細方案 § WasmGC 類型映射 (L54-115)

const std = @import("std");

/// Type tag constants for Clojure values in WasmGC.
pub const TypeTag = enum(i32) {
    nil = 0,
    boolean = 1,
    long = 2,
    double = 3,
    string = 4,
    symbol = 5,
    keyword = 6,
    list = 7,
    vector = 8,
    map = 9,
    set = 10,
};

/// WAT type definition generator.
pub const WatTypeGen = struct {
    arena: std.mem.Allocator,

    pub fn init(arena: std.mem.Allocator) WatTypeGen {
        return .{ .arena = arena };
    }

    /// Generate core $Value type definition in WAT.
    ///
    /// Spec: Tagged union with $tag (i32) + $data (ref null $ValueData)
    /// Output:
    ///   (type $Value (struct
    ///     (field $tag i32)
    ///     (field $data (ref null $ValueData))
    ///   ))
    pub fn emitValueType(self: *WatTypeGen) ![]const u8 {
        _ = self;
        return
            \\;; Core Clojure Value type (tagged union)
            \\(type $Value (struct
            \\  (field $tag i32)        ;; TypeTag: 0=nil, 1=boolean, ..., 10=set
            \\  (field $data (ref null $ValueData))
            \\))
        ;
    }

    /// Generate $String type definition in WAT.
    ///
    /// Spec: String stores UTF-8 bytes + hash cache
    /// Output:
    ///   (type $String (struct
    ///     (field $bytes (array (mut i8)))
    ///     (field $hash i32)
    ///   ))
    pub fn emitStringType(self: *WatTypeGen) ![]const u8 {
        _ = self;
        return
            \\;; Clojure String
            \\(type $String (struct
            \\  (field $bytes (array (mut i8)))
            \\  (field $hash i32)
            \\))
        ;
    }

    /// Generate $Symbol type definition in WAT.
    ///
    /// Spec: Symbol has optional namespace + name + hash cache
    /// Output:
    ///   (type $Symbol (struct
    ///     (field $ns (ref null $String))
    ///     (field $name (ref $String))
    ///     (field $hash i32)
    ///   ))
    pub fn emitSymbolType(self: *WatTypeGen) ![]const u8 {
        _ = self;
        return
            \\;; Clojure Symbol
            \\(type $Symbol (struct
            \\  (field $ns (ref null $String))
            \\  (field $name (ref $String))
            \\  (field $hash i32)
            \\))
        ;
    }

    /// Generate $Keyword type definition in WAT.
    ///
    /// Spec: Keyword structure identical to Symbol (ns + name + hash)
    /// Output:
    ///   (type $Keyword (struct
    ///     (field $ns (ref null $String))
    ///     (field $name (ref $String))
    ///     (field $hash i32)
    ///   ))
    pub fn emitKeywordType(self: *WatTypeGen) ![]const u8 {
        _ = self;
        return
            \\;; Clojure Keyword
            \\(type $Keyword (struct
            \\  (field $ns (ref null $String))
            \\  (field $name (ref $String))
            \\  (field $hash i32)
            \\))
        ;
    }

    /// Generate all core type definitions (called once per module).
    ///
    /// Spec: Emits $Value + $String + $Symbol + $Keyword + collection types
    /// Phase: Month 1 Week 3-4 (basic types only, collections in Month 2)
    pub fn emitAllTypes(self: *WatTypeGen) ![]const u8 {
        var buf = try std.array_list.Managed(u8).initCapacity(self.arena, 1024);

        try buf.appendSlice(try self.emitValueType());
        try buf.appendSlice("\n\n");
        try buf.appendSlice(try self.emitStringType());
        try buf.appendSlice("\n\n");
        try buf.appendSlice(try self.emitSymbolType());
        try buf.appendSlice("\n\n");
        try buf.appendSlice(try self.emitKeywordType());

        return buf.toOwnedSlice();
    }
};
