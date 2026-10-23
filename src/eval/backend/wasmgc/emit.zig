// SPDX-License-Identifier: EPL-2.0
//! Centralized WAT (WebAssembly Text) emission utilities for WasmGC backend
//!
//! This module consolidates all WAT code generation functionality:
//! - Instruction emission (struct.new, call, local.get, etc.)
//! - Control flow (if, loop, block, br)
//! - Type declarations (struct, func, array)
//! - Module structure (imports, exports, globals)
//! - Metadata support (custom sections, source maps)
//! - Exception handling (try, catch, throw)
//!
//! Design principles:
//! - Single source of truth for WAT syntax
//! - Consistent formatting and indentation
//! - Type-safe emission (validates at construction time where possible)
//! - Zero-allocation fast paths for common cases
//! - Support for debugging (source location tracking, readable output)

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Indentation and Formatting
// ============================================================================

/// Indentation context for WAT output
pub const IndentContext = struct {
    level: u32,
    spaces_per_level: u32,

    pub fn init() IndentContext {
        return .{
            .level = 0,
            .spaces_per_level = 2,
        };
    }

    pub fn push(self: *IndentContext) void {
        self.level += 1;
    }

    pub fn pop(self: *IndentContext) void {
        if (self.level > 0) {
            self.level -= 1;
        }
    }

    pub fn spaces(self: IndentContext, allocator: Allocator) ![]const u8 {
        const count = self.level * self.spaces_per_level;
        if (count == 0) return "";

        const buf = try allocator.alloc(u8, count);
        @memset(buf, ' ');
        return buf;
    }

    pub fn currentLevel(self: IndentContext) u32 {
        return self.level;
    }
};

/// WAT text builder with indentation support
pub const Builder = struct {
    buffer: std.ArrayList(u8),
    indent: IndentContext,
    allocator: Allocator,

    pub fn init(allocator: Allocator) Builder {
        return .{
            .buffer = std.ArrayList(u8).init(allocator),
            .indent = IndentContext.init(),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Builder) void {
        self.buffer.deinit();
    }

    pub fn pushIndent(self: *Builder) void {
        self.indent.push();
    }

    pub fn popIndent(self: *Builder) void {
        self.indent.pop();
    }

    pub fn appendLine(self: *Builder, text: []const u8) !void {
        const ind = try self.indent.spaces(self.allocator);
        defer self.allocator.free(ind);
        try self.buffer.appendSlice(ind);
        try self.buffer.appendSlice(text);
        try self.buffer.append('\n');
    }

    pub fn append(self: *Builder, text: []const u8) !void {
        try self.buffer.appendSlice(text);
    }

    pub fn appendFmt(self: *Builder, comptime fmt: []const u8, args: anytype) !void {
        try self.buffer.writer().print(fmt, args);
    }

    pub fn newline(self: *Builder) !void {
        try self.buffer.append('\n');
    }

    pub fn toString(self: *Builder) ![]const u8 {
        return try self.allocator.dupe(u8, self.buffer.items);
    }

    pub fn clear(self: *Builder) void {
        self.buffer.clearRetainingCapacity();
    }
};

// ============================================================================
// Identifier Management
// ============================================================================

/// Generate a WAT identifier with proper escaping
pub fn escapeIdentifier(allocator: Allocator, name: []const u8) ![]const u8 {
    // WAT identifiers starting with $ can contain alphanumeric + _ - . :
    var needs_escape = false;
    for (name) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '-' and c != '.' and c != ':') {
            needs_escape = true;
            break;
        }
    }

    if (!needs_escape) {
        return std.fmt.allocPrint(allocator, "${s}", .{name});
    }

    // Escape special characters
    var buf = std.ArrayList(u8).init(allocator);
    try buf.append('$');
    for (name) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '_') {
            try buf.append(c);
        } else {
            try buf.append('_');
        }
    }
    return buf.toOwnedSlice();
}

/// Generate unique local variable name
pub fn makeLocalName(allocator: Allocator, base: []const u8, index: u32) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}_{d}", .{ base, index });
}

/// Generate unique label name
pub fn makeLabelName(allocator: Allocator, kind: []const u8, index: u32) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}_label_{d}", .{ kind, index });
}

// ============================================================================
// Basic Instructions
// ============================================================================

/// Emit (local.get $name)
pub fn localGet(allocator: Allocator, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(local.get ${s})", .{name});
}

/// Emit (local.set $name value)
pub fn localSet(allocator: Allocator, name: []const u8, value: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(local.set ${s} {s})", .{ name, value });
}

/// Emit (local.tee $name value)
pub fn localTee(allocator: Allocator, name: []const u8, value: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(local.tee ${s} {s})", .{ name, value });
}

