const std = @import("std");

/// Memory management for ZON parsing
///
/// This module provides proper memory management for the ZON parser,
/// ensuring all allocations are tracked and properly freed.
/// Uses arena allocator pattern for temporary parse-time allocations.
/// Context for managing parse-time allocations
pub const ParseContext = struct {
    /// Main allocator for final results
    allocator: std.mem.Allocator,

    /// Arena for temporary parse-time allocations
    arena: std.heap.ArenaAllocator,

    /// List of texts that need to be transferred to AST
    transferred_texts: std.ArrayList([]const u8),

    const Self = @This();

    /// Initialize parse context
    pub fn init(allocator: std.mem.Allocator) ParseContext {
        return .{
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .transferred_texts = std.ArrayList([]const u8).init(allocator),
        };
    }

    /// Deinitialize and free all memory
    pub fn deinit(self: *Self) void {
        // Arena automatically frees all temporary allocations
        self.arena.deinit();

        // Free the list of transferred texts (but not the texts themselves)
        self.transferred_texts.deinit();
    }

    /// Get arena allocator for temporary allocations
    pub fn tempAllocator(self: *Self) std.mem.Allocator {
        return self.arena.allocator();
    }

    /// Allocate text that will be owned by the AST
    /// This text will survive beyond the parse context
    pub fn allocateAstText(self: *Self, text: []const u8) ![]const u8 {
        const owned = try self.allocator.dupe(u8, text);
        try self.transferred_texts.append(owned);
        return owned;
    }

    /// Create formatted text that will be owned by the AST
    pub fn allocatePrintAstText(self: *Self, comptime fmt: []const u8, args: anytype) ![]const u8 {
        const text = try std.fmt.allocPrint(self.allocator, fmt, args);
        try self.transferred_texts.append(text);
        return text;
    }

    /// Transfer ownership of all AST texts to caller
    /// After this, the caller is responsible for freeing the texts
    pub fn transferOwnership(self: *Self) []const []const u8 {
        const texts = self.transferred_texts.toOwnedSlice() catch &[_][]const u8{};
        return texts;
    }

    /// Free transferred texts (utility for cleanup)
    pub fn freeTransferredTexts(allocator: std.mem.Allocator, texts: []const []const u8) void {
        for (texts) |text| {
            allocator.free(text);
        }
        allocator.free(texts);
    }
};

/// AST memory tracker
/// Tracks allocations that are owned by the AST
pub const AstMemory = struct {
    allocator: std.mem.Allocator,
    owned_texts: []const []const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, owned_texts: []const []const u8) AstMemory {
        return .{
            .allocator = allocator,
            .owned_texts = owned_texts,
        };
    }

    pub fn deinit(self: *Self) void {
        ParseContext.freeTransferredTexts(self.allocator, self.owned_texts);
    }
};

/// Arena-based string builder for efficient concatenation
pub const StringBuilder = struct {
    arena: *std.heap.ArenaAllocator,
    buffer: std.ArrayList(u8),

    const Self = @This();

    pub fn init(arena: *std.heap.ArenaAllocator) StringBuilder {
        return .{
            .arena = arena,
            .buffer = std.ArrayList(u8).init(arena.allocator()),
        };
    }

    pub fn append(self: *Self, text: []const u8) !void {
        try self.buffer.appendSlice(text);
    }

    pub fn appendChar(self: *Self, char: u8) !void {
        try self.buffer.append(char);
    }

    pub fn toOwnedSlice(self: *Self) ![]const u8 {
        return self.buffer.toOwnedSlice();
    }
};
