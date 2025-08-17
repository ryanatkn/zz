const std = @import("std");

// Import foundation types
const Fact = @import("../foundation/types/fact.zig").Fact;
const FactId = @import("../foundation/types/fact.zig").FactId;
const Generation = @import("../foundation/types/fact.zig").Generation;
const Span = @import("../foundation/types/span.zig").Span;
const Predicate = @import("../foundation/types/predicate.zig").Predicate;
const Value = @import("../foundation/types/predicate.zig").Value;

// Import AST types (these will need to be defined)
const AST = @import("../ast/mod.zig").AST;
const ASTNode = @import("../../ast/mod.zig").ASTNode;
const NodeKind = @import("../ast/mod.zig").NodeKind;

// Import structural types
const ParseBoundary = @import("../structural/mod.zig").ParseBoundary;

/// Converts AST nodes into fact streams for the stratified parser architecture
pub const FactGenerator = struct {
    /// Memory allocator
    allocator: std.mem.Allocator,
    
    /// Next fact ID to assign
    next_fact_id: FactId,
    
    /// Current generation counter
    generation: Generation,
    
    /// Statistics for performance monitoring
    stats: FactGeneratorStats,
    
    pub fn init(allocator: std.mem.Allocator) FactGenerator {
        return FactGenerator{
            .allocator = allocator,
            .next_fact_id = 1,
            .generation = 0,
            .stats = FactGeneratorStats{},
        };
    }
    
    pub fn deinit(self: *FactGenerator) void {
        _ = self;
        // No cleanup needed for this simple implementation
    }
    
    /// Set the current generation for new facts
    pub fn setGeneration(self: *FactGenerator, generation: Generation) void {
        self.generation = generation;
    }
    
    /// Convert an AST to a list of facts
    /// This is the main entry point for AST-to-facts conversion
    pub fn fromAST(
        self: *FactGenerator,
        ast: AST,
        boundary: ParseBoundary,
    ) ![]Fact {
        const start_time = std.time.nanoTimestamp();
        defer {
            const elapsed = std.time.nanoTimestamp() - start_time;
            self.stats.total_conversion_time_ns += @intCast(elapsed);
            self.stats.conversions_performed += 1;
        }
        
        var facts = std.ArrayList(Fact).init(self.allocator);
        errdefer facts.deinit();
        
        // Generate facts for the root node and all children
        try self.visitNode(ast.root, &facts, boundary.confidence);
        
        const result = try facts.toOwnedSlice();
        self.stats.facts_generated += result.len;
        
        return result;
    }
    
    /// Visit a single AST node and generate appropriate facts
    fn visitNode(
        self: *FactGenerator,
        node: ASTNode,
        facts: *std.ArrayList(Fact),
        confidence: f32,
    ) !void {
        // Generate facts based on node type and rule name
        switch (node.node_type) {
            .terminal => try self.generateTerminalFacts(node, facts, confidence),
            .rule => try self.generateRuleBasedFacts(node, facts, confidence),
            .list => try self.generateListFacts(node, facts, confidence),
            .optional => try self.generateOptionalFacts(node, facts, confidence),
            .error_recovery => try self.generateErrorFacts(node, facts, confidence),
        }
        
        // Recursively visit all children
        for (node.children) |child| {
            try self.visitNode(child, facts, confidence);
        }
    }
    
    // ========================================================================
    // Specific fact generation methods for each AST node type
    // ========================================================================
    
    fn generateTerminalFacts(
        self: *FactGenerator,
        node: ASTNode,
        facts: *std.ArrayList(Fact),
        confidence: f32,
    ) !void {
        // Terminal nodes represent literal text - generate token facts
        try self.generateGenericFacts(node, facts, confidence);
    }
    
    fn generateRuleBasedFacts(
        self: *FactGenerator,
        node: ASTNode,
        facts: *std.ArrayList(Fact),
        confidence: f32,
    ) !void {
        // Use rule_name to determine the semantic type
        if (std.mem.eql(u8, node.rule_name, "function")) {
            try self.generateFunctionFacts(node, facts, confidence);
        } else if (std.mem.eql(u8, node.rule_name, "struct")) {
            try self.generateStructFacts(node, facts, confidence);
        } else {
            try self.generateGenericFacts(node, facts, confidence);
        }
    }
    
    fn generateListFacts(
        self: *FactGenerator,
        node: ASTNode,
        facts: *std.ArrayList(Fact),
        confidence: f32,
    ) !void {
        // List nodes represent repeated elements
        try self.generateGenericFacts(node, facts, confidence);
    }
    
    fn generateOptionalFacts(
        self: *FactGenerator,
        node: ASTNode,
        facts: *std.ArrayList(Fact),
        confidence: f32,
    ) !void {
        // Optional nodes may or may not be present
        try self.generateGenericFacts(node, facts, confidence);
    }
    
    fn generateErrorFacts(
        self: *FactGenerator,
        node: ASTNode,
        facts: *std.ArrayList(Fact),
        confidence: f32,
    ) !void {
        // Error recovery nodes indicate parse issues
        try self.generateGenericFacts(node, facts, confidence * 0.5); // Reduce confidence for errors
    }
    
    fn generateFunctionFacts(
        self: *FactGenerator,
        node: ASTNode,
        facts: *std.ArrayList(Fact),
        confidence: f32,
    ) !void {
        // Function declaration fact using rule name
        try facts.append(Fact{
            .id = self.nextId(),
            .subject = Span.init(node.start_position, node.end_position),
            .predicate = .is_function,
            .object = Value{ .string = node.rule_name },
            .confidence = confidence,
            .generation = self.generation,
        });
        
        // Function complexity fact (basic metric based on children)
        const complexity = node.children.len;
        try facts.append(Fact{
            .id = self.nextId(),
            .subject = Span.init(node.start_position, node.end_position),
            .predicate = .has_complexity,
            .object = Value{ .number = @floatFromInt(complexity) },
            .confidence = confidence,
            .generation = self.generation,
        });
    }
    
    fn generateStructFacts(
        self: *FactGenerator,
        node: ASTNode,
        facts: *std.ArrayList(Fact),
        confidence: f32,
    ) !void {
        // Struct declaration fact
        try facts.append(Fact{
            .id = self.nextId(),
            .subject = Span.init(node.start_position, node.end_position),
            .predicate = .is_struct,
            .object = Value{ .string = node.rule_name },
            .confidence = confidence,
            .generation = self.generation,
        });
        
        // Field count fact (useful for complexity analysis)
        try facts.append(Fact{
            .id = self.nextId(),
            .subject = Span.init(node.start_position, node.end_position),
            .predicate = .has_field_count,
            .object = Value{ .number = @floatFromInt(node.children.len) },
            .confidence = confidence,
            .generation = self.generation,
        });
    }
    
    fn generateVariableFacts(
        self: *FactGenerator,
        node: ASTNode,
        facts: *std.ArrayList(Fact),
        confidence: f32,
    ) !void {
        // Variable declaration fact
        try facts.append(Fact{
            .id = self.nextId(),
            .subject = Span.init(node.start_position, node.end_position),
            .predicate = .is_variable,
            .object = Value{ .string = node.rule_name },
            .confidence = confidence,
            .generation = self.generation,
        });
    }
    
    fn generateConstantFacts(
        self: *FactGenerator,
        node: ASTNode,
        facts: *std.ArrayList(Fact),
        confidence: f32,
    ) !void {
        try self.generateGenericFacts(node, facts, confidence);
    }
    
    // Simplified fact generation functions that just call generateGenericFacts
    fn generateImportFacts(self: *FactGenerator, node: ASTNode, facts: *std.ArrayList(Fact), confidence: f32) !void {
        try self.generateGenericFacts(node, facts, confidence);
    }
    fn generateTypeFacts(self: *FactGenerator, node: ASTNode, facts: *std.ArrayList(Fact), confidence: f32) !void {
        try self.generateGenericFacts(node, facts, confidence);
    }
    fn generateEnumFacts(self: *FactGenerator, node: ASTNode, facts: *std.ArrayList(Fact), confidence: f32) !void {
        try self.generateGenericFacts(node, facts, confidence);
    }
    fn generateFieldFacts(self: *FactGenerator, node: ASTNode, facts: *std.ArrayList(Fact), confidence: f32) !void {
        try self.generateGenericFacts(node, facts, confidence);
    }
    fn generateParameterFacts(self: *FactGenerator, node: ASTNode, facts: *std.ArrayList(Fact), confidence: f32) !void {
        try self.generateGenericFacts(node, facts, confidence);
    }
    fn generateCallFacts(self: *FactGenerator, node: ASTNode, facts: *std.ArrayList(Fact), confidence: f32) !void {
        try self.generateGenericFacts(node, facts, confidence);
    }
    fn generateIdentifierFacts(self: *FactGenerator, node: ASTNode, facts: *std.ArrayList(Fact), confidence: f32) !void {
        try self.generateGenericFacts(node, facts, confidence);
    }
    fn generateLiteralFacts(self: *FactGenerator, node: ASTNode, facts: *std.ArrayList(Fact), confidence: f32) !void {
        try self.generateGenericFacts(node, facts, confidence);
    }
    fn generateBlockFacts(self: *FactGenerator, node: ASTNode, facts: *std.ArrayList(Fact), confidence: f32) !void {
        try self.generateGenericFacts(node, facts, confidence);
    }
    fn generateAssignmentFacts(self: *FactGenerator, node: ASTNode, facts: *std.ArrayList(Fact), confidence: f32) !void {
        try self.generateGenericFacts(node, facts, confidence);
    }
    fn generateBinaryExpressionFacts(self: *FactGenerator, node: ASTNode, facts: *std.ArrayList(Fact), confidence: f32) !void {
        try self.generateGenericFacts(node, facts, confidence);
    }
    fn generateUnaryExpressionFacts(self: *FactGenerator, node: ASTNode, facts: *std.ArrayList(Fact), confidence: f32) !void {
        try self.generateGenericFacts(node, facts, confidence);
    }
    fn generateIfStatementFacts(self: *FactGenerator, node: ASTNode, facts: *std.ArrayList(Fact), confidence: f32) !void {
        try self.generateGenericFacts(node, facts, confidence);
    }
    fn generateWhileLoopFacts(self: *FactGenerator, node: ASTNode, facts: *std.ArrayList(Fact), confidence: f32) !void {
        try self.generateGenericFacts(node, facts, confidence);
    }
    fn generateForLoopFacts(self: *FactGenerator, node: ASTNode, facts: *std.ArrayList(Fact), confidence: f32) !void {
        try self.generateGenericFacts(node, facts, confidence);
    }
    fn generateReturnFacts(self: *FactGenerator, node: ASTNode, facts: *std.ArrayList(Fact), confidence: f32) !void {
        try self.generateGenericFacts(node, facts, confidence);
    }
    fn generateCommentFacts(self: *FactGenerator, node: ASTNode, facts: *std.ArrayList(Fact), confidence: f32) !void {
        try self.generateGenericFacts(node, facts, confidence);
    }
    
    fn generateGenericFacts(
        self: *FactGenerator,
        node: ASTNode,
        facts: *std.ArrayList(Fact),
        confidence: f32,
    ) !void {
        // Convert NodeType to NodeKind for predicate
        const node_kind: @import("../foundation/types/predicate.zig").NodeKind = switch (node.node_type) {
            .terminal => .terminal,
            .rule => .rule,
            .list => .list,
            .optional => .optional,
            .error_recovery => .error_recovery,
        };
        
        // Generic AST node fact
        try facts.append(Fact{
            .id = self.nextId(),
            .subject = Span.init(node.start_position, node.end_position),
            .predicate = .{ .is_node = node_kind },
            .object = Value{ .string = @tagName(node.node_type) },
            .confidence = confidence * 0.8, // Lower confidence for unknown nodes
            .generation = self.generation,
        });
    }
    
    // ========================================================================
    // Helper Methods
    // ========================================================================
    
    /// Generate next unique fact ID
    fn nextId(self: *FactGenerator) FactId {
        const id = self.next_fact_id;
        self.next_fact_id += 1;
        return id;
    }
    
    /// Calculate basic complexity metric for a node
    fn calculateComplexity(self: *FactGenerator, node: ASTNode) u32 {
        _ = self;
        
        var complexity: u32 = 1; // Base complexity
        
        // Add complexity based on number of children and rule names
        complexity += @as(u32, @intCast(node.children.len));
        
        for (node.children) |child| {
            if (std.mem.indexOf(u8, child.rule_name, "if") != null or
                std.mem.indexOf(u8, child.rule_name, "while") != null or
                std.mem.indexOf(u8, child.rule_name, "for") != null) {
                complexity += 2;
            }
        }
        
        return complexity;
    }
    
    // ========================================================================
    // Statistics and Performance Monitoring
    // ========================================================================
    
    pub fn getFactsGenerated(self: FactGenerator) u64 {
        return self.stats.facts_generated;
    }
    
    pub fn resetStats(self: *FactGenerator) void {
        self.stats = FactGeneratorStats{};
    }
    
    pub fn getStats(self: FactGenerator) FactGeneratorStats {
        return self.stats;
    }
};

/// Statistics for monitoring fact generation performance
pub const FactGeneratorStats = struct {
    facts_generated: u64 = 0,
    conversions_performed: u64 = 0,
    total_conversion_time_ns: u64 = 0,
    
    pub fn averageConversionTime(self: FactGeneratorStats) f64 {
        if (self.conversions_performed == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_conversion_time_ns)) / @as(f64, @floatFromInt(self.conversions_performed));
    }
    
    pub fn averageFactsPerConversion(self: FactGeneratorStats) f64 {
        if (self.conversions_performed == 0) return 0.0;
        return @as(f64, @floatFromInt(self.facts_generated)) / @as(f64, @floatFromInt(self.conversions_performed));
    }
    
    pub fn format(
        self: FactGeneratorStats,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        
        try writer.print("FactGeneratorStats{{ facts: {}, conversions: {}, avg_time: {d:.1}μs, facts_per_conversion: {d:.1} }}", .{
            self.facts_generated,
            self.conversions_performed,
            self.averageConversionTime() / 1000.0,
            self.averageFactsPerConversion(),
        });
    }
};