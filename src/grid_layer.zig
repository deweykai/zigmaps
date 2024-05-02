const std = @import("std");
const testing = std.testing;

const Allocator = std.mem.Allocator;

pub const GridPosition = struct { x: i32, y: i32 };

pub const GridIterator = struct {
    grid: *const GridLayer,
    x: i32,
    y: i32,
    low_bounds: GridPosition,
    high_bounds: GridPosition,

    pub fn next(self: *GridIterator) ?*f32 {
        if (self.y > self.high_bounds.y) {
            return null;
        }

        const idx = self.grid.get_index(GridPosition{ .x = self.x, .y = self.y });
        const value = &self.grid.data[idx];

        if (self.x > self.high_bounds.x) {
            self.x = self.low_bounds.x;
            self.y += 1;
        } else {
            self.x += 1;
        }

        return value;
    }
};

pub const GridError = error{
    InvalidPosition,
    InvalidLayer,
};

pub const GridLayer = struct {
    width: i32,
    height: i32,
    data: []f32,
    offset_x: i32,
    offset_y: i32,

    pub fn create(alloc: Allocator, width: i32, height: i32) !GridLayer {
        const data = try alloc.alloc(f32, @intCast(width * height));
        for (data) |*cell| {
            cell.* = std.math.nan(f32);
        }
        return GridLayer{ .width = width, .height = height, .data = data, .offset_x = -@divFloor(width, 2), .offset_y = -@divFloor(height, 2) };
    }

    pub fn free(self: *const GridLayer, alloc: Allocator) void {
        alloc.free(self.data);
    }

    pub fn fill(self: *const GridLayer, value: f32) void {
        for (self.data) |*cell| {
            cell.* = value;
        }
    }

    pub fn reposition(self: *GridLayer, offset_x: i32, offset_y: i32) void {
        const low_bounds = GridPosition{ .x = self.offset_x, .y = self.offset_y };
        const high_bounds = GridPosition{ .x = self.offset_x + self.width, .y = self.offset_y + self.height };

        self.offset_x = offset_x;
        self.offset_y = offset_y;

        var x: i32 = low_bounds.x;

        while (x <= high_bounds.x) : (x += 1) {
            var y: i32 = low_bounds.y;
            while (y <= high_bounds.y) : (y += 1) {
                if (self.is_valid(GridPosition{ .x = x, .y = y })) {
                    continue;
                }
                const idx = self.get_index(GridPosition{ .x = x, .y = y });
                self.data[idx] = std.math.nan(f32);
            }
        }
    }
    pub fn is_valid(self: *const GridLayer, pos: GridPosition) bool {
        if ((pos.x - self.offset_x) < 0) {
            return false;
        }
        if ((pos.x - self.offset_x) > self.width) {
            return false;
        }
        if ((pos.y - self.offset_y) < 0) {
            return false;
        }
        if ((pos.y - self.offset_y) > self.height) {
            return false;
        }
        return true;
    }

    pub fn get_index(self: *const GridLayer, pos: GridPosition) u32 {
        const idx_x: i32 = @intCast(@mod(pos.x, self.width));
        const idx_y: i32 = @intCast(@mod(pos.y, self.height));

        const idx = idx_y * self.width + idx_x;
        return @intCast(idx);
    }

    pub fn get_value(self: *const GridLayer, pos: GridPosition) ?*f32 {
        if (!self.is_valid(pos)) {
            return null;
        }

        const idx = self.get_index(pos);
        return &self.data[idx];
    }

    pub fn square_iterator(self: *const GridLayer, low_bounds: GridPosition, high_bounds: GridPosition) GridIterator {
        var checked_low_bounds = low_bounds;
        checked_low_bounds.x = @max(checked_low_bounds.x, self.offset_x);
        checked_low_bounds.y = @max(checked_low_bounds.y, self.offset_y);

        var checked_high_bounds = high_bounds;
        checked_high_bounds.x = @min(checked_high_bounds.x, self.offset_x + self.width);
        checked_high_bounds.y = @min(checked_high_bounds.y, self.offset_y + self.height);
        return GridIterator{ .grid = self, .x = low_bounds.x, .y = low_bounds.y, .low_bounds = checked_low_bounds, .high_bounds = checked_high_bounds };
    }

    pub fn layer_biop(self: *const GridLayer, alloc: Allocator, other: *const GridLayer, comptime op: fn (a: f32, b: f32) f32) !GridLayer {
        if ((self.offset_x != other.offset_x) or (self.offset_y != other.offset_y)) {
            return GridError.InvalidPosition;
        }
        if ((self.width != other.width) or (self.height != other.height)) {
            return GridError.InvalidLayer;
        }

        var new_layer = try GridLayer.create(alloc, self.width, self.height);
        new_layer.offset_x = self.offset_x;
        new_layer.offset_y = self.offset_y;

        for (self.data, other.data, new_layer.data) |a, b, *c| {
            c.* = op(a, b);
        }

        return new_layer;
    }

    pub fn layer_uop(self: *const GridLayer, alloc: Allocator, comptime op: fn (a: f32) f32) !GridLayer {
        var new_layer = try GridLayer.create(alloc, self.width, self.height);
        new_layer.offset_x = self.offset_x;
        new_layer.offset_y = self.offset_y;

        for (self.data, new_layer.data) |a, *c| {
            c.* = op(a);
        }

        return new_layer;
    }
};

