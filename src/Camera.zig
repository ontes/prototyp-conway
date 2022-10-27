const std = @import("std");
const vec3 = @import("linalg.zig").vec(f32, 3);
const mat3 = @import("linalg.zig").mat(f32, 3);
const mat4 = @import("linalg.zig").mat(f32, 4);

const Camera = @This();

position: [3]f32,
direction: [3]f32,
up: [3]f32 = .{ 0, 1, 0 },

fov: f32,
aspect: f32,
near: f32,
far: f32,

pub fn lookMat(cam: Camera) [3][3]f32 {
    const az = vec3.normalize(cam.direction);
    const ax = vec3.normalize(cross(cam.up, az));
    const ay = vec3.normalize(cross(az, ax));
    return mat3.transpose(.{ ax, ay, az });
}

pub fn viewMat(cam: Camera) [4][4]f32 {
    return mat4.multiply(
        mat4.fromLower(cam.lookMat()),
        mat4.translate(vec3.multiplyS(cam.position, -1)),
    );
}

pub fn perspectiveMat(cam: Camera) [4][4]f32 {
    return .{
        .{ 1 / std.math.tan(cam.fov / 2), 0, 0, 0 },
        .{ 0, 1 / std.math.tan(cam.fov / 2) * cam.aspect, 0, 0 },
        .{ 0, 0, -(cam.far + cam.near) / (cam.far - cam.near), -1 },
        .{ 0, 0, -2 * cam.far * cam.near / (cam.far - cam.near), 0 },
    };
}

pub fn mat(cam: Camera) [4][4]f32 {
    return mat4.multiply(
        cam.perspectiveMat(),
        cam.viewMat(),
    );
}

pub fn moveRelative(cam: *Camera, offset: [3]f32) void {
    cam.position = vec3.add(cam.position, mat3.multiplyV(mat3.transpose(cam.lookMat()), offset));
}

fn cross(a: [3]f32, b: [3]f32) [3]f32 {
    return .{
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    };
}
