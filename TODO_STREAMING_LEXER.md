# TODO_STREAMING_LEXER.md - Ultimate Language Tooling Architecture

## Phase 1 Status: ✅ COMPLETED (August 2025)
- **Stateful lexer infrastructure**: Complete with all language contexts
- **JSON reference implementation**: 100% working with chunk boundaries
- **Streaming adapters**: JSON and ZON integrated
- **Performance validated**: 61KB for 100KB input, <1ms for 10KB
- See [TODO_STREAMING_LEXER_PHASE_1.md](TODO_STREAMING_LEXER_PHASE_1.md) for details

## Phase 2 Status: ✅ COMPLETED (August 2025)
- **Language-specific token types**: JsonToken and ZonToken with rich semantic info
- **Token conversion pipeline**: Type-safe conversion to generic tokens
- **JSON stateful lexer**: Emits JsonToken with full metadata
- **Unified token iterator**: Supports multiple language lexers
- See [TODO_STREAMING_LEXER_PHASE_2.md](TODO_STREAMING_LEXER_PHASE_2.md) for details

## Executive Summary

Complete architectural overhaul to support **language-specific tokens**, **generic AST**, and **pluggable analysis** while maintaining **100% streaming correctness** and **maximum performance**.

## Core Architecture Principles

1. **Language-Specific Tokens**: Rich, type-safe token types per language
2. **Generic AST Core**: Universal AST structure for all languages
3. **Stateful Streaming**: Zero data loss on chunk boundaries
4. **Pluggable Analysis**: Extensible semantic analysis framework
5. **Zero-Copy Design**: Minimize allocations, maximize performance

## Architecture Overview

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐     ┌──────────┐     ┌────────────┐
│    Text     │────▶│   Stateful   │────▶│  Language   │────▶│ Language │────▶│  Generic   │
│   Stream    │     │    Lexer     │     │   Tokens    │     │  Parser  │     │    AST     │
└─────────────┘     └──────────────┘     └─────────────┘     └──────────┘     └────────────┘
                     (chunk-aware)        (type-safe)         (type-safe)       (universal)
                                                                                      │
                                                                                      ▼
                                    ┌──────────────────────────────────────────────────┐
                                    │              Semantic Analysis Engine             │
                                    │  ┌──────────┐  ┌──────────┐  ┌──────────────┐  │
                                    │  │   Type   │  │   Lint   │  │    Symbol    │  │
                                    │  │ Checker  │  │  Engine  │  │  Resolution  │  │
                                    │  └──────────┘  └──────────┘  └──────────────┘  │
                                    └──────────────────────────────────────────────────┘
```

## Detailed Component Design

### 1. Language-Specific Token System

Each language defines its own rich token types with maximum semantic information:

```zig
// src/lib/languages/json/token.zig
pub const JsonToken = union(enum) {
    // Structural tokens with precise semantics
    object_start: TokenData,
    object_end: TokenData,
    array_start: TokenData,
    array_end: TokenData,
    comma: TokenData,
    colon: TokenData,
    
    // Value tokens with parsed data
    string: struct {
        data: TokenData,
        value: []const u8,      // Unescaped string content
        raw: []const u8,        // Original with quotes
        has_escapes: bool,
    },
    
    number: struct {
        data: TokenData,
        int_value: ?i64,        // If representable as int
        float_value: ?f64,      // If representable as float
        raw: []const u8,        // Original text
        is_scientific: bool,
    },
    
    boolean: struct {
        data: TokenData,
        value: bool,
    },
    
    null: TokenData,
    
    // JSON5 extensions
    comment: struct {
        data: TokenData,
        text: []const u8,
        kind: enum { line, block },
    },
    
    // Error recovery
    invalid: struct {
        data: TokenData,
        expected: []const u8,
        actual: []const u8,
    },
    
    // Common token data
    pub const TokenData = struct {
        span: Span,
        line: u32,
        column: u32,
        depth: u16,             // Nesting depth
        flags: TokenFlags,
    };
    
    pub fn span(self: JsonToken) Span {
        return switch (self) {
            inline else => |data| data.data.span,
        };
    }
};

