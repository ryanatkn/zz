const std = @import("std");
const types = @import("types.zig");

/// Base transform interface following existing patterns from language modules
/// Similar to ILexer, IParser interfaces in the codebase

/// Generic bidirectional transform between types In and Out
pub fn Transform(comptime In: type, comptime Out: type) type {
    return struct {
        const Self = @This();
        
        // Core transform operations (like ILexer, IParser pattern)
        forward: *const fn (ctx: *Context, input: In) anyerror!Out,
        reverse: ?*const fn (ctx: *Context, output: Out) anyerror!In,
        
        // Optional async variants
        forward_async: ?*const fn (ctx: *Context, input: In) anyerror!Out,
        reverse_async: ?*const fn (ctx: *Context, output: Out) anyerror!In,
        
        // Metadata for introspection
        metadata: types.TransformMetadata,
        
        // Private data pointer for stateful transforms
        impl: ?*anyopaque = null,
        
        /// Execute forward transform
        pub fn runForward(self: Self, ctx: *Context, input: In) !Out {
            // Check for cancellation
            if (ctx.shouldCancel()) {
                return error.Cancelled;
            }
            
            // Use async variant if requested and available
            if (ctx.io_mode == .asynchronous and self.forward_async != null) {
                return self.forward_async.?(ctx, input);
            }
            
            return self.forward(ctx, input);
        }
        
        /// Execute reverse transform (if available)
        pub fn runReverse(self: Self, ctx: *Context, output: Out) !In {
            if (self.reverse == null) {
                return error.NotReversible;
            }
            
            if (ctx.shouldCancel()) {
                return error.Cancelled;
            }
            
            if (ctx.io_mode == .asynchronous and self.reverse_async != null) {
                return self.reverse_async.?(ctx, output);
            }
            
            return self.reverse.?(ctx, output);
        }
        
        /// Check if transform is reversible
        pub fn isReversible(self: Self) bool {
            return self.reverse != null;
        }
        
        /// Get estimated memory usage
        pub fn estimateMemory(self: Self, input_size: usize) usize {
            _ = input_size;
            return self.metadata.estimated_memory;
        }
    };
}

/// Transform context - carries state through transforms
/// Based on existing Context patterns in the codebase
pub const Context = struct {
    // Memory management (from memory/scoped.zig patterns)
    allocator: std.mem.Allocator,
    arena: ?*std.heap.ArenaAllocator = null,
    
    // IO configuration
    io_mode: types.IOMode = .synchronous,
    reader: ?std.io.AnyReader = null,
    writer: ?std.io.AnyWriter = null,
    
    // Options storage
    options: types.OptionsMap,
    
    // Error accumulation
    diagnostics: std.ArrayList(types.Diagnostic),
    error_limit: usize = 100,
    
    // Progress tracking (optional)
    progress: ?*types.Progress = null,
    cancel_token: ?*std.Thread.ResetEvent = null,
    
    // Performance monitoring
    start_time: ?i64 = null,
    memory_start: ?usize = null,
    
    const Self = @This();
    
    /// Create a new context
    pub fn init(allocator: std.mem.Allocator) Context {
        return .{
            .allocator = allocator,
            .options = types.OptionsMap.init(allocator),
            .diagnostics = std.ArrayList(types.Diagnostic).init(allocator),
        };
    }
    
    /// Create a context with arena for temporary allocations
    pub fn initWithArena(backing_allocator: std.mem.Allocator) !Context {
        var arena = try backing_allocator.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(backing_allocator);
        
        return .{
            .allocator = arena.allocator(),
            .arena = arena,
            .options = types.OptionsMap.init(arena.allocator()),
            .diagnostics = std.ArrayList(types.Diagnostic).init(arena.allocator()),
        };
    }
    
    /// Create a child context with its own arena
    /// Based on pattern from memory/scoped.zig
    pub fn createChild(self: *Context) !Context {
        var child_arena = try self.allocator.create(std.heap.ArenaAllocator);
        child_arena.* = std.heap.ArenaAllocator.init(self.allocator);
        
        return .{
            .allocator = child_arena.allocator(),
            .arena = child_arena,
            .io_mode = self.io_mode,
            .reader = self.reader,
            .writer = self.writer,
            .options = types.OptionsMap.init(child_arena.allocator()),
            .diagnostics = std.ArrayList(types.Diagnostic).init(child_arena.allocator()),
            .error_limit = self.error_limit,
            .progress = self.progress,
            .cancel_token = self.cancel_token,
            .start_time = self.start_time,
            .memory_start = self.memory_start,
        };
    }
    
    pub fn deinit(self: *Context) void {
        self.diagnostics.deinit();
        self.options.deinit();
        
        if (self.arena) |arena| {
            const backing = arena.child_allocator;
            arena.deinit();
            backing.destroy(arena);
        }
    }
    
    /// Add a diagnostic message
    pub fn addDiagnostic(self: *Context, diag: types.Diagnostic) !void {
        if (self.diagnostics.items.len >= self.error_limit) {
            return error.TooManyErrors;
        }
        try self.diagnostics.append(diag);
    }
    
    /// Add an error diagnostic
    pub fn addError(self: *Context, message: []const u8, span: ?types.Span) !void {
        try self.addDiagnostic(try types.Diagnostic.err(self.allocator, message, span));
    }
    
    /// Add a warning diagnostic
    pub fn addWarning(self: *Context, message: []const u8, span: ?types.Span) !void {
        try self.addDiagnostic(try types.Diagnostic.warn(self.allocator, message, span));
    }
    
    /// Check if operation should be cancelled
    pub fn shouldCancel(self: *Context) bool {
        if (self.cancel_token) |token| {
            return token.isSet();
        }
        return false;
    }
    
    /// Start performance timing
    pub fn startTiming(self: *Context) void {
        self.start_time = std.time.milliTimestamp();
        // Could also track memory here
    }
    
    /// Get elapsed time in milliseconds
    pub fn getElapsedMs(self: Context) ?i64 {
        if (self.start_time) |start| {
            return std.time.milliTimestamp() - start;
        }
        return null;
    }
    
    /// Set an option
    pub fn setOption(self: *Context, key: []const u8, value: anytype) !void {
        const T = @TypeOf(value);
        if (T == bool) {
            try self.options.setBool(key, value);
        } else if (T == i64 or T == i32 or T == i16 or T == i8) {
            try self.options.setInt(key, @as(i64, value));
        } else if (T == []const u8) {
            try self.options.setString(key, value);
        } else {
            @compileError("Unsupported option type");
        }
    }
    
    /// Get an option
    pub fn getOption(self: Context, key: []const u8, comptime T: type) ?T {
        if (T == bool) {
            return self.options.getBool(key);
        } else if (T == i64) {
            return self.options.getInt(key);
        } else if (T == []const u8) {
            return self.options.getString(key);
        } else {
            @compileError("Unsupported option type");
        }
    }
};

