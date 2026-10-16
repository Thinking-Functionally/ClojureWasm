const std = @import("std");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const content = try std.fs.cwd().readFileAlloc(allocator, "edn_parser.zig", 1024);
    defer allocator.free(content);
    std.debug.print("Read {d} bytes\n", .{content.len});
}
