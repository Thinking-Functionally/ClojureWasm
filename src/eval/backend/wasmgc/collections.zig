// collections.zig — Persistent data structures for WasmGC backend
//
// Implements:
// - PersistentVector (simplified with fixed 32-element tail)
// - PersistentHashMap (HAMT with bitmap nodes, 5-bit branching)
// - PersistentHashSet (wrapper around HashMap)
// - List (singly-linked list)
//
// Design constraints:
// - All operations must compile to WAT struct operations
// - Structural sharing for O(1) updates
// - No GC dependency (WasmGC manages lifetimes)

const std = @import("std");
const types = @import("types");
const codegen = @import("codegen");
const runtime = @import("runtime");

const Value = types.Value;
const ValueType = types.ValueType;
const WAT = codegen.WAT;

// ============================================================================
// PersistentVector — RRB-Tree simplified to fixed 32-element tail
// ============================================================================

/// Generates WAT struct definition for PersistentVector
/// Structure: { count: i32, shift: i32, root: (ref null $VectorNode), tail: (ref $VectorTail) }
pub fn generateVectorTypeDef(wat: *WAT) !void {
    // VectorTail: fixed 32-element array
    try wat.appendLine("(type $VectorTail (array (mut (ref null any))))");

    // VectorNode: internal node with 32 children
    try wat.appendLine("(type $VectorNode (struct");
    wat.indent();
    try wat.appendLine("(field $children (ref $VectorTail))");
    wat.dedent();
    try wat.appendLine("))");

    // PersistentVector: main structure
    try wat.appendLine("(type $PersistentVector (struct");
    wat.indent();
    try wat.appendLine("(field $count (mut i32))");
    try wat.appendLine("(field $shift (mut i32))");
    try wat.appendLine("(field $root (mut (ref null $VectorNode)))");
    try wat.appendLine("(field $tail (mut (ref $VectorTail)))");
    wat.dedent();
    try wat.appendLine("))");
}

/// Compiles vector literal: [1 2 3] → (call $vector.new ...)
pub fn compileVectorLiteral(wat: *WAT, elements: []const Value) !void {
    try wat.append("(call $vector.new");
    for (elements) |elem| {
        try wat.append(" ");
        try compileValue(wat, elem);
    }
    try wat.append(")");
}

/// Generates runtime function: vector.new
pub fn generateVectorNew(wat: *WAT) !void {
    try wat.appendLine("(func $vector.new (param $elements (ref $List)) (result (ref $PersistentVector))");
    wat.indent();
    try wat.appendLine("(local $vec (ref $PersistentVector))");
    try wat.appendLine("(local $tail (ref $VectorTail))");
    try wat.appendLine("(local $count i32)");

    // Count elements
    try wat.appendLine("(local.set $count (call $list.count (local.get $elements)))");

    // Create empty tail
    try wat.appendLine("(local.set $tail");
    wat.indent();
    try wat.appendLine("(array.new_default $VectorTail (i32.const 32))");
    wat.dedent();
    try wat.appendLine(")");

    // Fill tail from list
    try wat.appendLine("(call $vector.fill_tail (local.get $tail) (local.get $elements))");

    // Create vector struct
    try wat.appendLine("(struct.new $PersistentVector");
    wat.indent();
    try wat.appendLine("(local.get $count)");
    try wat.appendLine("(i32.const 5) ;; shift = 5 (32 = 2^5)");
    try wat.appendLine("(ref.null $VectorNode) ;; no root yet");
    try wat.appendLine("(local.get $tail)");
    wat.dedent();
    try wat.appendLine(")");

    wat.dedent();
    try wat.appendLine(")");
}

