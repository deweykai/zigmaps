const std = @import("std");
const testing = std.testing;
const expectEqual = testing.expectEqual;

const Allocator = std.mem.Allocator;

const grid_layer = @import("grid_layer.zig");
const GridLayer = grid_layer.GridLayer;
const GridPosition = grid_layer.GridPosition;
const GridIterator = grid_layer.GridIterator;

const MapPosition = struct { x: f32, y: f32 };
const Length = struct { width: f32, height: f32 };

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
        const offset_x = @as(i32, @intFromFloat(center.x / self.resolution)) - @divFloor(self.grid.width, 2);
        const offset_y = @as(i32, @intFromFloat(center.y / self.resolution)) - @divFloor(self.grid.height, 2);

        self.grid.reposition(offset_x, offset_y);
    }

    pub fn map_to_grid_space(self: *const MapLayer, pos: MapPosition) GridPosition {
        const grid_x = (pos.x + self.resolution / 2) / self.resolution;
        const grid_y = (pos.y + self.resolution / 2) / self.resolution;

        return GridPosition{ .x = @intFromFloat(grid_x), .y = @intFromFloat(grid_y) };
    }

    pub fn grid_to_map_space(self: *const MapLayer, pos: GridPosition) MapPosition {
        const map_x = @as(f32, @floatFromInt(pos.x)) * self.resolution;
        const map_y = @as(f32, @floatFromInt(pos.y)) * self.resolution;
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

    pub fn square_iterator(self: *const MapLayer, low_bounds: MapPosition, high_bounds: MapPosition) GridIterator {
        const low_grid_pos = self.map_to_grid_space(low_bounds);
        const high_grid_pos = self.map_to_grid_space(high_bounds);
        return self.grid.square_iterator(low_grid_pos, high_grid_pos);
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
};

test "create grid map" {
    const alloc = testing.allocator;
    var a = try MapLayer.create(alloc, Length{ .width = 10, .height = 5 }, 0.05);
    defer a.free(alloc);

    try expectEqual(@as(i32, 101), a.grid.height);
    try expectEqual(@as(i32, 201), a.grid.width);
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

            try expectEqual(expect_valid, a.is_valid(MapPosition{ .x = x, .y = y }));
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

            try expectEqual(expect_valid, a.is_valid(MapPosition{ .x = x, .y = y }));
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
        try expectEqual(@as(f32, 1.0), a.get_value(MapPosition{ .x = 0.0, .y = 0.0 }).?.*);
    }
}
test "write move and read grid value" {
    const alloc = testing.allocator;
    var a = try MapLayer.create(alloc, Length{ .width = 10, .height = 5 }, 0.05);
    defer a.free(alloc);

    a.get_value(MapPosition{ .x = 0.0, .y = 0.0 }).?.* = 1.0;
    a.recenter(MapPosition{ .x = 1.0, .y = 1.0 });
    try expectEqual(@as(f32, 1.0), a.get_value(MapPosition{ .x = 0.0, .y = 0.0 }).?.*);
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

test "square_iterator" {
    var a = try MapLayer.create(testing.allocator, Length{ .width = 10, .height = 5 }, 0.05);
    defer a.free(testing.allocator);

    var iter = a.square_iterator(MapPosition{ .x = 0.0, .y = -1.0 }, MapPosition{ .x = 1.0, .y = 2.0 });
    while (iter.next()) |cell| {
        cell.* = 1.0;
    }

    var x: f32 = -10;
    while (x < 10) : (x += 0.1) {
        var y: f32 = -10;
        while (y < 10) : (y += 0.1) {
            const expect_value = (-0.025 <= x) and (x <= 1.025) and (-1.025 <= y) and (y <= 2.025);
            if (a.get_value(MapPosition{ .x = x, .y = y })) |cell| {
                if (expect_value) {
                    testing.expect(cell.* == 1.0) catch |err| {
                        std.debug.print("x: {}, y: {}, expected: 1.0\n", .{ x, y });
                        return err;
                    };
                } else {
                    testing.expect(std.math.isNan(cell.*)) catch |err| {
                        std.debug.print("x: {}, y: {}, expected: nan\n", .{ x, y });
                        return err;
                    };
                }
            }
        }
    }
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
