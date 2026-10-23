// collections_test.zig — Tests for persistent data structures

const std = @import("std");
const testing = std.testing;
const codegen = @import("codegen");
const collections = @import("collections");

// ============================================================================
// Vector Tests
// ============================================================================

test "Vector type definition generation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var wat = codegen.WAT.init(alloc);
    try collections.generateVectorTypeDef(&wat);

    const output = try wat.toString();

    // Check type definitions present
    try testing.expect(std.mem.indexOf(u8, output, "(type $VectorTail") != null);
    try testing.expect(std.mem.indexOf(u8, output, "(type $VectorNode") != null);
    try testing.expect(std.mem.indexOf(u8, output, "(type $PersistentVector") != null);
    try testing.expect(std.mem.indexOf(u8, output, "(field $count") != null);
    try testing.expect(std.mem.indexOf(u8, output, "(field $shift") != null);
    try testing.expect(std.mem.indexOf(u8, output, "(field $root") != null);
    try testing.expect(std.mem.indexOf(u8, output, "(field $tail") != null);
}

test "Vector runtime function: vector.new" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var wat = codegen.WAT.init(alloc);
    try collections.generateVectorNew(&wat);

    const output = try wat.toString();

    try testing.expect(std.mem.indexOf(u8, output, "(func $vector.new") != null);
    try testing.expect(std.mem.indexOf(u8, output, "(param $elements") != null);
    try testing.expect(std.mem.indexOf(u8, output, "(result (ref $PersistentVector))") != null);
    try testing.expect(std.mem.indexOf(u8, output, "array.new_default $VectorTail") != null);
    try testing.expect(std.mem.indexOf(u8, output, "struct.new $PersistentVector") != null);
}

test "Vector runtime function: vector.conj" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var wat = codegen.WAT.init(alloc);
    try collections.generateVectorConj(&wat);

    const output = try wat.toString();

    try testing.expect(std.mem.indexOf(u8, output, "(func $vector.conj") != null);
    try testing.expect(std.mem.indexOf(u8, output, "(param $vec (ref $PersistentVector))") != null);
    try testing.expect(std.mem.indexOf(u8, output, "(param $val (ref any))") != null);
    try testing.expect(std.mem.indexOf(u8, output, "array.set $VectorTail") != null);
}

test "Vector runtime function: vector.nth" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var wat = codegen.WAT.init(alloc);
    try collections.generateVectorNth(&wat);

    const output = try wat.toString();

    try testing.expect(std.mem.indexOf(u8, output, "(func $vector.nth") != null);
    try testing.expect(std.mem.indexOf(u8, output, "(param $idx i32)") != null);
    try testing.expect(std.mem.indexOf(u8, output, "array.get $VectorTail") != null);
    try testing.expect(std.mem.indexOf(u8, output, "i32.ge_u") != null); // bounds check
}

test "Vector runtime function: vector.count" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var wat = codegen.WAT.init(alloc);
    try collections.generateVectorCount(&wat);

    const output = try wat.toString();

    try testing.expect(std.mem.indexOf(u8, output, "(func $vector.count") != null);
    try testing.expect(std.mem.indexOf(u8, output, "struct.get $PersistentVector $count") != null);
}

// ============================================================================
// HashMap Tests
// ============================================================================

test "HashMap type definition generation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var wat = codegen.WAT.init(alloc);
    try collections.generateMapTypeDef(&wat);

    const output = try wat.toString();

    try testing.expect(std.mem.indexOf(u8, output, "(type $MapEntry") != null);
    try testing.expect(std.mem.indexOf(u8, output, "(type $MapNode") != null);
    try testing.expect(std.mem.indexOf(u8, output, "(type $PersistentHashMap") != null);
    try testing.expect(std.mem.indexOf(u8, output, "(field $bitmap") != null);
    try testing.expect(std.mem.indexOf(u8, output, "(field $children") != null);
}

