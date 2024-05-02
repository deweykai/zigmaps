const std = @import("std");
const testing = std.testing;
const expectEqual = testing.expectEqual;

const Allocator = std.mem.Allocator;

pub const grid_layer = @import("grid_layer.zig");
pub const map_layer = @import("map_layer.zig");

pub fn addme(a: i32, b: i32) i32 {
    return a + (a + a) * b;
}