/// Generates runtime function: vector.conj
pub fn generateVectorConj(wat: *WAT) !void {
    try wat.appendLine("(func $vector.conj (param $vec (ref $PersistentVector)) (param $val (ref any)) (result (ref $PersistentVector))");
    wat.indent();
    try wat.appendLine("(local $count i32)");
    try wat.appendLine("(local $tail_len i32)");
    try wat.appendLine("(local $new_tail (ref $VectorTail))");

    try wat.appendLine("(local.set $count (struct.get $PersistentVector $count (local.get $vec)))");
    try wat.appendLine("(local.set $tail_len (i32.rem_u (local.get $count) (i32.const 32)))");

    // If tail not full, copy tail + append
    try wat.appendLine("(if (i32.lt_u (local.get $tail_len) (i32.const 32))");
    wat.indent();
    try wat.appendLine("(then");
    wat.indent();
    try wat.appendLine("(local.set $new_tail (call $vector.copy_tail");
    wat.indent();
    try wat.appendLine("(struct.get $PersistentVector $tail (local.get $vec))");
    try wat.appendLine("(local.get $tail_len)");
    wat.dedent();
    try wat.appendLine("))");
    try wat.appendLine("(array.set $VectorTail (local.get $new_tail) (local.get $tail_len) (local.get $val))");
    try wat.appendLine("(return (struct.new $PersistentVector");
    wat.indent();
    try wat.appendLine("(i32.add (local.get $count) (i32.const 1))");
    try wat.appendLine("(struct.get $PersistentVector $shift (local.get $vec))");
    try wat.appendLine("(struct.get $PersistentVector $root (local.get $vec))");
    try wat.appendLine("(local.get $new_tail)");
    wat.dedent();
    try wat.appendLine("))");
    wat.dedent();
    try wat.appendLine(")");
    wat.dedent();
    try wat.appendLine(")");

    // Tail full: push to root, create new tail
    try wat.appendLine("(unreachable) ;; TODO: handle tail overflow → push to root");

    wat.dedent();
    try wat.appendLine(")");
}

/// Generates runtime function: vector.nth
pub fn generateVectorNth(wat: *WAT) !void {
    try wat.appendLine("(func $vector.nth (param $vec (ref $PersistentVector)) (param $idx i32) (result (ref any))");
    wat.indent();
    try wat.appendLine("(local $count i32)");
    try wat.appendLine("(local $tail_offset i32)");

    try wat.appendLine("(local.set $count (struct.get $PersistentVector $count (local.get $vec)))");

    // Bounds check
    try wat.appendLine("(if (i32.ge_u (local.get $idx) (local.get $count))");
    wat.indent();
    try wat.appendLine("(then (unreachable)) ;; IndexOutOfBounds");
    wat.dedent();
    try wat.appendLine(")");

    // Calculate tail offset (count - (count % 32))
    try wat.appendLine("(local.set $tail_offset");
    wat.indent();
    try wat.appendLine("(i32.sub (local.get $count)");
    wat.indent();
    try wat.appendLine("(i32.rem_u (local.get $count) (i32.const 32))");
    wat.dedent();
    try wat.appendLine(")");
    wat.dedent();
    try wat.appendLine(")");

    // If idx >= tail_offset, read from tail
    try wat.appendLine("(if (i32.ge_u (local.get $idx) (local.get $tail_offset))");
    wat.indent();
    try wat.appendLine("(then");
    wat.indent();
    try wat.appendLine("(return (array.get $VectorTail");
    wat.indent();
    try wat.appendLine("(struct.get $PersistentVector $tail (local.get $vec))");
    try wat.appendLine("(i32.sub (local.get $idx) (local.get $tail_offset))");
    wat.dedent();
    try wat.appendLine("))");
    wat.dedent();
    try wat.appendLine(")");
    wat.dedent();
    try wat.appendLine(")");

    // Otherwise, navigate root tree
    try wat.appendLine("(unreachable) ;; TODO: navigate root tree for idx < tail_offset");

    wat.dedent();
    try wat.appendLine(")");
}

/// Generates runtime function: vector.count
pub fn generateVectorCount(wat: *WAT) !void {
    try wat.appendLine("(func $vector.count (param $vec (ref $PersistentVector)) (result i32)");
    wat.indent();
    try wat.appendLine("(struct.get $PersistentVector $count (local.get $vec))");
    wat.dedent();
    try wat.appendLine(")");
}

// ============================================================================
// PersistentHashMap — HAMT with 5-bit branching (32-way tree)
// ============================================================================