/// Emit (global.get $name)
pub fn globalGet(allocator: Allocator, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(global.get ${s})", .{name});
}

/// Emit (global.set $name value)
pub fn globalSet(allocator: Allocator, name: []const u8, value: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(global.set ${s} {s})", .{ name, value });
}

/// Emit (call $func args...)
pub fn call(allocator: Allocator, func_name: []const u8, args: []const []const u8) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    try buf.appendSlice("(call $");
    try buf.appendSlice(func_name);

    for (args) |arg| {
        try buf.append(' ');
        try buf.appendSlice(arg);
    }

    try buf.append(')');
    return buf.toOwnedSlice();
}

/// Emit (call_indirect (type $sig) index args...)
pub fn callIndirect(allocator: Allocator, type_name: []const u8, index_expr: []const u8, args: []const []const u8) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    try buf.writer().print("(call_indirect (type ${s})", .{type_name});

    for (args) |arg| {
        try buf.append(' ');
        try buf.appendSlice(arg);
    }

    try buf.append(' ');
    try buf.appendSlice(index_expr);
    try buf.append(')');
    return buf.toOwnedSlice();
}

// ============================================================================
// Control Flow
// ============================================================================

/// Emit (if (result type) test (then ...) (else ...))
pub fn ifThenElse(allocator: Allocator, test_expr: []const u8, then_expr: []const u8, else_expr: ?[]const u8, result_type: []const u8) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    try buf.writer().print("(if (result {s}) {s}\n  (then {s})\n  (else {s}))", .{
        result_type,
        test_expr,
        then_expr,
        else_expr orelse "(ref.null $Value)",
    });
    return buf.toOwnedSlice();
}

/// Emit (block $label (result type) body...)
pub fn block(allocator: Allocator, label: ?[]const u8, result_type: ?[]const u8, body: []const u8) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    try buf.appendSlice("(block");

    if (label) |l| {
        try buf.append(' ');
        try buf.append('$');
        try buf.appendSlice(l);
    }

    if (result_type) |rt| {
        try buf.writer().print(" (result {s})", .{rt});
    }

    try buf.append('\n');
    try buf.appendSlice(body);
    try buf.append(')');
    return buf.toOwnedSlice();
}

/// Emit (loop $label (result type) body...)
pub fn loop(allocator: Allocator, label: ?[]const u8, result_type: ?[]const u8, body: []const u8) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    try buf.appendSlice("(loop");

    if (label) |l| {
        try buf.append(' ');
        try buf.append('$');
        try buf.appendSlice(l);
    }

    if (result_type) |rt| {
        try buf.writer().print(" (result {s})", .{rt});
    }

    try buf.append('\n');
    try buf.appendSlice(body);
    try buf.append(')');
    return buf.toOwnedSlice();
}

/// Emit (br $label)
pub fn br(allocator: Allocator, label: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(br ${s})", .{label});
}

/// Emit (br_if $label condition)
pub fn brIf(allocator: Allocator, label: []const u8, condition: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(br_if ${s} {s})", .{ label, condition });
}

/// Emit (br_table $l1 $l2 ... $default index)
pub fn brTable(allocator: Allocator, labels: []const []const u8, default_label: []const u8, index: []const u8) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    try buf.appendSlice("(br_table");

    for (labels) |label| {
        try buf.append(' ');
        try buf.append('$');
        try buf.appendSlice(label);
    }

    try buf.append(' ');
    try buf.append('$');
    try buf.appendSlice(default_label);
    try buf.append(' ');
    try buf.appendSlice(index);
    try buf.append(')');
    return buf.toOwnedSlice();
}

/// Emit (return value)
pub fn returnValue(allocator: Allocator, value: ?[]const u8) ![]const u8 {
    if (value) |v| {
        return std.fmt.allocPrint(allocator, "(return {s})", .{v});
    }
    return try allocator.dupe(u8, "(return)");
}

// ============================================================================
// Exception Handling (WasmGC extension)
// ============================================================================

/// Emit (try $label (result type) (do body) (catch $tag handler))
pub fn tryBlock(allocator: Allocator, label: ?[]const u8, result_type: []const u8, body: []const u8, catches: []const CatchClause) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    try buf.appendSlice("(try");

    if (label) |l| {
        try buf.append(' ');
        try buf.append('$');
        try buf.appendSlice(l);
    }

    try buf.writer().print(" (result {s})\n", .{result_type});
    try buf.appendSlice("  (do\n");
    try buf.appendSlice(body);
    try buf.appendSlice("  )\n");

    for (catches) |catch_clause| {
        try buf.writer().print("  (catch ${s}\n", .{catch_clause.tag_name});
        try buf.appendSlice(catch_clause.handler);
        try buf.appendSlice("  )\n");
    }

    try buf.append(')');
    return buf.toOwnedSlice();
}

