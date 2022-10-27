const std = @import("std");
const Renderer = @import("Renderer.zig");

pub const n = 100;
pub const max_cells = n * n * n;

const survive_low = 4;
const survive_high = 4;
const born_low = 4;
const born_high = 4;
const initial_density = 80;
const steps_per_init = 30;

pub var thread: std.Thread = undefined;
pub var semaphore = std.Thread.Semaphore{};
pub var mutex = std.Thread.Mutex{};

var step_counter: u32 = steps_per_init;
pub var should_run = true;

var field = std.mem.zeroes([n][n][n]bool);
var prev_field = std.mem.zeroes([n][n][n]bool);

var cells = std.mem.zeroes([max_cells][4]i32);
var prev_cells = std.mem.zeroes([max_cells][4]i32);

var cell_count: u32 = 0;
var prev_cell_count: u32 = 0;

pub fn start() !void {
    thread = try std.Thread.spawn(.{}, runThread, .{});
    semaphore.post();
}

pub fn stop() void {
    mutex.lock();
    should_run = false;
    mutex.unlock();
    semaphore.post();
    thread.join();
}

pub fn update(renderer: *Renderer) void {
    mutex.lock();
    renderer.updateCells(cells[0..cell_count]);
    mutex.unlock();
    semaphore.post();
}

fn runThread() void {
    while (true) {
        semaphore.wait();
        mutex.lock();

        if (!should_run) {
            mutex.unlock();
            return;
        }
        if (step_counter == steps_per_init) {
            initRandom(@intCast(u64, std.time.milliTimestamp()));
            step(); // two steps after new init for better looking result
            step_counter = 0;
        }
        step();
        step_counter += 1;

        mutex.unlock();
    }
}

fn step() void {
    prev_field = field;
    prev_cells = cells;
    prev_cell_count = cell_count;

    clear();

    for (prev_cells[0..prev_cell_count]) |prev_cell| {
        const count = countNeighbors(prev_cell);
        if (count >= survive_low and count <= survive_high)
            addCell(prev_cell);
        checkNeighbors(prev_cell);
    }
}

fn clear() void {
    field = std.mem.zeroes([n][n][n]bool);
    cell_count = 0;
}

inline fn getField(cell: [4]i32) *bool {
    return &field[@intCast(usize, cell[0])][@intCast(usize, cell[1])][@intCast(usize, cell[2])];
}

inline fn getPrevField(cell: [4]i32) *bool {
    return &prev_field[@intCast(usize, cell[0])][@intCast(usize, cell[1])][@intCast(usize, cell[2])];
}

fn addCell(cell: [4]i32) void {
    std.debug.assert(cell_count < max_cells);
    if (!getField(cell).*) {
        getField(cell).* = true;
        cells[cell_count] = cell;
        cell_count += 1;
    }
}

fn countNeighbors(cell: [4]i32) u8 {
    var count: u8 = 0;
    inline for ([3]comptime_int{ -1, 0, 1 }) |x| {
        inline for ([3]comptime_int{ -1, 0, 1 }) |y| {
            inline for ([3]comptime_int{ -1, 0, 1 }) |z| {
                if (x == 0 and y == 0 and z == 0)
                    continue;
                const neighbor = [4]i32{ cell[0] + x, cell[1] + y, cell[2] + z, 1 };
                if (isInField(neighbor) and getPrevField(neighbor).*)
                    count += 1;
            }
        }
    }
    return count;
}

fn checkNeighbors(cell: [4]i32) void {
    inline for ([3]comptime_int{ -1, 0, 1 }) |x| {
        inline for ([3]comptime_int{ -1, 0, 1 }) |y| {
            inline for ([3]comptime_int{ -1, 0, 1 }) |z| {
                if (x == 0 and y == 0 and z == 0)
                    continue;
                const neighbor = [4]i32{ cell[0] + x, cell[1] + y, cell[2] + z, 1 };
                if (isInField(neighbor)) {
                    const count = countNeighbors(neighbor);
                    if (count >= born_low and count <= born_high)
                        addCell(neighbor);
                }
            }
        }
    }
}

inline fn isInField(pos: [4]i32) bool {
    inline for ([3]comptime_int{ 0, 1, 2 }) |i|
        if (pos[i] < 0 or pos[i] >= n)
            return false;
    return true;
}

fn initRandom(seed: u64) void {
    clear();

    var prng = std.rand.DefaultPrng.init(seed);
    const random = prng.random();

    var x: i32 = 0;
    while (x < n) : (x += 1) {
        var y: i32 = 0;
        while (y < n) : (y += 1) {
            var z: i32 = 0;
            while (z < n) : (z += 1) {
                if (random.int(u8) % initial_density == 0)
                    addCell(.{ x, y, z, 1 });
            }
        }
    }
}
