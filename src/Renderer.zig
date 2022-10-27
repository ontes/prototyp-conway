const std = @import("std");
const platform = @import("platform.zig");
const webgpu = @import("bindings/webgpu.zig");
const vec2 = @import("linalg.zig").vec(f32, 2);
const mat2 = @import("linalg.zig").mat(f32, 2);
const life = @import("life.zig");

const Renderer = @This();
const err = error.RendererError;

pub const Uniform = extern struct {
    cam_mat: [4][4]f32,
    cam_pos: [4]f32,
    light_dir: [4]f32,
};

instance: webgpu.Instance,
surface: webgpu.Surface,
adapter: webgpu.Adapter,
device: webgpu.Device,
swapchain: webgpu.SwapChain,
pipeline: webgpu.RenderPipeline,
bind_group_layout: webgpu.BindGroupLayout,
bind_group: webgpu.BindGroup,
depth_texture: webgpu.Texture,
depth_texture_view: webgpu.TextureView,
cells_buffer: webgpu.Buffer,
uniform_buffer: webgpu.Buffer,

instance_count: u32 = 0,

pub fn init(window: platform.Window) !Renderer {
    const window_size = try window.getSize();

    const instance = webgpu.createInstance(&.{});
    const surface = createSurface(instance, window);
    const adapter = try createAdapter(instance, surface);
    const device = try createDevice(adapter);
    const swapchain = createSwapchain(device, surface, window_size);

    const cells_buffer = device.createBuffer(&.{
        .usage = .{ .storage = true, .copy_dst = true },
        .size = @sizeOf([life.max_cells][4]i32),
    });
    const uniform_buffer = device.createBuffer(&.{
        .usage = .{ .uniform = true, .copy_dst = true },
        .size = @sizeOf([life.max_cells][4]i32),
    });

    const bind_group_layout = device.createBindGroupLayout(&.{
        .entry_count = 2,
        .entries = &[2]webgpu.BindGroupLayoutEntry{ .{
            .binding = 0,
            .visibility = .{ .vertex = true },
            .buffer = .{
                .binding_type = .read_only_storage,
                .min_binding_size = @sizeOf([life.max_cells][4]i32),
            },
        }, .{
            .binding = 1,
            .visibility = .{ .vertex = true, .fragment = true },
            .buffer = .{
                .binding_type = .uniform,
                .min_binding_size = @sizeOf(Uniform),
            },
        } },
    });

    const bind_group = device.createBindGroup(&.{
        .layout = bind_group_layout,
        .entry_count = 2,
        .entries = &[2]webgpu.BindGroupEntry{ .{
            .binding = 0,
            .buffer = cells_buffer,
            .offset = 0,
            .size = @sizeOf([life.max_cells][4]i32),
        }, .{
            .binding = 1,
            .buffer = uniform_buffer,
            .offset = 0,
            .size = @sizeOf(Uniform),
        } },
    });

    const pipeline = device.createRenderPipeline(&.{
        .layout = device.createPipelineLayout(&.{
            .bind_group_layout_count = 1,
            .bind_group_layouts = &[1]webgpu.BindGroupLayout{bind_group_layout},
        }),
        .vertex = .{
            .module = createShaderModuleWGSL(device, vs_source),
            .entry_point = "main",
            .buffer_count = 0,
            .buffers = &[0]webgpu.VertexBufferLayout{},
        },
        .primitive = .{
            .topology = .triangle_strip,
            .cull_mode = .front,
        },
        .depth_stencil = &webgpu.DepthStencilState{
            .format = .depth32_float,
            .depth_write_enabled = true,
            .depth_compare = .less,
        },
        .fragment = &webgpu.FragmentState{
            .module = createShaderModuleWGSL(device, fs_source),
            .entry_point = "main",
            .target_count = 1,
            .targets = &[1]webgpu.ColorTargetState{.{
                .format = .bgra8_unorm,
            }},
        },
    });

    const depth_texture = createDepthTexture(device, window_size);
    const depth_texture_view = depth_texture.createView(&.{});

    return .{
        .instance = instance,
        .surface = surface,
        .adapter = adapter,
        .device = device,
        .swapchain = swapchain,
        .pipeline = pipeline,
        .bind_group_layout = bind_group_layout,
        .bind_group = bind_group,
        .depth_texture = depth_texture,
        .depth_texture_view = depth_texture_view,
        .cells_buffer = cells_buffer,
        .uniform_buffer = uniform_buffer,
    };
}

pub fn deinit(renderer: Renderer) void {
    renderer.device.destroy();
}

