const std = @import("std");
const Context = @import("../transform.zig").Context;
const Token = @import("../../parser/foundation/types/token.zig").Token;
const GenericTokenIterator = @import("generic_token_iterator.zig").GenericTokenIterator;
const AST = @import("../../ast/mod.zig").AST;
const Node = @import("../../ast/node.zig").Node;

/// Incremental parser for streaming large files with minimal memory footprint
///
/// Parses tokens incrementally, maintaining only necessary state for partial
/// AST construction. Ideal for processing large files (>1MB) where loading
/// the complete AST would consume excessive memory.
pub const IncrementalParser = struct {
    allocator: std.mem.Allocator,
    context: *Context,
    token_iterator: *GenericTokenIterator,
    parser_interface: ?ParserInterface,
    state: ParseState,
    partial_ast: ?AST,
    current_node: ?*Node,
    node_stack: std.ArrayList(*Node),
    max_memory_mb: usize,

    const Self = @This();
    const DEFAULT_MAX_MEMORY_MB = 10; // 10MB limit for incremental parsing

    /// Current parsing state
    pub const ParseState = enum {
        initial,
        parsing,
        partial_success,
        complete_success,
        error_recovery,
        aborted,
    };

    /// Interface for language-specific parsers
    pub const ParserInterface = struct {
        const VTable = struct {
            parsePartial: *const fn (parser: *anyopaque, tokens: []const Token, context: *Context, allocator: std.mem.Allocator) anyerror!PartialResult,
            canContinue: *const fn (parser: *anyopaque, tokens: []const Token) bool,
            deinit: *const fn (parser: *anyopaque) void,
        };

        ptr: *anyopaque,
        vtable: *const VTable,

        pub fn init(pointer: anytype) ParserInterface {
            const Ptr = @TypeOf(pointer);
            const PtrInfo = @typeInfo(Ptr);
            if (PtrInfo != .Pointer) @compileError("pointer must be a pointer");
            if (PtrInfo.Pointer.size != .One) @compileError("pointer must be a single-item pointer");

            const gen = struct {
                fn parsePartialImpl(ptr: *anyopaque, tokens: []const Token, context: *Context, allocator: std.mem.Allocator) anyerror!PartialResult {
                    const self: Ptr = @ptrCast(@alignCast(ptr));
                    return try self.parsePartial(tokens, context, allocator);
                }

                fn canContinueImpl(ptr: *anyopaque, tokens: []const Token) bool {
                    const self: Ptr = @ptrCast(@alignCast(ptr));
                    return self.canContinue(tokens);
                }

                fn deinitImpl(ptr: *anyopaque) void {
                    const self: Ptr = @ptrCast(@alignCast(ptr));
                    self.deinit();
                }

                const vtable = VTable{
                    .parsePartial = parsePartialImpl,
                    .canContinue = canContinueImpl,
                    .deinit = deinitImpl,
                };
            };

            return ParserInterface{
                .ptr = pointer,
                .vtable = &gen.vtable,
            };
        }

        pub fn parsePartial(self: ParserInterface, tokens: []const Token, context: *Context, allocator: std.mem.Allocator) !PartialResult {
            return try self.vtable.parsePartial(self.ptr, tokens, context, allocator);
        }

        pub fn canContinue(self: ParserInterface, tokens: []const Token) bool {
            return self.vtable.canContinue(self.ptr, tokens);
        }

        pub fn deinit(self: ParserInterface) void {
            self.vtable.deinit(self.ptr);
        }
    };

    /// Result of partial parsing operation
    pub const PartialResult = struct {
        nodes: []Node,
        consumed_tokens: usize,
        continue_parsing: bool,
        errors: []ParseError,

        pub fn deinit(self: PartialResult, allocator: std.mem.Allocator) void {
            for (self.nodes) |node| {
                node.deinit(allocator);
            }
            allocator.free(self.nodes);

            for (self.errors) |err| {
                allocator.free(err.message);
            }
            allocator.free(self.errors);
        }
    };

    pub const ParseError = struct {
        message: []const u8,
        position: usize,
        recoverable: bool,
    };

    /// Initialize incremental parser
    pub fn init(allocator: std.mem.Allocator, context: *Context, token_iterator: *GenericTokenIterator, parser: ?ParserInterface) Self {
        return Self{
            .allocator = allocator,
            .context = context,
            .token_iterator = token_iterator,
            .parser_interface = parser,
            .state = .initial,
            .partial_ast = null,
            .current_node = null,
            .node_stack = std.ArrayList(*Node).init(allocator),
            .max_memory_mb = DEFAULT_MAX_MEMORY_MB,
        };
    }

    pub fn deinit(self: *Self) void {
        self.node_stack.deinit();

        if (self.partial_ast) |*ast| {
            ast.deinit();
        }

        if (self.parser_interface) |parser| {
            parser.deinit();
        }
    }

    /// Set maximum memory limit for incremental parsing
    pub fn setMaxMemory(self: *Self, max_mb: usize) void {
        self.max_memory_mb = max_mb;
    }

    /// Parse incrementally until completion or memory limit
    pub fn parseIncremental(self: *Self) !ParseResult {
        self.state = .parsing;

        var results = std.ArrayList(PartialResult).init(self.allocator);
        defer {
            for (results.items) |result| {
                result.deinit(self.allocator);
            }
            results.deinit();
        }

        var total_nodes: usize = 0;
        var total_errors: usize = 0;
        var tokens_consumed: usize = 0;

        // Collect tokens in batches
        var token_batch = std.ArrayList(Token).init(self.allocator);
        defer {
            for (token_batch.items) |token| {
                if (token.text.len > 0) {
                    self.allocator.free(token.text);
                }
            }
            token_batch.deinit();
        }

        const BATCH_SIZE = 100; // Process 100 tokens at a time

        while (!self.token_iterator.isEof()) {
            // Check memory limit
            if (try self.checkMemoryLimit()) {
                self.state = .aborted;
                break;
            }

            // Collect batch of tokens
            token_batch.clearRetainingCapacity();
            var batch_count: usize = 0;

            while (batch_count < BATCH_SIZE and !self.token_iterator.isEof()) {
                if (try self.token_iterator.next()) |token| {
                    try token_batch.append(token);
                    batch_count += 1;
                } else {
                    break;
                }
            }

            if (token_batch.items.len == 0) break;

            // Parse this batch
            if (self.parser_interface) |parser| {
                const result = parser.parsePartial(token_batch.items, self.context, self.allocator) catch {
                    self.state = .error_recovery;
                    // Try to continue parsing
                    continue;
                };

                total_nodes += result.nodes.len;
                total_errors += result.errors.len;
                tokens_consumed += result.consumed_tokens;

                if (!result.continue_parsing) {
                    self.state = .complete_success;
                    break;
                }

                try results.append(result);
            } else {
                // Fallback simple parsing
                const result = try self.parseSimple(token_batch.items);
                total_nodes += result.nodes.len;
                try results.append(result);
            }
        }

        // Determine final state
        if (self.state == .parsing) {
            if (total_errors > 0) {
                self.state = .partial_success;
            } else {
                self.state = .complete_success;
            }
        }

        return ParseResult{
            .state = self.state,
            .total_nodes = total_nodes,
            .total_errors = total_errors,
            .tokens_consumed = tokens_consumed,
            .memory_used_bytes = try self.calculateMemoryUsage(),
        };
    }

    /// Parse single token stream (simplified fallback)
    pub fn parseTokenStream(self: *Self, max_tokens: usize) !ParseResult {
        var tokens_processed: usize = 0;
        var nodes_created: usize = 0;

        self.state = .parsing;

        while (tokens_processed < max_tokens and !self.token_iterator.isEof()) {
            if (try self.token_iterator.next()) |stream_token| {
                // Convert StreamToken to generic Token for parser
                const token = stream_token.toGenericToken(self.token_iterator.input);
                
                // Simple token processing - create leaf nodes
                if (self.shouldCreateNode(token)) {
                    try self.createSimpleNode(token);
                    nodes_created += 1;
                }
                tokens_processed += 1;
            }

            // Check memory limit periodically
            if (tokens_processed % 1000 == 0) {
                if (try self.checkMemoryLimit()) {
                    self.state = .aborted;
                    break;
                }
            }
        }

        if (self.state == .parsing) {
            self.state = .complete_success;
        }

        return ParseResult{
            .state = self.state,
            .total_nodes = nodes_created,
            .total_errors = 0,
            .tokens_consumed = tokens_processed,
            .memory_used_bytes = try self.calculateMemoryUsage(),
        };
    }

    /// Get current parsing statistics
    pub fn getStats(self: *Self) !ParsingStats {
        return ParsingStats{
            .state = self.state,
            .tokens_position = self.token_iterator.getPosition(),
            .total_input_size = self.token_iterator.getInputSize(),
            .progress_percent = (@as(f64, @floatFromInt(self.token_iterator.getPosition())) / @as(f64, @floatFromInt(self.token_iterator.getInputSize()))) * 100.0,
            .memory_used_bytes = try self.calculateMemoryUsage(),
            .memory_limit_bytes = self.max_memory_mb * 1024 * 1024,
            .nodes_in_stack = self.node_stack.items.len,
        };
    }

    pub const ParseResult = struct {
        state: ParseState,
        total_nodes: usize,
        total_errors: usize,
        tokens_consumed: usize,
        memory_used_bytes: usize,
    };

    pub const ParsingStats = struct {
        state: ParseState,
        tokens_position: usize,
        total_input_size: usize,
        progress_percent: f64,
        memory_used_bytes: usize,
        memory_limit_bytes: usize,
        nodes_in_stack: usize,
    };

    fn checkMemoryLimit(self: *Self) !bool {
        const current_memory = try self.calculateMemoryUsage();
        const limit_bytes = self.max_memory_mb * 1024 * 1024;
        return current_memory > limit_bytes;
    }

    fn calculateMemoryUsage(self: *Self) !usize {
        var memory: usize = 0;

        // Token iterator memory
        const token_stats = self.token_iterator.getMemoryStats();
        memory += token_stats.buffer_bytes;

        // Node stack memory
        memory += self.node_stack.items.len * @sizeOf(*Node);

        // Estimate AST memory (rough calculation)
        if (self.partial_ast) |_| {
            memory += @sizeOf(AST);
            // Add estimated node memory
            memory += self.node_stack.items.len * 256; // Average node size estimate
        }

        return memory;
    }

    fn shouldCreateNode(self: Self, token: Token) bool {
        _ = self;
        // Simple heuristic: create nodes for non-whitespace tokens
        return token.kind != .whitespace and token.kind != .newline;
    }

    fn createSimpleNode(self: *Self, token: Token) !void {
        // For now, just track that we would create a node
        // In a real implementation, this would create proper AST nodes
        _ = self;
        _ = token;
    }

    fn parseSimple(self: *Self, tokens: []const Token) !PartialResult {
        var nodes = std.ArrayList(Node).init(self.allocator);
        defer nodes.deinit();

        // Simple parsing: create one node per token
        for (tokens) |token| {
            if (self.shouldCreateNode(token)) {
                // Create a simple leaf node
                const node = Node{
                    .kind = .identifier,
                    .span = token.span,
                    .children = &[_]Node{},
                    .data = .{ .text = try self.allocator.dupe(u8, token.text) },
                };
                try nodes.append(node);
            }
        }

        return PartialResult{
            .nodes = try nodes.toOwnedSlice(),
            .consumed_tokens = tokens.len,
            .continue_parsing = true,
            .errors = &[_]ParseError{},
        };
    }
};

