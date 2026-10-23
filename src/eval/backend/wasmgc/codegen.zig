// SPDX-License-Identifier: EPL-2.0
//! WAT text generation utilities for WasmGC backend
//!
//! Provides helper functions for generating well-formed WebAssembly Text (WAT)
//! format output. Handles indentation, formatting, and common WAT instruction
//! patterns.
//!
//! Key responsibilities:
//! - WAT instruction formatting (struct.new, call, local.get, etc.)
//! - Indentation management for nested blocks
//! - WAT identifier escaping and validation
//! - Common code generation patterns (load/store, arithmetic, control flow)
//!
//! Design notes:
//! - All functions return []const u8 slices that must be freed by caller
//! - Uses allocator passed explicitly (no global state)
//! - WAT output is human-readable with consistent indentation

const std = @import("std");
const types = @import("types");
const Allocator = std.mem.Allocator;

/// WAT text builder with indentation support
pub const WAT = struct {
    buffer: std.array_list.Managed(u8),
    indent_level: u32,
    allocator: Allocator,

    pub fn init(allocator: Allocator) WAT {
        return .{
            .buffer = std.array_list.Managed(u8).init(allocator),
            .indent_level = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *WAT) void {
        self.buffer.deinit();
    }

    pub fn indent(self: *WAT) void {
        self.indent_level += 1;
    }

    pub fn dedent(self: *WAT) void {
        if (self.indent_level > 0) {
            self.indent_level -= 1;
        }
    }

    pub fn appendLine(self: *WAT, text: []const u8) !void {
        const spaces = self.indent_level * 2;
        var i: u32 = 0;
        while (i < spaces) : (i += 1) {
            try self.buffer.append( ' ');
        }
        try self.buffer.appendSlice( text);
        try self.buffer.append( '\n');
    }

    pub fn append(self: *WAT, text: []const u8) !void {
        try self.buffer.appendSlice( text);
    }

    pub fn toString(self: *WAT) ![]const u8 {
        return try self.allocator.dupe(u8, self.buffer.items);
    }
};

/// Indentation level manager for WAT output
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
};

/// Generate a WAT identifier with proper escaping
pub fn escapeWATIdentifier(allocator: Allocator, name: []const u8) ![]const u8 {
    // WAT identifiers starting with $ can contain alphanumeric + _ - . :
    // If name is already valid, return as-is with $ prefix
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

    // Otherwise escape special characters
    var buf = std.array_list.Managed(u8).init(allocator);
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

/// Format a struct.new instruction
pub fn emitStructNew(allocator: Allocator, type_name: []const u8, fields: []const []const u8, indent: IndentContext) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);

    const ind = try indent.spaces(allocator);
    defer allocator.free(ind);

    try buf.appendSlice( ind);
    try buf.appendSlice( "(struct.new ");
    try buf.appendSlice( type_name);

    if (fields.len == 0) {
        try buf.append(')');
    } else {
        try buf.append('\n');
        var field_indent = indent;
        field_indent.push();
        const field_ind = try field_indent.spaces(allocator);
        defer allocator.free(field_ind);

        for (fields) |field| {
            try buf.appendSlice( field_ind);
            try buf.appendSlice( field);
            try buf.append('\n');
        }

        try buf.appendSlice( ind);
        try buf.append(')');
    }

    return buf.toOwnedSlice();
}

/// Format a local.get instruction
pub fn emitLocalGet(allocator: Allocator, var_name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(local.get ${s})", .{var_name});
}

/// Format a local.set instruction
pub fn emitLocalSet(allocator: Allocator, var_name: []const u8, value_expr: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(local.set ${s} {s})", .{ var_name, value_expr });
}

/// Format a global.get instruction
pub fn emitGlobalGet(allocator: Allocator, var_name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(global.get ${s})", .{var_name});
}

/// Format a global.set instruction
pub fn emitGlobalSet(allocator: Allocator, var_name: []const u8, value_expr: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(global.set ${s} {s})", .{ var_name, value_expr });
}