pub fn draw(renderer: *Renderer) void {
    const command_encoder = renderer.device.createCommandEncoder(&.{});
    const pass = command_encoder.beginRenderPass(&.{
        .color_attachment_count = 1,
        .color_attachments = &[1]webgpu.RenderPassColorAttachment{.{
            .view = renderer.swapchain.getCurrentTextureView(),
            .load_op = .clear,
            .store_op = .store,
            .clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
        }},
        .depth_stencil_attachment = &.{
            .view = renderer.depth_texture_view,
            .depth_load_op = .clear,
            .depth_store_op = .store,
            .depth_clear_value = 1,
        },
    });
    pass.setPipeline(renderer.pipeline);
    pass.setBindGroup(0, renderer.bind_group, 0, &[0]u32{});
    pass.draw(14, renderer.instance_count, 0, 0);
    pass.end();
    var command_buffer = command_encoder.finish(&.{});
    renderer.device.getQueue().submit(1, &[1]webgpu.CommandBuffer{command_buffer});
    renderer.swapchain.present();
}

pub fn updateCells(renderer: *Renderer, cells: []const [4]i32) void {
    renderer.device.getQueue().writeBuffer(renderer.cells_buffer, 0, cells.ptr, cells.len * @sizeOf([4]i32));
    renderer.instance_count = @intCast(u32, cells.len);
}

pub fn updateUniform(renderer: Renderer, uniform: Uniform) void {
    renderer.device.getQueue().writeBuffer(renderer.uniform_buffer, 0, &uniform, @sizeOf(Uniform));
}

pub fn updateSize(renderer: *Renderer, size: [2]u32) void {
    renderer.swapchain = createSwapchain(renderer.device, renderer.surface, size);

    renderer.depth_texture.destroy();
    renderer.depth_texture = createDepthTexture(renderer.device, size);
    renderer.depth_texture_view = renderer.depth_texture.createView(&.{});
}

const vs_source =
    \\  const cube_strip = array<vec3<f32>,14>(
    \\      vec3<f32>(-1, 1, 1),
    \\      vec3<f32>( 1, 1, 1),
    \\      vec3<f32>(-1,-1, 1),
    \\      vec3<f32>( 1,-1, 1),
    \\      vec3<f32>( 1,-1,-1),
    \\      vec3<f32>( 1, 1, 1),
    \\      vec3<f32>( 1, 1,-1),
    \\      vec3<f32>(-1, 1, 1),
    \\      vec3<f32>(-1, 1,-1),
    \\      vec3<f32>(-1,-1, 1),
    \\      vec3<f32>(-1,-1,-1),
    \\      vec3<f32>( 1,-1,-1),
    \\      vec3<f32>(-1, 1,-1),
    \\      vec3<f32>( 1, 1,-1),
    \\  );
    \\  struct VertexOut {
    \\      @location(0) rel_pos: vec4<f32>,
    \\      @location(1) abs_pos: vec4<f32>,
    \\      @builtin(position) screen_pos: vec4<f32>,
    \\  }
    \\  struct Uniform {
    \\      cam_mat: mat4x4<f32>,
    \\      light_dir: vec4<f32>,
    \\  }
    \\  @group(0) @binding(0) var<storage> cells: array<vec3<i32>,1000000>;
    \\  @group(0) @binding(1) var<uniform> uniform: Uniform;
    \\  @vertex
    \\  fn main(@builtin(vertex_index) vertex_index : u32, @builtin(instance_index) instance_index : u32) -> VertexOut {
    \\      let cell_pos = vec4<f32>(vec3<f32>(cells[instance_index] * 2 - 99), 1);
    \\      var out: VertexOut;
    \\      out.rel_pos = vec4<f32>(cube_strip[vertex_index], 1);
    \\      out.abs_pos = cell_pos + out.rel_pos;
    \\      out.screen_pos = uniform.cam_mat * out.abs_pos;
    \\      return out;
    \\  }
;

const fs_source =
    \\  struct Uniform {
    \\      cam_mat: mat4x4<f32>,
    \\      cam_pos: vec4<f32>,
    \\      light_dir: vec4<f32>,
    \\  }
    \\  @group(0) @binding(1) var<uniform> uniform: Uniform;
    \\  @fragment
    \\  fn main(@location(0) rel_pos: vec4<f32>, @location(1) abs_pos: vec4<f32>) -> @location(0) vec4<f32> {
    \\      let normal: vec4<f32> = normalize(trunc(rel_pos));
    \\      let light: vec4<f32> = normalize(uniform.light_dir);
    \\      let diffuse_coef = max(dot(light, normal), 0);
    \\      let dist_coef: f32 = 1 - clamp((length(abs_pos - uniform.cam_pos) - 50) / 400, 0, 1);
    \\      return vec4<f32>(vec3<f32>((0.5 + 0.75 * diffuse_coef) * dist_coef), 1);
    \\  }
;