test "add layers" {
    const add = struct {
        fn add(a: f32, b: f32) f32 {
            return a + b;
        }
    }.add;
    const layer1 = try GridLayer.create(testing.allocator, 100, 100);
    defer layer1.free(testing.allocator);

    layer1.fill(1.0);

    const layer2 = try GridLayer.create(testing.allocator, 100, 100);
    defer layer2.free(testing.allocator);

    layer2.fill(2.0);

    const layer3 = try layer1.layer_biop(testing.allocator, &layer2, add);
    defer layer3.free(testing.allocator);

    for (layer3.data) |cell| {
        try testing.expect(cell == 3.0);
    }
}

test "add layers of different sizes" {
    const add = struct {
        fn add(a: f32, b: f32) f32 {
            return a + b;
        }
    }.add;
    const layer1 = try GridLayer.create(testing.allocator, 90, 100);
    defer layer1.free(testing.allocator);

    layer1.fill(1.0);

    const layer2 = try GridLayer.create(testing.allocator, 100, 100);
    defer layer2.free(testing.allocator);

    layer2.fill(2.0);

    const layer3 = layer1.layer_biop(testing.allocator, &layer2, add) catch {
        return;
    };
    defer layer3.free(testing.allocator);

    try testing.expect(false);
}

test "add layers of different positions" {
    const add = struct {
        fn add(a: f32, b: f32) f32 {
            return a + b;
        }
    }.add;
    const layer1 = try GridLayer.create(testing.allocator, 100, 100);
    defer layer1.free(testing.allocator);

    layer1.fill(1.0);

    var layer2 = try GridLayer.create(testing.allocator, 100, 100);
    defer layer2.free(testing.allocator);

    layer2.reposition(1, 1);
    layer2.fill(2.0);

    const layer3 = layer1.layer_biop(testing.allocator, &layer2, add) catch {
        return;
    };
    defer layer3.free(testing.allocator);

    try testing.expect(false);
}

test "mult layers" {
    const mult = struct {
        fn mult(a: f32, b: f32) f32 {
            return a * b;
        }
    }.mult;
    const layer1 = try GridLayer.create(testing.allocator, 100, 100);
    defer layer1.free(testing.allocator);

    layer1.fill(2.0);

    const layer2 = try GridLayer.create(testing.allocator, 100, 100);
    defer layer2.free(testing.allocator);

    layer2.fill(5.0);

    const layer3 = try layer1.layer_biop(testing.allocator, &layer2, mult);
    defer layer3.free(testing.allocator);

    for (layer3.data) |cell| {
        try testing.expect(cell == 10.0);
    }
}

test "negate layers" {
    const neg = struct {
        fn neg(a: f32) f32 {
            return -a;
        }
    }.neg;
    const layer1 = try GridLayer.create(testing.allocator, 100, 100);
    defer layer1.free(testing.allocator);

    layer1.fill(2.0);

    const layer2 = try layer1.layer_uop(testing.allocator, neg);
    defer layer2.free(testing.allocator);

    for (layer2.data) |cell| {
        try testing.expect(cell == -2.0);
    }
}
