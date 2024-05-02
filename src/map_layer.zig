const std = @import("std");
const testing = std.testing;

const Allocator = std.mem.Allocator;

const grid_layer = @import("grid_layer.zig");
const GridLayer = grid_layer.GridLayer;
const GridPosition = grid_layer.GridPosition;

pub const MapPosition = struct { x: f32, y: f32 };
pub const Length = struct { width: f32, height: f32 };

pub const MapError = error{
    SizeError,
    PositionError,
    ResourceError,
};

pub const MapLayer = struct {
    size: Length,
    resolution: f32,
    center: MapPosition,
    grid: GridLayer,

    pub fn create(alloc: Allocator, size: Length, resolution: f32) !MapLayer {
        const grid_width = @as(i32, @intFromFloat(size.width / resolution)) + 1;
        const grid_height = @as(i32, @intFromFloat(size.height / resolution)) + 1;
        const grid = try GridLayer.create(alloc, grid_width, grid_height);
        return MapLayer{ .size = size, .resolution = resolution, .center = MapPosition{ .x = 0.0, .y = 0.0 }, .grid = grid };
    }

    pub fn free(self: *const MapLayer, alloc: Allocator) void {
        self.grid.free(alloc);
    }

    pub fn fill(self: *const MapLayer, value: f32) void {
        self.grid.fill(value);
    }

    pub fn recenter(self: *MapLayer, center: MapPosition) void {
        self.center = center;
        self.fill(std.math.nan(f32));
    }

    pub fn map_to_grid_space(self: *const MapLayer, pos: MapPosition) GridPosition {
        const f_x = pos.x - (self.center.x - self.size.width / 2);
        const f_y = pos.y - (self.center.y - self.size.height / 2);

        const grid_x = (f_x + self.resolution / 2) / self.resolution;
        const grid_y = (f_y + self.resolution / 2) / self.resolution;

        return GridPosition{ .x = @intFromFloat(grid_x), .y = @intFromFloat(grid_y) };
    }

    pub fn grid_to_map_space(self: *const MapLayer, pos: GridPosition) MapPosition {
        const map_x = @as(f32, @floatFromInt(pos.x)) * self.resolution + (self.center.x - self.size.width / 2);
        const map_y = @as(f32, @floatFromInt(pos.y)) * self.resolution + (self.center.y - self.size.height / 2);
        return MapPosition{ .x = map_x, .y = map_y };
    }

    pub fn is_valid(self: *const MapLayer, map_pos: MapPosition) bool {
        const grid_pos = self.map_to_grid_space(map_pos);
        return self.grid.is_valid(grid_pos);
    }

    pub fn get_index(self: *const MapLayer, pos: MapPosition) u32 {
        const grid_pos = self.map_to_grid_space(pos);

        const idx_x: i32 = @intCast(@mod(grid_pos.x, self.grid_width));
        const idx_y: i32 = @intCast(@mod(grid_pos.y, self.grid_height));

        const idx = idx_y * self.grid_height + idx_x;
        return @intCast(idx);
    }

    pub fn get_value(self: *const MapLayer, pos: MapPosition) ?*f32 {
        const grid_pos = self.map_to_grid_space(pos);
        return self.grid.get_value(grid_pos);
    }

    pub fn layer_biop(self: *const MapLayer, alloc: Allocator, other: *const MapLayer, comptime op: fn (a: f32, b: f32) f32) !MapLayer {
        if (self.size.width != other.size.width or self.size.height != other.size.height) {
            return MapError.SizeError;
        }
        if (self.center.x != other.center.x or self.center.y != other.center.y) {
            return MapError.PositionError;
        }
        if (self.resolution != other.resolution) {
            return MapError.ResourceError;
        }

        const grid = try self.grid.layer_biop(alloc, &other.grid, op);
        return MapLayer{ .size = self.size, .resolution = self.resolution, .center = self.center, .grid = grid };
    }

    pub fn layer_uop(self: *const MapLayer, alloc: Allocator, comptime op: fn (a: f32) f32) !MapLayer {
        const grid = try self.grid.layer_uop(alloc, op);
        return MapLayer{ .size = self.size, .resolution = self.resolution, .center = self.center, .grid = grid };
    }

    pub fn layer_kernel_op(self: *const MapLayer, alloc: Allocator, comptime K: anytype, kernel: *K) !MapLayer {
        const grid = try GridLayer.create(alloc, self.grid.width, self.grid.height);
        const layer = MapLayer{ .size = self.size, .resolution = self.resolution, .center = self.center, .grid = grid };

        var x: i32 = 0;
        while (x < self.grid.width) : (x += 1) {
            var y: i32 = 0;
            while (y < self.grid.height) : (y += 1) {
                const position = self.grid_to_map_space(GridPosition{ .x = x, .y = y });
                const value = kernel.process(self, position);
                if (layer.get_value(position)) |cell| {
                    cell.* = value;
                }
            }
        }

        return layer;
    }

    pub fn radius_iterator(self: *const MapLayer, center: MapPosition, radius: f32, comptime K: anytype, kernel: *K) void {
        const left_map = (center.x - radius);
        const right_map = (center.x + radius + self.resolution);
        const top_map = (center.y - radius);
        const bottom_map = (center.y + radius + self.resolution);
        const top_left_grid = self.map_to_grid_space(MapPosition{ .x = left_map, .y = top_map });
        const bottom_right_grid = self.map_to_grid_space(MapPosition{ .x = right_map, .y = bottom_map });

        const adj_radius = radius + self.resolution / 2;

        var x: i32 = top_left_grid.x;
        while (x < bottom_right_grid.x) : (x += 1) {
            var y: i32 = top_left_grid.y;
            while (y < bottom_right_grid.y) : (y += 1) {
                const map_pos = self.grid_to_map_space(GridPosition{ .x = x, .y = y });
                const dx = map_pos.x - center.x;
                const dy = map_pos.y - center.y;
                const distance2 = dx * dx + dy * dy;
                if (distance2 <= (adj_radius * adj_radius)) {
                    kernel.process(self, map_pos);
                }
            }
        }
    }
};