// Similar for other languages
pub const TypeScriptToken = union(enum) {
    // TypeScript-specific rich tokens
    interface_keyword: TokenData,
    type_keyword: TokenData,
    generic_start: TokenData,  // <
    generic_end: TokenData,    // >
    arrow_function: TokenData, // =>
    optional_chain: TokenData, // ?.
    nullish_coalesce: TokenData, // ??
    // ... hundreds more
};
```

### 2. Stateful Streaming Lexer

Complete state machine for perfect chunk boundary handling:

```zig
// src/lib/transform/streaming/stateful_lexer.zig
pub const StatefulLexer = struct {
    /// Generic lexer state
    pub const State = struct {
        // Current parsing context with full state
        context: union(enum) {
            normal: void,
            
            in_string: struct {
                quote_char: u8,         // ' or "
                start_pos: usize,
                escape_state: enum {
                    none,
                    backslash,
                    unicode,
                    hex,
                },
                unicode_buffer: [6]u8,  // \uXXXX or \u{XXXXXX}
                unicode_count: u3,
                accumulated: std.ArrayList(u8),
            },
            
            in_number: struct {
                start_pos: usize,
                buffer: [128]u8,       // Stack buffer for number
                len: u7,
                state: packed struct {
                    has_sign: bool,
                    has_decimal: bool,
                    has_exponent: bool,
                    has_exponent_sign: bool,
                    in_fraction: bool,
                    in_exponent: bool,
                    _padding: u2,
                },
            },
            
            in_template: struct {
                start_pos: usize,
                depth: u16,             // ${} nesting
                accumulated: std.ArrayList(u8),
            },
            
            in_regex: struct {
                start_pos: usize,
                in_charset: bool,
                escaped: bool,
                accumulated: std.ArrayList(u8),
            },
            
            in_comment: struct {
                kind: enum { line, block, doc },
                start_pos: usize,
                nesting_depth: u8,      // For nested /* */
                accumulated: ?std.ArrayList(u8), // Only if preserving
            },
        } = .normal,
        
        // Global position tracking
        byte_offset: usize = 0,
        line: u32 = 1,
        column: u32 = 1,
        last_newline_offset: usize = 0,
        
        // Bracket depth tracking
        bracket_depth: u16 = 0,
        brace_depth: u16 = 0,
        paren_depth: u16 = 0,
        
        // Configuration
        flags: packed struct {
            allow_comments: bool = false,
            allow_trailing_commas: bool = false,
            preserve_comments: bool = false,
            track_locations: bool = true,
            error_recovery: bool = true,
            _padding: u3 = 0,
        } = .{},
    };
    
    /// Interface for language implementations
    pub const Interface = struct {
        ptr: *anyopaque,
        vtable: *const VTable,
        
        pub const VTable = struct {
            processChunk: *const fn (ptr: *anyopaque, chunk: []const u8) anyerror!TokenBuffer,
            getState: *const fn (ptr: *anyopaque) *State,
            reset: *const fn (ptr: *anyopaque) void,
            deinit: *const fn (ptr: *anyopaque) void,
        };
        
        pub const TokenBuffer = struct {
            ptr: *anyopaque,        // Points to []LanguageToken
            len: usize,
            token_type: std.builtin.Type,
            allocator: std.mem.Allocator,
            
            pub fn deinit(self: TokenBuffer) void {
                // Type-erased deallocation
                self.allocator.free(self.ptr);
            }
        };
    };
};

