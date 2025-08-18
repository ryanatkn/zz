const std = @import("std");
const Symbol = @import("../interface.zig").Symbol;
const Reference = @import("../interface.zig").Reference;
const AST = @import("../../ast/mod.zig").AST;

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
/// Extract function calls from AST (simplified)
pub fn extractFunctionCalls(allocator: std.mem.Allocator, ast: AST) ![][]const u8 {
    // This is a placeholder implementation
    // Real implementation would traverse AST and extract function call nodes
    _ = ast;
    var calls = std.ArrayList([]const u8).init(allocator);
    // TODO: Implement actual AST traversal
    return calls.toOwnedSlice();
}

/// Extract variable declarations from AST (simplified)
pub fn extractVariableDeclarations(allocator: std.mem.Allocator, ast: AST) ![]Symbol {
    // This is a placeholder implementation
    // Real implementation would traverse AST and extract variable declarations
    _ = ast;
    var declarations = std.ArrayList(Symbol).init(allocator);
    // TODO: Implement actual AST traversal
    return declarations.toOwnedSlice();
}

/// Calculate cyclomatic complexity (simplified)
pub fn calculateComplexity(ast: AST) u32 {
    // This is a placeholder implementation
    // Real implementation would count decision points in AST
    _ = ast;
    return 1; // TODO: Implement actual complexity calculation
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
