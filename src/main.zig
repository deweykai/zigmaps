const std = @import("std");
const zigmaps = @import("lib.zig");

const MapLayer = zigmaps.map_layer.MapLayer;
const MapLength = zigmaps.map_layer.Length;
const MapPosition = zigmaps.map_layer.MapPosition;

pub fn main() !void {
    const alloc = std.heap.c_allocator;

    const map = try MapLayer.create(alloc, MapLength{ .width = 10, .height = 10 }, 0.05);
    defer map.free(alloc);

    map.fill(0.0);

    const reader = std.io.getStdIn().reader();
    const line = try reader.readUntilDelimiterAlloc(alloc, '\n', 1024);
    const v: f32 = try std.fmt.parseFloat(f32, line);

    zigmaps.kernels.set_value_radius(v, 3, &map, MapPosition{ .x = 0, .y = 0 });
    const avg = try zigmaps.kernels.mean_in_radius(&map, alloc, 0.5);
    defer avg.free(alloc);

    const traverse = try zigmaps.traverse.traverse_calc(alloc, &map);
    defer traverse.free(alloc);
}
