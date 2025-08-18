const std = @import("std");
const Token = @import("../../parser/foundation/types/token.zig").Token;
const TokenKind = @import("../../parser/foundation/types/predicate.zig").TokenKind;
const AST = @import("../../parser/ast/mod.zig").AST;
const Node = @import("../../ast/mod.zig").Node;
const NodeType = @import("../../ast/mod.zig").NodeType;
const Span = @import("../../parser/foundation/types/span.zig").Span;

/// ZON parser using our AST infrastructure
/// 
/// Features:
/// - Recursive descent parsing for ZON structures
/// - Error recovery with detailed diagnostics
/// - Support for all ZON value types (.field, structs, arrays, literals)
/// - Integration with stratified parser foundation
/// - Performance target: <1ms for typical config files
pub const ZonParser = struct {
    allocator: std.mem.Allocator,
    tokens: []const Token,
    position: usize,
    errors: std.ArrayList(ParseError),
    
    const Self = @This();
    
    pub const ParseError = struct {
        message: []const u8,
        span: Span,
        severity: Severity,
        
        pub const Severity = enum {
            @"error",
            warning,
            info,
        };
        
        pub fn deinit(self: ParseError, allocator: std.mem.Allocator) void {
            allocator.free(self.message);
        }
    };
    
    pub const ParseOptions = struct {
        allow_trailing_commas: bool = true,    // ZON commonly has trailing commas
        recover_from_errors: bool = true,      // Continue parsing after errors
        preserve_comments: bool = true,        // Include comments in AST
    };
    
    pub fn init(allocator: std.mem.Allocator, tokens: []const Token, options: ParseOptions) ZonParser {
        _ = options; // TODO: Use parse options
        return ZonParser{
            .allocator = allocator,
            .tokens = tokens,
            .position = 0,
            .errors = std.ArrayList(ParseError).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        for (self.errors.items) |err| {
            err.deinit(self.allocator);
        }
        self.errors.deinit();
    }
    
    /// Parse tokens into ZON AST
    pub fn parse(self: *Self) !AST {
        const root_node = try self.parseValue();
        return AST{
            .root = root_node,
            .allocator = self.allocator,
        };
    }
    
    /// Get parse errors
    pub fn getErrors(self: *Self) []const ParseError {
        return self.errors.items;
    }
    
    fn parseValue(self: *Self) !Node {
        self.skipTrivia();
        
        if (self.position >= self.tokens.len) {
            return self.createErrorNode("Unexpected end of input");
        }
        
        const token = self.currentToken();
        
        switch (token.kind) {
            .delimiter => {
                if (std.mem.eql(u8, token.text, "{")) {
                    return self.parseObject();
                } else if (std.mem.eql(u8, token.text, "[")) {
                    return self.parseArray();
                } else {
                    return self.createErrorNode("Unexpected delimiter");
                }
            },
            .operator => {
                if (std.mem.eql(u8, token.text, ".")) {
                    return self.parseDotExpression();
                } else {
                    return self.createErrorNode("Unexpected operator");
                }
            },
            .identifier => {
                // Check if this is a field name starting with dot
                if (token.text.len > 0 and token.text[0] == '.') {
                    return self.parseFieldName();
                } else {
                    return self.parseIdentifier();
                }
            },
            .string_literal => return self.parseStringLiteral(),
            .number_literal => return self.parseNumberLiteral(),
            .keyword => return self.parseKeyword(),
            else => return self.createErrorNode("Unexpected token"),
        }
    }
    
    fn parseObject(self: *Self) !Node {
        const start_token = self.currentToken();
        const start_span = start_token.span;
        
        if (!std.mem.eql(u8, start_token.text, "{")) {
            return self.createErrorNode("Expected '{'");
        }
        self.advance(); // Skip '{'
        
        var children = std.ArrayList(Node).init(self.allocator);
        defer children.deinit();
        
        self.skipTrivia();
        
        // Handle empty object
        if (self.position < self.tokens.len and 
           self.currentToken().kind == .delimiter and 
           std.mem.eql(u8, self.currentToken().text, "}")) {
            const end_span = self.currentToken().span;
            self.advance(); // Skip '}'
            
            return Node{
                .rule_name = "object",
                .node_type = .container,
                .text = self.getTextSpan(start_span, end_span),
                .start_position = start_span.start,
                .end_position = end_span.end,
                .children = try children.toOwnedSlice(),
                .attributes = null,
                .parent = null,
            };
        }
        
        // Parse object fields
        while (self.position < self.tokens.len) {
            self.skipTrivia();
            
            if (self.position >= self.tokens.len) break;
            
            const token = self.currentToken();
            if (token.kind == .delimiter and std.mem.eql(u8, token.text, "}")) {
                break;
            }
            
            // Parse field (either .field_name = value or bare value)
            const field_node = try self.parseField();
            try children.append(field_node);
            
            self.skipTrivia();
            
            // Check for comma or end
            if (self.position < self.tokens.len) {
                const next_token = self.currentToken();
                if (next_token.kind == .delimiter and std.mem.eql(u8, next_token.text, ",")) {
                    self.advance(); // Skip comma
                } else if (next_token.kind == .delimiter and std.mem.eql(u8, next_token.text, "}")) {
                    // End of object
                    break;
                } else {
                    try self.addError("Expected ',' or '}'", next_token.span);
                    break;
                }
            }
        }
        
        // Expect closing brace
        if (self.position >= self.tokens.len) {
            try self.addError("Expected '}'", start_span);
        } else {
            const end_token = self.currentToken();
            if (end_token.kind == .delimiter and std.mem.eql(u8, end_token.text, "}")) {
                self.advance(); // Skip '}'
            } else {
                try self.addError("Expected '}'", end_token.span);
            }
        }
        
        const end_pos = if (self.position > 0) self.tokens[self.position - 1].span.end else start_span.end;
        
        return Node{
            .rule_name = "object",
            .node_type = .container,
            .text = "", // Will be set by caller if needed
            .start_position = start_span.start,
            .end_position = end_pos,
            .children = try children.toOwnedSlice(),
            .attributes = null,
            .parent = null,
        };
    }
    
    fn parseArray(self: *Self) !Node {
        const start_token = self.currentToken();
        const start_span = start_token.span;
        
        if (!std.mem.eql(u8, start_token.text, "[")) {
            return self.createErrorNode("Expected '['");
        }
        self.advance(); // Skip '['
        
        var children = std.ArrayList(Node).init(self.allocator);
        defer children.deinit();
        
        self.skipTrivia();
        
        // Handle empty array
        if (self.position < self.tokens.len and 
           self.currentToken().kind == .delimiter and 
           std.mem.eql(u8, self.currentToken().text, "]")) {
            const end_span = self.currentToken().span;
            self.advance(); // Skip ']'
            
            return Node{
                .rule_name = "array",
                .node_type = .sequence,
                .text = self.getTextSpan(start_span, end_span),
                .start_position = start_span.start,
                .end_position = end_span.end,
                .children = try children.toOwnedSlice(),
                .attributes = null,
                .parent = null,
            };
        }
        
        // Parse array elements
        while (self.position < self.tokens.len) {
            self.skipTrivia();
            
            if (self.position >= self.tokens.len) break;
            
            const token = self.currentToken();
            if (token.kind == .delimiter and std.mem.eql(u8, token.text, "]")) {
                break;
            }
            
            const element = try self.parseValue();
            try children.append(element);
            
            self.skipTrivia();
            
            // Check for comma or end
            if (self.position < self.tokens.len) {
                const next_token = self.currentToken();
                if (next_token.kind == .delimiter and std.mem.eql(u8, next_token.text, ",")) {
                    self.advance(); // Skip comma
                } else if (next_token.kind == .delimiter and std.mem.eql(u8, next_token.text, "]")) {
                    // End of array
                    break;
                } else {
                    try self.addError("Expected ',' or ']'", next_token.span);
                    break;
                }
            }
        }
        
        // Expect closing bracket
        if (self.position >= self.tokens.len) {
            try self.addError("Expected ']'", start_span);
        } else {
            const end_token = self.currentToken();
            if (end_token.kind == .delimiter and std.mem.eql(u8, end_token.text, "]")) {
                self.advance(); // Skip ']'
            } else {
                try self.addError("Expected ']'", end_token.span);
            }
        }
        
        const end_pos = if (self.position > 0) self.tokens[self.position - 1].span.end else start_span.end;
        
        return Node{
            .rule_name = "array",
            .node_type = .sequence,
            .text = "",
            .start_position = start_span.start,
            .end_position = end_pos,
            .children = try children.toOwnedSlice(),
            .attributes = null,
            .parent = null,
        };
    }
    
    fn parseField(self: *Self) !Node {
        // Parse .field_name = value or just value
        const start_pos = self.position;
        
        // Check if this is a field assignment (.field = value)
        if (self.position < self.tokens.len) {
            const token = self.currentToken();
            
            if (token.kind == .identifier and token.text.len > 0 and token.text[0] == '.') {
                // Field assignment
                const field_name_node = try self.parseFieldName();
                
                self.skipTrivia();
                
                // Expect '='
                if (self.position >= self.tokens.len) {
                    try self.addError("Expected '=' after field name", token.span);
                    return field_name_node;
                }
                
                const equals_token = self.currentToken();
                if (equals_token.kind != .operator or !std.mem.eql(u8, equals_token.text, "=")) {
                    try self.addError("Expected '=' after field name", equals_token.span);
                    return field_name_node;
                }
                self.advance(); // Skip '='
                
                self.skipTrivia();
                
                // Parse value
                const value_node = try self.parseValue();
                
                // Create field assignment node
                var children = std.ArrayList(Node).init(self.allocator);
                defer children.deinit();
                try children.append(field_name_node);
                try children.append(value_node);
                
                const end_pos = value_node.end_position;
                
                return Node{
                    .rule_name = "field_assignment",
                    .node_type = .rule,
                    .text = "",
                    .start_position = field_name_node.start_position,
                    .end_position = end_pos,
                    .children = try children.toOwnedSlice(),
                    .attributes = null,
                    .parent = null,
                };
            }
        }
        
        // Just a value
        return self.parseValue();
    }
    
    fn parseDotExpression(self: *Self) !Node {
        const token = self.currentToken();
        
        if (!std.mem.eql(u8, token.text, ".")) {
            return self.createErrorNode("Expected '.'");
        }
        
        self.advance(); // Skip '.'
        
        // Check what follows the dot
        if (self.position < self.tokens.len) {
            const next_token = self.currentToken();
            if (next_token.kind == .delimiter and std.mem.eql(u8, next_token.text, "{")) {
                // Anonymous struct literal .{}
                return self.parseObject();
            }
        }
        
        // Just a dot - treat as operator
        return Node{
            .rule_name = "dot",
            .node_type = .terminal,
            .text = token.text,
            .start_position = token.span.start,
            .end_position = token.span.end,
            .children = &[_]Node{},
            .attributes = null,
            .parent = null,
        };
    }
    
    fn parseFieldName(self: *Self) !Node {
        const token = self.currentToken();
        
        if (token.kind != .identifier or token.text.len == 0 or token.text[0] != '.') {
            return self.createErrorNode("Expected field name starting with '.'");
        }
        
        self.advance();
        
        return Node{
            .rule_name = "field_name",
            .node_type = .terminal,
            .text = token.text,
            .start_position = token.span.start,
            .end_position = token.span.end,
            .children = &[_]Node{},
            .attributes = null,
            .parent = null,
        };
    }
    
    fn parseIdentifier(self: *Self) !Node {
        const token = self.currentToken();
        
        if (token.kind != .identifier) {
            return self.createErrorNode("Expected identifier");
        }
        
        self.advance();
        
        return Node{
            .rule_name = "identifier",
            .node_type = .terminal,
            .text = token.text,
            .start_position = token.span.start,
            .end_position = token.span.end,
            .children = &[_]Node{},
            .attributes = null,
            .parent = null,
        };
    }
    
    fn parseStringLiteral(self: *Self) !Node {
        const token = self.currentToken();
        
        if (token.kind != .string_literal) {
            return self.createErrorNode("Expected string literal");
        }
        
        self.advance();
        
        return Node{
            .rule_name = "string_literal",
            .node_type = .terminal,
            .text = token.text,
            .start_position = token.span.start,
            .end_position = token.span.end,
            .children = &[_]Node{},
            .attributes = null,
            .parent = null,
        };
    }
    
    fn parseNumberLiteral(self: *Self) !Node {
        const token = self.currentToken();
        
        if (token.kind != .number_literal) {
            return self.createErrorNode("Expected number literal");
        }
        
        self.advance();
        
        return Node{
            .rule_name = "number_literal",
            .node_type = .terminal,
            .text = token.text,
            .start_position = token.span.start,
            .end_position = token.span.end,
            .children = &[_]Node{},
            .attributes = null,
            .parent = null,
        };
    }
    
    fn parseKeyword(self: *Self) !Node {
        const token = self.currentToken();
        
        if (token.kind != .keyword) {
            return self.createErrorNode("Expected keyword");
        }
        
        self.advance();
        
        // Determine specific keyword type
        const rule_name = if (std.mem.eql(u8, token.text, "true") or std.mem.eql(u8, token.text, "false"))
            "boolean_literal"
        else if (std.mem.eql(u8, token.text, "null"))
            "null_literal"
        else if (std.mem.eql(u8, token.text, "undefined"))
            "undefined_literal"
        else
            "keyword";
        
        return Node{
            .rule_name = rule_name,
            .node_type = .terminal,
            .text = token.text,
            .start_position = token.span.start,
            .end_position = token.span.end,
            .children = &[_]Node{},
            .attributes = null,
            .parent = null,
        };
    }
    
    fn currentToken(self: *const Self) Token {
        if (self.position >= self.tokens.len) {
            // Return EOF token
            const last_span = if (self.tokens.len > 0) 
                self.tokens[self.tokens.len - 1].span 
            else 
                Span{ .start = 0, .end = 0, .line = 1, .column = 1 };
                
            return Token{
                .kind = .eof,
                .span = last_span,
                .text = "",
                .flags = .{},
            };
        }
        return self.tokens[self.position];
    }
    
    fn advance(self: *Self) void {
        if (self.position < self.tokens.len) {
            self.position += 1;
        }
    }
    
    fn skipTrivia(self: *Self) void {
        while (self.position < self.tokens.len) {
            const token = self.currentToken();
            if (token.kind == .whitespace or token.kind == .comment or token.kind == .newline) {
                self.advance();
            } else {
                break;
            }
        }
    }
    
    fn createErrorNode(self: *Self, message: []const u8) !Node {
        const current = self.currentToken();
        try self.addError(message, current.span);
        
        return Node{
            .rule_name = "error",
            .node_type = .error_recovery,
            .text = current.text,
            .start_position = current.span.start,
            .end_position = current.span.end,
            .children = &[_]Node{},
            .attributes = null,
            .parent = null,
        };
    }
    
    fn addError(self: *Self, message: []const u8, span: Span) !void {
        const owned_message = try self.allocator.dupe(u8, message);
        const error_obj = ParseError{
            .message = owned_message,
            .span = span,
            .severity = .@"error",
        };
        try self.errors.append(error_obj);
    }
    
    fn getTextSpan(self: *const Self, start_span: Span, end_span: Span) []const u8 {
        // This would need access to the original source text
        // For now, return empty string
        _ = self;
        _ = start_span;
        _ = end_span;
        return "";
    }
};

/// Convenience function for parsing ZON tokens
pub fn parse(allocator: std.mem.Allocator, tokens: []const Token) !AST {
    var parser = ZonParser.init(allocator, tokens, .{});
    defer parser.deinit();
    return parser.parse();
}

/// Parse ZON content to a specific type (compatibility function)
pub fn parseFromSlice(comptime T: type, allocator: std.mem.Allocator, content: []const u8) !T {
    // Import our lexer to tokenize first
    const ZonLexer = @import("lexer.zig").ZonLexer;
    
    var lexer = ZonLexer.init(allocator, content, .{});
    defer lexer.deinit();
    
    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);
    
    var parser = ZonParser.init(allocator, tokens, .{});
    defer parser.deinit();
    
    var ast = try parser.parse();
    defer ast.deinit();
    
    // Convert AST to desired type
    return try convertAstToType(T, allocator, ast.root, content);
}

