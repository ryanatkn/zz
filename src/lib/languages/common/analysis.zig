const std = @import("std");
const Symbol = @import("../interface.zig").Symbol;
const Reference = @import("../interface.zig").Reference;
const AST = @import("../../ast/mod.zig").AST;
const CommonRules = @import("../../ast/rules.zig").CommonRules;

/// Common analysis utilities shared across languages
///
/// This module provides building blocks for semantic analysis
/// that can be reused across language implementations.
/// Symbol table for tracking declarations and references
pub const SymbolTable = struct {
    allocator: std.mem.Allocator,
    symbols: std.HashMap([]const u8, Symbol),
    scopes: std.ArrayList(Scope),
    current_scope: u32,

    pub fn init(allocator: std.mem.Allocator) SymbolTable {
        var table = SymbolTable{
            .allocator = allocator,
            .symbols = std.HashMap([]const u8, Symbol).init(allocator),
            .scopes = std.ArrayList(Scope).init(allocator),
            .current_scope = 0,
        };

        // Add global scope
        table.scopes.append(Scope.init(allocator, null)) catch unreachable;

        return table;
    }

    pub fn deinit(self: *SymbolTable) void {
        self.symbols.deinit();
        for (self.scopes.items) |*scope| {
            scope.deinit();
        }
        self.scopes.deinit();
    }

    /// Enter a new scope
    pub fn enterScope(self: *SymbolTable, scope_type: ScopeType) !u32 {
        const scope_id: u32 = @intCast(self.scopes.items.len);
        const scope = Scope.init(self.allocator, scope_type);
        try self.scopes.append(scope);

        const old_scope = self.current_scope;
        self.current_scope = scope_id;
        return old_scope;
    }

    /// Exit current scope
    pub fn exitScope(self: *SymbolTable, previous_scope: u32) void {
        self.current_scope = previous_scope;
    }

    /// Add symbol to current scope
    pub fn addSymbol(self: *SymbolTable, name: []const u8, symbol: Symbol) !void {
        // Clone the name to ensure it's owned by the table
        const owned_name = try self.allocator.dupe(u8, name);
        try self.symbols.put(owned_name, symbol);

        // Add to current scope
        if (self.current_scope < self.scopes.items.len) {
            try self.scopes.items[self.current_scope].addSymbol(owned_name);
        }
    }

    /// Lookup symbol by name (searches up scope chain)
    pub fn lookupSymbol(self: *SymbolTable, name: []const u8) ?Symbol {
        return self.symbols.get(name);
    }

    /// Get all symbols in current scope
    pub fn getCurrentScopeSymbols(self: *SymbolTable) []const []const u8 {
        if (self.current_scope < self.scopes.items.len) {
            return self.scopes.items[self.current_scope].symbols.items;
        }
        return &.{};
    }

    /// Get all symbols
    pub fn getAllSymbols(self: *SymbolTable) std.HashMap([]const u8, Symbol) {
        return self.symbols;
    }
};

const Scope = struct {
    allocator: std.mem.Allocator,
    scope_type: ?ScopeType,
    symbols: std.ArrayList([]const u8),

    fn init(allocator: std.mem.Allocator, scope_type: ?ScopeType) Scope {
        return Scope{
            .allocator = allocator,
            .scope_type = scope_type,
            .symbols = std.ArrayList([]const u8).init(allocator),
        };
    }

    fn deinit(self: *Scope) void {
        self.symbols.deinit();
    }

    fn addSymbol(self: *Scope, name: []const u8) !void {
        try self.symbols.append(name);
    }
};

const ScopeType = enum {
    global,
    function,
    class,
    block,
    module,
};