/// Generates WAT struct definition for PersistentHashMap
/// Structure: { count: i32, root: (ref null $MapNode) }
/// MapNode: { bitmap: i32, children: (ref $MapNodeArray) }
pub fn generateMapTypeDef(wat: *WAT) !void {
    // MapEntry: key-value pair
    try wat.appendLine("(type $MapEntry (struct");
    wat.indent();
    try wat.appendLine("(field $key (ref any))");
    try wat.appendLine("(field $val (ref any))");
    try wat.appendLine("(field $hash i32)");
    wat.dedent();
    try wat.appendLine("))");

    // MapNodeArray: flexible array of (ref null any) — either MapNode or MapEntry
    try wat.appendLine("(type $MapNodeArray (array (mut (ref null any))))");

    // MapNode: HAMT internal node
    try wat.appendLine("(type $MapNode (struct");
    wat.indent();
    try wat.appendLine("(field $bitmap i32) ;; 32-bit bitmap for present children");
    try wat.appendLine("(field $children (ref $MapNodeArray))");
    wat.dedent();
    try wat.appendLine("))");

    // PersistentHashMap: main structure
    try wat.appendLine("(type $PersistentHashMap (struct");
    wat.indent();
    try wat.appendLine("(field $count (mut i32))");
    try wat.appendLine("(field $root (mut (ref null $MapNode)))");
    wat.dedent();
    try wat.appendLine("))");
}

/// Compiles map literal: {:a 1 :b 2} → (call $map.new ...)
pub fn compileMapLiteral(wat: *WAT, entries: []const struct { key: Value, val: Value }) !void {
    try wat.append("(call $map.new");
    for (entries) |entry| {
        try wat.append(" ");
        try compileValue(wat, entry.key);
        try wat.append(" ");
        try compileValue(wat, entry.val);
    }
    try wat.append(")");
}

/// Generates runtime function: map.new
pub fn generateMapNew(wat: *WAT) !void {
    try wat.appendLine("(func $map.new (result (ref $PersistentHashMap))");
    wat.indent();
    try wat.appendLine("(struct.new $PersistentHashMap");
    wat.indent();
    try wat.appendLine("(i32.const 0) ;; count = 0");
    try wat.appendLine("(ref.null $MapNode) ;; empty root");
    wat.dedent();
    try wat.appendLine(")");
    wat.dedent();
    try wat.appendLine(")");
}

/// Generates runtime function: map.assoc
pub fn generateMapAssoc(wat: *WAT) !void {
    try wat.appendLine("(func $map.assoc (param $map (ref $PersistentHashMap)) (param $key (ref any)) (param $val (ref any)) (result (ref $PersistentHashMap))");
    wat.indent();
    try wat.appendLine("(local $hash i32)");
    try wat.appendLine("(local $new_root (ref null $MapNode))");
    try wat.appendLine("(local $old_root (ref null $MapNode))");

    // Compute hash
    try wat.appendLine("(local.set $hash (call $runtime.hash (local.get $key)))");
    try wat.appendLine("(local.set $old_root (struct.get $PersistentHashMap $root (local.get $map)))");

    // Insert into HAMT
    try wat.appendLine("(local.set $new_root");
    wat.indent();
    try wat.appendLine("(call $map.node_assoc");
    wat.indent();
    try wat.appendLine("(local.get $old_root)");
    try wat.appendLine("(i32.const 0) ;; shift = 0 (root level)");
    try wat.appendLine("(local.get $hash)");
    try wat.appendLine("(local.get $key)");
    try wat.appendLine("(local.get $val)");
    wat.dedent();
    try wat.appendLine(")");
    wat.dedent();
    try wat.appendLine(")");

    // Return new map
    try wat.appendLine("(struct.new $PersistentHashMap");
    wat.indent();
    try wat.appendLine("(i32.add");
    wat.indent();
    try wat.appendLine("(struct.get $PersistentHashMap $count (local.get $map))");
    try wat.appendLine("(i32.const 1)");
    wat.dedent();
    try wat.appendLine(")");
    try wat.appendLine("(local.get $new_root)");
    wat.dedent();
    try wat.appendLine(")");

    wat.dedent();
    try wat.appendLine(")");
}

/// Generates runtime function: map.get
pub fn generateMapGet(wat: *WAT) !void {
    try wat.appendLine("(func $map.get (param $map (ref $PersistentHashMap)) (param $key (ref any)) (result (ref null any))");
    wat.indent();
    try wat.appendLine("(local $hash i32)");
    try wat.appendLine("(local $root (ref null $MapNode))");

    try wat.appendLine("(local.set $hash (call $runtime.hash (local.get $key)))");
    try wat.appendLine("(local.set $root (struct.get $PersistentHashMap $root (local.get $map)))");

    // Navigate HAMT
    try wat.appendLine("(if (ref.is_null (local.get $root))");
    wat.indent();
    try wat.appendLine("(then (return (ref.null any)))");
    wat.dedent();
    try wat.appendLine(")");

    try wat.appendLine("(call $map.node_get");
    wat.indent();
    try wat.appendLine("(ref.as_non_null (local.get $root))");
    try wat.appendLine("(i32.const 0) ;; shift = 0");
    try wat.appendLine("(local.get $hash)");
    try wat.appendLine("(local.get $key)");
    wat.dedent();
    try wat.appendLine(")");

    wat.dedent();
    try wat.appendLine(")");
}