pub const CatchClause = struct {
    tag_name: []const u8,
    handler: []const u8,
};

/// Emit (throw $tag value)
pub fn throwException(allocator: Allocator, tag_name: []const u8, value: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(throw ${s} {s})", .{ tag_name, value });
}

// ============================================================================
// Struct and Array Operations
// ============================================================================

/// Emit (struct.new $Type field1 field2 ...)
pub fn structNew(allocator: Allocator, type_name: []const u8, fields: []const []const u8) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    try buf.writer().print("(struct.new ${s}", .{type_name});

    for (fields) |field| {
        try buf.append(' ');
        try buf.appendSlice(field);
    }

    try buf.append(')');
    return buf.toOwnedSlice();
}

/// Emit (struct.get $Type field_index struct_ref)
pub fn structGet(allocator: Allocator, type_name: []const u8, field_index: u32, struct_ref: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(struct.get ${s} {d} {s})", .{ type_name, field_index, struct_ref });
}

/// Emit (struct.set $Type field_index struct_ref value)
pub fn structSet(allocator: Allocator, type_name: []const u8, field_index: u32, struct_ref: []const u8, value: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(struct.set ${s} {d} {s} {s})", .{ type_name, field_index, struct_ref, value });
}

/// Emit (array.new $Type initial_value length)
pub fn arrayNew(allocator: Allocator, type_name: []const u8, initial_value: []const u8, length: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(array.new ${s} {s} {s})", .{ type_name, initial_value, length });
}

/// Emit (array.new_fixed $Type elem1 elem2 ...)
pub fn arrayNewFixed(allocator: Allocator, type_name: []const u8, elements: []const []const u8) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    try buf.writer().print("(array.new_fixed ${s} {d}", .{ type_name, elements.len });

    for (elements) |elem| {
        try buf.append(' ');
        try buf.appendSlice(elem);
    }

    try buf.append(')');
    return buf.toOwnedSlice();
}

/// Emit (array.get $Type array_ref index)
pub fn arrayGet(allocator: Allocator, type_name: []const u8, array_ref: []const u8, index: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(array.get ${s} {s} {s})", .{ type_name, array_ref, index });
}

/// Emit (array.set $Type array_ref index value)
pub fn arraySet(allocator: Allocator, type_name: []const u8, array_ref: []const u8, index: []const u8, value: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(array.set ${s} {s} {s} {s})", .{ type_name, array_ref, index, value });
}

/// Emit (array.len array_ref)
pub fn arrayLen(allocator: Allocator, array_ref: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(array.len {s})", .{array_ref});
}

// ============================================================================
// Type Casting and Testing
// ============================================================================

/// Emit (ref.cast (ref $Type) value)
pub fn refCast(allocator: Allocator, type_name: []const u8, value: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(ref.cast (ref ${s}) {s})", .{ type_name, value });
}

/// Emit (ref.test (ref $Type) value)
pub fn refTest(allocator: Allocator, type_name: []const u8, value: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(ref.test (ref ${s}) {s})", .{ type_name, value });
}

/// Emit (ref.null $Type)
pub fn refNull(allocator: Allocator, type_name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(ref.null ${s})", .{type_name});
}

/// Emit (ref.is_null value)
pub fn refIsNull(allocator: Allocator, value: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(ref.is_null {s})", .{value});
}

// ============================================================================
// Arithmetic and Comparison
// ============================================================================

/// Emit (i32.add a b)
pub fn i32Add(allocator: Allocator, a: []const u8, b: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(i32.add {s} {s})", .{ a, b });
}

/// Emit (i64.add a b)
pub fn i64Add(allocator: Allocator, a: []const u8, b: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(i64.add {s} {s})", .{ a, b });
}

/// Emit (f64.add a b)
pub fn f64Add(allocator: Allocator, a: []const u8, b: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(f64.add {s} {s})", .{ a, b });
}

/// Emit (i32.eq a b)
pub fn i32Eq(allocator: Allocator, a: []const u8, b: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(i32.eq {s} {s})", .{ a, b });
}

/// Emit (i32.lt_s a b)
pub fn i32LtS(allocator: Allocator, a: []const u8, b: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(i32.lt_s {s} {s})", .{ a, b });
}

// ============================================================================
// Constants
// ============================================================================

/// Emit (i32.const value)
pub fn i32Const(allocator: Allocator, value: i32) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(i32.const {d})", .{value});
}