test "HashMap runtime function: map.new" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var wat = codegen.WAT.init(alloc);
    try collections.generateMapNew(&wat);

    const output = try wat.toString();

    try testing.expect(std.mem.indexOf(u8, output, "(func $map.new") != null);
    try testing.expect(std.mem.indexOf(u8, output, "(result (ref $PersistentHashMap))") != null);
    try testing.expect(std.mem.indexOf(u8, output, "struct.new $PersistentHashMap") != null);
    try testing.expect(std.mem.indexOf(u8, output, "ref.null $MapNode") != null);
}

test "HashMap runtime function: map.assoc" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var wat = codegen.WAT.init(alloc);
    try collections.generateMapAssoc(&wat);

    const output = try wat.toString();

    try testing.expect(std.mem.indexOf(u8, output, "(func $map.assoc") != null);
    try testing.expect(std.mem.indexOf(u8, output, "(param $map (ref $PersistentHashMap))") != null);
    try testing.expect(std.mem.indexOf(u8, output, "(param $key (ref any))") != null);
    try testing.expect(std.mem.indexOf(u8, output, "(param $val (ref any))") != null);
    try testing.expect(std.mem.indexOf(u8, output, "call $runtime.hash") != null);
    try testing.expect(std.mem.indexOf(u8, output, "call $map.node_assoc") != null);
}

test "HashMap runtime function: map.get" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var wat = codegen.WAT.init(alloc);
    try collections.generateMapGet(&wat);

    const output = try wat.toString();

    try testing.expect(std.mem.indexOf(u8, output, "(func $map.get") != null);
    try testing.expect(std.mem.indexOf(u8, output, "call $runtime.hash") != null);
    try testing.expect(std.mem.indexOf(u8, output, "call $map.node_get") != null);
    try testing.expect(std.mem.indexOf(u8, output, "ref.is_null") != null);
}

test "HashMap runtime function: map.count" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var wat = codegen.WAT.init(alloc);
    try collections.generateMapCount(&wat);

    const output = try wat.toString();

    try testing.expect(std.mem.indexOf(u8, output, "(func $map.count") != null);
    try testing.expect(std.mem.indexOf(u8, output, "struct.get $PersistentHashMap $count") != null);
}

// ============================================================================
// HashSet Tests
// ============================================================================

test "HashSet type definition generation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var wat = codegen.WAT.init(alloc);
    try collections.generateSetTypeDef(&wat);

    const output = try wat.toString();

    try testing.expect(std.mem.indexOf(u8, output, "(type $PersistentHashSet") != null);
    try testing.expect(std.mem.indexOf(u8, output, "(field $map (ref $PersistentHashMap))") != null);
}

test "HashSet runtime function: set.new" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var wat = codegen.WAT.init(alloc);
    try collections.generateSetNew(&wat);

    const output = try wat.toString();

    try testing.expect(std.mem.indexOf(u8, output, "(func $set.new") != null);
    try testing.expect(std.mem.indexOf(u8, output, "call $map.new") != null);
    try testing.expect(std.mem.indexOf(u8, output, "struct.new $PersistentHashSet") != null);
}

test "HashSet runtime function: set.conj" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var wat = codegen.WAT.init(alloc);
    try collections.generateSetConj(&wat);

    const output = try wat.toString();

    try testing.expect(std.mem.indexOf(u8, output, "(func $set.conj") != null);
    try testing.expect(std.mem.indexOf(u8, output, "call $map.assoc") != null);
    try testing.expect(std.mem.indexOf(u8, output, "struct.get $PersistentHashSet $map") != null);
}

test "HashSet runtime function: set.contains" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var wat = codegen.WAT.init(alloc);
    try collections.generateSetContains(&wat);

    const output = try wat.toString();

    try testing.expect(std.mem.indexOf(u8, output, "(func $set.contains") != null);
    try testing.expect(std.mem.indexOf(u8, output, "call $map.get") != null);
    try testing.expect(std.mem.indexOf(u8, output, "ref.is_null") != null);
}