/// Generates runtime function: map.count
pub fn generateMapCount(wat: *WAT) !void {
    try wat.appendLine("(func $map.count (param $map (ref $PersistentHashMap)) (result i32)");
    wat.indent();
    try wat.appendLine("(struct.get $PersistentHashMap $count (local.get $map))");
    wat.dedent();
    try wat.appendLine(")");
}

// ============================================================================
// PersistentHashSet — wrapper around PersistentHashMap
// ============================================================================

/// Generates WAT struct definition for PersistentHashSet
/// Structure: { map: (ref $PersistentHashMap) }
pub fn generateSetTypeDef(wat: *WAT) !void {
    try wat.appendLine("(type $PersistentHashSet (struct");
    wat.indent();
    try wat.appendLine("(field $map (ref $PersistentHashMap))");
    wat.dedent();
    try wat.appendLine("))");
}

/// Compiles set literal: #{1 2 3} → (call $set.new ...)
pub fn compileSetLiteral(wat: *WAT, elements: []const Value) !void {
    try wat.append("(call $set.new");
    for (elements) |elem| {
        try wat.append(" ");
        try compileValue(wat, elem);
    }
    try wat.append(")");
}

/// Generates runtime function: set.new
pub fn generateSetNew(wat: *WAT) !void {
    try wat.appendLine("(func $set.new (result (ref $PersistentHashSet))");
    wat.indent();
    try wat.appendLine("(struct.new $PersistentHashSet");
    wat.indent();
    try wat.appendLine("(call $map.new)");
    wat.dedent();
    try wat.appendLine(")");
    wat.dedent();
    try wat.appendLine(")");
}

/// Generates runtime function: set.conj
pub fn generateSetConj(wat: *WAT) !void {
    try wat.appendLine("(func $set.conj (param $set (ref $PersistentHashSet)) (param $val (ref any)) (result (ref $PersistentHashSet))");
    wat.indent();
    try wat.appendLine("(local $map (ref $PersistentHashMap))");

    try wat.appendLine("(local.set $map");
    wat.indent();
    try wat.appendLine("(call $map.assoc");
    wat.indent();
    try wat.appendLine("(struct.get $PersistentHashSet $map (local.get $set))");
    try wat.appendLine("(local.get $val)");
    try wat.appendLine("(local.get $val) ;; value = key for sets");
    wat.dedent();
    try wat.appendLine(")");
    wat.dedent();
    try wat.appendLine(")");

    try wat.appendLine("(struct.new $PersistentHashSet (local.get $map))");

    wat.dedent();
    try wat.appendLine(")");
}

/// Generates runtime function: set.contains
pub fn generateSetContains(wat: *WAT) !void {
    try wat.appendLine("(func $set.contains (param $set (ref $PersistentHashSet)) (param $val (ref any)) (result i32)");
    wat.indent();
    try wat.appendLine("(local $result (ref null any))");

    try wat.appendLine("(local.set $result");
    wat.indent();
    try wat.appendLine("(call $map.get");
    wat.indent();
    try wat.appendLine("(struct.get $PersistentHashSet $map (local.get $set))");
    try wat.appendLine("(local.get $val)");
    wat.dedent();
    try wat.appendLine(")");
    wat.dedent();
    try wat.appendLine(")");

    try wat.appendLine("(if (result i32) (ref.is_null (local.get $result))");
    wat.indent();
    try wat.appendLine("(then (i32.const 0))");
    try wat.appendLine("(else (i32.const 1))");
    wat.dedent();
    try wat.appendLine(")");

    wat.dedent();
    try wat.appendLine(")");
}

/// Generates runtime function: set.count
pub fn generateSetCount(wat: *WAT) !void {
    try wat.appendLine("(func $set.count (param $set (ref $PersistentHashSet)) (result i32)");
    wat.indent();
    try wat.appendLine("(call $map.count");
    wat.indent();
    try wat.appendLine("(struct.get $PersistentHashSet $map (local.get $set))");
    wat.dedent();
    try wat.appendLine(")");
    wat.dedent();
    try wat.appendLine(")");
}