/// Emit (i64.const value)
pub fn i64Const(allocator: Allocator, value: i64) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(i64.const {d})", .{value});
}

/// Emit (f64.const value)
pub fn f64Const(allocator: Allocator, value: f64) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(f64.const {d})", .{value});
}

// ============================================================================
// Module Structure
// ============================================================================

/// Emit (import "module" "name" (func $name (param ...) (result ...)))
pub fn importFunc(allocator: Allocator, module_name: []const u8, func_name: []const u8, local_name: []const u8, params: []const []const u8, result: ?[]const u8) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    try buf.writer().print("(import \"{s}\" \"{s}\" (func ${s}", .{ module_name, func_name, local_name });

    if (params.len > 0) {
        for (params) |param_type| {
            try buf.writer().print(" (param {s})", .{param_type});
        }
    }

    if (result) |res| {
        try buf.writer().print(" (result {s})", .{res});
    }

    try buf.appendSlice("))");
    return buf.toOwnedSlice();
}

/// Emit (export "name" (func $name))
pub fn exportFunc(allocator: Allocator, export_name: []const u8, func_name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(export \"{s}\" (func ${s}))", .{ export_name, func_name });
}

/// Emit (export "name" (global $name))
pub fn exportGlobal(allocator: Allocator, export_name: []const u8, global_name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(export \"{s}\" (global ${s}))", .{ export_name, global_name });
}

/// Emit (global $name (mut? type) init)
pub fn declareGlobal(allocator: Allocator, name: []const u8, mutable: bool, type_name: []const u8, init_value: []const u8) ![]const u8 {
    const mut_str = if (mutable) "(mut " else "";
    const close_str = if (mutable) ")" else "";
    return std.fmt.allocPrint(allocator, "(global ${s} {s}{s}{s} {s})", .{ name, mut_str, type_name, close_str, init_value });
}

/// Emit function signature: (func $name (param ...) (result ...) (local ...) body)
pub fn declareFunc(allocator: Allocator, name: []const u8, params: []const Param, result: ?[]const u8, locals: []const Local, body: []const u8) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    try buf.writer().print("(func ${s}\n", .{name});

    // Parameters
    for (params) |param| {
        try buf.writer().print("  (param ${s} {s})\n", .{ param.name, param.type_name });
    }

    // Result
    if (result) |res| {
        try buf.writer().print("  (result {s})\n", .{res});
    }

    // Locals
    for (locals) |local| {
        try buf.writer().print("  (local ${s} {s})\n", .{ local.name, local.type_name });
    }

    // Body
    try buf.appendSlice(body);
    try buf.append(')');
    return buf.toOwnedSlice();
}

pub const Param = struct {
    name: []const u8,
    type_name: []const u8,
};

pub const Local = struct {
    name: []const u8,
    type_name: []const u8,
};

// ============================================================================
// Type Declarations
// ============================================================================

/// Emit (type $Name (struct (field ...)))
pub fn declareStruct(allocator: Allocator, name: []const u8, fields: []const Field) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    try buf.writer().print("(type ${s} (struct\n", .{name});

    for (fields) |field| {
        const mut_str = if (field.mutable) "(mut " else "";
        const close_str = if (field.mutable) ")" else "";

        if (field.name) |field_name| {
            try buf.writer().print("  (field ${s} {s}{s}{s})\n", .{ field_name, mut_str, field.type_name, close_str });
        } else {
            try buf.writer().print("  (field {s}{s}{s})\n", .{ mut_str, field.type_name, close_str });
        }
    }

    try buf.appendSlice("))");
    return buf.toOwnedSlice();
}

pub const Field = struct {
    name: ?[]const u8,
    type_name: []const u8,
    mutable: bool,
};

/// Emit (type $Name (array (mut? elemtype)))
pub fn declareArray(allocator: Allocator, name: []const u8, elem_type: []const u8, mutable: bool) ![]const u8 {
    const mut_str = if (mutable) "(mut " else "";
    const close_str = if (mutable) ")" else "";
    return std.fmt.allocPrint(allocator, "(type ${s} (array {s}{s}{s}))", .{ name, mut_str, elem_type, close_str });
}

/// Emit (type $Name (func (param ...) (result ...)))
pub fn declareFuncType(allocator: Allocator, name: []const u8, params: []const []const u8, result: ?[]const u8) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    try buf.writer().print("(type ${s} (func", .{name});

    if (params.len > 0) {
        for (params) |param_type| {
            try buf.writer().print(" (param {s})", .{param_type});
        }
    }

    if (result) |res| {
        try buf.writer().print(" (result {s})", .{res});
    }

    try buf.appendSlice("))");
    return buf.toOwnedSlice();
}

