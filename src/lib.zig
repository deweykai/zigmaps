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

export fn zigmaps_create(width: f32, height: f32, center_x: f32, center_y: f32, resolution: f32) ?*MapLayer {
    var layer = MapLayer.create(std.heap.c_allocator, Length{ .width = width, .height = height }, resolution) catch {
        return null;
    };
    layer.recenter(map_layer.MapPosition{ .x = center_x, .y = center_y });
    const layer_heap = std.heap.c_allocator.create(MapLayer) catch {
        return null;
    };

    layer_heap.* = layer;

    return layer_heap;
}

export fn zigmaps_free(layer: *MapLayer) void {
    layer.free(std.heap.c_allocator);
    std.heap.c_allocator.destroy(layer);
}

export fn zigmaps_at(layer: *MapLayer, x: f32, y: f32) ?*f32 {
    return layer.get_value(map_layer.MapPosition{ .x = x, .y = y });
}

export fn zigmaps_make_traverse(map: *const MapLayer) ?*const MapLayer {
    const traverse_layer = traverse.traverse_calc(std.heap.c_allocator, map) catch {
        return null;
    };

    const ptr = std.heap.c_allocator.create(MapLayer) catch {
        return null;
    };

    ptr.* = traverse_layer;

    return ptr;
}
