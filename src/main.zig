const std = @import("std");
const testing = std.testing;
const expectEqual = testing.expectEqual;

const Allocator = std.mem.Allocator;

const MapPosition = struct { x: f32, y: f32 };
const GridPosition = struct { x: i32, y: i32 };
const Length = struct { width: f32, height: f32 };

const SquareIterator = struct {
    x: i32,
    y: i32,
    low_bounds: GridPosition,
    high_bounds: GridPosition,
    layer: *Layer,

    fn next(self: *SquareIterator) ?*f32 {
        if (self.x > self.high_bounds.x) {
            self.x = self.low_bounds.x;

            if (self.y > self.high_bounds.y) {
                return null;
            }

            const pos = GridPosition{ .x = self.x, .y = self.y };
            self.y += 1;
            const idx = self.layer.get_index(GridPosition, pos);
            return &self.layer.data[idx];
        }
        const pos = GridPosition{ .x = self.x, .y = self.y };
        self.x += 1;
        const idx = self.layer.get_index(GridPosition, pos);
        return &self.layer.data[idx];
    }
};

const Layer = struct {
    size: Length,
    grid_width: i32,
    grid_height: i32,
    resolution: f32,
    center: MapPosition,
    data: []f32,

    fn create(alloc: Allocator, size: Length, resolution: f32) !Layer {
        const grid_width = @as(i32, @intFromFloat(size.width / resolution)) + 1;
        const grid_height = @as(i32, @intFromFloat(size.height / resolution)) + 1;
        const data = try alloc.alloc(f32, @intCast(grid_width * grid_height));
        for (data) |*cell| {
            cell.* = std.math.nan(f32);
        }
        return Layer{ .size = size, .grid_width = grid_width, .grid_height = grid_height, .resolution = resolution, .center = MapPosition{ .x = 0.0, .y = 0.0 }, .data = data };
    }

    fn free(grid_map: *Layer, alloc: Allocator) void {
        alloc.free(grid_map.data);
    }

    fn square_iterator(self: *Layer, center: MapPosition, size: Length) SquareIterator {
        var low_bounds = GridPosition{ .x = @intFromFloat(center.x - size.width / 2), .y = @intFromFloat(center.y - size.height / 2) };
        var high_bounds = GridPosition{ .x = @intFromFloat(center.x + size.width / 2), .y = @intFromFloat(center.y + size.height / 2) };

        low_bounds.x = @max(low_bounds.x, @as(i32, @intFromFloat((self.center.x - self.size.width) / self.resolution)));
        low_bounds.y = @max(low_bounds.y, @as(i32, @intFromFloat((self.center.y - self.size.height) / self.resolution)));

        high_bounds.x = @min(high_bounds.x, @as(i32, @intFromFloat((self.center.x + self.size.width) / self.resolution)));
        high_bounds.y = @min(high_bounds.y, @as(i32, @intFromFloat((self.center.y + self.size.height) / self.resolution)));

        return SquareIterator{ .x = low_bounds.x, .y = low_bounds.y, .low_bounds = low_bounds, .high_bounds = high_bounds, .layer = self };
    }

    fn recenter(self: *Layer, center: MapPosition) void {
        const low_bounds = MapPosition{ .x = self.center.x - self.size.width / 2, .y = self.center.y - self.size.height / 2 };
        const high_bounds = MapPosition{ .x = self.center.x + self.size.width / 2, .y = self.center.y + self.size.height / 2 };

        self.center = center;

        var x: f32 = low_bounds.x;

        while (x < (high_bounds.x + self.resolution / 2)) : (x += self.resolution) {
            var y: f32 = low_bounds.y;
            while (y < (high_bounds.y + self.resolution / 2)) : (y += self.resolution) {
                if (self.is_valid(MapPosition{ .x = x, .y = y })) {
                    continue;
                }
                const idx = self.get_index(MapPosition, MapPosition{ .x = x, .y = y });
                self.data[idx] = std.math.nan(f32);
            }
        }
    }

    fn map_to_grid_space(self: *Layer, pos: MapPosition) GridPosition {
        const grid_x = (pos.x + self.resolution / 2) / self.resolution;
        const grid_y = (pos.y + self.resolution / 2) / self.resolution;

        return GridPosition{ .x = @intFromFloat(grid_x), .y = @intFromFloat(grid_y) };
    }

    fn is_valid(self: *Layer, map_pos: MapPosition) bool {
        if ((map_pos.x - self.center.x) > ((self.size.width + self.resolution) / 2.0)) {
            return false;
        }
        if ((map_pos.x - self.center.x) < -((self.size.width + self.resolution) / 2.0)) {
            return false;
        }
        if ((map_pos.y - self.center.y) > ((self.size.height + self.resolution) / 2.0)) {
            return false;
        }
        if ((map_pos.y - self.center.y) < -((self.size.height + self.resolution) / 2.0)) {
            return false;
        }
        return true;
    }

    fn get_index(self: *Layer, comptime T: type, pos: T) u32 {
        const grid_pos = switch (T) {
            MapPosition => self.map_to_grid_space(pos),
            GridPosition => pos,
            else => unreachable,
        };

        const idx_x: i32 = @intCast(@mod(grid_pos.x, self.grid_width));
        const idx_y: i32 = @intCast(@mod(grid_pos.y, self.grid_height));

        const idx = idx_y * self.grid_height + idx_x;
        return @intCast(idx);
    }

    fn get_value(self: *Layer, pos: MapPosition) ?*f32 {
        if (!self.is_valid(pos)) {
            return null;
        }

        const idx = self.get_index(MapPosition, pos);
        return &self.data[idx];
    }
};