/// Format a call instruction
pub fn emitCall(allocator: Allocator, func_name: []const u8, args: []const []const u8) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);

    try buf.appendSlice( "(call $");
    try buf.appendSlice( func_name);

    for (args) |arg| {
        try buf.append(' ');
        try buf.appendSlice( arg);
    }

    try buf.append(')');
    return buf.toOwnedSlice();
}

/// Format an if expression
pub fn emitIf(allocator: Allocator, test_expr: []const u8, then_expr: []const u8, else_expr: ?[]const u8, result_type: []const u8, indent: IndentContext) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);

    const ind = try indent.spaces(allocator);
    defer allocator.free(ind);

    try buf.appendSlice( ind);
    try buf.appendSlice( "(if (result ");
    try buf.appendSlice( result_type);
    try buf.appendSlice( ")\n");

    var inner_indent = indent;
    inner_indent.push();
    const inner_ind = try inner_indent.spaces(allocator);
    defer allocator.free(inner_ind);

    try buf.appendSlice( inner_ind);
    try buf.appendSlice( test_expr);
    try buf.appendSlice( "\n");

    try buf.appendSlice( inner_ind);
    try buf.appendSlice( "(then\n");

    var body_indent = inner_indent;
    body_indent.push();
    const body_ind = try body_indent.spaces(allocator);
    defer allocator.free(body_ind);

    try buf.appendSlice( body_ind);
    try buf.appendSlice( then_expr);
    try buf.appendSlice( ")\n");

    try buf.appendSlice( inner_ind);
    try buf.appendSlice( "(else\n");

    try buf.appendSlice( body_ind);
    if (else_expr) |else_e| {
        try buf.appendSlice( else_e);
    } else {
        try buf.appendSlice( "(ref.null $Value)");
    }
    try buf.appendSlice( "))\n");

    try buf.appendSlice( ind);
    try buf.append(')');

    return buf.toOwnedSlice();
}

/// Format a block instruction
pub fn emitBlock(allocator: Allocator, label: []const u8, result_type: []const u8, body: []const u8, indent: IndentContext) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);

    const ind = try indent.spaces(allocator);
    defer allocator.free(ind);

    try buf.appendSlice( ind);
    try buf.appendSlice( "(block $");
    try buf.appendSlice( label);
    try buf.appendSlice( " (result ");
    try buf.appendSlice( result_type);
    try buf.appendSlice( ")\n");

    var body_indent = indent;
    body_indent.push();
    const body_ind = try body_indent.spaces(allocator);
    defer allocator.free(body_ind);

    try buf.appendSlice( body_ind);
    try buf.appendSlice( body);
    try buf.append('\n');

    try buf.appendSlice( ind);
    try buf.append(')');

    return buf.toOwnedSlice();
}

/// Format a loop instruction
pub fn emitLoop(allocator: Allocator, label: []const u8, body: []const u8, indent: IndentContext) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);

    const ind = try indent.spaces(allocator);
    defer allocator.free(ind);

    try buf.appendSlice( ind);
    try buf.appendSlice( "(loop $");
    try buf.appendSlice( label);
    try buf.append('\n');

    var body_indent = indent;
    body_indent.push();
    const body_ind = try body_indent.spaces(allocator);
    defer allocator.free(body_ind);

    try buf.appendSlice( body_ind);
    try buf.appendSlice( body);
    try buf.append('\n');

    try buf.appendSlice( ind);
    try buf.append(')');

    return buf.toOwnedSlice();
}

/// Format a br (branch) instruction
pub fn emitBr(allocator: Allocator, label: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(br ${s})", .{label});
}

/// Format a br_if (conditional branch) instruction
pub fn emitBrIf(allocator: Allocator, label: []const u8, condition: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(br_if ${s} {s})", .{ label, condition });
}

/// Format an i32.const instruction
pub fn emitI32Const(allocator: Allocator, value: i32) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(i32.const {d})", .{value});
}

/// Format an i64.const instruction
pub fn emitI64Const(allocator: Allocator, value: i64) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(i64.const {d})", .{value});
}

/// Format an f64.const instruction
pub fn emitF64Const(allocator: Allocator, value: f64) ![]const u8 {
    return std.fmt.allocPrint(allocator, "(f64.const {d})", .{value});
}
