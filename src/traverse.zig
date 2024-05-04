const std = @import("std");
const testing = std.testing;
const map_layer = @import("map_layer.zig");
const kernels = @import("kernels.zig");

const MapLayer = map_layer.MapLayer;
const MapLength = map_layer.Length;
const MapPosition = map_layer.MapPosition;

fn calc_traverse_slope(slope: f32) f32 {
    return (slope - 0.0872665) / 0.3490655; // 10-25 degrees;
}

fn calc_traverse_stepsize(stepsize: f32) f32 {
    return (stepsize - 0.05) / 0.15; // 13 cm
}

fn calc_stepsize(elevation: f32, min: f32) f32 {
    return (elevation - min);
}

fn calc_max(a: f32, b: f32) f32 {
    return @max(a, b);
}

fn clamp(v: f32) f32 {
    return @min(1.0, @max(0.0, v));
}

fn filter_nan(source: f32, elevation: f32) f32 {
    if (std.math.isNan(source)) {
        return source;
    } else {
        return elevation;
    }
}

pub fn traverse_calc(alloc: std.mem.Allocator, elevation: *const MapLayer) !MapLayer {
    // filter 2
    const smooth_elevation = try kernels.mean_in_radius(elevation, alloc, 0.166);
    defer smooth_elevation.free(alloc);

    // filter 5
    const slope = try kernels.raster_slope(&smooth_elevation, alloc);
    defer slope.free(alloc);

    // filter 6
    const slope_min = try kernels.min_in_radius(&slope, alloc, 0.166);
    defer slope_min.free(alloc);

    // filter 7
    const traversability_slope = try slope_min.layer_uop(alloc, calc_traverse_slope);
    defer traversability_slope.free(alloc);

    // filter 8
    const local_min = try kernels.min_in_radius(&smooth_elevation, alloc, 0.166);
    defer local_min.free(alloc);

    // filter 9
    const stepsize = try smooth_elevation.layer_biop(alloc, &local_min, calc_stepsize);
    defer stepsize.free(alloc);

    // filter 10
    const traversability_stepsize = try stepsize.layer_uop(alloc, calc_traverse_stepsize);
    defer traversability_stepsize.free(alloc);

    // filter 11
    const traversability_raw = try traversability_slope.layer_biop(alloc, &traversability_stepsize, calc_max);
    defer traversability_raw.free(alloc);

    // filter 12 & 13
    const clamped_traversability = try traversability_raw.layer_uop(alloc, clamp);
    defer clamped_traversability.free(alloc);

    // filter 14
    const filtered_traversability = try elevation.layer_biop(alloc, &clamped_traversability, filter_nan);
    defer filtered_traversability.free(alloc);

    // filter 15
    const traversability = try kernels.max_in_radius(&filtered_traversability, alloc, 0.20);

    return traversability;
}

test "no crash" {
    var layer = try MapLayer.create(testing.allocator, MapLength{ .width = 1, .height = 1 }, 0.05);
    defer layer.free(testing.allocator);
    layer.recenter(MapPosition{ .x = 0.5, .y = 0 });

    kernels.set_value_radius(0.0, 0.3, &layer, MapPosition{ .x = 0, .y = 0 });
    kernels.set_value_radius(0.2, 0.15, &layer, MapPosition{ .x = 0, .y = 0 });
    // std.debug.print("\n", .{});
    // layer.grid.debug_print();

    const traverse = try traverse_calc(testing.allocator, &layer);
    defer traverse.free(testing.allocator);
    // std.debug.print("\n", .{});
    // traverse.grid.debug_print();
}