/// Helper to create a simple transform from functions
pub fn createTransform(
    comptime In: type,
    comptime Out: type,
    forward_fn: *const fn (*Context, In) anyerror!Out,
    reverse_fn: ?*const fn (*Context, Out) anyerror!In,
    metadata: types.TransformMetadata,
) Transform(In, Out) {
    return .{
        .forward = forward_fn,
        .reverse = reverse_fn,
        .forward_async = null,
        .reverse_async = null,
        .metadata = metadata,
    };
}

/// Identity transform (passthrough)
pub fn identity(comptime T: type) Transform(T, T) {
    const forward_fn = struct {
        fn forward(ctx: *Context, input: T) anyerror!T {
            _ = ctx;
            return input;
        }
    }.forward;
    
    return createTransform(T, T, forward_fn, forward_fn, .{
        .name = "identity",
        .description = "Passthrough transform",
        .reversible = true,
        .streaming_capable = true,
        .performance_class = .fast,
    });
}

// Tests
const testing = std.testing;

test "Context creation and cleanup" {
    const allocator = testing.allocator;
    
    // Basic context
    {
        var ctx = Context.init(allocator);
        defer ctx.deinit();
        
        try ctx.setOption("test", true);
        try testing.expectEqual(@as(?bool, true), ctx.getOption("test", bool));
    }
    
    // Context with arena
    {
        var ctx = try Context.initWithArena(allocator);
        defer ctx.deinit();
        
        try ctx.addError("test error", null);
        try testing.expectEqual(@as(usize, 1), ctx.diagnostics.items.len);
    }
    
    // Child context
    {
        var parent = Context.init(allocator);
        defer parent.deinit();
        
        var child = try parent.createChild();
        defer child.deinit();
        
        try child.setOption("child_option", @as(i64, 42));
        try testing.expectEqual(@as(?i64, 42), child.getOption("child_option", i64));
    }
}

test "Simple transform" {
    const allocator = testing.allocator;
    
    // Define a simple string to uppercase transform
    const upper_forward = struct {
        fn forward(ctx: *Context, input: []const u8) ![]const u8 {
            var result = try ctx.allocator.alloc(u8, input.len);
            for (input, 0..) |c, i| {
                result[i] = std.ascii.toUpper(c);
            }
            return result;
        }
    }.forward;
    
    const upper_reverse = struct {
        fn reverse(ctx: *Context, output: []const u8) ![]const u8 {
            var result = try ctx.allocator.alloc(u8, output.len);
            for (output, 0..) |c, i| {
                result[i] = std.ascii.toLower(c);
            }
            return result;
        }
    }.reverse;
    
    const transform = createTransform(
        []const u8,
        []const u8,
        upper_forward,
        upper_reverse,
        .{
            .name = "uppercase",
            .description = "Convert to uppercase",
            .reversible = true,
        },
    );
    
    var ctx = Context.init(allocator);
    defer ctx.deinit();
    
    const input = "hello";
    const output = try transform.runForward(&ctx, input);
    defer allocator.free(output);
    
    try testing.expectEqualStrings("HELLO", output);
    try testing.expect(transform.isReversible());
    
    const reversed = try transform.runReverse(&ctx, output);
    defer allocator.free(reversed);
    
    try testing.expectEqualStrings("hello", reversed);
}

test "Identity transform" {
    const allocator = testing.allocator;
    
    const transform = identity(i32);
    
    var ctx = Context.init(allocator);
    defer ctx.deinit();
    
    const result = try transform.runForward(&ctx, 42);
    try testing.expectEqual(@as(i32, 42), result);
    try testing.expect(transform.isReversible());
}

test "Context timing" {
    const allocator = testing.allocator;
    
    var ctx = Context.init(allocator);
    defer ctx.deinit();
    
    ctx.startTiming();
    std.time.sleep(10 * std.time.ns_per_ms); // Sleep 10ms
    
    const elapsed = ctx.getElapsedMs();
    try testing.expect(elapsed != null);
    try testing.expect(elapsed.? >= 10);
}