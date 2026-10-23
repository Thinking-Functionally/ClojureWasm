// SPDX-License-Identifier: EPL-2.0
//! WasmGC backend type definitions and mapping
//!
//! This module defines the WAT type system for ClojureWasm's WasmGC backend.
//! Unlike the TreeWalk and VM backends which use NaN-boxing for Value
//! representation, the WasmGC backend uses WebAssembly GC's native struct/array/ref
//! types with explicit tagged unions.
//!
//! Key design decisions (see Phase 4 proposal § 類型映射方案):
//! - Host-managed GC (browser/runtime handles allocation/collection)
//! - Tagged union with $tag field + $ValueData union
//! - NOT reusing NaN-boxing from TreeWalk/VM backends
//! - Persistent data structures implemented with WasmGC native types

const std = @import("std");

/// Value tag enumeration - maps to WAT i32 field
pub const ValueTag = enum(i32) {
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

    pub fn toWAT(self: ValueTag) []const u8 {
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
        };
    }
};

/// WAT type definition templates for code generation
pub const WATTypes = struct {
    /// Core $Value struct type
    pub const value_struct =
        \\(type $Value (struct
        \\  (field $tag i32)
        \\  (field $data (ref null $ValueData))
        \\))
    ;

    /// Tagged union for value data
    pub const value_data_union =
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
        \\))
    ;

    /// String type - immutable UTF-8 byte array
    pub const string_struct =
        \\(type $String (struct
        \\  (field $bytes (array i8))
        \\  (field $hash i32)
        \\))
    ;

    /// Symbol type - namespace + name
    pub const symbol_struct =
        \\(type $Symbol (struct
        \\  (field $ns (ref null $String))
        \\  (field $name (ref $String))
        \\  (field $hash i32)
        \\))
    ;

    /// Keyword type - namespace + name (distinct from Symbol)
    pub const keyword_struct =
        \\(type $Keyword (struct
        \\  (field $ns (ref null $String))
        \\  (field $name (ref $String))
        \\  (field $hash i32)
        \\))
    ;

    /// List type - persistent singly-linked list
    pub const list_struct =
        \\(type $List (struct
        \\  (field $first (ref null $Value))
        \\  (field $rest (ref null $List))
        \\  (field $count i32)
        \\))
    ;

    /// Vector type - persistent RRB-tree (simplified)
    pub const vector_struct =
        \\(type $Vector (struct
        \\  (field $root (ref null $VectorNode))
        \\  (field $tail (array (ref null $Value)))
        \\  (field $count i32)
        \\))
    ;

    /// Vector internal node for RRB-tree
    pub const vector_node_struct =
        \\(type $VectorNode (struct
        \\  (field $children (array (ref null any)))
        \\))
    ;

    /// Map type - persistent HAMT
    pub const map_struct =
        \\(type $Map (struct
        \\  (field $root (ref null $MapNode))
        \\  (field $count i32)
        \\))
    ;

    /// Map internal node for HAMT
    pub const map_node_struct =
        \\(type $MapNode (struct
        \\  (field $bitmap i32)
        \\  (field $children (array (ref null any)))
        \\))
    ;

    /// Set type - backed by Map with nil values
    pub const set_struct =
        \\(type $Set (struct
        \\  (field $backing_map (ref $Map))
        \\))
    ;

    /// Function type - closure with captured environment
    pub const function_struct =
        \\(type $Function (struct
        \\  (field $code_index i32)
        \\  (field $env (array (ref null $Value)))
        \\))
    ;
};
