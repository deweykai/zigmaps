const std = @import("std");
const testing = std.testing;

const Allocator = std.mem.Allocator;

pub const GridPosition = struct { x: i32, y: i32 };

pub const GridError = error{
    InvalidLayer,
};

pub const GridLayer = struct {
    width: i32,
    height: i32,
    data: []f32,

    pub fn create(alloc: Allocator, width: i32, height: i32) !GridLayer {
        const data = try alloc.alloc(f32, @intCast(width * height));
        for (data) |*cell| {
            cell.* = std.math.nan(f32);
        }
        return GridLayer{ .width = width, .height = height, .data = data };
    }

    pub fn free(self: *const GridLayer, alloc: Allocator) void {
        alloc.free(self.data);
    }

    pub fn fill(self: *const GridLayer, value: f32) void {
        for (self.data) |*cell| {
            cell.* = value;
        }
    }

    pub fn is_valid(self: *const GridLayer, pos: GridPosition) bool {
        if (pos.x < 0 or pos.x >= self.width) {
            return false;
        }
        if (pos.y < 0 or pos.y >= self.height) {
            return false;
        }
        return true;
    }

    pub fn get_index(self: *const GridLayer, pos: GridPosition) u32 {
        const idx = pos.y * self.width + pos.x;
        return @intCast(idx);
    }

    pub fn get_value(self: *const GridLayer, pos: GridPosition) ?*f32 {
        if (!self.is_valid(pos)) {
            return null;
        }

        const idx = self.get_index(pos);
        return &self.data[idx];
    }

    pub fn layer_biop(self: *const GridLayer, alloc: Allocator, other: *const GridLayer, comptime op: fn (a: f32, b: f32) f32) !GridLayer {
        if ((self.width != other.width) or (self.height != other.height)) {
            return GridError.InvalidLayer;
        }

        const new_layer = try GridLayer.create(alloc, self.width, self.height);

        for (self.data, other.data, new_layer.data) |a, b, *c| {
            c.* = op(a, b);
        }

        return new_layer;
    }

    pub fn layer_uop(self: *const GridLayer, alloc: Allocator, comptime op: fn (a: f32) f32) !GridLayer {
        const new_layer = try GridLayer.create(alloc, self.width, self.height);

        for (self.data, new_layer.data) |a, *c| {
            c.* = op(a);
        }

        return new_layer;
    }

    pub fn debug_print(self: *const GridLayer) void {
        for (0..@intCast(self.height)) |y| {
            for (0..@intCast(self.width)) |x| {
                const idx = self.get_index(GridPosition{ .x = @intCast(x), .y = @intCast(y) });
                std.debug.print("{d:1.1} ", .{self.data[idx]});
            }
            std.debug.print("\n", .{});
        }
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