// ============================================================================
// List — singly-linked list (cons cells)
// ============================================================================

/// Generates WAT struct definition for List
/// Structure: { head: (ref any), tail: (ref null $List) }
pub fn generateListTypeDef(wat: *WAT) !void {
    try wat.appendLine("(type $List (struct");
    wat.indent();
    try wat.appendLine("(field $head (ref any))");
    try wat.appendLine("(field $tail (ref null $List))");
    wat.dedent();
    try wat.appendLine("))");
}

/// Compiles list literal: (list 1 2 3) → (call $list.new ...)
pub fn compileListLiteral(wat: *WAT, elements: []const Value) !void {
    if (elements.len == 0) {
        try wat.append("(ref.null $List)");
        return;
    }

    // Build from right to left: (cons 1 (cons 2 (cons 3 nil)))
    var i: usize = elements.len;
    while (i > 0) {
        i -= 1;
        try wat.append("(struct.new $List ");
        try compileValue(wat, elements[i]);
        try wat.append(" ");
    }
    try wat.append("(ref.null $List)");
    for (0..elements.len) |_| {
        try wat.append(")");
    }
}

/// Generates runtime function: list.cons
pub fn generateListCons(wat: *WAT) !void {
    try wat.appendLine("(func $list.cons (param $head (ref any)) (param $tail (ref null $List)) (result (ref $List))");
    wat.indent();
    try wat.appendLine("(struct.new $List (local.get $head) (local.get $tail))");
    wat.dedent();
    try wat.appendLine(")");
}

/// Generates runtime function: list.first
pub fn generateListFirst(wat: *WAT) !void {
    try wat.appendLine("(func $list.first (param $list (ref null $List)) (result (ref null any))");
    wat.indent();
    try wat.appendLine("(if (ref.is_null (local.get $list))");
    wat.indent();
    try wat.appendLine("(then (return (ref.null any)))");
    wat.dedent();
    try wat.appendLine(")");
    try wat.appendLine("(struct.get $List $head (ref.as_non_null (local.get $list)))");
    wat.dedent();
    try wat.appendLine(")");
}

/// Generates runtime function: list.rest
pub fn generateListRest(wat: *WAT) !void {
    try wat.appendLine("(func $list.rest (param $list (ref null $List)) (result (ref null $List))");
    wat.indent();
    try wat.appendLine("(if (ref.is_null (local.get $list))");
    wat.indent();
    try wat.appendLine("(then (return (ref.null $List)))");
    wat.dedent();
    try wat.appendLine(")");
    try wat.appendLine("(struct.get $List $tail (ref.as_non_null (local.get $list)))");
    wat.dedent();
    try wat.appendLine(")");
}

/// Generates runtime function: list.count
pub fn generateListCount(wat: *WAT) !void {
    try wat.appendLine("(func $list.count (param $list (ref null $List)) (result i32)");
    wat.indent();
    try wat.appendLine("(local $count i32)");
    try wat.appendLine("(local $current (ref null $List))");

    try wat.appendLine("(local.set $count (i32.const 0))");
    try wat.appendLine("(local.set $current (local.get $list))");

    // Loop through list
    try wat.appendLine("(block $break");
    wat.indent();
    try wat.appendLine("(loop $continue");
    wat.indent();
    try wat.appendLine("(if (ref.is_null (local.get $current))");
    wat.indent();
    try wat.appendLine("(then (br $break))");
    wat.dedent();
    try wat.appendLine(")");
    try wat.appendLine("(local.set $count (i32.add (local.get $count) (i32.const 1)))");
    try wat.appendLine("(local.set $current (struct.get $List $tail (ref.as_non_null (local.get $current))))");
    try wat.appendLine("(br $continue)");
    wat.dedent();
    try wat.appendLine(")");
    wat.dedent();
    try wat.appendLine(")");

    try wat.appendLine("(local.get $count)");

    wat.dedent();
    try wat.appendLine(")");
}

// ============================================================================
// HAMT Helper Functions (internal operations)
// ============================================================================

