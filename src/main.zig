const std = @import("std");
const zigmaps = @import("lib.zig");

const TEST_SIZE = 1000 * 1000 * 50;

pub fn main() !void {
    const alloc = std.heap.c_allocator;

    const a: []i32 = try alloc.alloc(i32, TEST_SIZE);
    defer alloc.free(a);

    for (a, 0..) |*v, i| {
        v.* = @intCast(i);
    }

    const stdin = std.io.getStdIn().reader();
    const bare_line = try stdin.readUntilDelimiterAlloc(
        alloc,
        '\n',
        256,
    );
    defer alloc.free(bare_line);

    const b = try std.fmt.parseInt(i32, bare_line, 10);

    for (a) |*v| {
        v.* = zigmaps.addme(v.*, b);
    }
    var sum: i32 = 0;
    for (a) |v| {
        sum += v;
    }

    std.debug.print("Sum: {}\n", .{sum});
}
