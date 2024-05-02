const std = @import("std");
const testing = std.testing;
const expectEqual = testing.expectEqual;

const Allocator = std.mem.Allocator;

pub const grid_layer = @import("grid_layer.zig");
pub const map_layer = @import("map_layer.zig");
pub const kernels = @import("kernels.zig");
pub const traverse = @import("traverse.zig");

const MapLayer = map_layer.MapLayer;
const Length = map_layer.Length;

export fn zigmaps_create(width: f32, height: f32, resolution: f32) ?*MapLayer {
    var layer = MapLayer.create(std.heap.c_allocator, Length{ .width = width, .height = height }, resolution) catch {
        return null;
    };
    return &layer;
}

export fn zigmaps_free(layer: *MapLayer) void {
    layer.free(std.heap.c_allocator);
}
