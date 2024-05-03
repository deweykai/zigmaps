const map_layer = @import("map_layer.zig");
const grid_layer = @import("grid_layer.zig");
const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const MapLayer = map_layer.MapLayer;
const MapPosition = map_layer.MapPosition;
const GridPosition = grid_layer.GridPosition;
const Length = map_layer.Length;

pub fn mean_in_radius(layer: *const MapLayer, alloc: Allocator, radius: f32) !MapLayer {
    const KernelOp = struct {
        radius: f32,
        pub fn process(op: *@This(), map: *const MapLayer, pos: MapPosition) f32 {
            const SumKernel = struct {
                count: u32 = 0,
                sum: f32 = 0.0,

                pub fn process(self: *@This(), k_map: *const MapLayer, k_pos: MapPosition) void {
                    if (k_map.get_value(k_pos)) |cell| {
                        if (!std.math.isNan(cell.*)) {
                            self.*.count += 1;
                            self.*.sum += cell.*;
                        }
                    }
                }
            };

            var k = SumKernel{};
            map.radius_iterator(pos, op.radius, SumKernel, &k);
            const mean: f32 = k.sum / @as(f32, @floatFromInt(k.count));
            return mean;
        }
    };

    var k = KernelOp{ .radius = radius };
    const avg_layer = try layer.layer_kernel_op(alloc, KernelOp, &k);
    return avg_layer;
}

pub fn raster_slope(layer: *const MapLayer, alloc: Allocator) !MapLayer {
    const KernelOp = struct {
        pub fn process(_: *@This(), map: *const MapLayer, pos: MapPosition) f32 {
            // based on algorithm: https://www.flipcode.com/archives/Calculating_Vertex_Normals_for_Height_Maps.shtml
            const grid_pos = map.map_to_grid_space(pos);
            const x = grid_pos.x;
            const y = grid_pos.y;

            const grid = map.grid;

            var sx: f32 = (grid.get_value(GridPosition{ .x = if (x < grid.width - 1) x + 1 else x, .y = y }).?.* -
                grid.get_value(GridPosition{ .x = if (x > 0) x - 1 else x, .y = y }).?.*);
            if (x == 0 or x == grid.width - 1) {
                sx *= 2;
            }
            var sy: f32 = (grid.get_value(GridPosition{ .x = x, .y = if (y < grid.height - 1) y + 1 else y }).?.* -
                grid.get_value(GridPosition{ .x = x, .y = if (y > 0) y - 1 else y }).?.*);
            if (y == 0 or y == grid.height - 1) {
                sy *= 2;
            }

            const n_x = -sx;
            const n_y = sy;
            var n_z = 2 * map.resolution;

            const mag = std.math.sqrt(n_x * n_x + n_y * n_y + n_z * n_z);

            n_z /= mag;

            return std.math.acos(n_z);
        }
    };

    var k = KernelOp{};
    const slope_layer = try layer.layer_kernel_op(alloc, KernelOp, &k);
    return slope_layer;
}

pub fn min_in_radius(layer: *const MapLayer, alloc: Allocator, radius: f32) !MapLayer {
    const KernelOp = struct {
        radius: f32,
        pub fn process(op: *@This(), map: *const MapLayer, pos: MapPosition) f32 {
            const MinKernel = struct {
                min: f32 = std.math.nan(f32),

                pub fn process(self: *@This(), k_map: *const MapLayer, k_pos: MapPosition) void {
                    if (k_map.get_value(k_pos)) |cell| {
                        if (!std.math.isNan(cell.*)) {
                            if (std.math.isNan(self.min)) {
                                self.min = cell.*;
                            } else if (cell.* < self.min) {
                                self.min = cell.*;
                            }
                        }
                    }
                }
            };

            var k = MinKernel{};
            map.radius_iterator(pos, op.radius, MinKernel, &k);
            return k.min;
        }
    };

    var k = KernelOp{ .radius = radius };
    const min_layer = try layer.layer_kernel_op(alloc, KernelOp, &k);
    return min_layer;
}

pub fn max_in_radius(layer: *const MapLayer, alloc: Allocator, radius: f32) !MapLayer {
    const KernelOp = struct {
        radius: f32,
        pub fn process(op: *@This(), map: *const MapLayer, pos: MapPosition) f32 {
            const MaxKernel = struct {
                max: f32 = std.math.nan(f32),

                pub fn process(self: *@This(), k_map: *const MapLayer, k_pos: MapPosition) void {
                    if (k_map.get_value(k_pos)) |cell| {
                        if (!std.math.isNan(cell.*)) {
                            if (std.math.isNan(self.max)) {
                                self.max = cell.*;
                            } else if (cell.* > self.max) {
                                self.max = cell.*;
                            }
                        }
                    }
                }
            };

            var k = MaxKernel{};
            map.radius_iterator(pos, op.radius, MaxKernel, &k);
            return k.max;
        }
    };

    var k = KernelOp{ .radius = radius };
    const max_layer = try layer.layer_kernel_op(alloc, KernelOp, &k);
    return max_layer;
}

pub fn set_value_radius(
    value: f32,
    radius: f32,
    layer: *const MapLayer,
    pos: MapPosition,
) void {
    const Kernel = struct {
        value: f32,
        pub fn process(self: *const @This(), map: *const MapLayer, k_pos: MapPosition) void {
            if (map.get_value(k_pos)) |cell| {
                cell.* = self.value;
            }
        }
    };

    var k = Kernel{ .value = value };
    layer.radius_iterator(pos, radius, Kernel, &k);
}

test "radius_iterator" {
    const layer = try MapLayer.create(testing.allocator, Length{ .width = 3, .height = 3 }, 0.1);
    defer layer.free(testing.allocator);
    set_value_radius(1.0, 1.3, &layer, MapPosition{ .x = 0, .y = 0 });
    // layer.grid.debug_print();
}

test "complex_kernel_iterator" {
    const layer = try MapLayer.create(testing.allocator, Length{ .width = 5, .height = 5 }, 0.4);
    defer layer.free(testing.allocator);

    layer.fill(9.0);
    set_value_radius(1.0, 1.0, &layer, MapPosition{ .x = 0, .y = 0 });
    // layer.grid.debug_print();

    const avg_layer = try mean_in_radius(&layer, testing.allocator, 0.5);
    defer avg_layer.free(testing.allocator);
    // avg_layer.grid.debug_print();
}