// src/lib/languages/json/stateful_lexer.zig
pub const StatefulJsonLexer = struct {
    allocator: std.mem.Allocator,
    state: StatefulLexer.State,
    
    // Lookup tables for performance
    const DELIMITER_TABLE: [256]?JsonDelimiter = comptime blk: {
        var table = [_]?JsonDelimiter{null} ** 256;
        table['{'] = .object_start;
        table['}'] = .object_end;
        table['['] = .array_start;
        table[']'] = .array_end;
        table[','] = .comma;
        table[':'] = .colon;
        break :blk table;
    };
    
    pub fn processChunk(self: *Self, chunk: []const u8) ![]JsonToken {
        var tokens = try std.ArrayList(JsonToken).initCapacity(
            self.allocator,
            chunk.len / 4  // Heuristic
        );
        
        var pos: usize = 0;
        
        // Step 1: Resume partial token from previous chunk
        if (self.state.context != .normal) {
            pos = try self.resumePartialToken(chunk, &tokens);
        }
        
        // Step 2: Main tokenization loop
        while (pos < chunk.len) {
            // Skip whitespace fast path
            const ws_start = pos;
            while (pos < chunk.len and isWhitespace(chunk[pos])) {
                if (chunk[pos] == '\n') {
                    self.state.line += 1;
                    self.state.column = 1;
                    self.state.last_newline_offset = self.state.byte_offset + pos;
                } else {
                    self.state.column += 1;
                }
                pos += 1;
            }
            
            if (pos >= chunk.len) break;
            
            // Fast delimiter check
            if (DELIMITER_TABLE[chunk[pos]]) |delim| {
                try tokens.append(self.createDelimiterToken(delim, pos));
                pos += 1;
                continue;
            }
            
            // Check for incomplete token at chunk boundary
            const remaining = chunk.len - pos;
            if (remaining < 8 and self.mightBeIncomplete(chunk[pos..])) {
                self.savePartialState(chunk[pos..]);
                break;
            }
            
            // Parse complete token
            const result = try self.parseToken(chunk[pos..]);
            if (result.token) |token| {
                try tokens.append(token);
            }
            pos += result.consumed;
        }
        
        self.state.byte_offset += pos;
        return tokens.toOwnedSlice();
    }
    
    fn resumePartialToken(self: *Self, chunk: []const u8, tokens: *std.ArrayList(JsonToken)) !usize {
        switch (self.state.context) {
            .in_string => |*string_state| {
                // Complex string resumption with escape handling
                var pos: usize = 0;
                
                while (pos < chunk.len) {
                    const ch = chunk[pos];
                    
                    switch (string_state.escape_state) {
                        .none => {
                            if (ch == '\\') {
                                string_state.escape_state = .backslash;
                            } else if (ch == string_state.quote_char) {
                                // String complete
                                const value = try string_state.accumulated.toOwnedSlice();
                                try tokens.append(.{
                                    .string = .{
                                        .data = .{
                                            .span = Span.init(string_state.start_pos, self.state.byte_offset + pos + 1),
                                            .line = self.state.line,
                                            .column = self.state.column,
                                            .depth = self.state.brace_depth,
                                            .flags = .{},
                                        },
                                        .value = value,
                                        .raw = chunk[0..pos + 1],
                                        .has_escapes = true,
                                    },
                                });
                                self.state.context = .normal;
                                return pos + 1;
                            } else {
                                try string_state.accumulated.append(ch);
                            }
                        },
                        .backslash => {
                            const unescaped = switch (ch) {
                                'n' => '\n',
                                'r' => '\r',
                                't' => '\t',
                                'b' => '\x08',
                                'f' => '\x0C',
                                '"' => '"',
                                '\'' => '\'',
                                '\\' => '\\',
                                '/' => '/',
                                'u' => {
                                    string_state.escape_state = .unicode;
                                    string_state.unicode_count = 0;
                                    pos += 1;
                                    continue;
                                },
                                else => ch,  // Invalid escape, keep as-is
                            };
                            try string_state.accumulated.append(unescaped);
                            string_state.escape_state = .none;
                        },
                        .unicode => {
                            string_state.unicode_buffer[string_state.unicode_count] = ch;
                            string_state.unicode_count += 1;
                            
                            if (string_state.unicode_count == 4) {
                                // Parse Unicode escape
                                const hex_str = string_state.unicode_buffer[0..4];
                                if (std.fmt.parseInt(u16, hex_str, 16)) |codepoint| {
                                    var utf8_buf: [4]u8 = undefined;
                                    const len = std.unicode.utf8Encode(codepoint, &utf8_buf) catch 1;
                                    try string_state.accumulated.appendSlice(utf8_buf[0..len]);
                                }
                                string_state.escape_state = .none;
                            }
                        },
                        .hex => unreachable,  // JSON doesn't have \x escapes
                    }
                    
                    pos += 1;
                }
                
                // Still in string, continue accumulating
                return chunk.len;
            },
            
            .in_number => |*number_state| {
                // Resume number parsing
                var pos: usize = 0;
                
                while (pos < chunk.len and isNumberChar(chunk[pos])) {
                    if (number_state.len >= number_state.buffer.len) {
                        return error.NumberTooLarge;
                    }
                    number_state.buffer[number_state.len] = chunk[pos];
                    number_state.len += 1;
                    pos += 1;
                }
                
                // Number complete
                const number_text = number_state.buffer[0..number_state.len];
                const token = try self.parseNumber(number_text, number_state.start_pos);
                try tokens.append(token);
                self.state.context = .normal;
                return pos;
            },
            
            .in_comment => |*comment_state| {
                // Handle comment resumption
                switch (comment_state.kind) {
                    .line => {
                        if (std.mem.indexOfScalar(u8, chunk, '\n')) |newline_pos| {
                            if (self.state.flags.preserve_comments and comment_state.accumulated != null) {
                                // Save comment token
                            }
                            self.state.context = .normal;
                            return newline_pos + 1;
                        }
                        return chunk.len;
                    },
                    .block => {
                        if (std.mem.indexOf(u8, chunk, "*/")) |end_pos| {
                            self.state.context = .normal;
                            return end_pos + 2;
                        }
                        return chunk.len;
                    },
                    .doc => unreachable,  // JSON doesn't have doc comments
                }
            },
            
            else => return 0,
        }
    }
};
```

### 3. Language Parser with Generic AST Output

Each language parser converts its rich tokens to generic AST:

```zig
// src/lib/languages/json/parser.zig
pub const JsonParser = struct {
    allocator: std.mem.Allocator,
    tokens: []const JsonToken,
    current: usize,
    errors: std.ArrayList(ParseError),
    
    pub fn parse(allocator: std.mem.Allocator, tokens: []const JsonToken) !AST {
        var parser = JsonParser{
            .allocator = allocator,
            .tokens = tokens,
            .current = 0,
            .errors = std.ArrayList(ParseError).init(allocator),
        };
        defer parser.errors.deinit();
        
        const root = try parser.parseValue();
        
        if (parser.current < parser.tokens.len) {
            try parser.addError("Unexpected tokens after value", parser.tokens[parser.current].span());
        }
        
        return AST{
            .root = root,
            .allocator = allocator,
            .source = "", // Set by caller if needed
            .owned_texts = &.{},
        };
    }
    
    fn parseValue(self: *Self) !Node {
        const token = self.peek() orelse return error.UnexpectedEndOfInput;
        
        return switch (token) {
            .object_start => try self.parseObject(),
            .array_start => try self.parseArray(),
            .string => |s| blk: {
                _ = self.advance();
                break :blk Node{
                    .rule_id = @intFromEnum(CommonRules.string),
                    .node_type = .literal,
                    .text = s.value,
                    .start_position = s.data.span.start,
                    .end_position = s.data.span.end,
                    .children = &.{},
                    .attributes = null,
                    .parent = null,
                };
            },
            .number => |n| blk: {
                _ = self.advance();
                break :blk Node{
                    .rule_id = @intFromEnum(CommonRules.number),
                    .node_type = .literal,
                    .text = n.raw,
                    .start_position = n.data.span.start,
                    .end_position = n.data.span.end,
                    .children = &.{},
                    .attributes = null,
                    .parent = null,
                };
            },
            .boolean => |b| blk: {
                _ = self.advance();
                break :blk Node{
                    .rule_id = @intFromEnum(CommonRules.boolean),
                    .node_type = .literal,
                    .text = if (b.value) "true" else "false",
                    .start_position = b.data.span.start,
                    .end_position = b.data.span.end,
                    .children = &.{},
                    .attributes = null,
                    .parent = null,
                };
            },
            .null => |data| blk: {
                _ = self.advance();
                break :blk Node{
                    .rule_id = @intFromEnum(CommonRules.null),
                    .node_type = .literal,
                    .text = "null",
                    .start_position = data.span.start,
                    .end_position = data.span.end,
                    .children = &.{},
                    .attributes = null,
                    .parent = null,
                };
            },
            else => return error.UnexpectedToken,
        };
    }
    
    fn parseObject(self: *Self) !Node {
        const start = self.advance().?.object_start;
        var members = std.ArrayList(Node).init(self.allocator);
        errdefer members.deinit();
        
        // Handle empty object
        if (self.peek()) |next| {
            if (next == .object_end) {
                const end = self.advance().?.object_end;
                return Node{
                    .rule_id = @intFromEnum(CommonRules.object),
                    .node_type = .container,
                    .text = "",
                    .start_position = start.data.span.start,
                    .end_position = end.data.span.end,
                    .children = &.{},
                    .attributes = null,
                    .parent = null,
                };
            }
        }
        
        // Parse members
        while (true) {
            // Parse key
            const key_token = self.peek() orelse return error.UnexpectedEndOfInput;
            if (key_token != .string) return error.ExpectedStringKey;
            const key = self.advance().?.string;
            
            // Parse colon
            const colon = self.peek() orelse return error.UnexpectedEndOfInput;
            if (colon != .colon) return error.ExpectedColon;
            _ = self.advance();
            
            // Parse value
            const value = try self.parseValue();
            
            // Create member node
            const member = Node{
                .rule_id = @intFromEnum(CommonRules.member),
                .node_type = .pair,
                .text = key.value,
                .start_position = key.data.span.start,
                .end_position = value.end_position,
                .children = try self.allocator.dupe(Node, &[_]Node{value}),
                .attributes = null,
                .parent = null,
            };
            try members.append(member);
            
            // Check for continuation
            const next = self.peek() orelse return error.UnexpectedEndOfInput;
            switch (next) {
                .comma => {
                    _ = self.advance();
                    // Check for trailing comma
                    if (self.peek()) |after_comma| {
                        if (after_comma == .object_end) {
                            break;
                        }
                    }
                },
                .object_end => break,
                else => return error.ExpectedCommaOrBrace,
            }
        }
        
        const end = self.advance().?.object_end;
        
        return Node{
            .rule_id = @intFromEnum(CommonRules.object),
            .node_type = .container,
            .text = "",
            .start_position = start.data.span.start,
            .end_position = end.data.span.end,
            .children = try members.toOwnedSlice(),
            .attributes = null,
            .parent = null,
        };
    }
    
    fn parseArray(self: *Self) !Node {
        // Similar structure for array parsing
        // ... implementation
    }
};
```

### 4. Generic AST Structure (Language-Agnostic)

```zig
// src/lib/ast/node.zig - NO language-specific details!
pub const Node = struct {
    /// Universal rule identifier
    rule_id: u16,
    
    /// Generic node classification
    node_type: NodeType,
    
    /// Source text this node represents
    text: []const u8,
    
    /// Position in source
    start_position: usize,
    end_position: usize,
    
    /// Tree structure
    children: []Node,
    attributes: ?*NodeAttributes,
    parent: ?*Node,
    
    /// Semantic annotations (populated by analysis)
    semantic: ?*SemanticInfo = null,
};