// ============================================================================
// Metadata Support (Custom Sections)
// ============================================================================

/// Metadata attached to values and functions
pub const Metadata = struct {
    doc: ?[]const u8 = null,
    source_file: ?[]const u8 = null,
    line: ?u32 = null,
    column: ?u32 = null,
    tags: std.StringHashMap([]const u8),

    pub fn init(allocator: Allocator) Metadata {
        return .{
            .tags = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Metadata) void {
        self.tags.deinit();
    }

    pub fn setDoc(self: *Metadata, doc: []const u8) void {
        self.doc = doc;
    }

    pub fn setSourceLocation(self: *Metadata, file: []const u8, line: u32, column: u32) void {
        self.source_file = file;
        self.line = line;
        self.column = column;
    }

    pub fn addTag(self: *Metadata, key: []const u8, value: []const u8) !void {
        try self.tags.put(key, value);
    }

    /// Emit as custom section: (@metadata (doc "...") (source file:line:col) (tags ...))
    pub fn emit(self: Metadata, allocator: Allocator, target_name: []const u8) ![]const u8 {
        var buf = std.ArrayList(u8).init(allocator);
        try buf.writer().print("(@metadata ${s}", .{target_name});

        if (self.doc) |doc| {
            try buf.writer().print("\n  (doc \"{s}\")", .{doc});
        }

        if (self.source_file) |file| {
            if (self.line) |line| {
                if (self.column) |col| {
                    try buf.writer().print("\n  (source \"{s}:{d}:{d}\")", .{ file, line, col });
                }
            }
        }

        if (self.tags.count() > 0) {
            var it = self.tags.iterator();
            while (it.next()) |entry| {
                try buf.writer().print("\n  (tag {s} \"{s}\")", .{ entry.key_ptr.*, entry.value_ptr.* });
            }
        }

        try buf.append(')');
        return buf.toOwnedSlice();
    }
};

// ============================================================================
// Source Maps (for debugging)
// ============================================================================

/// Source location mapping for debugging
pub const SourceLocation = struct {
    clojure_file: []const u8,
    clojure_line: u32,
    clojure_column: u32,
    wat_line: u32,

    pub fn emit(self: SourceLocation, allocator: Allocator) ![]const u8 {
        return std.fmt.allocPrint(
            allocator,
            ";; {s}:{d}:{d}",
            .{ self.clojure_file, self.clojure_line, self.clojure_column }
        );
    }
};

pub const SourceMap = struct {
    mappings: std.ArrayList(SourceLocation),
    allocator: Allocator,

    pub fn init(allocator: Allocator) SourceMap {
        return .{
            .mappings = std.ArrayList(SourceLocation).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SourceMap) void {
        self.mappings.deinit();
    }

    pub fn addMapping(self: *SourceMap, location: SourceLocation) !void {
        try self.mappings.append(location);
    }

    /// Emit as custom section for WASM binary
    pub fn emitCustomSection(self: SourceMap, allocator: Allocator) ![]const u8 {
        var buf = std.ArrayList(u8).init(allocator);
        try buf.appendSlice("(; Source Map\n");

        for (self.mappings.items) |mapping| {
            const line = try mapping.emit(allocator);
            defer allocator.free(line);
            try buf.appendSlice(line);
            try buf.append('\n');
        }

        try buf.appendSlice(";)");
        return buf.toOwnedSlice();
    }
};

// ============================================================================
// Comments and Documentation
// ============================================================================

/// Emit ;; single-line comment
pub fn comment(allocator: Allocator, text: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, ";; {s}", .{text});
}

/// Emit (; multi-line comment ;)
pub fn blockComment(allocator: Allocator, lines: []const []const u8) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    try buf.appendSlice("(;");

    for (lines) |line| {
        try buf.append('\n');
        try buf.appendSlice(line);
    }

    try buf.appendSlice("\n;)");
    return buf.toOwnedSlice();
}

// ============================================================================
// Module Helpers
// ============================================================================

/// Complete module wrapper
pub fn wrapModule(allocator: Allocator, contents: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(module\n{s}\n)", .{contents});
}

/// Emit module header with version comment
pub fn moduleHeader(allocator: Allocator, name: []const u8, version: []const u8) ![]const u8 {
    return std.fmt.allocPrint(
        allocator,
        ";; Generated by ClojureWasm WasmGC Backend\n;; Module: {s}\n;; Version: {s}\n\n(module\n",
        .{ name, version }
    );
}

/// Emit module footer
pub fn moduleFooter() []const u8 {
    return ")\n";
}