pub fn createSurface(instance: webgpu.Instance, window: platform.Window) webgpu.Surface {
    return instance.createSurface(&.{
        .next_in_chain = switch (@import("builtin").target.os.tag) {
            .windows => &webgpu.SurfaceDescriptorFromWindowsHWND{
                .hinstance = platform.window_class.instance,
                .hwnd = window.win32,
            },
            .linux => &webgpu.SurfaceDescriptorFromXlibWindow{
                .display = platform.display,
                .window = @intCast(u32, @ptrToInt(window.x11)),
            },
            // .macos => blk: {
            //     const ns_window = glfw.Native(.{ .cocoa = true }).getCocoaWindow(window);
            //     const ns_view = objc.msgSend(ns_window, "contentView", .{}, *anyopaque); // [nsWindow contentView]

            //     // create a CAMetalLayer that covers the whole window that will be passed to CreateSurface
            //     objc.msgSend(ns_view, "setWantsLayer:", .{true}, void); // [view setWantsLayer:YES]
            //     const layer = objc.msgSend(objc.getClass("CAMetalLayer"), "layer", .{}, ?*anyopaque) orelse return error.RendererError; // [CAMetalLayer layer]
            //     objc.msgSend(ns_view, "setLayer:", .{layer}, void); // [view setLayer:layer]

            //     // use retina if the window was created with retina support
            //     const scale_factor = objc.msgSend(ns_window, "backingScaleFactor", .{}, f64); // [ns_window backingScaleFactor]
            //     objc.msgSend(layer, "setContentsScale:", .{scale_factor}, void); // [layer setContentsScale:scale_factor]

            //     break :blk .{ .metal = .{ .layer = layer } };
            // },
            else => @compileError("unsupported os"),
        },
    });
}

fn createAdapter(instance: webgpu.Instance, surface: webgpu.Surface) !webgpu.Adapter {
    const Response = struct {
        status: webgpu.RequestAdapterStatus = .unknown,
        adapter: ?webgpu.Adapter = null,
    };
    const callback = struct {
        fn callback(status: webgpu.RequestAdapterStatus, adapter: ?webgpu.Adapter, message: [*:0]const u8, userdata: ?*anyopaque) callconv(.C) void {
            if (status == .error_) @panic(std.mem.span(message));
            @ptrCast(*Response, @alignCast(@alignOf(*Response), userdata.?)).* = .{ .status = status, .adapter = adapter };
        }
    }.callback;

    var response = Response{};
    instance.requestAdapter(&.{ .compatible_surface = surface }, &callback, &response);
    if (response.status != .success or response.adapter == null) return err;

    var properties = std.mem.zeroes(webgpu.AdapterProperties);
    response.adapter.?.getProperties(&properties);
    std.debug.print("Running {s} on {s} (driver {s}).\n", .{
        @tagName(properties.backend_type),
        properties.name,
        properties.driver_description,
    });

    return response.adapter.?;
}

fn createDevice(adapter: webgpu.Adapter) !webgpu.Device {
    const Response = struct {
        status: webgpu.RequestDeviceStatus = .unknown,
        device: ?webgpu.Device = null,
    };
    const deviceCallback = struct {
        fn deviceCallback(status: webgpu.RequestDeviceStatus, device: ?webgpu.Device, message: [*:0]const u8, userdata: ?*anyopaque) callconv(.C) void {
            if (status == .error_) @panic(std.mem.span(message));
            @ptrCast(*Response, @alignCast(@alignOf(*Response), userdata.?)).* = .{ .status = status, .device = device };
        }
    }.deviceCallback;

    var response = Response{};
    adapter.requestDevice(&.{}, &deviceCallback, &response);
    if (response.status != .success or response.device == null) return err;

    const errorCallback = struct {
        fn errorCallback(error_type: webgpu.ErrorType, message: [*:0]const u8, _: ?*anyopaque) callconv(.C) void {
            _ = error_type;
            @panic(std.mem.span(message));
        }
    }.errorCallback;
    response.device.?.setUncapturedErrorCallback(&errorCallback, null);

    const lostCallback = struct {
        fn lostCallback(reason: webgpu.DeviceLostReason, message: [*:0]const u8, _: ?*anyopaque) callconv(.C) void {
            _ = reason;
            std.debug.print("{s}\n", .{message});
        }
    }.lostCallback;
    response.device.?.setDeviceLostCallback(&lostCallback, null);

    return response.device.?;
}

fn createSwapchain(device: webgpu.Device, surface: webgpu.Surface, size: [2]u32) webgpu.SwapChain {
    return device.createSwapChain(surface, &.{
        .usage = .{ .render_attachment = true },
        .format = .bgra8_unorm,
        .width = size[0],
        .height = size[1],
        .present_mode = .fifo,
    });
}

fn createDepthTexture(device: webgpu.Device, size: [2]u32) webgpu.Texture {
    return device.createTexture(&.{
        .usage = .{ .render_attachment = true },
        .dimension = ._2d,
        .size = .{ .width = size[0], .height = size[1] },
        .format = .depth32_float,
    });
}

fn createShaderModuleWGSL(device: webgpu.Device, source: [*:0]const u8) webgpu.ShaderModule {
    return device.createShaderModule(&.{
        .next_in_chain = &webgpu.ShaderModuleWGSLDescriptor{ .source = source },
    });
}