test "create grid map" {
    const alloc = testing.allocator;
    var a = try MapLayer.create(alloc, Length{ .width = 10, .height = 5 }, 0.05);
    defer a.free(alloc);

    try testing.expectEqual(@as(i32, 101), a.grid.height);
    try testing.expectEqual(@as(i32, 201), a.grid.width);
}

test "grid bounds check" {
    const alloc = testing.allocator;
    var a = try MapLayer.create(alloc, Length{ .width = 10, .height = 5 }, 0.05);
    defer a.free(alloc);

    var x: f32 = -10;
    while (x < 10) : (x += 0.1) {
        var y: f32 = -10;
        while (y < 10) : (y += 0.1) {
            const expect_valid = (-5.025 <= x) and (x <= 5.025) and (-2.525 <= y) and (y <= 2.525);

            try testing.expectEqual(expect_valid, a.is_valid(MapPosition{ .x = x, .y = y }));
        }
    }
}

test "grid non zero center bounds check" {
    const alloc = testing.allocator;
    var a = try MapLayer.create(alloc, Length{ .width = 10, .height = 5 }, 0.05);
    defer a.free(alloc);

    a.recenter(MapPosition{ .x = 5.0, .y = 0.0 });

    var x: f32 = -10;
    while (x < 10) : (x += 0.1) {
        var y: f32 = -10;
        while (y < 10) : (y += 0.1) {
            const expect_valid = (-0.025 <= x) and (x <= 10.025) and (-2.525 <= y) and (y <= 2.525);

            try testing.expectEqual(expect_valid, a.is_valid(MapPosition{ .x = x, .y = y }));
        }
    }
}

test "get grid value" {
    const alloc = testing.allocator;
    var a = try MapLayer.create(alloc, Length{ .width = 10, .height = 5 }, 0.05);
    defer a.free(alloc);

    var x: f32 = -10;
    while (x < 10) : (x += 0.1) {
        var y: f32 = -10;
        while (y < 10) : (y += 0.1) {
            const expect_valid = (-5.025 <= x) and (x <= 5.025) and (-2.525 <= y) and (y <= 2.525);
            const cell = a.get_value(MapPosition{ .x = x, .y = y });

            if (expect_valid) {
                try testing.expect(cell != null);
            } else {
                try testing.expect(cell == null);
            }
        }
    }
}

test "read uninitialized grid value" {
    const alloc = testing.allocator;
    var a = try MapLayer.create(alloc, Length{ .width = 10, .height = 5 }, 0.05);
    defer a.free(alloc);

    try testing.expect(std.math.isNan(a.get_value(MapPosition{ .x = 0.0, .y = 0.0 }).?.*));
}

test "write read grid value" {
    const alloc = testing.allocator;
    var a = try MapLayer.create(alloc, Length{ .width = 10, .height = 5 }, 0.05);
    defer a.free(alloc);

    {
        const cell = a.get_value(MapPosition{ .x = 0.0, .y = 0.0 }).?;
        cell.* = 1.0;
    }
    {
        try testing.expectEqual(@as(f32, 1.0), a.get_value(MapPosition{ .x = 0.0, .y = 0.0 }).?.*);
    }
}
test "write move and read grid value" {
    const alloc = testing.allocator;
    var a = try MapLayer.create(alloc, Length{ .width = 10, .height = 5 }, 0.05);
    defer a.free(alloc);

    a.get_value(MapPosition{ .x = 0.0, .y = 0.0 }).?.* = 1.0;
    a.recenter(MapPosition{ .x = 1.0, .y = 1.0 });
    try testing.expect(std.math.isNan(a.get_value(MapPosition{ .x = 0.0, .y = 0.0 }).?.*));
}

test "check moving out of bounds clears data" {
    const alloc = testing.allocator;
    var a = try MapLayer.create(alloc, Length{ .width = 10, .height = 5 }, 0.05);
    defer a.free(alloc);

    a.get_value(MapPosition{ .x = 0.0, .y = 0.0 }).?.* = 1.0;
    a.recenter(MapPosition{ .x = 100.0, .y = 100.0 });
    a.recenter(MapPosition{ .x = 0.0, .y = 0.0 });
    try testing.expect(std.math.isNan(a.get_value(MapPosition{ .x = 0.0, .y = 0.0 }).?.*));
}

test "add layers" {
    const mult = struct {
        fn mult(a: f32, b: f32) f32 {
            return a * b;
        }
    }.mult;
    const layer1 = try MapLayer.create(testing.allocator, Length{ .width = 10, .height = 10 }, 0.1);
    defer layer1.free(testing.allocator);

    layer1.fill(2.0);

    const layer2 = try MapLayer.create(testing.allocator, Length{ .width = 10, .height = 10 }, 0.1);
    defer layer2.free(testing.allocator);

    layer2.fill(5.0);

    const layer3 = try layer1.layer_biop(testing.allocator, &layer2, mult);
    defer layer3.free(testing.allocator);

    for (layer3.grid.data) |cell| {
        try testing.expect(cell == 10.0);
    }
}
