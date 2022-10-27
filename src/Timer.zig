const std = @import("std");

const Timer = @This();

prev_time: u64 = 0,
time: u64 = 0,
frames_per_second: u32 = 0,
frame_counter: u32 = 0,

pub fn update(timer: *Timer) void {
    timer.prev_time = timer.time;
    timer.time = @intCast(u64, std.time.milliTimestamp());

    timer.frame_counter += 1;
    if (timer.oncePerMilis(1000)) {
        timer.frames_per_second = timer.frame_counter;
        timer.frame_counter = 0;
    }
}

pub inline fn deltaMilis(timer: Timer) u64 {
    return timer.time - timer.prev_time;
}

pub inline fn deltaSeconds(timer: Timer) f32 {
    return @intToFloat(f32, timer.deltaMilis()) / 1000;
}

pub inline fn oncePerMilis(timer: Timer, milis: u64) bool {
    return (timer.time / milis) != (timer.prev_time / milis);
}
