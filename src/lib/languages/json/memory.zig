const std = @import("std");
const Node = @import("../../ast/mod.zig").Node;

/// Memory management for JSON parsing
///
/// This module provides proper memory management for the JSON parser,
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

    /// List of node arrays that need to be transferred to AST
    transferred_nodes: std.ArrayList([]Node),

    const Self = @This();

    /// Initialize parse context
    pub fn init(allocator: std.mem.Allocator) ParseContext {
        return .{
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .transferred_texts = std.ArrayList([]const u8).init(allocator),
            .transferred_nodes = std.ArrayList([]Node).init(allocator),
        };
    }

    /// Deinitialize and free all memory
    pub fn deinit(self: *Self) void {
        // Arena automatically frees all temporary allocations
        self.arena.deinit();

        // Free the list of transferred texts (but not the texts themselves)
        self.transferred_texts.deinit();
        
        // Free the list of transferred nodes (but not the nodes themselves)
        self.transferred_nodes.deinit();
    }

    /// Get arena allocator for temporary allocations
    pub fn tempAllocator(self: *Self) std.mem.Allocator {
        return self.arena.allocator();
    }

    /// Track text that will be owned by the AST
    pub fn trackText(self: *Self, text: []const u8) ![]const u8 {
        // Text is already allocated by caller, just track it
        try self.transferred_texts.append(text);
        return text;
    }

    /// Track node array that will be owned by the AST
    pub fn trackNodes(self: *Self, nodes: []const Node) ![]Node {
        // Allocate permanent storage for the nodes
        const owned = try self.allocator.alloc(Node, nodes.len);
        @memcpy(owned, nodes);
        try self.transferred_nodes.append(owned);
        return owned;
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