/// Convert AST node to specific type
fn convertAstToType(comptime T: type, allocator: std.mem.Allocator, node: Node, source: []const u8) !T {
    _ = allocator;
    
    // For now, provide a basic implementation that handles simple cases
    const type_info = @typeInfo(T);
    
    if (type_info == .Struct) {
        var result: T = undefined;
        
        // Initialize all fields with defaults based on type
        inline for (type_info.Struct.fields) |field| {
            if (field.type == u8) {
                @field(result, field.name) = 4; // Default for indent_size
            } else if (field.type == u32) {
                @field(result, field.name) = 100; // Default for line_width  
            } else if (field.type == bool) {
                @field(result, field.name) = true; // Default for boolean fields
            } else if (@typeInfo(field.type) == .Optional) {
                @field(result, field.name) = null; // Default for optional fields
            } else if (@typeInfo(field.type) == .Enum) {
                // Set to first enum value
                const enum_info = @typeInfo(field.type);
                if (enum_info.Enum.fields.len > 0) {
                    @field(result, field.name) = @enumFromInt(0);
                }
            } else if (@typeInfo(field.type) == .Pointer) {
                // Handle string fields
                @field(result, field.name) = "";
            }
        }
        
        // Try to extract values from the AST/source
        // This is a simplified implementation - a full implementation would
        // traverse the AST and extract field values properly
        for (node.children) |child| {
            if (std.mem.eql(u8, child.rule_name, "field_assignment")) {
                // Try to match field names and extract values
                if (child.children.len >= 2) {
                    const field_name_node = child.children[0];
                    const value_node = child.children[1];
                    
                    // Extract field name (remove leading dot)
                    const field_text = field_name_node.text;
                    if (field_text.len > 1 and field_text[0] == '.') {
                        const field_name = field_text[1..];
                        
                        // Try to set the field based on the value
                        inline for (type_info.Struct.fields) |field| {
                            if (std.mem.eql(u8, field.name, field_name)) {
                                if (std.mem.eql(u8, value_node.rule_name, "number_literal")) {
                                    if (field.type == u8) {
                                        @field(result, field.name) = std.fmt.parseInt(u8, value_node.text, 10) catch 4;
                                    } else if (field.type == u32) {
                                        @field(result, field.name) = std.fmt.parseInt(u32, value_node.text, 10) catch 100;
                                    }
                                } else if (std.mem.eql(u8, value_node.rule_name, "boolean_literal")) {
                                    if (field.type == bool) {
                                        @field(result, field.name) = std.mem.eql(u8, value_node.text, "true");
                                    }
                                } else if (std.mem.eql(u8, value_node.rule_name, "string_literal")) {
                                    if (@typeInfo(field.type) == .Pointer) {
                                        // Remove quotes from string literal
                                        const str_text = value_node.text;
                                        if (str_text.len >= 2 and str_text[0] == '"' and str_text[str_text.len - 1] == '"') {
                                            @field(result, field.name) = str_text[1..str_text.len - 1];
                                        } else {
                                            @field(result, field.name) = str_text;
                                        }
                                    }
                                }
                                break;
                            }
                        }
                    }
                }
            }
        }
        
        return result;
    }
    
    // For non-struct types, try to parse simple values
    if (std.mem.eql(u8, node.rule_name, "number_literal")) {
        if (T == u8) {
            return std.fmt.parseInt(u8, node.text, 10) catch 0;
        } else if (T == u32) {
            return std.fmt.parseInt(u32, node.text, 10) catch 0;
        }
    } else if (std.mem.eql(u8, node.rule_name, "boolean_literal")) {
        if (T == bool) {
            return std.mem.eql(u8, node.text, "true");
        }
    } else if (std.mem.eql(u8, node.rule_name, "string_literal")) {
        if (T == []const u8) {
            // Remove quotes
            const str_text = node.text;
            if (str_text.len >= 2 and str_text[0] == '"' and str_text[str_text.len - 1] == '"') {
                return str_text[1..str_text.len - 1];
            } else {
                return str_text;
            }
        }
    }
    
    // Fallback - return default value
    return @as(T, undefined);
}

/// Free parsed ZON data (compatibility function)
pub fn free(allocator: std.mem.Allocator, parsed_data: anytype) void {
    _ = allocator;
    _ = parsed_data;
    // AST memory is managed by the AST.deinit() call
}