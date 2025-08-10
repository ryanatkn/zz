const std = @import("std");

const sdl = @import("sdl.zig").c;

// Circle uniform buffer structure matching HLSL
// Let's check what size Zig actually gives us and adjust accordingly
const CircleUniforms = extern struct {
    screen_size: [2]f32, // 8 bytes
    circle_center: [2]f32, // 8 bytes
    circle_radius: f32, // 4 bytes
    _padding1: f32, // 4 bytes
    circle_color: [4]f32, // 16 bytes (RGBA)
    // Total should be 40 bytes, but extern struct might align differently
};

pub const CircleTest = struct {
    allocator: std.mem.Allocator,
    device: *sdl.SDL_GPUDevice,
    vertex_shader: *sdl.SDL_GPUShader,
    fragment_shader: *sdl.SDL_GPUShader,
    pipeline: *sdl.SDL_GPUGraphicsPipeline,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, window: *sdl.SDL_Window) !Self {
        std.debug.print("Creating GPU device for circle test...\n", .{});
        std.debug.print("CircleUniforms size: {} bytes\n", .{@sizeOf(CircleUniforms)});

        // Create GPU device with multiple shader formats supported
        const device = sdl.SDL_CreateGPUDevice(sdl.SDL_GPU_SHADERFORMAT_SPIRV | sdl.SDL_GPU_SHADERFORMAT_DXIL, false, // debug mode off for now
            null // auto-select backend
        ) orelse {
            std.debug.print("Failed to create GPU device\n", .{});
            return error.GPUDeviceCreationFailed;
        };

        // Claim window for GPU rendering
        if (!sdl.SDL_ClaimWindowForGPUDevice(device, window)) {
            std.debug.print("Failed to claim window for GPU device\n", .{});
            sdl.SDL_DestroyGPUDevice(device);
            return error.WindowClaimFailed;
        }

        std.debug.print("GPU device created successfully\n", .{});

        var self = Self{
            .allocator = allocator,
            .device = device,
            .vertex_shader = undefined,
            .fragment_shader = undefined,
            .pipeline = undefined,
        };

        try self.createShaders();
        try self.createPipeline();

        // Show window now that GPU is set up
        _ = sdl.SDL_ShowWindow(window);

        return self;
    }

    pub fn deinit(self: *Self) void {
        sdl.SDL_ReleaseGPUGraphicsPipeline(self.device, self.pipeline);
        sdl.SDL_ReleaseGPUShader(self.device, self.vertex_shader);
        sdl.SDL_ReleaseGPUShader(self.device, self.fragment_shader);
        sdl.SDL_DestroyGPUDevice(self.device);
    }

    fn createShaders(self: *Self) !void {
        std.debug.print("Loading circle test shaders...\n", .{});

        // Load compiled simple_circle shaders (fixed coordinate transformation)
        const circle_vs_spv = @embedFile("shaders/compiled/vulkan/simple_circle_vs.spv");
        const circle_fs_spv = @embedFile("shaders/compiled/vulkan/simple_circle_ps.spv");

        // Create vertex shader WITH uniform buffer support
        const vs_info = sdl.SDL_GPUShaderCreateInfo{
            .code_size = circle_vs_spv.len,
            .code = @ptrCast(circle_vs_spv.ptr),
            .entrypoint = "vs_main",
            .format = sdl.SDL_GPU_SHADERFORMAT_SPIRV,
            .stage = sdl.SDL_GPU_SHADERSTAGE_VERTEX,
            .num_samplers = 0,
            .num_storage_textures = 0,
            .num_storage_buffers = 0,
            .num_uniform_buffers = 1, // CRITICAL: Must match shader uniform count
        };

        self.vertex_shader = sdl.SDL_CreateGPUShader(self.device, &vs_info) orelse {
            std.debug.print("Failed to create circle vertex shader\n", .{});
            std.debug.print("SDL Error: {s}\n", .{sdl.SDL_GetError()});
            return error.VertexShaderFailed;
        };

        // Create fragment shader (no uniforms needed for simple circle)
        const fs_info = sdl.SDL_GPUShaderCreateInfo{
            .code_size = circle_fs_spv.len,
            .code = @ptrCast(circle_fs_spv.ptr),
            .entrypoint = "ps_main",
            .format = sdl.SDL_GPU_SHADERFORMAT_SPIRV,
            .stage = sdl.SDL_GPU_SHADERSTAGE_FRAGMENT,
            .num_samplers = 0,
            .num_storage_textures = 0,
            .num_storage_buffers = 0,
            .num_uniform_buffers = 0, // Fragment shader doesn't need uniforms
        };

        self.fragment_shader = sdl.SDL_CreateGPUShader(self.device, &fs_info) orelse {
            std.debug.print("Failed to create circle fragment shader\n", .{});
            std.debug.print("SDL Error: {s}\n", .{sdl.SDL_GetError()});
            return error.FragmentShaderFailed;
        };

        std.debug.print("Circle shaders created successfully\n", .{});
    }

    fn createPipeline(self: *Self) !void {
        std.debug.print("Creating circle graphics pipeline...\n", .{});

        // No vertex input - completely procedural
        const vertex_input_state = sdl.SDL_GPUVertexInputState{
            .vertex_buffer_descriptions = null,
            .num_vertex_buffers = 0,
            .vertex_attributes = null,
            .num_vertex_attributes = 0,
        };

        // Basic rasterizer state
        const rasterizer_state = sdl.SDL_GPURasterizerState{
            .fill_mode = sdl.SDL_GPU_FILLMODE_FILL,
            .cull_mode = sdl.SDL_GPU_CULLMODE_NONE,
            .front_face = sdl.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
            .depth_bias_constant_factor = 0.0,
            .depth_bias_clamp = 0.0,
            .depth_bias_slope_factor = 0.0,
            .enable_depth_bias = false,
        };

        // Basic multisample state
        const multisample_state = sdl.SDL_GPUMultisampleState{
            .sample_count = sdl.SDL_GPU_SAMPLECOUNT_1,
            .sample_mask = 0xFFFFFFFF,
            .enable_mask = false,
        };

        // Color target configuration with alpha blending for anti-aliasing
        const color_target_desc = sdl.SDL_GPUColorTargetDescription{
            .format = sdl.SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM,
            .blend_state = .{
                .src_color_blendfactor = sdl.SDL_GPU_BLENDFACTOR_SRC_ALPHA,
                .dst_color_blendfactor = sdl.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
                .color_blend_op = sdl.SDL_GPU_BLENDOP_ADD,
                .src_alpha_blendfactor = sdl.SDL_GPU_BLENDFACTOR_ONE,
                .dst_alpha_blendfactor = sdl.SDL_GPU_BLENDFACTOR_ZERO,
                .alpha_blend_op = sdl.SDL_GPU_BLENDOP_ADD,
                .color_write_mask = sdl.SDL_GPU_COLORCOMPONENT_R | sdl.SDL_GPU_COLORCOMPONENT_G | sdl.SDL_GPU_COLORCOMPONENT_B | sdl.SDL_GPU_COLORCOMPONENT_A,
                .enable_blend = true, // Enable blending for anti-aliasing
                .enable_color_write_mask = false,
            },
        };

        const target_info = sdl.SDL_GPUGraphicsPipelineTargetInfo{
            .color_target_descriptions = &color_target_desc,
            .num_color_targets = 1,
            .depth_stencil_format = sdl.SDL_GPU_TEXTUREFORMAT_INVALID,
            .has_depth_stencil_target = false,
        };

        // Create the pipeline
        const pipeline_create_info = sdl.SDL_GPUGraphicsPipelineCreateInfo{
            .vertex_shader = self.vertex_shader,
            .fragment_shader = self.fragment_shader,
            .vertex_input_state = vertex_input_state,
            .primitive_type = sdl.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
            .rasterizer_state = rasterizer_state,
            .multisample_state = multisample_state,
            .target_info = target_info,
        };

        self.pipeline = sdl.SDL_CreateGPUGraphicsPipeline(self.device, &pipeline_create_info) orelse {
            std.debug.print("Failed to create circle graphics pipeline\n", .{});
            std.debug.print("SDL Error: {s}\n", .{sdl.SDL_GetError()});
            return error.PipelineCreationFailed;
        };

        std.debug.print("Circle pipeline created successfully!\n", .{});
    }

    pub fn render(self: *Self, window: *sdl.SDL_Window) !void {
        // Prepare uniform data
        var window_w: c_int = undefined;
        var window_h: c_int = undefined;
        _ = sdl.SDL_GetWindowSize(window, &window_w, &window_h);

        const ticks = sdl.SDL_GetTicks();
        const time_sec = @as(f32, @floatFromInt(ticks)) / 1000.0;

        // Animated circle parameters
        const screen_center_x = @as(f32, @floatFromInt(window_w)) / 2.0;
        const screen_center_y = @as(f32, @floatFromInt(window_h)) / 2.0;

        // Animated position (circular motion)
        const orbit_radius = 100.0;
        const circle_x = screen_center_x + @sin(time_sec * 0.8) * orbit_radius;
        const circle_y = screen_center_y + @cos(time_sec * 0.8) * orbit_radius;

        // Pulsing radius
        const base_radius = 80.0;
        const radius_pulse = @sin(time_sec * 2.0) * 20.0 + base_radius;

        // Color cycling (hue shift over time)
        const hue = @mod(time_sec * 0.3, 1.0);
        const circle_color = hsvToRgb(hue, 0.8, 0.9);

        const uniform_data = CircleUniforms{
            .screen_size = [2]f32{ @floatFromInt(window_w), @floatFromInt(window_h) },
            .circle_center = [2]f32{ circle_x, circle_y },
            .circle_radius = radius_pulse,
            ._padding1 = 0.0,
            .circle_color = [4]f32{ circle_color[0], circle_color[1], circle_color[2], 1.0 },
        };

        // Acquire command buffer
        const cmd_buffer = sdl.SDL_AcquireGPUCommandBuffer(self.device) orelse {
            std.debug.print("Failed to acquire GPU command buffer\n", .{});
            return error.CommandBufferFailed;
        };

        // CRITICAL: Push uniform data BEFORE beginning render pass
        sdl.SDL_PushGPUVertexUniformData(cmd_buffer, 0, &uniform_data, @sizeOf(CircleUniforms));

        // Acquire swapchain texture
        var swapchain_texture: ?*sdl.SDL_GPUTexture = null;
        if (!sdl.SDL_WaitAndAcquireGPUSwapchainTexture(cmd_buffer, window, &swapchain_texture, null, null)) {
            std.debug.print("Failed to acquire swapchain texture: {s}\n", .{sdl.SDL_GetError()});
            return error.SwapchainFailed;
        }

        if (swapchain_texture) |texture| {
            // Set up color target - clear to dark background
            const color_target_info = sdl.SDL_GPUColorTargetInfo{
                .texture = texture,
                .clear_color = .{ .r = 0.1, .g = 0.1, .b = 0.2, .a = 1.0 }, // Dark blue background
                .load_op = sdl.SDL_GPU_LOADOP_CLEAR,
                .store_op = sdl.SDL_GPU_STOREOP_STORE,
                .cycle = false,
            };

            // Begin render pass
            const render_pass = sdl.SDL_BeginGPURenderPass(cmd_buffer, &color_target_info, 1, null) orelse {
                std.debug.print("Failed to begin render pass\n", .{});
                return error.RenderPassFailed;
            };

            // Bind pipeline
            sdl.SDL_BindGPUGraphicsPipeline(render_pass, self.pipeline);

            // Debug: print circle data every 3 seconds
            const frame_count = @as(u32, @intFromFloat(time_sec * 60));
            if (frame_count % 180 == 0 and frame_count > 0) {
                std.debug.print("Circle - Pos: ({d}, {d}), Radius: {d}, Color: ({d}, {d}, {d})\n", .{ uniform_data.circle_center[0], uniform_data.circle_center[1], uniform_data.circle_radius, uniform_data.circle_color[0], uniform_data.circle_color[1], uniform_data.circle_color[2] });
            }

            // Draw 6 vertices (2 triangles forming a quad)
            sdl.SDL_DrawGPUPrimitives(render_pass, 6, 1, 0, 0);

            // End render pass
            sdl.SDL_EndGPURenderPass(render_pass);
        }

        // Submit command buffer
        _ = sdl.SDL_SubmitGPUCommandBuffer(cmd_buffer);
    }
};

// HSV to RGB conversion for color cycling
fn hsvToRgb(h: f32, s: f32, v: f32) [3]f32 {
    const chroma = v * s;
    const x = chroma * (1.0 - @abs(@mod(h * 6.0, 2.0) - 1.0));
    const m = v - chroma;

    var r: f32 = 0;
    var g: f32 = 0;
    var b: f32 = 0;

    if (h < 1.0 / 6.0) {
        r = chroma;
        g = x;
        b = 0;
    } else if (h < 2.0 / 6.0) {
        r = x;
        g = chroma;
        b = 0;
    } else if (h < 3.0 / 6.0) {
        r = 0;
        g = chroma;
        b = x;
    } else if (h < 4.0 / 6.0) {
        r = 0;
        g = x;
        b = chroma;
    } else if (h < 5.0 / 6.0) {
        r = x;
        g = 0;
        b = chroma;
    } else {
        r = chroma;
        g = 0;
        b = x;
    }

    return [3]f32{ r + m, g + m, b + m };
}