/// Generates map.node_assoc: insert key-value into HAMT node (recursively)
pub fn generateMapNodeAssoc(wat: *WAT) !void {
    try wat.appendLine("(func $map.node_assoc");
    wat.indent();
    try wat.appendLine("(param $node (ref null $MapNode))");
    try wat.appendLine("(param $shift i32)");
    try wat.appendLine("(param $hash i32)");
    try wat.appendLine("(param $key (ref any))");
    try wat.appendLine("(param $val (ref any))");
    try wat.appendLine("(result (ref $MapNode))");
    try wat.appendLine("(local $idx i32)");
    try wat.appendLine("(local $bit i32)");
    try wat.appendLine("(local $bitmap i32)");

    // If node is null, create new node with single entry
    try wat.appendLine("(if (ref.is_null (local.get $node))");
    wat.indent();
    try wat.appendLine("(then");
    wat.indent();
    try wat.appendLine("(return (call $map.node_create_single");
    wat.indent();
    try wat.appendLine("(local.get $hash)");
    try wat.appendLine("(local.get $key)");
    try wat.appendLine("(local.get $val)");
    try wat.appendLine("(local.get $shift)");
    wat.dedent();
    try wat.appendLine("))");
    wat.dedent();
    try wat.appendLine(")");
    wat.dedent();
    try wat.appendLine(")");

    // Extract 5 bits at current shift level
    try wat.appendLine("(local.set $idx");
    wat.indent();
    try wat.appendLine("(i32.and");
    wat.indent();
    try wat.appendLine("(i32.shr_u (local.get $hash) (local.get $shift))");
    try wat.appendLine("(i32.const 31) ;; 0x1F = 5 bits");
    wat.dedent();
    try wat.appendLine(")");
    wat.dedent();
    try wat.appendLine(")");

    try wat.appendLine("(local.set $bit (i32.shl (i32.const 1) (local.get $idx)))");
    try wat.appendLine("(local.set $bitmap (struct.get $MapNode $bitmap (ref.as_non_null (local.get $node))))");

    // Check if bit is set
    try wat.appendLine("(if (i32.eqz (i32.and (local.get $bitmap) (local.get $bit)))");
    wat.indent();
    try wat.appendLine("(then");
    wat.indent();
    try wat.appendLine(";; Bit not set: insert new entry");
    try wat.appendLine("(return (call $map.node_insert_entry");
    wat.indent();
    try wat.appendLine("(ref.as_non_null (local.get $node))");
    try wat.appendLine("(local.get $bit)");
    try wat.appendLine("(local.get $key)");
    try wat.appendLine("(local.get $val)");
    try wat.appendLine("(local.get $hash)");
    wat.dedent();
    try wat.appendLine("))");
    wat.dedent();
    try wat.appendLine(")");
    wat.dedent();
    try wat.appendLine(")");

    // Bit is set: recurse or update
    try wat.appendLine("(unreachable) ;; TODO: handle collision (recurse deeper)");

    wat.dedent();
    try wat.appendLine(")");
}

/// Generates map.node_get: lookup key in HAMT node
pub fn generateMapNodeGet(wat: *WAT) !void {
    try wat.appendLine("(func $map.node_get");
    wat.indent();
    try wat.appendLine("(param $node (ref $MapNode))");
    try wat.appendLine("(param $shift i32)");
    try wat.appendLine("(param $hash i32)");
    try wat.appendLine("(param $key (ref any))");
    try wat.appendLine("(result (ref null any))");
    try wat.appendLine("(local $idx i32)");
    try wat.appendLine("(local $bit i32)");
    try wat.appendLine("(local $bitmap i32)");

    // Extract 5 bits at current level
    try wat.appendLine("(local.set $idx");
    wat.indent();
    try wat.appendLine("(i32.and");
    wat.indent();
    try wat.appendLine("(i32.shr_u (local.get $hash) (local.get $shift))");
    try wat.appendLine("(i32.const 31)");
    wat.dedent();
    try wat.appendLine(")");
    wat.dedent();
    try wat.appendLine(")");

    try wat.appendLine("(local.set $bit (i32.shl (i32.const 1) (local.get $idx)))");
    try wat.appendLine("(local.set $bitmap (struct.get $MapNode $bitmap (local.get $node)))");

    // Check if bit is set
    try wat.appendLine("(if (i32.eqz (i32.and (local.get $bitmap) (local.get $bit)))");
    wat.indent();
    try wat.appendLine("(then (return (ref.null any)))");
    wat.dedent();
    try wat.appendLine(")");

    // Bit is set: find entry in sparse array
    try wat.appendLine("(unreachable) ;; TODO: navigate sparse array + recurse");

    wat.dedent();
    try wat.appendLine(")");
}

