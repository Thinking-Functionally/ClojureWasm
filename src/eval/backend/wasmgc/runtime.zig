// SPDX-License-Identifier: EPL-2.0
//! WasmGC runtime support function definitions
//!
//! This module generates WAT function definitions for runtime support operations
//! that the compiler emits calls to. These functions handle:
//! - Value construction (strings, symbols, keywords)
//! - Type predicates and coercion
//! - Arithmetic and comparison operations
//! - Collection operations (conj, assoc, get, etc.)
//! - Equality and hashing
//!
//! Design notes:
//! - All runtime functions operate on (ref $Value) types
//! - Functions are emitted as WAT text during module compilation
//! - No global state - pure functions where possible
//! - Hash caching for immutable types (strings, symbols, keywords)

const std = @import("std");
const types = @import("value_types");
const codegen = @import("codegen");
const Allocator = std.mem.Allocator;

/// Runtime function generator for WasmGC backend
pub const RuntimeGen = struct {
    arena: Allocator,
    indent: codegen.IndentContext,

    pub fn init(arena: Allocator) RuntimeGen {
        return .{
            .arena = arena,
            .indent = codegen.IndentContext.init(),
        };
    }

    /// Generate $rt_make_string function
    /// Creates a $Value wrapping a $String from UTF-8 byte array
    pub fn emitMakeString(self: *RuntimeGen) ![]const u8 {
        var buf = std.array_list.Managed(u8).init(self.arena);

        try buf.appendSlice(
            \\  (func $rt_make_string (param $bytes (array i8)) (result (ref $Value))
            \\    (local $hash i32)
            \\    (local $i i32)
            \\    (local $len i32)
            \\    (local $byte i32)
            \\    ;; FNV-1a hash: hash = 2166136261; for each byte: hash = (hash ^ byte) * 16777619
            \\    (local.set $hash (i32.const 2166136261))
            \\    (local.set $len (array.len (local.get $bytes)))
            \\    (block $break
            \\      (loop $continue
            \\        (br_if $break (i32.ge_u (local.get $i) (local.get $len)))
            \\        (local.set $byte (array.get_u $bytes (local.get $i)))
            \\        (local.set $hash (i32.mul
            \\          (i32.xor (local.get $hash) (local.get $byte))
            \\          (i32.const 16777619)))
            \\        (local.set $i (i32.add (local.get $i) (i32.const 1)))
            \\        (br $continue))))
            \\
            \\    (struct.new $Value
            \\      (i32.const 4)  ;; TypeTag.string
            \\      (union.new $ValueData $string
            \\        (struct.new $String
            \\          (local.get $bytes)
            \\          (local.get $hash)))))
            \\
        );

        return buf.toOwnedSlice();
    }

    /// Generate $rt_make_symbol function
    /// Creates a $Value wrapping a $Symbol from namespace + name strings
    pub fn emitMakeSymbol(self: *RuntimeGen) ![]const u8 {
        var buf = std.array_list.Managed(u8).init(self.arena);

        try buf.appendSlice(
            \\  (func $rt_make_symbol (param $ns (ref null $String)) (param $name (ref $String)) (result (ref $Value))
            \\    (local $hash i32)
            \\    (local $i i32)
            \\    (local $len i32)
            \\    (local $byte i32)
            \\    (local $bytes (array i8))
            \\    ;; Hash = hash(namespace) * 31 + hash(name)
            \\    (local.set $hash (i32.const 2166136261))
            \\    ;; Hash namespace if present
            \\    (if (ref.is_null (local.get $ns))
            \\      (then)
            \\      (else
            \\        (local.set $bytes (struct.get $String $bytes (ref.as_non_null (local.get $ns))))
            \\        (local.set $len (array.len (local.get $bytes)))
            \\        (local.set $i (i32.const 0))
            \\        (block $break1
            \\          (loop $continue1
            \\            (br_if $break1 (i32.ge_u (local.get $i) (local.get $len)))
            \\            (local.set $byte (array.get_u $bytes (local.get $i)))
            \\            (local.set $hash (i32.mul
            \\              (i32.xor (local.get $hash) (local.get $byte))
            \\              (i32.const 16777619)))
            \\            (local.set $i (i32.add (local.get $i) (i32.const 1)))
            \\            (br $continue1)))
            \\        (local.set $hash (i32.mul (local.get $hash) (i32.const 31)))))
            \\    ;; Hash name
            \\    (local.set $bytes (struct.get $String $bytes (local.get $name)))
            \\    (local.set $len (array.len (local.get $bytes)))
            \\    (local.set $i (i32.const 0))
            \\    (block $break2
            \\      (loop $continue2
            \\        (br_if $break2 (i32.ge_u (local.get $i) (local.get $len)))
            \\        (local.set $byte (array.get_u $bytes (local.get $i)))
            \\        (local.set $hash (i32.mul
            \\          (i32.xor (local.get $hash) (local.get $byte))
            \\          (i32.const 16777619)))
            \\        (local.set $i (i32.add (local.get $i) (i32.const 1)))
            \\        (br $continue2)))
            \\
            \\    (struct.new $Value
            \\      (i32.const 5)  ;; TypeTag.symbol
            \\      (union.new $ValueData $symbol
            \\        (struct.new $Symbol
            \\          (local.get $ns)
            \\          (local.get $name)
            \\          (local.get $hash)))))
            \\
        );

        return buf.toOwnedSlice();
    }

    /// Generate $rt_make_keyword function
    /// Creates a $Value wrapping a $Keyword from namespace + name strings
    pub fn emitMakeKeyword(self: *RuntimeGen) ![]const u8 {
        var buf = std.array_list.Managed(u8).init(self.arena);

        try buf.appendSlice(
            \\  (func $rt_make_keyword (param $ns (ref null $String)) (param $name (ref $String)) (result (ref $Value))
            \\    (local $hash i32)
            \\    (local $i i32)
            \\    (local $len i32)
            \\    (local $byte i32)
            \\    (local $bytes (array i8))
            \\    ;; Hash = hash(namespace) * 31 + hash(name) (same as symbol)
            \\    (local.set $hash (i32.const 2166136261))
            \\    ;; Hash namespace if present
            \\    (if (ref.is_null (local.get $ns))
            \\      (then)
            \\      (else
            \\        (local.set $bytes (struct.get $String $bytes (ref.as_non_null (local.get $ns))))
            \\        (local.set $len (array.len (local.get $bytes)))
            \\        (local.set $i (i32.const 0))
            \\        (block $break1
            \\          (loop $continue1
            \\            (br_if $break1 (i32.ge_u (local.get $i) (local.get $len)))
            \\            (local.set $byte (array.get_u $bytes (local.get $i)))
            \\            (local.set $hash (i32.mul
            \\              (i32.xor (local.get $hash) (local.get $byte))
            \\              (i32.const 16777619)))
            \\            (local.set $i (i32.add (local.get $i) (i32.const 1)))
            \\            (br $continue1)))
            \\        (local.set $hash (i32.mul (local.get $hash) (i32.const 31)))))
            \\    ;; Hash name
            \\    (local.set $bytes (struct.get $String $bytes (local.get $name)))
            \\    (local.set $len (array.len (local.get $bytes)))
            \\    (local.set $i (i32.const 0))
            \\    (block $break2
            \\      (loop $continue2
            \\        (br_if $break2 (i32.ge_u (local.get $i) (local.get $len)))
            \\        (local.set $byte (array.get_u $bytes (local.get $i)))
            \\        (local.set $hash (i32.mul
            \\          (i32.xor (local.get $hash) (local.get $byte))
            \\          (i32.const 16777619)))
            \\        (local.set $i (i32.add (local.get $i) (i32.const 1)))
            \\        (br $continue2)))
            \\
            \\    (struct.new $Value
            \\      (i32.const 6)  ;; TypeTag.keyword
            \\      (union.new $ValueData $keyword
            \\        (struct.new $Keyword
            \\          (local.get $ns)
            \\          (local.get $name)
            \\          (local.get $hash)))))
            \\
        );

        return buf.toOwnedSlice();
    }

    /// Generate $rt_is_truthy function
    /// Returns 1 for truthy (everything except nil and false), 0 for falsy
    pub fn emitIsTruthy(self: *RuntimeGen) ![]const u8 {
        var buf = std.array_list.Managed(u8).init(self.arena);

        try buf.appendSlice(
            \\  (func $rt_is_truthy (param $val (ref $Value)) (result i32)
            \\    (local $tag i32)
            \\    (local.set $tag (struct.get $Value $tag (local.get $val)))
            \\
            \\    ;; nil (tag 0) is falsy
            \\    (if (result i32) (i32.eq (local.get $tag) (i32.const 0))
            \\      (then (i32.const 0))
            \\      (else
            \\        ;; boolean (tag 1): check the value
            \\        (if (result i32) (i32.eq (local.get $tag) (i32.const 1))
            \\          (then
            \\            ;; Extract boolean value from union
            \\            (union.get $ValueData $boolean
            \\              (struct.get $Value $data (local.get $val))))
            \\          (else
            \\            ;; Everything else is truthy
            \\            (i32.const 1))))))
            \\
        );

        return buf.toOwnedSlice();
    }

    /// Generate $rt_add function
    /// Arithmetic addition with type coercion (long + long → long, else → double)
    pub fn emitAdd(self: *RuntimeGen) ![]const u8 {
        _ = self;
        return
            \\  (func $rt_add (param $a (ref $Value)) (param $b (ref $Value)) (result (ref $Value))
            \\    (local $tag_a i32)
            \\    (local $tag_b i32)
            \\    (local.set $tag_a (struct.get $Value $tag (local.get $a)))
            \\    (local.set $tag_b (struct.get $Value $tag (local.get $b)))
            \\
            \\    ;; If both are longs (tag 2), do i64 addition
            \\    (if (result (ref $Value))
            \\      (i32.and
            \\        (i32.eq (local.get $tag_a) (i32.const 2))
            \\        (i32.eq (local.get $tag_b) (i32.const 2)))
            \\      (then
            \\        (struct.new $Value
            \\          (i32.const 2)
            \\          (union.new $ValueData $long
            \\            (i64.add
            \\              (union.get $ValueData $long (struct.get $Value $data (local.get $a)))
            \\              (union.get $ValueData $long (struct.get $Value $data (local.get $b)))))))
            \\      (else
            \\        ;; Coerce to double and add
            \\        (struct.new $Value
            \\          (i32.const 3)
            \\          (union.new $ValueData $double
            \\            (f64.add
            \\              (call $rt_to_double (local.get $a))
            \\              (call $rt_to_double (local.get $b))))))))
            \\
        ;
    }

    /// Generate $rt_to_double function
    /// Coerces long or double to f64 for arithmetic operations
    pub fn emitToDouble(self: *RuntimeGen) ![]const u8 {
        _ = self;
        return
            \\  (func $rt_to_double (param $val (ref $Value)) (result f64)
            \\    (local $tag i32)
            \\    (local.set $tag (struct.get $Value $tag (local.get $val)))
            \\
            \\    (if (result f64) (i32.eq (local.get $tag) (i32.const 2))
            \\      (then
            \\        ;; long → f64
            \\        (f64.convert_i64_s
            \\          (union.get $ValueData $long (struct.get $Value $data (local.get $val)))))
            \\      (else
            \\        ;; double → f64 (already f64)
            \\        (union.get $ValueData $double (struct.get $Value $data (local.get $val))))))
            \\
        ;
    }

    /// Generate $rt_subtract function
    /// Arithmetic subtraction with type coercion (long - long → long, else → double)
    pub fn emitSubtract(self: *RuntimeGen) ![]const u8 {
        _ = self;
        return
            \\  (func $rt_subtract (param $a (ref $Value)) (param $b (ref $Value)) (result (ref $Value))
            \\    (local $tag_a i32)
            \\    (local $tag_b i32)
            \\    (local.set $tag_a (struct.get $Value $tag (local.get $a)))
            \\    (local.set $tag_b (struct.get $Value $tag (local.get $b)))
            \\
            \\    (if (result (ref $Value))
            \\      (i32.and
            \\        (i32.eq (local.get $tag_a) (i32.const 2))
            \\        (i32.eq (local.get $tag_b) (i32.const 2)))
            \\      (then
            \\        (struct.new $Value
            \\          (i32.const 2)
            \\          (union.new $ValueData $long
            \\            (i64.sub
            \\              (union.get $ValueData $long (struct.get $Value $data (local.get $a)))
            \\              (union.get $ValueData $long (struct.get $Value $data (local.get $b)))))))
            \\      (else
            \\        (struct.new $Value
            \\          (i32.const 3)
            \\          (union.new $ValueData $double
            \\            (f64.sub
            \\              (call $rt_to_double (local.get $a))
            \\              (call $rt_to_double (local.get $b))))))))
            \\
        ;
    }

    /// Generate $rt_multiply function
    /// Arithmetic multiplication with type coercion (long * long → long, else → double)
    pub fn emitMultiply(self: *RuntimeGen) ![]const u8 {
        _ = self;
        return
            \\  (func $rt_multiply (param $a (ref $Value)) (param $b (ref $Value)) (result (ref $Value))
            \\    (local $tag_a i32)
            \\    (local $tag_b i32)
            \\    (local.set $tag_a (struct.get $Value $tag (local.get $a)))
            \\    (local.set $tag_b (struct.get $Value $tag (local.get $b)))
            \\
            \\    (if (result (ref $Value))
            \\      (i32.and
            \\        (i32.eq (local.get $tag_a) (i32.const 2))
            \\        (i32.eq (local.get $tag_b) (i32.const 2)))
            \\      (then
            \\        (struct.new $Value
            \\          (i32.const 2)
            \\          (union.new $ValueData $long
            \\            (i64.mul
            \\              (union.get $ValueData $long (struct.get $Value $data (local.get $a)))
            \\              (union.get $ValueData $long (struct.get $Value $data (local.get $b)))))))
            \\      (else
            \\        (struct.new $Value
            \\          (i32.const 3)
            \\          (union.new $ValueData $double
            \\            (f64.mul
            \\              (call $rt_to_double (local.get $a))
            \\              (call $rt_to_double (local.get $b))))))))
            \\
        ;
    }

    /// Generate $rt_divide function
    /// Arithmetic division (always produces double for Clojure semantics)
    pub fn emitDivide(self: *RuntimeGen) ![]const u8 {
        _ = self;
        return
            \\  (func $rt_divide (param $a (ref $Value)) (param $b (ref $Value)) (result (ref $Value))
            \\    ;; Division always produces double in Clojure
            \\    (struct.new $Value
            \\      (i32.const 3)
            \\      (union.new $ValueData $double
            \\        (f64.div
            \\          (call $rt_to_double (local.get $a))
            \\          (call $rt_to_double (local.get $b))))))
            \\
        ;
    }

    /// Generate $rt_equals function
    /// Value equality comparison (returns i32: 1=equal, 0=not equal)
    pub fn emitEquals(self: *RuntimeGen) ![]const u8 {
        _ = self;
        return
            \\  (func $rt_equals (param $a (ref $Value)) (param $b (ref $Value)) (result i32)
            \\    (local $tag_a i32)
            \\    (local $tag_b i32)
            \\    (local.set $tag_a (struct.get $Value $tag (local.get $a)))
            \\    (local.set $tag_b (struct.get $Value $tag (local.get $b)))
            \\
            \\    ;; Different tags → not equal
            \\    (if (result i32) (i32.ne (local.get $tag_a) (local.get $tag_b))
            \\      (then (i32.const 0))
            \\      (else
            \\        ;; Same tag, check value by type
            \\        (if (result i32) (i32.eq (local.get $tag_a) (i32.const 0))
            \\          (then (i32.const 1))  ;; nil = nil
            \\          (else (if (result i32) (i32.eq (local.get $tag_a) (i32.const 1))
            \\            (then  ;; boolean comparison
            \\              (i32.eq
            \\                (union.get $ValueData $boolean (struct.get $Value $data (local.get $a)))
            \\                (union.get $ValueData $boolean (struct.get $Value $data (local.get $b)))))
            \\            (else (if (result i32) (i32.eq (local.get $tag_a) (i32.const 2))
            \\              (then  ;; long comparison
            \\                (i64.eq
            \\                  (union.get $ValueData $long (struct.get $Value $data (local.get $a)))
            \\                  (union.get $ValueData $long (struct.get $Value $data (local.get $b)))))
            \\              (else (if (result i32) (i32.eq (local.get $tag_a) (i32.const 3))
            \\                (then  ;; double comparison
            \\                  (f64.eq
            \\                    (union.get $ValueData $double (struct.get $Value $data (local.get $a)))
            \\                    (union.get $ValueData $double (struct.get $Value $data (local.get $b)))))
            \\                (else (if (result i32) (i32.eq (local.get $tag_a) (i32.const 4))
            \\                  (then  ;; string comparison
            \\                    (call $rt_string_equals
            \\                      (union.get $ValueData $string (struct.get $Value $data (local.get $a)))
            \\                      (union.get $ValueData $string (struct.get $Value $data (local.get $b)))))
            \\                  (else (if (result i32) (i32.eq (local.get $tag_a) (i32.const 5))
            \\                    (then  ;; symbol comparison
            \\                      (call $rt_symbol_equals
            \\                        (union.get $ValueData $symbol (struct.get $Value $data (local.get $a)))
            \\                        (union.get $ValueData $symbol (struct.get $Value $data (local.get $b)))))
            \\                    (else (if (result i32) (i32.eq (local.get $tag_a) (i32.const 6))
            \\                      (then  ;; keyword comparison
            \\                        (call $rt_keyword_equals
            \\                          (union.get $ValueData $keyword (struct.get $Value $data (local.get $a)))
            \\                          (union.get $ValueData $keyword (struct.get $Value $data (local.get $b)))))
            \\                      (else
            \\                        ;; collection equality (list=7, vector=8, map=9, set=10)
            \\                        (if (result i32) (i32.le_u (local.get $tag_a) (i32.const 10))
            \\                          (then
            \\                            ;; Collections: structural equality via runtime helpers
            \\                            ;; Month 2 implementation - call appropriate collection_equals
            \\                            (if (result i32) (i32.eq (local.get $tag_a) (i32.const 7))
            \\                              (then (call $rt_list_equals (local.get $a) (local.get $b)))
            \\                              (else (if (result i32) (i32.eq (local.get $tag_a) (i32.const 8))
            \\                                (then (call $rt_vector_equals (local.get $a) (local.get $b)))
            \\                                (else (if (result i32) (i32.eq (local.get $tag_a) (i32.const 9))
            \\                                  (then (call $rt_map_equals (local.get $a) (local.get $b)))
            \\                                  (else (call $rt_set_equals (local.get $a) (local.get $b)))))))))
            \\                          (else (i32.const 0)))))))))))))))))
            \\
        ;
    }

    /// Generate $rt_less_than function
    /// Numeric less-than comparison (returns i32: 1=true, 0=false)
    pub fn emitLessThan(self: *RuntimeGen) ![]const u8 {
        _ = self;
        return
            \\  (func $rt_less_than (param $a (ref $Value)) (param $b (ref $Value)) (result i32)
            \\    (local $tag_a i32)
            \\    (local $tag_b i32)
            \\    (local.set $tag_a (struct.get $Value $tag (local.get $a)))
            \\    (local.set $tag_b (struct.get $Value $tag (local.get $b)))
            \\
            \\    ;; If both are longs, do i64 comparison
            \\    (if (result i32)
            \\      (i32.and
            \\        (i32.eq (local.get $tag_a) (i32.const 2))
            \\        (i32.eq (local.get $tag_b) (i32.const 2)))
            \\      (then
            \\        (i64.lt_s
            \\          (union.get $ValueData $long (struct.get $Value $data (local.get $a)))
            \\          (union.get $ValueData $long (struct.get $Value $data (local.get $b)))))
            \\      (else
            \\        ;; Otherwise coerce to double and compare
            \\        (f64.lt
            \\          (call $rt_to_double (local.get $a))
            \\          (call $rt_to_double (local.get $b))))))
            \\
        ;
    }

    /// Generate $rt_string_equals function
    /// String equality (hash-first optimization, then byte-by-byte comparison)
    pub fn emitStringEquals(self: *RuntimeGen) ![]const u8 {
        _ = self;
        return
            \\  (func $rt_string_equals (param $a (ref $String)) (param $b (ref $String)) (result i32)
            \\    (local $hash_a i32)
            \\    (local $hash_b i32)
            \\    (local $bytes_a (array i8))
            \\    (local $bytes_b (array i8))
            \\    (local $len i32)
            \\    (local $i i32)
            \\    (local.set $hash_a (struct.get $String $hash (local.get $a)))
            \\    (local.set $hash_b (struct.get $String $hash (local.get $b)))
            \\
            \\    ;; Fast path: different hashes → not equal
            \\    (if (result i32) (i32.ne (local.get $hash_a) (local.get $hash_b))
            \\      (then (i32.const 0))
            \\      (else
            \\        ;; Compare byte arrays
            \\        (local.set $bytes_a (struct.get $String $bytes (local.get $a)))
            \\        (local.set $bytes_b (struct.get $String $bytes (local.get $b)))
            \\        (local.set $len (array.len (local.get $bytes_a)))
            \\        ;; Different lengths → not equal
            \\        (if (result i32) (i32.ne (local.get $len) (array.len (local.get $bytes_b)))
            \\          (then (i32.const 0))
            \\          (else
            \\            ;; Byte-by-byte comparison
            \\            (local.set $i (i32.const 0))
            \\            (block $break (result i32)
            \\              (loop $continue (result i32)
            \\                (if (i32.ge_u (local.get $i) (local.get $len))
            \\                  (then (br $break (i32.const 1))))
            \\                (if (i32.ne
            \\                      (array.get_u $bytes_a (local.get $i))
            \\                      (array.get_u $bytes_b (local.get $i)))
            \\                  (then (br $break (i32.const 0))))
            \\                (local.set $i (i32.add (local.get $i) (i32.const 1)))
            \\                (br $continue)))))))
            \\)
            \\
        ;
    }

    /// Generate $rt_symbol_equals function
    /// Symbol equality (hash-first optimization, then namespace + name comparison)
    pub fn emitSymbolEquals(self: *RuntimeGen) ![]const u8 {
        _ = self;
        return
            \\  (func $rt_symbol_equals (param $a (ref $Symbol)) (param $b (ref $Symbol)) (result i32)
            \\    (local $hash_a i32)
            \\    (local $hash_b i32)
            \\    (local.set $hash_a (struct.get $Symbol $hash (local.get $a)))
            \\    (local.set $hash_b (struct.get $Symbol $hash (local.get $b)))
            \\
            \\    ;; Fast path: different hashes → not equal
            \\    (if (result i32) (i32.ne (local.get $hash_a) (local.get $hash_b))
            \\      (then (i32.const 0))
            \\      (else
            \\        ;; Full ns + name string comparison
            \\        (local $ns_a (ref null $String))
            \\        (local $ns_b (ref null $String))
            \\        (local.set $ns_a (struct.get $Symbol $ns (local.get $a)))
            \\        (local.set $ns_b (struct.get $Symbol $ns (local.get $b)))
            \\        ;; Compare namespaces
            \\        (if (result i32) (ref.is_null (local.get $ns_a))
            \\          (then
            \\            ;; a.ns is null: b.ns must also be null
            \\            (if (result i32) (ref.is_null (local.get $ns_b))
            \\              (then (call $rt_string_equals
            \\                      (struct.get $Symbol $name (local.get $a))
            \\                      (struct.get $Symbol $name (local.get $b))))
            \\              (else (i32.const 0))))
            \\          (else
            \\            ;; a.ns is non-null: b.ns must match
            \\            (if (result i32) (ref.is_null (local.get $ns_b))
            \\              (then (i32.const 0))
            \\              (else
            \\                (if (result i32) (call $rt_string_equals
            \\                                   (ref.as_non_null (local.get $ns_a))
            \\                                   (ref.as_non_null (local.get $ns_b)))
            \\                  (then (call $rt_string_equals
            \\                          (struct.get $Symbol $name (local.get $a))
            \\                          (struct.get $Symbol $name (local.get $b))))
            \\                  (else (i32.const 0)))))))))
            \\
            \\
        ;
    }

    /// Generate $rt_keyword_equals function
    /// Keyword equality (hash-first optimization, then namespace + name comparison)
    pub fn emitKeywordEquals(self: *RuntimeGen) ![]const u8 {
        _ = self;
        return
            \\  (func $rt_keyword_equals (param $a (ref $Keyword)) (param $b (ref $Keyword)) (result i32)
            \\    (local $hash_a i32)
            \\    (local $hash_b i32)
            \\    (local.set $hash_a (struct.get $Keyword $hash (local.get $a)))
            \\    (local.set $hash_b (struct.get $Keyword $hash (local.get $b)))
            \\
            \\    ;; Fast path: different hashes → not equal
            \\    (if (result i32) (i32.ne (local.get $hash_a) (local.get $hash_b))
            \\      (then (i32.const 0))
            \\      (else
            \\        ;; Full ns + name string comparison
            \\        (local $ns_a (ref null $String))
            \\        (local $ns_b (ref null $String))
            \\        (local.set $ns_a (struct.get $Keyword $ns (local.get $a)))
            \\        (local.set $ns_b (struct.get $Keyword $ns (local.get $b)))
            \\        ;; Compare namespaces
            \\        (if (result i32) (ref.is_null (local.get $ns_a))
            \\          (then
            \\            ;; a.ns is null: b.ns must also be null
            \\            (if (result i32) (ref.is_null (local.get $ns_b))
            \\              (then (call $rt_string_equals
            \\                      (struct.get $Keyword $name (local.get $a))
            \\                      (struct.get $Keyword $name (local.get $b))))
            \\              (else (i32.const 0))))
            \\          (else
            \\            ;; a.ns is non-null: b.ns must match
            \\            (if (result i32) (ref.is_null (local.get $ns_b))
            \\              (then (i32.const 0))
            \\              (else
            \\                (if (result i32) (call $rt_string_equals
            \\                                   (ref.as_non_null (local.get $ns_a))
            \\                                   (ref.as_non_null (local.get $ns_b)))
            \\                  (then (call $rt_string_equals
            \\                          (struct.get $Keyword $name (local.get $a))
            \\                          (struct.get $Keyword $name (local.get $b))))
            \\                  (else (i32.const 0)))))))))
            \\
            \\
        ;
    }

    /// Generate all runtime functions
    /// Emits all runtime support functions in one batch
    pub fn emitAllFunctions(self: *RuntimeGen) ![]const u8 {
        var buf = std.array_list.Managed(u8).init(self.arena);

        try buf.appendSlice( "\n  ;; Runtime support functions\n");
        try buf.appendSlice( try self.emitMakeString());
        try buf.appendSlice( "\n");
        try buf.appendSlice( try self.emitMakeSymbol());
        try buf.appendSlice( "\n");
        try buf.appendSlice( try self.emitMakeKeyword());
        try buf.appendSlice( "\n");
        try buf.appendSlice( try self.emitIsTruthy());
        try buf.appendSlice( "\n");
        try buf.appendSlice( try self.emitToDouble());
        try buf.appendSlice( "\n");
        try buf.appendSlice( try self.emitAdd());
        try buf.appendSlice( "\n");
        try buf.appendSlice( try self.emitSubtract());
        try buf.appendSlice( "\n");
        try buf.appendSlice( try self.emitMultiply());
        try buf.appendSlice( "\n");
        try buf.appendSlice( try self.emitDivide());
        try buf.appendSlice( "\n");
        try buf.appendSlice( try self.emitEquals());
        try buf.appendSlice( "\n");
        try buf.appendSlice( try self.emitLessThan());

        return buf.toOwnedSlice();
    }
};

