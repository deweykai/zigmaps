const std = @import("std");

const Allocator = std.mem.Allocator;

pub const GridPosition = struct { x: i32, y: i32 };

pub const GridIterator = struct {
    grid: *GridLayer,
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

    pub fn free(self: *GridLayer, alloc: Allocator) void {
        alloc.free(self.data);
    }

    pub fn fill(self: *GridLayer, value: f32) void {
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
    pub fn is_valid(self: *GridLayer, pos: GridPosition) bool {
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

    pub fn get_index(self: *GridLayer, pos: GridPosition) u32 {
        const idx_x: i32 = @intCast(@mod(pos.x, self.width));
        const idx_y: i32 = @intCast(@mod(pos.y, self.height));

        const idx = idx_y * self.width + idx_x;
        return @intCast(idx);
    }

    pub fn get_value(self: *GridLayer, pos: GridPosition) ?*f32 {
        if (!self.is_valid(pos)) {
            return null;
        }

        const idx = self.get_index(pos);
        return &self.data[idx];
    }

    pub fn square_iterator(self: *GridLayer, low_bounds: GridPosition, high_bounds: GridPosition) GridIterator {
        var checked_low_bounds = low_bounds;
        checked_low_bounds.x = @max(checked_low_bounds.x, self.offset_x);
        checked_low_bounds.y = @max(checked_low_bounds.y, self.offset_y);

        var checked_high_bounds = high_bounds;
        checked_high_bounds.x = @min(checked_high_bounds.x, self.offset_x + self.width);
        checked_high_bounds.y = @min(checked_high_bounds.y, self.offset_y + self.height);
        return GridIterator{ .grid = self, .x = low_bounds.x, .y = low_bounds.y, .low_bounds = checked_low_bounds, .high_bounds = checked_high_bounds };
    }
};
