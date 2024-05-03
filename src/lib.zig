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

const allocator = std.heap.c_allocator;
// const allocator = testing.allocator;

export fn zigmaps_create(width: f32, height: f32, center_x: f32, center_y: f32, resolution: f32) ?*const MapLayer {
    var layer = MapLayer.create(allocator, Length{ .width = width, .height = height }, resolution) catch {
        return null;
    };
    layer.recenter(map_layer.MapPosition{ .x = center_x, .y = center_y });
    const layer_heap = allocator.create(MapLayer) catch {
        return null;
    };

    layer_heap.* = layer;

    return layer_heap;
}

export fn zigmaps_free(layer: *const MapLayer) void {
    layer.free(allocator);
    allocator.destroy(layer);
}

export fn zigmaps_at(layer: *const MapLayer, x: f32, y: f32) ?*f32 {
    return layer.get_value(map_layer.MapPosition{ .x = x, .y = y });
}

export fn zigmaps_make_traverse(map: *const MapLayer) ?*const MapLayer {
    const traverse_layer = traverse.traverse_calc(allocator, map) catch {
        return null;
    };

    const ptr = allocator.create(MapLayer) catch {
        return null;
    };

    ptr.* = traverse_layer;

    return ptr;
}

test "create and free map" {
    const map = zigmaps_create(10, 10, 0, 0, 0.05);
    defer zigmaps_free(map.?);
    try testing.expect(map != null);
}

test "set and get value" {
    const map = zigmaps_create(10, 10, 0, 0, 0.05).?;
    defer zigmaps_free(map);
    const value = 1.3;
    zigmaps_at(map, 0, 0).?.* = value;
    try testing.expectEqual(zigmaps_at(map, 0, 0).?.*, value);
}

test "calculate traverse" {
    const map = zigmaps_create(10, 10, 0, 0, 0.05).?;
    defer zigmaps_free(map);
    const value = 1.3;
    zigmaps_at(map, 0, 0).?.* = value;
    try testing.expectEqual(zigmaps_at(map, 0, 0).?.*, value);
    const traverse_map = zigmaps_make_traverse(map).?;
    defer zigmaps_free(traverse_map);
}