/// Generates map.node_create_single: create single-entry node
fn generateMapNodeCreateSingle(wat: *WAT) !void {
    try wat.appendLine("(func $map.node_create_single");
    wat.indent();
    try wat.appendLine("(param $hash i32)");
    try wat.appendLine("(param $key (ref any))");
    try wat.appendLine("(param $val (ref any))");
    try wat.appendLine("(param $shift i32)");
    try wat.appendLine("(result (ref $MapNode))");
    try wat.appendLine("(local $idx i32)");
    try wat.appendLine("(local $bit i32)");
    try wat.appendLine("(local $entry (ref $MapEntry))");
    try wat.appendLine("(local $children (ref $MapNodeArray))");

    // Calculate index from hash
    try wat.appendLine("(local.set $idx");
    wat.indent();
    try wat.appendLine("(i32.and");
    wat.indent();
    try wat.appendLine("(i32.shr_u (local.get $hash) (local.get $shift))");
    try wat.appendLine("(i32.const 31)");
    wat.dedent();
    try wat.appendLine(")");
    wat.dedent();
    try wat.appendLine(")");

    try wat.appendLine("(local.set $bit (i32.shl (i32.const 1) (local.get $idx)))");

    // Create entry
    try wat.appendLine("(local.set $entry");
    wat.indent();
    try wat.appendLine("(struct.new $MapEntry");
    wat.indent();
    try wat.appendLine("(local.get $key)");
    try wat.appendLine("(local.get $val)");
    try wat.appendLine("(local.get $hash)");
    wat.dedent();
    try wat.appendLine(")");
    wat.dedent();
    try wat.appendLine(")");

    // Create array with single entry
    try wat.appendLine("(local.set $children");
    wat.indent();
    try wat.appendLine("(array.new_fixed $MapNodeArray 1 (local.get $entry))");
    wat.dedent();
    try wat.appendLine(")");

    // Return node
    try wat.appendLine("(struct.new $MapNode");
    wat.indent();
    try wat.appendLine("(local.get $bit)");
    try wat.appendLine("(local.get $children)");
    wat.dedent();
    try wat.appendLine(")");

    wat.dedent();
    try wat.appendLine(")");
}

/// Generates map.node_insert_entry: insert entry into existing node
fn generateMapNodeInsertEntry(wat: *WAT) !void {
    try wat.appendLine("(func $map.node_insert_entry");
    wat.indent();
    try wat.appendLine("(param $node (ref $MapNode))");
    try wat.appendLine("(param $bit i32)");
    try wat.appendLine("(param $key (ref any))");
    try wat.appendLine("(param $val (ref any))");
    try wat.appendLine("(param $hash i32)");
    try wat.appendLine("(result (ref $MapNode))");
    try wat.appendLine("(local $new_bitmap i32)");
    try wat.appendLine("(local $entry (ref $MapEntry))");

    // Create new entry
    try wat.appendLine("(local.set $entry");
    wat.indent();
    try wat.appendLine("(struct.new $MapEntry");
    wat.indent();
    try wat.appendLine("(local.get $key)");
    try wat.appendLine("(local.get $val)");
    try wat.appendLine("(local.get $hash)");
    wat.dedent();
    try wat.appendLine(")");
    wat.dedent();
    try wat.appendLine(")");

    // Update bitmap
    try wat.appendLine("(local.set $new_bitmap");
    wat.indent();
    try wat.appendLine("(i32.or");
    wat.indent();
    try wat.appendLine("(struct.get $MapNode $bitmap (local.get $node))");
    try wat.appendLine("(local.get $bit)");
    wat.dedent();
    try wat.appendLine(")");
    wat.dedent();
    try wat.appendLine(")");

    // Copy and expand children array
    try wat.appendLine("(unreachable) ;; TODO: copy children array + insert at sparse index");

    wat.dedent();
    try wat.appendLine(")");
}