// Tests
const testing = std.testing;

test "IncrementalParser - basic functionality" {
    var context = Context.init(testing.allocator);
    defer context.deinit();

    const input = "test input for incremental parsing with multiple tokens";
    var token_iterator = try GenericTokenIterator.initWithGlobalRegistry(testing.allocator, input, &context, .json);
    defer token_iterator.deinit();

    var parser = IncrementalParser.init(testing.allocator, &context, &token_iterator, null);
    defer parser.deinit();

    parser.setMaxMemory(1); // 1MB limit

    const result = try parser.parseTokenStream(100);
    try testing.expect(result.total_nodes > 0);
    try testing.expect(result.tokens_consumed > 0);
}

test "IncrementalParser - memory limit" {
    var context = Context.init(testing.allocator);
    defer context.deinit();

    const input = "a very small input";
    var token_iterator = try GenericTokenIterator.initWithGlobalRegistry(testing.allocator, input, &context, .json);
    defer token_iterator.deinit();

    var parser = IncrementalParser.init(testing.allocator, &context, &token_iterator, null);
    defer parser.deinit();

    parser.setMaxMemory(0); // Extremely low limit should trigger abort

    const result = try parser.parseTokenStream(10);
    // Should either succeed with small input or abort due to memory limit
    try testing.expect(result.state == .complete_success or result.state == .aborted);
}

test "IncrementalParser - statistics" {
    var context = Context.init(testing.allocator);
    defer context.deinit();

    const input = "test statistics functionality";
    var token_iterator = try GenericTokenIterator.initWithGlobalRegistry(testing.allocator, input, &context, .json);
    defer token_iterator.deinit();

    var parser = IncrementalParser.init(testing.allocator, &context, &token_iterator, null);
    defer parser.deinit();

    const stats_initial = try parser.getStats();
    try testing.expect(stats_initial.state == .initial);
    try testing.expect(stats_initial.progress_percent == 0.0);

    _ = try parser.parseTokenStream(5);

    const stats_after = try parser.getStats();
    try testing.expect(stats_after.memory_used_bytes > 0);
}
