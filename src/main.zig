const std = @import("std");
const platform = @import("platform.zig");
const gl = @import("gl.zig");
const vec3 = @import("linalg.zig").vec(f32, 3);
const vec4 = @import("linalg.zig").vec(f32, 4);

const Timer = @import("Timer.zig");
const Camera = @import("Camera.zig");
const Renderer = @import("Renderer.zig");
const life = @import("life.zig");

pub var window: platform.Window = undefined;

pub var timer: Timer = .{};
pub var cam: Camera = .{ // position, direction and aspect will be set later
    .position = .{ 0, 0, 0 },
    .direction = .{ 0, 0, 0 },
    .fov = std.math.pi / 4.0,
    .aspect = 1,
    .near = 1,
    .far = 1000,
};
pub var renderer: Renderer = undefined;

var should_run = true;

fn init() !void {
    renderer = try Renderer.init(window);
    timer.update();

    std.debug.print("Inited successfully.\n", .{});

    try life.start();
}

fn deinit() void {
    life.stop();
    renderer.deinit();
}

fn onEvent(event: platform.Event, _: platform.Window) !void {
    switch (event) {
        .window_close => should_run = false,
        .window_resize => |size| {
            renderer.updateSize(size);
            cam.aspect = @intToFloat(f32, size[0]) / @intToFloat(f32, size[1]);
        },
        else => {},
    }
}

fn onUpdate() !void {
    timer.update();

    if (timer.oncePerMilis(1000)) {
        life.update(&renderer);
        std.debug.print("FPS: {}; Instances: {}\n", .{ timer.frames_per_second, renderer.instance_count });
    }

    const position_coef = @intToFloat(f32, timer.time % 100000) / 100000 * std.math.pi * 2;
    const x = @cos(position_coef) * 150;
    const z = @sin(position_coef) * 150;
    const cam_pos = [3]f32{ x, 25, z };
    const light_dir = [3]f32{ x, 100, z };

    cam.position = cam_pos;
    cam.direction = cam_pos;

    const uniform = Renderer.Uniform{
        .cam_mat = cam.mat(),
        .cam_pos = vec4.fromLower(cam.position),
        .light_dir = vec4.fromLower(light_dir),
    };
    renderer.updateUniform(uniform);

    renderer.draw();
}

pub fn main() !void {
    try platform.init();
    defer platform.deinit();

    window = try platform.createWindow(.{ 0, 0 }, .{ 1920, 1080 }, "Prototyp Cubes");
    defer window.destroy();
    window.show();

    try init();
    defer deinit();

    while (should_run) {
        try platform.pollEvents(onEvent);
        try onUpdate();
    }
}