pub const NodeType = enum {
    // Structural
    root,
    container,
    list,
    pair,
    
    // Values
    literal,
    identifier,
    operator,
    
    // Special
    comment,
    error,
    missing,
};

pub const SemanticInfo = struct {
    /// Type information
    type_id: ?TypeId = null,
    type_name: ?[]const u8 = null,
    
    /// Symbol information
    symbol_id: ?SymbolId = null,
    symbol_kind: ?SymbolKind = null,
    
    /// Scope information
    scope_id: ?ScopeId = null,
    scope_kind: ?ScopeKind = null,
    
    /// Data flow
    definitions: []NodeId = &.{},
    references: []NodeId = &.{},
    
    /// Diagnostics
    diagnostics: []Diagnostic = &.{},
};

// src/lib/ast/rules.zig
pub const CommonRules = enum(u16) {
    // Universal rules (0-999)
    root = 0,
    object = 1,
    array = 2,
    member = 3,
    element = 4,
    string = 5,
    number = 6,
    boolean = 7,
    null = 8,
    identifier = 9,
    
    // Reserve ranges for extensions
    json_specific_start = 1000,
    typescript_specific_start = 2000,
    zig_specific_start = 3000,
    // ...
};
```

### 5. Semantic Analysis Framework

```zig
// src/lib/analysis/engine.zig
pub const AnalysisEngine = struct {
    allocator: std.mem.Allocator,
    passes: std.ArrayList(AnalysisPass),
    context: AnalysisContext,
    
    pub const AnalysisPass = struct {
        name: []const u8,
        priority: u32,
        requires: []const []const u8,
        provides: []const []const u8,
        
        vtable: *const struct {
            init: *const fn(ctx: *AnalysisContext) anyerror!*anyopaque,
            analyze: *const fn(self: *anyopaque, ast: *AST, ctx: *AnalysisContext) anyerror!void,
            deinit: *const fn(self: *anyopaque) void,
        },
    };
    
    pub fn init(allocator: std.mem.Allocator) AnalysisEngine {
        return .{
            .allocator = allocator,
            .passes = std.ArrayList(AnalysisPass).init(allocator),
            .context = AnalysisContext.init(allocator),
        };
    }
    
    pub fn registerPass(self: *Self, pass: AnalysisPass) !void {
        try self.passes.append(pass);
        try self.sortPasses();  // Topological sort by dependencies
    }
    
    pub fn analyze(self: *Self, ast: *AST) !AnalysisResult {
        // Initialize all passes
        var pass_instances = std.ArrayList(*anyopaque).init(self.allocator);
        defer pass_instances.deinit();
        
        for (self.passes.items) |pass| {
            const instance = try pass.vtable.init(&self.context);
            try pass_instances.append(instance);
        }
        
        // Run passes in dependency order
        for (self.passes.items, pass_instances.items) |pass, instance| {
            try pass.vtable.analyze(instance, ast, &self.context);
        }
        
        // Clean up
        for (self.passes.items, pass_instances.items) |pass, instance| {
            pass.vtable.deinit(instance);
        }
        
        return self.context.getResult();
    }
};

