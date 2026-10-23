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
    function = 11, // fn* anonymous functions

    /// Convert tag to WAT i32 constant
    pub fn toWAT(self: TypeTag) []const u8 {
        return switch (self) {
            .nil => "0",
            .boolean => "1",
            .long => "2",
            .double => "3",
            .string => "4",
            .symbol => "5",
            .keyword => "6",
            .list => "7",
            .vector => "8",
            .map => "9",
            .set => "10",
            .function => "11",
        };
    }
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

    /// Generate $ValueData union definition in WAT.
    ///
    /// Spec: Union of all value payload types
    /// Output:
    ///   (type $ValueData (union
    ///     (field $nil (struct))
    ///     (field $boolean i32)
    ///     ...
    ///   ))
    pub fn emitValueDataUnion(self: *WatTypeGen) ![]const u8 {
        _ = self;
        return
            \\;; Tagged union for value payloads
            \\(type $ValueData (union
            \\  (field $nil (struct))
            \\  (field $boolean i32)
            \\  (field $long i64)
            \\  (field $double f64)
            \\  (field $string (ref $String))
            \\  (field $symbol (ref $Symbol))
            \\  (field $keyword (ref $Keyword))
            \\  (field $list (ref $List))
            \\  (field $vector (ref $Vector))
            \\  (field $map (ref $Map))
            \\  (field $set (ref $Set))
            \\  (field $function (ref $Function))
            \\))
        ;
    }

    /// Generate $List type definition in WAT.
    ///
    /// Spec: Persistent singly-linked list
    /// Output:
    ///   (type $List (struct
    ///     (field $first (ref null $Value))
    ///     (field $rest (ref null $List))
    ///     (field $count i32)
    ///   ))
    pub fn emitListType(self: *WatTypeGen) ![]const u8 {
        _ = self;
        return
            \\;; Persistent singly-linked list
            \\(type $List (struct
            \\  (field $first (ref null $Value))
            \\  (field $rest (ref null $List))
            \\  (field $count i32)
            \\))
        ;
    }

    /// Generate $Vector type definition in WAT.
    ///
    /// Spec: Persistent RRB-tree (simplified)
    /// Output:
    ///   (type $Vector (struct
    ///     (field $root (ref null $VectorNode))
    ///     (field $tail (array (ref null $Value)))
    ///     (field $count i32)
    ///   ))
    pub fn emitVectorType(self: *WatTypeGen) ![]const u8 {
        _ = self;
        return
            \\;; Persistent vector (RRB-tree simplified)
            \\(type $Vector (struct
            \\  (field $root (ref null $VectorNode))
            \\  (field $tail (array (ref null $Value)))
            \\  (field $count i32)
            \\))
        ;
    }

    /// Generate $VectorNode type definition in WAT.
    ///
    /// Spec: Internal node for vector RRB-tree
    pub fn emitVectorNodeType(self: *WatTypeGen) ![]const u8 {
        _ = self;
        return
            \\;; Vector internal node
            \\(type $VectorNode (struct
            \\  (field $children (array (ref null any)))
            \\))
        ;
    }

    /// Generate $Map type definition in WAT.
    ///
    /// Spec: Persistent hash map (HAMT)
    /// Output:
    ///   (type $Map (struct
    ///     (field $root (ref null $MapNode))
    ///     (field $count i32)
    ///   ))
    pub fn emitMapType(self: *WatTypeGen) ![]const u8 {
        _ = self;
        return
            \\;; Persistent hash map (HAMT)
            \\(type $Map (struct
            \\  (field $root (ref null $MapNode))
            \\  (field $count i32)
            \\))
        ;
    }

    /// Generate $MapNode type definition in WAT.
    ///
    /// Spec: Internal HAMT node with bitmap
    pub fn emitMapNodeType(self: *WatTypeGen) ![]const u8 {
        _ = self;
        return
            \\;; Map internal HAMT node
            \\(type $MapNode (struct
            \\  (field $bitmap i32)
            \\  (field $children (array (ref null any)))
            \\))
        ;
    }

    /// Generate $Set type definition in WAT.
    ///
    /// Spec: Persistent hash set (wrapper around Map)
    pub fn emitSetType(self: *WatTypeGen) ![]const u8 {
        _ = self;
        return
            \\;; Persistent hash set
            \\(type $Set (struct
            \\  (field $map (ref $Map))
            \\))
        ;
    }

    /// Generate $Function type definition in WAT.
    ///
    /// Spec: First-class function with captures (closure)
    /// Fields:
    ///   - func_index: index into function table
    ///   - captures: array of captured Value references
    ///   - arity: number of required parameters
    pub fn emitFunctionType(self: *WatTypeGen) ![]const u8 {
        _ = self;
        return
            \\;; First-class function (closure)
            \\(type $Function (struct
            \\  (field $func_index i32)           ;; Index in function table
            \\  (field $captures (ref null (array (ref $Value))))  ;; Captured variables
            \\  (field $arity i32)                ;; Parameter count
            \\))
        ;
    }

    /// Generate all core type definitions (called once per module).
    ///
    /// Spec: Emits all types needed for Clojure runtime
    /// Phase: Month 1-2 complete type system
    pub fn emitAllTypes(self: *WatTypeGen) ![]const u8 {
        var buf = try std.array_list.Managed(u8).initCapacity(self.arena, 4096);

        // Core value types
        try buf.appendSlice(try self.emitValueType());
        try buf.appendSlice("\n\n");
        try buf.appendSlice(try self.emitValueDataUnion());
        try buf.appendSlice("\n\n");

        // Scalar types
        try buf.appendSlice(try self.emitStringType());
        try buf.appendSlice("\n\n");
        try buf.appendSlice(try self.emitSymbolType());
        try buf.appendSlice("\n\n");
        try buf.appendSlice(try self.emitKeywordType());
        try buf.appendSlice("\n\n");

        // Collection types
        try buf.appendSlice(try self.emitListType());
        try buf.appendSlice("\n\n");
        try buf.appendSlice(try self.emitVectorType());
        try buf.appendSlice("\n\n");
        try buf.appendSlice(try self.emitVectorNodeType());
        try buf.appendSlice("\n\n");
        try buf.appendSlice(try self.emitMapType());
        try buf.appendSlice("\n\n");
        try buf.appendSlice(try self.emitMapNodeType());
        try buf.appendSlice("\n\n");
        try buf.appendSlice(try self.emitSetType());
        try buf.appendSlice("\n\n");
        try buf.appendSlice(try self.emitFunctionType());

        return buf.toOwnedSlice();
    }
};