test "HashSet runtime function: set.count" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var wat = codegen.WAT.init(alloc);
    try collections.generateSetCount(&wat);

    const output = try wat.toString();

    try testing.expect(std.mem.indexOf(u8, output, "(func $set.count") != null);
    try testing.expect(std.mem.indexOf(u8, output, "call $map.count") != null);
}

// ============================================================================
// List Tests
// ============================================================================

test "List type definition generation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var wat = codegen.WAT.init(alloc);
    try collections.generateListTypeDef(&wat);

    const output = try wat.toString();

    try testing.expect(std.mem.indexOf(u8, output, "(type $List") != null);
    try testing.expect(std.mem.indexOf(u8, output, "(field $head") != null);
    try testing.expect(std.mem.indexOf(u8, output, "(field $tail") != null);
}

test "List runtime function: list.cons" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var wat = codegen.WAT.init(alloc);
    try collections.generateListCons(&wat);

    const output = try wat.toString();

    try testing.expect(std.mem.indexOf(u8, output, "(func $list.cons") != null);
    try testing.expect(std.mem.indexOf(u8, output, "(param $head (ref any))") != null);
    try testing.expect(std.mem.indexOf(u8, output, "(param $tail (ref null $List))") != null);
    try testing.expect(std.mem.indexOf(u8, output, "struct.new $List") != null);
}

test "List runtime function: list.first" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var wat = codegen.WAT.init(alloc);
    try collections.generateListFirst(&wat);

    const output = try wat.toString();

    try testing.expect(std.mem.indexOf(u8, output, "(func $list.first") != null);
    try testing.expect(std.mem.indexOf(u8, output, "struct.get $List $head") != null);
    try testing.expect(std.mem.indexOf(u8, output, "ref.is_null") != null);
}

test "List runtime function: list.rest" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var wat = codegen.WAT.init(alloc);
    try collections.generateListRest(&wat);

    const output = try wat.toString();

    try testing.expect(std.mem.indexOf(u8, output, "(func $list.rest") != null);
    try testing.expect(std.mem.indexOf(u8, output, "struct.get $List $tail") != null);
}

test "List runtime function: list.count" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var wat = codegen.WAT.init(alloc);
    try collections.generateListCount(&wat);

    const output = try wat.toString();

    try testing.expect(std.mem.indexOf(u8, output, "(func $list.count") != null);
    try testing.expect(std.mem.indexOf(u8, output, "(loop $continue") != null);
    try testing.expect(std.mem.indexOf(u8, output, "struct.get $List $tail") != null);
}

// ============================================================================
// Integration Tests
// ============================================================================

test "All collection type definitions" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var wat = codegen.WAT.init(alloc);
    try collections.generateAllTypeDefs(&wat);

    const output = try wat.toString();

    // Check all types present
    try testing.expect(std.mem.indexOf(u8, output, "$PersistentVector") != null);
    try testing.expect(std.mem.indexOf(u8, output, "$PersistentHashMap") != null);
    try testing.expect(std.mem.indexOf(u8, output, "$PersistentHashSet") != null);
    try testing.expect(std.mem.indexOf(u8, output, "$List") != null);
}

test "All collection runtime functions" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var wat = codegen.WAT.init(alloc);
    try collections.generateAllRuntimeFunctions(&wat);

    const output = try wat.toString();

    // Check key functions present
    try testing.expect(std.mem.indexOf(u8, output, "$vector.new") != null);
    try testing.expect(std.mem.indexOf(u8, output, "$vector.conj") != null);
    try testing.expect(std.mem.indexOf(u8, output, "$map.new") != null);
    try testing.expect(std.mem.indexOf(u8, output, "$map.assoc") != null);
    try testing.expect(std.mem.indexOf(u8, output, "$set.new") != null);
    try testing.expect(std.mem.indexOf(u8, output, "$list.cons") != null);
}