// src/lib/analysis/type_checker.zig
pub const TypeChecker = struct {
    allocator: std.mem.Allocator,
    type_registry: TypeRegistry,
    inference_engine: InferenceEngine,
    
    pub fn createPass() AnalysisPass {
        return .{
            .name = "type_checker",
            .priority = 100,
            .requires = &.{"symbol_resolver"},
            .provides = &.{"types"},
            .vtable = &.{
                .init = init,
                .analyze = analyze,
                .deinit = deinit,
            },
        };
    }
    
    fn analyze(self: *anyopaque, ast: *AST, ctx: *AnalysisContext) !void {
        const checker = @ptrCast(*TypeChecker, @alignCast(self));
        
        // Walk AST and infer types
        var walker = ast.walker();
        while (walker.next()) |node| {
            const type_info = try checker.inferType(node);
            node.semantic = try ctx.getOrCreateSemantic(node);
            node.semantic.type_id = type_info.id;
            node.semantic.type_name = type_info.name;
        }
    }
};

// src/lib/analysis/linter.zig
pub const Linter = struct {
    rules: []const LintRule,
    config: LintConfig,
    
    pub const LintRule = struct {
        id: []const u8,
        severity: Severity,
        check: *const fn(node: *Node, ctx: *AnalysisContext) ?Diagnostic,
    };
    
    pub fn createPass(rules: []const LintRule) AnalysisPass {
        return .{
            .name = "linter",
            .priority = 200,
            .requires = &.{},
            .provides = &.{"diagnostics"},
            .vtable = &.{
                .init = init,
                .analyze = analyze,
                .deinit = deinit,
            },
        };
    }
};
```

### 6. Performance Optimizations

```zig
// src/lib/optimization/simd.zig
pub const SimdScanner = struct {
    /// SIMD-accelerated delimiter scanning
    pub fn findDelimiters(input: []const u8) DelimiterMask {
        const vector_size = 32;  // AVX2
        
        if (input.len < vector_size) {
            return findDelimitersScalar(input);
        }
        
        var mask = DelimiterMask{};
        var pos: usize = 0;
        
        while (pos + vector_size <= input.len) {
            const vector = @as(@Vector(vector_size, u8), input[pos..][0..vector_size].*);
            
            // Check for all delimiters in parallel
            const brace_open = vector == @as(@Vector(vector_size, u8), @splat('{'));
            const brace_close = vector == @as(@Vector(vector_size, u8), @splat('}'));
            const bracket_open = vector == @as(@Vector(vector_size, u8), @splat('['));
            const bracket_close = vector == @as(@Vector(vector_size, u8), @splat(']'));
            const comma = vector == @as(@Vector(vector_size, u8), @splat(','));
            const colon = vector == @as(@Vector(vector_size, u8), @splat(':'));
            
            // Combine masks
            const combined = @bitCast(u32, brace_open | brace_close | bracket_open | bracket_close | comma | colon);
            
            if (combined != 0) {
                // Found delimiters, process them
                mask.addDelimiters(pos, combined);
            }
            
            pos += vector_size;
        }
        
        // Handle remainder
        if (pos < input.len) {
            const remainder_mask = findDelimitersScalar(input[pos..]);
            mask.merge(remainder_mask, pos);
        }
        
        return mask;
    }
};

