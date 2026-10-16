const std = @import("std");
const edn = @import("edn_parser.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const content = "{:name \"test\"}";
    var ir = try edn.parse(allocator, content);
    defer ir.deinit(allocator);
    std.debug.print("Parsed!\n", .{});
}
