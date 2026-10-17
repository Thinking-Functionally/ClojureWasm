const std = @import("std");
const edn = @import("edn_parser.zig");

const ir_content = @embedFile("test_ir_data.txt");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("IR content length: {d}\n", .{ir_content.len});
    std.debug.print("First 50 chars: {s}\n", .{ir_content[0..@min(50, ir_content.len)]});

    var ir = try edn.parse(allocator, ir_content);
    defer ir.deinit(allocator);

    std.debug.print("Parsed successfully!\n", .{});
}
