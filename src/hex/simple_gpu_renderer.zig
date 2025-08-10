const std = @import("std");

const sdl = @import("sdl.zig").c;

const types = @import("types.zig");

const Vec2 = types.Vec2;
const Color = types.Color;

// Circle uniform buffer - color components split to avoid HLSL array packing issues
const CircleUniforms = extern struct {
    screen_size: [2]f32, // 8 bytes
    circle_center: [2]f32, // 8 bytes
    circle_radius: f32, // 4 bytes
    circle_color_r: f32, // 4 bytes
    circle_color_g: f32, // 4 bytes
    circle_color_b: f32, // 4 bytes
    circle_color_a: f32, // 4 bytes
    _padding: f32, // 4 bytes (16-byte alignment)
    // Total: 40 bytes
};

// Rectangle uniform buffer - color components split to avoid HLSL array packing issues
const RectUniforms = extern struct {
    screen_size: [2]f32, // 8 bytes
    rect_position: [2]f32, // 8 bytes
    rect_size: [2]f32, // 8 bytes
    rect_color_r: f32, // 4 bytes
    rect_color_g: f32, // 4 bytes
    rect_color_b: f32, // 4 bytes
    rect_color_a: f32, // 4 bytes
    // Total: 40 bytes
};

// Effect uniform buffer for GPU-based visual effects
const EffectUniforms = extern struct {
    screen_size: [2]f32, // 8 bytes
    center: [2]f32, // 8 bytes
    radius: f32, // 4 bytes
    color_r: f32, // 4 bytes
    color_g: f32, // 4 bytes
    color_b: f32, // 4 bytes
    color_a: f32, // 4 bytes
    intensity: f32, // 4 bytes
    time: f32, // 4 bytes (for animations)
    _padding: [3]f32, // 12 bytes (16-byte alignment)
    // Total: 64 bytes
};