test "create grid map" {
    const alloc = testing.allocator;
    var a = try Layer.create(alloc, Length{ .width = 10, .height = 5 }, 0.05);
    defer a.free(alloc);

    try expectEqual(@as(i32, 101), a.grid_height);
    try expectEqual(@as(i32, 201), a.grid_width);
}

test "grid bounds check" {
    const alloc = testing.allocator;
    var a = try Layer.create(alloc, Length{ .width = 10, .height = 5 }, 0.05);
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
    var a = try Layer.create(alloc, Length{ .width = 10, .height = 5 }, 0.05);
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
    var a = try Layer.create(alloc, Length{ .width = 10, .height = 5 }, 0.05);
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
    var a = try Layer.create(alloc, Length{ .width = 10, .height = 5 }, 0.05);
    defer a.free(alloc);

    try testing.expect(std.math.isNan(a.get_value(MapPosition{ .x = 0.0, .y = 0.0 }).?.*));
}

test "write read grid value" {
    const alloc = testing.allocator;
    var a = try Layer.create(alloc, Length{ .width = 10, .height = 5 }, 0.05);
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
    var a = try Layer.create(alloc, Length{ .width = 10, .height = 5 }, 0.05);
    defer a.free(alloc);

    a.get_value(MapPosition{ .x = 0.0, .y = 0.0 }).?.* = 1.0;
    a.recenter(MapPosition{ .x = 1.0, .y = 1.0 });
    try expectEqual(@as(f32, 1.0), a.get_value(MapPosition{ .x = 0.0, .y = 0.0 }).?.*);
}

test "check moving out of bounds clears data" {
    const alloc = testing.allocator;
    var a = try Layer.create(alloc, Length{ .width = 10, .height = 5 }, 0.05);
    defer a.free(alloc);

    a.get_value(MapPosition{ .x = 0.0, .y = 0.0 }).?.* = 1.0;
    a.recenter(MapPosition{ .x = 100.0, .y = 100.0 });
    a.recenter(MapPosition{ .x = 0.0, .y = 0.0 });
    try testing.expect(std.math.isNan(a.get_value(MapPosition{ .x = 0.0, .y = 0.0 }).?.*));
}

test "square_iterator" {
    var a = try Layer.create(testing.allocator, Length{ .width = 10, .height = 5 }, 0.05);
    defer a.free(testing.allocator);

    var iter = a.square_iterator(MapPosition{ .x = 0.0, .y = 0.0 }, Length{ .width = 1.0, .height = 1.0 });
    while (iter.next()) |cell| {
        cell.* = 1.0;
    }
}
