const std = @import("std");
const Node = @import("Node");
const Allocator = std.mem.Allocator;

/// Minimal WAT generator for proof-of-concept
/// Does NOT replace the existing 6,069 LOC compiler
/// Goal: Get 5-10 simple expressions working to prove architecture
pub const SimpleWatGenerator = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) SimpleWatGenerator {
        return .{ .allocator = allocator };
    }

    pub fn generate(self: *SimpleWatGenerator, node: *const Node) ![]const u8 {
        var wat = std.ArrayList(u8).init(self.allocator);
        errdefer wat.deinit();

        try wat.appendSlice("(module\n");
        try wat.appendSlice("  (func (export \"main\") (result i64)\n");
        try wat.appendSlice("    ");

        try self.generateExpr(&wat, node);

        try wat.appendSlice("\n  )\n");
        try wat.appendSlice(")\n");

        return try wat.toOwnedSlice();
    }

    fn generateExpr(self: *SimpleWatGenerator, wat: *std.ArrayList(u8), node: *const Node) !void {
        _ = self;

        switch (node.tag) {
            .int_literal => {
                try wat.writer().print("i64.const {d}", .{node.data.int_literal});
            },

            .add => {
                try wat.appendSlice("(i64.add ");
                try self.generateExpr(wat, node.data.binary.left);
                try wat.appendSlice(" ");
                try self.generateExpr(wat, node.data.binary.right);
                try wat.appendSlice(")");
            },

            .sub => {
                try wat.appendSlice("(i64.sub ");
                try self.generateExpr(wat, node.data.binary.left);
                try wat.appendSlice(" ");
                try self.generateExpr(wat, node.data.binary.right);
                try wat.appendSlice(")");
            },

            .mul => {
                try wat.appendSlice("(i64.mul ");
                try self.generateExpr(wat, node.data.binary.left);
                try wat.appendSlice(" ");
                try self.generateExpr(wat, node.data.binary.right);
                try wat.appendSlice(")");
            },

            .div => {
                try wat.appendSlice("(i64.div_s ");
                try self.generateExpr(wat, node.data.binary.left);
                try wat.appendSlice(" ");
                try self.generateExpr(wat, node.data.binary.right);
                try wat.appendSlice(")");
            },

            else => {
                std.debug.print("Unsupported node type: {s}\n", .{@tagName(node.tag)});
                return error.UnsupportedNodeType;
            },
        }
    }
};