pub const SimpleGPURenderer = struct {
    allocator: std.mem.Allocator,
    device: *sdl.SDL_GPUDevice,
    window: *sdl.SDL_Window,

    // Circle rendering
    circle_vs: *sdl.SDL_GPUShader,
    circle_ps: *sdl.SDL_GPUShader,
    circle_pipeline: *sdl.SDL_GPUGraphicsPipeline,

    // Rectangle rendering
    rect_vs: *sdl.SDL_GPUShader,
    rect_ps: *sdl.SDL_GPUShader,
    rect_pipeline: *sdl.SDL_GPUGraphicsPipeline,

    // Effect rendering
    effect_vs: *sdl.SDL_GPUShader,
    effect_ps: *sdl.SDL_GPUShader,
    effect_pipeline: *sdl.SDL_GPUGraphicsPipeline,

    // Current frame data
    screen_width: f32,
    screen_height: f32,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, window: *sdl.SDL_Window) !Self {
        std.debug.print("Creating simple GPU device...\n", .{});

        const device = sdl.SDL_CreateGPUDevice(sdl.SDL_GPU_SHADERFORMAT_SPIRV | sdl.SDL_GPU_SHADERFORMAT_DXIL, false, // debug mode off
            null // auto-select backend
        ) orelse {
            std.debug.print("Failed to create GPU device\n", .{});
            return error.GPUDeviceCreationFailed;
        };

        if (!sdl.SDL_ClaimWindowForGPUDevice(device, window)) {
            std.debug.print("Failed to claim window for GPU device\n", .{});
            sdl.SDL_DestroyGPUDevice(device);
            return error.WindowClaimFailed;
        }

        std.debug.print("GPU device created successfully\n", .{});

        var self = Self{
            .allocator = allocator,
            .device = device,
            .window = window,
            .circle_vs = undefined,
            .circle_ps = undefined,
            .circle_pipeline = undefined,
            .rect_vs = undefined,
            .rect_ps = undefined,
            .rect_pipeline = undefined,
            .effect_vs = undefined,
            .effect_ps = undefined,
            .effect_pipeline = undefined,
            .screen_width = 1920.0,
            .screen_height = 1080.0,
        };

        try self.createShaders();
        try self.createPipelines();

        // Show window now that GPU is set up
        _ = sdl.SDL_ShowWindow(window);

        return self;
    }

    pub fn deinit(self: *Self) void {
        sdl.SDL_ReleaseGPUGraphicsPipeline(self.device, self.circle_pipeline);
        sdl.SDL_ReleaseGPUGraphicsPipeline(self.device, self.rect_pipeline);
        sdl.SDL_ReleaseGPUGraphicsPipeline(self.device, self.effect_pipeline);
        sdl.SDL_ReleaseGPUShader(self.device, self.circle_vs);
        sdl.SDL_ReleaseGPUShader(self.device, self.circle_ps);
        sdl.SDL_ReleaseGPUShader(self.device, self.rect_vs);
        sdl.SDL_ReleaseGPUShader(self.device, self.rect_ps);
        sdl.SDL_ReleaseGPUShader(self.device, self.effect_vs);
        sdl.SDL_ReleaseGPUShader(self.device, self.effect_ps);
        sdl.SDL_DestroyGPUDevice(self.device);
    }

    fn createShaders(self: *Self) !void {
        std.debug.print("Loading simple GPU shaders...\n", .{});

        // Load simple circle shaders
        const circle_vs_spv = @embedFile("shaders/compiled/vulkan/simple_circle_vs.spv");
        const circle_ps_spv = @embedFile("shaders/compiled/vulkan/simple_circle_ps.spv");

        const circle_vs_info = sdl.SDL_GPUShaderCreateInfo{
            .code_size = circle_vs_spv.len,
            .code = @ptrCast(circle_vs_spv.ptr),
            .entrypoint = "vs_main",
            .format = sdl.SDL_GPU_SHADERFORMAT_SPIRV,
            .stage = sdl.SDL_GPU_SHADERSTAGE_VERTEX,
            .num_samplers = 0,
            .num_storage_textures = 0,
            .num_storage_buffers = 0,
            .num_uniform_buffers = 1, // Circle shader uses uniforms
        };

        self.circle_vs = sdl.SDL_CreateGPUShader(self.device, &circle_vs_info) orelse {
            std.debug.print("Failed to create circle vertex shader: {s}\n", .{sdl.SDL_GetError()});
            return error.VertexShaderFailed;
        };

        const circle_ps_info = sdl.SDL_GPUShaderCreateInfo{
            .code_size = circle_ps_spv.len,
            .code = @ptrCast(circle_ps_spv.ptr),
            .entrypoint = "ps_main",
            .format = sdl.SDL_GPU_SHADERFORMAT_SPIRV,
            .stage = sdl.SDL_GPU_SHADERSTAGE_FRAGMENT,
            .num_samplers = 0,
            .num_storage_textures = 0,
            .num_storage_buffers = 0,
            .num_uniform_buffers = 0, // Fragment shader doesn't use uniforms directly
        };

        self.circle_ps = sdl.SDL_CreateGPUShader(self.device, &circle_ps_info) orelse {
            std.debug.print("Failed to create circle fragment shader\n", .{});
            return error.FragmentShaderFailed;
        };

        // Load rectangle shaders
        const rect_vs_spv = @embedFile("shaders/compiled/vulkan/simple_rectangle_vs.spv");
        const rect_ps_spv = @embedFile("shaders/compiled/vulkan/simple_rectangle_ps.spv");

        const rect_vs_info = sdl.SDL_GPUShaderCreateInfo{
            .code_size = rect_vs_spv.len,
            .code = @ptrCast(rect_vs_spv.ptr),
            .entrypoint = "vs_main",
            .format = sdl.SDL_GPU_SHADERFORMAT_SPIRV,
            .stage = sdl.SDL_GPU_SHADERSTAGE_VERTEX,
            .num_samplers = 0,
            .num_storage_textures = 0,
            .num_storage_buffers = 0,
            .num_uniform_buffers = 1, // Rectangle shader uses uniforms
        };

        self.rect_vs = sdl.SDL_CreateGPUShader(self.device, &rect_vs_info) orelse {
            std.debug.print("Failed to create rectangle vertex shader\n", .{});
            return error.VertexShaderFailed;
        };

        const rect_ps_info = sdl.SDL_GPUShaderCreateInfo{
            .code_size = rect_ps_spv.len,
            .code = @ptrCast(rect_ps_spv.ptr),
            .entrypoint = "ps_main",
            .format = sdl.SDL_GPU_SHADERFORMAT_SPIRV,
            .stage = sdl.SDL_GPU_SHADERSTAGE_FRAGMENT,
            .num_samplers = 0,
            .num_storage_textures = 0,
            .num_storage_buffers = 0,
            .num_uniform_buffers = 0, // Fragment shader doesn't need uniforms
        };

        self.rect_ps = sdl.SDL_CreateGPUShader(self.device, &rect_ps_info) orelse {
            std.debug.print("Failed to create rectangle fragment shader\n", .{});
            return error.FragmentShaderFailed;
        };

        // Load effect shaders
        const effect_vs_spv = @embedFile("shaders/compiled/vulkan/effect_vs.spv");
        const effect_ps_spv = @embedFile("shaders/compiled/vulkan/effect_ps.spv");

        const effect_vs_info = sdl.SDL_GPUShaderCreateInfo{
            .code_size = effect_vs_spv.len,
            .code = @ptrCast(effect_vs_spv.ptr),
            .entrypoint = "vs_main",
            .format = sdl.SDL_GPU_SHADERFORMAT_SPIRV,
            .stage = sdl.SDL_GPU_SHADERSTAGE_VERTEX,
            .num_samplers = 0,
            .num_storage_textures = 0,
            .num_storage_buffers = 0,
            .num_uniform_buffers = 1, // Effect shader uses uniforms
        };

        self.effect_vs = sdl.SDL_CreateGPUShader(self.device, &effect_vs_info) orelse {
            std.debug.print("Failed to create effect vertex shader\n", .{});
            return error.VertexShaderFailed;
        };

        const effect_ps_info = sdl.SDL_GPUShaderCreateInfo{
            .code_size = effect_ps_spv.len,
            .code = @ptrCast(effect_ps_spv.ptr),
            .entrypoint = "ps_main",
            .format = sdl.SDL_GPU_SHADERFORMAT_SPIRV,
            .stage = sdl.SDL_GPU_SHADERSTAGE_FRAGMENT,
            .num_samplers = 0,
            .num_storage_textures = 0,
            .num_storage_buffers = 0,
            .num_uniform_buffers = 0, // Fragment shader doesn't need uniforms
        };

        self.effect_ps = sdl.SDL_CreateGPUShader(self.device, &effect_ps_info) orelse {
            std.debug.print("Failed to create effect fragment shader\n", .{});
            return error.FragmentShaderFailed;
        };

        std.debug.print("Simple GPU shaders loaded successfully\n", .{});
    }

    fn createPipelines(self: *Self) !void {
        std.debug.print("Creating simple graphics pipelines...\n", .{});

        // Get the actual swapchain texture format (usually B8G8R8A8 on most systems)
        const swapchain_format = sdl.SDL_GetGPUSwapchainTextureFormat(self.device, self.window);

        // No vertex input - completely procedural like test cases
        const vertex_input_state = sdl.SDL_GPUVertexInputState{
            .vertex_buffer_descriptions = null,
            .num_vertex_buffers = 0,
            .vertex_attributes = null,
            .num_vertex_attributes = 0,
        };

        const rasterizer_state = sdl.SDL_GPURasterizerState{
            .fill_mode = sdl.SDL_GPU_FILLMODE_FILL,
            .cull_mode = sdl.SDL_GPU_CULLMODE_NONE,
            .front_face = sdl.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
            .depth_bias_constant_factor = 0.0,
            .depth_bias_clamp = 0.0,
            .depth_bias_slope_factor = 0.0,
            .enable_depth_bias = false,
        };

        const multisample_state = sdl.SDL_GPUMultisampleState{
            .sample_count = sdl.SDL_GPU_SAMPLECOUNT_1,
            .sample_mask = 0xFFFFFFFF,
            .enable_mask = false,
        };

        // Alpha blending for smooth circles - use actual swapchain format
        const alpha_blend_state = sdl.SDL_GPUColorTargetDescription{
            .format = swapchain_format,
            .blend_state = .{
                .src_color_blendfactor = sdl.SDL_GPU_BLENDFACTOR_SRC_ALPHA,
                .dst_color_blendfactor = sdl.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
                .color_blend_op = sdl.SDL_GPU_BLENDOP_ADD,
                .src_alpha_blendfactor = sdl.SDL_GPU_BLENDFACTOR_ONE,
                .dst_alpha_blendfactor = sdl.SDL_GPU_BLENDFACTOR_ZERO,
                .alpha_blend_op = sdl.SDL_GPU_BLENDOP_ADD,
                .color_write_mask = sdl.SDL_GPU_COLORCOMPONENT_R | sdl.SDL_GPU_COLORCOMPONENT_G | sdl.SDL_GPU_COLORCOMPONENT_B | sdl.SDL_GPU_COLORCOMPONENT_A,
                .enable_blend = true,
                .enable_color_write_mask = false,
            },
        };

        // No blending for solid rectangles - use actual swapchain format
        const solid_blend_state = sdl.SDL_GPUColorTargetDescription{
            .format = swapchain_format,
            .blend_state = .{
                .src_color_blendfactor = sdl.SDL_GPU_BLENDFACTOR_ONE,
                .dst_color_blendfactor = sdl.SDL_GPU_BLENDFACTOR_ZERO,
                .color_blend_op = sdl.SDL_GPU_BLENDOP_ADD,
                .src_alpha_blendfactor = sdl.SDL_GPU_BLENDFACTOR_ONE,
                .dst_alpha_blendfactor = sdl.SDL_GPU_BLENDFACTOR_ZERO,
                .alpha_blend_op = sdl.SDL_GPU_BLENDOP_ADD,
                .color_write_mask = sdl.SDL_GPU_COLORCOMPONENT_R | sdl.SDL_GPU_COLORCOMPONENT_G | sdl.SDL_GPU_COLORCOMPONENT_B | sdl.SDL_GPU_COLORCOMPONENT_A,
                .enable_blend = false,
                .enable_color_write_mask = false,
            },
        };

        const circle_target_info = sdl.SDL_GPUGraphicsPipelineTargetInfo{
            .color_target_descriptions = &alpha_blend_state,
            .num_color_targets = 1,
            .depth_stencil_format = sdl.SDL_GPU_TEXTUREFORMAT_INVALID,
            .has_depth_stencil_target = false,
        };

        const rect_target_info = sdl.SDL_GPUGraphicsPipelineTargetInfo{
            .color_target_descriptions = &solid_blend_state,
            .num_color_targets = 1,
            .depth_stencil_format = sdl.SDL_GPU_TEXTUREFORMAT_INVALID,
            .has_depth_stencil_target = false,
        };

        // Create circle pipeline
        const circle_create_info = sdl.SDL_GPUGraphicsPipelineCreateInfo{
            .vertex_shader = self.circle_vs,
            .fragment_shader = self.circle_ps,
            .vertex_input_state = vertex_input_state,
            .primitive_type = sdl.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
            .rasterizer_state = rasterizer_state,
            .multisample_state = multisample_state,
            .target_info = circle_target_info,
        };

        self.circle_pipeline = sdl.SDL_CreateGPUGraphicsPipeline(self.device, &circle_create_info) orelse {
            std.debug.print("Failed to create circle graphics pipeline\n", .{});
            std.debug.print("SDL Error: {s}\n", .{sdl.SDL_GetError()});
            return error.PipelineCreationFailed;
        };

        // Create rectangle pipeline
        const rect_create_info = sdl.SDL_GPUGraphicsPipelineCreateInfo{
            .vertex_shader = self.rect_vs,
            .fragment_shader = self.rect_ps,
            .vertex_input_state = vertex_input_state,
            .primitive_type = sdl.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
            .rasterizer_state = rasterizer_state,
            .multisample_state = multisample_state,
            .target_info = rect_target_info,
        };

        self.rect_pipeline = sdl.SDL_CreateGPUGraphicsPipeline(self.device, &rect_create_info) orelse {
            std.debug.print("Failed to create rectangle graphics pipeline\n", .{});
            std.debug.print("SDL Error: {s}\n", .{sdl.SDL_GetError()});
            return error.PipelineCreationFailed;
        };

        // Create effect pipeline (needs alpha blending for visual effects)
        const effect_target_info = sdl.SDL_GPUGraphicsPipelineTargetInfo{
            .color_target_descriptions = &alpha_blend_state,
            .num_color_targets = 1,
            .depth_stencil_format = sdl.SDL_GPU_TEXTUREFORMAT_INVALID,
            .has_depth_stencil_target = false,
        };

        const effect_create_info = sdl.SDL_GPUGraphicsPipelineCreateInfo{
            .vertex_shader = self.effect_vs,
            .fragment_shader = self.effect_ps,
            .vertex_input_state = vertex_input_state,
            .primitive_type = sdl.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
            .rasterizer_state = rasterizer_state,
            .multisample_state = multisample_state,
            .target_info = effect_target_info,
        };

        self.effect_pipeline = sdl.SDL_CreateGPUGraphicsPipeline(self.device, &effect_create_info) orelse {
            std.debug.print("Failed to create effect graphics pipeline\n", .{});
            std.debug.print("SDL Error: {s}\n", .{sdl.SDL_GetError()});
            return error.PipelineCreationFailed;
        };

        std.debug.print("Simple graphics pipelines created successfully!\n", .{});
    }

    // Begin frame and get command buffer ready for rendering
    pub fn beginFrame(self: *Self, window: *sdl.SDL_Window) !*sdl.SDL_GPUCommandBuffer {
        // Update screen size
        var window_w: c_int = undefined;
        var window_h: c_int = undefined;
        _ = sdl.SDL_GetWindowSize(window, &window_w, &window_h);
        self.screen_width = @floatFromInt(window_w);
        self.screen_height = @floatFromInt(window_h);

        // Acquire command buffer
        const cmd_buffer = sdl.SDL_AcquireGPUCommandBuffer(self.device) orelse {
            return error.CommandBufferFailed;
        };

        return cmd_buffer;
    }

    // Start a render pass with the given background color
    pub fn beginRenderPass(self: *Self, cmd_buffer: *sdl.SDL_GPUCommandBuffer, window: *sdl.SDL_Window, bg_color: Color) !*sdl.SDL_GPURenderPass {
        _ = self;
        // Acquire swapchain texture
        var swapchain_texture: ?*sdl.SDL_GPUTexture = null;
        if (!sdl.SDL_WaitAndAcquireGPUSwapchainTexture(cmd_buffer, window, &swapchain_texture, null, null)) {
            return error.SwapchainFailed;
        }

        if (swapchain_texture) |texture| {
            const color_target_info = sdl.SDL_GPUColorTargetInfo{
                .texture = texture,
                .clear_color = .{ .r = @as(f32, @floatFromInt(bg_color.r)) / 255.0, .g = @as(f32, @floatFromInt(bg_color.g)) / 255.0, .b = @as(f32, @floatFromInt(bg_color.b)) / 255.0, .a = 1.0 },
                .load_op = sdl.SDL_GPU_LOADOP_CLEAR,
                .store_op = sdl.SDL_GPU_STOREOP_STORE,
                .cycle = false,
            };

            const render_pass = sdl.SDL_BeginGPURenderPass(cmd_buffer, &color_target_info, 1, null) orelse {
                return error.RenderPassFailed;
            };

            return render_pass;
        }

        return error.SwapchainFailed;
    }

    // Draw a single circle with distance field anti-aliasing
    pub fn drawCircle(self: *Self, cmd_buffer: *sdl.SDL_GPUCommandBuffer, render_pass: *sdl.SDL_GPURenderPass, pos: Vec2, radius: f32, color: Color) void {
        // Prepare uniform data
        const uniform_data = CircleUniforms{
            .screen_size = [2]f32{ self.screen_width, self.screen_height },
            .circle_center = [2]f32{ pos.x, pos.y },
            .circle_radius = radius,
            .circle_color_r = @as(f32, @floatFromInt(color.r)) / 255.0,
            .circle_color_g = @as(f32, @floatFromInt(color.g)) / 255.0,
            .circle_color_b = @as(f32, @floatFromInt(color.b)) / 255.0,
            .circle_color_a = @as(f32, @floatFromInt(color.a)) / 255.0,
            ._padding = 0.0,
        };

        // Push uniform data BEFORE binding pipeline
        sdl.SDL_PushGPUVertexUniformData(cmd_buffer, 0, &uniform_data, @sizeOf(CircleUniforms));

        // Bind pipeline and draw
        sdl.SDL_BindGPUGraphicsPipeline(render_pass, self.circle_pipeline);
        sdl.SDL_DrawGPUPrimitives(render_pass, 6, 1, 0, 0); // 6 vertices for quad
    }

    // Draw a single rectangle
    pub fn drawRect(self: *Self, cmd_buffer: *sdl.SDL_GPUCommandBuffer, render_pass: *sdl.SDL_GPURenderPass, pos: Vec2, size: Vec2, color: Color) void {
        // Prepare uniform data - swap R and B for BGR swapchain format
        const uniform_data = RectUniforms{
            .screen_size = [2]f32{ self.screen_width, self.screen_height },
            .rect_position = [2]f32{ pos.x, pos.y },
            .rect_size = [2]f32{ size.x, size.y },
            .rect_color_r = @as(f32, @floatFromInt(color.r)) / 255.0,
            .rect_color_g = @as(f32, @floatFromInt(color.g)) / 255.0,
            .rect_color_b = @as(f32, @floatFromInt(color.b)) / 255.0,
            .rect_color_a = @as(f32, @floatFromInt(color.a)) / 255.0,
        };

        // Push uniform data BEFORE binding pipeline (critical for SDL3 GPU)
        sdl.SDL_PushGPUVertexUniformData(cmd_buffer, 0, &uniform_data, @sizeOf(RectUniforms));

        // Bind pipeline and draw
        sdl.SDL_BindGPUGraphicsPipeline(render_pass, self.rect_pipeline);
        sdl.SDL_DrawGPUPrimitives(render_pass, 6, 1, 0, 0); // 6 vertices for quad (2 triangles)
    }

    // Draw a visual effect with animated rings and pulsing
    pub fn drawEffect(self: *Self, cmd_buffer: *sdl.SDL_GPUCommandBuffer, render_pass: *sdl.SDL_GPURenderPass, pos: Vec2, radius: f32, color: Color, intensity: f32, time: f32) void {
        // Prepare uniform data for effect shader
        const uniform_data = EffectUniforms{
            .screen_size = [2]f32{ self.screen_width, self.screen_height },
            .center = [2]f32{ pos.x, pos.y },
            .radius = radius,
            .color_r = @as(f32, @floatFromInt(color.r)) / 255.0,
            .color_g = @as(f32, @floatFromInt(color.g)) / 255.0,
            .color_b = @as(f32, @floatFromInt(color.b)) / 255.0,
            .color_a = @as(f32, @floatFromInt(color.a)) / 255.0,
            .intensity = intensity,
            .time = time,
            ._padding = [3]f32{ 0.0, 0.0, 0.0 },
        };

        // Push uniform data BEFORE binding pipeline
        sdl.SDL_PushGPUVertexUniformData(cmd_buffer, 0, &uniform_data, @sizeOf(EffectUniforms));

        // Bind effect pipeline and draw with alpha blending
        sdl.SDL_BindGPUGraphicsPipeline(render_pass, self.effect_pipeline);
        sdl.SDL_DrawGPUPrimitives(render_pass, 6, 1, 0, 0); // 6 vertices for larger quad (effects need more space)
    }

    // End render pass
    pub fn endRenderPass(self: *Self, render_pass: *sdl.SDL_GPURenderPass) void {
        _ = self;
        sdl.SDL_EndGPURenderPass(render_pass);
    }

    // End frame and submit
    pub fn endFrame(self: *Self, cmd_buffer: *sdl.SDL_GPUCommandBuffer) void {
        _ = self;
        _ = sdl.SDL_SubmitGPUCommandBuffer(cmd_buffer);
    }

    // Transform world coordinates to screen coordinates (placeholder for now)
    pub fn worldToScreen(self: *Self, world_pos: Vec2) Vec2 {
        _ = self;
        return world_pos; // For now, assume world coordinates = screen coordinates
    }

    // Set render color (compatibility function - not needed for GPU but game expects it)
    pub fn setRenderColor(self: *Self, color: Color) void {
        _ = self;
        _ = color;
        // No-op for GPU rendering - color is passed per primitive
    }

    // Draw pixel (fallback for HUD text - draw as tiny rectangle)
    pub fn drawPixel(self: *Self, cmd_buffer: *sdl.SDL_GPUCommandBuffer, render_pass: *sdl.SDL_GPURenderPass, x: f32, y: f32, color: Color) void {
        self.drawRect(cmd_buffer, render_pass, Vec2{ .x = x, .y = y }, Vec2{ .x = 1.0, .y = 1.0 }, color);
    }
};