/// Generates vector.copy_tail: copy tail array with new capacity
fn generateVectorCopyTail(wat: *WAT) !void {
    try wat.appendLine("(func $vector.copy_tail");
    wat.indent();
    try wat.appendLine("(param $old_tail (ref $VectorTail))");
    try wat.appendLine("(param $len i32)");
    try wat.appendLine("(result (ref $VectorTail))");
    try wat.appendLine("(local $new_tail (ref $VectorTail))");
    try wat.appendLine("(local $i i32)");

    try wat.appendLine("(local.set $new_tail (array.new_default $VectorTail (i32.const 32)))");
    try wat.appendLine("(local.set $i (i32.const 0))");

    // Copy loop
    try wat.appendLine("(block $break");
    wat.indent();
    try wat.appendLine("(loop $continue");
    wat.indent();
    try wat.appendLine("(if (i32.ge_u (local.get $i) (local.get $len))");
    wat.indent();
    try wat.appendLine("(then (br $break))");
    wat.dedent();
    try wat.appendLine(")");
    try wat.appendLine("(array.set $VectorTail");
    wat.indent();
    try wat.appendLine("(local.get $new_tail)");
    try wat.appendLine("(local.get $i)");
    try wat.appendLine("(array.get $VectorTail (local.get $old_tail) (local.get $i))");
    wat.dedent();
    try wat.appendLine(")");
    try wat.appendLine("(local.set $i (i32.add (local.get $i) (i32.const 1)))");
    try wat.appendLine("(br $continue)");
    wat.dedent();
    try wat.appendLine(")");
    wat.dedent();
    try wat.appendLine(")");

    try wat.appendLine("(local.get $new_tail)");

    wat.dedent();
    try wat.appendLine(")");
}

/// Generates vector.fill_tail: fill tail from list elements
fn generateVectorFillTail(wat: *WAT) !void {
    try wat.appendLine("(func $vector.fill_tail");
    wat.indent();
    try wat.appendLine("(param $tail (ref $VectorTail))");
    try wat.appendLine("(param $list (ref $List))");
    try wat.appendLine("(local $current (ref null $List))");
    try wat.appendLine("(local $i i32)");

    try wat.appendLine("(local.set $current (local.get $list))");
    try wat.appendLine("(local.set $i (i32.const 0))");

    try wat.appendLine("(block $break");
    wat.indent();
    try wat.appendLine("(loop $continue");
    wat.indent();
    try wat.appendLine("(if (ref.is_null (local.get $current))");
    wat.indent();
    try wat.appendLine("(then (br $break))");
    wat.dedent();
    try wat.appendLine(")");
    try wat.appendLine("(array.set $VectorTail");
    wat.indent();
    try wat.appendLine("(local.get $tail)");
    try wat.appendLine("(local.get $i)");
    try wat.appendLine("(struct.get $List $head (ref.as_non_null (local.get $current)))");
    wat.dedent();
    try wat.appendLine(")");
    try wat.appendLine("(local.set $i (i32.add (local.get $i) (i32.const 1)))");
    try wat.appendLine("(local.set $current (struct.get $List $tail (ref.as_non_null (local.get $current))))");
    try wat.appendLine("(br $continue)");
    wat.dedent();
    try wat.appendLine(")");
    wat.dedent();
    try wat.appendLine(")");

    wat.dedent();
    try wat.appendLine(")");
}

// ============================================================================
// Helper functions
// ============================================================================

fn compileValue(wat: *WAT, value: Value) !void {
    _ = wat;
    _ = value;
    // Stub: actual implementation delegates to compiler.zig
    @panic("compileValue should be imported from compiler.zig");
}

// ============================================================================
// Module exports
// ============================================================================

/// Generates all collection type definitions
pub fn generateAllTypeDefs(wat: *WAT) !void {
    try generateVectorTypeDef(wat);
    try generateMapTypeDef(wat);
    try generateSetTypeDef(wat);
    try generateListTypeDef(wat);
}

/// Generates all collection runtime functions
pub fn generateAllRuntimeFunctions(wat: *WAT) !void {
    // Vector operations
    try generateVectorNew(wat);

    try generateVectorConj(wat);
    try generateVectorNth(wat);
    try generateVectorCount(wat);
    try generateVectorCopyTail(wat);
    try generateVectorFillTail(wat);

    // Map operations
    try generateMapNew(wat);

    try generateMapAssoc(wat);
    try generateMapGet(wat);
    try generateMapCount(wat);
    try generateMapNodeAssoc(wat);
    try generateMapNodeGet(wat);
    try generateMapNodeCreateSingle(wat);
    try generateMapNodeInsertEntry(wat);

    // Set operations
    try generateSetNew(wat);
    try generateSetConj(wat);
    try generateSetContains(wat);
    try generateSetCount(wat);

    // List operations
    try generateListCons(wat);
    try generateListFirst(wat);
    try generateListRest(wat);
    try generateListCount(wat);
}