/// Reference tracker for finding symbol usage
pub const ReferenceTracker = struct {
    allocator: std.mem.Allocator,
    references: std.HashMap([]const u8, std.ArrayList(Reference)),

    pub fn init(allocator: std.mem.Allocator) ReferenceTracker {
        return ReferenceTracker{
            .allocator = allocator,
            .references = std.HashMap([]const u8, std.ArrayList(Reference)).init(allocator),
        };
    }

    pub fn deinit(self: *ReferenceTracker) void {
        var iterator = self.references.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.references.deinit();
    }

    /// Add reference to a symbol
    pub fn addReference(self: *ReferenceTracker, symbol_name: []const u8, reference: Reference) !void {
        const owned_name = try self.allocator.dupe(u8, symbol_name);

        var result = try self.references.getOrPut(owned_name);
        if (!result.found_existing) {
            result.value_ptr.* = std.ArrayList(Reference).init(self.allocator);
        }

        try result.value_ptr.append(reference);
    }

    /// Get all references to a symbol
    pub fn getReferences(self: *ReferenceTracker, symbol_name: []const u8) ?[]const Reference {
        if (self.references.get(symbol_name)) |refs| {
            return refs.items;
        }
        return null;
    }

    /// Get all tracked symbols
    pub fn getTrackedSymbols(self: *ReferenceTracker) std.HashMap([]const u8, std.ArrayList(Reference)) {
        return self.references;
    }
};

/// Dependency tracker for module/import analysis
pub const DependencyTracker = struct {
    allocator: std.mem.Allocator,
    dependencies: std.HashMap([]const u8, std.ArrayList([]const u8)),

    pub fn init(allocator: std.mem.Allocator) DependencyTracker {
        return DependencyTracker{
            .allocator = allocator,
            .dependencies = std.HashMap([]const u8, std.ArrayList([]const u8)).init(allocator),
        };
    }

    pub fn deinit(self: *DependencyTracker) void {
        var iterator = self.dependencies.iterator();
        while (iterator.next()) |entry| {
            // Free dependency names
            for (entry.value_ptr.items) |dep| {
                self.allocator.free(dep);
            }
            entry.value_ptr.deinit();
            // Free module name
            self.allocator.free(entry.key_ptr.*);
        }
        self.dependencies.deinit();
    }

    /// Add dependency relationship
    pub fn addDependency(self: *DependencyTracker, from_module: []const u8, to_module: []const u8) !void {
        const owned_from = try self.allocator.dupe(u8, from_module);
        const owned_to = try self.allocator.dupe(u8, to_module);

        var result = try self.dependencies.getOrPut(owned_from);
        if (!result.found_existing) {
            result.value_ptr.* = std.ArrayList([]const u8).init(self.allocator);
        }

        try result.value_ptr.append(owned_to);
    }

    /// Get dependencies of a module
    pub fn getDependencies(self: *DependencyTracker, module: []const u8) ?[]const []const u8 {
        if (self.dependencies.get(module)) |deps| {
            return deps.items;
        }
        return null;
    }

    /// Check for circular dependencies
    pub fn hasCircularDependencies(self: *DependencyTracker) bool {
        // Simple cycle detection using DFS
        var visited = std.HashMap([]const u8, bool).init(self.allocator);
        defer visited.deinit();

        var visiting = std.HashMap([]const u8, bool).init(self.allocator);
        defer visiting.deinit();

        var iterator = self.dependencies.iterator();
        while (iterator.next()) |entry| {
            if (self.hasCycleDFS(entry.key_ptr.*, &visited, &visiting)) {
                return true;
            }
        }

        return false;
    }

    fn hasCycleDFS(
        self: *DependencyTracker,
        module: []const u8,
        visited: *std.HashMap([]const u8, bool),
        visiting: *std.HashMap([]const u8, bool),
    ) bool {
        if (visiting.get(module) orelse false) {
            return true; // Back edge found - cycle detected
        }

        if (visited.get(module) orelse false) {
            return false; // Already processed
        }

        visiting.put(module, true) catch return false;

        if (self.getDependencies(module)) |deps| {
            for (deps) |dep| {
                if (self.hasCycleDFS(dep, visited, visiting)) {
                    return true;
                }
            }
        }

        visiting.put(module, false) catch {};
        visited.put(module, true) catch {};

        return false;
    }
};