// src/lib/optimization/lookup_tables.zig
pub const LookupTables = struct {
    /// Pre-computed character classification tables
    pub const CHAR_CLASS: [256]CharClass = comptime blk: {
        var table = [_]CharClass{.other} ** 256;
        
        // Whitespace
        table[' '] = .whitespace;
        table['\t'] = .whitespace;
        table['\n'] = .newline;
        table['\r'] = .newline;
        
        // Delimiters
        table['{'] = .delimiter;
        table['}'] = .delimiter;
        table['['] = .delimiter;
        table[']'] = .delimiter;
        table['('] = .delimiter;
        table[')'] = .delimiter;
        table[','] = .delimiter;
        table[':'] = .delimiter;
        table[';'] = .delimiter;
        
        // Quotes
        table['"'] = .quote;
        table['\''] = .quote;
        table['`'] = .quote;
        
        // Numbers
        for ('0'..'9' + 1) |ch| {
            table[ch] = .digit;
        }
        table['-'] = .sign;
        table['+'] = .sign;
        table['.'] = .decimal;
        
        // Identifiers
        for ('a'..'z' + 1) |ch| {
            table[ch] = .alpha;
        }
        for ('A'..'Z' + 1) |ch| {
            table[ch] = .alpha;
        }
        table['_'] = .alpha;
        table['$'] = .alpha;
        
        break :blk table;
    };
    
    pub const CharClass = enum(u4) {
        other,
        whitespace,
        newline,
        delimiter,
        quote,
        digit,
        sign,
        decimal,
        alpha,
    };
};
```

## Implementation Phases

### Phase 1: Core Infrastructure ✅ COMPLETE
- [x] Create stateful lexer base types
- [x] Implement state machine for all contexts
- [x] Add chunk boundary handling
- [x] Create generic token interface

### Phase 2: Language-Specific Tokens ✅ COMPLETE
- [x] Implement JsonToken union type with rich metadata
- [x] Create StatefulJsonLexer emitting JsonToken
- [x] Implement token conversion pipeline
- [x] Add unified token iterator for streaming

### Phase 3: Parser Architecture (Days 3-4)
- [ ] Update AST.Node to remove language specifics
- [ ] Create CommonRules enum
- [ ] Update boundary parser for generic AST
- [ ] Fix ParseNode/AST.Node mismatch

### Phase 4: Analysis Framework (Days 4-5)
- [ ] Design AnalysisPass interface
- [ ] Implement AnalysisEngine with dependency resolution
- [ ] Create TypeChecker pass
- [ ] Create Linter pass
- [ ] Add symbol resolution

### Phase 5: Performance Optimization (Day 5-6)
- [ ] Add SIMD delimiter scanning
- [ ] Implement lookup tables
- [ ] Profile and optimize hot paths
- [ ] Add memory pools for allocations

### Phase 6: Testing & Validation (Day 6-7)
- [ ] Exhaustive chunk boundary tests
- [ ] Fuzzing for edge cases
- [ ] Performance benchmarks
- [ ] Memory leak detection
- [ ] Integration tests

## Success Metrics

### Correctness
- ✅ **100% chunk boundary handling** - No data loss ever
- ✅ **All 840 tests passing** - Full test suite green
- ✅ **Zero memory leaks** - Valgrind clean
- ✅ **RFC compliance** - JSON RFC 8259, ECMAScript spec, etc.

### Performance
- ✅ **<50ns per token** - Lexer performance
- ✅ **<200ns per AST node** - Parser performance
- ✅ **<1ms for 10KB file** - End-to-end
- ✅ **<5% streaming overhead** - vs non-chunked

### Architecture
- ✅ **Type-safe language implementations** - Compile-time verification
- ✅ **Generic analysis tools** - Work on all languages
- ✅ **Pluggable passes** - Easy to extend
- ✅ **Zero breaking changes** - Clean migration path

## Risk Mitigation

### Complexity Risk
**Mitigation**: Clear layer boundaries, comprehensive tests, documentation

### Performance Risk
**Mitigation**: Profiling, benchmarks, optimization passes

### Migration Risk
**Mitigation**: Incremental implementation, compatibility layer

## Long-Term Vision

This architecture enables:
1. **IDE Integration** - LSP server implementation
2. **Incremental Parsing** - Real-time editor updates
3. **Parallel Analysis** - Multi-threaded passes
4. **Custom Languages** - Easy to add new languages
5. **Advanced Analysis** - Dead code, security, complexity

---

**Status**: READY FOR IMPLEMENTATION
**Priority**: CRITICAL - Core infrastructure
**Complexity**: HIGH - But manageable with clear design
**Impact**: FOUNDATIONAL - Enables all future features