/// Common analysis patterns
/// Extract function calls from AST using new AST infrastructure
pub fn extractFunctionCalls(allocator: std.mem.Allocator, ast: AST) ![][]const u8 {
    const traversal = @import("../../ast/traversal.zig");
    const query = @import("../../ast/query.zig");

    var calls = std.ArrayList([]const u8).init(allocator);
    defer calls.deinit();

    // Find all function call nodes
    const ast_query = query.ASTQuery.init(allocator);

    // Look for common function call patterns
    const call_patterns = [_][]const u8{
        "function_call",
        "call_expression",
        "method_call",
        "invocation",
    };

    for (call_patterns) |pattern| {
        const call_nodes = ast_query.selectByRule(&ast.root, pattern) catch continue;
        defer allocator.free(call_nodes);

        for (call_nodes) |node| {
            // Extract function name from call node
            if (node.children.len > 0) {
                const name_text = node.children[0].text;
                if (name_text.len > 0) {
                    try calls.append(try allocator.dupe(u8, name_text));
                }
            }
        }
    }

    return calls.toOwnedSlice();
}

/// Extract variable declarations from AST using new AST infrastructure
pub fn extractVariableDeclarations(allocator: std.mem.Allocator, ast: AST) ![]Symbol {
    const query = @import("../../ast/query.zig");

    var declarations = std.ArrayList(Symbol).init(allocator);
    defer declarations.deinit();

    // Find all variable declaration patterns
    const ast_query = query.ASTQuery.init(allocator);

    const declaration_patterns = [_][]const u8{
        "variable_declaration",
        "var_declaration",
        "const_declaration",
        "let_declaration",
        "field_declaration",
    };

    for (declaration_patterns) |pattern| {
        const decl_nodes = ast_query.selectByRule(&ast.root, pattern) catch continue;
        defer allocator.free(decl_nodes);

        for (decl_nodes) |node| {
            // Extract variable name and create symbol
            var symbol_name: []const u8 = "";
            var symbol_type: []const u8 = "variable";

            // Look for identifier in children
            for (node.children) |child| {
                if (child.rule_id == @intFromEnum(CommonRules.identifier)) {
                    symbol_name = try allocator.dupe(u8, child.text);
                    break;
                }
            }

            if (symbol_name.len > 0) {
                try declarations.append(Symbol{
                    .name = symbol_name,
                    .symbol_type = try allocator.dupe(u8, symbol_type),
                    .location = SymbolLocation{
                        .file = "current", // TODO: Track actual file
                        .line = 0, // TODO: Calculate from positions
                        .column = 0,
                    },
                    .scope = .local, // TODO: Determine actual scope
                });
            }
        }
    }

    return declarations.toOwnedSlice();
}

/// Calculate cyclomatic complexity using new AST infrastructure
pub fn calculateComplexity(ast: AST) u32 {
    const query = @import("../../ast/query.zig");

    // Base complexity starts at 1
    var complexity: u32 = 1;

    const ast_query = query.ASTQuery.init(std.heap.page_allocator);

    // Decision points that increase complexity
    const decision_patterns = [_][]const u8{
        "if_statement",
        "while_statement",
        "for_statement",
        "switch_statement",
        "case_statement",
        "catch_clause",
        "conditional_expression", // ternary operator
        "logical_and",
        "logical_or",
    };

    for (decision_patterns) |pattern| {
        const nodes = ast_query.selectByRule(&ast.root, pattern) catch continue;
        defer std.heap.page_allocator.free(nodes);
        complexity += @as(u32, @intCast(nodes.len));
    }

    return complexity;
}

/// Find unused symbols
pub fn findUnusedSymbols(symbol_table: *SymbolTable, reference_tracker: *ReferenceTracker) ![][]const u8 {
    var unused = std.ArrayList([]const u8).init(symbol_table.allocator);

    var symbol_iterator = symbol_table.symbols.iterator();
    while (symbol_iterator.next()) |entry| {
        const symbol_name = entry.key_ptr.*;

        // Check if symbol has any references
        if (reference_tracker.getReferences(symbol_name) == null) {
            try unused.append(symbol_name);
        }
    }

    return unused.toOwnedSlice();
}
